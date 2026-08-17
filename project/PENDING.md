# Pendências do Projeto

> Arquivo central de pendências — **resolvidas e não resolvidas**.
> Toda pendência encontrada em qualquer arquivo do projeto deve ser registrada aqui com um ID único.
> Ao resolver uma, marcar como `✅ Resolvida` com a sessão em que foi corrigida.
> 
> Última atualização: 2026-08-17 (Sessão 209: P49 avançado — Desktop fechado de ponta a ponta com i18n real (en/pt-BR/es/zh-CN), achado e corrigido bug real de chave duplicada que quebrava a tradução; Mobile/site ainda só normalizados PT→EN)

---

## Nota de lançamento — Sessão 203 (2026-08-16)

Levantamento completo de pendências pedido pelo dono do projeto pra decidir sobre colocar o app em
produção hoje — **excluindo explicitamente a parte paga** (tier facilitado/billing). Conclusão: o
core do produto (protocolo de identidade, `IdentityRegistry`/`DeviceRegistry`/`RecoveryManager`/
`SessionRegistry`/`TruthIDAccountFactory`/`VaultRegistry`, Desktop, Mobile, extensão, Vault, 2FA,
passkeys, backup, social recovery, 4 SDKs) já está deployado na Base Mainnet (cascata da Sessão
197) e validado com hardware real (Ledger + celular físico) em sessões anteriores — sem débito de
segurança em aberto (S1-S7, C1-C9 todos fechados) e sem achado de `/code-review` pendente. O site
de documentação também já está no ar (GitHub Pages, v1 fechado nas Sessões 199-200).

**Decisão do dono do projeto**: as pendências de validação em hardware real desta seção (P3, P6,
P7, P30, P31, P32, P33, P34, P35, P37, P38 — autofill de SO em Android/iOS, leitura de documentos/
cartões do Vault, cliques reais no fluxo de Social Recovery, validação cross-network do dead-drop)
são **aceitas como risco conhecido** e não bloqueiam o lançamento de hoje — são todas validações de
recursos secundários (Fases 15/16), não do protocolo core de autenticação, que já roda em produção
real desde a Sessão 179 em diante. Ficam registradas como estavam, sem fechamento — continuam
valendo pra retomar quando houver hardware/ambiente disponível (Mac pro iOS, device Android físico,
2 redes de fato diferentes).

**Fora do escopo de hoje, por decisão já registrada em sessões anteriores**: P47 (billing/tier
facilitado), P15/P16 (monetização/session key com limite de gasto), P14 (polish de UI/UX), P49
(i18n, recém-registrado), P18-P24 (ideias de expansão, brainstorm puro).

---

## Não Resolvidas

### P56 — rotação de DEK ao revogar device nunca funcionou de verdade; corrigida a causa e a ordem insegura (Sessão 206)

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P56 | **Achado investigando o P54, sem relação direta com a causa raiz dele**: `rotateVaultKeyOnRevoke.ts::buildRotationBatch` (disparada automaticamente depois de revogar um device com outros restantes ativos) cifrava a chave nova via ECIES usando `d.pubKey` — o **endereço Ethereum de 20 bytes** que `DeviceRegistry.sol` guarda pra cada device (o próprio contrato documenta a decisão: guarda o address derivado, não a chave bruta, pra economizar gas). `encrypt_vault_key_for_device` (Rust) exige uma chave pública secp256k1 crua de 33 ou 65 bytes — **rejeita qualquer endereço de 20 bytes**. Ou seja: toda vez que um device era revogado com ≥1 device restante, a rotação sempre lançava erro ("device_pubkey must be 33-byte... or 65-byte") pro primeiro device da lista — a redistribuição nunca funcionou, nem uma vez, desde que a feature existe (`03c5828`). Pior: `rotate_vault_key()` (Rust) já rodava incondicionalmente ANTES desse loop — já tinha reescrito o keyring e re-cifrado o `vault.enc` local inteiro sob a chave nova antes do erro acontecer, deixando o Desktop local dessincronizado do que estava publicado on-chain (a transação `updateVault`/`updateDeviceVaultKey` nunca chegava a ser montada). Não disparou até hoje porque nenhuma revogação com devices restantes tinha acontecido de fato desde que a feature foi adicionada — mas era um problema latente esperando pra corromper o estado local na primeira vez que alguém revogasse um device de verdade. **Corrigido**: (1) `encrypt_key_for_device`/`generate_vault_key_hex` novos (Rust) permitem cifrar a chave nova pra cada device restante ANTES de commitar qualquer coisa local — `rotate_vault_key` agora recebe a chave já pronta (`new_key_hex`) em vez de gerar e commitar sozinha; (2) como a chave pública crua de um device já pareado nunca fica disponível em lugar nenhum (nem on-chain, nem local — só existe efemeramente na hora do pareamento), a rotação não dispara mais sozinha: `ManageDevices.tsx` agora pede a chave pública de cada device restante antes de confirmar (`pendingRemaining`/`rawPubkeys`), e só chama `buildRotationBatch` com todos os dados em mãos. `cargo test --lib` 184/184, `cargo clippy --lib` limpo, `npx vitest run` 101/101, `tsc --noEmit` limpo. Não validado em hardware — exigiria revogar um device de teste real com outro restante ativo. | achado investigando o P54 (Sessão 206) | 🟠 Média — não bloqueia nada hoje (nunca disparou em produção), mas corrompia o estado local na primeira revogação real com devices restantes |

