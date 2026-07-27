# Pendências do Projeto

> Arquivo central de pendências — **resolvidas e não resolvidas**.
> Toda pendência encontrada em qualquer arquivo do projeto deve ser registrada aqui com um ID único.
> Ao resolver uma, marcar como `✅ Resolvida` com a sessão em que foi corrigida.
> 
> Última atualização: 2026-07-26 (Sessão 167 — P8/Fase 15: etapa 15.1 (schema do Digital Identity Vault) concluída)

---

## Não Resolvidas

### Deploy e Redeploy

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P1 | **Deploy em cascata (DeviceRegistry débito #52)** — `DeviceRegistry.sol` alterado (re-registro após revogação). Exige redeploy de 5 contratos em Sepolia e Mainnet. ⚠️ Há identidade real em uso na Mainnet desde a Sessão 116 — avaliar migração antes de redeployar. | `ARCHITECTURE.md` (débito #52, Pendências de Deploy #5) | 🔴 Alta |
| P2 | **Deploy do RecoveryManager corrigido** (C1 — reentrância) — código corrigido na Sessão 150. Aguardando cascata junto com outros contratos. | `SESSIONS.md` (Sessão 150) | 🔴 Alta |
| P26 | **Assinatura de sessão desalinhada com o fix C4 (domain separation)** — `SessionRegistry.createSession` já verifica `keccak256(chainId, address(this), hash)` no código-fonte (fix C4, ainda não redeployado — ver P1/P2). **Fix implementado nesta sessão em mobile e desktop** (achado real no caminho: o desktop tinha o mesmo bug, não documentado — `QuickLogin.tsx`/`sign_session_hash` também assinava o hash cru), atrás de flag desligada por padrão (`BlockchainService.sessionDomainSeparationEnabled` no mobile, `SESSION_DOMAIN_SEPARATION_ENABLED` em `desktop/src/config/contracts.ts`) — liga a flag quebraria a criação de sessão contra o contrato atual (sem o fix C4), então a ativação fica pra quando o redeploy em cascata (P1/P2) realmente acontecer. Novo `mobile/lib/utils/session_domain_hash.dart`/`desktop/src/utils/buildSessionDomainHash.ts` espelham `keccak256(abi.encode(chainId, address(this), hash))`; `signHash`/`sign_session_hash` continuam genéricos (compartilhados com a assinatura de UserOperation), só o call site em `approval_screen.dart`/`QuickLogin.tsx` decide o que assinar. `flutter test` 403/403, `flutter analyze` limpo, `npx vitest run` 101/101, `tsc --noEmit` limpo. | `SESSIONS.md` (Sessões 160, 163) | 🟠 Média — aguardando ativação em lockstep com o redeploy (P1/P2) |

### Validações em Hardware Real

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P3 | **Validação E2E real — extensão (13.9)** — fluxo completo: extensão carregada unpacked + celular real na mesma Wi-Fi, scan → perfil → envio → confirmação das entradas na popup. LAN e dead-drop. | `PHASE.md` (Fase 13.9, pendências finais) | 🟠 Média |
| P4 | **Validação E2E real — delegação de assinatura** — Desktop + Practice Valuation rodando juntos na mesma máquina, colisão de porta 1420 do Vite a resolver. | `ROADMAP.md` (Vault genérico, fatias futuras) | 🟠 Média |
| P5 | **Validação E2E real — assinatura via device key no Mainnet** — device key do Desktop nunca foi registrada on-chain. Falta configurar bundler + parear o Desktop como device. | `ROADMAP.md` (Vault genérico, fatia 1) | 🟠 Média |
| P6 | **Revalidar decifra da vault key de pareamento (ECIES)** em hardware real — corrigido na Sessão 92 (SHA-256 do shared secret) + 99 (Mac.empty no Dart), mas nunca confirmado ao vivo no celular. | `PHASE.md` (Fase 13.9, pendências finais) | 🟠 Média |
| P7 | **Diálogo de Local Network Privacy do iOS** — mitigação aplicada (timing), não validada em device real. | `PHASE.md` (Fase 13.9, pendências finais) | 🟡 Baixa |

### Funcionalidades Não Implementadas

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P8 | **Phase 15 — Digital Identity Vault** — documentos, endereços, cartões de crédito. 8 etapas planejadas. **15.1 (schema) concluída na Sessão 167** — faltam 15.2-15.8 (CRUD Desktop/Mobile, autofill browser/SO, documentos, revisão de segurança). | `PHASE.md` (Fase 15) | 🟠 Média |
| P9 | **Phase 15 — Autofill SO (Android/iOS)** — implementar `AutofillService` e `ASCredentialProviderViewController`. | `PHASE.md` (Fase 15, etapas 15.5/15.6) | 🟠 Média |
| P11 | **`/truthid/v1/pin`** — endpoint para apps terceiros usarem os providers de pin do TruthID. Modelo de consentimento em aberto. | `ROADMAP.md` (Sessão 106, item 2) | 🟡 Baixa |
| P28 | **SDK Dart: transporte deep link no `TruthIDRequester`** — só cross-device (QR) implementado. Deep link (mesmo aparelho) exigiria o app host registrar seu próprio esquema de URI, específico de plataforma — decidido deixar de fora de um pacote Dart puro por ora. Reavaliado na Sessão 165: hoje nem o Mobile aceita deep link pra `pin`/`vault-edit` (só `sign-message`/`sign-request`), e um pacote Dart puro não consegue automatizar o registro de URI scheme do app hospedeiro nem depende de `url_launcher` — decisão confirmada, segue de fora. | `SESSIONS.md` (Sessão 161, reavaliado 165) | 🟡 Baixa |

### Pendências de Arquitetura / Decisões em Aberto

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P14 | **Interface e identidade visual (UI/UX)** — app e desktop funcionais mas sem polish de produto final. Identidade visual já aplicada (Fase 9), mas fluxos e polish de produto pendentes. | `ARCHITECTURE.md` (tabela de decisões) | 🟡 Baixa |
| P15 | **Session key com limite de gasto** — desenho para evitar gas por mensagem (IA). Em aberto: onde registrar consumo on-chain vs off-chain, revogação em cascata. | `ROADMAP.md` (Monetização) | 🟡 Baixa |
| P16 | **Monetização — definições finais** — precificação ETH/BRL, modelo de consentimento do /pin, session key spending limit, margem de cada fonte de receita. Nada implementado. | `ROADMAP.md` (Monetização) | 🟡 Baixa |

### Ideias de Expansão (Brainstorm — sem `/plan`)

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P17 | **Social Recovery** — N-de-M guardiões com multisig/timelock. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P18 | **Verifiable Credentials / Atestações ZK** — provar atributos sem revelar tudo (KYC descentralizado). | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P19 | **Delegação de acesso temporário** — sessões com escopo e prazo. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P20 | **Reputação on-chain portátil** — histórico de confiança consultável. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P21 | **Vault compartilhado (Family/Team)** — múltiplos Devices de pessoas diferentes. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P22 | **Detecção de vazamento de senha** — k-anonymity (HIBP-like). | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P23 | **Modo panic/duress** — PIN secundário mostrando vault vazio. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P24 | **Suporte a hardware wallets alternativas** — Trezor, YubiKey/FIDO2. | `ROADMAP.md` (Expansão) | 💡 Ideia |

---

## Resolvidas

### Débitos Técnicos (1–53)

| ID | Arquivo(s) | Problema | Resolvida em |
|---|---|---|---|
| ~~D1~~ | ~~`desktop/src/components/ManageDevices.tsx`~~ | ~~347 linhas misturando 3 responsabilidades~~ | **Sessão 39** |
| ~~D2~~ | ~~`mobile/lib/services/blockchain_service.dart`~~ | ~~ABI inline como string JSON~~ | **Sessão 41** |
| ~~D3~~ | ~~`sdk/typescript/src/client.ts:22`~~ | ~~`private publicClient: any`~~ | **Sessão 41** |
| ~~D4~~ | ~~`desktop/src/components/ManageDevices.tsx:133`~~ | ~~`DeviceInfo` type local~~ | **Sessão 39** |
| ~~D5~~ | ~~Desktop (React geral)~~ | ~~Nenhum ErrorBoundary~~ | **Sessão 41** |
| ~~D6~~ | ~~Desktop (React geral)~~ | ~~Estado todo local sem compartilhamento~~ | **Sessão 41** |
| ~~D7~~ | ~~Desktop + Mobile~~ | ~~Zero testes de UI/frontend~~ | **Sessão 43** |
| ~~D8~~ | ~~Desktop (UX/layout)~~ | ~~Posição/organização das telas~~ | **Sessão 40** |
| ~~D9~~ | ~~`ConnectLedger.tsx`~~ | ~~Tela de espera sem hierarquia visual~~ | **Sessão 40** |
| ~~D10~~ | ~~`ConnectLedger.tsx`~~ | ~~Seletor de conta sem endereços~~ | **Sessão 40** |
| ~~D11~~ | ~~`sdk/typescript/`~~ | ~~Registro de sessão incompleto no SDK~~ | **Sessão 39** |
| ~~D12~~ | ~~wagmi auto-reconnect~~ | ~~Reconectava Ledger automaticamente~~ | **Sessão 41** |
| ~~D13~~ | ~~Site de docs (Fase 8)~~ | ~~Sem seção Session Registration~~ | **Sessão 42** |
| ~~D14~~ | ~~`devices_screen.dart`~~ | ~~Não detectava pareamento automaticamente~~ | **Sessão 46** |
| ~~D15~~ | ~~`show_device_qr_screen.dart`~~ | ~~Sem botão de retry no polling~~ | **Sessão 46** |
| ~~D16~~ | ~~Desktop + Mobile~~ | ~~Sem mecanismo de doação~~ | **Sessão 47** |
| ~~D17~~ | ~~`IdentityRegistry.sol:80`~~ | ~~`createIdentity` sem validação de controller~~ | **Sessão 62** |
| ~~D18~~ | ~~`TruthIDAccount.sol`~~ | ~~`abi.decode` revertendo em vez de `SIG_VALIDATION_FAILED`~~ | **Sessão 55** |
| ~~D19~~ | ~~`RecoveryManager.sol`~~ | ~~`emergencyWithdraw` inalcançável~~ | **Sessão 68** |
| ~~D20~~ | ~~`TruthIDAccount.sol:69`~~ | ~~Constante `_SECP256K1N_DIV_2` com dígito faltante~~ | **Sessão 55** |
| ~~D21~~ | ~~`TruthIDAccountFactory.sol`~~ | ~~`createAccount` recomputando hash desnecessariamente~~ | **Sessão 61** |
| ~~D22~~ | ~~`TruthIDAccountFactory.sol` + test~~ | ~~Assembly `extcodesize` duplicado~~ | **Sessão 61** |
| ~~D23~~ | ~~`Deploy.s.sol` + tests~~ | ~~`ENTRY_POINT_V07` hardcoded em múltiplos arquivos~~ | **Sessão 61** |
| ~~D24~~ | ~~`TruthIDAccountFactory.sol:40`~~ | ~~4 erros customizados separados~~ | **Sessão 61** |
| ~~D25~~ | ~~`TruthIDAccountFactory.sol:97`~~ | ~~`_salt` sem suporte a múltiplas contas por owner~~ | **Sessão 68/69** |
| ~~D26~~ | ~~`TruthIDAccountFactory.t.sol:40`~~ | ~~Helper não reusado~~ | **Sessão 61** |
| ~~D27~~ | ~~`pimlico_bundler_client.dart` + `secrets.dart`~~ | ~~API key do Pimlico embutida no build~~ | **Sessão 68** |
| ~~D28~~ | ~~`IdentityRegistry.sol` (deployado)~~ | ~~Factory chamada com seletor antigo de 1 argumento~~ | **Sessão 70** |
| ~~D29~~ | ~~`computeSmartAccountAddress.ts`~~ | ~~`encodeAbiParameters` em vez de `encodePacked` no salt~~ | **Sessão 70** |
| ~~D30~~ | ~~`blockchain_service.dart` + `devices_screen.dart`~~ | ~~`getUsernameForIdentity` sem `fromBlock`/`toBlock` e fire-and-forget~~ | **Sessão 70** |
| ~~D31~~ | ~~`mobile/docker-compose.yml`~~ | ~~Keystore de debug não persistida~~ | **Sessão 70** |
| ~~D32~~ | ~~`mobile/lib/services/blockchain_service.dart`~~ | ~~Struct com campo dinâmico no `web3dart`~~ | **Sessão 70** |
| ~~D33~~ | ~~`VaultManagement.tsx` + `VaultRegistry.sol:71`~~ | ~~`writeContract` direto em vez de via `TruthIDAccount.execute()`~~ | **Sessão 78** |
| ~~D34~~ | ~~`vault_key_service.dart:23`~~ | ~~Chave do vault derivada da device key em vez da wallet~~ | **Sessão 76** |
| ~~D35~~ | ~~`VaultManagement.tsx:386`~~ | ~~`invoke` com chaves snake_case em vez de camelCase~~ | **Sessão 79** |
| ~~D36~~ | ~~`VaultManagement.tsx:317`~~ | ~~Falha parcial de pin tratada como sucesso~~ | **Sessão 80** |
| ~~D37~~ | ~~`VaultSettings.tsx:70`~~ | ~~`healthStatus` indexado por posição, sem reindex~~ | **Sessão 81** |
| ~~D38~~ | ~~`vault_repository.dart:155`~~ | ~~`updateEntry` não verificava existência do ID~~ | **Sessão 82** |
| ~~D39~~ | ~~`VaultManagement.tsx:288`~~ | ~~`useEffect` sem `isConnected` nas dependências~~ | **Sessão 83** |
| ~~D40~~ | ~~`VaultSettings.tsx:90`~~ | ~~API key não validada no formulário PSA~~ | **Sessão 84** |
| ~~D41~~ | ~~`VaultRegistry.sol:71`~~ | ~~`updateVault` sem validação de `contentHash` zero~~ | **Sessão 85** |
| ~~D42~~ | ~~`VaultRegistry.sol:117`** + contracts~~ | ~~`_getCallerIdentityId()` duplicado em 3 contratos~~ | **Sessão 86/88** |
| ~~D43~~ | ~~`VaultManagement.tsx:199`~~ | ~~Orquestração de publish inline no componente~~ | **Sessão 87** |
| ~~D44~~ | ~~`CreateIdentity.tsx`~~ | ~~Fluxo travado se tx2/tx3 falha (nonce desatualizado)~~ | **Sessão 91** |
| ~~D45~~ | ~~`ConnectLedger.tsx`~~ | ~~Chamadas HID concorrentes + falta de timeout~~ | **Sessão 90** |
| ~~D46~~ | ~~`VaultSettings.tsx` (guia Kubo)~~ | ~~CORS ausente do guia de setup do Kubo~~ | **Sessão 91** |
| ~~D47~~ | ~~`mobile/lib/contracts/abis.dart`~~ | ~~`deviceVaultKeys` ausente do ABI~~ | **Sessão 92** |
| ~~D48~~ | ~~`desktop/src-tauri/src/lib.rs`~~ | ~~SHA-256 ausente antes da chave AES (ECIES)~~ | **Sessão 92** |
| ~~D49~~ | ~~`device_key_service.dart`~~ | ~~Race condition na criação da chave~~ | **Sessão 92** |
| ~~D50~~ | ~~`device_key_service.dart`~~ | ~~Prefixo SEC1 `0x04` ausente~~ | **Sessão 92** |
| ~~D51~~ | ~~`PairDevice.tsx`~~ | ~~Botão travado após erro on-chain~~ | **Sessão 92** |
| ~~D52~~ | ~~`DeviceRegistry.sol:103`~~ | ~~Impossibilidade de re-registro após revogação~~ | **Sessão 118** |
| ~~D53~~ | ~~`blockchain_service.dart`~~ | ~~Sem fallback entre RPCs~~ | **Sessão 93** |

### Correções de Segurança (Auditoria Fase 6)

| ID | Contrato | Achado | Resolvida em |
|---|---|---|---|
| ~~S1~~ | ~~IdentityRegistry~~ | ~~`setRecoveryManager` sem controle de acesso~~ | **Sessão 24** |
| ~~S2~~ | ~~SessionRegistry~~ | ~~`createSession` permissionless~~ | **Sessão 24** |
| ~~S3~~ | ~~RecoveryManager + IdentityRegistry~~ | ~~Falta validação de `address(0)` em `newController`~~ | **Sessão 24** |
| ~~S4~~ | ~~IdentityRegistry~~ | ~~`transferController`/`recoverController` sem validação~~ | **Sessão 24** |
| ~~S5~~ | ~~RecoveryManager~~ | ~~Guardians não zerados após recovery~~ | **Sessão 24** |
| ~~S6~~ | ~~RecoveryManager~~ | ~~Array de guardians sem limite~~ | **Sessão 24** |
| ~~S7~~ | ~~DeviceRegistry~~ | ~~Front-running do `devicePubKey`~~ | **Sessão 24** |

### Correções de Contratos (Review Sessão 140 — C1 a C9)

| ID | Achado | Resolvida em |
|---|---|---|
| ~~C1~~ | ~~Reentrância em `RecoveryManager.executeRecovery`~~ | **Sessão 150** |
| ~~C2~~ | ~~Revogar device não desautoriza na `TruthIDAccount`~~ | **Sessão 118** |
| ~~C3~~ | ~~`executeRecovery` não toca no `DeviceRegistry`~~ | **Sessão 118** |
| ~~C4~~ | ~~Replay cross-chain no `SessionRegistry.createSession`~~ | **Sessão 150** |
| ~~C5~~ | ~~`setRecoveryManager` sem checagem de endereço zero~~ | **Sessão 140** |
| ~~C6~~ | ~~3 arrays por identidade sem limite~~ | **Sessão 150** |
| ~~C7~~ | ~~`configureGuardians` aceita guardians duplicados~~ | **Sessão 140** |
| ~~C8~~ | ~~Cascata de endereços imutáveis não documentada~~ | **Sessão 140** |
| ~~C9~~ | ~~`try/catch` do `emergencyWithdraw` engole revert~~ | **Sessão 140** |

### Correções de Mobile (Review Sessão 151 — M1 a M10)

| ID | Achado | Resolvida em |
|---|---|---|
| ~~M1~~ | ~~Deep link/QR bypassava `AppLockService` — telas de aprovação empurradas por cima do bloqueio~~ | **Sessão 152** |
| ~~M2~~ | ~~Login sem checagem de `expiresAt` — `approval_screen.dart` não validava expiração do challenge~~ | **Sessão 153** |
| ~~M3~~ | ~~TOCTOU em `markPublished` — recarregava o vault atual do disco em vez do conteúdo de fato publicado; corrigido em Mobile e Desktop (mesmo padrão nos dois)~~ | **Sessão 154** |
| ~~M4~~ | ~~Future rejeitada cacheada pra sempre em `DeviceKeyService._getOrCreateKey` — falha transiente na 1ª leitura da secure storage quebrava toda assinatura até reiniciar o app~~ | **Sessão 155** |
| ~~M5~~ | ~~Sem guarda de reentrância — sign_request — duplo toque podia submeter 2 UserOperations~~ | **Sessão 156** |
| ~~M6~~ | ~~Sem guarda de reentrância — pin — duplo toque disparava 2 fluxos concorrentes de pin/entrega~~ | **Sessão 156** |
| ~~M7~~ | ~~Sem guarda de reentrância — vault edit — guarda `_entryPersisted` checada só após `await`, duplo toque podia criar entrada duplicada~~ | **Sessão 156** |
| ~~M8~~ | ~~Bug de username reintroduzido — `devices_screen.dart` reimplementava inline em vez de usar `resolvePairedUsername()`, só resolvia na auto-descoberta~~ | **Sessão 157** |
| ~~M9~~ | ~~`expiresAt` ignorado no canal de deep link — `DeepLinkDeliveryChannel.deliver()` recebia o parâmetro mas nunca checava, mascarado pelos chamadores~~ | **Sessão 158** |
| ~~M10~~ | ~~`IndexedStack` construía as 4 abas de uma vez no cold start — Devices/Sessions/Wallet/Vault cada uma chamando `getDevice` redundante pro mesmo endereço~~ | **Sessão 159** |

### Atualização dos SDKs (TypeScript, Python, Ruby — Sessão 160)

| ID | Item | Resolvida em |
|---|---|---|
| ~~SDK1~~ | ~~`registerSession`/`register_session` (relayer server-side) removido dos 3 SDKs — morto na prática desde que o mobile passou a criar a sessão on-chain sozinho via UserOp (14.9.5)~~ | **Sessão 160** |
| ~~SDK2~~ | ~~`AuthResponse` do TS sem `sessionSignature` — inconsistente com Python/Ruby e com o que o mobile de fato envia~~ | **Sessão 160** |
| ~~SDK3~~ | ~~`computeSmartAccountAddress`/`compute_smart_account_address` portado do Desktop pros 3 SDKs — `docs/docs/smart-account.mdx` já prometia essa função no SDK TS, mas ela nunca existiu lá~~ | **Sessão 160** |
| ~~SDK4~~ | ~~Achado real no caminho: `verify_auth_response` do SDK Ruby comparava a chave pública recuperada (`Eth::Signature.personal_recover`, 65 bytes) direto contra um endereço (20 bytes) — nunca batia, rejeitando toda assinatura válida. Corrigido com `Eth::Util.public_key_to_address`~~ | **Sessão 160** |
| ~~SDK5~~ | ~~Nenhum dos 3 SDKs tinha suíte de testes — adicionados vitest (TS), pytest (Python) e rspec (Ruby), incluindo um vetor fixo de paridade cross-linguagem pra `computeSmartAccountAddress`~~ | **Sessão 160** |
| ~~SDK6~~ | ~~Documentação (README, 3 páginas de SDK, quickstart, exemplo) reescrita — narrativa de relayer wallet removida, versões fictícias ("mobile app v14.9.5+"/"v1.1+") removidas~~ | **Sessão 160** |

### Novo SDK Dart (Sessão 161)

| ID | Item | Resolvida em |
|---|---|---|
| ~~SDK7~~ | ~~Novo `sdk/dart/` (`truthid_sdk`) — `TruthIDClient` (verificador, mesmo papel do TS/Python/Ruby: createChallenge/verifyAuthResponse/verifySession/checkDeviceStatus/computeSmartAccountAddress), pure-Dart, sem dependência de `package:flutter`~~ | **Sessão 161** |
| ~~SDK8~~ | ~~`TruthIDRequester` (papel novo, nunca implementado em nenhum idioma antes) — 3 fluxos genéricos (`signMessage`/`signRequest`/`pin`), portado do protocolo real do Mobile (ECIES, HKDF, IPNS, LAN sweep) e do requisitante de referência da extensão (`vaultEdit/*`, TypeScript)~~ | **Sessão 161** |
| ~~SDK9~~ | ~~Vetor de paridade cross-linguagem (`computeSmartAccountAddress`) validado também no Dart — 4º SDK bate byte a byte com TS/Python/Ruby na primeira tentativa~~ | **Sessão 161** |
| ~~SDK10~~ | ~~Vetor de paridade IPNS validado contra Kubo real (mesmo fixture de `mobile/test/services/ipns_key_service_test.dart`, Sessão 113) reaproveitado no SDK Dart~~ | **Sessão 161** |
| ~~SDK11~~ | ~~Achado real no caminho: conectar um container Docker à sua própria IP externa trava (hairpin NAT) — sweep LAN e dead-drop poll tornados injetáveis em `TruthIDRequester` pra testar a orquestração sem depender de rede real entre dois dispositivos físicos~~ | **Sessão 161** |
| ~~SDK12~~ | ~~52 testes novos (dart test), `dart analyze` limpo, doc nova (`docs/docs/sdk/dart.md`) + seção no `sdk/README.md`, build do Docusaurus validado~~ | **Sessão 161** |

### P25 — hang em `cargo test --lib pin::` (Sessão 162)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P25~~ | ~~Causa raiz: descasamento de casing entre o `app_name` normalizado (minúsculo) que `try_consume_quota` usa pra buscar e o `app_name` capitalizado que 3 testes semeavam direto no arquivo de autorizações — o app "não era encontrado", caía no caminho de aprovação e ficava parqueado esperando um `resolve()` que esses testes nunca chamavam. Corrigido semeando os testes já normalizados e endurecendo `revoke_authorization`/`set_daily_limit` pra também normalizar o `app_name` recebido (mesma consistência que o resto do módulo já tinha)~~ | **Sessão 162** |

### P10 — Fase 2 do passkey na extensão + senha nova via extensão (Sessão 164)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P10~~ | ~~Documentação corrigida: a fatia Mobile já tinha fechado 100% em hardware real nas Sessões 135-136 (`PENDING.md`/`ROADMAP.md` nunca foram atualizados depois disso). **Escopo real que faltava — senha nova via extensão — implementado nesta sessão**: novo `extension/src/autofill/newCredentialCapture.ts` detecta submit de formulário com usuário+senha e propõe a credencial pro Device aprovar (mesma heurística do "Salvar senha?" nativo dos navegadores — propõe quando não há entrada existente com esse username exato pro hostname, evita distinguir estruturalmente cadastro de login). Toda a infra downstream (`pendingEdits.ts`, `cipher.ts`, `mobileDelivery.ts`/`desktopDelivery.ts`, `vault_edit_approval_screen.dart`/`VaultEditApprovalModal.tsx`, `vault_edit.rs`) já era genérica — zero mudança fora da extensão. Batch sync (sub-item 2.1 do roadmap) segue de fora, ver P29~~ | **Sessão 164** |

### P27 — `vault-edit` no SDK Dart (Sessão 165)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P27~~ | ~~Novo método `TruthIDRequester.vaultEdit(...)` — LAN + dead-drop cross-network completo, paridade com o requisitante de referência em TypeScript (`extension/src/vaultEdit/*`). Sem fase de resposta (estrutura diferente de `signMessage`/`signRequest`/`pin`), retorna `VaultEditPendingRequest` (`delivered: Future<bool>`) em vez de `PendingRequest<T>`. Novo `internal/vault_edit_content_cipher.dart` (cifra AES-GCM/HKDF, salt domain-separado), `internal/vault_edit_dead_drop_key.dart` (deriva o par Ed25519 completo, não só o nome IPNS público — vetor cross-language TS↔Dart validado byte a byte), `internal/kubo_publish_client.dart` (cliente HTTP Kubo novo via `dart:io`, add/key-import/name-publish/key-rm, best-effort — primeiro cliente Kubo do SDK Dart). `marshalKeyProtobuf`/`computeIpnsName` de `ipns_key.dart` promovidos a públicos e reaproveitados. `dart test` 69/69 (17 novos), `dart analyze` limpo, build do Docusaurus validado~~ | **Sessão 165** |

### P12/P13 — documentação corrigida, já estavam fechados (achado ao levantar pendências, Sessão 166)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P12~~ | ~~Dead-drop IPFS/IPNS pra `/sign-message`/`/sign-request` — já implementado nos dois (`_deadDropIpnsName`/`_deadDropError` em `sign_message_approval_screen.dart` e `sign_request_approval_screen.dart`, e no SDK Dart via `DeadDropPollClient` em `_awaitResult`/`_raceForBlob`, requester.dart). Nunca foi removido do PENDING.md depois de implementado~~ | já implementado antes, doc corrigida na Sessão 166 |
| ~~P13~~ | ~~Callback opcional no login — duplicata: já fechado como **F15** ("Funcionalidades Implementadas", Sessão 142), `callbackUrl` já é `String?` opcional em `approval_screen.dart` desde então. P13 nunca foi removido quando F15 fechou~~ | já implementado (F15, Sessão 142), doc corrigida na Sessão 166 |

### P29 — Sync em lote (batch sync) pro vault-edit (Sessão 166)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P29~~ | ~~Extensão acumula 1+ credenciais propostas (`pendingEdits.ts` já era lista) e manda tudo numa sessão só; Device (Mobile/Desktop) mostra uma lista, aprova de uma vez — N `addEntry`/`vault_upsert_entry` locais + **1 publish() só** no fim. **Achado que reduziu bastante o escopo**: `executeBatch` não era necessário — `VaultRegistry.updateVault` sempre grava um único `(cid, contentHash)` por publish, não importa quantas entradas mudaram no blob (confirmado no contrato); `executeBatch` nunca foi usado por nenhum UserOperation via device key/bundler, só por transações diretas do owner (Ledger) em pareamento de device, sem relação com Vault. `desktop/src-tauri/src/vault_edit.rs`/`local_signer_server.rs`: corpo HTTP virou `Vec<VaultEditRequestBody>` (só a extensão fala esse endpoint, sem quebra de compatibilidade). `mobile/lib/screens/vault_edit_approval_screen.dart`: aceita tanto lista quanto objeto único no conteúdo cifrado — o SDK Dart (`TruthIDRequester.vaultEdit`, P27) ainda manda uma proposta por sessão, sem precisar de nenhuma mudança nele. `extension/src/vaultEdit/{mobileDelivery,desktopDelivery}.ts`/`popup/main.ts`: usam a lista `pending` inteira em vez de `pending[0]`; novo `removePendingEdits` (lote) substitui `removePendingEdit` (item único, ficou órfão, removido). `cargo test --lib` 97/97 (4 novos), `flutter test` 407/407 (4 novos), `npx vitest run` (extensão) 88/88 (2 novos), `tsc --noEmit`/`npm run build`/`flutter analyze` limpos~~ | **Sessão 166** |

### Bugs do `/code-review max` (Desktop) — 52/52

| ID | Grupo | Resolvida em |
|---|---|---|
| ~~B1-B52~~ | ~~Todos os 52 bugs de alta/média/baixa severidade~~ | **Sessão 149** |

### Backlog (Sessão 130)

| ID | Item | Resolvida em |
|---|---|---|
| ~~BL1~~ | ~~Ler QR code do 2FA (TOTP) no celular e desktop~~ | **Sessão 132** |
| ~~BL2~~ | ~~Passkey na extensão — Fase 1 (login)~~ | **Sessão 133** |
| ~~BL3~~ | ~~Gerador de senha do Desktop como popup~~ | **Sessão 135** |
| ~~BL4~~ | ~~Bug de "pending changes" falso no Mobile~~ | **Sessão 131** |

### Funcionalidades Implementadas

| ID | Funcionalidade | Concluída em |
|---|---|---|
| ~~F1~~ | ~~Fase 1 — Smart Contracts~~ | ✅ |
| ~~F2~~ | ~~Fase 2 — Comunicação (WebRTC — retirado)~~ | ✅ |
| ~~F3~~ | ~~Fase 3 — Desktop App (Tauri)~~ | ✅ |
| ~~F4~~ | ~~Fase 4 — Mobile App (Flutter)~~ | ✅ |
| ~~F5~~ | ~~Fase 5 — SDKs (TS, Python, Ruby)~~ | ✅ |
| ~~F6~~ | ~~Fase 6 — Integração & Testes E2E~~ | ✅ |
| ~~F7~~ | ~~Fase 7 — Mainnet & Lançamento~~ | ✅ |
| ~~F8~~ | ~~Fase 8 — Documentação Web (Docusaurus)~~ | ✅ |
| ~~F9~~ | ~~Fase 9 — Identidade Visual~~ | ✅ |
| ~~F10~~ | ~~Fase 10 — Ledger via USB direto (Desktop)~~ | ✅ |
| ~~F11~~ | ~~Fase 11 — Teste E2E Prático~~ | ✅ |
| ~~F12~~ | ~~Fase 12 — Publicação & Release (v1.0.0)~~ | ✅ |
| ~~F13~~ | ~~Fase 13 — TruthID Vault (senhas)~~ | ✅ |
| ~~F14~~ | ~~Fase 14 — Smart Account (ERC-4337)~~ | ✅ |
| ~~F15~~ | ~~Callback opcional no login~~ | **Sessão 142** |
| ~~F16~~ | ~~Vault genérico — Desktop assina via device key (fatia 1)~~ | **Sessão 102** |
| ~~F17~~ | ~~Vault genérico — canal de comunicação local (fatia 2a)~~ | **Sessão 103** |
| ~~F18~~ | ~~Vault genérico — sign-request + modal (fatia 2b)~~ | **Sessão 103** |
| ~~F19~~ | ~~Vault genérico — Practice Valuation cliente (fatia 3)~~ | **Sessão 103** |
| ~~F20~~ | ~~`/sign-message` implementado~~ | **Sessão 107** |
| ~~F21~~ | ~~Cross-device /sign-message — LAN (fatia 1)~~ | **Sessão 108** |
| ~~F22~~ | ~~Cross-device /sign-message — dead-drop (fatia 2)~~ | **Sessão 109** |
| ~~F23~~ | ~~Cross-device /sign-request — LAN (fatia 1)~~ | **Sessão 110** |
| ~~F24~~ | ~~Backup criptografado exportável~~ | **Sessão 126** |
| ~~F25~~ | ~~`/truthid/v1/pin` — núcleo Rust (fatia 1)~~ | **Sessão 119** |
| ~~F26~~ | ~~`/truthid/v1/pin` — rota HTTP + tela (fatia 2)~~ | **Sessão 120** |
| ~~F27~~ | ~~`/truthid/v1/pin` — Settings (fatia 3)~~ | **Sessão 121** |