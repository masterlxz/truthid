import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;

import 'package:truthid_mobile/services/deep_link_delivery_channel.dart';
import 'package:truthid_mobile/services/result_delivery_channel.dart';

void main() {
  final callbackBase = Uri.parse('someapp://truthid-result');

  test('monta a callback URI com sessionId + campos do result, e lança',
      () async {
    Uri? launched;
    LaunchMode? launchedMode;
    final channel = DeepLinkDeliveryChannel(
      callbackBaseUri: callbackBase,
      launch: (url, {LaunchMode? mode}) async {
        launched = url;
        launchedMode = mode;
        return true;
      },
    );

    final result = await channel.deliver(
      result: const {
        'status': 'executed',
        'userOpHash': '0xabc',
        'transactionHash': '0xdef',
      },
      sessionId: 'session-1',
      expiresAt: DateTime.now().add(const Duration(minutes: 3)),
    );

    expect(result.outcome, DeliveryOutcome.sent);
    // Sem transporte de rede — nunca há dead-drop no caminho deep link.
    expect(result.deadDropIpnsName, isNull);
    expect(result.deadDropError, isNull);

    expect(launched, isNotNull);
    expect(launched!.scheme, 'someapp');
    expect(launched!.host, 'truthid-result');
    expect(launched!.queryParameters['sessionId'], 'session-1');
    expect(launched!.queryParameters['status'], 'executed');
    expect(launched!.queryParameters['userOpHash'], '0xabc');
    expect(launched!.queryParameters['transactionHash'], '0xdef');
    expect(launchedMode, LaunchMode.externalApplication);
  });

  test('preserva query params já presentes na callback base', () async {
    Uri? launched;
    final channel = DeepLinkDeliveryChannel(
      callbackBaseUri: Uri.parse('someapp://truthid-result?requestId=42'),
      launch: (url, {LaunchMode? mode}) async {
        launched = url;
        return true;
      },
    );

    await channel.deliver(
      result: const {'status': 'rejected'},
      sessionId: 'session-2',
      expiresAt: DateTime.now().add(const Duration(minutes: 3)),
    );

    expect(launched!.queryParameters['requestId'], '42');
    expect(launched!.queryParameters['sessionId'], 'session-2');
    expect(launched!.queryParameters['status'], 'rejected');
  });

  test('launchUrl retornando false vira erro, não "sent" silencioso',
      () async {
    final channel = DeepLinkDeliveryChannel(
      callbackBaseUri: callbackBase,
      launch: (url, {LaunchMode? mode}) async => false,
    );

    expect(
      () => channel.deliver(
        result: const {'status': 'rejected'},
        sessionId: 'session-3',
        expiresAt: DateTime.now().add(const Duration(minutes: 3)),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
