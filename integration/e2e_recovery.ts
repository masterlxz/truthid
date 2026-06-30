/**
 * Teste de integração E2E — Etapa 6.2
 * Fluxo de recovery: 3 de 5 guardians aprovam → timelock 7 dias → novo wallet assume
 *
 * Personagens:
 *   Alice  — controller original da identidade "alice"
 *   Bob    — novo controller (quem Alice quer que assuma em caso de emergência)
 *   G1–G5  — 5 guardians de confiança de Alice; threshold = 3
 *
 * Fluxo testado:
 *   1. Deploy dos 3 contratos (IdentityRegistry, DeviceRegistry, RecoveryManager)
 *   2. Alice cria identidade e define RecoveryManager como gerenciador
 *   3. Alice configura 5 guardians com threshold 3
 *   4. G1 propõe recovery para Bob (approvalCount = 0 — propor ≠ aprovar)
 *   5. G1 aprova  (approvalCount = 1)
 *   5. G2 aprova  (approvalCount = 2)
 *   6. G3 aprova  (approvalCount = 3 = threshold atingido)
 *   7. ⏩ Anvil avança 7 dias no tempo (evm_increaseTime + evm_mine)
 *   8. Qualquer um executa o recovery
 *   9. Verificação: controller da identidade "alice" agora é Bob
 */

import { spawn, ChildProcess } from "child_process";
import { readFileSync } from "fs";
import { join } from "path";
import { createPublicClient, createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";

// ────────────────────────────────────────────────────────────────────────────
// Chain local (Anvil)
// ────────────────────────────────────────────────────────────────────────────

const LOCAL_RPC = "http://127.0.0.1:8545";

const localChain = {
  id: 31337,
  name: "Anvil",
  network: "anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [LOCAL_RPC] }, public: { http: [LOCAL_RPC] } },
} as const;

// ────────────────────────────────────────────────────────────────────────────
// Carteiras de teste do Anvil
// Private keys do mnemônico padrão "test test test ... junk"
// ────────────────────────────────────────────────────────────────────────────

const ALICE_KEY  = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;
const BOB_KEY    = "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d" as const;
const G1_KEY     = "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a" as const;
const G2_KEY     = "0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6" as const;
const G3_KEY     = "0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a" as const;
const G4_KEY     = "0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba" as const;
const G5_KEY     = "0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e" as const;

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function pass(msg: string) { console.log(`  ✅ ${msg}`); }
function fail(msg: string): never { console.error(`  ❌ ${msg}`); process.exit(1); }
function step(title: string) { console.log(`\n── ${title} ──`); }
function info(msg: string) { console.log(`     ${msg}`); }

function loadArtifact(contractName: string) {
  const path = join(__dirname, "..", "contracts", "out", `${contractName}.sol`, `${contractName}.json`);
  const artifact = JSON.parse(readFileSync(path, "utf-8"));
  return { abi: artifact.abi, bytecode: artifact.bytecode.object as `0x${string}` };
}

async function waitForAnvil(maxWaitMs = 5000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < maxWaitMs) {
    try {
      const resp = await fetch(LOCAL_RPC, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", method: "eth_chainId", params: [], id: 1 }),
      });
      if (resp.ok) return;
    } catch { /* ainda não pronto */ }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("Anvil não respondeu em tempo hábil");
}

/**
 * Avança o relógio da blockchain local.
 *
 * Por que dois passos?
 *   - `evm_increaseTime` agenda o offset de tempo para o PRÓXIMO bloco
 *   - `evm_mine` força a mineração desse bloco — sem isso, o timestamp novo
 *     não é visível para os contratos ainda
 */
async function fastForward(publicClient: ReturnType<typeof createPublicClient>, seconds: number) {
  await publicClient.request({
    method: "evm_increaseTime" as never,
    params: [seconds] as never,
  });
  await publicClient.request({
    method: "evm_mine" as never,
    params: [] as never,
  });
}

