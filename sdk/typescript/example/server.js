const express = require("express");
const { randomUUID } = require("crypto");
const { TruthIDClient } = require("../dist");

const app = express();
app.use(express.json());

const truthid = new TruthIDClient({ network: "base-sepolia" });

// Armazenamento em memória (use Redis em produção)
// Map: nonce → AuthChallenge
const pendingChallenges = new Map();
// Map: sessionToken → { identityId, deviceAddress }
const sessions = new Map();

// ─── Passo 1: website pede um challenge para montar o QR code ─────────────────
app.get("/auth/challenge", (req, res) => {
  const origin = req.headers.host ?? "localhost";
  const challenge = truthid.createChallenge(origin);

  // Guarda o challenge pelo nonce para recuperar na verificação
  pendingChallenges.set(challenge.nonce, challenge);

  // Remove automaticamente após 35s (um pouco além do TTL de 30s do SDK)
  setTimeout(() => pendingChallenges.delete(challenge.nonce), 35_000);

  res.json(challenge);
});

// ─── Passo 2: mobile assinou → website manda a resposta aqui ─────────────────
app.post("/auth/verify", async (req, res) => {
  const response = req.body; // { approved, nonce, signature, deviceAddress }

  // Recupera o challenge original pelo nonce
  const challenge = pendingChallenges.get(response.nonce);
  if (!challenge) {
    return res.status(400).json({ error: "Challenge not found or already used" });
  }

  // Remove o challenge para impedir replay: o mesmo nonce não pode ser usado duas vezes
  pendingChallenges.delete(response.nonce);

  // Chama o SDK para verificar tudo: assinatura, TTL, device ativo na blockchain
  const result = await truthid.verifyAuthResponse({ challenge, response });

  if (!result.valid) {
    return res.status(401).json({ error: result.reason });
  }

  // Cria um token de sessão simples (use JWT em produção)
  const sessionToken = randomUUID();
  sessions.set(sessionToken, {
    identityId: result.identityId.toString(),
    deviceAddress: result.deviceAddress,
  });

  res.json({
    token: sessionToken,
    identityId: result.identityId.toString(),
  });
});

// ─── Rota protegida ───────────────────────────────────────────────────────────
app.get("/api/profile", requireAuth, (req, res) => {
  res.json({
    message: "Authenticated!",
    identityId: req.user.identityId,
    deviceAddress: req.user.deviceAddress,
  });
});

// ─── Middleware de autenticação ───────────────────────────────────────────────
function requireAuth(req, res, next) {
  const authHeader = req.headers.authorization; // "Bearer <token>"
  const token = authHeader?.split(" ")[1];

  const session = sessions.get(token);
  if (!session) {
    return res.status(401).json({ error: "Unauthorized" });
  }

  req.user = session;
  next();
}

app.listen(3000, () => {
  console.log("Server running on http://localhost:3000");
  console.log("");
  console.log("Endpoints:");
  console.log("  GET  /auth/challenge  → gera o challenge para o QR code");
  console.log("  POST /auth/verify     → verifica a resposta do mobile");
  console.log("  GET  /api/profile     → rota protegida (exige Bearer token)");
});
