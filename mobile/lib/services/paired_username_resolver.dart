import 'blockchain_service.dart';
import 'local_storage_service.dart';

// Extraído do achado real da Sessão 135 (ultrareview): a lógica de "o
// celular já está pareado (identityId persistido), mas o @username nunca
// resolveu — tenta de novo on-chain antes de desistir" tinha sido
// copiada quase igual entre wallet_screen.dart e
// vault_edit_approval_screen.dart, e nunca chegou em mais 3 telas
// (sign_request_approval_screen.dart, sessions_screen.dart,
// vault_screen.dart) que sofrem do mesmo bug: `getUsernameForIdentity`
// (scan de log on-chain) pode falhar uma vez de forma transiente e, sem
// retry, o username nunca mais persiste — travando qualquer tela que
// dependa dele.
//
// Função livre (não um método de LocalStorageService) de propósito —
// LocalStorageService é só um wrapper chave-valor, sem dependência de
// BlockchainService; misturar as duas nela criaria um acoplamento que não
// existe hoje em nenhum outro lugar do projeto.
Future<String?> resolvePairedUsername({
  required LocalStorageService storage,
  required BlockchainService blockchain,
  required String identityId,
}) async {
  final cached = await storage.getPairedUsername();
  if (cached != null) return cached;

  try {
    final resolved = await blockchain.getUsernameForIdentity(BigInt.parse(identityId));
    if (resolved != null) {
      await storage.savePairedUsername(resolved);
    }
    return resolved;
  } catch (_) {
    // Falha transiente (RPC fora do ar, chunk específico deu timeout) —
    // quem chamou decide o que fazer (mostrar erro, tentar de novo no
    // próximo load, ou só deixar a UI dependente desabilitada).
    return null;
  }
}
