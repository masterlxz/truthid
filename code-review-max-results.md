# Code Review Max — Resultados Consolidados

**Data:** 2026-07-22 | **Sessão:** `2c6f8b24` | **Comando:** `/code-review max --path desktop/`
**Agentes concluídos:** 9/9
**Agentes ausentes:**
- Angle B (Invariant Auditor — segurança) não produziu resultado final (ficou preso em tool calls)

---


================================================================================
## Resultado 1: Altitude (arquitetura / generalização)
**Agent ID:** `a159a780a8437b7da` | **Timestamp:** 2026-07-22T13:13:39.065Z
================================================================================

# Findings — Desktop mechanism-generalization review

Two scoping notes before the findings: (1) per the extension/mobile memory, the LAN+IPFS/IPNS "dead-drop" race for vault-edit lives entirely in `extension/` and `mobile/` — Desktop's `vault_edit.rs`/`useIncomingVaultEditRequest.ts`/`VaultEditApprovalModal.tsx` only ever receive over the single loopback HTTP endpoint, so there's no channel-racing logic to find on the Desktop side of that mechanism. (2) `sign_message.rs`/`sign_request.rs` don't actually branch over Ledger/WebAuthn/device-key — both channels are hardcoded to device-key signing (`crate::sign_personal_message`, `executeViaUserOp`); Ledger only exists on a separate, wagmi-connector-based path (`connectors/ledger.ts`) used by `useVaultPublish.ts`/`PairDevice.tsx`/`ManageDevices.tsx`/`DesktopDevice.tsx`. The real "two paths coexisting" case on Desktop is Ledger-publish vs. device-key-publish (finding 4 below), not a signing-method fork inside the local-signer channels.

1. **Approval-parking core duplicated wholesale across all 4 local-signer channels, instead of one generic module.**
   `desktop/src-tauri/src/vault_edit.rs:187-260` (struct `PendingVaultEdit`, `VaultEditState`, `handle_incoming`/`handle_incoming_with_timeout`/`current`/`resolve`) is a near-total copy of the same shape in `pin.rs:245-263,394-494`, `sign_message.rs:155-238`, and `sign_request.rs:163-240` — same `Mutex<Option<Pending...>>` single-flight slot, same oneshot+timeout race, same Busy/TimedOut/Invalid outcome plumbing, same resolve-by-id guard. `vault_edit.rs`'s own doc comment even says "mesmo espírito de pin::handle_incoming." This is the textbook (b): each new channel was added by copy-pasting an existing module rather than extending a shared `approval_channel<P, D>` abstraction. Cost: any protocol-level fix (race handling, queueing instead of single-slot, timeout semantics) must be hand-applied 4 times today; the next channel already foreshadowed in project memory (WebAuthn "create() + batch approval via Device") will copy this ~150-line shape a 5th time instead of parameterizing over it.

2. **`local_signer_server.rs`'s router state/`start()` grew by appending a new (state, notifier) pair per channel, not by generalizing to a registry.**
   `desktop/src-tauri/src/local_signer_server.rs:30-40` — `struct SignRequestRouterState` (name frozen from the *first* channel implemented) now holds 4 unrelated state+notifier field pairs; `start()` at `local_signer_server.rs:212-222` has grown to 8 positional parameters. Cost: adding a 5th channel touches the struct, a new `XxxNotifier` type alias, `start()`'s signature, `router()`, `lib.rs::local_signer_start` (which repeats the same clone-and-wrap 4 times, e.g. `lib.rs:608-630`), and every one of the 12+ tests in the file's `mod tests` that must now pass `temp_pin_state()`/`temp_vault_edit_state()`/no-op closures for channels they don't even exercise (e.g. `ping_endpoint_returns_expected_service_identifier`).

3. **`publishVaultViaDeviceKey.ts` copy-pastes the pin-failure check from `useVaultPublish.ts` and silently drops half of it.**
   `desktop/src/services/vaultPublishViaDeviceKey.ts:25-28` duplicates the "all providers failed → throw" check from `desktop/src/hooks/useVaultPublish.ts:126-135`, but the original also has a "some providers failed → show partial-redundancy warning" branch (`setPinWarning(...)`) that the new function never reproduces — and its return type (`{transactionHash}`) doesn't even carry `providers_ok`/`providers_failed` back out, so the caller *couldn't* show that warning even if it wanted to. Cost: both of this function's current call sites — the device-key button in `useVaultPublish.ts` and `desktop/src/components/VaultEditApprovalModal.tsx:71` — can silently publish with degraded pin redundancy and never tell the user, unlike the Ledger path. A third caller would have to re-derive the warning from scratch a second time since the shared service structurally can't return it.

