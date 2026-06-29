import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

class DeviceKeyService {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'truthid_device_private_key';

  Future<EthPrivateKey> _getOrCreateKey() async {
    final stored = await _storage.read(key: _storageKey);
    if (stored != null) {
      return EthPrivateKey.fromHex(stored);
    }

    final key = EthPrivateKey.createRandom(Random.secure());
    final keyHex = bytesToHex(key.privateKey, include0x: true);
    await _storage.write(key: _storageKey, value: keyHex);
    return key;
  }

  Future<Uint8List> getPrivateKeyBytes() async {
    final key = await _getOrCreateKey();
    return key.privateKey;
  }

  Future<String> getDeviceAddress() async {
    final key = await _getOrCreateKey();
    return key.address.hexEip55;
  }

  Future<String> signChallenge(String challengeJson) async {
    final key = await _getOrCreateKey();
    final messageBytes = Uint8List.fromList(utf8.encode(challengeJson));
    final signature = key.signPersonalMessageToUint8List(messageBytes);
    return bytesToHex(signature, include0x: true);
  }

  // Signs a 32-byte hash using Ethereum's personal_sign prefix for 32-byte messages.
  // This produces the (r, s, v) signature the SessionRegistry.createSession contract expects.
  Future<String> signHash(Uint8List hash32) async {
    final key = await _getOrCreateKey();
    final signature = key.signPersonalMessageToUint8List(hash32);
    return bytesToHex(signature, include0x: true);
  }
}
