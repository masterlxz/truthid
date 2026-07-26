/// Which network to read contracts from.
enum Network {
  baseSepolia('base-sepolia'),
  baseMainnet('base-mainnet');

  const Network(this.id);

  /// The `"base-sepolia"`/`"base-mainnet"` string used as map key across all
  /// TruthID SDKs (TS/Python/Ruby use the same strings).
  final String id;
}

class TruthIDClientConfig {
  final Network network;
  final String? rpcUrl;

  const TruthIDClientConfig({required this.network, this.rpcUrl});
}

/// Exact format the mobile receives and signs.
class AuthChallenge {
  final String type;
  final String nonce;
  final int issuedAt; // Unix timestamp in ms
  final String origin;

  const AuthChallenge({
    this.type = 'challenge',
    required this.nonce,
    required this.issuedAt,
    required this.origin,
  });

  /// Compact JSON (no spaces) — matches `JSON.stringify()`/`jsonEncode()` on
  /// the mobile side, which is what it actually signs.
  Map<String, dynamic> toJson() => {
        'type': type,
        'nonce': nonce,
        'issuedAt': issuedAt,
        'origin': origin,
      };
}

/// Response sent by the mobile after the user approves.
class AuthResponse {
  final bool approved;
  final String nonce;
  final String signature; // secp256k1 signature in hex ("0x...")
  final String deviceAddress; // Ethereum address derived from the device key
  // personal_sign over keccak256(nonce) — the mobile always sends this
  // alongside the login signature.
  final String? sessionSignature;

  const AuthResponse({
    required this.approved,
    required this.nonce,
    required this.signature,
    required this.deviceAddress,
    this.sessionSignature,
  });
}

class VerifyAuthResult {
  final bool valid;
  final BigInt? identityId;
  final String? deviceAddress;
  final String? reason;

  const VerifyAuthResult({
    required this.valid,
    this.identityId,
    this.deviceAddress,
    this.reason,
  });
}

class SessionInfo {
  final bool exists;
  final bool revoked;
  final BigInt? identityId;
  final String? devicePubKey;
  final DateTime? createdAt;

  const SessionInfo({
    required this.exists,
    required this.revoked,
    this.identityId,
    this.devicePubKey,
    this.createdAt,
  });
}

class DeviceStatus {
  final bool exists;
  final bool active;
  final String? label;
  final BigInt? identityId;
  final DateTime? addedAt;

  const DeviceStatus({
    required this.exists,
    required this.active,
    this.label,
    this.identityId,
    this.addedAt,
  });
}