4. **No single owner decides between the Ledger-publish and device-key-publish paths; both are independently clickable and independently gated.**
   `desktop/src/components/VaultManagement.tsx:770` (`disabled={buttonDisabled}`, only tracks the Ledger/wagmi pipeline's `publishState`/`isTxPending`/`isConfirming`) and `VaultManagement.tsx:778-779` (`disabled={deviceKeyPublishState === "publishing"}`, only tracks the device-key pipeline) never check each other's in-flight state. The underlying `vault_publish` Tauri command (`desktop/src-tauri/src/lib.rs:426`) has no single-flight mutex the way `pin.rs`/`vault_edit.rs` do. The code's own comment at `VaultManagement.tsx:773-776` calls the device-key button a "segundo caminho... prova de que o pipeline funciona... sem UI polida de propósito" — i.e. it was deliberately bolted on next to the real feature, not integrated with it. Cost: a user can trigger both simultaneously, firing two concurrent `vault_publish` IPFS pins plus two independent on-chain `updateVault` submissions (one EOA-signed, one device-key-signed) with nothing arbitrating which result is authoritative.

5. **The "bundler not configured" precondition is copy-pasted per call site instead of owned by `executeViaUserOp`, and the copies have already drifted.**
   `desktop/src/services/vaultPublishViaDeviceKey.ts:30-35` and `desktop/src/components/SignRequestModal.tsx:93-96` both independently fetch `get_bundler_config` and throw if `api_key` is empty — but `desktop/src/services/userOpExecutor.ts` (which already receives `bundlerApiKey` as a parameter) and `desktop/src/services/pimlicoBundlerClient.ts:8-16` (`pimlicoBundlerUrl`, which just interpolates the key into a URL) never validate it themselves. The two existing copies have already drifted: one throws in Portuguese ("Bundler não configurado — grave..."), the other in English ("Bundler not configured — set..."). Cost: the next call site to `executeViaUserOp` must remember to paste this guard a third time or ship a confusing raw-Pimlico HTTP error instead of a friendly message.

6. **The four `useIncomingXRequest` hooks are near-identical copies rather than one generic factory.**
   `desktop/src/hooks/useIncomingPinRequest.ts:1-43`, `useIncomingSignMessage.ts:1-40`, `useIncomingSignRequest.ts:1-43`, `useIncomingVaultEditRequest.ts:1-47` each re-implement the identical "invoke `get_pending_X` once, `listen` for `truthid://X`, expose `clear()`" shape, varying only by type names and two string literals. Cost: a shared correctness concern (e.g. the initial `invoke()` resolving *after* a fresher `listen` event already arrived, potentially clobbering it with stale state — the same race shape in all four) has to be diagnosed and fixed four times over; the next channel again copies these ~40 lines verbatim instead of parameterizing `getPendingCommand`/`eventName`.

7. **Ledger APDU chunking duplicated between transaction-signing and personal-message-signing instead of one parameterized chunker.**
   `desktop/src-tauri/src/ledger.rs:251-277` (`build_sign_tx_apdus`) and `ledger.rs:345-372` (`build_sign_personal_message_apdus`) are line-for-line identical chunking loops (derive path, slice into `SIGN_CHUNK_SIZE` pieces, first packet gets a header, later ones get `P1_FOLLOWING_CHUNK`), differing only in the instruction byte and a 4-byte length prefix the personal-message variant prepends. This is the second signing "flavor" added by copying the first loop and tweaking two things rather than extracting `build_chunked_apdus(ins, extra_header, payload, account_index)`. Cost: `connectors/ledger.ts` already stubs `eth_signTypedData_v4` as `unsupported(...)` — the day that's implemented, it's the obvious third copy-paste of this same chunking loop, and any bug in the chunking math (e.g. header-length accounting) has already needed fixing twice and would need a third fix.

Files referenced (all under `/home/masterlxz/Documents/workspace/truthid/desktop/`):
`src-tauri/src/vault_edit.rs`, `src-tauri/src/pin.rs`, `src-tauri/src/sign_message.rs`, `src-tauri/src/sign_request.rs`, `src-tauri/src/local_signer_server.rs`, `src-tauri/src/lib.rs`, `src-tauri/src/ledger.rs`, `src/services/vaultPublishViaDeviceKey.ts`, `src/services/userOpExecutor.ts`, `src/services/pimlicoBundlerClient.ts`, `src/hooks/useVaultPublish.ts`, `src/hooks/useIncomingPinRequest.ts`, `src/hooks/useIncomingSignMessage.ts`, `src/hooks/useIncomingSignRequest.ts`, `src/hooks/useIncomingVaultEditRequest.ts`, `src/components/VaultManagement.tsx`, `src/components/VaultEditApprovalModal.tsx`, `src/components/SignRequestModal.tsx`.


================================================================================
## Resultado 2: Simplification (complexidade desnecessária)
**Agent ID:** `abdf8ad0e0f915472` | **Timestamp:** 2026-07-22T13:13:47.803Z
================================================================================

I read all the requested files (12 Rust modules in `desktop/src-tauri/src/`, `App.tsx`, both contexts, all 11 hooks, all 3 services, all 11 utils, and the 6 named components) and cross-checked several suspects with `grep` for actual call sites before reporting. Below are 8 concrete findings, ordered roughly by how clear-cut the win is.

---

**1. The four `useIncoming*Request` hooks are byte-identical except for a type name and two string literals**
File: `desktop/src/hooks/useIncomingSignRequest.ts:23-43` (same shape in `useIncomingPinRequest.ts:23-43`, `useIncomingSignMessage.ts:20-40`, `useIncomingVaultEditRequest.ts:27-47`)
Each hook does exactly: `useState<T|null>` → on mount `invoke(getCommand)` then `listen(eventName)` → `useCallback` clear, with only the generic type, the Tauri command string, and the event string varying.
Cost: any fix to this pattern (e.g. handling an `invoke` rejection differently, or a listener-leak fix) must be hand-applied 4 times, and nothing enforces the 4 copies staying in sync — a 5th channel means pasting a 5th near-identical 20-line file.
Simpler alternative: one generic `function useIncomingRequest<T>(command: string, event: string) { ...same body... }`; each of the 4 exported hooks becomes a one-line specialization (`export const useIncomingPinRequest = () => useIncomingRequest<IncomingPinRequest>("get_pending_pin_request", "truthid://pin");`). Collapses ~170 lines to ~25 + 4 one-liners.

**2. The four approval modals duplicate the same 10-line "expiry failsafe" effect verbatim**
File: `desktop/src/components/SignRequestModal.tsx:58-68` (identical block in `PinApprovalModal.tsx:19-29`, `SignMessageModal.tsx:18-28`, `VaultEditApprovalModal.tsx:28-38`)
The `setInterval`-based "has `request.expiresAtMs` passed?" polling loop is copy-pasted across all 4 modals.
Cost: `VaultEditApprovalModal.tsx` already shows the drift starting — its copy resets 3 extra pieces of state (`showPassword`, `stage`, `error`) inline in the same effect that the other 3 don't need, so the "same" logic is no longer textually identical and a future bug fix (e.g. a race between expiry firing and a fresh request replacing `request`) has to be re-derived and re-applied 4 times instead of once.
Simpler alternative: extract `function useRequestExpiry(expiresAtMs?: number): boolean` once; each modal becomes `const expired = useRequestExpiry(request?.expiresAtMs);`.

**3. `useVaultKey.ts` is dead code, and the flow it encodes is independently re-implemented (with drift) in two components**
File: `desktop/src/hooks/useVaultKey.ts:21-75` — confirmed via `grep -rn "useVaultKey"` that this exported hook has **zero importers** anywhere in `desktop/src`.
The "sign `VAULT_KEY_MESSAGE` → `derive_vault_key_from_wallet(r,s,v)`" flow it implements is instead hand-duplicated in `desktop/src/components/CreateIdentity.tsx:105-134` and `desktop/src/components/VaultManagement.tsx:411-447`, each with its *own* state shape (`vaultKeyDerived` boolean vs. `vaultKeyReady`/`derivingKey`/`deriveError` trio) and its own error handling (`CreateIdentity` silently swallows derive errors; `VaultManagement` surfaces them). The security-relevant domain-separation string `"TruthID Vault Key v1"` is copied 3 times: `useVaultKey.ts:6`, `CreateIdentity.tsx:22`, `VaultManagement.tsx:24`.
Cost: a future change to this message (e.g. introducing a v2 scheme) risks being applied to only 1 or 2 of the 3 copies, silently breaking cross-device vault-key derivation — exactly the class of bug this codebase's own comments elsewhere (vault-key-v1/v2 isolation) show real concern about.
Simpler alternative: delete the unused hook, or make it the single source of truth and have both components call it — either way the flow and the constant should exist in exactly one place. (Aside, in case the hook is ever revived: line 36, `setState(exists ? "ready" : "ready")`, sets the same value on both branches — dead conditional; `.then(() => setState("ready")).catch(() => setState("ready"))` could just be `.finally(() => setState("ready"))`.)

**4. Four Rust modules hand-roll the same "single pending request behind a oneshot channel" state machine**
File: `desktop/src-tauri/src/sign_message.rs:155-268` — the shape (`PendingX{payload,responder}` struct → `XState(Mutex<Option<PendingX>>)` → `handle_incoming`/`handle_incoming_with_timeout` → `current` → `resolve`) recurs almost verbatim in `pin.rs:245-520`, `sign_request.rs:163-273`, and `vault_edit.rs:187-290`.
Each file also carries its own near-identical `concurrent_second_..._is_busy` and `timeout_returns_timed_out_...` tests proving the same properties 4 times over.
Cost: a correctness fix to the core parking/timeout/resolve-by-id protocol has to be re-applied and re-verified 4 times; adding a 5th channel means writing ~100-150 lines of this scaffold again. (The in-code comments defend the duplication as needed for testing each module without a live Tauri app — a fair point, but a shared generic core would preserve that same testability.)
Simpler alternative: factor the common part into one generic `SingleSlotChannel<Payload, Decision>` (park/notify/current/resolve/timeout), with `pin.rs`'s extra quota bookkeeping layered on top as a thin wrapper — the 4 modules would shrink to just their actually-distinct parts (body validation + payload shape).

**5. `local_signer_server::start()`'s 8-positional-parameter signature, duplicated at every call site**
File: `desktop/src-tauri/src/local_signer_server.rs:30-40` (`SignRequestRouterState`, 8 fields) and `:212-222` (`start()` signature); called from `desktop/src-tauri/src/lib.rs:625-644` (`local_signer_start` command) and again at `lib.rs:814-833` (the `setup()` closure) — plus ~9 more call sites in `local_signer_server.rs`'s own test module (e.g. `:343-356`, `:467-479`, `:676-688`) that all repeat the identical 8-argument shape in the same order.
Cost: the two production call sites in `lib.rs` independently clone the `AppHandle` 4 times and build 4 near-identical notifier closures to pass into the same 8-arg call — one written for "start on demand" and one for "auto-start on launch," so a change to the wiring (e.g. adding a 5th channel) means editing the struct, the signature, and updating both `lib.rs` sites plus ~9 test call sites, all by hand and all positionally (a transposed `(state, notifier)` pair would still type-check).
Simpler alternative: register channels as a collection (`Vec<Channel>` or a small builder: `ServerBuilder::new().channel(sign_requests, on_sign_request).channel(...).build()`) so `start()` takes one collection argument instead of 8 positional ones, and have `local_signer_start` simply call the same helper `setup()` already needs instead of re-assembling it.

**6. `useVaultPublish.ts` duplicates the same 5-line "mark as published" block in two handlers**
File: `desktop/src/hooks/useVaultPublish.ts:111-118` and `:159-164`
Both the `isTxSuccess` effect and `handleEnviarViaDeviceKey`'s success path run the identical sequence `refetchHasVault(); refetchVaultRef(); onPublished(); setJustPublished(true); setTimeout(() => setJustPublished(false), 3000);`, differing only in the final status reset (`resetTx()` vs. `setDeviceKeyPublishState("idle")`).
Cost: the magic `3000`ms and the refetch/callback ordering have to be kept in sync by hand between the Ledger path and the device-key path; a change to one (e.g. adjusting the "Enviado ✓" display duration) is easy to apply to only one branch and forget the other.
Simpler alternative: a small local helper, e.g. `function markPublished() { refetchHasVault(); refetchVaultRef(); onPublished(); setJustPublished(true); setTimeout(() => setJustPublished(false), 3000); }`, called from both places.

**7. `computeSmartAccountAddress.ts`'s async dual-mode function and its type-guard are unused**
File: `desktop/src/utils/computeSmartAccountAddress.ts:22-43` (the `ComputeAddressFromFactory | ComputeAddressExplicit` union + `isExplicitParams` guard) and `:64-99` (`computeSmartAccountAddress`)
Confirmed via `grep -rn "computeSmartAccountAddress\b"`: the only import anywhere in `desktop/src` is `computeSmartAccountAddressSync` (from `App.tsx:23`). The async function's own dedicated test file (`__tests__/computeSmartAccountAddress.test.ts`) also exclusively calls `computeSmartAccountAddressSync` — the "from factory" on-chain-multicall mode and the union-type dispatch built to support it have no caller at all, production or test.
Cost: a reader has to understand the two-mode union type and the `isExplicitParams` discriminator to work in this file, but that complexity buys nothing that's actually used — it's pure surface area to maintain (e.g. keep in sync with `TRUTHID_ACCOUNT_FACTORY_ABI`) for a code path nothing exercises.
Simpler alternative: delete the async `computeSmartAccountAddress`, the union type, and `isExplicitParams`; keep only `computeSmartAccountAddressSync` (renamed to `computeSmartAccountAddress` if the "Sync" suffix is no longer needed to disambiguate).

**8. `vault_edit.rs` splits one struct into two just to separate `Serialize`/`Deserialize`, unlike every other type in this codebase**
File: `desktop/src-tauri/src/vault_edit.rs:50-65` (`VaultEditRequestBody`, `Deserialize`-only) and `:86-108` (`VaultEditRequestBodyOut`, `Serialize`-only, field-for-field identical, plus a manual `From<VaultEditRequestBody>` impl)
The two structs have exactly the same 6 fields; the only difference is that `Deserialize` and `Serialize` are derived on separate types instead of both on one. This is inconsistent with the rest of the file (`PasskeyProposal`, two lines above, derives both on one struct) and with `vault.rs`'s `VaultEntry`/`Passkey` (also both traits on one struct).
Cost: ~20 extra lines (a duplicate field list + a hand-written conversion impl) that have to be kept in sync by hand if a field is ever added or renamed — miss one side and it's a compile error at best, a silent field-drop at worst if the `From` impl isn't updated to match.
Simpler alternative: `#[derive(Deserialize, Serialize, Clone, Debug)] #[serde(rename_all = "camelCase")] pub struct VaultEditRequestBody { ... }` (drop the `#[serde(default)]` attributes, which are harmless no-ops under `Serialize`) and use it directly as `VaultEditApprovalPayload.entry`'s type — no second struct, no `From` impl.


================================================================================
## Resultado 3: Efficiency/Performance
**Agent ID:** `a487a7d36f28885b4` | **Timestamp:** 2026-07-22T13:14:08.438Z
================================================================================

Reviewed the Desktop app's Rust backend (`vault.rs`, `vault_edit.rs`, `ipfs.rs`, `backup.rs`, `local_signer_server.rs`, `pin.rs`), all hooks in `desktop/src/hooks/`, all services in `desktop/src/services/`, the three named utils, the four named components, `App.tsx`, and (to trace context/prop flow) `IdentityContext.tsx` and `WalletModalContext.tsx`. The four `useIncoming*Request` hooks are already well-built (empty-dep effects, stable `useCallback` clear, no polling — event-driven via `listen()`), and `useSmartAccountActivity`/`scanSmartAccountActivity` already do incremental block-range caching via `localStorage`, so I did not flag those patterns. Findings below are ranked by estimated impact.

**1. `desktop/src-tauri/src/lib.rs:438-439` and `desktop/src-tauri/src/vault.rs:481-491`** — `vault_publish` decrypts the vault twice in a row for no reason: it calls `vault::load()` to get `v.version`, then passes only `v.version` into `mark_published(version: u64)`, which itself calls `load()` again to get the same `Vault` (just to compute `content_signature`). Cost: one extra full disk read + OS-keyring lookup (`Entry::get_password`) + AES-256-GCM decrypt + JSON parse + migration scan of the identical, unchanged vault, on every single "publish" click. Fix: change `mark_published` to take `&Vault` (the one `vault_publish` already has in hand) instead of just the version number, eliminating the second `load()` entirely.

**2. `desktop/src/components/VaultManagement.tsx:502-520`** (called from lines 522, 546, 563, 576, 618, 631, 644) — `loadAll()` fires `Promise.all` over `vault_list_entries`, `vault_pending_changes`, `vault_get_device_permissions`, `vault_list_profiles` after every single add/edit/delete of an entry or profile op, and each of those four Tauri commands independently calls `vault::load()` (`vault.rs:228`) — and `vault_pending_changes` alone triggers two decrypts (`load()` + `load_published_snapshot()`). Cost: one mutation (e.g. saving one password) triggers ~5 full vault decrypts (5 OS-keyring round-trips + 5 file reads + 5 AES-GCM decrypts + JSON parses + migration scans of the same content) where `vault_upsert_entry`/`vault_delete_entry` already return/imply the new state. Cheaper alternative: mirror what `handleToggleFavorite`/`handleTogglePerm` already do — patch `entries` locally from the command's return value and only re-fetch the cheap derived `pending_changes` count, instead of re-fetching everything from scratch on every mutation.

**3. `desktop/src/contexts/IdentityContext.tsx:31`** — `<IdentityContext.Provider value={{ username, identityId: identity?.id, smartAccountAddress }}>` builds a brand-new object every render of `IdentityProvider`. Since `identity` comes from an unmemoized `useReadContract` (default wagmi refetch-on-focus/reconnect behavior), every settle of that query — even when the returned identity is unchanged — produces a new context value object, forcing every consumer of `useIdentity()` (the entire active tab: `SmartAccountDashboard`, `ActiveSessions`, `VaultManagement`, `ManageDevices`) to re-render. Fix: `useMemo(() => ({ username, identityId: identity?.id, smartAccountAddress }), [username, identity?.id, smartAccountAddress])`.

**4. `desktop/src/App.tsx:142`** — `<WalletModalContext.Provider value={{ openConnectModal: () => setConnectModalOpen(true) }}>` allocates a new object *and* a new closure on every render of `App`, and this provider wraps the entire app shell (topbar, tabs, all tab content, all four always-mounted approval modals). `App` itself re-renders often (`useAccount`, `useReadContract` for identity, `useSwitchChain`, `useDisconnect`, `useQueryClient`), so every one of those re-renders cascades into every `useWalletModal()` consumer anywhere in the tree. Fix: `useCallback` the function and `useMemo` the value object (or store it in a `ref`/stable singleton).

**5. `desktop/src-tauri/src/ipfs.rs:63-73` and `:83-88`, with `:105` and `:148`** — `pin_vault` uploads to every configured Kubo provider in a sequential `for ... .await` loop, then pins to every PSA provider in a second sequential loop, and both `kubo_add`/`psa_pin` construct a fresh `reqwest::Client::new()` per call. Cost: with N redundancy providers configured (the entire point of the multi-provider feature), total publish latency is the *sum* of each provider's round-trip instead of the max, and every one of those round-trips pays a fresh TCP+TLS handshake instead of reusing a pooled connection. Fix: build one shared `reqwest::Client` (passed in or `once_cell`-cached) and fire each provider's request concurrently (`futures::future::join_all` or a `JoinSet`) within the Kubo phase and again within the PSA phase.

**6. `desktop/src/services/userOpExecutor.ts:82-89`** — `readContract(...)` (on-chain `EntryPoint.getNonce`) and `bundlerClient.getUserOperationGasPrice()` (HTTP call to Pimlico) are two independent network round-trips awaited back-to-back even though neither depends on the other's result. Cost: adds a full extra round-trip of latency (~100-500ms depending on RPC/bundler) to every device-key UserOperation — every sign-request approval, every "publish via device key" click. Fix: `const [nonce, gasPrice] = await Promise.all([readContract(...), bundlerClient.getUserOperationGasPrice()]);`.

**7. `desktop/src/components/VaultManagement.tsx:650-657`** — `sortedEntries` (favorite-partition) and `filtered` (substring match with `.toLowerCase()` across site/username/each profile) are plain `const`s, not `useMemo`. Cost: this recomputes over the *entire* entries list on every render of `VaultManagement` — including renders triggered by unrelated local state (opening the delete-confirm on one row, opening/closing the add-entry form, toggling password visibility inside `EntryForm`) — not just when `entries` or `filter` actually change. For a vault with hundreds of saved credentials this repeats string-lowercasing and array copies needlessly on every keystroke and every unrelated toggle. Fix: `useMemo(() => ..., [entries, filter])`.

**8. `desktop/src/utils/scanSmartAccountActivity.ts:119-139`** — inside each 2000-block chunk, `getTransactionReceipt` (line 129) and `getBlock` (line 136) are awaited one log at a time in a `for` loop, even across distinct cache-miss hashes/blocks in the same chunk. The code comments justify this as "simpler to dedupe" for an expected "tens of operations," but the dedup is by `Map` key, not fetch order, so batching per-chunk unique hashes/blocks via `Promise.all` before the loop (then a second pass to build `activities` in order) would be equally correct. Cost: a full/first-time scan for a long-lived identity pays one sequential RPC round-trip (~100-300ms against public RPC endpoints) per unique tx/block, serially, directly extending the "Scanning transaction history..." wait shown in `SmartAccountDashboard`; this is only amortized by the existing localStorage cache on *subsequent* visits, not on first scan or after a long gap.


================================================================================
## Resultado 4: Reuse/Deduplication
**Agent ID:** `a96862b71fb113b9c` | **Timestamp:** 2026-07-22T13:14:21.357Z
================================================================================

## Reuse Review — Desktop (`desktop/`)

Read all 12 Rust files under `desktop/src-tauri/src/`, all hooks in `desktop/src/hooks/`, all services in `desktop/src/services/`, all utils in `desktop/src/utils/` (excluding `__tests__`), and the four approval modals. 8 findings below, ordered roughly by size of the duplicated surface.

---

**1. The entire "park an HTTP request for human approval" protocol is written from scratch 4 times**
`desktop/src-tauri/src/pin.rs:24-35,394-520` vs `desktop/src-tauri/src/sign_request.rs:18-29,177-273` vs `desktop/src-tauri/src/sign_message.rs:13-24,170-268` vs `desktop/src-tauri/src/vault_edit.rs:16-27,205-290`

Each of the four channels (`/pin`, `/sign-request`, `/sign-message`, `/vault-edit`) independently defines its own `random_id()`/`now_ms()` (byte-identical in all four files), its own `Mutex<Option<Pending{X}>>`, its own `handle_incoming_with_timeout` that locks, returns `Busy` if occupied, builds a payload with `id: random_id()` / `expires_at_ms: now_ms() + timeout`, opens a `oneshot::channel`, calls `notify`, then races `tokio::time::timeout(timeout, rx)` against `Rejected`/disconnect/timeout — and its own `current()`/`resolve()` pair with the identical "id must match, else put it back and error" logic. The `Outcome::into_response()` impls also all map the same five outcomes to the same status codes (Busy→409, TimedOut→408, Invalid→400, Rejected→403). Only the domain-specific validation and the "what happens on approval" side effect actually differ.
**Cost**: ~150 lines of state-machine plumbing copy-pasted 4x with zero shared abstraction; a bug fixed in one channel's race handling (e.g. the wrong-id race already guarded in `sign_request.rs`) has to be manually re-applied to the other three. Should reuse: a generic `PendingApproval<TPayload, TDecision>` + `park_for_approval(...)` core (plus shared `random_id`/`now_ms`) in one module, with each channel supplying only its payload type, validation, and post-approval closure.

**2. Every local JSON config file reimplements its own `$HOME/.truthid` path + load/save boilerplate**
`desktop/src-tauri/src/ipfs.rs:172-194` vs `desktop/src-tauri/src/bundler.rs:17-39` vs `desktop/src-tauri/src/pin.rs:207-231` vs `desktop/src-tauri/src/vault.rs:215-220,350-362` vs `desktop/src-tauri/src/lib.rs:29-34,125-130`

`let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".to_string()); ... .join(".truthid")` (with `create_dir_all`) appears essentially verbatim 11 times across these 5 files (`fallback_key_path`, `vault_key_path`, `vault_path`, `meta_path`, `published_snapshot_path`, plus the inline legacy-permissions lookup in `vault.rs:291`, `default_authorizations_path`, `providers_path`, `save_providers`, `config_path`, `save_config`). On top of that, `ipfs::load_providers`/`save_providers`, `bundler::load_config`/`save_config`, and `pin::load_authorizations`/`save_authorizations` all repeat the identical "read_to_string → serde_json::from_str().unwrap_or_default(), else write create_dir_all + to_string_pretty" shape for three different serde types.
**Cost**: any future change to the storage location (e.g. respecting `XDG_DATA_HOME` instead of hardcoding `.truthid` under `$HOME`) requires editing 8+ call sites instead of one. Should reuse: a single `fn local_config_path(filename: &str) -> Result<PathBuf, String>` plus generic `load_json_or_default<T: DeserializeOwned + Default>`/`save_json_pretty<T: Serialize>` helpers, called by `ipfs.rs`, `bundler.rs`, `pin.rs`, and the two key-path functions in `lib.rs`.

**3. The four `useIncomingXxx` hooks are the same hook, copy-pasted**
`desktop/src/hooks/useIncomingPinRequest.ts:23-43` vs `useIncomingSignMessage.ts:20-40` vs `useIncomingSignRequest.ts:23-43` vs `useIncomingVaultEditRequest.ts:27-47`

All four are: `useState<T | null>(null)` → `useEffect` that calls `invoke<T | null>("get_pending_X")` once on mount, subscribes `listen<T>("truthid://X", ...)`, cleans up with `unlisten.then(f => f())` → a `clear` callback → return `{ request, clear }`. The only per-hook variation is the two string literals (invoke command, event name) and the payload type.
**Cost**: this is the exact comparison the review brief asked for — none of the four hooks shares the pattern; each is ~20 lines that could be a 3-line call site. Should reuse: one generic `useIncomingRequest<T>(getCommand: string, eventName: string)` factory in `hooks/`, with all four current files reduced to a type + one call.

**4. All four approval modals reimplement the same expiry-countdown effect and modal shell**
`desktop/src/components/PinApprovalModal.tsx:19-29` vs `SignMessageModal.tsx:18-28` vs `SignRequestModal.tsx:58-68` vs `VaultEditApprovalModal.tsx:28-38`

Every modal has the identical `useEffect(() => { if (!request) {...return;} setExpired(Date.now() > request.expiresAtMs); const timer = setInterval(() => {...}, 1000); return () => clearInterval(timer); }, [request])`, plus the same `modal-overlay > modal-box > modal-header/h2.modal-title + .card ... .actions-row` JSX wrapper and footer (Approve/Reject) markup. `VaultEditApprovalModal.tsx` already shows copy-paste drift: it's the only one that also resets `showPassword`/`stage`/`error` inside that same effect, because there's no shared place to put per-modal reset logic.
**Cost**: a fifth approval channel (there's a clear pattern of adding new `/truthid/v1/*` channels) means copying this block a fifth time; the drift already visible in the vault-edit modal shows the reset logic silently diverges when hand-copied. Should reuse: a `useExpiryCountdown(expiresAtMs)` hook returning `expired`, and/or a shared `<ApprovalModalShell title onApprove onReject approveDisabled approveLabel>` component that the four call sites fill with only their request-specific body.

**5. `handleReject` (and the simple `handleApprove`) is byte-identical across all four modals except the command string**
`desktop/src/components/PinApprovalModal.tsx:42-49` vs `SignMessageModal.tsx:41-48` vs `SignRequestModal.tsx:123-130` vs `VaultEditApprovalModal.tsx:80-87`

```tsx
async function handleReject() {
  if (!request) return;
  await invoke("respond_to_pin_request", { id: request.id, decision: { outcome: "rejected" } }).catch(() => {});
  clear();
}
```
This exact body (guard on `!request`, `invoke(cmd, {id, decision:{outcome:"rejected"}}).catch(() => {})`, `clear()`) repeats 4 times, differing only in the invoke command name; `PinApprovalModal`/`SignMessageModal`'s `handleApprove` follow the same shape for the "approved" outcome too. The same "swallow error, setError(String(e))" idiom also recurs in `hooks/useVaultPublish.ts:121-142,144-170` and `hooks/useVaultBackup.ts:30-49,51-70`.
**Cost**: a one-line Tauri command rename requires touching 4 files instead of 1, and there's no single place to add cross-cutting behavior (e.g. logging every rejection). Should reuse: a tiny shared `respondToRequest(command: string, id: string, decision: unknown, clear: () => void)` helper (or fold it into the hook from finding #3, e.g. have it return a bound `respond` function).

**6. `webauthn.ts` hand-rolls hex/concat primitives that are already available one import away**
`desktop/src/utils/webauthn.ts:18-30` (`toHex`/`fromHex`) and `:38-47` (`concatBytes`) vs `desktop/src/utils/cbor.ts:57-66` (`concat`)

`webauthn.ts` already imports `p256` from `@noble/curves/p256` and `sha256` from `@noble/hashes/sha2` — both packages transitively pull in `@noble/hashes/utils`, which exports `bytesToHex`/`hexToBytes`/`concatBytes` with the exact same contract (no `0x` prefix) that this file's hand-rolled `toHex`/`fromHex`/`concatBytes` reimplement. Worse, `concatBytes` (lines 38-47) is a verbatim copy of the private `concat()` already defined in the neighboring `cbor.ts:57-66` (same reduce-then-copy-loop, just array-vs-spread args) — and `webauthn.ts` already imports four other functions from `cbor.ts` without picking this one up too.
**Cost**: three small crypto primitives reimplemented instead of imported, one of them duplicated in two adjacent files in the same directory. Should reuse: `bytesToHex`/`hexToBytes`/`concatBytes` from `@noble/hashes/utils` (already a transitive dependency of imports in this same file), which would also remove the need for `cbor.ts`'s private `concat`.

**7. The "all pinning providers failed" guard is duplicated with a hardcoded error string**
`desktop/src/hooks/useVaultPublish.ts:126-129` vs `desktop/src/services/vaultPublishViaDeviceKey.ts:25-28`

```ts
const result = await invoke<PinResult>("vault_publish");
if (result.providers_failed.length > 0 && result.providers_ok.length === 0) {
  throw new Error(`Todos os providers falharam: ${result.providers_failed.join(", ")}`);
}
```
`vaultPublishViaDeviceKey.ts`'s own doc comment says it was "extracted from `useVaultPublish.ts::handleEnviarViaDeviceKey`... does not duplicate the logic" — true for the UserOp-signing part, but the all-providers-failed check on `vault_publish`'s result was left behind in the sibling `handleEnviar` (the Ledger/`writeContract` path) instead of being extracted too.
**Cost**: the error message text now has two sources of truth; a future change to the wording (or to the failure condition) only gets applied to whichever call site someone remembers to edit. Should reuse: export the check from `vaultPublishViaDeviceKey.ts` (or a small `assertPinResultOk(result: PinResult)` in `services/`) and call it from both `useVaultPublish.ts::handleEnviar` and `publishVaultViaDeviceKey`.

**8. `useVaultBackup.ts` reimplements the same base64 char-loop already written in `utils/webauthn.ts`**
`desktop/src/hooks/useVaultBackup.ts:17-28` (`base64ToBytes`/`bytesToBase64`) vs `desktop/src/utils/webauthn.ts:32-36` (`base64UrlEncode`)

```ts
function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary);
}
```
is exactly the first two lines of `webauthn.ts`'s `base64UrlEncode` before its URL-safe `.replace()` chain. `useVaultBackup.ts` (a hook) reimplements the byte↔base64 codec instead of importing a shared version from `utils/`, where the technique already lives.
**Cost**: two independent implementations of the same encode loop, in a hook that has no other reason to own crypto/encoding code. Should reuse: hoist `bytesToBase64`/`base64ToBytes` into `desktop/src/utils/` (new file or alongside `cbor.ts`), and rewrite `base64UrlEncode` as a one-line wrapper over the shared `bytesToBase64`.

---

Note: the mission's suggested Rust comparison ("file-read/decrypt/write-with-lock boilerplate across `vault.rs`, `vault_edit.rs`, `backup.rs`") didn't hold up — `vault_edit.rs` has no file I/O at all (state is in-memory only, by design per its own comments), and `backup.rs` is pure encrypt/decrypt with no path/lock concerns of its own, so no finding was forced there.


================================================================================
## Resultado 5: Angle D: Language/Framework Pitfalls
**Agent ID:** `aacfdd9bb8aa4e68b` | **Timestamp:** 2026-07-22T13:18:17.266Z
================================================================================

Review complete. I read all 12 Rust files and all 47 TypeScript/React files specified (App.tsx, both contexts, all 11 hooks, all 3 services, all 11 utils, all 25 components). I traced the codebase's control flow carefully rather than pattern-matching superficially — several look-alike patterns (`!!identityId`, `balance.value === 0n`, the `== null` idiom, TOTP/timestamp arithmetic) turned out to be safe on inspection (e.g., I checked `IdentityRegistry.sol` and confirmed identity IDs start at 1, so `0` is a legitimate "doesn't exist" sentinel, not a real falsy-zero bug).

Here are the findings I'm confident are real:

**1. `desktop/src/components/SignRequestModal.tsx:51,58-68,90-121,132,181,184` — stale `stage` state permanently disables the sign-request modal after the first successful approval.**
`stage` (`"idle"|"signing"|"error"`) is only ever reset by the `useEffect` at lines 58-68, which resets `expired` but not `stage`/`error`. On a successful approval, `handleApprove` sets `stage="signing"` (line 90) and, after success, only calls `clear()` (line 111) — `stage` is never set back to `"idle"`. Since `SignRequestModal` is mounted unconditionally for the app's entire lifetime (in both branches of `App.tsx`), the next incoming sign-request re-renders the *same* component instance with `stage` still `"signing"`. `busy = stage === "signing"` (line 132) then disables **both** Approve (`disabled={busy || expired}`, line 181) and Reject (`disabled={busy}`, line 184) — the user can neither approve nor reject any subsequent request, and nothing ever clears it short of an app restart. Notably, `VaultEditApprovalModal.tsx` (lines 28-38) explicitly resets its analogous `stage`/`error` state in the same spot, and `PairDevice.tsx`/`CreateIdentity.tsx` have dedicated effects added specifically to avoid a "stuck phase forever" bug — this looks like a regression of a class of bug the team has fixed elsewhere, but missed here, and it's triggered by the *success* path (the most common one).

**2. `desktop/src-tauri/src/vault.rs:243` — out-of-bounds panic on a corrupted/truncated vault file.**
In `load()`'s legacy-key migration branch, `decrypt(&blob)` already returned `Err` because `blob.len() < 28` (line 333 of `decrypt`), but the fallback branch reuses the same unvalidated `blob` and does `Nonce::from_slice(&blob[..12])` unconditionally. If `~/.truthid/vault.enc` is truncated below 12 bytes (crash mid-write, disk full, partial copy, manual tampering), this slice panics instead of returning a graceful error. Every vault command (`vault_list_entries`, `vault_upsert_entry`, etc.) funnels through `vault::load()`, so a corrupted vault file crashes the command instead of surfacing "vault decrypt failed."

**3. `desktop/src/hooks/useSmartAccountActivity.ts:104-152` (specifically 110-111 and 143-146) — dashboard can get stuck in "Scanning..." forever.**
The `scanInFlight` ref guards against concurrent scans, and the async closure checks a `cancelled` flag before each `setState`. But if the user clicks "Refresh activity" (never disabled while scanning — see `SmartAccountDashboard.tsx:111`) while a scan is still in flight: the new effect run sees `scanInFlight.current === true` and returns immediately without starting a new scan; when the *old* scan later finishes, its closure's `cancelled` is `true`, so `if (!cancelled) setIsScanning(false)` (line 144) is skipped too — leaving `isScanning` stuck `true` with no scan actually running and no further effect run scheduled to fix it.

**4. `desktop/src/components/DesktopDevice.tsx:106` (same pattern in `ManageDevices.tsx:101` and `useVaultPublish.ts:116,164`) — `useEffect`-scheduled `setTimeout` with no cleanup.**
After a successful device registration, `setTimeout(() => { refetch(); onRegistered(); }, 3000)` is fired with no returned cleanup — unlike the sibling effect a few lines above (76-99) in the *same file*, which correctly does `return () => clearTimeout(timer)`. If the user navigates away from the Devices tab within that 3-second window, the component unmounts and the timer still fires afterward against a torn-down tree. Impact is muted since `refetch`/`invalidateQueries` are react-query operations that are generally safe to call after unmount, but it's a real, repeated inconsistency against the pattern the codebase uses correctly elsewhere.

**5. `desktop/src-tauri/src/local_signer_server.rs:254-260` — silently discarded server error leaves `LocalSignerServerState` reporting "running" after the HTTP bridge has actually died.**
```rust
let join_handle = tauri::async_runtime::spawn(async move {
    let _ = axum::serve(listener, router(router_state))
        .with_graceful_shutdown(async { let _ = shutdown_rx.await; })
        .await;
});
```
The `Result` of `axum::serve(...).await` is discarded. `RunningServer` is stored in `state.0` right after spawning regardless of whether the task later fails, so if serving errors out post-bind, `local_signer_status`/`LocalSignerStatus.running` keeps reporting `true` indefinitely with no path to detect or recover — silently breaking the whole cross-app signing bridge (sign-request/sign-message/pin/vault-edit) while the UI still shows it as active.

I verified there is no `std::sync::Mutex` used anywhere (only `tokio::sync::Mutex`, consistently and deliberately, per comments), no other `.unwrap()`/`.expect()` outside tests besides the top-level `lib.rs:888` (idiomatic `main()`-level panic, appropriate) and `backup.rs:76` (a `try_into().unwrap()` on a provably-fixed-length-4 slice, safe), and no truncating-cast issues that are reachable with realistic inputs. I'm reporting 5 rather than 8 because the remaining candidates I traced (a `TotpQrScanner` prop-identity re-render, a stale-`smartAccountAddress`-closure retry gap in `VaultEditApprovalModal`, `useVaultKey.ts`'s dead `exists ? "ready" : "ready"` ternary) turned out to be either unreachable in the actual UI flow or not a match for the requested pitfall categories once traced through.


================================================================================
## Resultado 6: Angle C: Cross-file IPC Tracer
**Agent ID:** `a369b3c5a0d8773e7` | **Timestamp:** 2026-07-22T13:19:40.877Z
================================================================================

## Angle C — Cross-file tracer: Rust `#[tauri::command]` ↔ frontend `invoke()` findings

Traced all 44 `#[tauri::command]` exports in `desktop/src-tauri/src/{lib,ledger}.rs` against every `invoke()`/`invoke<T>()` call site in `desktop/src/` (components, hooks, services, connectors), plus the five `useIncoming*`/`useLocalSignerServer` hooks end-to-end.

### 1. No lock around the vault file lets two independent frontend paths silently drop each other's write (data loss)
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src-tauri/src/vault.rs` (`load()` line 228, `save()` line 305) and `/home/masterlxz/Documents/workspace/truthid/desktop/src-tauri/src/lib.rs` (`vault_upsert_entry` line 296, `vault_delete_entry` line 305, `vault_set_favorite` line 496, etc.) — callers: `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/VaultManagement.tsx` (lines 545, 560, 575, 588) and `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/VaultEditApprovalModal.tsx` (line 70).
Every vault-mutating command does a plain `load()` → mutate in memory → `save()` with no mutex, and `lib.rs::run()`'s `.manage(...)` calls (lines 758–762) register state for the local-signer server, sign-request/sign-message/pin/vault-edit, but never a `Vault`/file lock — and these are non-`async fn` commands, so Tauri runs them on separate OS threads.
**Failure scenario:** user is editing an entry in `VaultManagement` (`handleEdit` → `vault_upsert_entry` in flight) while, at the same moment, the always-mounted `VaultEditApprovalModal` (browser-extension flow) has its own `vault_upsert_entry` in flight for an approved credential. Both read the same on-disk `vault.enc`, both add their entry to their own in-memory copy, both call `save()`; whichever write lands last overwrites the file, and the other entry (a saved password) is silently and permanently lost with no error surfaced anywhere.

### 2. "Enviar" and "Publicar via device key" are independently enabled, letting two concurrent `vault_publish` + on-chain `updateVault` submissions fire
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src/hooks/useVaultPublish.ts` line 188 (`buttonDisabled: publishState === "publishing" || isTxPending || isConfirming || justPublished`) vs. `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/VaultManagement.tsx` line 779 (`disabled={deviceKeyPublishState === "publishing"}`); Rust side `vault_publish` in `lib.rs` line ~426 has no lock either.
**Failure scenario:** user clicks "Enviar" (Ledger path, `handleEnviar`) and then, before it resolves, clicks "Publicar via device key" (`handleEnviarViaDeviceKey`) — its disabled condition only checks its own independent `deviceKeyPublishState`, not the Ledger path's state. Both call `invoke("vault_publish")` concurrently and each then submits its own `updateVault(cid, contentHash)` transaction on Base Mainnet (one Ledger tx, one UserOperation) — real gas is spent twice from the smart account for the same/conflicting update, and if a mutation slipped in between the two `vault_publish` reads, the two CIDs differ and whichever tx confirms last silently wins on-chain.

### 3. A second incoming vault-edit request can have its approval modal silently dismissed mid-flight
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/VaultEditApprovalModal.tsx` lines 42–78 (`handleApprove`), in combination with `/home/masterlxz/Documents/workspace/truthid/desktop/src/hooks/useIncomingVaultEditRequest.ts` line 36 (`setRequest(event.payload)` unconditionally overwrites state), and `/home/masterlxz/Documents/workspace/truthid/desktop/src-tauri/src/vault_edit.rs` (`resolve()` lines 273–290 frees the single-flight `pending` slot as soon as the user clicks Approve, well before merge/publish runs, per the doc comment at lines 199–204).
**Failure scenario:** extension proposal A arrives, user clicks Approve; `respond_to_vault_edit_request` (line 52) succeeds immediately, freeing Rust's pending slot and returning 200 to the extension — but `vault_upsert_entry` (line 70) and `publishVaultViaDeviceKey` (line 71, which can take tens of seconds polling for a UserOp receipt) are still running. If proposal B arrives from the extension during that window, it parks fine (slot is free) and its event overwrites React's `request` state to B, so the modal now displays B. When A's `handleApprove` finally finishes, it calls `clear()` (line 73) — which nulls out the *currently displayed* request, i.e. B — dismissing B's modal without the user ever seeing/approving/rejecting it. B then sits parked in Rust for up to 5 minutes before timing out and silently never getting saved.

### 4. Retrying "Approve" after a post-approval failure is permanently broken
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/VaultEditApprovalModal.tsx` lines 42–78, button disable at line 139 (`disabled={expired || stage === "publishing"}`).
**Failure scenario:** user clicks Approve; `respond_to_vault_edit_request` (line 52) succeeds and `vault_upsert_entry` (line 70) succeeds, but `publishVaultViaDeviceKey` (line 71) throws (e.g. bundler not configured, network hiccup) → `stage="error"`, and the Approve button is *not* disabled in this stage (only `expired`/`"publishing"` disable it). User clicks Approve again: `handleApprove` unconditionally re-sends `invoke("respond_to_vault_edit_request", {id, outcome: approved})` for the same `id`, but Rust's `VaultEditState.pending` was already consumed on the first call, so `resolve()` (vault_edit.rs line ~288) now always returns `Err("no pending vault edit request...")`. Every subsequent Approve click fails at this very first step — `vault_upsert_entry`/publish are never retried — and the only way out is "Reject" (which swallows its own error via `.catch(() => {})` at line 85 and unconditionally clears), leaving the entry saved locally but never published.

### 5. Stopping the local signer channel can hang for up to 5 minutes with zero UI feedback
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src-tauri/src/local_signer_server.rs` `stop()` lines 277–287 (`running.join_handle.await` waits for axum's graceful shutdown, which waits for in-flight handlers to finish); `/home/masterlxz/Documents/workspace/truthid/desktop/src/hooks/useLocalSignerServer.ts` lines 36–41 (`stop` has no busy/pending state); `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/LocalSignerStatus.tsx` line 25 (`<button onClick={stop}>Stop</button>`, no disabled/loading state at all).
**Failure scenario:** a third-party app's `/truthid/v1/sign-request` (or `/pin`, `/sign-message`, `/vault-edit`) is currently parked awaiting human approval (up to `SIGN_REQUEST_TIMEOUT` = 300s). User goes to Devices → "Local app channel" and clicks Stop. Axum's graceful shutdown won't complete until that in-flight handler returns (via the user approving/rejecting elsewhere, or the 300s timeout), so `local_signer_stop`'s promise never resolves during that window; the button stays labeled "Stop" with no spinner/disabled state, looking completely unresponsive/frozen for up to 5 minutes.

### 6. `DesktopDevice.tsx` regresses a previously-fixed "stuck phase" bug (débito #44)
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/DesktopDevice.tsx` lines 55–141 (`phase` state, `handleRegister`), contrast with `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/PairDevice.tsx` lines 134–136, which has the fix and explicitly documents it as "the same bug class already fixed in `CreateIdentity.tsx` (débito #44)."
**Failure scenario:** user clicks "Register this desktop"; `setPhase("committing")` (line 126) fires `sendCommit`. If the commit tx is rejected in the wallet/Ledger or reverts on-chain, `isCommitError`/`isRegisterError` (lines 58–59, 69) become true and an error is displayed, but — unlike `PairDevice.tsx` — there is no effect resetting `phase` back to `"idle"` on error. `isBusy = phase !== "idle"` (line 143) then permanently disables the "Register this desktop" button; the only recovery is fully restarting the app, blocking the core device-registration/onboarding flow for that session.

### 7. Favoriting an entry or toggling a device's write permission never refreshes the "pending changes" counter
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/VaultManagement.tsx` `handleToggleFavorite` (lines 586–593) and `handleTogglePerm` (lines 596–608), vs. `pendingCount` (line 455) which is only refreshed inside `loadAll()` (called at lines 522, 546, 563, 576, 618, 630, 641 — never from the two toggle handlers) or reset to 0 by `useVaultPublish`'s `onPublished` callback (line 537).
**Failure scenario:** vault shows "Enviar" with 0 pending changes; user stars a favorite (`vault_set_favorite`, which per `vault.rs::diff_count` genuinely counts as a pending content change against the last published snapshot — the exact mechanism fixed twice recently per git history). The local `entries` array updates optimistically but `pendingCount` stays 0, so the button keeps showing plain "Enviar" (no "(N pendente)"); a user who only publishes when the counter says something is pending will leave that favorite toggle unpublished/out of sync with Mobile and the extension indefinitely (until an unrelated add/edit/delete triggers `loadAll()`, or they switch away from and back to the Vault tab).

### 8. Approve on Pin/Sign-Message requests silently swallows a failed resolution, showing false success
**File:** `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/PinApprovalModal.tsx` lines 33–40 and `/home/masterlxz/Documents/workspace/truthid/desktop/src/components/SignMessageModal.tsx` lines 32–39 — both `handleApprove` wrap `invoke("respond_to_..._request", ...)` in `.catch(() => {})` and then unconditionally call `clear()`.
**Failure scenario:** the local `expired` flag is driven by a 1-second `setInterval` (lines 19–29 in both files) checking the same `expiresAtMs` the Rust side enforces via `tokio::time::timeout`. If the user clicks Approve in the sub-second window after Rust's 300s deadline has already fired (clearing `PinState`/`SignMessageState.pending`) but before the local interval has re-checked, `respond_to_pin_request`/`respond_to_sign_message` rejects with "no pending ... request (it may have already expired)" — which is swallowed, and `clear()` still runs, closing the modal exactly as it would on real success. The user believes they approved the pinning/signing request when in fact nothing happened and the requester already received a 408.

All 8 are corroborated directly by reading both the Rust command implementation and its caller(s); none require speculation about files outside `desktop/`.


================================================================================
## Resultado 7: Angle E: Wrapper/Adapter Correctness
**Agent ID:** `aaf880739e4001cea` | **Timestamp:** 2026-07-22T13:20:26.073Z
================================================================================

## Angle E — Wrapper/Adapter/Proxy Correctness: Findings

I read all 7 named files in full, plus their imports from `desktop/src/config/` and `desktop/src/utils/`, and cross-referenced `ledger.rs` and `local_signer_server.rs`. I also traced every real caller of each wrapper (grep across `desktop/src/`) rather than trusting the wrapper's own doc comments. 8 findings below, ranked by severity/confidence. `useLocalSignerServer.ts`/`local_signer_server.rs` (mission item 4) checked out clean — every `invoke` reads fresh Tauri state, the Rust side is a single `tokio::Mutex`-guarded singleton with idempotent start and an awaited graceful shutdown, so no finding came from that pair.

---

**1. `desktop/src/services/userOpExecutor.ts:143` (also 39-42, 147-150) — drops the ERC-4337 receipt's `success` flag**
`executeViaUserOp()` returns `{ userOpHash, transactionHash }` only; `waitForReceipt()`'s return type (`Promise<{ transactionHash: Hex } | null>`) structurally strips out the `success` boolean that `PimlicoBundlerClient.getUserOperationReceipt()` already parses onto `UserOperationReceipt` (see `receiptFromRpc`, same file). A mined-but-reverted UserOp and a mined-and-succeeded UserOp are therefore indistinguishable to every caller.
*Failure scenario:* A UserOp lands on-chain but the inner `execute()` call reverts (blocked destination, revoked device, target contract requirement not met) — EntryPoint still mines it and emits `success=false`. `SignRequestModal.tsx` responds "executed" to the requesting third-party app, and `VaultManagement`'s device-key button shows "Enviado ✓", even though nothing was actually written on-chain.

**2. `desktop/src/hooks/useVaultPublish.ts:68-69, 110-119` — Ledger publish path never checks `receipt.status`**
`isTxSuccess` from `useWaitForTransactionReceipt` only means "a receipt was fetched," not that the transaction succeeded (viem's `waitForTransactionReceipt` resolves normally for `status: "reverted"`). The effect at line 110 fires `refetchHasVault()/onPublished()/"Enviado ✓"` on `isTxSuccess` alone, with no read of `.status`.
*Failure scenario:* User clicks "Enviar" (Ledger path); `TruthIDAccount.execute()` reverts on-chain (e.g. the smart account is no longer a registered identity controller). The tx is mined with `status: "reverted"`, `isTxSuccess` is still `true`, and the UI reports success while `VaultRegistry.updateVault` never ran — same class of bug as #1, independently present on the other path.

**3. `desktop/src/components/SignRequestModal.tsx:98-110` — unconditional `"executed"` outcome sent to third-party apps**
`handleApprove()` always calls `respond_to_sign_request` with `outcome: "executed"` as soon as `executeViaUserOp()` returns, even when `transactionHash` is `null` (not confirmed within the ~60s poll). This diverges from the sibling device-key vault-publish caller (`useVaultPublish.ts::handleEnviarViaDeviceKey`), which explicitly `throw`s in that exact situation instead of treating it as success.
*Failure scenario:* A local third-party app (e.g. Practice Valuation) sends a `/sign-request`; the bundler accepts the UserOp but Base is congested and it isn't mined within 60s. The Desktop app reports `outcome: "executed"` (with `transactionHash: null`) over the HTTP bridge — the third-party app has no signal that the op is still pending and may treat the request as finalized.

**4. `desktop/src/services/vaultPublishViaDeviceKey.ts:25-28` — silently drops the partial-pin-failure warning**
It only throws when `providers_ok.length === 0`; when some (not all) IPFS pinning providers fail, it proceeds silently. Compare `desktop/src/hooks/useVaultPublish.ts:130-135`, where the same `PinResult` from the same `vault_publish` command produces a visible `pinWarning` ("Redundância parcial...") for the identical partial-failure case.
*Failure scenario:* One of two configured pinning providers is down. Clicking "Publish via device key" (`VaultManagement.tsx`) or approving an incoming credential from the browser extension (`VaultEditApprovalModal.tsx`, the third caller of this same function) both publish with reduced redundancy and never tell the user — while the Ledger "Enviar" button, given the exact same `PinResult`, would have shown a warning.

**5. `desktop/src/hooks/useVaultKey.ts` (whole file, zero callers) vs. `desktop/src/components/CreateIdentity.tsx:117-127` and `desktop/src/components/VaultManagement.tsx:422-438` — dead wrapper, diverged duplicate logic**
`useVaultKey()` is never imported anywhere in `src/`. The two real call sites each hand-roll their own copy of "sign fixed message → derive key via HKDF → store." The copies have already diverged: `CreateIdentity.tsx:123` swallows a `derive_vault_key_from_wallet` failure via `.catch(() => {})` with zero user feedback, while `VaultManagement.tsx:433-434` correctly sets a visible `deriveError`.
*Failure scenario:* User rejects the Ledger "sign to derive vault key" prompt (or the Tauri call fails) during identity creation. `CreateIdentity.tsx` leaves `vaultKeyDerived` stuck at `false` with no error shown, confusing the user about why later vault steps don't work — whereas the same failure in `VaultManagement.tsx` is surfaced correctly. Any fix applied to `useVaultKey.ts` itself (including its own "stuck on signing forever if the user rejects" gap) affects nothing, since it's unreachable code.

**6. `desktop/src/App.tsx:114` (feeding `desktop/src/contexts/IdentityContext.tsx:23-28`) — stale `username` survives an account switch**
`displayUsername` falls back to `localStorage`-backed `storedUsername` whenever the on-chain `getUsernameByController` read for the *currently connected* account resolves to `""` (unregistered — mappings default to empty string, never revert). `storedUsername` is only cleared by `handleLogout()`, not by the separate "Disconnect wallet" button, and not on account/Ledger-index switch. Meanwhile `smartAccountAddress` (passed into the same `IdentityProvider`) is fully reactive via `useMemo([address])`.
*Failure scenario:* User connects Ledger account #0 ("alice", cached to localStorage), clicks "Disconnect wallet" (not "Log out"), then reconnects with Ledger account #1 (no on-chain identity yet). `smartAccountAddress` updates to account #1 correctly; `onChainUsername` for account #1 resolves empty, so `displayUsername` falls back to stale "alice." `IdentityContext` now hands every consumer (ManageDevices, VaultManagement, useVaultPublish) alice's real `identityId`/vault/device data paired with account #1's `smartAccountAddress` — writes go to account #1 (revert, or worse, silently hit a *different* identity if #1 happens to control one), while the UI displays alice's.

**7. `desktop/src/connectors/ledger.ts:189-208` vs. `desktop/src/config/wagmi.ts:21-28` — generic RPC passthrough bypasses the configured fallback transport**
For every JSON-RPC method besides `eth_chainId`/`eth_accounts`/`eth_sendTransaction`/`personal_sign`, the Ledger provider's `request()` does a raw `fetch` against only `chain.rpcUrls.default.http[0]`, instead of using `config.transports[base.id]` — the `fallback([mainnet.base.org, base-rpc.publicnode.com, base.drpc.org])` that `config/wagmi.ts` sets up specifically for RPC resilience (the `eth_sendTransaction` branch just above it, by contrast, correctly builds its wallet client from `config.transports`).
*Failure scenario:* `mainnet.base.org` (the sole URL in `rpcUrls.default.http`) rate-limits or has an outage. Any Ledger-signed write needing `eth_getTransactionCount`/`eth_estimateGas` through the connector's own client (add device, revoke device, withdraw, vault publish via Ledger) fails outright with a raw fetch error, even though the two fallback RPCs wired into `config.transports` are healthy and are transparently serving every other read in the app.

**8. `desktop/src/config/truthidAccount.ts:19-24` + `desktop/src/utils/computeSmartAccountAddress.ts:64-99` — hardcoded immutables, on-chain-verifying sibling never called**
`App.tsx:84` only ever calls `computeSmartAccountAddressSync`, which derives every user's smart account address from the hand-maintained constant `FACTORY_IMMUTABLES`. The sibling `computeSmartAccountAddress` in the same util file — which reads the factory's *actual current* immutables on-chain via `multicall` — has no callers anywhere in `src/`.
*Failure scenario:* The factory/registries get redeployed again (this already happened once, per this file's own comment: "Mainnet (redeploy de 2026-07-06, débito #42)"). Whoever ships that redeploy updates `contracts.ts`'s registry addresses but misses updating the separately-hardcoded `FACTORY_IMMUTABLES` in `truthidAccount.ts` (two independent hardcoded copies, nothing ties them together or cross-checks against `factory.getAddress()`). Every user's `smartAccountAddress` computed app-wide — dashboard, vault, devices, sessions — is silently wrong from that point on, with no runtime verification path wired in to catch it.


================================================================================
## Resultado 8: Angle A: Line-by-line (varredura completa)
**Agent ID:** `a3b34d7d8bcb9f0da` | **Timestamp:** 2026-07-22T13:20:44.644Z
================================================================================

I completed a full line-by-line pass over all Priority 1 and Priority 2 files, plus the full Priority 3 set and a skim of Priority 4. Below are the highest-confidence findings, ranked roughly by severity.

1. file: desktop/src/App.tsx, line: 114, summary: `displayUsername` treats the on-chain confirmed "no identity" result (empty string) as if it were "not loaded yet" and falls back to the stale cached username from a previous wallet, causing the whole app to run under a mismatched identity/smart-account pair.
failure_scenario: User connects Wallet A ("alice"), which gets cached via `saveUsername` (line 110) into `localStorage["truthid:username"]`. User clicks "Disconnect wallet" (not "Log out" — that button skips `clearUsername()`), then connects Wallet B, which has never called `createIdentity`. `getUsernameByController(walletB's smart account)` correctly resolves to `""` (Solidity's default for an unset string mapping — a valid, non-error read, not `undefined`). Because `"" ` is falsy, `displayUsername` at line 114 falls through to the stale `storedUsername` ("alice"), so `CreateIdentity` (gated on `!storedUsername` at the render check) never shows for Wallet B, and `IdentityProvider` renders with `username="alice"` (resolving `identityId` to Alice's identity/controller) while `smartAccountAddress` throughout the app is Wallet B's real address — every tab (Devices, Sessions, Vault, Dashboard) now operates on a spliced identity/account pair that was never actually created together.

2. file: desktop/src/components/ActiveSessions.tsx, line: 144, summary: `isRevokeAllSuccess` is never reset after a successful "Revoke all", so any session that becomes active afterward is permanently mis-rendered as "Revoked" for the rest of the component's mounted lifetime.
failure_scenario: While on the Active Sessions tab, user clicks "Revoke all" and it succeeds (`isRevokeAllSuccess` becomes `true` and is never reset via `resetRevokeAll()`, unlike the analogous `resetTx()`/`resetCommit()` calls elsewhere in the codebase). User then opens the "Desktop Login" modal (an overlay, doesn't unmount ActiveSessions) and registers a brand-new session via QuickLogin. That new, genuinely-active session now renders with `isRevoked = session.revoked || (isRevokeAllSuccess && !session.revoked)` = `true`, hiding its individual "Revoke" button and showing a "Revoked" badge — even though `activeSessions.filter(s => !s.revoked)` (used for the "Revoke all (N)" button count) correctly still counts it as active, producing a visibly inconsistent security-audit screen that could lead a user to believe a live session is already revoked.

3. file: desktop/src-tauri/src/ledger.rs, line: 224, summary: `open_ledger_device`'s carefully-distinguished "access_denied" error is discarded by `.map_err(|_| "not_connected".to_string())`, so a Ledger blocked by another process (e.g. Ledger Live) always reports as simply unplugged.
failure_scenario: User has Ledger Live open, which holds exclusive HID access to the device. `open_ledger_device` (by its own doc comment) correctly classifies the OS-level open failure as `"access_denied"`, but `get_ledger_address` at line 224 (and `sign_ledger_transaction`/`sign_ledger_personal_message` at lines 310/386, same pattern) collapse any error into `"not_connected"`. `ConnectLedger.tsx`'s polling loop then never reaches its `isAccessDenied` branch (`status === "access_denied"`), so the user only ever sees "Connect your Ledger via USB" step 1 forever and never the actionable "Close Ledger Live" message, even though the fix is one click away.

4. file: desktop/src/components/VaultEditApprovalModal.tsx, line: 52, summary: the extension is told "approved" (its pending HTTP request is resolved) before the credential is actually merged into the vault and published, and a failure after that point leaves no working retry path.
failure_scenario: Extension proposes a new credential; user clicks Approve. Line 52's `invoke("respond_to_vault_edit_request", { decision: "approved" })` succeeds and unblocks the extension's HTTP call immediately. If the subsequent `vault_upsert_entry` (line 70) or `publishVaultViaDeviceKey` (line 71) then throws (e.g. vault key/keyring error, or bundler not configured), the catch block (lines 74-76) shows an error but never calls `clear()`, and the extension has already received a definitive "approved" response for a credential that was never actually saved. Worse, if the user clicks "Approve" again to retry, it re-sends `respond_to_vault_edit_request` with the same `request.id` (line 52-55) — but Rust's `resolve()` (vault_edit.rs) already consumed that id and returns `Err("no pending vault edit request...")`, so every retry just fails with a confusing, unrelated error instead of ever re-attempting the save.

5. file: desktop/src/hooks/useSmartAccountActivity.ts, line: 110, summary: the `scanInFlight` ref is shared across identity changes and is never reset when `identityId` changes, so switching identity while a scan is in flight silently skips scanning the new identity and leaves the previous identity's activity on screen.
failure_scenario: User is viewing identity A's dashboard while its activity scan (potentially spanning ~250 RPC chunks) is still running. User logs out and connects a different wallet (identity B, never scanned before, no cache). The effect reruns for `identityId=B`, but `scanInFlight.current` is still `true` from A's in-flight scan, so the guard at line 110 returns immediately without starting a scan for B and without clearing `activities` — the dashboard keeps showing identity A's transaction history/costs under identity B's account until the user manually clicks "Refresh activity".

6. file: desktop/src-tauri/src/backup.rs, line: 76, summary: the PBKDF2 `iterations` count is parsed directly out of the untrusted backup file header with no upper-bound sanity check before being used to key-derive.
failure_scenario: A `.truthid-backup` file that is corrupted (e.g. a bit flip landing in the 4-byte iterations field at offset 24-27) or maliciously crafted sets `iterations` to a huge value (up to `u32::MAX` ≈ 4.29 billion). `vault_import_backup` (a synchronous, non-cancelable Tauri command) calls `decrypt` → `derive_key` → `pbkdf2_hmac` with that value, which can hang for an extremely long time with no timeout and no way for the user to cancel from the UI, appearing to freeze the import feature indefinitely.

7. file: desktop/src/components/SignRequestModal.tsx, line: 30, summary: the declared-function-signature verification compares the callData's 4-byte selector against the computed selector with a case-sensitive string `!==`, so valid callData using uppercase hex digits is falsely flagged as unverified.
failure_scenario: A legitimate third-party app sends `callData: "0xA9059CBB..."` (uppercase hex, valid and byte-identical to lowercase) for `functionSignature: "transfer(address,uint256)"`. `toFunctionSelector` normalizes to lowercase `"0xa9059cbb"`, but `actualSelector` at line 29 preserves the original casing, so line 30's `!==` comparison finds them different and shows the "⚠ Could not verify declared function" warning with the raw-bytes fallback UI for a perfectly matching, safe request — eroding user trust in the approval screen's warnings.

8. file: desktop/src/hooks/useVaultKey.ts, line: 36, summary: `setState(exists ? "ready" : "ready")` — both branches of the ternary are identical, so the vault-key-existence check has no effect on the resulting state (currently dead code, since this hook is not imported anywhere in the app, confirmed via repo-wide grep).
failure_scenario: If this hook were wired into any screen (it currently isn't — `VaultManagement.tsx`/`CreateIdentity.tsx` duplicate the same check inline instead), a device with no vault key derived yet would still be reported as `state: "ready"` instead of prompting the user to sign and derive one, since the `false` branch was clearly meant to differ from the `true` branch.


================================================================================
## Resultado 9: Angle B: Invariant Auditor (segurança)
**Agent ID:** `a7565f9b62fb97061` | **Timestamp:** 2026-07-22T13:20:52.207Z
================================================================================

I reviewed all the listed files (Rust backend in `desktop/src-tauri/src/` and the React/TS frontend in `desktop/src/`) end to end. Below are the findings that hold up as concrete, evidenced invariant breaks, ranked by severity. I verified each one by tracing the full call chain rather than flagging in isolation.

## Finding 1 (highest severity — real-fund risk on Base Mainnet)
**File:** `desktop/src/components/SignRequestModal.tsx`, lines 90–111 (esp. line 98 vs. 107); compare `desktop/src-tauri/src/sign_request.rs`, lines 185–240 (esp. 232–238).

**Invariant broken:** #2 — "approved after the requester gave up" must be impossible. It holds for `pin.rs`, `sign_message.rs`, and `vault_edit.rs` (the sensitive action runs *inside* the same Rust future that races against the 300s timeout, so a late decision is simply a no-op), but **not** for sign-request.

`SignRequestModal.handleApprove()` calls `executeViaUserOp()` (line 98) — which fetches a fresh nonce, signs with the device key via `sign_user_op_hash`, and submits a real UserOperation to the bundler — **before** it ever calls `respond_to_sign_request` (line 107). Rust's `SIGN_REQUEST_TIMEOUT` (`sign_request.rs:232-238`) only controls the HTTP status code returned to the *original third-party caller*; nothing re-validates against current server-side pending state before the frontend independently executes. Contrast this with `vault_edit.rs`, where `respond_to_vault_edit_request` is awaited *first* and — if it errors because the slot already timed out — the subsequent `vault_upsert_entry`/publish never run.

**Failure scenario:** A third-party app POSTs a sign-request; the user doesn't respond and the Desktop window is minimized/backgrounded (webview timers commonly throttle `setInterval` while hidden, so the 1s `expired` poll in the modal's `useEffect` at lines 58–68 doesn't get a chance to fire promptly). At t=300s Rust's timeout fires, the original caller gets a 408 and gives up/retries with different data. The user later restores the window and clicks "Approve" on the still-displayed, stale modal before its client-side `expired` flag has caught up. `executeViaUserOp` unconditionally signs and submits the abandoned request's `dest/value/callData` — a real transaction executes on Base Mainnet even though the requesting app has already treated the request as failed. There is no server-side gate for this path, only a client-side timer.

## Finding 2
**File:** `desktop/src-tauri/src/vault_edit.rs`, lines 45–65 and 205–260; `desktop/src-tauri/src/local_signer_server.rs`, lines 42–46 and 189–198; `desktop/src/components/VaultEditApprovalModal.tsx`, lines 91–101.

**Invariant broken:** #5 — the local server is usable as a blind oracle by any non-paired local peer, for the vault-write channel specifically.

`VaultEditRequestBody` carries no caller-identity field at all, and `router()` applies zero authentication to any route (not even the existing `/handshake`, which validates non-emptiness but issues no token anything downstream checks). Yet `VaultEditApprovalModal.tsx` unconditionally renders "The TruthID browser extension wants to save a new credential" (lines 99–101). The port block comment (`local_signer_server.rs:42-46`) documents this exact router as meant for arbitrary third-party integrations (e.g. "Practice Valuation") to talk to — the same unauthenticated surface the vault-edit protocol assumes only the first-party extension uses.

**Failure scenario:** Any local process (malware, or a third-party app already onboarded to this documented protocol) POSTs to `/truthid/v1/vault-edit` with `{site:"bank.com", username:"victim", password:"attacker-chosen", passkey:{...attacker's own private key...}}`. The user sees the extension-attributed prompt, trusts it, clicks Approve. The attacker-controlled password/passkey is merged via `vault_upsert_entry` and published cross-device via `publishVaultViaDeviceKey` — the attacker now holds a credential/passkey the user believes is their own legitimate one.

## Finding 3
**File:** `desktop/src-tauri/src/pin.rs`, lines 294–311 (`try_consume_quota`) and 430–447; `desktop/src-tauri/src/local_signer_server.rs`, lines 105–130, 189–198.

**Invariant broken:** #5/#1 — an unauthorized caller reaches an approval-gated operation with zero approval, because "authorization" is keyed on an unauthenticated, self-reported string.

The only "identity" behind the /pin fast path (skip the approval modal once an app is authorized and within quota) is the caller-supplied `app_name`. Since the local server has no per-caller authentication, any process can spoof the `app_name` of an already-approved app.

**Failure scenario:** User approves "Practice Valuation" once (grants a 50/day quota). Any other local process now POSTs to `/truthid/v1/pin` with `appName:"Practice Valuation"` — `try_consume_quota` matches by string alone, consumes a unit, and pins the attacker's own content through the user's configured pinning providers, with **no modal shown at all**, up to 50 times/day, silently burning the legitimate app's quota and the user's (possibly paid) provider credentials.

## Finding 4
**File:** `desktop/src-tauri/src/vault.rs`, lines 63–71 and 180–191; `desktop/src-tauri/src/vault_edit.rs` (no permission check anywhere); `desktop/src/components/VaultEditApprovalModal.tsx`, lines 42–78.

**Invariant broken:** #1 — a device whose vault-write permission was revoked should not be able to complete a vault-edit.

`device_permissions`/`can_write` ("canWriteVault") is set/read (via `VaultManagement.tsx` → `vault_set_device_permission`/`vault_get_device_permissions`) and persisted, but is never consulted before accepting a mutation. `vault_edit::handle_incoming` — the one path an external device would use to propose a write — has no `pub_key` field and performs no permission check, so revocation has no enforcement effect on the one channel it exists to gate (compounds Finding 2: even a legitimately-revoked device, or anything impersonating it, sails through as long as the human clicks Approve on a prompt that never reflects the revoked state).

**Failure scenario:** User revokes the browser extension's write permission via `vault_set_device_permission(extensionPubKey, false)`. The extension (or an impersonator) still POSTs to `/truthid/v1/vault-edit`; the request parks and shows the approval modal exactly as before revocation; on Approve, `vault_upsert_entry` proceeds normally — the revocation provided no actual protection.

## Finding 5
**File:** `desktop/src/components/VaultEditApprovalModal.tsx`, lines 42–78 (esp. 52–55 vs. 70–71).

**Invariant broken:** #6 — "approved" should never be reported to the network caller unless the credential was actually persisted.

`handleApprove()` calls `respond_to_vault_edit_request` (line 52, which releases the HTTP 200 "approved" response to the network caller) **before** `vault_upsert_entry` (line 70) and `publishVaultViaDeviceKey` (line 71). If either of those later throws, the caller has already been told success.

**Failure scenario:** Extension proposes a credential; user clicks Approve; `respond_to_vault_edit_request` succeeds and the extension's POST returns 200 "approved" and moves on assuming success. `vault_upsert_entry` or (more plausibly) `publishVaultViaDeviceKey` then throws (e.g. bundler not configured, no smart account loaded, keyring locked) — Desktop shows a local error, but the extension has no way to learn its "approved" credential was never actually saved/published.

I stopped at 5 rather than padding to 8 — these are the issues I could concretely trace end-to-end from the listed files; I looked hard for a second "device-key path vs. Ledger path" asymmetry (the mission's other hinted shape) but found that `ManageDevices.tsx`/`PairDevice.tsx` already defend against exactly that class of bug by batching `DeviceRegistry`+`TruthIDAccount` calls atomically via `executeBatch`, so I did not manufacture a weaker finding there.
