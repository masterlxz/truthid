import { invoke } from "@tauri-apps/api/core";

// Helper compartilhado — handleReject nos 4 modais de aprovação
// (PinApproval, SignMessage, SignRequest, VaultEdit) faz exatamente o
// mesmo: responde "rejected" ao Rust e limpa o request local.
export async function respondToRequest(
  cmd: string,
  requestId: string,
  clear: () => void,
): Promise<void> {
  await invoke(cmd, {
    id: requestId,
    decision: { outcome: "rejected" },
  }).catch(() => {});
  clear();
}
