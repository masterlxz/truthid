import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';
import 'package:truthid_sdk/src/client.dart';
import 'package:truthid_sdk/src/contracts.dart';
import 'package:truthid_sdk/src/types.dart';

import 'fake_rpc_server.dart';

/// Encodes a raw `0x...` eth_call result the same way a real node would —
/// reuses the function's own `outputs` type metadata so the fixture is
/// guaranteed to match what `decodeReturnValues` expects.
String encodeResult(ContractFunction function, List<dynamic> values) {
  final tupleType = TupleType(function.outputs.map((p) => p.type).toList());
  final sink = LengthTrackingByteSink();
  tupleType.encode(values, sink);
  return '0x${sink.asBytes().map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

void main() {
  final deviceContract = DeployedContract(
    ContractAbi.fromJson(deviceRegistryAbi, 'DeviceRegistry'),
    EthereumAddress.fromHex(deviceRegistryAddresses[Network.baseSepolia]!),
  );

  final signerKey = EthPrivateKey.createRandom(Random.secure());
  final deviceAddress = signerKey.address.hexEip55;

  AuthChallenge makeChallenge({int? issuedAt}) => AuthChallenge(
        nonce: 'nonce-1',
        issuedAt: issuedAt ?? DateTime.now().millisecondsSinceEpoch,
        origin: 'https://example.com',
      );

  String signChallenge(AuthChallenge challenge) {
    final message = jsonEncode(challenge.toJson());
    final signature = signerKey.signPersonalMessageToUint8List(
      Uint8List.fromList(utf8.encode(message)),
    );
    return bytesToHex(signature, include0x: true);
  }

  group('createChallenge', () {
    test('returns the expected shape', () {
      final client = TruthIDClient(network: Network.baseSepolia);
      final challenge = client.createChallenge('https://example.com');
      expect(challenge.type, 'challenge');
      expect(challenge.origin, 'https://example.com');
      expect(challenge.nonce, isNotEmpty);
    });

    test('generates a different nonce every call', () {
      final client = TruthIDClient(network: Network.baseSepolia);
      final a = client.createChallenge('https://example.com');
      final b = client.createChallenge('https://example.com');
      expect(a.nonce, isNot(b.nonce));
    });
  });

  group('verifyAuthResponse', () {
    test('rejects when the user declined', () async {
      final client = TruthIDClient(network: Network.baseSepolia);
      final challenge = makeChallenge();
      final result = await client.verifyAuthResponse(
        challenge,
        AuthResponse(
          approved: false,
          nonce: challenge.nonce,
          signature: '0x',
          deviceAddress: deviceAddress,
        ),
      );
      expect(result.valid, isFalse);
      expect(result.reason, 'User rejected the login request');
    });

    test('rejects an expired challenge', () async {
      final client = TruthIDClient(network: Network.baseSepolia);
      final challenge = makeChallenge(
        issuedAt: DateTime.now().millisecondsSinceEpoch - 60000,
      );
      final result = await client.verifyAuthResponse(
        challenge,
        AuthResponse(
          approved: true,
          nonce: challenge.nonce,
          signature: '0x',
          deviceAddress: deviceAddress,
        ),
        ttlMs: 30000,
      );
      expect(result.valid, isFalse);
      expect(result.reason, 'Challenge expired');
    });

    test('rejects a nonce mismatch', () async {
      final client = TruthIDClient(network: Network.baseSepolia);
      final challenge = makeChallenge();
      final result = await client.verifyAuthResponse(
        challenge,
        AuthResponse(
          approved: true,
          nonce: 'different-nonce',
          signature: '0x',
          deviceAddress: deviceAddress,
        ),
      );
      expect(result.valid, isFalse);
      expect(result.reason, 'Nonce mismatch');
    });

    test('rejects a malformed signature', () async {
      final client = TruthIDClient(network: Network.baseSepolia);
      final challenge = makeChallenge();
      final result = await client.verifyAuthResponse(
        challenge,
        AuthResponse(
          approved: true,
          nonce: challenge.nonce,
          signature: '0xnotasignature',
          deviceAddress: deviceAddress,
        ),
      );
      expect(result.valid, isFalse);
      expect(result.reason, 'Invalid signature format');
    });

    test('rejects a signature that recovers to a different address', () async {
      final client = TruthIDClient(network: Network.baseSepolia);
      final challenge = makeChallenge();
      final otherKey = EthPrivateKey.createRandom(Random.secure());
      final message = jsonEncode(challenge.toJson());
      final signature = otherKey.signPersonalMessageToUint8List(
        Uint8List.fromList(utf8.encode(message)),
      );
      final result = await client.verifyAuthResponse(
        challenge,
        AuthResponse(
          approved: true,
          nonce: challenge.nonce,
          signature: bytesToHex(signature, include0x: true),
          deviceAddress: deviceAddress, // claims to be signerKey, signed with otherKey
        ),
      );
      expect(result.valid, isFalse);
      expect(result.reason, 'Signature does not match device address');
    });

    test('rejects an inactive device', () async {
      final server = await FakeRpcServer.start();
      addTearDown(server.close);
      final client = TruthIDClient(network: Network.baseSepolia, rpcUrl: server.url);
      final challenge = makeChallenge();

      server.enqueueResult(
        encodeResult(deviceContract.function('isDeviceActive'), [false]),
      );

      final result = await client.verifyAuthResponse(
        challenge,
        AuthResponse(
          approved: true,
          nonce: challenge.nonce,
          signature: signChallenge(challenge),
          deviceAddress: deviceAddress,
        ),
      );
      expect(result.valid, isFalse);
      expect(result.reason, 'Device is not active or has been revoked');
    });

    test('succeeds and returns the identityId for a valid, active device', () async {
      final server = await FakeRpcServer.start();
      addTearDown(server.close);
      final client = TruthIDClient(network: Network.baseSepolia, rpcUrl: server.url);
      final challenge = makeChallenge();

      server.enqueueResult(
        encodeResult(deviceContract.function('isDeviceActive'), [true]),
      );
      server.enqueueResult(
        encodeResult(deviceContract.function('getDevice'), [
          [
            BigInt.from(42),
            signerKey.address,
            '',
            BigInt.zero,
            false,
            true,
          ],
        ]),
      );

      final result = await client.verifyAuthResponse(
        challenge,
        AuthResponse(
          approved: true,
          nonce: challenge.nonce,
          signature: signChallenge(challenge),
          deviceAddress: deviceAddress,
        ),
      );
      expect(result.valid, isTrue);
      expect(result.identityId, BigInt.from(42));
      expect(result.deviceAddress, deviceAddress);
    });
  });
}