### Validações em Hardware Real

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P3 | **Validação E2E real — extensão (13.9)** — fluxo completo: extensão carregada unpacked + celular real na mesma Wi-Fi, scan → perfil → envio → confirmação das entradas na popup. LAN e dead-drop. | `PHASE.md` (Fase 13.9, pendências finais) | 🟠 Média |
| P6 | **Revalidar decifra da vault key de pareamento (ECIES)** em hardware real — corrigido na Sessão 92 (SHA-256 do shared secret) + 99 (Mac.empty no Dart), mas nunca confirmado ao vivo no celular. | `PHASE.md` (Fase 13.9, pendências finais) | 🟠 Média |
| P7 | **Diálogo de Local Network Privacy do iOS** — mitigação aplicada (timing), não validada em device real. | `PHASE.md` (Fase 13.9, pendências finais) | 🟡 Baixa |
| P30 | **Validação E2E real — autofill de endereço (15.4, fatia 1)** — extensão carregada unpacked num formulário real (`autocomplete="street-address"` etc) + celular físico na mesma Wi-Fi: detecção do campo, QR, LAN (ou IP manual), picker no Mobile, preenchimento de volta no formulário. **Achado real na Sessão 182 (validando o P33, mesmo gesto de permissão compartilhado)**: o clique no ícone in-page realmente não propagava gesto de usuário até `chrome.permissions.request()` — já corrigido (ver P33). Ainda falta o resto do roteiro específico deste item (QR real + celular físico), que não foi tocado nesta sessão. | `PHASE.md` (Fase 15.4, fatia 1) | 🟠 Média |
| P31 | **Validação E2E real — autofill de cartão de crédito (15.4, fatia 2)** — mesmo roteiro de P30, agora com `autocomplete="cc-number"`/`cc-exp`/`cc-csc` num formulário de checkout real. Mesma limitação de hardware (P30 nunca foi validada também). | `PHASE.md` (Fase 15.4, fatia 2) | 🟠 Média |
| P32 | **Validação E2E real — dead-drop do autofill (15.4, fatia 2)** — mesmo roteiro de P30/P31, mas forçando o caminho sem LAN compartilhada (celular em rede diferente do navegador): confirmar que o Mobile publica no nome IPNS certo, que a extensão resolve via `pullFromDeadDrop`/`background.ts` e decifra corretamente. Nunca testado contra um gateway IPFS real nem contra o Kubo do dono do projeto. | `PHASE.md` (Fase 15.4, fatia 2) | 🟠 Média |
| P33 | **Validação E2E real — autofill via Desktop loopback (15.4, fatia 2) — 2 bugs reais achados e corrigidos na Sessão 182, protocolo confirmado de ponta a ponta.** Testado ao vivo (Brave real + extensão carregada unpacked + TruthID Desktop nativo, tudo na mesma máquina, sem precisar de celular). Achados: **(1) gesto de usuário perdido no pedido de permissão** — `chrome.permissions.request({origins:['http://*/*']})` sempre falhava com `"This function must be called during a user gesture"` (confirmado rodando direto no console do service worker) quando disparado via `chrome.runtime.sendMessage` do clique no ícone in-page → background.ts (`AUTOFILL_ENSURE_HOST_PERMISSION_MESSAGE`) — o "fluxo de concessão que já funciona hoje" documentado no próprio `background.ts` (clicar "I scanned it — look for my phone" no popup) **também estava quebrado no Brave**: o handler desse botão (`popup/main.ts::findButton`) fazia `return` antecipado no check `!isNetworkDiscoverySupported()` (verdadeiro no Brave, que desativa `chrome.system.network`) **antes** de chegar em `ensureHostPermission()` — ou seja, não existia nenhum caminho real de concessão da permissão no Brave. Corrigido invertendo a ordem: `ensureHostPermission()` roda primeiro (aproveita o gesto real do clique), o check de LAN vem depois só pra decidir se vale a pena varrer. Confirmado com o prompt nativo do Chrome/Brave aparecendo pela primeira vez ("TruthID Vault has requested additional permissions... Allow"). **(2) CORS ausente no servidor loopback** — mesmo com a permissão concedida, o fetch de `/truthid/v1/autofill-address`/`-creditcard` (que roda no content script, sujeito a CORS da origem da página — diferente de fetches do background, que não são) sempre falhava com erro de CORS: `local_signer_server.rs` nunca setava nenhum header `Access-Control-Allow-Origin`. Corrigido com `tower-http::cors::CorsLayer::permissive()` no router (mesmo modelo de confiança da nota de segurança já existente — localhost já é confiável, CORS aberto pro navegador não amplia a superfície real de ataque). **Confirmado**: `curl -i` mostra `access-control-allow-origin: *`; a extensão real conseguiu achar a porta (`ping` 200), mandar o POST de autofill (parqueado, "Pending" no Network tab), e o `AutofillAddressApprovalModal` do Desktop apareceu com o candidato certo do vault local (`Casa Teste`) — confirma o protocolo inteiro funcionando de ponta a ponta pela primeira vez. **Não confirmado**: o clique em "Use this address" e o preenchimento visual de volta no formulário do navegador — bloqueado pela mesma flakiness de clique do mouse no WebView do Tauri já documentada no P46 (não um bug novo; o mecanismo por trás já foi provado funcionando no P46 quando o clique acerta). Achado colateral, não confirmado: depois de um reload do frontend do Desktop com uma requisição ainda parqueada no Rust (confirmado via 409 Conflict num pedido concorrente), o modal não reapareceu — pode ser um bug real em `get_pending_autofill_address_request`/`useIncomingRequest`, mas não investigado a fundo. `cargo test --lib` 135/135, `npx vitest run`/`tsc --noEmit` (extensão) limpos. **Efeito colateral da validação**: 2 entradas de teste (`Casa Teste` endereço, `Nubank Teste` cartão) ficaram no vault local, não publicadas on-chain — dono do projeto pode removê-las quando quiser. | `PHASE.md` (Fase 15.4, fatia 2); `SESSIONS.md` (Sessão 182) | 🟡 Baixa — protocolo confirmado, falta só o clique final de aprovação (mesma limitação do P46) |
| P34 | **Validação E2E real — Android Autofill Framework (15.5)** — habilitar "TruthID" em Configurações → Sistema → Idiomas e entrada → Serviço de preenchimento automático, num device físico (API 26+), e testar num app terceiro real: campo com hint reconhecido oferece "Fill with TruthID", `PendingIntent` abre a `MainActivity`, o picker mostra as entradas certas, `EXTRA_AUTHENTICATION_RESULT` é aceito pelo framework e o campo é preenchido de verdade. Nunca rodado fora de testes automatizados/build de APK — nenhuma parte do fluxo de autofill de SO (detecção de campo via `AssistStructure`, `PendingIntent`, `Dataset` de autenticação) foi exercitada contra o framework real do Android. | `PHASE.md` (Fase 15.5) | 🟠 Média |
| P38 | **Validação em hardware real — Social Recovery UI (Fase 16)** — `GuardianManagement.tsx` (Desktop) e `GuardianStatusScreen.dart` (Mobile) nunca foram clicados de verdade, só `tsc --noEmit`/`flutter analyze`/testes automatizados (Sessões 178). Falta: configurar guardiões de verdade no Desktop nativo contra o `RecoveryManager` da Mainnet, propor/aprovar/executar/cancelar um recovery real (ou pelo menos até o timelock, sem esperar 7 dias), e confirmar que o `GuardianStatusScreen` do Mobile reflete o estado on-chain via pull-to-refresh. | `SESSIONS.md` (Sessão 178) | 🟠 Média |
| P37 | **Validação E2E real — documentos separados do blob (15.7) — parcialmente fechada, Sessão 181.** Publicados 2 documentos reais no Desktop contra Kubo local de verdade (`ipfs.service`). **Confirmado**: o blob do documento pina como objeto IPFS totalmente separado do blob principal do vault — isolado via diff do `pin ls` do Kubo antes/depois de um publish isolado (exatamente 2 CIDs novos: o vault v11 e o documento, distintos); buscar o CID do documento num gateway público (`ipfs.io`) funciona de verdade (HTTP 200) e o hash bate byte a byte com o Kubo local — confirma resolução correta "num 2º device sem cache local". **Não confirmado**: "cache local funciona offline" — bloqueado pela fragilidade de clique no botão ⭐/"Baixar" documentada e fechada como risco aceito no P46 (ver "Resolvidas"): os botões de entradas tipo documento não respondem a clique de forma confiável neste ambiente, então não foi possível exercitar a leitura via UI (só a escrita/publish foi validada). | `PHASE.md` (Fase 15.7) | 🟠 Média — falta só a parte de leitura, mesma fragilidade de clique do P46 |
| P35 | **Build real — `AutofillExtension` (15.6, fatia 1 + fatia 2)** — target criado programaticamente (gem `xcodeproj`) e validado só por inspeção (dependency, embed phase, bundle id, entitlements, configs Debug/Release/Profile, frameworks linkados) — nunca compilado, este ambiente é Linux, sem Xcode/macOS/simulador. Checklist de validação num Mac real, fundindo fatia 1 e fatia 2 (ver P36, que foi fundido aqui): (1) abrir `Runner.xcodeproj`, confirmar que builda sem erro nos 2 targets; (2) habilitar "TruthID" em Ajustes → Senhas → Preencher senhas automaticamente; (3) confirmar que as identidades registradas via `ASCredentialIdentityStore` aparecem na lista/QuickType bar; (4) abrir o app, desbloquear o Vault (dispara `IosAutofillVaultSyncService.sync`) e confirmar que a chave/blob chegam no Keychain Access Group/App Group compartilhados; (5) num app ou site real com campo de senha, confirmar que o preenchimento de verdade funciona — Face ID/passcode do sistema, escolha na lista (`prepareCredentialList`) e auto-preenchimento direto (`prepareInterfaceToProvideCredential`); (6) forçar os caminhos de erro (Vault nunca sincronizado, entrada removida) e confirmar que cancela com mensagem sensata em vez de travar. | `PHASE.md` (Fase 15.6, fatias 1 e 2) | 🟠 Média |

