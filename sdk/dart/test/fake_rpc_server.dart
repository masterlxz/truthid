import 'dart:convert';
import 'dart:io';

/// Minimal fake JSON-RPC server for testing `TruthIDClient` without a real
/// node — replies to `eth_call` with a queue of pre-encoded raw hex results,
/// one per expected call, in order.
class FakeRpcServer {
  final HttpServer _server;
  final List<String> _responseQueue = [];

  FakeRpcServer._(this._server) {
    _server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final resultHex = _responseQueue.removeAt(0);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'jsonrpc': '2.0',
        'id': decoded['id'],
        'result': resultHex,
      }));
      await request.response.close();
    });
  }

  static Future<FakeRpcServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeRpcServer._(server);
  }

  String get url => 'http://127.0.0.1:${_server.port}';

  /// Queues the raw `0x...` hex that the next `eth_call` should return.
  void enqueueResult(String resultHex) => _responseQueue.add(resultHex);

  Future<void> close() => _server.close(force: true);
}
