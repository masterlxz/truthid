# TruthID

Decentralized authentication that replaces "Login with Google/Apple/Microsoft." Users own their identity through a blockchain wallet and authenticate with trusted devices — no password, no email, no third-party identity provider.

```
Your Backend          QR code (your frontend)        User's Phone
     |                         |                          |
     |── createChallenge() ────>|                          |
     |   embeds challenge +    |                          |
     |   callbackUrl in QR     |                          |
     |                         |───── scan QR ───────────>|
     |                         |                          |── user approves
     |                         |                          |   and signs locally
     |<──────────── POST {callbackUrl} (HTTPS, direct) ────|
     |    verifyAuthResponse() [SDK]:                       |
     |    signature valid + device active on-chain          |
     |                                                       |
     LOGIN OK
```

No TruthID-operated server sits in this path — the challenge travels inside the QR code, and the signed response goes straight from the phone to your own backend over HTTPS.

## Why

Centralized identity providers create account lockouts, data collection, and a single point of failure. TruthID gives users sovereignty over their own identity (a wallet they control) while giving integrators a simple SDK to verify logins against a public blockchain. See [`CONTEXT.md`](CONTEXT.md) for the full product rationale.

## How it works

- **Identity**: a username bound to a controller wallet, created on-chain (`IdentityRegistry`).
- **Trusted devices**: each device (desktop, phone) generates its own keypair locally — private keys never leave the device (Android Keystore / iOS Secure Enclave / Windows TPM / Linux Keyring). Devices are registered on-chain (`DeviceRegistry`) via a commit-reveal scheme to prevent front-running.
- **Login**: a website embeds a signed challenge directly in a QR code along with a callback URL. The user's phone scans it, signs locally, and POSTs the response straight to that callback. The integrator's backend verifies the signature and device status on-chain using a TruthID SDK.
- **Sessions**: only a `keccak256` hash of session data is stored on-chain (`SessionRegistry`) — what the hash represents stays local to the user's device. Revocation (single session or all sessions) is a single on-chain call.
- **Recovery**: identities can configure M-of-N guardians (default 3-of-5) to recover a lost controller wallet, with a 7-day timelock before the recovery takes effect (`RecoveryManager`).

## Architecture

| Component | Stack | Path |
|---|---|---|
| Smart contracts | Solidity (Foundry) | [`contracts/`](contracts/) |
| Desktop app | Tauri + Rust + React + TypeScript | [`desktop/`](desktop/) |
| Mobile app | Flutter | [`mobile/`](mobile/) |
| SDKs | TypeScript, Python, Ruby | [`sdk/`](sdk/) |
| E2E integration tests | viem + tsx, against local Anvil | [`integration/`](integration/) |

There is no relay, signaling server, or backend operated by TruthID — every off-chain message either travels inside a QR code or goes directly between the user's phone and the integrator's own backend.

## Smart contracts (Base Mainnet, chain 8453)

| Contract | Address |
|---|---|
| `IdentityRegistry` | [`0x1313C576403F89eE265C880b33373d5DFB504cF2`](https://basescan.org/address/0x1313C576403F89eE265C880b33373d5DFB504cF2) |
| `DeviceRegistry` | [`0x48e0862c43339f29ED850a59f5DBd08A4786EaDf`](https://basescan.org/address/0x48e0862c43339f29ED850a59f5DBd08A4786EaDf) |
| `RecoveryManager` | [`0x889d45C27264e1f59576FDb06722DF9Cf970CBFD`](https://basescan.org/address/0x889d45C27264e1f59576FDb06722DF9Cf970CBFD) |
| `SessionRegistry` | [`0x6531a5Ed42e077cf1b2D78d441248dC7a3ab9776`](https://basescan.org/address/0x6531a5Ed42e077cf1b2D78d441248dC7a3ab9776) |

All four contracts are immutable (no upgrade proxy) and verified on Basescan. Base Sepolia testnet addresses and a full address reference are in [`sdk/README.md`](sdk/README.md#smart-contracts).

## Integrating TruthID into your app

Use one of the official SDKs — they wrap challenge creation, signature verification, and on-chain reads so your backend never talks to the blockchain directly:

| SDK | Package |
|---|---|
| TypeScript | [`truthid-sdk`](https://www.npmjs.com/package/truthid-sdk) on npm |
| Python | [`truthid-sdk`](https://pypi.org/project/truthid-sdk/) on PyPI |
| Ruby | [`truthid-sdk`](https://rubygems.org/gems/truthid-sdk) on RubyGems |

Full API reference, quickstart, and framework examples (Express / Flask / Sinatra): [`sdk/README.md`](sdk/README.md).

## Building from source

**Smart contracts** ([Foundry](https://book.getfoundry.sh/)):
```
cd contracts
forge build
forge test
```

**Desktop app** (Tauri + React, runs in Docker to avoid host toolchain setup):
```
cd desktop
./dev.sh
```

**Mobile app** (Flutter):
```
cd mobile
flutter pub get
flutter run
```

**E2E integration tests** (spin up a local Anvil chain and run the full identity → device → login flow):
```
cd integration
npm install
npx tsx e2e.ts
```

## Security

- The four contracts went through a manual security review (no automated tooling) covering access control, reentrancy, front-running, timestamp dependence, DoS, and input validation. All findings were fixed before the mainnet deploy — see the audit table in [`PROJECT_STATE.md`](PROJECT_STATE.md), section "Fase 6".
- Device private keys never leave the device and never touch any server.
- This project has **not** undergone a third-party professional audit. Treat it as early-stage software.

If you find a vulnerability, please report it privately via this repository's GitHub Security tab rather than opening a public issue.

## License

MIT — see [`LICENSE`](LICENSE).
