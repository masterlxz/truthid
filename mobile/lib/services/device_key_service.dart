import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

class DeviceKeyService {
  static const _storage = FlutterSecureStorage();
  static const _storageKey = 'truthid_device_private_key';

  // Memoização estática (não por instância): cada tela cria seu próprio
  // DeviceKeyService(), e num install novo, duas telas podem chamar
  // _getOrCreateKey() quase ao mesmo tempo. Sem isso, cada chamada faz seu
  // próprio read-then-write — as duas veem a storage vazia, cada uma gera
  // uma chave aleatória diferente, e quem escreve por último "vence",
  // deixando a outra tela com um endereço órfão em memória (já visto na
  // prática: Devices e Pair device mostrando endereços diferentes logo após
  // reinstalar o app). Compartilhar a mesma Future entre todas as instâncias
  // garante que só a primeira chamada gera/grava a chave; as demais esperam
  // o mesmo resultado.
  static Future<EthPrivateKey>? _keyFuture;

  Future<EthPrivateKey> _getOrCreateKey() {
    return _keyFuture ??= _loadOrCreateKey();
  }

  Future<EthPrivateKey> _loadOrCreateKey() async {
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

  // Retorna a chave pública no formato SEC1 não-comprimido (0x04 || X || Y,
  // 65 bytes) — o formato que ECIES (Rust/k256, ver
  // encrypt_vault_key_for_device) exige. `privateKeyToPublic()` do web3dart
  // devolve só X||Y (64 bytes, convenção do Ethereum pra derivar endereço via
  // keccak256), sem o prefixo. Sem prependar o 0x04, o lado Rust rejeitava
  // (só aceita exatamente 33 ou 65 bytes) — silenciosamente, já que quem
  // chama engole o erro — deixando a vault key nunca cifrada/entregue no
  // pareamento (achado depois de 2 pareamentos reais em Base Mainnet com
  // deviceVaultKeys vazio on-chain nos dois).
  Future<String> getDevicePublicKeyHex() async {
    final key = await _getOrCreateKey();
    final privBigInt = BigInt.parse(
      bytesToHex(key.privateKey, include0x: false),
      radix: 16,
    );
    final rawPubKey = privateKeyToPublic(privBigInt);
    final sec1PubKey = Uint8List.fromList([0x04, ...rawPubKey]);
    return bytesToHex(sec1PubKey, include0x: true);
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
