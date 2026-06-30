/**
 * Teste de integração E2E — Etapa 6.4
 * Testes de segurança: replay attack, challenge expirado, nonce mismatch,
 * assinatura de device errado.
 *
 * Estes testes focam na CAMADA DE VERIFICAÇÃO (SDK), não em transações
 * blockchain. O setup (deploy, identidade, device) usa a blockchain local,
 * mas os ataques são testados sem enviar novas transações.
 *
 * Por que a camada de verificação importa?
 *   Um atacante pode interceptar uma resposta assinada e tentar reutilizá-la.
 *   A assinatura vai continuar criptograficamente válida — só a lógica do
 *   servidor salva o usuário. Este teste valida essa lógica.
 */

import { spawn, ChildProcess } from "child_process";
import { readFileSync } from "fs";
import { join } from "path";
import {
  createPublicClient,
  createWalletClient,
  http,
  recoverMessageAddress,
  keccak256,
  encodePacked,
} from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";

// ────────────────────────────────────────────────────────────────────────────
// Chain local
// ────────────────────────────────────────────────────────────────────────────

const LOCAL_RPC = "http://127.0.0.1:8545";

const localChain = {
  id: 31337,
  name: "Anvil",
  network: "anvil",
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [LOCAL_RPC] }, public: { http: [LOCAL_RPC] } },
} as const;

const ALICE_KEY = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function pass(msg: string) { console.log(`  ✅ ${msg}`); }
function fail(msg: string): never { console.error(`  ❌ ${msg}`); process.exit(1); }
function step(title: string) { console.log(`\n── ${title} ──`); }
function expectReject(msg: string) { console.log(`  ❌ (esperado) ${msg}`); }

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

// ────────────────────────────────────────────────────────────────────────────
// Servidor simulado
//
// Em produção, o servidor Express guarda os challenges num Map<nonce, challenge>
// e deleta o nonce após o primeiro uso (anti-replay). Aqui simulamos isso
// com a classe abaixo para testar os dois cenários:
//   - servidor correto: deleta o nonce após uso
//   - servidor com bug: não deleta (vulnerável a replay)
// ────────────────────────────────────────────────────────────────────────────

type Challenge = { type: string; nonce: string; issuedAt: number; origin: string };
type AuthResponse = { approved: boolean; nonce: string; signature: `0x${string}`; deviceAddress: `0x${string}` };
type AuthResult = { valid: true; identityId: bigint } | { valid: false; reason: string };

class SimulatedServer {
  // Map que o servidor mantém em memória: nonce → challenge
  private pendingChallenges = new Map<string, Challenge>();

  constructor(
    private publicClient: ReturnType<typeof createPublicClient>,
    private deviceAbi: unknown[],
    private deviceContractAddr: `0x${string}`,
    private ttlMs = 30_000,
  ) {}

  createChallenge(origin: string): Challenge {
    const challenge: Challenge = {
      type: "challenge",
      nonce: crypto.randomUUID(),
      issuedAt: Date.now(),
      origin,
    };
    this.pendingChallenges.set(challenge.nonce, challenge);
    return challenge;
  }

  /**
   * Verifica a resposta do mobile.
   *
   * deleteAfterUse = true  → comportamento correto (anti-replay)
   * deleteAfterUse = false → servidor com bug (vulnerável a replay)
   */
  async verify(response: AuthResponse, deleteAfterUse = true): Promise<AuthResult> {
    if (!response.approved) return { valid: false, reason: "User rejected the login request" };

    // Busca o challenge pelo nonce — se não encontrar, foi consumido ou nunca existiu
    const challenge = this.pendingChallenges.get(response.nonce);
    if (!challenge) return { valid: false, reason: "Challenge not found or already used" };

    if (Date.now() - challenge.issuedAt > this.ttlMs) {
      this.pendingChallenges.delete(response.nonce);
      return { valid: false, reason: "Challenge expired" };
    }

    if (challenge.nonce !== response.nonce) return { valid: false, reason: "Nonce mismatch" };

    const message = JSON.stringify({
      type: challenge.type,
      nonce: challenge.nonce,
      issuedAt: challenge.issuedAt,
      origin: challenge.origin,
    });

    let signer: string;
    try {
      signer = await recoverMessageAddress({ message, signature: response.signature });
    } catch {
      return { valid: false, reason: "Invalid signature format" };
    }

    if (signer.toLowerCase() !== response.deviceAddress.toLowerCase()) {
      return { valid: false, reason: "Signature does not match device address" };
    }

    const isActive = await this.publicClient.readContract({
      address: this.deviceContractAddr,
      abi: this.deviceAbi,
      functionName: "isDeviceActive",
      args: [response.deviceAddress],
    }) as boolean;

    if (!isActive) return { valid: false, reason: "Device is not active or has been revoked" };

    // Deleta o nonce SOMENTE agora, após todas as verificações passarem.
    // Deletar antes permitiria um race condition: dois requests concorrentes
    // com o mesmo nonce, o primeiro falha na blockchain e o segundo consegue.
    if (deleteAfterUse) this.pendingChallenges.delete(response.nonce);

    const device = await this.publicClient.readContract({
      address: this.deviceContractAddr,
      abi: this.deviceAbi,
      functionName: "getDevice",
      args: [response.deviceAddress],
    }) as { identityId: bigint };

    return { valid: true, identityId: device.identityId };
  }
}

