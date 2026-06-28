---
sidebar_position: 3
sidebar_label: Ruby
---

# Ruby SDK

Full API reference for [`truthid-sdk`](https://rubygems.org/gems/truthid-sdk) on RubyGems. New to TruthID? Start with the [Quickstart](/docs/quickstart) — this page is the detailed reference for every method and type once you're integrating for real.

## Installation

```bash
gem install truthid-sdk
```

Requires Ruby 3.0+.

## `TruthID::Client`

```ruby
require "truthid"

truthid = TruthID::Client.new  # defaults to network: "base-mainnet"
```

There's also a factory function, if you prefer it:

```ruby
truthid = TruthID.new_client  # equivalent to TruthID::Client.new
```

### Constructor

`TruthID::Client.new(network: "base-mainnet", rpc_url: nil)`

| Field | Type | Required | Description |
|-------|------|----------|--------------|
| `network` | `"base-sepolia"` or `"base-mainnet"` | No — defaults to `"base-mainnet"` | Which network to read contracts from |
| `rpc_url` | `String` or `nil` | No | Custom RPC endpoint. Defaults to the public Base RPC for the chosen network |

Like Python, `network` has a default here — you only need to pass it to override or to use the testnet. (The TypeScript SDK requires it explicitly, with no default.)

## Methods

### `create_challenge(origin)`

Creates a one-time challenge to embed in the QR code shown to the user.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `origin` | `String` | Your site's domain, e.g. `"yoursite.com"` |

**Returns** [`AuthChallenge`](#authchallenge)

```ruby
challenge = truthid.create_challenge("yoursite.com")
challenge.nonce      #=> "3f2e1a4b-..."
challenge.issued_at  #=> 1718000000000
```

:::tip[Store it, then delete it]
Keep the challenge server-side, keyed by `nonce`, until `verify_auth_response` runs — then delete it immediately. See [Nonce invalidation](#nonce-invalidation) below.
:::

**Building the QR code** — the mobile app expects this exact shape (`challenge.to_h` already produces the right camelCase keys):

```json
{
  "action": "truthid-auth",
  "challenge": { "type": "challenge", "nonce": "...", "issuedAt": 1718000000000, "origin": "yoursite.com" },
  "callbackUrl": "https://yoursite.com/auth/verify"
}
```

`callbackUrl` **must** use `https://` — the mobile app refuses to send the signed response to a plain `http://` URL.

---

### `verify_auth_response(challenge, response, ttl_ms: 30_000)`

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
| `ttl_ms:` *(optional)* | `Integer` | Max challenge age in ms. Default: `30_000` |

**Returns** [`VerifyAuthResult`](#verifyauthresult)

`AuthResponse.from_hash` builds it straight from the parsed JSON body — unlike the Python SDK, no manual field mapping needed:

```ruby
data = JSON.parse(request.body.read)  # { "approved" => ..., "nonce" => ..., "signature" => ..., "deviceAddress" => ... }

response = TruthID::AuthResponse.from_hash(data)
result = truthid.verify_auth_response(challenge, response)

if result.valid
  puts "Authenticated! Identity ID: #{result.identity_id}"
else
  puts "Failed: #{result.reason}"
end
```

**Failure reasons**

| `reason` | Cause |
|----------|-------|
| `"User rejected the login request"` | User tapped "Reject" on their phone |
| `"Challenge expired"` | More than `ttl_ms` ms have passed since `issued_at` |
| `"Nonce mismatch"` | Response nonce doesn't match the challenge |
| `"Invalid signature format"` | Signature is malformed |
| `"Signature does not match device address"` | Signature was not made by `device_address` |
| `"Device is not active or has been revoked"` | Device was revoked by the identity owner |

---

### `verify_session(session_hash)`

Checks whether a session hash is still valid (not revoked). Call this on subsequent requests after login to confirm the session hasn't been revoked from another device.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `session_hash` | `String` | `bytes32` hex string (`0x...`) |

**Returns** [`SessionInfo`](#sessioninfo)

```ruby
session = truthid.verify_session(session_hash)
if session.exists && !session.revoked
  # still logged in
end
```

---

### `check_device_status(device_pub_key)`

Looks up a device's current status on the blockchain.

**Parameters**

| Name | Type | Description |
|------|------|-------------|
| `device_pub_key` | `String` | Ethereum address of the device (`0x...`) |

**Returns** [`DeviceStatus`](#devicestatus)

```ruby
status = truthid.check_device_status(device_pub_key)
```

## Types

All of the following are in the `TruthID` module. `AuthChallenge` and `AuthResponse` are plain classes — their attributes follow normal Ruby snake_case (`issued_at`, `device_address`), and each has a conversion method (`to_h` / `from_hash`) at the boundary where it meets the camelCase JSON the mobile app actually sends and signs. `VerifyAuthResult`, `SessionInfo`, and `DeviceStatus` are `Struct`s, since they never cross the wire.

#### `AuthChallenge`

```ruby
class AuthChallenge
  attr_reader :type, :nonce, :issued_at, :origin

  # to_h => { "type" => ..., "nonce" => ..., "issuedAt" => ..., "origin" => ... }
end
```

#### `AuthResponse`

```ruby
class AuthResponse
  attr_reader :approved, :nonce, :signature, :device_address

  # self.from_hash(h) reads h["deviceAddress"] into device_address, etc.
end
```

#### `VerifyAuthResult`

```ruby
VerifyAuthResult = Struct.new(:valid, :identity_id, :device_address, :reason, keyword_init: true)
```

#### `SessionInfo`

```ruby
SessionInfo = Struct.new(:exists, :revoked, :identity_id, :device_pub_key, :created_at, keyword_init: true)
```

#### `DeviceStatus`

```ruby
DeviceStatus = Struct.new(:exists, :active, :label, :identity_id, :added_at, keyword_init: true)
```

## Security notes

### Nonce invalidation

Delete the challenge from your store **before** calling `verify_auth_response`, not after — deleting after leaves a race condition where the same signed response can be submitted twice within the TTL window.

```ruby
# Correct order
pending_challenges.delete(response.nonce)            # delete first
result = truthid.verify_auth_response(challenge, response)  # then verify
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

```ruby
# Testnet during development
truthid = TruthID::Client.new(network: "base-sepolia")

# Custom RPC instead of the public endpoint
truthid = TruthID::Client.new(network: "base-mainnet", rpc_url: "https://your-private-rpc.example.com")
```

Contract addresses for both networks are in [Smart contracts](/docs/intro#smart-contracts-base-mainnet-chain-8453).

## Session registration

On-chain session registration (`register_session`) is currently available only in the **TypeScript SDK**. The Ruby SDK does not yet implement this method.

If you need session registration from a Ruby backend, the recommended approach is to call the TypeScript example server as a sidecar, or wait for a future Ruby release. See the [TypeScript `registerSession` reference](/docs/sdk/typescript#registersessionparams) for how it works.

## Next steps

- [Quickstart](/docs/quickstart) — full walkthrough from install to first login
- [Full Sinatra example](https://github.com/masterlxz/truthid/blob/main/sdk/README.md#full-examples) with session tokens and a protected route
- [TypeScript SDK reference](/docs/sdk/typescript)
- [Python SDK reference](/docs/sdk/python)
