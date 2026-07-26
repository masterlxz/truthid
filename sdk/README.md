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

### Dart / Flutter

```yaml
dependencies:
  truthid_sdk: ^0.1.0
```

Pure Dart, no `package:flutter` dependency — works in Flutter apps (mobile or desktop) and plain Dart backends alike. Unlike the other three, this one also ships a second role: `TruthIDRequester`, for requesting a signature/transaction/pin from the user's phone directly — see the [Dart reference](https://masterlxz.github.io/truthid/docs/sdk/dart) for details.

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

### Dart

```dart
import 'package:truthid_sdk/truthid_sdk.dart';

final truthid = TruthIDClient(network: Network.baseMainnet);

// 1. Create a challenge (embed this in the QR code)
final challenge = truthid.createChallenge('yoursite.com');

// 2. After the user approves on their phone, verify the response
final result = await truthid.verifyAuthResponse(challenge, response);

if (result.valid) {
  print('Authenticated! Identity ID: ${result.identityId}');
} else {
  print('Failed: ${result.reason}');
}
```

---

## API Reference

Full parameter tables, return types, and failure reasons for every method now live on the docs site — one detailed reference page per language:

- **[TypeScript reference](https://masterlxz.github.io/truthid/docs/sdk/typescript)**
- **[Python reference](https://masterlxz.github.io/truthid/docs/sdk/python)**
- **[Ruby reference](https://masterlxz.github.io/truthid/docs/sdk/ruby)**
- **[Dart reference](https://masterlxz.github.io/truthid/docs/sdk/dart)** — verifier (`TruthIDClient`) and cross-device requester (`TruthIDRequester`)

Quick summary of what each client gives you:

| Method | Purpose |
|--------|---------|
| `createChallenge` / `create_challenge` | Create a one-time challenge to embed in the QR code |
| `verifyAuthResponse` / `verify_auth_response` | Verify the signed response from the user's phone (signature, TTL, device status) |
| `verifySession` / `verify_session` | Check whether a session hash is still valid (not revoked) |
| `checkDeviceStatus` / `check_device_status` | Look up a device's current status on the blockchain |

The Dart SDK additionally exports `TruthIDRequester`, with no equivalent in the other three — see [Dart reference](https://masterlxz.github.io/truthid/docs/sdk/dart#truthidrequester-cross-device-requester).

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

## Session Visibility — Nothing To Do

Completed logins already show up in the user's TruthID mobile/desktop apps and can be individually revoked from there. The phone registers the session on-chain itself (via a UserOperation) before it ever calls your callback URL — there's no relayer to fund, no server-side registration step, and no gas for your backend to pay.

If you want to double-check a session landed on-chain, derive its hash from the nonce (`keccak256(nonce)`, the same value the contract uses as the session identifier) and call `verifySession`:

```typescript
import { keccak256, toBytes } from "viem";

const sessionHash = keccak256(toBytes(response.nonce));
const session = await truthid.verifySession(sessionHash);
if (session.exists && !session.revoked) {
  // confirmed on-chain
}
```

### Predicting the smart account address

Every SDK also exports `computeSmartAccountAddress` (`compute_smart_account_address` in Python/Ruby/Dart) — a pure, local `CREATE2` computation that predicts a user's smart account address from their owner key, with no RPC call and no server involved. Useful for showing a deposit address before the account has ever been used on-chain. See each language's SDK reference for details.

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

The TypeScript and Dart SDKs require `network` explicitly — there is no default. Python and Ruby default to `"base-mainnet"`.

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
| IdentityRegistry | `0xC11426fd1cB103bC56dD3263325b34f2AcEe9903` |
| DeviceRegistry | `0x4Fd53d70553df00D42c015EB35E2626cB80b1614` |
| RecoveryManager | `0x1d51daD35Bd3562f8B56B334a9B8637873fE40e9` |
| SessionRegistry | `0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df` |

All contracts are verified on [Basescan](https://basescan.org).

### Base Sepolia (testnet, chain ID 84532)

| Contract | Address |
|----------|---------|
| IdentityRegistry | `0x7582E1c55fAFF19619A6c0a8b6575855d4e933d0` |
| DeviceRegistry | `0x867EA636FDF324B0Cc4a631C70421580e2Bbe91c` |
| RecoveryManager | `0xC60AE3D7Fc7991A48B780E3bF2838027079204Ce` |
| SessionRegistry | `0xFE49Cec3a927136f7F18E521BF1547f00b09B17f` |

All contracts are verified on [Basescan](https://sepolia.basescan.org).
