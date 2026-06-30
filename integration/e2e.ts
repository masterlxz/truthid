/**
 * Teste de integração E2E — Etapa 6.1
 * Fluxo: criar identidade → registrar device → autenticar via challenge/response
 *
 * Como funciona:
 * 1. Sobe o Anvil (blockchain local em memória)
 * 2. Faz deploy dos contratos reais (mesmo bytecode que rodaria em produção)
 * 3. Executa o fluxo completo com transações reais na blockchain local
 * 4. Imprime ✅ / ❌ em cada passo
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
// Configuração da chain local (Anvil roda na porta 8545, chainId 31337)
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
// O Anvil cria 10 carteiras conhecidas com 10.000 ETH cada.
// Private keys derivadas do mnemônico padrão "test test test ... junk"
// ────────────────────────────────────────────────────────────────────────────

// Carteira de Alice — vai criar a identidade e registrar o device
const ALICE_PRIVATE_KEY =
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" as const;

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function pass(msg: string) {
  console.log(`  ✅ ${msg}`);
}

function fail(msg: string) {
  console.error(`  ❌ ${msg}`);
  process.exit(1);
}

function step(title: string) {
  console.log(`\n── ${title} ──`);
}

/** Lê o bytecode e ABI compilados pelo Foundry */
function loadArtifact(contractName: string) {
  const contractsDir = join(__dirname, "..", "contracts", "out");
  const path = join(contractsDir, `${contractName}.sol`, `${contractName}.json`);
  const artifact = JSON.parse(readFileSync(path, "utf-8"));
  return {
    abi: artifact.abi,
    bytecode: artifact.bytecode.object as `0x${string}`, // já tem prefixo 0x
  };
}

/** Aguarda até o Anvil estar aceitando conexões */
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
    } catch {
      // ainda não está pronto
    }
    await new Promise((r) => setTimeout(r, 100));
  }
  throw new Error("Anvil não respondeu em tempo hábil");
}

// ────────────────────────────────────────────────────────────────────────────
// Função principal
// ────────────────────────────────────────────────────────────────────────────

