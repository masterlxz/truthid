# TruthID SDK

Integrate passwordless, decentralized authentication into your app in minutes.

TruthID replaces passwords and social login with cryptographic device keys. Users authenticate by approving a login request on their phone — no password, no email, no third-party server.

---

## How It Works

There is no TruthID-operated server anywhere in this flow — not for signaling, not for relaying messages. Your backend talks directly to your own frontend (QR code) and your own `/auth/verify` endpoint receives a direct HTTPS request from the user's phone.

```
Your Backend          QR code (your frontend)        User's Phone
     |                         |                          |
     |── createChallenge() ────>|                          |
     |   (SDK, no network)     |                          |
     |   embeds challenge +    |                          |
     |   callbackUrl in QR     |                          |
     |                         |───── scan QR ───────────>|
     |                         |                          |── user approves
     |                         |                          |   and signs locally
     |<──────────── POST {callbackUrl} (HTTPS, direct) ────|
     |    (your /auth/verify)                              |
     |    verifyAuthResponse() [SDK]:                       |
     |    1. signature valid                                |
     |    2. device active on blockchain                    |
     |    3. challenge not expired                           |
     |                                                       |
     LOGIN OK — your frontend learns this however you already
     notify it of backend events (polling, SSE, your own WebSocket)
```

The SDK only does the parts that need cryptography or a blockchain read — building the challenge, verifying the signature, checking device status. It never makes a network call to deliver the challenge or receive the response; that travels directly between the QR code and the phone, and from the phone to your own backend.

---

## Installation

### TypeScript / Node.js

```bash
npm install truthid-sdk
```

Requires Node.js 16+.

### Python

```bash
pip install truthid-sdk
```

Requires Python 3.10+.

### Ruby

```bash
gem install truthid-sdk
```

Requires Ruby 3.0+.

---

## Quick Start

### TypeScript

```typescript
import { TruthIDClient } from "truthid-sdk";

const truthid = new TruthIDClient({ network: "base-mainnet" });

// 1. Create a challenge (embed this in the QR code)
const challenge = truthid.createChallenge("yoursite.com");

// 2. After the user approves on their phone, verify the response
const result = await truthid.verifyAuthResponse({ challenge, response });

if (result.valid) {
  console.log("Authenticated! Identity ID:", result.identityId);
} else {
  console.log("Failed:", result.reason);
}
```

### Python

```python
from truthid import TruthIDClient, AuthResponse

truthid = TruthIDClient()  # defaults to network="base-mainnet"

# 1. Create a challenge
challenge = truthid.create_challenge("yoursite.com")

# 2. Verify the response from the phone
result = truthid.verify_auth_response(challenge, response)

if result.valid:
    print(f"Authenticated! Identity ID: {result.identity_id}")
else:
    print(f"Failed: {result.reason}")
```

### Ruby

```ruby
require "truthid"

truthid = TruthID::Client.new  # defaults to network: "base-mainnet"

# 1. Create a challenge
challenge = truthid.create_challenge("yoursite.com")

# 2. Verify the response from the phone
result = truthid.verify_auth_response(challenge, response)

if result.valid
  puts "Authenticated! Identity ID: #{result.identity_id}"
else
  puts "Failed: #{result.reason}"
end
```

---

## API Reference

Full parameter tables, return types, and failure reasons for every method now live on the docs site — one detailed reference page per language:

- **[TypeScript reference](https://masterlxz.github.io/truthid/docs/sdk/typescript)**
- **[Python reference](https://masterlxz.github.io/truthid/docs/sdk/python)**
- **[Ruby reference](https://masterlxz.github.io/truthid/docs/sdk/ruby)**

Quick summary of what each client gives you:

| Method | Purpose |
|--------|---------|
| `createChallenge` / `create_challenge` | Create a one-time challenge to embed in the QR code |
| `verifyAuthResponse` / `verify_auth_response` | Verify the signed response from the user's phone (signature, TTL, device status) |
| `verifySession` / `verify_session` | Check whether a session hash is still valid (not revoked) |
| `checkDeviceStatus` / `check_device_status` | Look up a device's current status on the blockchain |

---

## Full Examples

### Express.js (TypeScript)

```typescript
import express from "express";
import { randomUUID } from "crypto";
import { TruthIDClient, AuthChallenge, AuthResponse } from "truthid-sdk";

const app = express();
app.use(express.json());

const truthid = new TruthIDClient({ network: "base-mainnet" });

// In production, use Redis with a TTL instead of an in-memory Map
const pendingChallenges = new Map<string, AuthChallenge>();
const sessions = new Map<string, { identityId: string; deviceAddress: string }>();

// Step 1: client requests a challenge to embed in the QR code.
// The frontend builds the QR from { action, challenge, callbackUrl } —
// callbackUrl must be https:// and reachable by the phone, not localhost.
app.get("/auth/challenge", (req, res) => {
  const challenge = truthid.createChallenge(req.hostname);
  pendingChallenges.set(challenge.nonce, challenge);
  setTimeout(() => pendingChallenges.delete(challenge.nonce), 35_000);
  res.json({
    action: "truthid-auth",
    challenge,
    callbackUrl: `https://${req.hostname}/auth/verify`,
  });
});

