---
sidebar_position: 2
sidebar_label: Python
---

# Python SDK

Full API reference for [`truthid-sdk`](https://pypi.org/project/truthid-sdk/) on PyPI. New to TruthID? Start with the [Quickstart](/docs/quickstart) — this page is the detailed reference for every method and type once you're integrating for real.

## Installation

```bash
pip install truthid-sdk
```

Requires Python 3.10+.

## `TruthIDClient`

```python
from truthid import TruthIDClient

truthid = TruthIDClient()  # defaults to network="base-mainnet"
```

### Constructor

`TruthIDClient(network: str = "base-mainnet", rpc_url: Optional[str] = None)`

| Field | Type | Required | Description |
|-------|------|----------|--------------|
| `network` | `"base-sepolia"` or `"base-mainnet"` | No — defaults to `"base-mainnet"` | Which network to read contracts from |
| `rpc_url` | `Optional[str]` | No | Custom RPC endpoint. Defaults to the public Base RPC for the chosen network |

Unlike the TypeScript SDK, `network` has a default here — you only need to pass it to override or to use the testnet.

## Methods

### `create_challenge(origin)`

Creates a one-time challenge to embed in the QR code shown to the user.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `origin` | `str` | Your site's domain, e.g. `"yoursite.com"` |

**Returns** [`AuthChallenge`](#authchallenge)

```python
challenge = truthid.create_challenge("yoursite.com")
# AuthChallenge(type="challenge", nonce="3f2e1a4b-...", issuedAt=1718000000000, origin="yoursite.com")
```

:::tip[Store it, then delete it]
Keep the challenge server-side, keyed by `nonce`, until `verify_auth_response` runs — then delete it immediately. See [Nonce invalidation](#nonce-invalidation) below.
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

### `verify_auth_response(challenge, response, ttl_ms=30_000)`

Verifies the signed response received from the user's phone. Runs six checks in sequence and stops at the first failure:

1. User approved (not rejected)
2. Challenge is within TTL (default: 30 seconds)
3. Nonce matches the original challenge
4. Cryptographic signature is valid
5. Device is registered and active on the blockchain
6. Retrieves the identity ID linked to this device

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `challenge` | [`AuthChallenge`](#authchallenge) | The challenge you created |
| `response` | [`AuthResponse`](#authresponse) | The response received from the phone |
| `ttl_ms` *(optional)* | `int` | Max challenge age in ms. Default: `30_000` |

**Returns** [`VerifyAuthResult`](#verifyauthresult)

`AuthResponse` has no `from_dict` helper — build it field by field from the parsed JSON body. Its fields are camelCase (matching the wire format), not snake_case:

```python
from truthid import AuthResponse

data = request.json  # { "approved": ..., "nonce": ..., "signature": ..., "deviceAddress": ... }

response = AuthResponse(
    approved=data["approved"],
    nonce=data["nonce"],
    signature=data["signature"],
    deviceAddress=data["deviceAddress"],
)

result = truthid.verify_auth_response(challenge, response)

if result.valid:
    print(f"Authenticated! Identity ID: {result.identity_id}")
else:
    print(f"Failed: {result.reason}")
```

**Failure reasons**

| `reason` | Cause |
|----------|-------|
| `"User rejected the login request"` | User tapped "Reject" on their phone |
| `"Challenge expired"` | More than `ttl_ms` ms have passed since `issuedAt` |
| `"Nonce mismatch"` | Response nonce doesn't match the challenge |
| `"Invalid signature format"` | Signature is malformed |
| `"Signature does not match device address"` | Signature was not made by `deviceAddress` |
| `"Device is not active or has been revoked"` | Device was revoked by the identity owner |

---

### `verify_session(session_hash)`

Checks whether a session hash is still valid (not revoked). Call this on subsequent requests after login to confirm the session hasn't been revoked from another device.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `session_hash` | `str` | `bytes32` hex string (`0x...`) |

**Returns** [`SessionInfo`](#sessioninfo)

```python
session = truthid.verify_session(session_hash)
if session.exists and not session.revoked:
    pass  # still logged in
```

---

### `check_device_status(device_pub_key)`

Looks up a device's current status on the blockchain.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `device_pub_key` | `str` | Ethereum address of the device (`0x...`) |

**Returns** [`DeviceStatus`](#devicestatus)

```python
status = truthid.check_device_status(device_pub_key)
```

## Types

All of the following are exported from `truthid`. `AuthChallenge` and `AuthResponse` use **camelCase** field names because they mirror the JSON shape the mobile app sends and signs directly — every other type follows normal Python snake_case, since it never crosses the wire.

#### `AuthChallenge`

```python
@dataclass
class AuthChallenge:
    type: str
    nonce: str
    issuedAt: int  # Unix timestamp in ms
    origin: str
```

#### `AuthResponse`

```python
@dataclass
class AuthResponse:
    approved: bool
    nonce: str
    signature: str      # secp256k1 signature, hex ("0x...")
    deviceAddress: str  # Ethereum address of the device key
```

#### `VerifyAuthResult`

```python
@dataclass
class VerifyAuthResult:
    valid: bool
    identity_id: Optional[int] = None
    device_address: Optional[str] = None
    reason: Optional[str] = None
```

#### `SessionInfo`

```python
@dataclass
class SessionInfo:
    exists: bool
    revoked: bool
    identity_id: Optional[int] = None
    device_pub_key: Optional[str] = None
    created_at: Optional[datetime] = None
```

#### `DeviceStatus`

```python
@dataclass
class DeviceStatus:
    exists: bool
    active: bool
    label: Optional[str] = None
    identity_id: Optional[int] = None
    added_at: Optional[datetime] = None
```

## Security notes

### Nonce invalidation

Delete the challenge from your store **before** calling `verify_auth_response`, not after — deleting after leaves a race condition where the same signed response can be submitted twice within the TTL window.

```python
# Correct order
del pending_challenges[response.nonce]          # delete first
result = truthid.verify_auth_response(...)       # then verify
```

### TTL

The default is 30 seconds, matching the mobile app's own challenge expiry. Lowering it is fine; raising it above 30 seconds has no effect, since the phone will already refuse an older challenge.

### HTTPS only

The phone `POST`s the signed response directly to your callback URL — the mobile app refuses non-`https://` URLs, and your endpoint still needs a valid TLS certificate for the connection to succeed.

## Networks

| Network | Chain ID | Description |
|---------|----------|--------------|
| `"base-sepolia"` | 84532 | Testnet — for development |
| `"base-mainnet"` | 8453 | Production (default) |

```python
# Testnet during development
truthid = TruthIDClient(network="base-sepolia")

# Custom RPC instead of the public endpoint
truthid = TruthIDClient(network="base-mainnet", rpc_url="https://your-private-rpc.example.com")
```

Contract addresses for both networks are in [Smart contracts](/docs/intro#smart-contracts-base-mainnet-chain-8453).

## Session registration

### `register_session(...)`

Registers a completed login session on-chain so it appears in the user's TruthID desktop app and can be individually revoked. Optional — auth still works without it — but enables the user to see and revoke active sessions.

**Why a relayer?** The mobile device key never holds ETH — it only signs messages. Gas is paid by a server-side relayer wallet you fund. On Base this costs fractions of a cent per session.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `nonce` | `str` | The nonce from the original `AuthChallenge` |
| `identity_id` | `int` | From `verify_auth_response` result |
| `device_pub_key` | `str` | From `verify_auth_response` result |
| `session_signature` | `str` | The session signature from the phone's response (`sessionSignature`) |
| `relayer_private_key` | `str` | Private key (`"0x..."`) of the funded relayer wallet |

**Returns** `RegisterSessionResult(tx_hash, session_hash)`

```python
# After verify_auth_response succeeds:
session_signature = response_body.get("sessionSignature")
if session_signature and os.environ.get("RELAYER_PRIVATE_KEY"):
    try:
        result = truthid.register_session(
            nonce=challenge.nonce,
            identity_id=auth_result.identity_id,
            device_pub_key=auth_result.device_address,
            session_signature=session_signature,
            relayer_private_key=os.environ["RELAYER_PRIVATE_KEY"],
        )
        print("Session registered on-chain:", result.session_hash)
    except Exception as e:
        print("Session registration failed (login still succeeded):", e)
```

:::tip[Non-blocking]
`register_session` failing does not affect the login — wrap it in a try/except and keep it out of the response path. If the relayer runs out of ETH, auth continues normally.
:::

**Setup** — fund a relayer wallet with a small amount of ETH on Base (0.01 ETH covers thousands of sessions):

```bash
RELAYER_PRIVATE_KEY=0x... python server.py
```

**Mobile compatibility** — `sessionSignature` is only present in TruthID mobile app v1.1+. Older clients don't send it; check for its presence before calling `register_session`.

## Next steps

- [Quickstart](/docs/quickstart) — full walkthrough from install to first login
- [Full Flask example](https://github.com/masterlxz/truthid/blob/main/sdk/README.md#full-examples) with session tokens and a protected route
- [TypeScript SDK reference](/docs/sdk/typescript)
- [Ruby SDK reference](/docs/sdk/ruby)