async function main() {
  console.log("═══════════════════════════════════════════════════");
  console.log("  TruthID — Teste E2E 6.1: Fluxo completo de login");
  console.log("═══════════════════════════════════════════════════");

  // ── Passo 0: Subir o Anvil ──────────────────────────────────────────────
  step("Passo 0: Iniciando Anvil (blockchain local)");

  let anvilProcess: ChildProcess | null = null;
  try {
    anvilProcess = spawn("anvil", ["--silent"], { stdio: "pipe" });
    anvilProcess.on("error", (err) => {
      console.error("Erro ao iniciar Anvil:", err.message);
      process.exit(1);
    });

    await waitForAnvil();
    pass("Anvil rodando em http://127.0.0.1:8545 (chainId 31337)");
  } catch (err) {
    fail(`Não conseguiu iniciar o Anvil: ${err}`);
  }

  // Garante que o Anvil é terminado ao sair, mesmo com erro
  const cleanup = () => {
    if (anvilProcess && !anvilProcess.killed) {
      anvilProcess.kill();
    }
  };
  process.on("exit", cleanup);
  process.on("SIGINT", () => { cleanup(); process.exit(0); });

  // ── Clientes viem ───────────────────────────────────────────────────────
  const publicClient = createPublicClient({
    chain: localChain,
    transport: http(LOCAL_RPC),
  });

  const alice = privateKeyToAccount(ALICE_PRIVATE_KEY);

  const walletClient = createWalletClient({
    chain: localChain,
    transport: http(LOCAL_RPC),
    account: alice,
  });

  // ── Passo 1: Deploy dos contratos ───────────────────────────────────────
  step("Passo 1: Deploy dos contratos");

  const identityArtifact = loadArtifact("IdentityRegistry");
  const deviceArtifact = loadArtifact("DeviceRegistry");

  // Deploy IdentityRegistry (sem constructor args)
  const identityDeployTx = await walletClient.deployContract({
    abi: identityArtifact.abi,
    bytecode: identityArtifact.bytecode,
    args: [],
  });
  const identityReceipt = await publicClient.waitForTransactionReceipt({
    hash: identityDeployTx,
  });
  const identityAddress = identityReceipt.contractAddress!;
  pass(`IdentityRegistry deployado em ${identityAddress}`);

  // Deploy DeviceRegistry (recebe o endereço do IdentityRegistry no constructor)
  const deviceDeployTx = await walletClient.deployContract({
    abi: deviceArtifact.abi,
    bytecode: deviceArtifact.bytecode,
    args: [identityAddress],
  });
  const deviceReceipt = await publicClient.waitForTransactionReceipt({
    hash: deviceDeployTx,
  });
  const deviceAddress = deviceReceipt.contractAddress!;
  pass(`DeviceRegistry deployado em ${deviceAddress}`);

  // ── Passo 2: Criar identidade ────────────────────────────────────────────
  step("Passo 2: Criar identidade on-chain");

  // Alice envia uma transação para criar a identidade "alice"
  const createIdentityTx = await walletClient.writeContract({
    address: identityAddress,
    abi: identityArtifact.abi,
    functionName: "createIdentity",
    args: ["alice", alice.address],
  });
  await publicClient.waitForTransactionReceipt({ hash: createIdentityTx });

  // Confirma que a identidade foi criada corretamente
  const identity = await publicClient.readContract({
    address: identityAddress,
    abi: identityArtifact.abi,
    functionName: "getIdentity",
    args: ["alice"],
  }) as { id: bigint; username: string; controller: `0x${string}`; exists: boolean };

  if (!identity.exists) fail("Identidade não foi criada");
  if (identity.controller.toLowerCase() !== alice.address.toLowerCase()) {
    fail(`Controller incorreto: esperado ${alice.address}, obtido ${identity.controller}`);
  }
  pass(`Identidade criada: id=${identity.id}, username="${identity.username}", controller=${identity.controller}`);

  // ── Passo 3: Registrar device ────────────────────────────────────────────
  step("Passo 3: Registrar device na blockchain");

  // Simula o app mobile gerando um par de chaves no dispositivo
  // (no app real, isso acontece no Android Keystore / iOS Secure Enclave)
  const devicePrivateKey = generatePrivateKey();
  const deviceAccount = privateKeyToAccount(devicePrivateKey);
  const deviceAddress2 = deviceAccount.address;

  // Registro em 2 passos (commit-reveal) — protege contra front-running:
  // sem isso, alguém observando a mempool poderia ver o devicePubKey da
  // transação pendente e registrá-lo primeiro para a própria identidade.
  const salt = generatePrivateKey(); // só precisa ser 32 bytes aleatórios
  const commitment = keccak256(
    encodePacked(["address", "bytes32", "address"], [deviceAddress2, salt, alice.address])
  );

  const commitTx = await walletClient.writeContract({
    address: deviceAddress,
    abi: deviceArtifact.abi,
    functionName: "commitDevice",
    args: [commitment],
  });
  await publicClient.waitForTransactionReceipt({ hash: commitTx });

  // Alice registra o device usando a carteira dela (ela é o controller da identidade)
  const registerTx = await walletClient.writeContract({
    address: deviceAddress,
    abi: deviceArtifact.abi,
    functionName: "registerDevice",
    args: [deviceAddress2, "Meu celular de teste", salt],
  });
  await publicClient.waitForTransactionReceipt({ hash: registerTx });

  // Verifica que o device está ativo
  const isActive = await publicClient.readContract({
    address: deviceAddress,
    abi: deviceArtifact.abi,
    functionName: "isDeviceActive",
    args: [deviceAddress2],
  });

  if (!isActive) fail("Device não ficou ativo após registro");
  pass(`Device registrado e ativo: ${deviceAddress2}`);

  // ── Passo 4: Fluxo de autenticação ──────────────────────────────────────
  step("Passo 4: Fluxo de autenticação (challenge → sign → verify)");

  // 4a. Website cria o challenge
  const challenge = {
    type: "challenge" as const,
    nonce: crypto.randomUUID(),
    issuedAt: Date.now(),
    origin: "http://meusite.com",
  };
  pass(`Challenge criado: nonce=${challenge.nonce.slice(0, 8)}…`);

  // 4b. O challenge chega ao celular via WebRTC (P2P). O celular assina com a chave do device.
  // No app real, esta assinatura acontece dentro do Android Keystore / iOS Secure Enclave.
  // Aqui simulamos com a chave de teste.
  const message = JSON.stringify({
    type: challenge.type,
    nonce: challenge.nonce,
    issuedAt: challenge.issuedAt,
    origin: challenge.origin,
  });
  const signature = await deviceAccount.signMessage({ message });
  pass(`Challenge assinado pelo device`);

  // 4c. Verificação no website:

  // Verificação 1: TTL (challenge não pode ter expirado)
  const TTL_MS = 30_000;
  const age = Date.now() - challenge.issuedAt;
  if (age > TTL_MS) fail(`Challenge expirado (${age}ms > ${TTL_MS}ms)`);
  pass(`TTL ok (challenge tem ${age}ms de idade)`);

  // Verificação 2: Recuperar o endereço que assinou e comparar com o device registrado
  const recoveredAddress = await recoverMessageAddress({ message, signature });
  if (recoveredAddress.toLowerCase() !== deviceAddress2.toLowerCase()) {
    fail(`Assinatura inválida: recuperado ${recoveredAddress}, esperado ${deviceAddress2}`);
  }
  pass(`Assinatura válida: recuperado ${recoveredAddress}`);

  // Verificação 3: Confirma na blockchain que o device ainda está ativo (não foi revogado)
  const isStillActive = await publicClient.readContract({
    address: deviceAddress,
    abi: deviceArtifact.abi,
    functionName: "isDeviceActive",
    args: [deviceAddress2],
  });
  if (!isStillActive) fail("Device foi revogado");
  pass("Device confirmado ativo na blockchain");

  // Verificação 4: Busca o identityId do device para retornar ao website
  const deviceInfo = await publicClient.readContract({
    address: deviceAddress,
    abi: deviceArtifact.abi,
    functionName: "getDevice",
    args: [deviceAddress2],
  }) as { identityId: bigint; pubKey: `0x${string}`; label: string; addedAt: bigint; revoked: boolean; exists: boolean };
  pass(`Login aprovado para identityId=${deviceInfo.identityId} (username: "alice")`);

  // ── Resultado final ──────────────────────────────────────────────────────
  console.log("\n═══════════════════════════════════════════════════");
  console.log("  ✅ Todos os passos passaram — Etapa 6.1 concluída");
  console.log("═══════════════════════════════════════════════════\n");

  cleanup();
  process.exit(0);
}

main().catch((err) => {
  console.error("\n❌ Erro inesperado:", err);
  process.exit(1);
});
