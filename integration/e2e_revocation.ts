/**
 * Teste de integração E2E — Etapa 6.3
 * Fluxo de revogação: revogar device → tentativa de login falha
 *
 * O teste tem dois momentos contrastantes:
 *   ANTES da revogação: login com device ativo    → deve ser aprovado ✅
 *   DEPOIS da revogação: mesmo device tenta login → deve ser rejeitado ❌
 *
 * A rejeição acontece no passo 5 da verificação: `isDeviceActive(devicePubKey)`
 * retorna false na blockchain e o login é negado com razão "Device is not active".
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
// Lógica de verificação de auth (mesma do TruthIDClient.verifyAuthResponse)
// Retorna { valid, reason } em vez de lançar exceção — para testar o caso
// de falha sem encerrar o processo.
// ────────────────────────────────────────────────────────────────────────────

type AuthResult = { valid: true; identityId: bigint } | { valid: false; reason: string };

async function verifyAuth(
  publicClient: ReturnType<typeof createPublicClient>,
  deviceAbi: unknown[],
  deviceContractAddr: `0x${string}`,
  challenge: { type: string; nonce: string; issuedAt: number; origin: string },
  response: { approved: boolean; nonce: string; signature: `0x${string}`; deviceAddress: `0x${string}` },
  ttlMs = 30_000,
): Promise<AuthResult> {
  if (!response.approved) return { valid: false, reason: "User rejected the login request" };
  if (Date.now() - challenge.issuedAt > ttlMs) return { valid: false, reason: "Challenge expired" };
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

  // Ponto crítico: consulta a blockchain — é aqui que a revogação bloqueia o login
  const isActive = await publicClient.readContract({
    address: deviceContractAddr,
    abi: deviceAbi,
    functionName: "isDeviceActive",
    args: [response.deviceAddress],
  }) as boolean;

  if (!isActive) return { valid: false, reason: "Device is not active or has been revoked" };

  const device = await publicClient.readContract({
    address: deviceContractAddr,
    abi: deviceAbi,
    functionName: "getDevice",
    args: [response.deviceAddress],
  }) as { identityId: bigint; pubKey: `0x${string}`; label: string; addedAt: bigint; revoked: boolean; exists: boolean };

  return { valid: true, identityId: device.identityId };
}

// ────────────────────────────────────────────────────────────────────────────
// Função principal
// ────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════════════════");
  console.log("  TruthID — Teste E2E 6.3: Revogação de device");
  console.log("═══════════════════════════════════════════════════════════════");

  // ── Passo 0: Subir Anvil ────────────────────────────────────────────────
  step("Passo 0: Iniciando Anvil");

  let anvilProcess: ChildProcess | null = null;
  anvilProcess = spawn("anvil", ["--silent"], { stdio: "pipe" });
  anvilProcess.on("error", (err: Error) => { console.error("Erro Anvil:", err.message); process.exit(1); });
  const cleanup = () => { if (anvilProcess && !anvilProcess.killed) anvilProcess.kill(); };
  process.on("exit", cleanup);
  process.on("SIGINT", () => { cleanup(); process.exit(0); });

  await waitForAnvil();
  pass("Anvil rodando em http://127.0.0.1:8545");

  const publicClient = createPublicClient({ chain: localChain, transport: http(LOCAL_RPC) });
  const alice = privateKeyToAccount(ALICE_KEY);
  const aliceWallet = createWalletClient({ chain: localChain, transport: http(LOCAL_RPC), account: alice });

  // ── Passo 1: Deploy dos contratos ───────────────────────────────────────
  step("Passo 1: Deploy dos contratos");

  const identityArtifact = loadArtifact("IdentityRegistry");
  const deviceArtifact = loadArtifact("DeviceRegistry");

  const idTx = await aliceWallet.deployContract({
    abi: identityArtifact.abi, bytecode: identityArtifact.bytecode, args: [],
  });
  const idReceipt = await publicClient.waitForTransactionReceipt({ hash: idTx });
  const identityAddr = idReceipt.contractAddress!;
  pass(`IdentityRegistry → ${identityAddr}`);

  const devTx = await aliceWallet.deployContract({
    abi: deviceArtifact.abi, bytecode: deviceArtifact.bytecode, args: [identityAddr],
  });
  const devReceipt = await publicClient.waitForTransactionReceipt({ hash: devTx });
  const deviceAddr = devReceipt.contractAddress!;
  pass(`DeviceRegistry → ${deviceAddr}`);

  // ── Passo 2: Criar identidade e registrar device ─────────────────────────
  step("Passo 2: Criar identidade e registrar device");

  await publicClient.waitForTransactionReceipt({
    hash: await aliceWallet.writeContract({
      address: identityAddr, abi: identityArtifact.abi,
      functionName: "createIdentity", args: ["alice", alice.address],
    }),
  });
  pass(`Identidade "alice" criada`);

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
  pass(`Device registrado: ${devicePubKey}`);

  // ── Passo 3: Login ANTES da revogação (deve ser aprovado) ───────────────
  step("Passo 3: Login com device ativo (deve ser aprovado)");

  const challenge1 = {
    type: "challenge" as const,
    nonce: crypto.randomUUID(),
    issuedAt: Date.now(),
    origin: "http://meusite.com",
  };
  const message1 = JSON.stringify(challenge1);
  const sig1 = await deviceAccount.signMessage({ message: message1 });

  const result1 = await verifyAuth(
    publicClient,
    deviceArtifact.abi,
    deviceAddr,
    challenge1,
    { approved: true, nonce: challenge1.nonce, signature: sig1, deviceAddress: devicePubKey },
  );

  if (!result1.valid) fail(`Login deveria ter sido aprovado, mas foi rejeitado: ${result1.reason}`);
  pass(`Login aprovado para identityId=${result1.identityId}`);

  // ── Passo 4: Alice revoga o device ──────────────────────────────────────
  step("Passo 4: Alice revoga o device");

  await publicClient.waitForTransactionReceipt({
    hash: await aliceWallet.writeContract({
      address: deviceAddr, abi: deviceArtifact.abi,
      functionName: "revokeDevice", args: [devicePubKey],
    }),
  });

  // Confirma o estado na blockchain
  const isActive = await publicClient.readContract({
    address: deviceAddr, abi: deviceArtifact.abi,
    functionName: "isDeviceActive", args: [devicePubKey],
  }) as boolean;

  if (isActive) fail("Device ainda aparece ativo após revogação");
  pass(`Device revogado — isDeviceActive retorna false`);

  // ── Passo 5: Login APÓS revogação (deve ser rejeitado) ───────────────────
  step("Passo 5: Login com device revogado (deve ser rejeitado)");

  // O device ainda tem a chave privada e consegue assinar — mas a blockchain
  // vai negar porque isDeviceActive retorna false.
  const challenge2 = {
    type: "challenge" as const,
    nonce: crypto.randomUUID(),
    issuedAt: Date.now(),
    origin: "http://meusite.com",
  };
  const message2 = JSON.stringify(challenge2);
  const sig2 = await deviceAccount.signMessage({ message: message2 });

  const result2 = await verifyAuth(
    publicClient,
    deviceArtifact.abi,
    deviceAddr,
    challenge2,
    { approved: true, nonce: challenge2.nonce, signature: sig2, deviceAddress: devicePubKey },
  );

  if (result2.valid) {
    fail("Login deveria ter sido rejeitado, mas foi aprovado — a revogação não está funcionando!");
  }
  expectReject(`Login rejeitado com motivo: "${result2.reason}"`);

  if (result2.reason !== "Device is not active or has been revoked") {
    fail(`Motivo de rejeição inesperado: "${result2.reason}"`);
  }
  pass(`Motivo de rejeição correto`);

  // ── Resultado final ──────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════════════════");
  console.log("  ✅ Todos os passos passaram — Etapa 6.3 concluída");
  console.log("═══════════════════════════════════════════════════════════════\n");

  cleanup();
  process.exit(0);
}

main().catch((err) => {
  console.error("\n❌ Erro inesperado:", err);
  process.exit(1);
});