### Funcionalidades Não Implementadas

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P9 | **Phase 15 — Autofill SO (Android/iOS)** — implementar `AutofillService` e `ASCredentialProviderViewController`. **Android (15.5) concluído na Sessão 174** — `TruthIdAutofillService.kt` detecta campos e delega a leitura/aprovação pra Activity Flutter existente (mesmo Vault/AppLockGate/picker da Fase 15.4), sem duplicar acesso ao vault em Kotlin. **iOS (15.6) concluído por completo na Sessão 176** — target `AutofillExtension` (fatia 1, S175) + decifra real dentro da extensão via Keychain Access Group/App Group compartilhados (fatia 2, S176, `CredentialProviderViewController.swift`/`SharedVaultAccess.swift`), só credencial (endereço/cartão não têm extension point público no iOS, achado real da fatia 1). Falta só validar em Mac real (P35). | `PHASE.md` (Fase 15, etapas 15.5/15.6) | 🟠 Média |
| P47 | **`site/` — próximas fatias, fora do escopo do v1** — billing (Stripe/Mercado Pago) + Entitlement Service, bootstrap de identidade TruthID sem Ledger (item 2.1 do épico de tier facilitado), GitHub e o próprio TruthID como provider adicional de login (modelo `Identity` já suporta). Migração de `docs/` (Docusaurus) pro site **fechada na Sessão 200** pro que já existia: Fumadocs em `/docs` no `site/frontend`, identidade visual reaplicada (teal/cyan + Inter/Space Grotesk), deploy estático no GitHub Pages (só a doc, não o app inteiro), conteúdo expandido com 8 páginas novas + correções reais (P48, fechado na mesma sessão — ver "Resolvidas"). Billing/Entitlement/bootstrap sem Ledger seguem em desenvolvimento, mas **decisão explícita do dono do projeto (Sessão 200): sem lançamento ao vivo por um bom tempo** — prioridade atual é continuar a doc. Nenhuma dessas fatias tem `/plan` rodado ainda. | `SESSIONS.md`/`ROADMAP.md` (Sessão 199, 200) | 🟡 Baixa |
| P28 | **SDK Dart: transporte deep link no `TruthIDRequester`** — só cross-device (QR) implementado. Deep link (mesmo aparelho) exigiria o app host registrar seu próprio esquema de URI, específico de plataforma — decidido deixar de fora de um pacote Dart puro por ora. Reavaliado na Sessão 165: hoje nem o Mobile aceita deep link pra `pin`/`vault-edit` (só `sign-message`/`sign-request`), e um pacote Dart puro não consegue automatizar o registro de URI scheme do app hospedeiro nem depende de `url_launcher` — decisão confirmada, segue de fora. | `SESSIONS.md` (Sessão 161, reavaliado 165) | 🟡 Baixa |
| P49 | **Internacionalização (i18n) — seleção de idioma no software e na documentação.** Pedido original na Sessão 202 (registrado sem escopo nem `/plan`). **Sessão 208**: `/plan` rodado, decisões travadas com o dono do projeto — as 4 superfícies entram (Desktop, Mobile, extensão, site incluindo a doc pública) e os idiomas-alvo são pt-BR, es e zh-CN além do inglês (idioma-base). Arquitetura por superfície documentada — Mobile: `flutter_localizations`+`intl`+ARB; Desktop: `i18next`+`react-i18next`; extensão: `chrome.i18n` nativo; site: i18n nativo do Fumadocs pra doc pública + `next-intl` pra landing/dashboard — plano salvo em `~/.claude/plans/bora-continuar-para-mudar-calm-sifakis.md`. **Extensão fechada de ponta a ponta nesta sessão**: `_locales/{en,pt,es,zh_CN}/messages.json` (68 chaves), manifest com `__MSG_extName__`/`__MSG_extDescription__` + `default_locale`, popup localizado via atributos `data-i18n*` + `browser.i18n.getMessage` (idioma segue automaticamente o do navegador, sem seletor manual). `npx vitest run` 152/152, `tsc --noEmit`/`wxt build` limpos. **Desktop fechado de ponta a ponta na Sessão 209** — continuando um run de 11 agentes de uma sessão anterior que não tinha sido commitado nem documentado aqui (infra `i18next`/`react-i18next` e extração de chaves já estavam prontas pra 27 dos 29 componentes, sobreviveram intactas no working tree): terminado o wiring que faltava em `VaultManagement.tsx` (a função principal inteira, ~750 linhas, não tinha nenhum `t()` ainda) e `ErrorBoundary.tsx` (class component — usa `i18n.t()` direto em vez do hook, já que não dá pra usar `useTranslation` numa classe). **Achado real no caminho**: 9 arquivos JSON (`app`, `depositModal`, `donateModal`, `connectWallet`, `errorBoundary`, `localSignerStatus`, `pinApprovalModal`, `autofillAddressApprovalModal`, `autofillCreditCardApprovalModal`) tinham uma chave externa redundante que fazia `t()` nunca resolver — mostrava a chave crua na tela em vez do texto traduzido, afetando até o `PinApprovalModal` (aprovação de assinatura) e o `ErrorBoundary` (tela de erro); pego pelo `SmartAccountDashboard.test.tsx` (esperava string literal, recebia a chave crua) e corrigido removendo o wrapper redundante nos 9 arquivos. Traduções completas pra pt-BR/es/zh-CN feitas em seguida (478 chaves cada, 3 sub-agentes em paralelo, um por idioma), usando o glossário de `extension/public/_locales/` como referência de terminologia pra manter consistência com a extensão. Paridade de chaves e de `{{placeholders}}` validada nos 4 idiomas via script, zero divergência. `tsc --noEmit`/`npx vitest run` (101/101) limpos. Commitado (`18b1982`). **Mesma decisão da extensão**: sem seletor de idioma manual, detecção automática via `navigator`/`localStorage`. **Não validado**: nunca rodou o app de verdade pra conferir visualmente (só checagem estática/testes automatizados) — tradução automática pode estourar layout, ainda não foi olhado na tela. **Mobile e site** seguem só com a normalização de texto de UI residual em português para inglês — nenhuma infra de i18n de verdade neles ainda. | conversa direta (Sessão 202); escopo definido e extensão fechada na Sessão 208; Desktop fechado na Sessão 209 | 🟡 Baixa |