// ────────────────────────────────────────────────────────────────────────────
// Função principal
// ────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  TruthID — Teste E2E 6.4: Testes de segurança");
  console.log("═══════════════════════════════════════════════════════════════");

  // ── Setup: Anvil + contratos + identidade + device ───────────────────────
  step("Setup: Anvil + contratos + identidade + device");

  let anvilProcess: ChildProcess | null = null;
  anvilProcess = spawn("anvil", ["--silent"], { stdio: "pipe" });
  anvilProcess.on("error", (err: Error) => { console.error("Erro Anvil:", err.message); process.exit(1); });
  const cleanup = () => { if (anvilProcess && !anvilProcess.killed) anvilProcess.kill(); };
  process.on("exit", cleanup);
  process.on("SIGINT", () => { cleanup(); process.exit(0); });

  await waitForAnvil();

  const publicClient = createPublicClient({ chain: localChain, transport: http(LOCAL_RPC) });
  const alice = privateKeyToAccount(ALICE_KEY);
  const aliceWallet = createWalletClient({ chain: localChain, transport: http(LOCAL_RPC), account: alice });

  const identityArtifact = loadArtifact("IdentityRegistry");
  const deviceArtifact = loadArtifact("DeviceRegistry");

  const idTx = await aliceWallet.deployContract({ abi: identityArtifact.abi, bytecode: identityArtifact.bytecode, args: [] });
  const idReceipt = await publicClient.waitForTransactionReceipt({ hash: idTx });
  const identityAddr = idReceipt.contractAddress!;

  const devTx = await aliceWallet.deployContract({ abi: deviceArtifact.abi, bytecode: deviceArtifact.bytecode, args: [identityAddr] });
  const devReceipt = await publicClient.waitForTransactionReceipt({ hash: devTx });
  const deviceAddr = devReceipt.contractAddress!;

  await publicClient.waitForTransactionReceipt({
    hash: await aliceWallet.writeContract({
      address: identityAddr, abi: identityArtifact.abi,
      functionName: "createIdentity", args: ["alice", alice.address],
    }),
  });

  const devicePrivKey = generatePrivateKey();
  const deviceAccount = privateKeyToAccount(devicePrivKey);
  const devicePubKey = deviceAccount.address;

  // Registro em 2 passos (commit-reveal) — protege contra front-running
  const salt = generatePrivateKey();
  const commitment = keccak256(
    encodePacked(["address", "bytes32", "address"], [devicePubKey, salt, alice.address])
  );
  await publicClient.waitForTransactionReceipt({
    hash: await aliceWallet.writeContract({
      address: deviceAddr, abi: deviceArtifact.abi,
      functionName: "commitDevice", args: [commitment],
    }),
  });

  await publicClient.waitForTransactionReceipt({
    hash: await aliceWallet.writeContract({
      address: deviceAddr, abi: deviceArtifact.abi,
      functionName: "registerDevice", args: [devicePubKey, "Meu celular", salt],
    }),
  });

  pass(`Setup completo — device ativo: ${devicePubKey}`);

  const server = new SimulatedServer(publicClient, deviceArtifact.abi, deviceAddr);

  // ── Teste 1: Replay attack ───────────────────────────────────────────────
  step("Teste 1: Replay attack");
  console.log("  Cenário: atacante captura uma resposta assinada e tenta reutilizá-la.");
  console.log("  A assinatura continua válida — a proteção é o servidor consumir o nonce.\n");

  const challenge1 = server.createChallenge("http://meusite.com");
  const message1 = JSON.stringify(challenge1);
  const sig1 = await deviceAccount.signMessage({ message: message1 });
  const response1: AuthResponse = {
    approved: true, nonce: challenge1.nonce,
    signature: sig1, deviceAddress: devicePubKey,
  };

  // 1ª tentativa — legítima, deve passar
  const first = await server.verify(response1, /* deleteAfterUse= */ true);
  if (!first.valid) fail(`1ª tentativa deveria ter passado: ${first.reason}`);
  pass(`1ª tentativa (legítima): aprovada para identityId=${first.identityId}`);

  // 2ª tentativa — replay com a MESMA resposta assinada
  const replay = await server.verify(response1, /* deleteAfterUse= */ true);
  if (replay.valid) fail("Replay deveria ter sido rejeitado, mas foi aprovado!");
  expectReject(`Replay rejeitado: "${replay.reason}"`);
  if (replay.reason !== "Challenge not found or already used") {
    fail(`Motivo inesperado: "${replay.reason}"`);
  }
  pass(`Motivo correto — nonce foi consumido após o primeiro uso`);

  // Demonstra o que acontece se o servidor NÃO deletar o nonce (bug)
  const challenge1b = server.createChallenge("http://meusite.com");
  const sig1b = await deviceAccount.signMessage({ message: JSON.stringify(challenge1b) });
  const response1b: AuthResponse = {
    approved: true, nonce: challenge1b.nonce,
    signature: sig1b, deviceAddress: devicePubKey,
  };
  const firstOk = await server.verify(response1b, /* deleteAfterUse= */ false); // bug: não deleta
  const replayOk = await server.verify(response1b, /* deleteAfterUse= */ false); // replay funciona!
  if (!firstOk.valid || !replayOk.valid) fail("Demonstração de bug falhou inesperadamente");
  pass(`⚠️  Demonstração de bug: sem deleteAfterUse, replay APROVADO — identityId=${replayOk.identityId}`);
  console.log("     (isso NÃO é o comportamento correto — é a vulnerabilidade que o delete evita)");
  // Limpa o nonce manualmente para não vazar para os próximos testes

  // ── Teste 2: Challenge expirado ──────────────────────────────────────────
  step("Teste 2: Challenge expirado (TTL = 30s)");
  console.log("  Cenário: mobile demora mais de 30s para aprovar (ou atacante atrasa a entrega).\n");

  // Cria um challenge adulterado com issuedAt no passado
  const expiredChallenge: Challenge = {
    type: "challenge",
    nonce: crypto.randomUUID(),
    issuedAt: Date.now() - 31_000, // 31 segundos atrás — expirado
    origin: "http://meusite.com",
  };
  // Injeta diretamente no Map interno do servidor para simular o cenário
  // (em produção, o servidor criaria o challenge com o timestamp adulterado
  // ou o mobile retornaria muito tarde)
  // Aqui usamos um servidor separado com TTL curto para demonstrar:
  const fastServer = new SimulatedServer(publicClient, deviceArtifact.abi, deviceAddr, 1); // TTL = 1ms
  const expChallenge = fastServer.createChallenge("http://meusite.com");
  await new Promise((r) => setTimeout(r, 5)); // espera 5ms — suficiente para expirar o TTL de 1ms

  const expSig = await deviceAccount.signMessage({ message: JSON.stringify(expChallenge) });
  const expResult = await fastServer.verify({
    approved: true, nonce: expChallenge.nonce,
    signature: expSig, deviceAddress: devicePubKey,
  });

  if (expResult.valid) fail("Challenge expirado deveria ter sido rejeitado");
  expectReject(`Challenge expirado rejeitado: "${expResult.reason}"`);
  if (expResult.reason !== "Challenge expired") fail(`Motivo inesperado: "${expResult.reason}"`);
  pass(`Motivo correto`);

  // ── Teste 3: Nonce mismatch ──────────────────────────────────────────────
  step("Teste 3: Nonce mismatch");
  console.log("  Cenário: mobile (ou atacante) devolve um nonce diferente do challenge original.\n");

  const challenge3 = server.createChallenge("http://meusite.com");
  const sig3 = await deviceAccount.signMessage({ message: JSON.stringify(challenge3) });

  // Response com nonce adulterado
  const mismatchResult = await server.verify({
    approved: true,
    nonce: crypto.randomUUID(), // nonce diferente — não bate com nenhum challenge pendente
    signature: sig3,
    deviceAddress: devicePubKey,
  });

  if (mismatchResult.valid) fail("Nonce mismatch deveria ter sido rejeitado");
  expectReject(`Nonce mismatch rejeitado: "${mismatchResult.reason}"`);
  // O servidor não encontra o nonce falso no Map — rejeita como "not found"
  if (mismatchResult.reason !== "Challenge not found or already used") {
    fail(`Motivo inesperado: "${mismatchResult.reason}"`);
  }
  pass(`Motivo correto`);

  // ── Teste 4: Assinatura de device errado ─────────────────────────────────
  step("Teste 4: Assinatura de device errado");
  console.log("  Cenário: atacante usa a chave de um device diferente, mas declara ser o device A.\n");

  const impostorPrivKey = generatePrivateKey();
  const impostorAccount = privateKeyToAccount(impostorPrivKey);

  const challenge4 = server.createChallenge("http://meusite.com");
  const message4 = JSON.stringify(challenge4);

  // Impostor assina com a chave DELE, mas declara o endereço do device legítimo
  const impostorSig = await impostorAccount.signMessage({ message: message4 });

  const impostorResult = await server.verify({
    approved: true, nonce: challenge4.nonce,
    signature: impostorSig,
    deviceAddress: devicePubKey, // declara ser o device de Alice
  });

  if (impostorResult.valid) fail("Impostor deveria ter sido rejeitado");
  expectReject(`Impostor rejeitado: "${impostorResult.reason}"`);
  if (impostorResult.reason !== "Signature does not match device address") {
    fail(`Motivo inesperado: "${impostorResult.reason}"`);
  }
  pass(`Motivo correto — recoverMessageAddress expôs o endereço real do impostor`);

  // ── Resultado final ──────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("  ✅ Todos os testes de segurança passaram — Etapa 6.4 concluída");
  console.log("═══════════════════════════════════════════════════════════════\n");

  cleanup();
  process.exit(0);
}

main().catch((err) => {
  console.error("\n❌ Erro inesperado:", err);
  process.exit(1);
});
