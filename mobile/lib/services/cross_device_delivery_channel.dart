import 'dart:convert';
import 'dart:typed_data';

import 'ecies_service.dart';
import 'ipfs_pin_client.dart';
import 'pinning_provider_service.dart';
import 'remote_signer_lan_server.dart';
import 'result_delivery_channel.dart';

/// Transporte cross-device (QR) — cifra o `result` com ECIES pra chave
/// pública efêmera do requisitante e entrega via dois canais em paralelo:
/// um servidor LAN efêmero (decide `sent`/`timeout`) e um dead-drop
/// IPFS/IPNS best-effort (nunca decide o status, só é registrado se der
/// certo). Corpo movido de `_deliver()`/`_publishDeadDrop()`, que eram
/// idênticos entre `SignMessageApprovalScreen` e `SignRequestApprovalScreen`
/// — mesmo comportamento de sempre, zero mudança.
class CrossDeviceDeliveryChannel implements ResultDeliveryChannel {
  final String requesterPubKeyHex;
  final EciesService _ecies;
  final RemoteSignerLanServer _lanServer;
  final IpfsPinClient _ipfsPinClient;
  final PinningProviderService _pinningProviderService;

  CrossDeviceDeliveryChannel({
    required this.requesterPubKeyHex,
    required EciesService ecies,
    required RemoteSignerLanServer lanServer,
    required IpfsPinClient ipfsPinClient,
    required PinningProviderService pinningProviderService,
  })  : _ecies = ecies,
        _lanServer = lanServer,
        _ipfsPinClient = ipfsPinClient,
        _pinningProviderService = pinningProviderService;

  @override
  Future<DeliveryResult> deliver({
    required Map<String, dynamic> result,
    required String sessionId,
    required DateTime expiresAt,
  }) async {
    final plaintext = Uint8List.fromList(utf8.encode(jsonEncode(result)));
    final encryptedBlob = await _ecies.encrypt(plaintext, requesterPubKeyHex);

    // Mesma decisão travada da 13.9: o dead-drop corre em paralelo com o
    // LAN, nunca como fallback sequencial, e nunca lança — uma falha (sem
    // provider Kubo configurado, Kubo fora do ar) não pode derrubar o
    // transporte LAN, que já funciona sozinho.
    String? deadDropIpnsName;
    String? deadDropError;
    final deadDropFuture = _publishDeadDrop(sessionId, encryptedBlob).then(
      (name) => deadDropIpnsName = name,
      onError: (Object e) => deadDropError = '$e',
    );

    final served = await _lanServer.serveOnce(
      encryptedBlob: encryptedBlob,
      sessionId: sessionId,
      expiresAt: expiresAt,
    );
    await deadDropFuture;

    return DeliveryResult(
      outcome: served ? DeliveryOutcome.sent : DeliveryOutcome.timeout,
      deadDropIpnsName: deadDropIpnsName,
      deadDropError: deadDropError,
    );
  }

  Future<String?> _publishDeadDrop(
    String sessionId,
    Uint8List encryptedBlob,
  ) async {
    final providers = await _pinningProviderService.load();
    return _ipfsPinClient.publishDeadDrop(sessionId, encryptedBlob, providers);
  }
}
