import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Port block of the mobile app's `RemoteSignerLanServer` — distinct from
/// the vault-pairing read block (`47850-47854`) and the Desktop loopback
/// block (`47950-47954`). Cross-reference:
/// `mobile/lib/services/remote_signer_lan_server.dart::candidatePorts`.
const List<int> requesterCandidatePorts = [48050, 48051, 48052, 48053, 48054];

const int _defaultConcurrency = 50;
const Duration _defaultTimeout = Duration(milliseconds: 800);

// Prefixes of virtual/container interface names (Docker, libvirt,
// VirtualBox, VPN...) — never where the phone actually is. Without this
// filter, a sweep spends most of its time budget on these subnets (e.g.
// docker0 at 172.17.0.0/16, always present on a dev machine running Docker)
// before ever reaching the real Wi-Fi subnet — same filter as
// `extension/src/session/lanDiscovery.ts`.
const List<String> _virtualInterfacePrefixes = [
  'docker',
  'br-',
  'veth',
  'virbr',
  'vmnet',
  'vboxnet',
  'tun',
  'tap',
  'zt',
  'utun',
];

bool _isVirtualInterface(String name) =>
    _virtualInterfacePrefixes.any((prefix) => name.startsWith(prefix));

/// Local IPv4 addresses, excluding loopback and virtual/container interfaces.
Future<List<String>> localIpAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return interfaces
      .where((iface) => !_isVirtualInterface(iface.name))
      .expand((iface) => iface.addresses)
      .map((address) => address.address)
      .toList();
}

/// All hosts on the /24 that [localIp] belongs to (e.g. 192.168.1.1..254).
List<String> subnetHosts(String localIp) {
  final parts = localIp.split('.');
  if (parts.length != 4) return const [];
  final prefix = parts.sublist(0, 3).join('.');
  return List.generate(254, (i) => '$prefix.${i + 1}');
}

/// `GET /session/<sessionId>` on a host:port — mirrors
/// `RemoteSignerLanServer.serveOnce()` (Dart, mobile side), which replies
/// `{"blob": "<base64>"}` on success. Returns `null` on any failure or
/// non-200 status; never throws.
Future<Uint8List?> fetchSessionBlob(
  HttpClient client,
  String host,
  int port,
  String sessionId, {
  Duration timeout = _defaultTimeout,
}) async {
  try {
    final request = await client
        .getUrl(Uri.parse('http://$host:$port/session/$sessionId'))
        .timeout(timeout);
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>();
      return null;
    }
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    final blobBase64 = decoded['blob'] as String?;
    return blobBase64 == null ? null : base64Decode(blobBase64);
  } catch (_) {
    return null;
  }
}

/// `PUT /session/<sessionId>/content` on a host:port with [body] as the raw
/// payload — mirrors `RemoteSignerLanServer.receiveOnce()`, which replies
/// `200` (no body) as soon as it has read the whole request. Returns `true`
/// only on `200`; never throws.
Future<bool> putSessionContent(
  HttpClient client,
  String host,
  int port,
  String sessionId,
  Uint8List body, {
  Duration timeout = _defaultTimeout,
}) async {
  try {
    final request = await client
        .putUrl(Uri.parse('http://$host:$port/session/$sessionId/content'))
        .timeout(timeout);
    request.add(body);
    final response = await request.close().timeout(timeout);
    await response.drain<void>();
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

List<(String, int)> _buildTargets(List<String> localIps) {
  final seenHosts = <String>{};
  final targets = <(String, int)>[];
  for (final ip in localIps) {
    for (final host in subnetHosts(ip)) {
      if (!seenHosts.add(host)) continue;
      for (final port in requesterCandidatePorts) {
        targets.add((host, port));
      }
    }
  }
  return targets;
}

/// Sweeps the local /24(s) × [requesterCandidatePorts], in parallel batches,
/// for the first phone that answers `GET /session/<sessionId>` with a blob.
/// Exits as soon as one is found — does not wait for the whole sweep.
Future<Uint8List?> sweepLanForResult(
  String sessionId, {
  int concurrency = _defaultConcurrency,
  Duration timeout = _defaultTimeout,
}) async {
  final localIps = await localIpAddresses();
  if (localIps.isEmpty) return null;

  final targets = _buildTargets(localIps);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    for (var i = 0; i < targets.length; i += concurrency) {
      final batch = targets.skip(i).take(concurrency);
      final results = await Future.wait(batch.map(
        (t) => fetchSessionBlob(client, t.$1, t.$2, sessionId, timeout: timeout),
      ));
      for (final result in results) {
        if (result != null) return result;
      }
    }
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Sweeps the local /24(s) × [requesterCandidatePorts], in parallel batches,
/// pushing [body] via `PUT` to the first phone that accepts it. Same
/// strategy as [sweepLanForResult], inverted (push instead of pull, exits on
/// the first acceptance instead of the first content).
Future<bool> sweepLanToPush(
  String sessionId,
  Uint8List body, {
  int concurrency = _defaultConcurrency,
  Duration timeout = _defaultTimeout,
}) async {
  final localIps = await localIpAddresses();
  if (localIps.isEmpty) return false;

  final targets = _buildTargets(localIps);
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    for (var i = 0; i < targets.length; i += concurrency) {
      final batch = targets.skip(i).take(concurrency);
      final results = await Future.wait(batch.map(
        (t) => putSessionContent(client, t.$1, t.$2, sessionId, body, timeout: timeout),
      ));
      if (results.any((ok) => ok)) return true;
    }
    return false;
  } finally {
    client.close(force: true);
  }
}
