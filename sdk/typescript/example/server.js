const express = require("express");
const { randomUUID } = require("crypto");
const { TruthIDClient } = require("../dist");

const app = express();
app.use(express.json());

const truthid = new TruthIDClient({ network: "base-mainnet" });

// In-memory storage (use Redis in production)
// Map: nonce → AuthChallenge
const pendingChallenges = new Map();
// Map: sessionToken → { identityId, deviceAddress }
const sessions = new Map();

// ─── Step 1: website requests a challenge to build the QR code ───────────────
// The QR must contain { action, challenge, callbackUrl } — the mobile app reads
// this directly, with no signaling server in between. callbackUrl must be
// https:// and reachable by the phone (not "localhost" — to test with a real
// phone, expose this server via ngrok or deploy it).
app.get("/auth/challenge", (req, res) => {
  const origin = req.headers.host ?? "localhost";
  const challenge = truthid.createChallenge(origin);

  // Store the challenge by nonce to retrieve it during verification
  pendingChallenges.set(challenge.nonce, challenge);

  // Auto-remove after 35s (slightly beyond the SDK's 30s TTL)
  setTimeout(() => pendingChallenges.delete(challenge.nonce), 35_000);

  res.json({
    action: "truthid-auth",
    challenge,
    callbackUrl: `https://${origin}/auth/verify`,
  });
});

// ─── Step 2: mobile signed → website posts the response here ─────────────────
app.post("/auth/verify", async (req, res) => {
  const response = req.body; // { approved, nonce, signature, deviceAddress }

  // Retrieve the original challenge by nonce
  const challenge = pendingChallenges.get(response.nonce);
  if (!challenge) {
    return res.status(400).json({ error: "Challenge not found or already used" });
  }

  // Remove the challenge to prevent replay: the same nonce cannot be used twice
  pendingChallenges.delete(response.nonce);

  // Call the SDK to verify everything: signature, TTL, device active on-chain
  const result = await truthid.verifyAuthResponse({ challenge, response });

  if (!result.valid) {
    return res.status(401).json({ error: result.reason });
  }

  // Create a simple session token (use JWT in production)
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

// ─── Protected route ──────────────────────────────────────────────────────────
app.get("/api/profile", requireAuth, (req, res) => {
  res.json({
    message: "Authenticated!",
    identityId: req.user.identityId,
    deviceAddress: req.user.deviceAddress,
  });
});

// ─── Authentication middleware ────────────────────────────────────────────────
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
  console.log("  GET  /auth/challenge  → generates the challenge for the QR code");
  console.log("  POST /auth/verify     → verifies the mobile response");
  console.log("  GET  /api/profile     → protected route (requires Bearer token)");
});