### Pendências de Arquitetura / Decisões em Aberto

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P14 | **Interface e identidade visual (UI/UX)** — app e desktop funcionais mas sem polish de produto final. Identidade visual já aplicada (Fase 9), mas fluxos e polish de produto pendentes. | `ARCHITECTURE.md` (tabela de decisões) | 🟡 Baixa |
| P15 | **Session key com limite de gasto** — desenho para evitar gas por mensagem (IA). Em aberto: onde registrar consumo on-chain vs off-chain, revogação em cascata. | `ROADMAP.md` (Monetização) | 🟡 Baixa |
| P16 | **Monetização — definições finais** — precificação ETH/BRL, modelo de consentimento do /pin, session key spending limit, margem de cada fonte de receita. Nada implementado. | `ROADMAP.md` (Monetização) | 🟡 Baixa |

### Ideias de Expansão (Brainstorm — sem `/plan`)

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| P18 | **Verifiable Credentials / Atestações ZK** — provar atributos sem revelar tudo (KYC descentralizado). | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P19 | **Delegação de acesso temporário** — sessões com escopo e prazo. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P20 | **Reputação on-chain portátil** — histórico de confiança consultável. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P21 | **Vault compartilhado (Family/Team)** — múltiplos Devices de pessoas diferentes. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P22 | **Detecção de vazamento de senha** — k-anonymity (HIBP-like). | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P23 | **Modo panic/duress** — PIN secundário mostrando vault vazio. | `ROADMAP.md` (Expansão) | 💡 Ideia |
| P24 | **Suporte a hardware wallets alternativas** — Trezor, YubiKey/FIDO2. | `ROADMAP.md` (Expansão) | 💡 Ideia |

---

## Resolvidas

### P51 — aviso de "vault legado" não cobria o caso de falha total (sem cache, sem permissão de escrita) (Sessão 207)

| ID | Item | Onde se originou | Prioridade |
|---|---|---|---|
| ~~P51~~ | ~~`_buildLegacyStorageBanner()` em `vault_screen.dart` (Mobile) só renderiza atrás de `if (_canWrite && _legacyIpfsCid)`, escrito pra outro cenário (S201: device que **já tem** cache e só quer o nudge de republish). O caso real achado na Sessão 204 é diferente — um device sem cache local (read-only ou não) tentando resolver um vault ainda no cid IPFS legado cai direto em `VaultSyncStatus.syncFailedNoCache`, mostrando o erro técnico cru dos gateways IPFS sem nenhuma explicação. Causa raiz em `VaultSyncService.sync()`: a variável `ref` (que tem o cid on-chain) só existia dentro do escopo do `try`, invisível no `catch` que chama `_fallbackToCache()` — não tinha como saber ali se a falha era por causa do esquema legado ou de outra coisa qualquer.~~ **Corrigido**: ~~`ref` foi hoisted pra fora do `try` (`VaultRef? ref;` antes do bloco, atribuído sem `final` dentro dele) — o `catch` agora consegue checar `ref != null && !ref.cid.startsWith('ar://')` e propaga isso como `legacyIpfsCid` pro `_fallbackToCache()`, que passou a aceitar o parâmetro e repassá-lo pros dois outcomes que produz (`offlineUsingCache` e `syncFailedNoCache` — antes só os dois caminhos de sucesso setavam o campo). Em `vault_screen.dart`, o branch de `syncFailedNoCache` bifurca: com `legacyIpfsCid` verdadeiro, mostra "Vault on legacy storage" com instrução acionável (pedir pra outro device com cache sincronizado republicar pro Arweave) em vez do erro cru — independente de `_canWrite`, já que mesmo um device com permissão de escrita não consegue republicar sem ter cache nenhum pra ler.~~ **Fora de escopo, decidido por ser o fix mais estreito que cobre o cenário real relatado**: ~~não foi criada uma variante do banner informativo pra devices read-only com cache (a 2ª alternativa cogitada no achado original) — o caso descrito na S204 era falha total (sem cache), não um device read-only que já sincroniza normalmente.~~ ~~`flutter test` 586/586 (2 novos: um em `vault_sync_service_test.dart` provando que a detecção olha o prefixo do cid — não fica `true` incondicional só por `ref` existir — e um em `vault_screen_test.dart` confirmando a mensagem nova substitui a antiga), `flutter analyze` limpo (mesmos 6 avisos pré-existentes).~~ | conversa direta (Sessão 204), corrigido Sessão 207 | **Sessão 207** |