// Step 2: client sends the phone's response here
app.post("/auth/verify", async (req, res) => {
  const response: AuthResponse = req.body;
  const challenge = pendingChallenges.get(response.nonce);

  if (!challenge) {
    return res.status(400).json({ error: "Challenge not found or already used" });
  }

  // Delete immediately — prevents the same response being accepted twice
  pendingChallenges.delete(response.nonce);

  const result = await truthid.verifyAuthResponse({ challenge, response });

  if (!result.valid) {
    return res.status(401).json({ error: result.reason });
  }

  // In production, issue a JWT instead of a random token
  const token = randomUUID();
  sessions.set(token, {
    identityId: result.identityId!.toString(),
    deviceAddress: result.deviceAddress!,
  });

  res.json({ token, identityId: result.identityId!.toString() });
});

// Protected route
app.get("/api/profile", (req, res) => {
  const token = req.headers.authorization?.split(" ")[1];
  const session = sessions.get(token ?? "");
  if (!session) return res.status(401).json({ error: "Unauthorized" });
  res.json(session);
});

app.listen(3000);
```

### Flask (Python)

```python
import uuid
from flask import Flask, request, jsonify
from truthid import TruthIDClient, AuthResponse

app = Flask(__name__)
truthid = TruthIDClient()  # defaults to network="base-mainnet"

pending_challenges = {}  # nonce → AuthChallenge
sessions = {}            # token → { identity_id, device_address }

@app.get("/auth/challenge")
def get_challenge():
    challenge = truthid.create_challenge(request.host)
    pending_challenges[challenge.nonce] = challenge
    return jsonify({
        "action": "truthid-auth",
        "challenge": {"type": challenge.type, "nonce": challenge.nonce,
                       "issuedAt": challenge.issuedAt, "origin": challenge.origin},
        "callbackUrl": f"https://{request.host}/auth/verify",
    })

@app.post("/auth/verify")
def verify():
    data = request.json
    challenge = pending_challenges.pop(data.get("nonce", ""), None)
    if not challenge:
        return jsonify({"error": "Challenge not found or already used"}), 400

    response = AuthResponse(
        approved=data["approved"],
        nonce=data["nonce"],
        signature=data["signature"],
        deviceAddress=data["deviceAddress"],
    )
    result = truthid.verify_auth_response(challenge, response)

    if not result.valid:
        return jsonify({"error": result.reason}), 401

    token = str(uuid.uuid4())
    sessions[token] = {"identity_id": result.identity_id, "device_address": result.device_address}
    return jsonify({"token": token, "identity_id": result.identity_id})

@app.get("/api/profile")
def profile():
    token = request.headers.get("Authorization", "").removeprefix("Bearer ")
    session = sessions.get(token)
    if not session:
        return jsonify({"error": "Unauthorized"}), 401
    return jsonify(session)
```

### Sinatra (Ruby)

```ruby
require "sinatra"
require "json"
require "securerandom"
require "truthid"

truthid = TruthID::Client.new  # defaults to network: "base-mainnet"
pending_challenges = {}  # nonce → AuthChallenge
sessions = {}            # token → { identity_id:, device_address: }

get "/auth/challenge" do
  content_type :json
  challenge = truthid.create_challenge(request.host)
  pending_challenges[challenge.nonce] = challenge
  {
    action: "truthid-auth",
    challenge: challenge.to_h,
    callbackUrl: "https://#{request.host}/auth/verify"
  }.to_json
end

post "/auth/verify" do
  content_type :json
  data = JSON.parse(request.body.read)
  challenge = pending_challenges.delete(data["nonce"])
  halt 400, { error: "Challenge not found or already used" }.to_json unless challenge

  response = TruthID::AuthResponse.from_hash(data)
  result = truthid.verify_auth_response(challenge, response)

  halt 401, { error: result.reason }.to_json unless result.valid

  token = SecureRandom.uuid
  sessions[token] = { identity_id: result.identity_id, device_address: result.device_address }
  { token: token, identity_id: result.identity_id }.to_json
end

get "/api/profile" do
  content_type :json
  token = request.env["HTTP_AUTHORIZATION"]&.delete_prefix("Bearer ")
  session = sessions[token]
  halt 401, { error: "Unauthorized" }.to_json unless session
  session.to_json
