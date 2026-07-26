import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/device_key_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorageChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  tearDown(() {
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, null);
  });

  test(
      'falha transiente na primeira leitura do secure storage não fica presa '
      'pra sempre — uma chamada seguinte consegue tentar de novo e ter '
      'sucesso (M4, achado do /code-review high: o Future rejeitado ficava '
      'cacheado no campo estático pra sempre)', () async {
    var readCalls = 0;
    TestWidgetsFlutterBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorageChannel, (call) async {
      switch (call.method) {
        case 'read':
          readCalls++;
          if (readCalls == 1) {
            throw PlatformException(
              code: 'transient_failure',
              message: 'simulated secure storage hiccup',
            );
          }
          return null; // sem chave gravada ainda — cai no caminho de criar
        case 'write':
          return null;
        default:
          return null;
      }
    });

    final service = DeviceKeyService();

    await expectLater(
      service.getDeviceAddress(),
      throwsA(isA<PlatformException>()),
    );

    final address = await service.getDeviceAddress();
    expect(address, startsWith('0x'));
  });
}