### P54 — mismatch real de vault key Desktop↔device pareado, fechado e validado em hardware (Sessões 205/206)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P54~~ | ~~Achado na Sessão 205 validando o P52 num celular físico (Z Flip, `SM-S731B`, device "S25 FE teste", `0x9f0E2AF37dcEA864F9F5DA7891AcdDC3d4A0A545`): a chave que o celular recuperava via `deviceVaultKeys` não batia com a que o Desktop usa pra publicar — `SecretBoxAuthenticationError` mesmo com o conteúdo certo (hash batendo contra o `contentHash` on-chain). Investigação da Sessão 206 (sem hardware disponível): `cast call deviceVaultKeys(...)` confirmou blob ECIES válido (93 bytes) on-chain, descartando "campo Encryption key em branco". Achado mais forte por forense de arquivos em `~/.truthid/`: `vault.key` (fallback em arquivo de `get_vault_key()`) tinha conteúdo idêntico ao keyring do SO mas foi escrito em `2026-08-12` (mesmo dia do pareamento deste device) e era **dono por `root`** — junto com `arweave_wallet.json` também de `2026-08-12`/dono `root` — sinal de uma execução com sessão/contexto diferente do usuário normal, sem acesso ao keyring da sessão do usuário, rodando naquele dia. Hipótese de causa raiz: se o keyring também falhasse pra LEITURA nesse mesmo contexto durante `encrypt_vault_key_for_device`, a função (que na época não tinha fallback estrito) caía silenciosamente pro tier 3 — a chave legada derivada da device key, nunca da wallet — entregando ao celular uma chave que nunca poderia bater com o vault real. **Corrigido independente da confirmação definitiva da causa**: `get_current_vault_key_strict()` novo (Rust) — `encrypt_vault_key_for_device` nunca mais cai silenciosamente pro fallback legado, erra explicitamente em vez disso. Novo caminho de recuperação sem revogar/re-parear nada: `RedistributeVaultKey.tsx` (Desktop) reenvia a vault key atual pra um device já registrado, só precisando colar a chave pública crua dele de novo (mesmo campo do pareamento) — mobile ganhou um botão "Show encryption key" novo (`devices_screen.dart`) pra reexibir esse valor num device já pareado, que antes só existia na tela de pareamento inicial. **Validado ao vivo na Sessão 206**: dono do projeto conectou a Ledger física, confirmou a transação `updateDeviceVaultKey`, `cast call` confirmou o blob on-chain mudou; no celular (depois de contornar 2 obstáculos de ambiente sem relação com o fix — tela travando sozinha entre comandos adb, exigindo desbloqueio manual repetido, e o bug conhecido do Impeller/tela preta da Sessão 123, resolvido com `am force-stop`+reabrir), a aba Vault carregou as entradas reais (`127.0.0.1`, `Casa Teste`, `Nubank Teste`) sem nenhum erro de decifra. Fecha o P54 de ponta a ponta. Achado colateral sem relação direta, registrado à parte: P56 (rotação de DEK ao revogar device nunca funcionou, corrigido no mesmo caminho).~~ | **Sessão 206** |

### P55 — crash real no Mobile: `canWriteVault()`/`pendingChanges()` sem proteção travavam a tela do Vault pra sempre (Sessão 205)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P55~~ | ~~Achado ao vivo validando o P52 num celular físico (Z Flip): `_VaultScreenState._load()` (`vault_screen.dart`) chama `_syncService.sync(...)` primeiro — que já trata decifra local falhando graciosamente (`syncFailedNoCache`) — mas logo depois chamava `_repository.canWriteVault(address)` e `_repository.pendingChanges()` **sem nenhum try/catch**, cada uma fazendo sua própria leitura+decifra do `vault.enc` local. Com o cache local desse celular ilegível (ver P54), essas duas chamadas lançavam `SecretBoxAuthenticationError` direto, derrubando `_load()` inteira ANTES do `setState` — a tela ficava girando o spinner pra sempre, mesmo quando `sync()` já tinha resolvido tudo certo. Corrigido envolvendo as duas chamadas num try/catch com fallback seguro (`canWrite = false`, `pending = 0`), mesma filosofia que `VaultSyncService._fallbackToCache` já usa. `flutter analyze` limpo, `flutter test` 584/584 (1 teste novo, simula as duas chamadas lançando e confirma que a tela mostra o resultado do sync em vez de travar). **Validado em hardware real**: rebuild do APK debug + `adb install -r` no celular físico — a tela passou a mostrar "Could not load your vault" com o erro real em vez de ficar carregando pra sempre.~~ | **Sessão 205** |

### P52/P53 — vault de `@masterlxz` destravado do CID IPFS morto; achado sistêmico de devices não reautorizados pós-cascata (Sessão 205)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P52~~ | ~~**Vault real de `@masterlxz` (identityId 1) preso no CID IPFS morto**~~ — causa raiz era dupla, as duas corrigidas e validadas ao vivo. **(1)** `IdentityContext.tsx` só expunha `smartAccountAddress` derivado de `useAccount().address` (CREATE2 síncrono, passado de `App.tsx`) — só existe se uma wallet estiver conectada *nesta sessão do app*. O botão "Publicar via device key (sem Ledger)" herdava esse mesmo valor; sem wallet conectada (justo o cenário que o botão promete cobrir), `smartAccountAddress` ficava `null` → "Nenhuma identidade carregada". Corrigido priorizando `identity.controller` — já devolvido pela leitura on-chain de `getIdentity(username)` que o contexto já fazia, é o mesmo endereço da smart account e só depende do username em cache local. **(2)** Corrigido esse ponto, apareceu um erro novo e mais fundo — `AA24 signature error` — ver P53 abaixo. Depois do fix do P53, republish confirmado on-chain de ponta a ponta, independente do app: `getVault(1)` no `VaultRegistry` (`0x0744...849b4`, Base Mainnet) foi de `QmeY4no...` (versão 1, IPFS morto) pra `ar://9_sUbYf4K9w9bOxqkzjIf_r8v4OvhbMTEcwDNHGq-TM` (versão 2, Arweave), `updatedAt` batendo com o horário real do teste (16/08/2026 19:03 UTC).~~ | **Sessão 205** |
| ~~P53~~ | ~~**Achado sistêmico: nenhum device consegue assinar UserOp pra `@masterlxz` desde a cascata da Sessão 197** — `DeviceRegistry.migrateDevices()` (ver [[project-cascade-migration-197]]) migrou os *registros* (label/addedAt/revoked/chave ECIES) pro `DeviceRegistry` novo, mas nunca chamou `TruthIDAccount.addDevice()` na smart account nova, que é uma mapping separada (`authorizedDevices`) dentro do próprio contrato da conta — é ela, não o `DeviceRegistry`, que `_validateSignature` checa de fato. Confirmado via `cast call` num RPC público: dos 7 devices listados em `getDevicesByIdentity(1)`, todos vinham `authorizedDevices() == false` na smart account atual (`0xAa45...eDa05`) antes do fix — só a Ledger (owner) conseguia assinar qualquer coisa; Mobile e Desktop via device key estavam quebrados pra essa identidade desde 13/08/2026, não só o publish do vault. Achado colateral: `DesktopDevice.tsx` só checava `DeviceRegistry.isDeviceActive()` (global) pra decidir se mostrava "✓ Registered" ou o botão de registro — como isso já vinha `true` da migração, o botão nem aparecia, sem nenhum caminho de UI pra corrigir. Corrigido em `ManageDevices.tsx`: nova leitura de `authorizedDevices()` por device na smart account atual (`useReadContracts`), filtrando os já revogados; se detectar a lacuna, mostra banner + botão "Reautorizar N devices" — um `executeBatch` só, uma confirmação na Ledger, sem re-parear nada (pubkeys já conhecidos on-chain). `tsc --noEmit` limpo, `npx vitest run` 101/101. **Validado ao vivo pelo dono do projeto**: dos 7 devices, os 4 ativos (3 já revogados antes da migração corretamente ignorados pelo lote) foram de `false` pra `true` em `authorizedDevices()`, confirmado via `cast call` independente do app.~~ | **Sessão 205** |

