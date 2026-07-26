---
sidebar_position: 4
sidebar_label: Dart
---

# Dart SDK

Full API reference for [`truthid_sdk`](https://pub.dev/packages/truthid_sdk) on pub.dev. New to TruthID? Start with the [Quickstart](/docs/quickstart) — this page is the detailed reference for every method and type once you're integrating for real.

Unlike the TypeScript/Python/Ruby SDKs — which are all **verifier**-only (the role a website's backend plays) — this package has two independent roles in one import:

- **`TruthIDClient`** — the verifier, same role as the other 3 SDKs. For a backend written in Dart.
- **`TruthIDRequester`** — a Dart-only role: request a signature, a transaction execution, or a file pin from the user's TruthID mobile app, over the same LAN/dead-drop transport the mobile app itself uses. For any Flutter (mobile or desktop) app, or a plain Dart backend, that wants to be the requesting side of a cross-device flow — no TruthID-operated server involved, either way.

Pure Dart — no `package:flutter` dependency. Works in Flutter apps and plain Dart backends alike.

## Installation

```yaml
dependencies:
  truthid_sdk: ^0.1.0
```

## `TruthIDClient` (verifier)

```dart
import 'package:truthid_sdk/truthid_sdk.dart';

final truthid = TruthIDClient(network: Network.baseMainnet);
```

### Constructor

`TruthIDClient({required Network network, String? rpcUrl})`

| Field | Type | Required | Description |
|-------|------|----------|--------------|
| `network` | `Network.baseSepolia` or `Network.baseMainnet` | Yes — no default | Which network to read contracts from |
| `rpcUrl` | `String?` | No | Custom RPC endpoint. Defaults to the public Base RPC for the chosen network |

### `createChallenge(origin)`

Creates a one-time challenge to embed in the QR code shown to the user.

**Returns** [`AuthChallenge`](#authchallenge)

```dart
final challenge = truthid.createChallenge('yoursite.com');
```

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

### `verifyAuthResponse(challenge, response, {ttlMs})`

Verifies the signed response received from the user's phone. Runs six checks in sequence and stops at the first failure — same order as the other 3 SDKs:

1. User approved (not rejected)
2. Challenge is within TTL (default: 30 seconds)
3. Nonce matches the original challenge
4. Cryptographic signature is valid
5. Device is registered and active on the blockchain
6. Retrieves the identity ID linked to this device

**Returns** [`VerifyAuthResult`](#verifyauthresult)

```dart
final result = await truthid.verifyAuthResponse(challenge, response);
if (result.valid) {
  print('Authenticated! Identity ID: ${result.identityId}');
} else {
  print('Failed: ${result.reason}');
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

### `verifySession(hash)`

Checks whether a session hash is still valid (not revoked).

**Returns** [`SessionInfo`](#sessioninfo)

```dart
final session = await truthid.verifySession(sessionHash);
if (session.exists && !session.revoked) {
  // still logged in
}
```

---

### `checkDeviceStatus(devicePubKey)`

Looks up a device's current status on the blockchain. **Returns** [`DeviceStatus`](#devicestatus).

---

### `computeSmartAccountAddress(ledgerAddress, {index})`

Predicts a user's smart account (controller) address via `CREATE2` — pure local computation, no RPC call and no server involved.

```dart
final smartAccount = truthid.computeSmartAccountAddress(ledgerAddress);
```

A standalone function is also exported for when you don't need a full client instance:

```dart
import 'package:truthid_sdk/truthid_sdk.dart' show computeSmartAccountAddress, Network;

final smartAccount = computeSmartAccountAddress(ledgerAddress, Network.baseMainnet);
```

## `TruthIDRequester` (cross-device requester)

```dart
final requester = TruthIDRequester();
```

Request a signature, a transaction execution, or a file pin from the user's phone — you show a QR code, the user scans it with the TruthID mobile app, approves or rejects, and the answer comes back over the same transport the mobile app itself uses for every other cross-device flow (a local-network sweep first, an IPFS/IPNS dead-drop as the fallback). No relayer, no TruthID server, no polling endpoint for you to host.

Each method returns a [`PendingRequest`](#pendingrequestt) **immediately** — the QR payload is ready to render right away; `result` is a `Future` that resolves once the phone answers or the request expires.

:::info[Cross-device only, 3 flows]
Deep-link transport (same device, no QR) is out of scope — it would require your app to register its own URI scheme, which is platform-specific and outside what a pure-Dart package can automate. `vault-edit` (proposing a new credential to the user's Vault) is also out of scope for now — see [What's not covered yet](#whats-not-covered-yet).
:::

### `signMessage({appName, purpose, timeout})`

Asks the phone to sign an arbitrary short message — the actual string signed is always `'TruthID Message Signing: $appName:$purpose'`, reconstructed by the mobile app itself; you never choose the raw bytes.

| Name | Type | Required | Description |
|------|------|----------|--------------|
| `appName` | `String` | Yes | Shown to the user on the approval screen |
| `purpose` | `String` | Yes | 1-64 chars, `[A-Za-z0-9_.-]+` — shown to the user, part of the signed message |
| `timeout` | `Duration` | No — default 3 minutes | How long the QR stays valid |

**Returns** `PendingRequest<`[`SignMessageResult`](#signmessageresult)`>`

```dart
final pending = requester.signMessage(appName: 'My App', purpose: 'login');
showQrCode(pending.qrPayload); // your own QR widget, e.g. qr_flutter

final result = await pending.result;
if (result.delivered && result.data!.status == 'signed') {
  print('Signature: ${result.data!.signature}');
}
```

---

### `signRequest({appName, dest, callData, functionSignature, value, timeout})`

Asks the phone to execute an arbitrary contract call **from the user's smart account** — the phone builds, signs, and submits the `UserOperation` itself (the smart account pays its own gas). Use this for anything beyond a plain signature: token transfers, contract interactions, anything `execute()` can reach.

| Name | Type | Required | Description |
|------|------|----------|--------------|
| `appName` | `String` | Yes | Shown to the user |
| `dest` | `String` | Yes | Destination contract address (`0x...`) |
| `callData` | `String` | Yes | ABI-encoded call data (`0x...`) |
| `functionSignature` | `String` | Yes | e.g. `"transfer(address,uint256)"` — shown to the user for verification |
| `value` | `String` | No — default `"0"` | Wei to send, as a decimal string |
| `timeout` | `Duration` | No — default 3 minutes | |

**Returns** `PendingRequest<`[`SignRequestResult`](#signrequestresult)`>`

```dart
final pending = requester.signRequest(
  appName: 'My App',
  dest: tokenAddress,
  callData: encodedTransferCall,
  functionSignature: 'transfer(address,uint256)',
);
final result = await pending.result;
if (result.delivered && result.data!.status == 'executed') {
  print('Transaction hash: ${result.data!.transactionHash}');
}
```

:::tip[This can take longer than the other two]
The phone doesn't just sign here — it submits the UserOperation through a bundler and waits for the receipt before answering. Budget up to a minute of extra wait after the user approves.
:::

---

### `pin({appName, content, timeout})`

Asks the phone to pin arbitrary bytes to its configured IPFS providers. Two phases under the hood, both handled for you: the encrypted `content` is pushed to the phone over the LAN first (there's no dead-drop for this phase — the phone only starts listening once it scans the QR, so this keeps retrying the push in the background until it lands or the request expires); once the phone has it, the usual result race (LAN + dead-drop) delivers the pin result.

| Name | Type | Required | Description |
|------|------|----------|--------------|
| `appName` | `String` | Yes | Shown to the user |
| `content` | `Uint8List` | Yes | The bytes to pin |
| `timeout` | `Duration` | No — default 3 minutes | |

**Returns** `PendingRequest<`[`PinResult`](#pinresult)`>`

```dart
final pending = requester.pin(appName: 'My App', content: fileBytes);
final result = await pending.result;
if (result.delivered && result.data!.status == 'pinned') {
  print('CID: ${result.data!.cid}');
}
```

### What's not covered yet

- **Deep-link (same-device) transport** — requires the host app to register its own URI scheme.
- **`vault-edit`** (proposing a new Vault credential) — more specialized (password-manager-style integrations) and has no response phase at all. May be added in a future release.

## Types

### Verifier types

All exported from `package:truthid_sdk/truthid_sdk.dart`.

#### `Network`

```dart
enum Network { baseSepolia, baseMainnet }
```

#### `AuthChallenge`

```dart
class AuthChallenge {
  final String type;      // always "challenge"
  final String nonce;
  final int issuedAt;      // Unix timestamp in ms
  final String origin;
}
```

#### `AuthResponse`

```dart
class AuthResponse {
  final bool approved;
  final String nonce;
  final String signature;          // secp256k1 signature, hex ("0x...")
  final String deviceAddress;      // Ethereum address of the device key
  final String? sessionSignature;  // personal_sign over keccak256(nonce) — always sent alongside signature
}
```

#### `VerifyAuthResult`

```dart
class VerifyAuthResult {
  final bool valid;
  final BigInt? identityId;
  final String? deviceAddress;
  final String? reason;
}
```

#### `SessionInfo`

```dart
class SessionInfo {
  final bool exists;
  final bool revoked;
  final BigInt? identityId;
  final String? devicePubKey;
  final DateTime? createdAt;
}
```

#### `DeviceStatus`

```dart
class DeviceStatus {
  final bool exists;
  final bool active;
  final String? label;
  final BigInt? identityId;
  final DateTime? addedAt;
}
```

### Requester types

#### `PendingRequest<T>`

```dart
class PendingRequest<T> {
  final String qrPayload;                    // JSON, ready to render as a QR code
  final String sessionId;
  final DateTime expiresAt;
  final Future<TransportResult<T>> result;
}
```

#### `TransportResult<T>`

```dart
class TransportResult<T> {
  final bool delivered; // false = expired with no answer
  final T? data;        // present only when delivered is true
}
```

#### `SignMessageResult`

```dart
class SignMessageResult {
  final String status; // 'signed' | 'rejected'
  final String? message;
  final String? signature;
}
```

#### `SignRequestResult`

```dart
class SignRequestResult {
  final String status; // 'executed' | 'failed' | 'rejected'
  final String? userOpHash;
  final String? transactionHash;
  final String? error;
}
```

#### `PinResult`

```dart
class PinResult {
  final String status; // 'pinned' | 'failed' | 'rejected'
  final String? cid;
  final String? contentHash;
  final List<String>? providersOk;
  final List<String>? providersFailed;
  final String? error;
}
```

## Security notes

### Nonce invalidation

Delete the challenge from your store **before** calling `verifyAuthResponse`, not after — deleting after leaves a race condition where the same signed response can be submitted twice within the TTL window.

### TTL

The default is 30 seconds, matching the mobile app's own challenge expiry.

### HTTPS only

The phone `POST`s the signed response directly to your `callbackUrl` — the mobile app refuses non-`https://` URLs, and your endpoint still needs a valid TLS certificate for the connection to succeed.

## Networks

| Network | Chain ID | Description |
|---------|----------|--------------|
| `Network.baseSepolia` | 84532 | Testnet — for development |
| `Network.baseMainnet` | 8453 | Production |

Contract addresses for both networks are in [Smart contracts](/docs/intro#smart-contracts-base-mainnet-chain-8453).

## Session visibility — nothing to do

Completed logins (via `TruthIDClient.verifyAuthResponse`, or via `TruthIDRequester.signRequest`) already show up in the user's TruthID mobile/desktop apps and can be individually revoked from there — the phone registers sessions on-chain itself. If you want to double-check a session landed on-chain, derive its hash from the nonce and call `verifySession`:

```dart
import 'package:web3dart/crypto.dart' show keccak256;
import 'dart:convert';

final sessionHash = '0x' + keccak256(Uint8List.fromList(utf8.encode(nonce)))
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();
final session = await truthid.verifySession(sessionHash);
```

## Next steps

- [Quickstart](/docs/quickstart) — full walkthrough from install to first login
- [TypeScript SDK reference](/docs/sdk/typescript)
- [Python SDK reference](/docs/sdk/python)
- [Ruby SDK reference](/docs/sdk/ruby)
