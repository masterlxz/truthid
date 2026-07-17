/// Abstrai "como entregar o resultado de uma aprovação (sign-message/
/// sign-request) de volta pro app requisitante" — as telas de aprovação
/// (`SignMessageApprovalScreen`/`SignRequestApprovalScreen`) montam o
/// `result` (status/assinatura/erro) do mesmo jeito sempre; só COMO ele
/// chega no requisitante muda conforme o transporte:
///   - QR/cross-device: `CrossDeviceDeliveryChannel` (cifra ECIES + LAN +
///     dead-drop IPFS/IPNS em paralelo — dois aparelhos, salto de rede não
///     confiável).
///   - Deep link/mesmo aparelho: `DeepLinkDeliveryChannel` (sem cifra, só
///     devolve via outro deep link — nenhum salto de rede a proteger).
enum DeliveryOutcome { sent, timeout }

class DeliveryResult {
  final DeliveryOutcome outcome;
  final String? deadDropIpnsName;
  final String? deadDropError;

  const DeliveryResult({
    required this.outcome,
    this.deadDropIpnsName,
    this.deadDropError,
  });
}

abstract class ResultDeliveryChannel {
  Future<DeliveryResult> deliver({
    required Map<String, dynamic> result,
    required String sessionId,
    required DateTime expiresAt,
  });
}
