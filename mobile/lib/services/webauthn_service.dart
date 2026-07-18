import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:elliptic/elliptic.dart' as ec;
import 'package:pointycastle/asn1.dart' as pc;
import 'package:pointycastle/export.dart' as pc;

import 'cbor_util.dart' as cbor;

/// Virtual WebAuthn authenticator — espelho funcional de
/// `desktop/src/utils/webauthn.ts`. Gera credenciais P-256/ES256 e assina
/// asserções, seguindo o mesmo princípio do TOTP (ver totp_service.dart):
/// lógica pura, sem UI, reimplementada de forma independente do TS, nunca
/// via ponte/FFI compartilhado.
///
/// Escopo desta fase: só a cerimônia criptográfica em si. Não há
/// interceptação de `navigator.credentials` num site real.

final ec.Curve _p256Curve = ec.getP256();
final pc.ECDomainParameters _pcP256Domain = pc.ECDomainParameters('secp256r1');

final Uint8List _aaguid = Uint8List(16); // zeros — sem attestation de hardware real nesta fase.

String toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List fromHex(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String base64UrlEncodeNoPad(List<int> bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

Uint8List _randomBytes(int length) {
  final random = Random.secure();
  return Uint8List.fromList(List<int>.generate(length, (_) => random.nextInt(256)));
}

/// Encodes a P-256 public key as a COSE_Key CBOR map, per WebAuthn §6.5.1.1:
/// {1: 2 (kty: EC2), 3: -7 (alg: ES256), -1: 1 (crv: P-256), -2: x, -3: y}.
Uint8List encodeCoseP256PublicKey(List<int> x, List<int> y) {
  return cbor.encodeMap([
    (cbor.encodeInt(1), cbor.encodeInt(2)),
    (cbor.encodeInt(3), cbor.encodeInt(-7)),
    (cbor.encodeInt(-1), cbor.encodeInt(1)),
    (cbor.encodeInt(-2), cbor.encodeBytes(x)),
    (cbor.encodeInt(-3), cbor.encodeBytes(y)),
  ]);
}

class AttestedCredential {
  final Uint8List credentialId;
  final Uint8List coseP256PublicKey;

  const AttestedCredential({required this.credentialId, required this.coseP256PublicKey});
}

/// Builds the WebAuthn `authenticatorData` byte structure (§6.1):
/// rpIdHash(32) || flags(1) || signCount(4, BE) || [attestedCredentialData].
Uint8List buildAuthenticatorData({
  required String rpId,
  required int signCount,
  AttestedCredential? attestedCredential,
}) {
  final rpIdHash = crypto.sha256.convert(utf8.encode(rpId)).bytes;
  final flags = attestedCredential != null ? 0x45 : 0x05;
  final signCountBytes = Uint8List(4)..buffer.asByteData().setUint32(0, signCount, Endian.big);

  final out = BytesBuilder();
  out.add(rpIdHash);
  out.addByte(flags);
  out.add(signCountBytes);

  if (attestedCredential != null) {
    final credentialId = attestedCredential.credentialId;
    final credentialIdLen = Uint8List(2)
      ..buffer.asByteData().setUint16(0, credentialId.length, Endian.big);
    out.add(_aaguid);
    out.add(credentialIdLen);
    out.add(credentialId);
    out.add(attestedCredential.coseP256PublicKey);
  }

  return out.toBytes();
}

/// Builds a "none"-format WebAuthn attestationObject CBOR map (§6.5.4).
Uint8List buildAttestationObject(Uint8List authData) {
  return cbor.encodeMap([
    (cbor.encodeText('fmt'), cbor.encodeText('none')),
    (cbor.encodeText('attStmt'), cbor.encodeMap(const [])),
    (cbor.encodeText('authData'), cbor.encodeBytes(authData)),
  ]);
}

class CreatedPasskey {
  final String privateKeyHex;
  final String credentialIdB64;
  final String userHandleB64;
  final String clientDataJSON;
  final Uint8List attestationObject;
  final int signCount;
  final int createdAt;

  const CreatedPasskey({
    required this.privateKeyHex,
    required this.credentialIdB64,
    required this.userHandleB64,
    required this.clientDataJSON,
    required this.attestationObject,
    required this.signCount,
    required this.createdAt,
  });
}

/// Derives the (x, y) public key coordinates for a given hex-encoded P-256
/// private key scalar. Exposed (not just internal) so callers — and the
/// fixed-vector cross-check test — can derive the public key for a specific
/// known private key, not just a freshly generated one (see [createPasskey]).
(Uint8List, Uint8List) publicKeyXYFromPrivateKeyHex(String privateKeyHex) {
  final publicKey = ec.PrivateKey.fromHex(_p256Curve, privateKeyHex).publicKey;
  return (_bigIntToFixedBytes(publicKey.X, 32), _bigIntToFixedBytes(publicKey.Y, 32));
}

/// Runs a full (local, self-contained) WebAuthn registration ceremony: gera
/// um par de chaves P-256 novo, monta authenticatorData + attestationObject
/// "none". Não há relying party real nesta fase.
CreatedPasskey createPasskey({
  required String rpId,
  required Uint8List challenge,
  required String origin,
}) {
  final privateKey = _p256Curve.generatePrivateKey();
  final (x, y) = publicKeyXYFromPrivateKeyHex(privateKey.toHex());

  final credentialId = _randomBytes(16);
  final userHandle = _randomBytes(16);
  final coseP256PublicKey = encodeCoseP256PublicKey(x, y);

  final authData = buildAuthenticatorData(
    rpId: rpId,
    signCount: 0,
    attestedCredential: AttestedCredential(
      credentialId: credentialId,
      coseP256PublicKey: coseP256PublicKey,
    ),
  );
  final attestationObject = buildAttestationObject(authData);

  final clientDataJSON = jsonEncode({
    'type': 'webauthn.create',
    'challenge': base64UrlEncodeNoPad(challenge),
    'origin': origin,
  });

  return CreatedPasskey(
    privateKeyHex: privateKey.toHex(),
    credentialIdB64: base64UrlEncodeNoPad(credentialId),
    userHandleB64: base64UrlEncodeNoPad(userHandle),
    clientDataJSON: clientDataJSON,
    attestationObject: attestationObject,
    signCount: 0,
    createdAt: DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
  );
}

class SignedAssertion {
  final Uint8List authenticatorData;
  final String clientDataJSON;
  final Uint8List signatureDer;
  final int newSignCount;

  const SignedAssertion({
    required this.authenticatorData,
    required this.clientDataJSON,
    required this.signatureDer,
    required this.newSignCount,
  });
}

/// Runs a full (local, self-contained) WebAuthn authentication ceremony:
/// builds authenticatorData (no attested credential this time) + signs
/// `authenticatorData || SHA-256(clientDataJSON)` with ES256 (deterministic,
/// RFC 6979 — via `package:pointycastle`, since `package:cryptography`'s pure
/// Dart ECDSA backend throws UnimplementedError with no native plugin
/// registered), per §6.3.3.
SignedAssertion signAssertion({
  required String privateKeyHex,
  required String rpId,
  required int signCount,
  required Uint8List challenge,
  required String origin,
}) {
  final newSignCount = signCount + 1;
  final authenticatorData = buildAuthenticatorData(rpId: rpId, signCount: newSignCount);

  final clientDataJSON = jsonEncode({
    'type': 'webauthn.get',
    'challenge': base64UrlEncodeNoPad(challenge),
    'origin': origin,
  });
  final clientDataHash = crypto.sha256.convert(utf8.encode(clientDataJSON)).bytes;
  final message = Uint8List.fromList([...authenticatorData, ...clientDataHash]);

  final d = BigInt.parse(privateKeyHex, radix: 16);
  final signer = pc.NormalizedECDSASigner(
    pc.Signer('SHA-256/DET-ECDSA') as pc.ECDSASigner,
  );
  signer.init(true, pc.PrivateKeyParameter(pc.ECPrivateKey(d, _pcP256Domain)));
  final signature = signer.generateSignature(message) as pc.ECSignature;

  final signatureDer = pc.ASN1Sequence(elements: [
    pc.ASN1Integer(signature.r),
    pc.ASN1Integer(signature.s),
  ]).encode();

  return SignedAssertion(
    authenticatorData: authenticatorData,
    clientDataJSON: clientDataJSON,
    signatureDer: signatureDer,
    newSignCount: newSignCount,
  );
}

Uint8List _bigIntToFixedBytes(BigInt value, int length) {
  final hex = value.toRadixString(16).padLeft(length * 2, '0');
  return fromHex(hex);
}
