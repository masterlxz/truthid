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
}
