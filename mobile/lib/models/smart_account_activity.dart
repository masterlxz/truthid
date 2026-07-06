// Modelo compartilhado entre SmartAccountActivityScanner, ActivityCacheService
// e WalletScreen — porta de desktop/src/types.ts (SmartAccountActivity/
// SmartAccountActivityType), usado pela dashboard da smart account (14.10)
// e agora também pela aba Wallet do mobile.
//
// `vaultUpdated` fica de fora de propósito: VaultRegistry ainda não foi
// deployado (endereço zero), mesma decisão já tomada no Desktop
// (scanSmartAccountActivity.ts pula esse evento inteiramente enquanto isso).
enum SmartAccountActivityType {
  deviceRegistered,
  deviceRevoked,
  sessionCreated,
  sessionRevoked,
  sessionRevokedAll,
}

class SmartAccountActivity {
  final SmartAccountActivityType type;
  final String hash; // tx hash, "0x..."
  final int blockNumber;
  final int logIndex;
  final int timestamp; // unix seconds
  final BigInt costWei; // gasUsed * effectiveGasPrice da tx que emitiu o evento

  const SmartAccountActivity({
    required this.type,
    required this.hash,
    required this.blockNumber,
    required this.logIndex,
    required this.timestamp,
    required this.costWei,
  });

  // costWei serializado como String — BigInt não é representável em JSON
  // nativo, mesmo motivo do cache em localStorage no useSmartAccountActivity.ts.
  Map<String, dynamic> toJson() => {
        'type': type.name,
        'hash': hash,
        'blockNumber': blockNumber,
        'logIndex': logIndex,
        'timestamp': timestamp,
        'costWei': costWei.toString(),
      };

  static SmartAccountActivity fromJson(Map<String, dynamic> json) {
    return SmartAccountActivity(
      type: SmartAccountActivityType.values.byName(json['type'] as String),
      hash: json['hash'] as String,
      blockNumber: json['blockNumber'] as int,
      logIndex: json['logIndex'] as int,
      timestamp: json['timestamp'] as int,
      costWei: BigInt.parse(json['costWei'] as String),
    );
  }
}

// Progresso do scan em andamento — usado pra UI mostrar "bloco X de Y"
// enquanto a varredura completa (desde o bloco de deploy) ainda não terminou.
class ScanProgress {
  final int scannedTo;
  final int latest;

  const ScanProgress({required this.scannedTo, required this.latest});
}
