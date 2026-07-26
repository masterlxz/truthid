import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

import 'contracts.dart';
import 'signature_recovery.dart';
import 'smart_account.dart' as smart_account;
import 'types.dart';

const _rpcUrls = {
  Network.baseSepolia: 'https://sepolia.base.org',
  Network.baseMainnet: 'https://mainnet.base.org',
};

/// The verifier role — same as the TypeScript/Python/Ruby SDKs: create a
/// login challenge, verify the signed response received from the phone.
/// For a backend written in Dart. No TruthID-operated server involved.
class TruthIDClient {
  final Network network;
  final String rpcUrl;
  final DeployedContract _deviceContract;
  final DeployedContract _sessionContract;

  TruthIDClient({required this.network, String? rpcUrl})
      : rpcUrl = rpcUrl ?? _rpcUrls[network]!,
        _deviceContract = DeployedContract(
          ContractAbi.fromJson(deviceRegistryAbi, 'DeviceRegistry'),
          EthereumAddress.fromHex(deviceRegistryAddresses[network]!),
        ),
        _sessionContract = DeployedContract(
          ContractAbi.fromJson(sessionRegistryAbi, 'SessionRegistry'),
          EthereumAddress.fromHex(sessionRegistryAddresses[network]!),
        );

  /// Creates a challenge in the exact format the mobile expects and signs.
  AuthChallenge createChallenge(String origin) {
    return AuthChallenge(
      nonce: _randomUuid(),
      issuedAt: DateTime.now().millisecondsSinceEpoch,
      origin: origin,
    );
  }

  /// Verifies the login response received from the mobile. Runs the same 6
  /// checks, in the same order, as the TypeScript/Python/Ruby SDKs.
  Future<VerifyAuthResult> verifyAuthResponse(
    AuthChallenge challenge,
    AuthResponse response, {
    int ttlMs = 30000,
  }) async {
    // 1. User explicitly rejected
    if (!response.approved) {
      return const VerifyAuthResult(
        valid: false,
        reason: 'User rejected the login request',
      );
    }

    // 2. Challenge expired (time-based replay protection)
    if (DateTime.now().millisecondsSinceEpoch - challenge.issuedAt > ttlMs) {
      return const VerifyAuthResult(valid: false, reason: 'Challenge expired');
    }

    // 3. Response nonce must match the challenge nonce (content-based replay protection)
    if (challenge.nonce != response.nonce) {
      return const VerifyAuthResult(valid: false, reason: 'Nonce mismatch');
    }

    // 4. Verify the cryptographic signature. The mobile signed
    // jsonEncode(challenge) with the Ethereum personal_sign prefix.
    final message = jsonEncode(challenge.toJson());
    String signer;
    try {
      signer = recoverPersonalSignatureAddress(message, response.signature);
    } catch (_) {
      return const VerifyAuthResult(
        valid: false,
        reason: 'Invalid signature format',
      );
    }

    if (signer.toLowerCase() != response.deviceAddress.toLowerCase()) {
      return const VerifyAuthResult(
        valid: false,
        reason: 'Signature does not match device address',
      );
    }

    // 5. Check on-chain whether the device is still active (not revoked)
    final deviceAddress = EthereumAddress.fromHex(response.deviceAddress);
    final isActive = await _ethCall(
      _deviceContract,
      'isDeviceActive',
      [deviceAddress],
    );
    if (!(isActive[0] as bool)) {
      return const VerifyAuthResult(
        valid: false,
        reason: 'Device is not active or has been revoked',
      );
    }

    // 6. Fetch the identityId associated with this device
    final device = await _ethCall(_deviceContract, 'getDevice', [deviceAddress]);
    final identityId = device[0][0] as BigInt;

    return VerifyAuthResult(
      valid: true,
      identityId: identityId,
      deviceAddress: response.deviceAddress,
    );
  }

  /// Reads a session's full data, or null if it was never created. getSession
  /// reverts on-chain when the hash is unknown — that revert is the only way
  /// this call can fail against a live RPC, so any error here is treated as
  /// "doesn't exist yet" rather than propagated.
  Future<List<dynamic>?> _readSession(Uint8List hash) async {
    try {
      final session = await _ethCall(_sessionContract, 'getSession', [hash]);
      final tuple = session[0] as List<dynamic>;
      return (tuple[4] as bool) ? tuple : null;
    } catch (_) {
      return null;
    }
  }

  /// Checks whether a session exists and has not been revoked.
  Future<SessionInfo> verifySession(String hash) async {
    final hashBytes = hexToBytes(hash);
    final session = await _readSession(hashBytes);
    if (session == null) {
      return const SessionInfo(exists: false, revoked: false);
    }

    final revoked = await _ethCall(_sessionContract, 'isSessionRevoked', [hashBytes]);

    return SessionInfo(
      exists: true,
      revoked: revoked[0] as bool,
      identityId: session[0] as BigInt,
      devicePubKey: (session[1] as EthereumAddress).hexEip55,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (session[2] as BigInt).toInt() * 1000,
      ),
    );
  }

  /// Predicts the smart account (controller) address for a given owner key
  /// via CREATE2, before the account is ever deployed on-chain — pure local
  /// computation, no RPC call needed. See smart_account.dart for the algorithm.
  String computeSmartAccountAddress(String ledgerAddress, {BigInt? index}) {
    return smart_account.computeSmartAccountAddress(
      ledgerAddress,
      network,
      index: index,
    );
  }

  /// Checks the status of a device on-chain.
  Future<DeviceStatus> checkDeviceStatus(String devicePubKey) async {
    final device = await _ethCall(
      _deviceContract,
      'getDevice',
      [EthereumAddress.fromHex(devicePubKey)],
    );
    final tuple = device[0] as List<dynamic>;
    if (!(tuple[5] as bool)) {
      return const DeviceStatus(exists: false, active: false);
    }

    return DeviceStatus(
      exists: true,
      active: !(tuple[4] as bool),
      label: tuple[2] as String,
      identityId: tuple[0] as BigInt,
      addedAt: DateTime.fromMillisecondsSinceEpoch(
        (tuple[3] as BigInt).toInt() * 1000,
      ),
    );
  }

  Future<List<dynamic>> _ethCall(
    DeployedContract contract,
    String functionName,
    List<dynamic> params,
  ) async {
    final function = contract.function(functionName);
    final callData = function.encodeCall(params);
    final callDataHex =
        '0x${callData.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

    final result = await _rpcCall('eth_call', [
      {'to': contract.address.hexEip55, 'data': callDataHex},
      'latest',
    ]);
    final resultHex = (result as String).substring(2);
    return function.decodeReturnValues(resultHex);
  }

  Future<dynamic> _rpcCall(String method, List<dynamic> params) async {
    final client = HttpClient();
    try {
      final request = await client.postUrl(Uri.parse(rpcUrl));
      request.headers.set('content-type', 'application/json');
      request.write(jsonEncode({
        'jsonrpc': '2.0',
        'method': method,
        'params': params,
        'id': 1,
      }));

      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['error'] != null) {
        throw Exception('RPC error: ${decoded['error']}');
      }
      return decoded['result'];
    } finally {
      client.close();
    }
  }
}

final _uuidRandom = Random.secure();

String _randomUuid() {
  final bytes = Uint8List(16);
  for (var i = 0; i < 16; i++) {
    bytes[i] = _uuidRandom.nextInt(256);
  }
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 1
  String hex(int start, int end) =>
      bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