end
```

---

## Session Registration (On-Chain Audit Trail)

After a successful login, you can register the session on-chain so it appears in `ActiveSessions` in the TruthID desktop app and can be individually revoked by the user.

### Why a relayer?

The mobile device key never holds ETH — it only signs messages. Gas must be paid by a server-side **relayer wallet** that you fund. On Base, this costs fractions of a cent per session.

### How it works

When the mobile approves a login, it produces two signatures:
1. **Auth signature** — `personal_sign(JSON.stringify(challenge))` — verified by `verifyAuthResponse`
2. **Session signature** — `personal_sign(keccak256(nonce))` — verified on-chain by the contract

Both use the same device key. The session hash (`keccak256(nonce)`) is derived independently by both the mobile and the server from the nonce already in the challenge — no extra round-trip needed.

### Setup

Fund a relayer wallet (any Ethereum key) with a small amount of ETH on Base (0.01 ETH covers thousands of sessions), then pass its private key via environment variable:

```bash
RELAYER_PRIVATE_KEY=0x... node server.js
```

### Code

```typescript
// After verifyAuthResponse succeeds:
if (response.sessionSignature && process.env.RELAYER_PRIVATE_KEY) {
  const { txHash, sessionHash, alreadyRegistered } = await truthid.registerSession({
    nonce: response.nonce,
    identityId: result.identityId!,
    devicePubKey: result.deviceAddress!,
    sessionSignature: response.sessionSignature,
    relayerPrivateKey: process.env.RELAYER_PRIVATE_KEY as `0x${string}`,
  });
  console.log(alreadyRegistered ? "Session already on-chain:" : "Session registered on-chain:", sessionHash);
}
```

`registerSession` is non-blocking for auth — if it fails (e.g. relayer has no ETH), the login still succeeds. Wrap it in a try/catch and log the error.

### Idempotency

TruthID mobile app v14.9.5+ creates the session on-chain itself (via a UserOperation, before it ever calls your callback). `registerSession` checks for this first: if the session already exists, it returns `{ alreadyRegistered: true, txHash: undefined, sessionHash }` without submitting a transaction — no relayer gas spent, no `SessionAlreadyExists` revert. `txHash` is only present when this call actually submitted the transaction.

### Mobile compatibility

`sessionSignature` is only present in TruthID mobile app v1.1+. Older clients don't send it; registrations just won't happen. The field is optional — check for its presence before calling `registerSession`.

---

## Security Notes

### Nonce invalidation (required)

Delete the challenge from your store **before** calling `verifyAuthResponse`. If you delete after, a race condition allows the same signed response to be submitted twice within the TTL window.

```typescript
// Correct order
pendingChallenges.delete(response.nonce);       // delete first
const result = await truthid.verifyAuthResponse(...); // then verify
```

### TTL

The default TTL is 30 seconds. This matches the mobile app's challenge expiry. You can lower it — raising it above 30 seconds doesn't help, as the mobile will already have rejected the challenge.

### Session tokens

The examples above use random UUIDs as session tokens. In production, use signed JWTs so you can validate sessions without a database lookup. Include `identityId` and `deviceAddress` in the payload.

### HTTPS only

Always serve your `/auth/*` endpoints over HTTPS. The phone POSTs the signed response directly to your `callbackUrl` — the TruthID mobile app refuses non-`https://` callback URLs, but your endpoint still needs a valid TLS cert for that to work.

---

## Networks

| Network | ID | Description |
|---------|-----|-------------|
| `"base-sepolia"` | 84532 | Testnet — for development |
| `"base-mainnet"` | 8453 | Production (default for Python and Ruby) |

The TypeScript SDK requires `network` explicitly — there is no default. Python and Ruby default to `"base-mainnet"`.

**Using testnet during development:**

```typescript
const truthid = new TruthIDClient({ network: "base-sepolia" });
```

```python
truthid = TruthIDClient(network="base-sepolia")
```

```ruby
truthid = TruthID::Client.new(network: "base-sepolia")
```

You can also pass a custom RPC URL:

```typescript
const truthid = new TruthIDClient({
  network: "base-mainnet",
  rpcUrl: "https://your-private-rpc.example.com",
});
```

---

## Smart Contracts

### Base Mainnet (production, chain ID 8453)

| Contract | Address |
|----------|---------|
| IdentityRegistry | `0x1313C576403F89eE265C880b33373d5DFB504cF2` |
| DeviceRegistry | `0x48e0862c43339f29ED850a59f5DBd08A4786EaDf` |
| RecoveryManager | `0x889d45C27264e1f59576FDb06722DF9Cf970CBFD` |
| SessionRegistry | `0x6531a5Ed42e077cf1b2D78d441248dC7a3ab9776` |

All contracts are verified on [Basescan](https://basescan.org).

### Base Sepolia (testnet, chain ID 84532)

| Contract | Address |
|----------|---------|
| IdentityRegistry | `0xDe7a0f1918Ee39cc1792e709Edde17e8ea858998` |
| DeviceRegistry | `0x2be6a81B22823510c7F3Fa93E70B85aAd4fB488d` |
| RecoveryManager | `0xbBe777145D32fdbf8A5878eAa3a21b5f1A7d67F7` |
| SessionRegistry | `0xbf8b940dDC3754D06ee5281209Bd3dD58852BF65` |

All contracts are verified on [Basescan](https://sepolia.basescan.org).
