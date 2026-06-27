---
sidebar_position: 1
sidebar_label: TypeScript
---

# TypeScript SDK

Full API reference for [`truthid-sdk`](https://www.npmjs.com/package/truthid-sdk) on npm. New to TruthID? Start with the [Quickstart](/docs/quickstart) — this page is the detailed reference for every method and type once you're integrating for real.

## Installation

```bash
npm install truthid-sdk
```

Requires Node.js 16+.

## `TruthIDClient`

```typescript
import { TruthIDClient } from "truthid-sdk";

const truthid = new TruthIDClient({ network: "base-mainnet" });
```

### Constructor

`new TruthIDClient(config: TruthIDClientConfig)`

| Field | Type | Required | Description |
|-------|------|----------|--------------|
| `network` | `"base-sepolia" \| "base-mainnet"` | Yes — no default | Which network to read contracts from |
| `rpcUrl` | `string` | No | Custom RPC endpoint. Defaults to the public Base RPC for the chosen network |

Unlike the Python and Ruby SDKs, `network` has no default here — you must pass it explicitly every time you construct a client.

## Methods

### `createChallenge(origin)`

Creates a one-time challenge to embed in the QR code shown to the user.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `origin` | `string` | Your site's domain, e.g. `"yoursite.com"` |

**Returns** [`AuthChallenge`](#authchallenge)

```typescript
const challenge = truthid.createChallenge("yoursite.com");
// {
//   type: "challenge",
//   nonce: "3f2e1a4b-...",
//   issuedAt: 1718000000000,
//   origin: "yoursite.com"
// }
```

:::tip[Store it, then delete it]
Keep the challenge server-side, keyed by `nonce`, until `verifyAuthResponse` runs — then delete it immediately. See [Nonce invalidation](#nonce-invalidation) below.
:::

**Building the QR code** — the mobile app expects this exact shape:

```json
{
  "action": "truthid-auth",
  "challenge": { "type": "challenge", "nonce": "...", "issuedAt": 1718000000000, "origin": "yoursite.com" },
  "callbackUrl": "https://yoursite.com/auth/verify"
}
```

`callbackUrl` **must** use `https://` — the mobile app refuses to send the signed response to a plain `http://` URL.

---

### `verifyAuthResponse(params)`

Verifies the signed response received from the user's phone. Runs six checks in sequence and stops at the first failure:

1. User approved (not rejected)
2. Challenge is within TTL (default: 30 seconds)
3. Nonce matches the original challenge
4. Cryptographic signature is valid
5. Device is registered and active on the blockchain
6. Retrieves the identity ID linked to this device

**Parameters** ([`VerifyAuthParams`](#verifyauthparams))

| Name | Type | Description |
|------|------|-------------|
| `challenge` | [`AuthChallenge`](#authchallenge) | The challenge you created |
| `response` | [`AuthResponse`](#authresponse) | The response received from the phone |
| `ttlMs` *(optional)* | `number` | Max challenge age in ms. Default: `30_000` |

**Returns** [`VerifyAuthResult`](#verifyauthresult)

```typescript
const result = await truthid.verifyAuthResponse({ challenge, response });

if (result.valid) {
  console.log("Authenticated! Identity ID:", result.identityId);
} else {
  console.log("Failed:", result.reason);
}
```

**Failure reasons**

| `reason` | Cause |
|----------|-------|
| `"User rejected the login request"` | User tapped "Reject" on their phone |
| `"Challenge expired"` | More than `ttlMs` ms have passed since `issuedAt` |
| `"Nonce mismatch"` | Response nonce doesn't match the challenge |
| `"Invalid signature format"` | Signature is malformed |
| `"Signature does not match device address"` | Signature was not made by `deviceAddress` |
| `"Device is not active or has been revoked"` | Device was revoked by the identity owner |

---

### `verifySession(sessionHash)`

Checks whether a session hash is still valid (not revoked). Call this on subsequent requests after login to confirm the session hasn't been revoked from another device.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `sessionHash` | `string` | `bytes32` hex string (`0x...`) |

**Returns** [`SessionInfo`](#sessioninfo)

```typescript
const session = await truthid.verifySession(sessionHash);
if (session.exists && !session.revoked) {
  // still logged in
}
```

---

### `checkDeviceStatus(devicePubKey)`

Looks up a device's current status on the blockchain.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `devicePubKey` | `string` | Ethereum address of the device (`0x...`) |

**Returns** [`DeviceStatus`](#devicestatus)

```typescript
const status = await truthid.checkDeviceStatus(devicePubKey);
```

## Types

All of the following are exported from `truthid-sdk`.

```typescript
type Network = "base-sepolia" | "base-mainnet";
```

#### `AuthChallenge`

```typescript
interface AuthChallenge {
  type: "challenge";
  nonce: string;
  issuedAt: number;   // Unix timestamp in ms
  origin: string;
}
```

#### `AuthResponse`

```typescript
interface AuthResponse {
  approved: boolean;
  nonce: string;
  signature: string;     // secp256k1 signature, hex ("0x...")
  deviceAddress: string; // Ethereum address of the device key
}
```

#### `VerifyAuthParams`

```typescript
interface VerifyAuthParams {
  challenge: AuthChallenge;
  response: AuthResponse;
  ttlMs?: number; // default: 30_000
}
```

#### `VerifyAuthResult`

```typescript
interface VerifyAuthResult {
  valid: boolean;
  identityId?: bigint;
  deviceAddress?: string;
  reason?: string;
}
```

#### `SessionInfo`

```typescript
interface SessionInfo {
  exists: boolean;
  revoked: boolean;
  identityId?: bigint;
  devicePubKey?: string;
  createdAt?: Date;
}
```

#### `DeviceStatus`

```typescript
interface DeviceStatus {
  exists: boolean;
  active: boolean;
  label?: string;
  identityId?: bigint;
  addedAt?: Date;
}
```

## Security notes

### Nonce invalidation

Delete the challenge from your store **before** calling `verifyAuthResponse`, not after — deleting after leaves a race condition where the same signed response can be submitted twice within the TTL window.

```typescript
// Correct order
pendingChallenges.delete(response.nonce);             // delete first
const result = await truthid.verifyAuthResponse(...);  // then verify
```

### TTL

The default is 30 seconds, matching the mobile app's own challenge expiry. Lowering it is fine; raising it above 30 seconds has no effect, since the phone will already refuse an older challenge.

### HTTPS only

The phone `POST`s the signed response directly to your `callbackUrl` — the mobile app refuses non-`https://` URLs, and your endpoint still needs a valid TLS certificate for the connection to succeed.

## Networks

| Network | Chain ID | Description |
|---------|----------|--------------|
| `"base-sepolia"` | 84532 | Testnet — for development |
| `"base-mainnet"` | 8453 | Production |

```typescript
// Testnet during development
const truthid = new TruthIDClient({ network: "base-sepolia" });

// Custom RPC instead of the public endpoint
const truthid = new TruthIDClient({
  network: "base-mainnet",
  rpcUrl: "https://your-private-rpc.example.com",
});
```

Contract addresses for both networks are in [Smart contracts](/docs/intro#smart-contracts-base-mainnet-chain-8453).

## Next steps

- [Quickstart](/docs/quickstart) — full walkthrough from install to first login
- [Full Express.js example](https://github.com/masterlxz/truthid/blob/main/sdk/README.md#full-examples) with session tokens and a protected route
- [Python SDK reference](/docs/sdk/python)
- Ruby reference — coming soon