### P50 — bug real de scan de QR no Mobile, corrigido e validado em hardware (Sessão 204)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P50~~ | ~~Abrir a câmera de QR no Mobile (`mobile/lib/screens/scan_screen.dart`, usado pelo pareamento de leitura da extensão entre outros fluxos) sempre falhava com "Unexpected error occurred" em hardware real (Samsung Galaxy S25 FE, Android 16/API 36) — confirmado via `logcat` que não era permissão (já concedida): `NoSuchMethodException: com.google.mlkit.vision.common.internal.VisionCommonRegistrar.<init>`, causado por um bug conhecido do pacote `mobile_scanner` 6.x onde o R8 (modo full, padrão desde AGP 8.0) corrompe/obfusca classes do ML Kit acessadas via reflexão — corrigido oficialmente rio-acima na versão 7.2.1 (`CHANGELOG.md` do pacote, confirmado via fetch direto do GitHub). Corrigido atualizando `mobile_scanner: ^6.0.0` → `^7.4.0` (mais recente, sem breaking change relevante pro uso deste projeto — só `MobileScanner`/`BarcodeCapture`/`analyzeImage`, nenhuma API removida/alterada em uso). Aproveitado pra adicionar um `errorBuilder` de verdade em `ScanScreen` (não existia nenhum tratamento de erro antes, caía no fallback genérico do pacote sem nenhum diagnóstico). `flutter analyze` limpo, `flutter test` 582/582. **Validado em hardware real**: rebuild do APK debug + reinstalação via `adb install -r` no device físico, scan de QR real confirmado funcionando pela pessoa dona do projeto.~~ | **Sessão 204** |

### P46/P11 — decisões do dono do projeto: fecha investigação do bug do ⭐, define modelo de consentimento do /pin (Sessão 202)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P46~~ | ~~Botão ⭐ (favoritar)/"Baixar" não responde a clique de forma confiável — **fechado por decisão do dono do projeto, não por fix**: a investigação da Sessão 182 já tinha esgotado o que dava pra provar sem clique físico real ou devtools (mecanismo funciona quando o clique acerta, causa raiz é a fragilidade do alvo, não o handler). Sem hardware/ambiente novo pra investigar mais fundo, o dono do projeto decidiu não seguir tentando — risco aceito como conhecido, registrado, não escondido. Não desbloqueia o P37 (mesma fragilidade de clique continua impedindo a validação de leitura de documentos), só encerra a linha de investigação em si.~~ | **Sessão 202** |
| ~~P11~~ | ~~Modelo de consentimento do `/pin` decidido pelo dono do projeto: **aprovação por chamada**, mesmo padrão do `/sign-message`/`/sign-request` — sem autorização persistida por app nem cota diária. Achado no caminho: o modelo até então implementado no Desktop (`pin.rs`, autorização por app + `DEFAULT_DAILY_LIMIT=50`/dia, "fatia 3" da Sessão 106) nunca tinha sido registrado como resolvido aqui, apesar de já estar em produção desde 2026-07-17 — o Mobile (fluxo cross-device via QR) sempre foi por chamada, então os dois lados divergiam até esta sessão. `pin.rs` reescrito seguindo o padrão de `sign_message.rs` (state vira só `SingleSlotChannel`, sem arquivo `pin_authorizations.json`); comandos Tauri `pin_get_authorizations`/`pin_revoke_authorization`/`pin_set_daily_limit` e a seção `PinAuthorizationsSection` de `VaultSettings.tsx` removidos (ficaram órfãos); `PinApprovalModal.tsx` simplificado pro texto único (sem distinção "app novo" vs "cota estourada"), mirror do `SignMessageModal.tsx`. Doc pública (`concepts/cross-device-and-storage.mdx`, `apps/mobile.mdx`, escritas no P48) corrigida — descreviam o modelo antigo como fato atual. `cargo test --lib` 182/182, clippy limpo, `tsc --noEmit`/`npx vitest run` (101/101) limpos, `npm run build` do site limpo.~~ | **Sessão 202** |

### P48 — Expansão de conteúdo da doc (Sessão 200, continuação)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P48~~ | ~~8 páginas novas em `site/frontend/content/docs/` (`concepts/{vision,how-it-works,vault,recovery,cross-device-and-storage}`, `apps/{desktop,mobile,extension}`, `structure.mdx`), com conteúdo verificado direto no código-fonte (`contracts/`, `mobile/`, `desktop/`, `extension/`, `project/CONTEXT.md`) por 3 buscas de pesquisa em paralelo antes de escrever qualquer linha. Aproveitado pra corrigir erros reais já publicados nas 10 páginas antigas: contrato faltando (`VaultRegistry`, eram descritos "quatro contratos", são seis), claim errado de iOS Secure Enclave (não suporta secp256k1, a curva que os device keys realmente usam), link quebrado pro `PROJECT_STATE.md` (arquivo não existe mais), audit status incompleto (faltava a reentrância C1 do `RecoveryManager`), instalação do SDK Dart apontando pra pacote nunca publicado no pub.dev, "immutable" simplificado demais (sem proxy, mas com `updateRegistries` que já habilitou 4 redeploys em cascata). Cada tópico tem um dono canônico (`contracts.mdx` pra endereços/funções, `how-it-works.mdx` pro fluxo do protocolo) — as outras páginas linkam em vez de duplicar. Nada de monetização/pricing, conforme a decisão da mesma sessão. `npm run build`/`npm run lint` limpos; screenshots confirmaram sidebar, tabelas, callouts e navegação prev/next renderizando certo~~ | **Sessão 200** |

### P1/P2/P26 — Redeploy em cascata do débito #52, migração real de identidade na Mainnet

