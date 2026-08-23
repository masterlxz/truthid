## 0.1.1

- Fix: `TRUTHID_ACCOUNT_CREATION_CODE` was stale since before the C8 fix (registries stopped being `immutable`) — the cascade migration only updated addresses in `FACTORY_IMMUTABLES`, not this bytecode blob. Any locally-computed smart account address (`computeSmartAccountAddress`) was wrong. Recompiled from the real `TruthIDAccount.sol` artifact and validated against the on-chain factory.

## 0.1.0

- Initial release.
- `TruthIDClient` — verifier role: generate a login challenge, verify the signed response from the phone.
- `TruthIDRequester` — cross-device requester role: `signMessage`, `signRequest`, `pin`, `vaultEdit` over the same LAN/dead-drop transport the mobile app uses.
