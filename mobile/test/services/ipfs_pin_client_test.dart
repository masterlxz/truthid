import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/ipfs_pin_client.dart';

void main() {
  group('IpfsPinClient', () {
    test('lança quando nenhum provider Kubo está configurado', () async {
      final client = IpfsPinClient();
      final providers = [
        const PinningProvider(name: 'p', kind: 'psa', endpointUrl: 'http://x'),
      ];

      expect(
        () => client.pinVault(Uint8List.fromList([1, 2, 3]), providers),
        throwsA(isA<Exception>()),
      );
    });

    test('sobe pro Kubo e retorna o CID + hash do conteúdo', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({
          'Name': 'vault.enc',
          'Hash': 'QmTestCid123',
          'Size': '4',
        }));
        await request.response.close();
      });

      final client = IpfsPinClient();
      final providers = [
        PinningProvider(
          name: 'local-kubo',
          kind: 'kubo',
          endpointUrl: 'http://${server.address.address}:${server.port}',
        ),
      ];
      final content = Uint8List.fromList([1, 2, 3, 4]);

      final result = await client.pinVault(content, providers);

      expect(result.cid, 'QmTestCid123');
      expect(result.contentHash, startsWith('0x'));
      expect(result.contentHash.length, 2 + 64);
      expect(result.providersOk, contains('local-kubo'));
      expect(result.providersFailed, isEmpty);

      await server.close(force: true);
    });

    test('pina o CID nos providers PSA depois do upload Kubo', () async {
      final kuboServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      kuboServer.listen((request) async {
        request.response.statusCode = 200;
        request.response.write(jsonEncode({'Hash': 'QmAbc'}));
        await request.response.close();
      });

      String? psaBody;
      String? psaAuthHeader;
      final psaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      psaServer.listen((request) async {
        psaAuthHeader = request.headers.value('authorization');
        psaBody = await utf8.decoder.bind(request).join();
        request.response.statusCode = 202;
        await request.response.close();
      });

      final client = IpfsPinClient();
      final providers = [
        PinningProvider(
          name: 'local-kubo',
          kind: 'kubo',
          endpointUrl: 'http://${kuboServer.address.address}:${kuboServer.port}',
        ),
        PinningProvider(
          name: 'pinata',
          kind: 'psa',
          endpointUrl: 'http://${psaServer.address.address}:${psaServer.port}',
          apiKey: 'secret-key',
        ),
      ];

      final result = await client.pinVault(Uint8List.fromList([9, 9]), providers);

      expect(result.providersOk, containsAll(['local-kubo', 'pinata']));
      expect(psaAuthHeader, 'Bearer secret-key');
      expect(jsonDecode(psaBody!)['cid'], 'QmAbc');

      await kuboServer.close(force: true);
      await psaServer.close(force: true);
    });

    test('trata PSA 409 (já fixado) como sucesso', () async {
      final kuboServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      kuboServer.listen((request) async {
        request.response.write(jsonEncode({'Hash': 'QmAbc'}));
        await request.response.close();
      });
      final psaServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      psaServer.listen((request) async {
        request.response.statusCode = 409;
        await request.response.close();
      });

      final client = IpfsPinClient();
      final result = await client.pinVault(Uint8List.fromList([1]), [
        PinningProvider(
          name: 'kubo',
          kind: 'kubo',
          endpointUrl: 'http://${kuboServer.address.address}:${kuboServer.port}',
        ),
        PinningProvider(
          name: 'psa',
          kind: 'psa',
          endpointUrl: 'http://${psaServer.address.address}:${psaServer.port}',
        ),
      ]);

      expect(result.providersOk, containsAll(['kubo', 'psa']));

      await kuboServer.close(force: true);
      await psaServer.close(force: true);
    });

    test('lança quando todos os providers Kubo falham', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });

      final client = IpfsPinClient();
      final providers = [
        PinningProvider(
          name: 'quebrado',
          kind: 'kubo',
          endpointUrl: 'http://${server.address.address}:${server.port}',
        ),
      ];

      await expectLater(
        client.pinVault(Uint8List.fromList([1]), providers),
        throwsA(isA<Exception>()),
      );

      await server.close(force: true);
    });

    test('contentHash é determinístico pro mesmo conteúdo', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.write(jsonEncode({'Hash': 'Qm1'}));
        await request.response.close();
      });

      final client = IpfsPinClient();
      final providers = [
        PinningProvider(
          name: 'kubo',
          kind: 'kubo',
          endpointUrl: 'http://${server.address.address}:${server.port}',
        ),
      ];
      final content = Uint8List.fromList(utf8.encode('same content'));

      final r1 = await client.pinVault(content, providers);
      final r2 = await client.pinVault(content, providers);

      expect(r1.contentHash, r2.contentHash);

      await server.close(force: true);
    });
  });
}
