import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:truthid_mobile/services/ipfs_gateway_client.dart';

void main() {
  group('IpfsGatewayClient', () {
    test('retorna os bytes quando o gateway responde 200', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      server.listen((request) async {
        request.response.statusCode = 200;
        request.response.add(bytes);
        await request.response.close();
      });

      final client = IpfsGatewayClient(
        gateways: ['http://${server.address.address}:${server.port}/ipfs/'],
      );

      final result = await client.fetch('cid123');
      expect(result, equals(bytes));

      await server.close(force: true);
    });

    test('cai pro segundo gateway quando o primeiro falha', () async {
      final badServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      badServer.listen((request) async {
        request.response.statusCode = 500;
        await request.response.close();
      });

      final goodServer =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final bytes = Uint8List.fromList([9, 9, 9]);
      goodServer.listen((request) async {
        request.response.statusCode = 200;
        request.response.add(bytes);
        await request.response.close();
      });

      final client = IpfsGatewayClient(gateways: [
        'http://${badServer.address.address}:${badServer.port}/ipfs/',
        'http://${goodServer.address.address}:${goodServer.port}/ipfs/',
      ]);

      final result = await client.fetch('cid123');
      expect(result, equals(bytes));

      await badServer.close(force: true);
      await goodServer.close(force: true);
    });

    test('lança quando todos os gateways falham', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.statusCode = 404;
        await request.response.close();
      });

      final client = IpfsGatewayClient(
        gateways: ['http://${server.address.address}:${server.port}/ipfs/'],
      );

      await expectLater(client.fetch('cid123'), throwsException);

      await server.close(force: true);
    });
  });
}
