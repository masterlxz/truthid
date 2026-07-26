# truthid_sdk

TruthID passwordless, decentralized authentication SDK for Dart/Flutter.

Integrate passwordless, decentralized authentication into your app in minutes — no TruthID-operated server, no passwords, no third-party login. Two independent roles in one package:

- **`TruthIDClient`** — the verifier role (same as the TypeScript/Python/Ruby SDKs): generate a login challenge, verify the signed response from the phone. For a backend written in Dart.
- **`TruthIDRequester`** — a Dart-only role: request a signature, transaction execution, or file pin from the user's TruthID mobile app over the same LAN/dead-drop transport the mobile app itself uses. For any Flutter (mobile or desktop) or server-side Dart app that wants to act as the requesting side of a cross-device flow.

Pure Dart — no `package:flutter` dependency, works in Flutter apps and plain Dart backends alike.

```yaml
dependencies:
  truthid_sdk: ^0.1.0
```

Full documentation, how it works, and usage examples: [github.com/masterlxz/truthid/tree/main/sdk](https://github.com/masterlxz/truthid/tree/main/sdk#readme)

## License

MIT — see [LICENSE](./LICENSE).
