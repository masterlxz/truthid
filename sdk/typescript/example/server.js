const express = require("express");
const { randomUUID } = require("crypto");
const QRCode = require("qrcode");
const { TruthIDClient } = require("../dist");

const app = express();
app.use(express.json());

// Allow requests from the Tauri dev webview (localhost:1420) and any other local origin
app.use((req, res, next) => {
  res.header("Access-Control-Allow-Origin", "*");
  res.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
  res.header("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  if (req.method === "OPTIONS") return res.sendStatus(200);
  next();
});

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
// Body: { approved, nonce, signature, deviceAddress, sessionSignature? }
// sessionSignature is only present when the mobile is TruthID app v1.1+.
// If absent (old client), auth still works; the session just won't appear on-chain.
app.post("/auth/verify", async (req, res) => {
  const response = req.body;

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
    completedSessions.set(response.nonce, null); // signal rejection to poll endpoint
    return res.status(401).json({ error: result.reason });
  }

  // Create a simple session token (use JWT in production)
  const sessionToken = randomUUID();
  const sessionData = {
    identityId: result.identityId.toString(),
    deviceAddress: result.deviceAddress,
    token: sessionToken,
  };
  sessions.set(sessionToken, sessionData);
  completedSessions.set(response.nonce, sessionData); // signal approval to poll endpoint

  // Optional: register session on-chain via relayer so it appears in ActiveSessions.
  // Requires RELAYER_PRIVATE_KEY env var (funded wallet that pays gas on Base).
  // Gas cost is minimal — fractions of a cent per session on Base.
  let sessionHash = null;
  if (response.sessionSignature && process.env.RELAYER_PRIVATE_KEY) {
    try {
      const registered = await truthid.registerSession({
        nonce: response.nonce,
        identityId: result.identityId,
        devicePubKey: result.deviceAddress,
        sessionSignature: response.sessionSignature,
        relayerPrivateKey: process.env.RELAYER_PRIVATE_KEY,
      });
      sessionHash = registered.sessionHash;
    } catch (err) {
      // Non-fatal: auth succeeded, session just won't be on-chain
      console.error("registerSession failed:", err.message);
    }
  }

  res.json({
    token: sessionToken,
    identityId: result.identityId.toString(),
    ...(sessionHash && { sessionHash }),
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

// ─── Demo page ───────────────────────────────────────────────────────────────
app.get("/", (req, res) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TruthID Login Demo</title>
  <style>
    body { font-family: sans-serif; background: #0B0F14; color: #E6EDF3; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
    h1 { color: #4DD0E1; margin-bottom: 8px; }
    p { color: #9FB1C2; margin-bottom: 32px; }
    #qr-box { background: white; padding: 16px; border-radius: 12px; display: none; }
    #qr-box img { display: block; }
    #status { margin-top: 24px; font-size: 14px; color: #9FB1C2; }
    #result { margin-top: 16px; background: #111820; border: 1px solid #1F2630; border-radius: 8px; padding: 16px; display: none; font-family: monospace; font-size: 13px; max-width: 400px; word-break: break-all; }
    button { background: #4DD0E1; color: #0B0F14; border: none; padding: 12px 28px; border-radius: 8px; font-size: 15px; font-weight: bold; cursor: pointer; }
    button:hover { background: #34C3D6; }
    button:disabled { opacity: 0.5; cursor: default; }
  </style>
</head>
<body>
  <h1>TruthID Login Demo</h1>
  <p>Click the button, then scan the QR code with the TruthID mobile app.</p>
  <button id="btn" onclick="startLogin()">Generate Login QR</button>
  <div id="qr-box"><img id="qr" /></div>
  <div id="status"></div>
  <div id="result"></div>
  <script>
    async function startLogin() {
      const btn = document.getElementById('btn');
      const status = document.getElementById('status');
      const qrBox = document.getElementById('qr-box');
      const result = document.getElementById('result');
      btn.disabled = true;
      qrBox.style.display = 'none';
      result.style.display = 'none';
      status.textContent = 'Generating challenge…';

      const resp = await fetch('/auth/challenge');
      const payload = await resp.json();
      const nonce = payload.challenge.nonce;

      document.getElementById('qr').src = '/auth/qr/' + nonce;
      qrBox.style.display = 'block';
      status.textContent = 'Scan with TruthID mobile. Waiting for approval…';

      const interval = setInterval(async () => {
        const r = await fetch('/auth/poll/' + nonce);
        if (r.status === 200) {
          const data = await r.json();
          clearInterval(interval);
          status.textContent = '✅ Login approved!';
          result.style.display = 'block';
          result.innerHTML = '<b>Identity:</b> #' + data.identityId + '<br><b>Device:</b> ' + data.deviceAddress + '<br><b>Token:</b> ' + data.token;
          btn.disabled = false;
        } else if (r.status === 401) {
          clearInterval(interval);
          status.textContent = '❌ Login rejected.';
          btn.disabled = false;
        }
      }, 1500);
    }
  </script>
</body>
</html>`);
});

// ─── QR image endpoint: returns PNG generated server-side ────────────────────
app.get("/auth/qr/:nonce", async (req, res) => {
  const challenge = pendingChallenges.get(req.params.nonce);
  if (!challenge) return res.status(404).end();
  const host = req.headers.host ?? "localhost:3000";
  const payload = JSON.stringify({
    action: "truthid-auth",
    challenge,
    callbackUrl: `https://${host}/auth/verify`,
  });
  res.setHeader("Content-Type", "image/png");
  QRCode.toFileStream(res, payload, { width: 260, margin: 2 });
});

// ─── Poll endpoint for demo page ─────────────────────────────────────────────
const completedSessions = new Map(); // nonce → result
app.get("/auth/poll/:nonce", (req, res) => {
  const result = completedSessions.get(req.params.nonce);
  if (result === undefined) return res.status(204).end(); // still waiting
  if (result === null) return res.status(401).end();      // rejected
  completedSessions.delete(req.params.nonce);
  res.json(result);
});

app.listen(3000, () => {
  console.log("Server running on http://localhost:3000");
  console.log("");
  console.log("Endpoints:");
  console.log("  GET  /             → demo page with QR login");
  console.log("  GET  /auth/challenge  → generates the challenge for the QR code");
  console.log("  POST /auth/verify     → verifies the mobile response");
  console.log("  GET  /api/profile     → protected route (requires Bearer token)");
});