// ────────────────────────────────────────────────────────────────────────────
// Função principal
// ────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  TruthID — Teste E2E 6.2: Recovery M-de-N (3 de 5) + Timelock");
  console.log("═══════════════════════════════════════════════════════════════");

  // ── Passo 0: Subir Anvil ────────────────────────────────────────────────
  step("Passo 0: Iniciando Anvil");

  let anvilProcess: ChildProcess | null = null;
  anvilProcess = spawn("anvil", ["--silent"], { stdio: "pipe" });
  anvilProcess.on("error", (err) => { console.error("Erro Anvil:", err.message); process.exit(1); });
  const cleanup = () => { if (anvilProcess && !anvilProcess.killed) anvilProcess.kill(); };
  process.on("exit", cleanup);
  process.on("SIGINT", () => { cleanup(); process.exit(0); });

  await waitForAnvil();
  pass("Anvil rodando em http://127.0.0.1:8545");

  // ── Clientes viem ───────────────────────────────────────────────────────

  const publicClient = createPublicClient({ chain: localChain, transport: http(LOCAL_RPC) });

  const alice = privateKeyToAccount(ALICE_KEY);
  const bob   = privateKeyToAccount(BOB_KEY);
  const g1    = privateKeyToAccount(G1_KEY);
  const g2    = privateKeyToAccount(G2_KEY);
  const g3    = privateKeyToAccount(G3_KEY);
  const g4    = privateKeyToAccount(G4_KEY);
  const g5    = privateKeyToAccount(G5_KEY);

  // walletClient genérico — troca de conta via `account` em cada chamada
  const wallet = (account: ReturnType<typeof privateKeyToAccount>) =>
    createWalletClient({ chain: localChain, transport: http(LOCAL_RPC), account });

  // ── Passo 1: Deploy dos 3 contratos ────────────────────────────────────
  step("Passo 1: Deploy dos contratos");

  const identityArtifact = loadArtifact("IdentityRegistry");
  const recoveryArtifact = loadArtifact("RecoveryManager");

  // IdentityRegistry — sem constructor args
  const idTx = await wallet(alice).deployContract({
    abi: identityArtifact.abi, bytecode: identityArtifact.bytecode, args: [],
  });
  const idReceipt = await publicClient.waitForTransactionReceipt({ hash: idTx });
  const identityAddr = idReceipt.contractAddress!;
  pass(`IdentityRegistry → ${identityAddr}`);

  // RecoveryManager — recebe endereço do IdentityRegistry no constructor
  const rmTx = await wallet(alice).deployContract({
    abi: recoveryArtifact.abi, bytecode: recoveryArtifact.bytecode, args: [identityAddr],
  });
  const rmReceipt = await publicClient.waitForTransactionReceipt({ hash: rmTx });
  const recoveryAddr = rmReceipt.contractAddress!;
  pass(`RecoveryManager → ${recoveryAddr}`);

  // ── Passo 2: Criar identidade e vincular RecoveryManager ───────────────
  step("Passo 2: Criar identidade + vincular RecoveryManager");

  // Alice cria a identidade "alice"
  const createTx = await wallet(alice).writeContract({
    address: identityAddr, abi: identityArtifact.abi,
    functionName: "createIdentity", args: ["alice", alice.address],
  });
  await publicClient.waitForTransactionReceipt({ hash: createTx });
  pass(`Identidade "alice" criada — controller: ${alice.address}`);

  // Alice registra o RecoveryManager como o único gerenciador de recovery
  // (só pode ser feito uma vez — proteção contra troca maliciosa depois)
  const setRmTx = await wallet(alice).writeContract({
    address: identityAddr, abi: identityArtifact.abi,
    functionName: "setRecoveryManager", args: [recoveryAddr],
  });
  await publicClient.waitForTransactionReceipt({ hash: setRmTx });
  pass(`RecoveryManager vinculado ao IdentityRegistry`);

  // ── Passo 3: Alice configura 5 guardians com threshold = 3 ─────────────
  step("Passo 3: Configurar guardians (5 guardians, threshold = 3)");

  const guardians = [g1.address, g2.address, g3.address, g4.address, g5.address];
  const THRESHOLD = 3n;

  const configTx = await wallet(alice).writeContract({
    address: recoveryAddr, abi: recoveryArtifact.abi,
    functionName: "configureGuardians",
    args: ["alice", guardians, THRESHOLD],
  });
  await publicClient.waitForTransactionReceipt({ hash: configTx });

  const [configuredGuardians, configuredThreshold] = await publicClient.readContract({
    address: recoveryAddr, abi: recoveryArtifact.abi,
    functionName: "getGuardianConfig", args: ["alice"],
  }) as [string[], bigint];

  if (configuredGuardians.length !== 5) fail(`Esperava 5 guardians, obteve ${configuredGuardians.length}`);
  if (configuredThreshold !== THRESHOLD) fail(`Threshold incorreto: ${configuredThreshold}`);
  pass(`5 guardians configurados, threshold = ${configuredThreshold}`);
  for (let i = 0; i < guardians.length; i++) {
    info(`G${i+1}: ${guardians[i]}`);
  }

  // ── Passo 4: G1 propõe recovery para Bob ───────────────────────────────
  step("Passo 4: G1 propõe recovery → novo controller será Bob");
  info(`Bob: ${bob.address}`);

  const proposeTx = await wallet(g1).writeContract({
    address: recoveryAddr, abi: recoveryArtifact.abi,
    functionName: "proposeRecovery", args: ["alice", bob.address],
  });
  await publicClient.waitForTransactionReceipt({ hash: proposeTx });

  const proposal = await publicClient.readContract({
    address: recoveryAddr, abi: recoveryArtifact.abi,
    functionName: "getProposal", args: ["alice"],
  }) as { proposedBy: string; newController: string; proposedAt: bigint; approvalCount: bigint; executed: boolean; cancelled: boolean; exists: boolean };

  if (!proposal.exists) fail("Proposta não foi criada");
  // proposeRecovery zera approvalCount — o proposer vota separadamente via approveRecovery
  if (proposal.approvalCount !== 0n) fail(`approvalCount incorreto: esperava 0, obteve ${proposal.approvalCount}`);
  pass(`Proposta criada por G1 (approvalCount = 0 — proposer vota separadamente)`);
  info(`Timelock expira em: ${new Date(Number(proposal.proposedAt + 7n * 24n * 3600n) * 1000).toISOString()}`);

  // ── Passo 5: G1 + G2 + G3 aprovam → threshold atingido ─────────────────
  step("Passo 5: G1, G2 e G3 aprovam (threshold = 3)");

  for (const [label, guardian] of [["G1", g1], ["G2", g2], ["G3", g3]] as const) {
    const approveTx = await wallet(guardian).writeContract({
      address: recoveryAddr, abi: recoveryArtifact.abi,
      functionName: "approveRecovery", args: ["alice"],
    });
    await publicClient.waitForTransactionReceipt({ hash: approveTx });

    const p = await publicClient.readContract({
      address: recoveryAddr, abi: recoveryArtifact.abi,
      functionName: "getProposal", args: ["alice"],
    }) as typeof proposal;
    pass(`${label} aprovou, approvalCount = ${p.approvalCount}/3`);
  }

  const proposal3 = await publicClient.readContract({
    address: recoveryAddr, abi: recoveryArtifact.abi,
    functionName: "getProposal", args: ["alice"],
  }) as typeof proposal;
  if (proposal3.approvalCount < THRESHOLD) fail(`Threshold não atingido: ${proposal3.approvalCount}/3`);
  pass(`Threshold atingido ✓`);

  // ── Passo 7: Avançar 7 dias no tempo ───────────────────────────────────
  step("Passo 7: Avançando 7 dias no tempo (timelock)");

  const SEVEN_DAYS = 7 * 24 * 60 * 60; // segundos
  await fastForward(publicClient, SEVEN_DAYS + 1); // +1 para garantir que passou do limite

  const blockAfter = await publicClient.getBlock();
  pass(`Tempo avançado — timestamp do bloco atual: ${new Date(Number(blockAfter.timestamp) * 1000).toLocaleString()}`);

  // Tenta executar ANTES de avançar o tempo seria rejeitado pelo contrato.
  // A chamada a `fastForward` acima simula os 7 dias passando.

  // ── Passo 8: Executar o recovery ────────────────────────────────────────
  step("Passo 8: Executar recovery (qualquer endereço pode chamar)");

  // Não precisa ser Alice, nem guardian — qualquer um pode executar após o timelock.
  // Usamos Bob para demonstrar isso.
  const executeTx = await wallet(bob).writeContract({
    address: recoveryAddr, abi: recoveryArtifact.abi,
    functionName: "executeRecovery", args: ["alice"],
  });
  await publicClient.waitForTransactionReceipt({ hash: executeTx });
  pass("executeRecovery() chamado com sucesso");

  // ── Passo 9: Verificar que o controller mudou ───────────────────────────
  step("Passo 9: Verificar novo controller na blockchain");

  const identity = await publicClient.readContract({
    address: identityAddr, abi: identityArtifact.abi,
    functionName: "getIdentity", args: ["alice"],
  }) as { id: bigint; username: string; controller: `0x${string}`; exists: boolean };

  if (identity.controller.toLowerCase() !== bob.address.toLowerCase()) {
    fail(
      `Controller incorreto!\n  Esperado: ${bob.address}\n  Obtido:   ${identity.controller}`
    );
  }
  pass(`Controller da identidade "alice" agora é: ${identity.controller}`);
  info(`(antes era Alice: ${alice.address})`);

  // Verifica também que a proposta foi marcada como executada
  const finalProposal = await publicClient.readContract({
    address: recoveryAddr, abi: recoveryArtifact.abi,
    functionName: "getProposal", args: ["alice"],
  }) as typeof proposal;
  if (!finalProposal.executed) fail("Proposta deveria estar marcada como executed");
  pass("Proposta marcada como executed = true");

  // ── Resultado final ──────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("  ✅ Todos os passos passaram — Etapa 6.2 concluída");
  console.log("═══════════════════════════════════════════════════════════════\n");

  cleanup();
  process.exit(0);
}

main().catch((err) => {
  console.error("\n❌ Erro inesperado:", err);
  process.exit(1);
});
