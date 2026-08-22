## 0.1.0

- Initial release.
- `TruthIDClient` — verifier role: generate a login challenge, verify the signed response from the phone.
- `TruthIDRequester` — cross-device requester role: `signMessage`, `signRequest`, `pin`, `vaultEdit` over the same LAN/dead-drop transport the mobile app uses.