| ID | Item | Resolvida em |
|---|---|---|
| ~~P1~~ | ~~Deploy em cascata (`DeviceRegistry` débito #52) — 6 contratos redeployados em Sepolia (rehearsal) e Mainnet (`IdentityRegistry`, `DeviceRegistry`, `RecoveryManager`, `TruthIDAccountFactory`, `SessionRegistry`, `VaultRegistry`), todos com os fixes C1-C9. Novo `DeviceRegistry.migrateDevices()` (função de uso único, 9 testes novos) portou os 7 devices da identidade real (`masterlxz`, Sessão 116) numa única transação — status idêntico ao legado (3 revogados, 4 ativos), sem re-pareamento físico. Smart account mudou de endereço (`0x6689...` → `0xAa45...`, inevitável — CREATE2 depende do endereço da factory, e a conta antiga tinha os registries `immutable`, sem `updateRegistries`). Saldo ETH e ponteiro do vault (mesmo CID) migrados via `execute()` direto da Ledger. Endereços novos propagados em Desktop/Mobile/4 SDKs/docs/READMEs~~ | **Sessão 197** |
| ~~P2~~ | ~~Deploy do `RecoveryManager` corrigido (C1 — reentrância) — parte da mesma cascata~~ | **Sessão 197** |
| ~~P26~~ | ~~Assinatura de sessão desalinhada com o fix C4 (domain separation) — `SESSION_DOMAIN_SEPARATION_ENABLED`/`sessionDomainSeparationEnabled` ligadas em Desktop e Mobile agora que o `SessionRegistry` novo (com o fix C4) está live~~ | **Sessão 197** |

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

### P36 — decifra do Vault dentro da extensão iOS (Sessão 176)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P36~~ | ~~15.6, fatia 2 — `CredentialProviderViewController` só mostrava uma tela informativa e cancelava~~. `CredentialProviderViewController.swift` agora decifra AES-256-GCM (`CryptoKit.AES.GCM.SealedBox(combined:)`, o layout do blob `nonce\|\|ciphertext\|\|tag` bate byte a byte com o formato `combined`, sem slicing manual) usando chave/blob compartilhados via Keychain Access Group + App Group (`SharedVaultAccess.swift`, duplicado nos 2 targets — contrato próprio, não depende do schema interno do `flutter_secure_storage`). Novo canal `truthid/ios_autofill_vault_sync` (`AppDelegate.swift`, 2 métodos: `syncVaultKey`/`syncVaultBlob`) + `IosAutofillVaultSyncService` (Dart, novo) espelham chave+blob toda vez que `vault_screen.dart::_load()` recarrega (reaproveita `VaultRepository.readRawBlob()`/`VaultKeyService.deriveVaultKey()`, já existentes). `prepareInterfaceToProvideCredential` preenche direto pelo `recordIdentifier`; `prepareCredentialList` mostra um picker simples (`UITableView`) de todas as entradas tipo credencial; `provideCredentialWithoutUserInteraction` continua cancelando de propósito, forçando o gate de Face ID/passcode que o próprio iOS já exige antes de invocar a extensão. `Security.framework`/`CryptoKit.framework` linkados no target (mesma referência `SDKROOT`-relativa da fatia 1). Checklist de validação em hardware **fundido em P35** — nada disso builda neste ambiente Linux, sem Xcode/macOS/simulador, mesma limitação já registrada na fatia 1. `flutter analyze`/`flutter test` (lado Dart) verificados nesta sessão.~~ | **Sessão 176** |

### P8 — Fase 15 (Digital Identity Vault) concluída por completo, 15.1-15.8 (Sessão 177)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P8~~ | ~~Fase 15 — Digital Identity Vault (documentos, endereços, cartões de crédito), 8 etapas~~. Última etapa, 15.8 (revisão de segurança): auditoria confirmou zero logging real (grep completo, nenhum print/console.log/dbg!/tracing toca card_number/cvv em produção ou testes), fechou preventivamente um `impl Debug` customizado redigindo `card_number`/`cvv` na `CreditCardData` (Rust) contra vazamento futuro por `dbg!`/`tracing`. Implementada a cifra individual de `card_number`/`cvv` (tentativa+fallback, mesmo padrão de migração de chave que `vault::load()` já usa — sem flag de schema nova), sempre em claro em memória e sempre cifrada em disco/export, reusando a mesma vault key (sem sub-chave derivada). Achado crítico corrigido: o reparse inline de `vault_publish`/`markPublished` (otimização pré-existente que evita `load()` duplicado) não normalizava os campos de cartão, o que geraria "pendência fantasma" pra sempre em qualquer vault com cartão — corrigido com teste de regressão nos 2 lados. Achado real de exposição mínima: `toJsonForExtension()` só removia `totp_secret`, não `document`/`address`/`credit_card` — uma entrada de cartão sincronizada pelo canal QR mais antigo (13.9) vazava em texto pleno pro `chrome.storage.session` da extensão; corrigido. `_MaskedInfoRow` (Mobile) trocou máscara proporcional ao tamanho por máscara fixa (vazava comprimento do PAN/CVV). Polish: campos de cartão no formulário Desktop ganharam reveal toggle igual senha. `cargo test --lib` 135/135, `flutter test` 496/496, `flutter analyze`/`npx vitest run` 101/101/`tsc --noEmit`/`cargo clippy`/`cargo fmt --check` limpos.~~ | **Sessão 177** |

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

### P17 — Social Recovery UI (Sessão 178)

| ID | Item | Resolvida em |
|---|---|---|
| ~~P17~~ | ~~**Social Recovery (UI)** — N-de-M guardiões com multisig/timelock. Contrato `RecoveryManager` já existia e estava deployado, mas sem interface de usuário. Implementado: `GuardianManagement.tsx` (Desktop) com configurar/propor/aprovar/executar/cancelar recovery + `GuardianStatusScreen.dart` (Mobile, só leitura). Aba "Recovery" adicionada ao Desktop App.tsx. ABI completo do RecoveryManager adicionado aos dois lados. `tsc --noEmit` limpo, 101/101 testes passando. Redeploy em cascata (P1/P2) não é pré-requisito — a UI funciona contra o contrato atual~~ | **Sessão 178** |
| ~~P5~~ | ~~**Validação E2E real — assinatura via device key no Mainnet** — device key do Desktop e bundler já estavam prontos (herdado do P4, mesma sessão). Clicado "Publicar via device key (sem Ledger)" na aba Vault: primeira tentativa falhou com "todos os providers Kubo falharam" (`ipfs.service` systemd --user instalado mas inativo nesta máquina) — dono do projeto autorizou `systemctl --user start ipfs`, segunda tentativa funcionou. Vault foi de versão 8 pra 9. **Confirmado on-chain via `cast call getVault(1)` num RPC público, independente do app**: `version=9`, `updatedAt=1785599131` (01/08/2026 15:45 UTC, bate com o horário real da sessão). Prova real do pipeline UserOp+bundler assinando só com device key, sem toque físico no Ledger, contra a Mainnet.~~ | **Sessão 181** |
| ~~P45~~ | ~~**`queryClient.invalidateQueries()` sem filtro** (`GuardianManagement.tsx`, configureGuardians/propose/approve/execute) — invalida o cache do app inteiro (vault, sessões, devices, saldos) a cada ação de guardião, não só as queries de recovery. **Fechado como não-bug**: é o mesmo padrão usado em `App.tsx` (botão "Refresh" manual), `ManageDevices.tsx`, `WithdrawModal.tsx`, `DesktopDevice.tsx` e `CreateIdentity.tsx` — convenção deliberada do projeto (refetch amplo após qualquer escrita), não um descuido isolado do Recovery. Corrigir só aqui quebraria a consistência e arriscaria parar de atualizar saldo/devices depois de uma ação de guardião, que hoje dependem desse invalidate global. Dono do projeto escolheu não mexer.~~ | **Sessão 181** |
| ~~P44~~ | ~~**Timelock de 7 dias hardcoded 2x** (`timeRemaining`/`canExecute`) em vez de reusar o `timelock` já lido do `TIMELOCK()` do contrato. Se o contrato fosse redeployado com timelock diferente, o contador regressivo e o gate do botão Execute ficariam dessincronizados do texto. Corrigido: `timeRemaining` ganhou um 2º parâmetro `timelockSecs` (default `7n * 86400n` só como fallback pra janela breve antes do `TIMELOCK()` carregar — default de parâmetro JS já cobre `timelock` chegando `undefined`), os 2 call sites (identidade própria e a seção do P39) passam o valor real; `canExecute` ganhou a mesma guarda `timelock !== undefined` que `canTargetExecute` (P39/P41) já tinha desde que nasceu.~~ | **Sessão 181** |
| ~~P43~~ | ~~**No-op silencioso quando `smartAccountAddress` é `null`** (`handleConfigure`/`handleCancel`) — diferente das outras validações nas mesmas funções, que chamam `setConfigError(...)`, esses branches só davam `return` sem nenhum feedback visual. Corrigido: `handleConfigure` chama `setConfigError(...)` (reusa o estado/exibição já existentes); `handleCancel` ganhou um `cancelError` local novo, exibido junto do erro de transação já existente.~~ | **Sessão 181** |
| ~~P42~~ | ~~**`hasApproved` indefinido mostrava "Approve" pra quem já tinha aprovado** — mesmo padrão do P41 (query separada carregando à parte, estado de loading tratado como negativo). Contrato já protegia via revert (`AlreadyApproved`), só gerava um prompt de transação falho confuso. Corrigido com `isHasApprovedLoading`/`isTargetHasApprovedLoading` gateando os dois pontos (identidade própria e a nova seção "Act as Guardian" do P39, que nasceu com o mesmo padrão) — mostra "Checking approval status…" em vez do botão/badge até a leitura resolver.~~ | **Sessão 181** |
| ~~P41~~ | ~~**`canExecute` corria à frente do `threshold` real** — `getProposal` e `getGuardianConfig` carregam de forma independente; se a proposta resolvesse antes do threshold (que ficava `0n` por padrão), "Execute Recovery Now" aparecia disponível antes da hora. Contrato já protegia via revert (`ThresholdNotReached`), então era só UX ruim, não risco de segurança. Corrigido reusando o mesmo `isGuardianConfigLoading` do P40 como guarda extra em `canExecute`.~~ | **Sessão 181** |
| ~~P40~~ | ~~**Risco de sobrescrita silenciosa de guardiões reais** — `guardianConfig` ficava `undefined` enquanto `getGuardianConfig` carregava, então `isConfigured` caía no default `false` e mostrava "No guardians configured" mesmo com guardiões já configurados; num RPC lento, clicar em "Configure Guardians" nesse estado sobrescreveria a lista real. Corrigido: novo `isGuardianConfigLoading` (de `useReadContract`) gateia o aviso — enquanto carrega, mostra "Loading guardian configuration…" em vez do aviso; o aviso "No guardians configured" (e o botão que abre o form) só renderiza depois que a leitura resolve de verdade. `tsc --noEmit`/`vitest run` (101/101) limpos.~~ | **Sessão 181** |
| ~~P39~~ | ~~**Fluxo de guardião (Propose/Approve) inalcançável na prática** — `GuardianManagement.tsx` usava `username` do `IdentityContext`, que sempre resolve pra identidade de quem está conectado, sem campo de busca. Corrigido: nova seção "Act as Guardian" com input de username + botão "Look up", reads (`getGuardianConfig`/`getProposal`/`hasGuardianApproved`) e handlers (`proposeRecovery`/`approveRecovery`/`executeRecovery`) próprios, escopados ao username buscado (`guardianTarget`), totalmente separados dos da identidade própria — nenhum comportamento existente (configurar/cancelar a própria identidade) foi tocado. `canTargetExecute` já nasce sem a corrida do P41 (guarda `targetThreshold > 0n`). `tsc --noEmit`/`vitest run` (101/101) limpos. Validado com clique real no Desktop nativo: buscar o próprio username mostra corretamente "You are not a guardian for @masterlxz" (nenhum guardião configurado ainda) — confirma que o lookup lê o contrato pelo username buscado, não mais pelo da identidade logada.~~ | **Sessão 181** |
| ~~P4~~ | ~~Validação E2E real — delegação de assinatura (Desktop + Practice Valuation). Colisão de porta 1420 já não existia mais (Practice Valuation fixou 1430/1431 permanentemente antes desta sessão). Achado real: primeira tentativa de Approve com o Ledger conectado na conta errada ("Account 0" do modal) devolveu `AA20 account not deployed` — `smartAccountAddress` é derivado do endereço conectado via `computeSmartAccountAddressSync`, então conectar a conta errada aponta pra um CREATE2 nunca implantado. Achado o endereço certo lendo `owner()` da smart account on-chain via `cast call` (bate com "Account 1" do Ledger). Reconectado, novo sign-request, Approve → `Status: executed`, `userOpHash`/`transactionHash` reais. **Confirmado on-chain via `cast receipt` num RPC público, independente do app**: bloco 49402374, `status: 1 (success)`, `to` é o EntryPoint v0.7. Primeira vez que o caminho completo (app terceiro → loopback → aprovação → Ledger → UserOp → bundler Pimlico → EntryPoint) roda de ponta a ponta contra a Mainnet de verdade~~ | **Sessão 179** |