## Roadmap de Evoluções Planejadas

### Sinalização sem servidor — IMPLEMENTADO (Sessão 26, continuação)

**Decisão final**: a ideia original era ir pra sinalização on-chain (eventos+transação). Investigando o desenho, percebemos que isso teria 3 problemas reais: (1) latência — WebRTC de verdade troca várias mensagens, e cada uma virando transação passaria de ~7-10s por login; (2) custo — cada tentativa de login gastaria gas, mesmo as que o usuário nunca completa; (3) a chave do device no mobile não tem fundos por design (só assina, nunca paga gas), então o mobile nem teria como submeter uma transação de qualquer forma. **Solução adotada: transporte direto, sem blockchain e sem servidor do TruthID.**

**Login** (mobile ⇄ backend do site):
- O QR mostrado pelo site já contém o challenge completo + um `callbackUrl` (a própria `/auth/verify` que o integrador já roda, documentada no `sdk/README.md`)
- Mobile lê o QR, assina, e faz `POST` HTTPS direto pro `callbackUrl` — sem WebSocket, sem relay
- `https://` é obrigatório — o app recusa `callbackUrl` que não seja https (`approval_screen.dart`)
- O frontend do site aprende o resultado do jeito que ele já notifica sua própria UI (polling no próprio backend, SSE, etc.) — fora do escopo do TruthID, é o mesmo padrão de qualquer callback OAuth-like

**Pareamento** (mobile ⇄ desktop):
- Inverteu a direção do QR: antes o desktop mostrava e o mobile escaneava (e mandava a chave por WebSocket); agora o **mobile mostra** seu próprio endereço (`show_device_qr_screen.dart`) — ele é o único lado que já tem essa informação, não precisa de rede pra exibi-la
- Desktop lê (hoje só colar manual — câmera é melhoria de UX futura, ver Fase 8) e segue com o commit-reveal já existente, sem mudança nenhuma na parte on-chain
- Confirmação: o mobile faz polling de `getDevice(meuEndereço)` na blockchain (leitura gratuita) até `exists && !revoked` — não existe "pair-confirmed" enviado por ninguém (esse recurso nunca funcionou de verdade antes, ver achado da Sessão 22)

**O que NÃO mudou**: contratos de identidade, DeviceRegistry, SDKs, lógica de verificação (TTL, nonce, assinatura) — tudo isso já era independente de transporte.

**Removido do repositório**: `signaling/` (FastAPI/WebSocket), `turn/` (coturn) e `webrtc-demo/` — confirmados como código morto (nenhum dos dois fluxos de produção dependia deles; só existiam pelo prototype abandonado da Fase 2/Sessão 20).

**Trade-off original (Sessão 26) revisitado na Sessão 45**: o `IdentityRegistry` não tem `id → username`, mas o evento `IdentityCreated(uint256 indexed id, string username, address indexed controller)` emitido no deploy é indexado pelo `id`. Na Sessão 45 o mobile passou a resolver `@username` via `eth_getLogs` filtrando pelo topic do `id` — `getUsernameForIdentity(BigInt id)` em `blockchain_service.dart`. Username cacheado em `FlutterSecureStorage` após o pareamento; limpo junto com `clearPairedIdentity`. Sem redeploy de contrato.

---

### Callback opcional no login (fallback on-chain) — ideia externa (Sessão 94, 2026-07-12; corrigida Sessão 95, 2026-07-12)

**Contexto**: durante uma conversa sobre o Practice Valuation (outro projeto do dono, app de valuation de ações/cripto, `~/Documents/workspace/practice-valuation`), surgiu a necessidade de ele reaproveitar o login/identidade do TruthID em vez de um sistema de conta próprio. Só brainstorm — nenhum `/plan` rodado, nada implementado.

**Login hoje exige callback HTTPS obrigatório — trava integradores sem backend público.**
`ApprovalScreen` (`approval_screen.dart:88-96`) recusa qualquer QR sem `callbackUrl` https — um app desktop local sem servidor próprio (como o Practice Valuation) fica de fora do fluxo de login atual.

Achado ao investigar o código: a escrita da sessão on-chain (`SessionCreator` via UserOperation, dentro de `_approve()`) **já acontece incondicionalmente**, antes até do POST pro callback (ver comentário em `sdk/typescript/src/client.ts` sobre o mobile v14.9.5+). Ou seja, o "canal de fallback" que resolveria isso não precisa ser construído do zero, só **exposto**: tornar `callbackUrl` opcional no payload do QR e, quando ausente, pular só o `_postResponse` HTTPS — a escrita on-chain (que já ia rodar de qualquer forma) vira o único sinal de sucesso. Nesse modo, o integrador faria polling de `getSession`/`isSessionRevoked` (já expostos em `SessionRegistry`, leitura pública e gratuita) em vez de receber POST.

**Ressalva de segurança**: o `https://` obrigatório existe pra impedir que um QR malicioso redirecione a resposta assinada pro servidor de um atacante. A extensão certa é permitir **omitir** o callback inteiramente — nunca afrouxar pra aceitar `http://` (ex: pensando numa LAN) como substituto, isso reabriria o mesmo risco que a checagem atual evita.

**Correção da Sessão 95 sobre o Vault**: a Sessão 94 também levantou generalizar o `VaultRegistry` (Fase 13) pra múltiplos vaults por identidade, pensando em servir o Practice Valuation. O dono do projeto corrigiu isso: **não é o que ele quer**. O `VaultRegistry` continua exatamente como está — 1 vault por `identityId`, uso exclusivo do password manager, sem alteração nenhuma. O Practice Valuation é outro software; ele só precisa do esquema de login/autenticação do TruthID (o item de callback opcional acima). Sincronização de dados do Practice Valuation via IPFS, se acontecer, é responsabilidade só dele — sem tocar em `VaultRegistry` nem na cifra ECIES derivada do pareamento.

**Design fechado na Sessão 95** (ainda não implementado, sem `/plan` rodado): ordem confirmada é POST HTTPS primeiro quando `callbackUrl` existir, escrita on-chain como sinal de fallback quando não existir. Como a escrita on-chain já é incondicional (roda antes/independente do POST), não precisa de lógica nova de retry ou detecção de falha — se o POST falhar (callback configurado mas servidor fora do ar), o comportamento atual (loga e desiste, sem retry) se mantém; o integrador pode cair pro polling on-chain por conta própria já que o dado está lá de qualquer forma. Resumo do escopo de implementação, quando for retomado:
- Tornar `callbackUrl` opcional no payload do QR / schema de pareamento.
- `ApprovalScreen` (`approval_screen.dart:88-96`): parar de rejeitar QR sem `callbackUrl`; pular só o `_postResponse` HTTPS quando ausente.
- Manter a validação `https://` obrigatória quando o campo **está** presente (não afrouxar pra `http://`).
- Documentar pro integrador (SDK/docs) o modo polling via `getSession`/`isSessionRevoked` como alternativa ao callback.

Retomar quando o dono do projeto voltar ao assunto — provavelmente puxado pelo lado do Practice Valuation, que é quem tem o caso de uso concreto hoje (ver `PROJECT_STATE.md` de lá, Fase 8).

---

### Vault genérico multi-app + delegação de assinatura via session key — brainstorm (Sessão 96, 2026-07-13); fatia 1 (Sessão 102), fatias 2a/2b/3 (Sessão 103), `/sign-message` (Sessão 107) implementadas

**Reabre, sob um desenho diferente, a parte de "Vault genérico" que a Sessão 95 tinha fechado como "não é o que o dono do projeto quer".** A diferença desta vez: não é mais "generalizar o Vault de senhas", é um mecanismo novo — apps terceiros (Practice Valuation sendo o primeiro caso real) sincronizando dados próprios via IPFS com o CID atual registrado on-chain, no mesmo padrão que o `VaultRegistry` já usa (`identityId → {cid, contentHash, version}`), mas sem tocar no vault de senhas existente.

**Correção importante feita na Sessão 102, antes de qualquer código**: o texto original mencionava um "Paymaster" cobrindo o gás das UserOperations de apps terceiros — isso **não existe** no TruthID (descartado deliberadamente na Sessão 52). O que existe é mais simples: a própria smart account do usuário paga o próprio gás (ETH que ela já tem depositado), igual já acontece hoje pro Vault de senhas.

**Reescopo feito na Sessão 102 a partir de uma pergunta do dono do projeto** ("mas isso não é o app terceiro que tem que se preocupar?"): o desenho original cogitava um contrato `AppVaultRegistry` novo, de posse do TruthID, pra guardar CIDs de apps terceiros. Reconhecido que isso é desnecessário — o app terceiro (Practice Valuation) traz e mantém o **próprio** contrato; o TruthID só precisa ser um "assinador genérico": recebe um pedido de assinatura pra uma chamada arbitrária, mostra pro usuário (decodificando de verdade a chamada, não confiando só numa descrição livre — escolha do dono do projeto), usuário aprova, TruthID assina e executa. Nenhum contrato novo do lado TruthID é necessário — `blockedForDevices` é uma lista de bloqueio, não permissão; um contrato de terceiro nunca listado ali já é chamável por um device autorizado, sem mudança nenhuma no `TruthIDAccount.sol`.

**Fatia 1 (Sessão 102, 2026-07-14) — Desktop ganha assinatura via device key, sem Ledger**: pré-requisito descoberto durante o desenho — o Desktop só assinava escrita via Ledger (toque físico); o pipeline de UserOperation+bundler (que permite assinar sem toque, com a device key) só existia no Mobile. Portado pro Desktop: `desktop/src/utils/userOperation.ts` (empacotamento + hash, mirror de `mobile/lib/utils/user_operation.dart`), `desktop/src/services/pimlicoBundlerClient.ts` (mirror de `pimlico_bundler_client.dart`), `desktop/src/services/userOpExecutor.ts` (mirror de `SessionCreator._executeViaUserOp`). Rust: `sign_session_hash` refatorado (extraído `sign_eip191_hash_raw`, comportamento idêntico) + novo comando `sign_user_op_hash`; novos `get_bundler_config`/`save_bundler_config` (mirror de `pinning_providers.json`). `useVaultPublish.ts` ganhou um segundo botão, "Publicar via device key (sem Ledger)", ao lado do caminho Ledger já existente — mesma ação real (`VaultRegistry.updateVault`), caminho de assinatura novo.

**Validado com vetores cruzados do Mobile, não só round-trip interno**: os 5 vetores de `mobile/test/utils/user_operation_test.dart` (hash de UserOp, gerados originalmente via `viem`) bateram de primeira em `userOperation.test.ts`; o vetor de `device_key_signature_vector_test.dart` (chave #0 do Anvil, assinatura conhecida) bateu de primeira no novo teste Rust `sign_eip191_hash_raw_matches_known_vector_from_dart_and_viem`. `tsc`/`vitest`(56/56)/`cargo test`(28/28) limpos.

**Pendência real, achada ao tentar validar contra o Mainnet**: o device key do Desktop (`0xfd23ed10b147f2557d0f072b1d10f6575c300f65`, confirmado via leitura pública) **nunca foi registrado on-chain** (`DeviceRegistry.getDevice` reverte — device não existe) — provavelmente porque o Desktop sempre assinou escrita via Ledger, nunca precisou ser pareado como device antes. Pra validar de verdade contra o Mainnet falta: (1) o dono do projeto configurar `~/.truthid/bundler_config.json` com uma chave de API Pimlico (segredo — não deve ser manuseado pelo Claude); (2) parear este Desktop como device via o fluxo já existente em `DesktopDevice.tsx` (Ledger assina `DeviceRegistry.registerDevice` + `TruthIDAccount.addDevice`). Sem isso, a prova real fica pendente — todo o resto (matemática, assinatura, builds) já está provado.

**Fatia 2a (Sessão 103, 2026-07-14) — canal de comunicação local, só transporte**: confirmado com o
dono do projeto que o app terceiro roda como outro processo nativo na mesma máquina (não web app
no browser — sem CORS a resolver), e a fatia 2 foi quebrada em sub-fatias menores (mesmo padrão
da 13.9). Novo `desktop/src-tauri/src/local_signer_server.rs`: servidor `axum` bindado
estritamente em `127.0.0.1` (nunca `0.0.0.0` — principal propriedade de segurança que a fatia
entrega, já que ainda não há autenticação), tentando em ordem `CANDIDATE_PORTS = [47950..47954]`
(bloco próprio, longe de `47850..47854` do LAN da 13.9 e de `1420` do Vite). Sobe automático no
`tauri::Builder::setup`, fica no ar enquanto o app roda. Dois endpoints só de handshake —
`GET /truthid/v1/ping` e `POST /truthid/v1/handshake` — sem tocar nada sensível (o módulo nem
importa `vault`/`bundler`/`k256`). Comandos Tauri `local_signer_start/stop/status` + hook
`useLocalSignerServer.ts` + `LocalSignerStatus.tsx` (pill de status + kill switch), montado em
`DesktopDevice.tsx`. 6 testes Rust novos; achado no caminho: testes rodam em paralelo por padrão
e disputam as mesmas 5 portas candidatas contra o loopback real — precisou de um
`tokio::sync::Mutex` estático serializando o ciclo de vida completo de cada teste.

**Fatia 2b (Sessão 103) — endpoint de sign-request + modal de aprovação + decodificação**: duas
decisões negociadas antes de codar — (1) o app terceiro manda a `functionSignature` em texto
junto do pedido, o TruthID recalcula o seletor (`viem`'s `toFunctionSelector`) e confere contra o
`callData` antes de decodificar/exibir; se não bater, mostra bytes crus + aviso sem bloquear (a
aprovação humana é o ponto de confiança final, não uma checagem no Rust); (2) o
`POST /truthid/v1/sign-request` do app terceiro fica pendurado até o usuário decidir (padrão
`window.ethereum.request`), com timeout de 5min no Rust (sobrevive a UI travada). Novo
`desktop/src-tauri/src/sign_request.rs`: núcleo do protocolo (`handle_incoming`/`resolve`/
`current`) recebe "notificar a UI" como closure genérica em vez de `tauri::AppHandle` direto —
permitiu testar a lógica de negócio inteira em `#[tokio::test]` puro (parking, single-flight via
`Busy`, timeout com duração injetável) e, como bônus, testar a rota HTTP ponta a ponta via
`reqwest` real. Frontend: `SignRequestModal.tsx` (decodifica via `viem`'s `parseAbi`+
`decodeFunctionData`, reaproveita `executeViaUserOp`/`get_bundler_config` sem alteração nesses
arquivos) montado em 2 pontos de `App.tsx`. `cargo test` 41/41 (34+7 novos), `tsc --noEmit` limpo.

**Fatia 3 (Sessão 103) — Practice Valuation ganha cliente HTTP mínimo, prova de conceito**:
escopo negociado explicitamente antes de tocar no outro repo — só descobrir+handshake+1
sign-request real sem efeito econômico (transferência de valor zero pro endereço de burn), não a
Fase 8 completa (sync IPFS, generalizar `VaultRegistry`) que já estava brainstormada no
`PROJECT_STATE.md` do Practice Valuation e assumia Paymaster (que o TruthID não tem). Novo
`practice-valuation/desktop/src-tauri/src/commands/truthid.rs` (`discover`+2 comandos Tauri,
mesmo estilo de `AppError`/`reqwest` já usado em `commands/chat.rs` de lá) + aba nova "TruthID
Sync" (`TruthIdPanel.tsx`). `cargo check`/`tsc --noEmit` limpos nos dois repos.

**Não validado em nenhuma das 3 fatias**: nenhum clique real na UI do Desktop foi observado
acontecendo (a janela do Tauri não é capturável pelas ferramentas de screenshot/automação deste
ambiente) — toda validação foi via curl + testes automatizados. E os 2 apps (TruthID + Practice
Valuation) nunca rodaram ao mesmo tempo de verdade: colidem na porta 1420 do Vite por padrão, e a
Practice Valuation trava fora do Docker dela (`unable to open database file`) — não subi o Docker
dela sem pedir, dado o histórico de disco cheio compartilhado entre os 2 projetos.

**Lacuna de transparência corrigida (Sessão 104)**: quando a verificação de seletor falha, o
`SignRequestModal.tsx` agora mostra a `functionSignature` que o app terceiro declarou (rotulada
"unverified — does not match callData") além dos bytes crus do `callData` — o humano vê o que foi
*alegado*, não só que não bateu. `tsc --noEmit` limpo, `vitest run` 56/56.

**Fica pra uma fatia futura**: validação E2E real dos 2 apps rodando juntos (precisa resolver o
setup Docker da Practice Valuation e/ou a colisão de porta); validação real em Mainnet (bundler +
pareamento do device, pendência antiga da fatia 1); integração de fato/produção do lado do
Practice Valuation (hoje é só prova de conceito).

**Problema original**: Practice Valuation (Fase 8 do `PROJECT_STATE.md` dele) quer sincronizar valuations/alertas salvos entre desktop e celular via IPFS, com o CID atual registrado on-chain.

**Por que não dá pra só reaproveitar o `VaultRegistry` como está**: ele é 1 vault por identidade, dedicado ao password manager (ver `#### O que é aproveitável do código já existente`, Fase 13). Serviria um segundo app só generalizando pra algo tipo `identityId + appId → VaultRef`, permitindo múltiplos apps terceiros registrarem seu próprio slot de CID sob a mesma identidade.

**Segunda questão, mais sensível — como o app terceiro paga gas pra atualizar seu CID**: sem o usuário precisar da Ledger toda hora, e sem abrir brecha onde qualquer app "logado com TruthID" ganharia poder de assinar transação. Consenso da conversa (direção, não decisão final):

1. Login com TruthID (prova de identidade) e capacidade de assinar transação via smart account são coisas completamente separadas — login nunca deve dar poder de assinatura.
2. Apps terceiros como o Practice Valuation não devem ter chave privada própria nem assinar UserOperations diretamente. Fluxo proposto: o app terceiro monta a UserOperation (ex: "atualizar CID X no slot practice-valuation") sem assinar, manda o pedido pro TruthID (IPC/deep link se for o mesmo device; QR/P2P se forem devices diferentes — ex: celular com Practice Valuation pedindo aprovação pro TruthID do desktop), o TruthID mostra uma tela de aprovação clara ("Practice Valuation quer atualizar o vault dele. Permitir?" — mesmo padrão do approval screen que já existe pro browser extension, ver `#### Hierarquia de confiança: Devices vs. sessões de extensão`, Fase 13), o usuário aprova com um clique, e só então o TruthID assina com uma **chave de sessão escopada**, nunca com a chave raiz/Ledger. Paymaster cobre o gas via UserOperation patrocinada (mesma infra da Fase 14).
3. A chave de sessão precisa ser fortemente escopada: contrato de destino permitido (só o `VaultRegistry` generalizado), função permitida (só o método de update de CID), escopo/slot (só o `appId` do Practice Valuation, sem autoridade sobre o vault de senhas ou qualquer outro slot), expiração/revogação em cascata (revogar o device/app no TruthID mata a chave na hora — mesmo princípio de revogação em cascata já desenhado pra sessões de extensão na Fase 13).

**Em aberto, pra decidir num `/plan` futuro (não decidir sozinho, trazer opções pro dono escolher)**:
- `VaultRegistry` generalizado (`identityId + appId → VaultRef`) vs. contrato irmão dedicado — trade-off complexidade vs. reuso.
- O canal de "app terceiro pede pro TruthID assinar" reaproveita o approval flow que já existe pra extensão, ou precisa de canal novo — IPC local (mesmo device) vs. QR/P2P (devices diferentes)?
- UX da aprovação: clique único a cada update (mais seguro, mais fricção) vs. sessão válida por N usos/tempo após a primeira aprovação (menos fricção, janela de exposição maior) — configurável no escopo da própria session key, mas é decisão de produto.
- Onde mora o "registro de apps terceiros autorizados" — nova entidade no schema do TruthID (tipo um `SessionRegistry` por app), ou estende algo que já existe.

**Nota (Sessão 106): os 4 pontos acima são o texto original da Sessão 96, desatualizado — todos já foram resolvidos pelas Fatias 1-3 (Sessões 102-103) na direção mais simples que venceu no reescopo da Sessão 102** (nada de session key/`VaultRegistry` generalizado/registro de apps: contrato é do app terceiro, canal é o `local_signer_server.rs` local já implementado, aprovação é sempre por clique único, sem sessão). Deixado como está por valor histórico; ver Sessão 106 abaixo pro que continua de fato em aberto.

Retomar quando o dono do projeto quiser rodar um `/plan` de verdade sobre isso — provavelmente puxado de novo pelo lado do Practice Valuation.

---

### Sessão 106 (2026-07-15, ideia externa — do lado do Practice Valuation) — duas capacidades genéricas novas propostas: `/sign-message` e `/pin`

**Contexto**: retomando a Fase 8 do Practice Valuation (sync de dados via IPFS), agora que o canal de assinatura delegada (Fatias 1-3 acima) já existe e já foi validado. Só brainstorm/registro — nenhum `/plan` rodado deste lado, nenhum código tocado no TruthID.

**Princípio confirmado pelo dono do projeto, explicitamente**: o que falta não deve virar privilégio específico do Practice Valuation — tem que ser capacidade **genérica**, disponível a qualquer app terceiro construído sobre o TruthID, seguindo o mesmo molde do `/sign-request` já existente (app nunca segura o segredo, só pede pro TruthID agir por ele, com aprovação humana no meio).

**1. `POST /truthid/v1/sign-message` (implementado na Sessão 107 — ver entrada abaixo)** — hoje o canal só assina UserOperations; sincronizar dados via IPFS precisa de uma chave simétrica compartilhada entre os dispositivos do usuário, e a forma natural de obter isso sem inventar segredo novo é assinar uma mensagem fixa e derivar a chave da assinatura (mesmo princípio que `useVaultKey.ts` já usa internamente pro password manager, assinando `"TruthID Vault Key v1"` — só que isso não é exposto a apps terceiros). Desenho proposto, espelhando `sign_request.rs`:
- App terceiro manda `{appName, purpose}` (`purpose` é um identificador curto, não texto livre)
- TruthID monta a mensagem final de forma padronizada no próprio Rust, não manipulável pelo chamador — ex. `"TruthID Message Signing: {appName}:{purpose}"` (domain separation, evita colisão entre apps/propósitos)
- Mesmo padrão de parking+aprovação do `sign_request.rs` (evento pro frontend, timeout 5min, single-flight), com uma tela genérica ("**{appName}** quer derivar uma chave de assinatura pra si — aprovar?")
- Assina via `personal_sign` reaproveitando a primitiva já usada por `useVaultKey.ts`/`sign_eip191_hash_raw`, devolve só a assinatura — quem deriva a chave (HKDF) é o app chamador, localmente; o TruthID nunca sabe pra que serve
- Canal isolado do password manager — mensagem própria, nunca reaproveita `"TruthID Vault Key v1"`

**2. `POST /truthid/v1/pin` (novo, não implementado) — ideia levantada pelo dono do projeto nesta sessão, não estava em nenhum brainstorm anterior**: como o TruthID já é a porta única que qualquer app descentralizado construído sobre ele precisa passar, o mesmo raciocínio de "não duplicar segredo" vale pro pinning de IPFS. Em vez de cada app terceiro pedir pro usuário configurar/pagar um provider de pinning próprio, o TruthID poderia oferecer os providers que o usuário **já tem configurados** (`ipfs.rs`/`pin_vault`, sem alteração na lógica existente) como serviço:
- App terceiro manda o blob **já cifrado** (a cifra é sempre responsabilidade do chamador — o TruthID nunca vê conteúdo em claro)
- TruthID faz o upload usando os próprios providers configurados e devolve só `{cid, contentHash}` — a API key do provider (Pinata/PSA/Kubo) nunca sai do TruthID
- **Estritamente opcional** pro app terceiro — pode preferir trazer e pagar o próprio provider em vez de usar o do usuário via TruthID
- **Em aberto, não decidido**: modelo de consentimento. Assinar transação é raro (poucas aprovações esperadas); pinning pode ser frequente (ex: toda vez que o app salva um dado) — repetir aprovação por chamada, no mesmo padrão do `/sign-request`, pode ser fricção desnecessária aqui (diferente de assinar, que envolve fundos/autoridade real). Risco de abuso (app malicioso/com bug esgotando cota ou fatura do provider do usuário em loop) é real e precisa de algum limite — aprovação por chamada (simples, consistente) vs. aprovação única por app com teto de uso (menos fricção, mais lógica nova) fica pra decidir num `/plan` futuro.

**Nenhuma das duas rotas foi implementada** — só registradas aqui como pendência, pra retomar quando o dono do projeto quiser rodar um `/plan` de verdade de um dos dois lados (provavelmente TruthID primeiro, já que o Practice Valuation depende delas pra fechar a Fase 8 dele — ver `PROJECT_STATE.md` de lá).

**3. Correção feita ainda na mesma sessão, a partir de uma pergunta do dono do projeto**: as duas rotas acima (e o `/sign-request` já existente) hoje só funcionam quando o app terceiro roda **na mesma máquina** que o TruthID — `local_signer_server.rs` escuta estritamente em `127.0.0.1`. Cenário real levantado: e se o usuário só tiver o Practice Valuation no computador e o TruthID só no celular? Hoje **não tem canal nenhum** pra esse caso — uma versão anterior deste mesmo registro (do lado do Practice Valuation) chegou a marcar essa questão como resolvida/desnecessária, o que estava errado e foi corrigido ainda nesta sessão.

O TruthID já resolveu exatamente esse tipo de problema pra outro caso de uso — a extensão de navegador (Fase 13.9, Sessões 97-101): dois transportes tentados em paralelo, **descoberta na mesma rede local** (`vault_lan_server_service.dart`, servidor efêmero de 1 request, portas 47850-47854) e **dead-drop assíncrono via IPFS/IPNS** (funciona entre redes diferentes, propagação mais lenta). Segurança não depende de estar na mesma rede ser suficiente: o QR carrega um `sessionId` de 128 bits imprevisível, o servidor LAN devolve 404 uniforme pra path errado (sem oracle), e o payload é cifrado via ECIES pra uma chave pública efêmera que só existe no QR — só quem escaneou o QR de verdade consegue achar e decifrar o blob. Vale lembrar que essa mesma peça de ECIES teve um bug real que ficou sem detecção por várias sessões até ser pego contra hardware real (Sessão 99) — reforça que qualquer reaproveitamento precisa de validação em hardware real antes de confiar, não só round-trip interno.

**Em aberto, não decidido**: estender `/sign-message`/`/pin` (e possivelmente `/sign-request`) pra também aceitar esses dois transportes, no mesmo molde da 13.9, é trabalho novo — nada desenhado em detalhe ainda. Fica registrado junto com as outras duas pendências, pra um `/plan` futuro decidir.

**Nota (Sessão 108): fatia 1 do transporte cross-device (só LAN) implementada do lado Mobile — ver entrada da Sessão 108 abaixo.** Dead-drop IPFS/IPNS (fatia 2), `/pin`, e qualquer lado requisitante (app terceiro que gera o QR) continuam em aberto.

---

### Ideias de Expansão e Roadmap — "app global de segurança" self-sovereign (registrado
2026-07-17, Sessão 121; conversas de 2026-06 a 2026-07-01, fora do Claude Code)

**Fonte**: `~/Downloads/TruthID - Ideias de Expansao e Roadmap.md` (última atualização
2026-07-01), anotações de conversas sobre evolução do TruthID. Puro brainstorm — nenhum `/plan`
rodado, nenhum código tocado, registrado aqui pra não se perder (a versão em `~/Downloads`
continua sendo o rascunho original, este é o registro oficial no projeto).

**Visão geral**: evoluir o TruthID de um sistema de identidade pra um ecossistema completo de
segurança digital self-sovereign — identidade + gerenciador de senhas/passkeys/2FA + conta
cripto, tudo com a mesma raiz de confiança (Ledger).

**1. Roadmap principal (foco apontado nas conversas, não necessariamente ordem de execução)**

1. **Social Recovery** — recuperação via N-de-M guardiões (multisig/timelock), usando o
   `SessionRegistry`/`DeviceRegistry` já existentes. Resolve "e se eu perder o Ledger".
2. **Verifiable Credentials / Atestações ZK** — provar atributos sobre a pessoa sem revelar tudo
   (ex: "maior de 18", "dev verificado") via zero-knowledge proofs. Abre porta pra KYC
   descentralizado e monetização B2B (ver item 4 da lista de receita, abaixo).
3. **Delegação de acesso temporário** — sessões com escopo e prazo definido, construindo sobre
   os contextos Work/Home do Vault. Casos de uso: suporte técnico, compartilhamento pontual.
4. **Reputação on-chain portátil** — módulo de "histórico de confiança" (tempo de conta,
   recuperações, atestações recebidas) consultável por outros protocolos — diferencial
   competitivo frente a Worldcoin/Civic.
5. **Passkeys / WebAuthn**:
   - Virtual authenticator: expõe interface WebAuthn, guarda a chave privada cifrada no Vault.
   - Novo `credential_type: passkey` no `VaultRegistry`.
   - Fluxo de criação: manual, via ação do usuário no próprio cadastro do site (a extensão
     **não oferece proativamente** criar passkey).
   - Entrada de passkey agrupada com a senha do mesmo site — uma única credential record por
     domínio (senha + passkey juntos).
6. **2FA / TOTP**:
   - Guarda o `secret` (seed base32) cifrado no Vault, gerador de código local (RFC 6238).
   - **Regra de segurança inegociável**: 2FA/TOTP nunca é manipulado pela extensão de
     navegador — fica isolado no app/desktop. Preserva a separação real dos fatores (se a
     extensão guardasse tudo, colapsaria os fatores de 2FA em um só).
7. **Backup criptografado exportável**:
   - Arquivo `.truthid-backup`: blob único cifrado com chave derivada da master key do device
     (ou senha extra).
   - Fluxo de restore: novo device root gera chave, reidrata o Vault a partir do backup.
   - Pode combinar com Social Recovery (guardiões ajudam a recuperar a chave de decriptação do
     backup).

**2. Decisões de arquitetura já discutidas pra extensão de navegador**

**Princípio central**: a extensão nunca tem autoridade de escrita no Vault — só relaia e faz
autofill. Pra credenciais novas (senha ou passkey) criadas via extensão: material cifrado com a
chave de sessão existente, enviado ao **Device raiz persistente** (mobile/desktop) pra aprovação
e commit, reaproveitando o mesmo mecanismo de aprovação já usado no upgrade de sessão via QR P2P.
A extensão participa da cerimônia criptográfica (precisa, é ela que interage com a página), mas
**quem persiste é sempre o Device raiz**.

**2.1 Sync em lote (batch sync)** — **implementado na Sessão 166** (registrado como P29 em
`PENDING.md`). Resolve o problema de UX de gerar um QR por credencial alterada, e reduz custo de
gas (1 transação por sessão de edição, não por item):
1. Extensão acumula edições pendentes localmente, em memória de sessão cifrada (`pendingEdits.ts`
   já era uma lista desde o início — nada precisou mudar aí).
2. Ao clicar em "Send to this computer"/"Send to phone", empacota tudo (a leva inteira, não só a
   1ª) num payload único.
3. Device mostra uma lista com todas as propostas da leva (site/usuário/senha mascarada/badge de
   passkey por item).
4. Na aprovação, N `addEntry`/`vault_upsert_entry` locais seguidos de **1 publish() só**, no fim.

**Achado real ao implementar, mudando o desenho original**: o passo 4 originalmente dizia "a smart
account assina uma única `UserOperation` em lote (estilo `execBatch`)" — na prática isso não é
necessário. `VaultRegistry.updateVault` sempre grava um único `(cid, contentHash)` por publish,
não importa quantas entradas mudaram no blob local — então já era **sempre** 1 UserOperation por
publish, mesmo antes do sync em lote existir. `executeBatch` (que existe no `TruthIDAccount.sol` e
funciona, validado em hardware real nas Sessões 115-117) nunca foi usado nesse caminho — só em
transações diretas do owner (Ledger) durante pareamento de device, sem relação nenhuma com o
Vault. "1 transação por sessão de edição" já era o comportamento natural do publish existente; o
trabalho real do sync em lote foi só de UX/transporte (extensão manda N propostas juntas, Device
revisa e persiste as N antes de publicar), não de infraestrutura on-chain nova.

O passo 3 original ("mostra resumo das mudanças + taxa de gas estimada") teve a parte de "taxa de
gas estimada" deixada de fora — nenhuma tela de aprovação do projeto mostra estimativa de gas hoje,
seria uma capacidade nova sem precedente, fora do escopo do sync em lote em si.

O passo 5 original ("ordem crítica: pinning no IPFS antes da assinatura do commit on-chain") já era
garantido pelo próprio `VaultPublishService.publish()`/`vault_publish` (Rust) — pina no IPFS e só
depois assina o `updateVault`, mesma ordem de sempre, nada novo precisou ser construído pra isso.

**3. Ideias exploratórias (não são foco, registradas pra não perder)**

- Anti-phishing domain-binding: vincular credenciais salvas ao domínio exato, reforçado pela
  resistência nativa a phishing do WebAuthn.
- Vault compartilhado (Family/Team): múltiplos Devices de pessoas diferentes acessando um
  subconjunto de credenciais compartilhadas, com controle de acesso multisig. Possível ângulo de
  monetização B2B.
- Log de atividade/auditoria: histórico de quando cada Device acessou uma credencial, pra
  detectar uso suspeito.
- Auto-fill inteligente com detecção de formulário + preenchimento de senha e código 2FA já
  calculado.
- Compartilhamento de emergência (estilo "emergency access" do 1Password), com delay de
  segurança cancelável.
- Detecção de vazamento de senha via k-anonymity (estilo Have I Been Pwned).
- Auditoria/"security score" do Vault (senhas fracas/reutilizadas, 2FA ausente).
- Modo panic/duress (PIN secundário que mostra vault vazio/falso).
- Suporte a hardware wallets alternativas como root key (Trezor, YubiKey/FIDO2).

**Nada implementado, nada desenhado em detalhe — fica pra quando o dono do projeto quiser rodar
um `/plan` de verdade sobre algum desses itens.**

---

### Backlog pós-item 6: QR no TOTP, passkey na extensão, gerador de senha em popup, bug de
"pending changes" falso no Mobile (registrado 2026-07-19, Sessão 130)

**Contexto**: pedido explícito do dono do projeto — só registrar estas 5 ideias/achados agora, sem
implementar nada nesta sessão ("não precisa implementar tudo numa porrada só"). Cada item roda
depois, um de cada vez, em sessão própria (provavelmente com `/plan`).

1. ~~**Ler QR code do 2FA (TOTP) no celular e no desktop**~~ — **CORRIGIDO na Sessão 132**
   (2026-07-19), validado em hardware real dos dois lados. Ver detalhe técnico completo logo
   abaixo, na entrada de sessão.

2. ~~**Passkey deveria ir pra extensão — hoje não vai, de propósito**~~ — **Fase 1 (login)
   CORRIGIDA na Sessão 133**, validada em hardware real. Fase 2 (criação de passkey via extensão +
   canal de aprovação em lote) registrada como item novo do backlog, ver entrada de sessão logo
   abaixo pro detalhe técnico completo.

3. ~~**Gerador de senha do Desktop "esquisito" — virar popup**~~ — **CORRIGIDO na Sessão 135**
   (2026-07-19). Era um painel inline dentro do próprio formulário
   (`desktop/src/components/VaultManagement.tsx`); Mobile já resolvia isso como bottom sheet
   (`vault_entry_form_screen.dart`, Sessão 128), Desktop ficava fora da paridade. Novo
   `desktop/src/components/PasswordGeneratorModal.tsx`, mesmo padrão de modal já usado por
   `TotpQrScanner` (`modal-overlay`/`modal-box`) — a lógica de estado (`genOptions`/`genPreview`/
   `genError`) continua em `VaultManagement.tsx`, só a apresentação virou popup. `tsc --noEmit`
   limpo, `vitest` 93/93. **Validado com clique real no Desktop nativo** (`GDK_BACKEND=x11`): popup
   abre ao clicar 🎲, toggle de categoria regenera a preview ao vivo, "Usar esta senha" aplica no
   campo Senha (medidor de força confirmou "Muito forte") e fecha o popup.

4. ~~**Bug reportado: "pending changes" falso no Mobile depois de sync**~~ — **CORRIGIDO na Sessão
   131** (2026-07-19). Publicar uma entrada nova no Desktop, o Mobile puxava a atualização certinho
   (aparece a entrada nova), mas continuava mostrando "N pending changes" como se tivesse mudança
   local não publicada. **Causa raiz**: `VaultRepository.pendingChanges()`
   (`mobile/lib/services/vault_repository.dart:494`) calcula `data.version - last`, onde `last` vem
   de uma chave própria do device (`vault_last_published_version` no `flutter_secure_storage`) que
   só era atualizada por `markPublished()` — chamado exclusivamente em
   `vault_publish_service.dart:66`, ou seja, só quando o **próprio Mobile** publica algo. Quando
   `VaultSyncService.sync()` puxava uma versão mais nova vinda de outro device e sobrescrevia o
   cache local (`vault_sync_service.dart:119`, `_repository.overwriteCache(bytes)` — o mesmo
   caminho do fix da Sessão 126 pro bug de perda de dados), nunca chamava `markPublished(ref.version)`.
   Então `data.version` subia (refletindo a versão nova sincronizada) mas o marcador de "última
   publicada por este device" ficava parado no valor antigo, e a subtração virava um número positivo
   de "pendências" que não existiam de verdade.

   **Fix**: `sync()` (`vault_sync_service.dart`) agora chama `markPublished(ref.version)` em dois
   pontos — (a) depois de `overwriteCache(bytes)`, no caminho de pull de uma versão mais nova; (b)
   no caminho de early-return, quando `ref.version == localVersion` (cobre o caso de um device que
   nasce já sincronizado com a versão on-chain atual, ex. logo depois do pareamento, e nunca chamou
   `markPublished` por conta própria — mesmo bug, caminho de código diferente). **Não** marca como
   publicado quando `ref.version < localVersion` (local genuinamente à frente, com edições reais
   ainda não publicadas) — esse caso continua contando certo, de propósito.

   2 testes de regressão novos em `vault_sync_service_test.dart`, reproduzindo os dois cenários
   corrigidos com chain mockada (ambos esperam `pendingChanges() == 0` depois do sync). Precisou
   adicionar o mock de `flutter_secure_storage` (`MethodChannel` + `TestWidgetsFlutterBinding.
   ensureInitialized()`, mesmo padrão de `vault_publish_service_test.dart`/Sessão 98) ao arquivo de
   teste, que antes não precisava disso (nenhum teste anterior passava pelo caminho que grava em
   secure storage). `flutter test`: 331/331 (2 novos), `flutter analyze` limpo.

   **Validado em duas frentes, sem gastar gas**: (1) build real instalado no celular físico
   (Samsung Galaxy S25 FE) — o vault real desse device mostrava "10 pending changes" já documentado
   como débito de teste conhecido da Sessão 126 (passkey de teste criada e apagada, nunca publicada,
   nenhuma sessão depois tocou o vault do Mobile de novo); (2) leitura on-chain direta e gratuita do
   `VaultRegistry` via `cast call getVault(uint256) 1` (eth_call, sem transação) confirmou
   `version=4` publicada — bate exatamente com `4 (chain) + 10 (edições locais reais, nunca
   publicadas) = 14 (local)`. Ou seja, o fix **não zerou** essa pendência real, confirmando que ele
   distingue certo "pendência real" (`ref.version < localVersion`, não mexe) de "pendência fantasma"
   (`ref.version >= localVersion`, corrige). Não foi feita uma publicação real a partir do Desktop
   pra provar o caminho inverso ao vivo (custaria gas real em Base Mainnet, não autorizado) — a
   cobertura fica pelos 2 testes automatizados que reproduzem exatamente esse caminho com mocks.

5. **Depois de tudo isso**: code review completo do app inteiro, atualizar documentação, e publicar
   o app — registrado como sequência pedida pro fim desta leva de trabalho. **`/code-review high`
   rodado sobre `mobile/` inteiro na Sessão 151** (2026-07-25): 10 achados (M1-M10 em
   `PENDING.md`), incluindo 2 de segurança (deep link bypassando `AppLockService`; login sem
   checagem de expiração de challenge) — **nada corrigido ainda**, ver `SESSIONS.md` Sessão 151
   pro detalhe completo. Documentação e publicação seguem pendentes até esses achados serem
   tratados.

6. **Fase 2: criação de credencial nova (senha e/ou passkey) direto na extensão + aprovação via
   Device** — registrado ao fechar a Sessão 133 (item 2 acima, Fase 1/login de passkey, fechou).
   **Escopo ampliado por pedido explícito do dono do projeto** (2026-07-19, mesma sessão, "não
   rodar ainda, só anotar"): não é só `navigator.credentials.create()` (passkey) — o mesmo padrão
   de aprovação vale pra **qualquer credencial nova criada a partir da extensão**, incluindo uma
   senha nova digitada/gerada direto num formulário de cadastro de site (a extensão hoje não tem
   nenhum jeito de criar entrada nova — só autofill de entrada já existente). Confirmado com o dono
   do projeto: **qualquer alteração no Vault iniciada pela extensão precisa de aprovação de um
   Device** (Desktop/Mobile) — a extensão nunca tem autoridade de escrita, princípio já registrado
   na seção "Decisões de arquitetura já discutidas pra extensão de navegador" acima, que já cobria
   isso pra "credenciais novas (senha ou passkey)" desde o brainstorm original — a Sessão 133 só
   reafirmou que vale pros dois, não só passkey.

   Isso exige construir do zero o "Sync em lote (batch sync)" descrito nessa mesma seção (2.1) —
   extensão acumula a credencial nova (senha ou passkey) em memória de sessão cifrada → gera QR →
   Device escaneia, mostra resumo + taxa de gas → aprova → smart account assina uma `UserOperation`
   (pinning no IPFS antes do commit on-chain, ordem crítica) — **nada disso existia até a Sessão
   134**, só desenho de papel. Peça de infraestrutura do tamanho do `/truthid/v1/pin` inteiro (3
   sessões).

   ~~Nenhum `/plan` detalhado rodado ainda~~ — **`/plan` completo rodado e aprovado na Sessão 134**
   (2026-07-19), com escopo explicitamente reduzido pra essa rodada (confirmado com o dono do
   projeto via `AskUserQuestion`): **só passkey** nesta fatia (senha nova via extensão fica pro
   próximo item do backlog — o desenho de "qualquer credencial" acima continua válido, só a
   implementação começou pela metade menor); e **os dois caminhos de entrega** (Desktop na mesma
   máquina via loopback HTTP, e celular via QR+LAN), confirmado porque o dono do projeto apontou
   explicitamente que "o device não necessariamente é o app no mesmo computador, pode ser a
   extensão no PC e autorizar com o celular".

   ~~Desktop e extensão fechados e validados; Mobile — a fatia final — ainda não implementada~~ —
   **fatia Mobile fechou 100% na Sessão 135, todo o fluxo (Desktop loopback + celular via QR+LAN)
   validado em hardware real na Sessão 136** (esta seção do ROADMAP nunca tinha sido atualizada
   depois disso — corrigido na Sessão 164, ver `PENDING.md` P10). **Senha nova via extensão**
   (a parte que de fato só tinha "desenho de papel" até então) **implementada na Sessão 164**: novo
   `extension/src/autofill/newCredentialCapture.ts` escuta submit de formulário e propõe a
   credencial pro Device aprovar quando não há entrada existente com esse username exato pro
   hostname — mesma heurística do "Salvar senha?" nativo dos navegadores, evita tentar distinguir
   estruturalmente cadastro de login. Reaproveita 100% da infra já validada pra passkey
   (`VaultEditProposal` já tinha `password` como campo de primeira classe e `passkey` opcional,
   zero mudança em `pendingEdits.ts`/`cipher.ts`/`mobileDelivery.ts`/`desktopDelivery.ts`/telas de
   aprovação/`vault_edit.rs`). `npx vitest run` (extensão) 86/86, `tsc --noEmit`/`npm run build`
   limpos. **Sync em lote (batch sync, seção 2.1 acima) implementado na Sessão 166** — bem menor
   escopo do que a estimativa original (~3 sessões) porque não precisou de `executeBatch`/infra
   on-chain nova, ver seção 2.1 pro achado completo. P29 em `PENDING.md`.

Nada implementado nesta entrada — só levantamento e registro de causa raiz (item 4), pra rodar item
por item nas próximas sessões.

---

### Monetização — brainstorm (registrado 2026-07-17, Sessão 121; conversa de 2026-07-17 fora do
Claude Code)

**Fonte**: `~/Downloads/TRUTHID_MONETIZACAO.md`. Puro brainstorm — nenhuma decisão final, nenhum
código tocado. Puxado pela motivação original de uma integração B3 (consolidação de carteira),
mas generalizado pra um modelo de cobrança aplicável a várias ideias de receita.

**Princípio geral (não negociável, definido pelo dono do projeto)**:
- **Nunca cobrar pelo que já é do usuário.** Identidade, dispositivos, Vault, smart account —
  tudo roda local/on-chain e continua funcionando **mesmo que o TruthID como empresa/serviço
  deixe de existir**. Não é negociável pra nenhuma ideia de monetização.
- **Nunca forçar pagamento pra usar o produto core.** Tudo que hoje é grátis continua grátis.
  Monetização só entra em serviços adicionais que geram custo real e recorrente pro dono do
  projeto manter rodando (infraestrutura, não o produto em si).
- **Preferência explícita por pay-per-use em vez de assinatura** — descartado "plano mensal
  fixo" como estrutura principal.
- Referência mental: modelo Ledger — a chave nunca sai do hardware (grátis, sempre), mas o
  backup redundante é um serviço pago opcional.

**Por que "assinatura mensal via Pix→ETH" foi descartada**: modelo "cambista" (usuário deposita
Pix, dono do projeto compra ETH e credita) configura operação de câmbio de fato — no Brasil, cai
na Lei 14.478/2022 (marco legal dos criptoativos), que exigiria autorização do Banco Central como
Prestador de Serviços de Ativos Virtuais (VASP), com todo o aparato de KYC/AML. Exatamente o
nível de complexidade regulatória que o dono do projeto quer evitar com CNPJ mínimo.

**Modelo escolhido: taxa de serviço on-chain, paga pela própria smart account, em ETH**
1. **Modo padrão (sempre disponível, sem o dono do projeto no meio)**: usuário deposita ETH
   direto na própria smart account (self-funded gas — já é a Fase 14, concluída). 100%
   self-custodial, sem dependência de nenhum serviço do dono do projeto.
2. **Modo premium (opcional)**: pra funcionalidades extras, a própria smart account paga em ETH,
   **dentro da mesma UserOperation** que executa a ação, uma taxa pra uma carteira do dono do
   projeto.

**Por que resolve o problema regulatório**: o dono do projeto nunca recebe fiat do usuário nem
entrega cripto a ele — o fluxo é o usuário autorizando uma transação que sai da própria wallet
dele, em ETH, como pagamento por um serviço prestado. Estruturalmente idêntico a uma taxa de
protocolo (ex: fee do Uniswap), não câmbio nem custódia de terceiro.

**Arquitetura técnica (em cima do que já existe e já foi validado)**:
- `execBatch` já roda de verdade em hardware real (Sessões 115-117 — AA26 corrigido, UserOps
  executando com `userOpHash`/`transactionHash` reais via bundler/Paymaster).
- **Ações on-chain** (ex: pinning extra no `VaultRegistry`): uma UserOp com `execBatch` contendo
  (a) a call real da ação e (b) um `transfer` de ETH pra carteira de taxas — atômico, ou as duas
  rodam ou nenhuma roda.
- **Ações off-chain** (ex: IA gerenciada, consolidação B3 — rodam num backend do dono do
  projeto): precisa de ponte entre pagamento on-chain e liberação do serviço. Duas abordagens,
  a decidir: (a) backend só libera depois de confirmar a transação minerada — simples, mas
  adiciona latência de bloco a cada chamada; (b) **session key com limite de gasto** (spending
  limit) autoriza um lote de N chamadas até um teto em ETH, sem transação nova a cada mensagem —
  preferida pro caso de IA (gas por mensagem de chat seria proibitivo). Ver desenho abaixo.

**Precificação em ETH — volatilidade, nenhuma opção decidida**: (a) valor fixo em ETH,
reajustado manualmente de vez em quando — mais simples de implementar agora, mas o preço real em
poder de compra varia com a cotação; (b) cotação via oráculo (Chainlink tem feed ETH/USD na
Base), consultado só no momento de calcular quanto ETH cobrar pra bater um valor-alvo em dólar.
Recomendação implícita da conversa: começar por (a), evoluir pra (b) se o volume justificar.

**Saldo em fiat (R$/USD) como fallback**: explicitamente de baixa prioridade — construir primeiro
o modelo 100% ETH via smart account (não exige tratar fiat, gateway de pagamento, ou nada que se
pareça com custódia).

**Ideias de fonte de renda (cada uma paga via o mecanismo acima)**:
1. **Gas sponsorship por uso** — a mais direta, já tem a infra pronta (Paymaster). Cada UserOp
   patrocinada é medida e cobrada proporcionalmente, só quando o usuário opta por não pagar o
   próprio gas.
2. **Integração B3** — a motivação original do brainstorm. Requer CNPJ e certificado mTLS.
   Cobrado por consolidação/chamada, não assinatura — bate com o próprio modelo de cobrança da
   B3 pra API de dados de investidor.
3. **Pinning IPFS além do free tier** — Filebase/Pinata cobram do dono do projeto acima do free
   tier; repassar (+ margem) pro usuário que precisar de mais espaço. Base técnica já existe:
   providers de pinning configuráveis (Kubo/PSA) conectados à navegação do Mobile na Sessão 116.
4. **Verificação/atestação (KYC descentralizado), B2B** — cobrar por consulta quando uma empresa
   terceira quiser validar identidade via TruthID (depende do item 2 do roadmap de expansão,
   acima — verifiable credentials/ZK — ainda não implementado).
5. **IA gerenciada — avaliado e rebaixado a "conveniência", não pilar de receita**: diferente de
   gas/B3/pinning, não existe barreira técnica real — qualquer usuário pega uma API key grátis
   (Gemini, por exemplo) e faz o mesmo em minutos. Decisão: manter BYOK grátis pra sempre (como
   já é hoje), oferecer chave gerenciada como conveniência opcional cobrando só repasse de custo
   + margem pequena (20-30%), sem esperar que vire receita relevante.

**Session key com limite de gasto — arquitetura pra evitar gas por mensagem (IA), ainda não
desenhada em detalhe**: uma session key (mecanismo que já está no roadmap — item 3, "delegação
de acesso temporário") é criada com um teto de gasto em ETH e/ou número máximo de chamadas.
Enquanto o teto não estoura, o backend de IA aceita chamadas autorizadas por essa session key sem
exigir uma transação on-chain nova a cada mensagem — a cobrança acontece em lote, no fechamento.
Precisa decidir: onde fica o registro de "quanto já foi consumido dentro do teto" (on-chain
custaria gas a cada atualização, anulando o benefício; provavelmente um registro off-chain no
backend, com a liquidação batendo on-chain só no fechamento do lote). Risco a mapear: o que
acontece se o backend achar que o teto não estourou mas a session key foi revogada nesse meio
tempo — precisa de checagem de validade a cada uso, não só no início.

**Token/DAO com moeda própria**: avaliado e **descartado por ora** — risco regulatório alto
(oferta pública de valor mobiliário), sem tração suficiente pra justificar, risco de prejudicar
credibilidade pra grants futuros.

**Outras fontes de financiamento mencionadas (fora do mecanismo de taxa acima)**: relay/hosting
gerenciado (SLA, uptime, suporte); integração B2B/enterprise (dashboard de gestão de
devices/sessions); **grants** (Base, Ethereum Foundation, Protocol Labs, Gitcoin) como via
principal de financiamento no estágio atual — não depende de tração de usuários, avalia mais
qualidade técnica e visão; doações diretas, mantidas como complemento de baixo custo.

**Decisões em aberto (nada decidido ainda)**:
- Formato final: virar uma Fase nova em `project/PHASE.md` (Fase 15), ou ficar como documento separado
  referenciado por ele? (Registrado aqui, dentro do Roadmap, por ora — pode virar Fase própria
  quando/se sair do brainstorm pra implementação real.)
- Opção (a) ou (b) de precificação ETH/BRL pra começar.
- Ponte pagamento→liberação pras ações off-chain: confirmação on-chain simples vs. session key
  com limite de gasto (provavelmente session key pra IA, a decidir caso a caso pras outras).
- Desenho detalhado da session key com limite de gasto.
- Se/quando entrar a camada de saldo fiat (R$/USD) — explicitamente de baixa prioridade.
- Margem/spread exato em cada uma das 4 ideias de receita — nenhum número foi fixado.

**Nada implementado — fica pra quando o dono do projeto quiser rodar um `/plan` de verdade.**

---

### Migração de storage (Filebase/Pinata → Storacha) + Tier facilitado (pago) — desenho completo
(registrado 2026-08-05, Sessão 184)

**Fonte**: `truthid-storacha-tier-facilitado.md` (raiz do repo), substitui o rascunho anterior
`migracao-storacha.md`. Continuação direta do brainstorm de Monetização acima — este documento
destrava o item 7 do roadmap de prioridade (ver `PENDING.md`/histórico de sessões: itens 1-6 pós-
Fase 14 fechados na Sessão 129) com decisões concretas, mas **nada foi implementado ainda** — só
desenho. Duas frentes independentes, ambas dependendo da mesma base `DeviceRegistry`/
`SessionRegistry`. **Instrução do dono do projeto**: antes de codar, estudar a doc oficial da
Storacha/SDK `w3up`/auth UCAN vigentes e perguntar antes de assumir decisão de arquitetura.

**Épico 1 — migração de storage.** Decisão: sair completamente de Filebase/Pinata e migrar pra
**Storacha** (ex-web3.storage), que faz deals reais na rede Filecoin com múltiplos storage
providers via SDK `w3up` (cliente calcula CID localmente, empacota em CAR file, sobe — se a
Storacha como empresa sumir, os deals Filecoin já feitos continuam existindo com os storage
providers). Self-hosting puro (nó IPFS no homelab) descartado por ora — trocaria dependência de
terceiro por single point of failure do próprio dono do projeto + trabalho operacional que não
compensa no estágio atual; pode voltar depois como redundância extra, nunca como espinha dorsal.
Billing da Storacha é por conta única (sem billing nativo por usuário final) — decisão: manter
conta única do TruthID + construir camada de metering interna (rastrear uso por usuário) em vez de
cada usuário abrir conta própria na Storacha (fricção de cadastro de cartão em serviço terceiro).
Escopo: (1) trocar client de upload pelo `w3up` no fluxo de escrita do Vault; (2) validar latência
real do gateway de retrieval da Storacha; (3) migrar CIDs já commitados on-chain pra também
ficarem persistidos via Storacha, sem alterar CID nem contrato; (4) double-write temporário
(Filebase/Pinata + Storacha em paralelo) até reads via Storacha ficarem 100% confiáveis, só então
cortar os antigos; (5) validar custo real considerando que vault entries são arquivos pequenos
(KBs) — avaliar batching. Pinning continua tendo que acontecer antes da assinatura do commit do
CID on-chain — isso não muda.

**Perguntas em aberto que o documento original deixou pro Claude Code investigar antes de
implementar**: forma de autenticação/identidade da Storacha hoje (UCAN, DID, API key?) e como
integra com a identidade que o usuário já tem no TruthID; granularidade de cobrança/free tier
atual e como escala com número de usuários e frequência de writes pequenos; onde exatamente no
código atual (Tauri/Rust desktop, extensão) a chamada de API do Filebase/Pinata acontece, pra
mapear o escopo real da troca.

**Épico 2 — tier facilitado (pago), opt-in.** Princípio: core continua 100% self-sovereign e
grátis, cancelar o tier pago nunca quebra o core (vault continua acessível). Só entra no tier pago
o que exige custo/envolvimento contínuo do dono do projeto (servidor, gas sponsorship, custódia
temporária no bootstrap) — UX que roda 100% no client fica grátis pra sempre. Peças:
- **2.1 Onboarding sem Ledger** — "celular como Ledger": chave gerada localmente no device,
  protegida por passkey (WebAuthn PRF)/biometria no secure enclave, nunca trafega em claro nem vai
  pro servidor do dono do projeto; servidor só paga o gas do deploy da smart account via
  Paymaster, usando só o endereço público. Trade-off a documentar na UI: não é air-gapped como
  Ledger.
- **2.2 Gas sponsorship** — usuária paga por Pix/cartão, dono do projeto mantém pool de ETH na
  Base, Paymaster consulta assinatura ativa antes de sponsorizar. Proteções obrigatórias desde o
  MVP: rate limit de UserOps/dia/mês, cap de gas por transação, log de reconciliação custo real vs.
  cobrado. Risco não-técnico: receber fiat de terceiros e converter pra cripto por conta deles pode
  se aproximar de money transmission dependendo de jurisdição/volume — mapear antes de escalar.
- **2.3 Backup em nuvem opcional** — backup local já é independente; cancelar só remove a cópia
  extra, com grace period de retenção antes de apagar e path de "mover pro seu storage" oferecido
  antes de expirar.
- **2.4 Transição sponsorship → self-funded** — aviso proativo antes de expirar + on-ramp
  integrado (Coinbase Onramp/Transak) pra depositar ETH na Base sem sair pra exchange externa;
  nunca deixar transação falhar silenciosamente por falta de gas.
- **2.5 Rotação de device genérica** — celular↔celular, celular↔Ledger é sempre a mesma operação,
  já que a identidade gira em torno do endereço da smart account + `DeviceRegistry`, não da chave
  que assina: novo device registrado (autorizado pelo antigo) → gera chave própria → handoff
  deliberado com confirmação explícita + possível timelock antes de promover a signer primário →
  antigo revogado ou mantido como secundário, à escolha da usuária. Nenhum CID muda.
- **2.6 Recovery por perda de device** — reaproveita 100% o guardian recovery M-of-N já
  implementado (Fase 16, `SessionRegistry`/`DeviceRegistry`); dono do projeto pode ser guardião
  opcional no tier pago pra quem não tem outros guardiões configurados.
- **2.7 PROBLEMA EM ABERTO, único ponto que exige contrato novo — guardian-on-cancel**: quando
  alguém com o dono do projeto como guardião M-of-N cancela o tier pago, precisa de evento
  on-chain que (a) remova ativamente o dono do projeto do guardian set via
  `DeviceRegistry`/`SessionRegistry`, (b) dispare notificação in-app clara ("guardião X saiu,
  escolha outro ou continue com M-1 de N"). Sem isso, usuário fica com guardião "morto" no quórum
  sem saber, descoberto só na hora real de recuperar — pior momento possível. Sem desenho de
  contrato feito ainda.

**Resumo do que exige desenho/código novo**: camada de metering Storacha por usuário, bootstrap
sem Ledger, backend de sponsorship (rate limit + cap + verificação de assinatura), evento de
guardian-on-cancel, UX de aviso + on-ramp. **O resto é composição do que já existe**: rotação de
device (`DeviceRegistry`), recovery (guardian recovery da Fase 16), backup em nuvem (mesma
criptografia E2E já existente, só muda o destino do upload).

**Nada implementado — documento é plano, ainda vai ser debatido com o dono do projeto antes de
qualquer `/plan` ou código.**

**Discussão logo após o registro (mesma Sessão 184) — 3 pontos de risco levantados e a resposta do
dono do projeto a cada um:**

1. **Risco regulatório do 2.2 (money transmission)** é o maior risco não-técnico do documento
   inteiro, agravado pelo dono do projeto ser menor de idade — mapear isso vem antes de construir
   o backend de sponsorship, não em paralelo. Dono do projeto confirmou o ponto ("beleza"), sem
   mudança de plano ainda — fica registrado como prioridade de pesquisa antes do 2.2 virar código.

2. **Mecanismo de "Paymaster consulta assinatura ativa" (2.2) precisa decidir fail-open vs.
   fail-closed** quando o backend de sponsorship cair ou a assinatura expirar. **Resposta do dono
   do projeto, que resolve a dúvida**: o software continua 100% usável sem o plano — quem tem ETH
   próprio depositado na smart account sempre pode pagar o próprio gas (caminho self-funded da
   Fase 14, já implementado e grátis pra sempre). Isso torna **fail-closed seguro por padrão**: se
   a sponsorship falhar, a pior consequência é "essa transação específica não foi patrocinada", não
   "vault inacessível". **Ressalva a manter no design**: quem entrou justamente pelo onboarding sem
   Ledger (2.1) pode não ter ETH nenhum depositado — pra essa pessoa, cair pro self-funded não é
   imediato, precisa primeiro passar pelo on-ramp do 2.4. A UX de "nunca deixar transação falhar
   silenciosamente por falta de gas" (já prevista no 2.4 pra expiração planejada) deve valer
   **também** pra qualquer falha de sponsorship não-planejada (backend fora do ar, rate limit
   estourado, etc.), não só pro caso de expiração.

3. **Risco de vendor lock-in na Storacha (Épico 1)**: dono do projeto confirmou que não é um risco
   real da forma que foi levantado — como o `VaultRegistry` só guarda o CID on-chain e nunca sabe
   quem serve o conteúdo, trocar de Storacha pra outro provider no futuro (outro serviço, deal
   Filecoin direto, self-host) é só trocar o client de upload/leitura, **sem tocar em contrato nem
   migrar nenhum CID existente**. Confirma o desenho original do documento (`VaultRegistry`
   storage-agnostic por design) — não é uma mudança de plano, é uma confirmação de que o risco já
   estava mitigado pela arquitetura.

**Investigação aprofundada, mesma Sessão 184 — a preocupação do ponto 3 acima se confirmou na
prática, e destravou um `/plan` de pesquisa só sobre storage decentralizado.** Antes de codar,
seguindo a instrução do documento original ("estudar a doc oficial da Storacha antes de
implementar"), fomos verificar o estado atual da Storacha — e o que achamos invalida a premissa
central do Épico 1 como estava escrito.

**Achado que muda tudo: `storacha.network`, `docs.storacha.network` e `web3.storage` redirecionam
(301) inteiros pra `fil.one`** — um produto diferente, S3-compatible, centralizado, sem nenhuma
menção a UCAN/w3up/deals Filecoin multi-provider (exatamente o que justificou escolher a Storacha).
`console.storacha.network` (onde se criaria a conta/Space) nem resolve mais via DNS. A org no
GitHub segue ativa (atividade em maio/2026) e o pacote npm atual `@storacha/client` (v2.1.4) não
está deprecated — mas nenhuma issue pública documenta esse redirect, e a incerteza é grande demais
pra apostar a arquitetura nisso agora.

**Comparação de alternativas investigadas (cada uma com pesquisa ao vivo, não memória de
treino — preços, funding, maturidade, atividade real de repositório):**

| Candidato | Achado real | Veredito |
|---|---|---|
| Storacha | Ver acima — domínio/docs/console redirecionando pra outro produto | Status incerto demais |
| Lighthouse.storage | ~US$100k levantados (seed único, 2022, 1 investidor), ~9 funcionários. Gateway grátis já foi restringido pra usuários premium. Auth por API key simples, não mais soberano que Filebase/Pinata hoje. Escopo diluído (Filecoin + Walrus + S3-compatible) | Mesmo padrão de risco, financiamento pior |
| Crust Network | PSA parcial (`pin.crustcode.com/psa`), histórico de falhar compliance checks; paga em token próprio (CRU), 3º token além de ETH | Descartado por ora |
| QuickNode | Empresa estabelecida: US$106M levantados, avaliação US$800M, 117 funcionários, fundada 2017, 99,99% uptime, receita +300%. Pinning é feature secundária pra eles, não o core business | **Bom pra reforço de redundância PSA imediato** |
| Arweave (base layer) | Mainnet desde nov/2018, 24+ bilhões de tx até 2025, nenhum outage real confirmado em 7+ anos. Preço ~US$0,0000037/KB (AR≈US$1,84, ago/2026), sem piso de taxa mínima encontrado. Modelo de endowment: garantia formal de 200 anos, estendendo-se enquanto custo de storage em hardware cair ≥0,5%/ano (histórico real ~38%/ano) | **Candidato mais forte encontrado** |
| Irys (ex-Bundlr) | Deixou de ser bundling sobre o Arweave maduro — lançou como **L1 própria em 2025**, consenso novo (uPoW/S), ~1 ano de idade. Grátis até 100KiB/upload, US$0,01 mínimo acima disso — economia ótima, mas reintroduz risco de chain nova/não testada | Economia boa, maturidade não bate — não usar por ora |

**Recomendação**: QuickNode como reforço de redundância PSA de curto prazo (config, zero
engenharia nova, resolve o risco imediato de "só Filebase+Pinata" do Épico 1) + Arweave puro (sem
Irys) como a aposta de storage genuinamente decentralizado e resistente a qualquer empresa sumir.

**Desenho de duas trilhas pro storage Arweave, resolvendo uma contradição real levantada na
discussão** ("não precisa ser sempre grátis, mas o usuário precisa conseguir não depender de mim"):

- **Storage core do Vault** (o CID que vai pro `VaultRegistry` a cada publish) continua **sempre
  grátis**, sem taxa nenhuma, não importa o backend — inegociável, é o que já garante
  self-sovereignty hoje. Confirmado no código: `desktop/src-tauri/src/lib.rs:467`
  (`vault_publish`) → `desktop/src/hooks/useVaultPublish.ts:88-105` (`execute` único, `value: 0n`,
  só `updateVault`) — nada aqui precisa mudar, o storage core já é isolado de qualquer taxa por
  desenho.
- **Trilha self-sovereign**: usuário gera/importa uma chave Arweave (JWK) local no device, financia
  sozinho (exchange ou on-ramp), zero dependência do dono do projeto. É o que garante que storage
  decentralizado continua disponível **sem exigir o tier pago** — não é "grátis de custo", é "não
  depende de mim".
- **Trilha facilitada (tier pago)**: dono do projeto mantém carteira Arweave própria (pool), paga
  por trás; usuário paga uma **taxa em ETH** (nunca em AR) dentro de uma UserOperation de uma ação
  **separada e específica** do tier pago — nunca dentro do `updateVault` core.

**Mecanismo de taxa via `execBatch` — achado importante, corrige suposição errada da conversa**:
`executeBatch` existe (`contracts/src/TruthIDAccount.sol:208`) e funciona, mas **nunca foi usado
via UserOperation/device key/bundler** — só em transações diretas assinadas pelo Ledger (owner),
nos fluxos de pareamento/revogação de device (`PairDevice.tsx`, `ManageDevices.tsx`,
`DesktopDevice.tsx`, sempre `value: 0n`). A Sessão 166 já tinha registrado que bundling de
valor/fee dentro de UserOperation nunca foi construído nem validado — foi cogitado e descartado por
escopo antes. **Não é reaproveitamento de algo provado em hardware — é infraestrutura nova**, ainda
que usando peças que já existem (`executeBatch`, `desktop/src/utils/buildAccountCalls.ts:12-30`).
Nenhum padrão de "taxa/treasury" existe hoje em nenhuma parte do código (grep vazio).

**Sincronização da chave Arweave entre devices — desenho com precedente real**: o canal ECIES que
já sincroniza a chave simétrica do Vault no pareamento (`encrypt_bytes_for_device`,
`desktop/src-tauri/src/lib.rs:393-445`) é genérico sobre `&[u8]`, e o
`CrossDeviceDeliveryChannel` (`mobile/lib/services/cross_device_delivery_channel.dart:32-64`) já
cifra payload arbitrário pela mesma técnica — prova que o canal já serve segredo arbitrário, não só
a chave do vault. Desenho proposto: gerar a chave Arweave uma vez (bootstrap ou primeiro uso) e
distribuir pra cada device novo pelo mesmo canal — reaproveita a **primitiva** já validada em
hardware real (bugs históricos documentados em comentário no código, Sessões 92/76/99), não código
pronto (nada de Arweave existe no repo hoje).

**Dois gaps técnicos identificados nesta pesquisa — decisões tomadas logo depois (mesma Sessão
184), pesquisando soluções concretas pra cada um:**

**1. Revogação não gira segredo compartilhado — decisão: corrigir já, valendo pra Vault key E
Arweave key juntas.** Pesquisa de precedente (Signal/WhatsApp multi-device): esses sistemas evitam
o problema por completo porque não usam chave simétrica compartilhada — cada device tem identidade
própria, conteúdo cifrado por device (fan-out). Copiar isso 1:1 seria reformular o Vault inteiro,
fora de escopo. **Padrão adotado em vez disso: rotação de DEK (data encryption key) com
re-criptografia**, o modelo de envelope encryption (S3 KMS e similares) — ao revogar um device:
gerar uma DEK nova, re-cifrar o conteúdo sob ela, redistribuir só pros devices que restaram, via o
mesmo canal ECIES já usado hoje (`encrypt_bytes_for_device`/`EciesService`). **Decisão do dono do
projeto**: implementar o quanto antes, mesmo sendo mudança grande — "quebra e faz aos poucos"
(iterativo, não tenta entregar tudo de uma vez). Cobre as duas chaves com o mesmo mecanismo:
`deviceVaultKeys` (`contracts/src/DeviceRegistry.sol:49`, já existente) e a chave Arweave nova
(ainda não implementada). Fica pra um `/plan` de implementação dedicado, por causa do tamanho.

**2. `PinningProvider` não encaixa o modelo pay-per-upload do Arweave — decisão: remover o
pinning por completo, não coexistir.** Em vez de manter Kubo/PSA rodando ao lado do Arweave (o que
exigiria o design de "escolha de backend com prefixo de esquema" que foi cogitado), o dono do
projeto decidiu **cortar o sistema de pinning inteiro** (`ipfs.rs`, `PinningProvider`,
Kubo/Filebase/Pinata) e ir 100% Arweave. **Escopo confirmado**: não é só desligar escrita nova —
o conteúdo **já publicado** via Kubo/PSA também será **re-publicado no Arweave**, fechando de vez
a dependência de qualquer gateway IPFS (`GATEWAYS` em `ipfs.rs:201`, `fetch_from_gateway`)
daqui pra frente. Isso é migração de dado real, não só troca de client — fica pra um `/plan` de
implementação dedicado (mesmo aviso do item 1: mudança grande, feita aos poucos).

**Validações reais pendentes antes de qualquer implementação (ainda não resolvidas):**
1. Teste de upload+retrieval+custo real via `arweave-js`, com números precisos de latência (não
   deu pra medir isso só com ferramentas de busca/fetch — confirmado que `arweave.net/info`
   responde saudável, mas sem timing preciso).
2. **Adiado, sem urgência** — confirmar se Transak (ou outro on-ramp) atende Pix/BRL pra compra de
   AR. Pesquisa já mostrou que hoje só achamos caminho manual via exchange completa (Bitget aceita
   Pix + lista AR, mas exige cadastro/KYC, não é widget embutido) — mais fricção que o on-ramp de
   ETH já planejado, mas não bloqueia o resto.
3. Prototipar `execBatch` pelo caminho UserOp+bundler+paymaster de verdade — **esclarecido**: a
   ação que carrega a taxa é uma ação paga (a própria smart account paga o próprio gas), então
   **Paymaster não entra nessa ação específica** — a dúvida original não se aplica mais.

**Nada implementado ainda — os dois itens acima (rotação de DEK unificada, remoção total do
pinning + migração pro Arweave) estão priorizados pelo dono do projeto pra implementação em
`/plan`s dedicados, tratados como mudanças grandes feitas de forma incremental.**

**Item 1 (rotação de DEK) implementado, mesma Sessão 184, em 5 etapas — `/plan` dedicado rodado
logo em seguida.** Escopo real corrigido no meio do caminho: `DeviceRegistry` está em
`blockedForDevices` (`TruthIDAccount.sol`) por desenho de segurança deliberado — device-tier
signers nunca podem chamar nada lá, então o Mobile **nunca pode iniciar** revogação/rotação, só
recebê-la. Só o Desktop (Ledger, owner-tier) inicia.

- **Contrato**: `updateDeviceVaultKey(address, bytes)` nova em `DeviceRegistry.sol`, aditiva,
  mesmo controle de acesso do `revokeDevice`. 7 testes novos, `forge test` 276/276.
- **Desktop**: `decrypt_bytes_for_device` novo (Desktop passa a saber *receber* chave via ECIES,
  não só enviar); `rotate_vault_key`/`rotate_vault_key_bytes` (núcleo puro separado de I/O,
  re-cifra vault + campos de cartão + documentos); `ManageDevices.tsx` dispara tudo automaticamente
  depois de um `revokeDevice` confirmado — `executeBatch` via Ledger (caminho já provado) com
  `updateDeviceVaultKey` por device restante + `updateVault` da republicação, numa transação só.
  `cargo test` 141/141, `tsc`/`vitest` limpos.
- **Mobile**: escopo original ("botão Revogar") descartado pela restrição acima. Escopo real:
  `VaultSyncService.sync()` passou a chamar `VaultKeyService.tryRecoverFromChain` (que já existia,
  só nunca era invocada fora do pareamento) a cada sync, se já há chave cacheada — detecta e adota
  a chave rotacionada sem nenhuma função nova. `flutter test` 507/507, `flutter analyze` limpo.
- **Validação (Etapa 5)**: sem hardware físico disponível, rodada contra `anvil` local real — deploy
  real, identidade real (assinatura via `cast wallet sign --no-hash`), 2 devices registrados com
  ECIES real (`encrypt_bytes_for_device` de produção), revoga A, redistribui a chave nova só pra B,
  lê de volta on-chain e decifra com `decrypt_bytes_for_device` de produção. B decifra pra chave
  nova, A continua só com a antiga, atualizar chave de device revogado reverte. Achado no caminho:
  `forge script --broadcast` tem inconsistência entre simulação local e verificação contra RPC real
  em fluxos commit-reveal (`vm.roll` não se aplica na segunda fase) — contornado com `cast
  send`/`cast call` diretos.

**Fora de escopo, decisão explícita**: deploy em Mainnet (validado só em Anvil/local) e integração
com guardian recovery (`revokeAllDevices` via `RecoveryManager` — depende de entender como o device
recuperado obtém a vault key hoje, não investigado). Falta só validação em hardware físico (celular
real + Ledger real) pra fechar de vez — mesmo padrão de pendência do resto do projeto.

**Item 2 (remoção do pinning + migração pro Arweave) — Etapa 1 implementada (Sessão 185,
2026-08-06): núcleo do cliente Arweave em Rust no Desktop, standalone, sem integração com
`vault_publish`/`VaultRegistry` ainda (fica pra próximas etapas, junto com `deviceArweaveKeys` +
sync ECIES entre devices, trilha self-sovereign vs facilitada, Mobile, migração do conteúdo já
pinned e remoção do `PinningProvider`/Kubo/PSA).**

- **Decisão de arquitetura**: transação Arweave formato 2 direta contra qualquer node/gateway
  (permissionless), não ANS-104 via bundler — pesquisa ao vivo achou que a única lib Rust mantida
  pra Arweave (`permaweb/bundles-rs`, org oficial do ecossistema) só faz ANS-104/bundler, que
  reintroduziria dependência de empresa terceira no caminho de escrita, o mesmo risco já rejeitado
  pra Storacha/Lighthouse/Crust e incompatível com a trilha self-sovereign.
- **Módulo novo**: `desktop/src-tauri/src/arweave/{mod,wallet,deep_hash,merkle,transaction}.rs` —
  gera/importa wallet JWK RSA-4096, monta e assina tx formato 2 (deep hash SHA-384 + RSA-PSS/
  SHA-256, merkle `data_root` SHA-256 sobre chunks de 256 KiB), submete (`POST /tx`), lê status e
  conteúdo de volta. 7 commands Tauri novos (`arweave_generate_wallet`, `arweave_import_wallet`,
  `arweave_wallet_exists`, `arweave_wallet_address`, `arweave_publish`, `arweave_get_status`,
  `arweave_fetch`) só pra validação manual isolada — nenhum integrado ainda no fluxo do Vault.
  Wallet armazenada local via keyring do SO + fallback arquivo, mesmo padrão de `get_vault_key`.
- **Sem vetores de teste oficiais pra deep hash/merkle/assinatura** — mitigado gerando vetores
  cross-checados contra `arweave-js` real (rodado localmente via Node, scripts descartáveis) pra
  blob hash, list hash, merkle root (1 chunk e multi-chunk) e a montagem completa dos campos da tx
  (`getSignatureData()`) — todos batem exatamente com a implementação Rust. `cargo test` 201/201
  (171 pré-existentes + 30 novos, 2 ignorados: keygen RSA-4096 real e o teste de integração
  ArLocal), `cargo clippy` limpo, `cargo build` (lib+bin) limpo.
- **Achado real durante a implementação, não estava no plano original**: o crate `rsa`
  (RustCrypto) faz verificação PSS **estrita** de salt length — ao contrário do OpenSSL/Node.js
  (que auto-detectam o salt a partir do padding na hora de verificar), duas assinaturas com salt
  length diferente falham verificação cruzada entre si nessa lib. Mitigado usando consistentemente
  os wrappers tipados `SigningKey<Sha256>`/`VerifyingKey<Sha256>` (salt = 32 bytes, tamanho do
  digest) dos dois lados — resolve a auto-consistência interna (`verify_transaction_signature`),
  mas **não prova que um node Arweave real aceita essa assinatura** (Node.js/arweave-js assina por
  padrão com salt bem maior, `RSA_PSS_SALTLEN_MAX_SIGN`) — só uma submissão real confirma.
- **`cargo audit`**: crate `rsa` 0.9.10 carrega RUSTSEC-2023-0071 (Marvin Attack, timing
  sidechannel) sem correção disponível ainda na crate inteira ("No fixed upgrade is available").
  Uso aqui é só assinatura PSS (não decrypt), o que reduz a exposição descrita no advisory, mas é
  um risco em aberto, não resolvido — registrado, não ignorado.
- **Validação contra ArLocal NÃO rodou de fato nesta sessão** — o pacote `arlocal` depende
  transitivamente de um fork via git (`avsc`), bloqueado pela política de rede do sandbox usado
  pra implementar (`npm error code EALLOWGIT`). O teste de integração
  (`arweave::arlocal_tests::publish_and_fetch_round_trip_against_arlocal`, `#[ignore]`) foi escrito
  e compila, mas só validado por leitura — não por execução real. **Isso deixa em aberto justamente
  o ponto mais importante: se a rede Arweave de verdade aceita a assinatura RSA-PSS produzida por
  este código.** Rodar manualmente numa rede sem essa restrição (`npx arlocal` +
  `cargo test --lib arweave::arlocal_tests -- --ignored --nocapture`) é o próximo passo antes de
  confiar nisso pra qualquer integração real.

**Validação contra ArLocal rodou de fato (Sessão 186, 2026-08-08) — passou.** O bloqueio de rede
persistia neste ambiente também, mas era contornável sem violar a política: `arlocal@1.1.20` (fixando
`arbundles` em `0.6.12` via `overrides` do npm, já que o range `^0.6.12` do próprio pacote inclui
versões que reintroduzem o fork) resolve todas as dependências pela registry normal, sem git. O
único outro bloqueio (`sqlite3`/`secp256k1`/etc. precisando compilar bindings nativos, barrados pela
allowlist de install scripts do npm) foi liberado com aprovação explícita do dono do projeto, restrito
à pasta descartável do scratchpad — nunca tocou o repositório real.

- **Resultado**: `publish_and_fetch_round_trip_against_arlocal` passou (publish → mine → status →
  fetch, bytes idênticos). Confirma que a assinatura RSA-PSS de `sign_transaction` é aceita por uma
  implementação real de node Arweave, não só pela verificação local (`verify_transaction_signature`).
  Risco de salt length ainda não é 100% descartado pra mainnet (ArLocal reimplementa a validação de
  assinatura em JS, não é o node oficial em Erlang) — mas é a evidência mais forte disponível até
  agora sem gastar AR real.
- **Achado real no caminho, corrigido**: o `last_tx`/anchor devolvido pelo ArLocal usa alfabeto
  base64url válido mas não é uma codificação canônica (bits residuais != 0 no último símbolo) — o
  decoder estrito usado no resto do módulo rejeitava isso (`base64::DecodeError`). Como esse campo
  vem de fora (do node, não codificado por nós), criado `b64url_decode_lenient` em `transaction.rs`
  só pra ele, mantendo estrito nos campos que o próprio cliente codifica (`owner`/`data_root`, onde
  qualquer desvio indicaria bug real). 2 testes novos cobrindo o decoder permissivo. `cargo test`
  173/173 (2 ignorados: keygen RSA-4096 real e o round-trip ArLocal, que só roda com o node local no
  ar), `cargo clippy` limpo no módulo `arweave` (aviso pré-existente em `vault.rs:629`, não
  relacionado, confirmado via `git stash`).
- **Ainda em aberto**: risco de salt length contra um node Arweave oficial de verdade (não ArLocal) —
  só testnet/mainnet real resolve isso por completo. Integração em `vault_publish`/`VaultRegistry`
  (Etapa 2) continua não implementada.

**Item 2 — Etapa 2 implementada (Sessão 187, 2026-08-08): blob principal do vault integrado de
verdade no `vault_publish`, publicando no Arweave em vez do IPFS.** Escopo deliberadamente mais
estreito que a intenção original registrada acima ("ir 100% Arweave, remover `PinningProvider` por
completo, re-publicar conteúdo já pinado") — aquilo continua trabalho futuro, não foi abandonado,
só não é esta etapa. Confirmado com o dono do projeto antes de implementar: corte direto sem
feature flag/fallback (mesmo padrão da rotação de DEK), inclusão do shim de leitura no Mobile nesta
mesma etapa, e só o blob principal do vault (não documentos anexados) — o cliente Arweave da Etapa
1 só sobe até 256KB (chunk único), e documentos podem chegar a 50MB (`VaultManagement.tsx`); upload
em chunks fica pra uma etapa futura dedicada.

- **Design**: ponteiro auto-descritivo `"ar://" + tx_id` gravado como `cid` no `VaultRegistry`
  (`updateVault(string cid, bytes32 contentHash)` só valida `bytes(cid).length != 0` — string opaca
  por design, confirmado lendo o contrato). Um `cid` sem esse prefixo continua significando "busca
  no IPFS", exatamente como antes — zero migração de dado, zero mudança de contrato, compatível com
  qualquer conteúdo já publicado e com qualquer outro escritor (Mobile, Extension) que continue
  publicando no IPFS.
- **Rust** (`arweave/mod.rs`): `publish_vault_blob_with_jwk` (core, sem I/O de wallet — testável
  direto contra ArLocal com um JWK gerado na hora) + `publish_vault_blob` (carrega a wallet local,
  erro claro e sem fallback se ausente) + `get_wallet_balance`/comando `arweave_wallet_balance`
  (saldo em winston, pra dar erro acionável antes de gastar uma requisição de publish fadada a
  falhar). `lib.rs::vault_publish` troca só a chamada do blob principal
  (`ipfs::pin_vault` → `arweave::publish_vault_blob`); documentos por-documento e o comando
  `pin_content` de terceiros (`/truthid/v1/pin`, usado pelo SDK) continuam intocados no IPFS.
  `vault_document_read` ganha dispatch por prefixo (`ar://` → `arweave::fetch_data`, sem wallet
  necessária pra ler — GET público).
- **Mobile** (`ipfs_gateway_client.dart`): mesmo dispatch por prefixo, centralizado no único ponto
  que `vault_sync_service.dart` e `vault_repository.dart` já usam pra buscar conteúdo — nenhum dos
  dois precisou mudar. Sem carteira/cripto nova no Dart, é só GET HTTP contra `arweave.net`.
- **UI nova no Desktop** (`VaultSettings.tsx`, `ArweaveWalletSection`): antes desta etapa não
  existia nenhuma referência a Arweave em `desktop/src` — sem UI, o corte direto deixaria o dono do
  projeto sem jeito de gerar/financiar a wallet. Mostra endereço (copiável), saldo em AR, botão de
  gerar wallet nova.
- **Testes**: Rust 173/173 (`cargo test --lib`, 3 ignorados: 2 de keygen RSA-4096 real, 1 novo —
  `publish_vault_blob_round_trip_against_arlocal` — validado de fato rodando manualmente contra
  ArLocal, mesma receita da Etapa 1: publish → mine → status → fetch, `cid` prefixado `ar://`,
  `content_hash` batendo com `ipfs::keccak256_hex`). `cargo clippy` limpo (mesmo aviso pré-existente
  de `vault.rs:629`, não relacionado). `tsc --noEmit` limpo. Dart: 5/5 em
  `ipfs_gateway_client_test.dart` (3 existentes sem regressão + 2 novos cobrindo o dispatch
  `ar://`, rodado via `./dev.sh flutter test` no Docker).
- **Achado no caminho, sem relação com o código**: rodar os dois testes ArLocal (antigo + novo) em
  paralelo ou logo em sequência produziu falhas de rede intermitentes ("error sending request",
  sem chegar a bater no servidor — confirmado via log do ArLocal e um `curl` direto na mesma URL,
  que funcionou normalmente). Ambiente lento pra 2 keygens RSA-4096 + round-trips HTTP seguidos, não
  bug de lógica — rodando de novo com tempo suficiente (`--test-threads=1`, ~400s), os dois passam
  limpo.
- **Ainda em aberto**: documentos anexados continuam no IPFS (upload em chunks do Arweave é etapa
  futura); sync de wallet Arweave entre devices não implementado (não bloqueia nada agora — ler não
  precisa de wallet, só quem publica); remoção do `PinningProvider`/Kubo/PSA e re-publicação do
  conteúdo já pinado continuam trabalho futuro; risco de salt length contra mainnet real (não
  ArLocal) só se resolve com uma publicação real, ainda não feita — precisa de uma wallet financiada
  com AR de verdade, ação do dono do projeto.

**Item 1 (upload em chunks) implementado (Sessão 188, 2026-08-08): cliente Arweave agora publica
conteúdo de qualquer tamanho via `POST /chunk` real, não só inline (≤256KB).** Escopo confirmado
com o dono do projeto antes de implementar: só a capacidade no cliente — documentos do Vault
continuam no IPFS por enquanto, trocar o call site (`vault_publish`/`vault_document_read`/
`VaultManagement.tsx`) fica pra uma etapa própria depois.

- **Design validado contra o código-fonte real de `arweave-js`** (`merkle.ts`, `transaction.ts`,
  `transaction-uploader.ts`, `chunks.ts`) e `arlocal` (`routes/chunk.ts`, `routes/data.ts`,
  `db/chunks.ts`), não só a doc prosa (que diverge do código em pelo menos um ponto: direção do
  walk em `downloadChunkedData`). Achados que mudaram o design ingênuo:
  1. `chunk_data()` produz um chunk vazio à direita quando o conteúdo é múltiplo exato de
     `MAX_CHUNK_SIZE` — precisa ser descartado antes de decidir inline-vs-chunked e antes do loop de
     upload, senão o dispatch erra e/ou tenta `POST /chunk` um chunk de 0 bytes. Novo helper
     `merkle::chunk_data_for_upload` centraliza esse descarte.
  2. ArLocal ignora o campo `offset` que o cliente envia e deriva a ordem de chegada globalmente
     (sem filtrar por `data_root`) — upload precisa ser sequencial, não concorrente, ou a
     remontagem de uma tx pode corromper (não é limitação de node real, só do ArLocal).
  3. `GET /{id}` (`fetch_data`, sem mudança) já remonta dados publicados via chunk tanto no ArLocal
     quanto em gateway real — não trocar pra `GET /tx/{id}/data`, que no ArLocal não tem fallback
     de remontagem e retorna 500 pra conteúdo só-em-chunks.
  4. `POST /chunk` responde texto puro `"OK"` no sucesso, não JSON.
- **`merkle.rs`**: `Node` virou `MerkleNode` (enum `Leaf`/`Branch`, retém a árvore inteira, não só
  a raiz) — `compute_data_root` mantém assinatura/comportamento idênticos, todos os testes
  existentes passaram sem alteração. Novo `generate_proofs` (prova de inclusão por chunk,
  `data_path`) e `validate_path` (verificação local da prova antes de cada `POST /chunk` — mesmo
  padrão que `verify_transaction_signature` já usa antes de `submit_transaction`; ArLocal não
  valida a prova que o cliente manda, então essa checagem local é a única rede de segurança contra
  um bug sutil de merkle antes de mainnet). `validate_path` portado de `validatePath` real de
  `arweave-js` (fonte buscado ao vivo, não recriado de memória).
- **Cross-check real contra `arweave-js`**: pacote `arweave` (não `arlocal`) instalado limpo num
  scratchpad descartável (sem bloqueio de git/EALLOWGIT dessa vez) e usado pra gerar `data_root` +
  `data_path` reais de `generateTransactionChunks()` sobre o mesmo vetor multi-chunk já usado em
  `cross_checked_multi_chunk_root`. Teste novo `cross_checked_proofs_match_arweave_js` compara os
  bytes de `data_path` produzidos por `generate_proofs` byte-a-byte contra esse vetor — não só que
  a árvore reassembla localmente, mas que a prova é a mesma que o cliente de referência produziria.
- **`transaction.rs`**: `to_wire_json_no_data()` (mesmo corpo de `to_wire_json`, `data` vazio —
  usado quando o conteúdo vai por chunks separados, `data_size`/`data_root` continuam reais).
  `b64url_encode`/`b64url_decode` viraram `pub(crate)` pra uso cross-módulo.
- **`mod.rs`**: `submit_transaction_no_data` + `submit_chunk` (`POST /chunk`, campos `offset`/
  `data_size` sempre string JSON, nunca número). `publish()` decide o caminho via
  `chunk_data_for_upload`: ≤1 chunk real usa o `POST /tx` inline de sempre; caso contrário,
  `submit_transaction_no_data` + loop sequencial de `submit_chunk` (sem concorrência — achado #2
  acima), validando localmente cada prova antes de gastar a requisição, sem retry automático (erro
  já carrega `tx.id` + índice do chunk que falhou, pra diagnóstico/retomada manual). Sem mudança de
  assinatura em `publish()` nem nos wrappers existentes (`publish_vault_blob*`) — qualquer chamador
  passa a suportar qualquer tamanho de conteúdo automaticamente.
- **Testes**: Rust 178/178 (`cargo test --lib`, 5 ignorados: 3 pré-existentes + 2 novos de ArLocal).
  `cargo clippy` limpo (mesmo aviso pré-existente de `vault.rs:629`, não relacionado). Validado de
  fato contra ArLocal 1.1.20 (mesma receita — `overrides: {"arbundles": "0.6.12"}`): os 4 testes de
  `arlocal_tests` passaram, incluindo os 2 novos —
  `publish_multi_chunk_content_round_trip_against_arlocal` (conteúdo real de ~512KB, 3 chunks,
  exercita de fato `submit_transaction_no_data` + loop de `submit_chunk` pela primeira vez) e
  `publish_exact_double_max_chunk_size_round_trip_against_arlocal` (2×`MAX_CHUNK_SIZE` exatos —
  confirma contra um node real que o descarte do chunk final vazio funciona mesmo quando ainda
  sobra mais de 1 chunk de verdade).
- **Flakiness de rede conhecida, não nova**: os 2 testes pré-existentes (`publish_and_fetch...`,
  `publish_vault_blob...`) falharam algumas vezes com "error sending request" bem no `mint()` do
  faucet, mesmo rodando isolados (`--test-threads=1`, um de cada vez). Investigado a fundo desta
  vez: `curl` direto na mesma URL funcionou e ficou registrado no log do ArLocal; a requisição que
  falhou no lado do Rust **nunca apareceu no log do servidor** — confirma que é uma falha
  client-side/sandbox de rede (não do ArLocal, não do código novo), mesmo padrão já documentado na
  Sessão 186/187. Retry resolveu todas — os 4 testes têm pelo menos uma passagem limpa confirmada
  nesta sessão.
- **Ainda em aberto**: documentos do Vault ainda não migraram pra Arweave — a capacidade existe
  agora no cliente, mas o call site (`vault_publish`/`vault_document_read`/`VaultManagement.tsx`)
  continua no IPFS até uma etapa própria (decisão explícita desta sessão). Fallback de fetch via
  `GET /tx/{id}/offset` + `GET /chunk/{offset}` (pra gateways/nodes sem a remontagem automática de
  `GET /{id}`) não implementado — não testável contra ArLocal (offset ali é por ordem de chegada,
  não absoluto-no-weave, ver achado #2) e não é bloqueante hoje (`GET /{id}` já cobre ArLocal e
  gateways reais). Retry automático por chunk (com backoff, como `arweave-js` faz) não implementado
  — escopo deliberadamente reduzido pra v1, erro já carrega contexto suficiente pra retomada manual.

**Item "documentos do Vault" fechado (Sessão 189, 2026-08-10): cutover completo, IPFS → Arweave,
mesmo padrão de corte direto (sem feature flag, sem fallback) já usado no blob principal.**

- `arweave::publish_document_with_jwk`/`publish_document` (mod.rs) — mesmo par de camadas de
  `publish_vault_blob*`, mas com tags reais do documento (`Content-Type` = `doc.mime_type`,
  `File-Name` = `doc.file_name`, em vez das tags genéricas hardcoded do blob principal).
- `vault_publish` (lib.rs): loop de documentos pendentes trocou `ipfs::pin_vault` por
  `arweave::publish_document`; guard de `providers.is_empty()` removido (não sobrou nenhum uso de
  IPFS nesta função). `vault_document_read` não mudou — o dispatch por prefixo `ar://` já tinha
  sido escrito pensando nisso na Etapa 2.
- Frontend: `pinWarning`/`providers_failed` virou código morto em todo lugar que consumia o retorno
  de `vault_publish` (Arweave nunca populua `providers_failed`, nem pro blob nem pra documento) —
  removido de `useVaultPublish.ts`, `vaultPublishViaDeviceKey.ts`, `rotateVaultKeyOnRevoke.ts`,
  `ManageDevices.tsx`, `VaultEditApprovalModal.tsx`, `VaultManagement.tsx`. `tsc` limpo.
- Teste novo `publish_vault_document_round_trip_against_arlocal` (mod.rs, `arlocal_tests`) — mesmo
  padrão de `publish_multi_chunk_content_round_trip_against_arlocal` (conteúdo >256KB, exercita
  chunking de verdade), mas via `publish_document_with_jwk` com `file_name`/`mime_type` de teste.
  Rust 178/178 (+1 ignorado, total 6), `cargo clippy` limpo (mesmo aviso pré-existente de
  `vault.rs:629`). Validado contra ArLocal 1.1.20 de fato — mesma flakiness client-side já
  documentada (Sessões 186-188) apareceu de novo na primeira rodada em lote (4 de 5 falharam no
  `mint()`, confirmado de novo que a requisição nunca chegou no log do servidor); rodando cada teste
  isolado (`--test-threads=1`, um por vez), **os 5 testes de `arlocal_tests` passaram**, incluindo o
  novo — confirma round-trip real do documento (chunked, tags incluídas) contra um node Arweave de
  verdade, não só localmente.
- Escopo confirmado com o dono do projeto antes de implementar: Mobile ficou de fora (o blob
  principal do vault no Mobile ainda publica via IPFS — `VaultPublishService.publish()` nunca
  recebeu a Etapa 2 — gap real, registrado como próxima etapa própria, vai precisar de um cliente
  Arweave inteiro em Dart, não tem hoje).

**Novo item de backlog registrado (Sessão 189, não implementado, dono do projeto pediu explicitamente
pra guardar pra depois): permitir que apps terceiros integrados via TruthID armazenem conteúdo no
Arweave usando a conta TruthID da pessoa, com a TruthID pagando o custo.** Contexto: já existe hoje
um canal genérico pra apps terceiros pedirem storage via identidade TruthID (`pin_content`/canal
`/pin`, ver Sessão 106) — mas ele **continua só no IPFS**, não foi tocado por nenhuma etapa desta
migração (só o Vault foi migrado). Generalizar esse canal pro Arweave é o próximo passo natural, mas
reabre a mesma pergunta de billing/metering já levantada na avaliação da Storacha (ver acima nesta
seção): quem paga e como? Casos de uso citados pelo dono do projeto envolvem payloads bem maiores
que o Vault (ex.: mundos de Minecraft, ~2GB, com upload novo a cada sessão de jogo).

Estimativa de custo dada nesta sessão (preço de referência já levantado acima nesta seção,
~US$0,0000037/KB, AR≈US$1,84, ago/2026 — **volátil**, não é cotação ao vivo): 2GB ≈ **US$7,76 por
upload**, pagamento único e permanente (sem reembolso, sem deleção — modelo de endowment).

**Correção registrada na mesma sessão**: a preocupação inicial de "billing/metering entre múltiplos
usuários" (por analogia com a conta única compartilhada da Storacha) **não se aplica aqui** — checado
no código (`pin_content`, `lib.rs:846-862`), o canal `/pin` já existente usa
`ipfs::load_providers()`, a configuração **local da própria pessoa**, não uma conta central da
TruthID (que nem existe — o projeto é self-sovereign por instalação, sem backend compartilhado).
Generalizar `pin_content` pro Arweave usaria naturalmente a wallet Arweave que a própria pessoa já
configura (mesma `get_arweave_wallet()` usada pelo Vault) — cada instalação paga pelo próprio uso,
sem problema de billing entre usuários.

O ponto real não é quem paga, é **não reenviar o payload inteiro a cada sessão**. Caso de uso citado
(mundo de Minecraft) tem uma saída natural: o save do Minecraft já é dividido em arquivos de região
(`.mca`), uma sessão de jogo normal só altera uma fração pequena do mapa — um "commit" estilo git
(árvore de hashes por arquivo de região, sobe só o que mudou) fica bem mais perto de
~US$0,40-0,80/sessão do que US$7,76, reaproveitando a mesma forma que git já usa pra objetos
(blob+tree), só trocando o content store local do git por Arweave. Fica registrado como direção de
design pra quando isso for desenhado de verdade — nada implementado ainda.

**Refinamento decidido na mesma conversa (ainda 2026-08-10, sem código)**: o "MCGit" (nome de
trabalho — interface amigável de versionamento de mundos de Minecraft via git, integrada ao TruthID)
**não vai ser desenvolvido neste repo**, dono do projeto só quer o TruthID preparado pra suportar.
Direção escolhida: **não reinventar um sistema de árvore de hashes customizado — usar o modelo de
objetos do git de verdade** (blob/tree/commit, já content-addressed, já com compartilhamento
estrutural nativo — arquivo que não mudou não duplica). Existe precedente real de "git sobre storage
descentralizado" pra referência de interface (Radicle é o mais maduro; git-remote-ipfs é mais
simples), sem compromisso de usar nenhum dos dois.

O que cabe ao TruthID, quando isso for implementado: só generalizar `pin_content`/`/pin` (item já
registrado acima) pra virar um content store genérico endereçado por hash, pago pela wallet local da
pessoa, assinado pela identidade dela — sem saber nada sobre git especificamente. O app externo
(MCGit) que rodaria um repo git local normal e, no "push", percorreria os objetos git novos da sessão
mandando cada um pro `/pin` do TruthID em vez de pra um remote git tradicional. Checado no código
nesta sessão: os **documentos do Vault já têm o primitivo equivalente ao "não reenviar o que não
mudou"** — `document_needs_pin` (`vault.rs`) compara hash do conteúdo atual contra o já publicado e
pula o upload se bateu, mesmo princípio de content-addressing que o git usa. O blob principal do
vault **não** tem esse mecanismo (sempre republica inteiro — aceitável só porque é ~3KB); não serve
de modelo pra payloads grandes.

**Decisão registrada (mesma sessão): não adotar git (nem `libgit2`/binário `git`) como camada geral
de storage do TruthID — descartado deliberadamente, não é lacuna a fechar depois.** Raciocínio: um
blob git é o hash do conteúdo — comparar hash (`document_needs_pin`) já é o mecanismo interno do
git, não um substituto inferior dele; a estrutura extra do git (árvore, commit, merge) só compra algo
quando existem muitos arquivos inter-relacionados com mudança incremental real e histórico útil —
nenhum dos dois workloads atuais do TruthID (vault principal ~3KB sempre-recifra-inteiro, documentos
individuais grandes raramente revisados em pedaços pequenos) tem essa forma. Risco concreto adicional
contra adotar git de verdade: não existe binário `git` nem binding maduro de `libgit2` viável no
Mobile (Flutter/Dart, sandbox iOS/Android) — bloquearia paridade de plataforma. Caso apareça no
futuro um caso de uso *dentro* do TruthID com a forma do MCGit (muitos arquivos, incremental de
verdade), reabrir a discussão; até lá, manter conteúdo endereçado por hash como já é hoje.

**Correção sobre o quanto o MCGit precisaria do TruthID (mesma sessão)**: a lógica de git em si
(objetos, árvore, commits) fica inteiramente no MCGit, fora deste repo — nisso o dono do projeto
estava certo. Duas ressalvas concretas, checadas no código desta sessão, que valem quando isso for
retomado:
1. **Leitura não passa pelo TruthID de jeito nenhum, e isso é bom** — Arweave é rede pública, `GET
   https://arweave.net/{tx_id}` funciona de qualquer lugar sem TruthID no meio (mesmo padrão que
   apps terceiros já usam hoje pra ler do IPFS via gateway público). `/truthid/v1/pin`
   (`local_signer_server.rs:425`) é a única rota do canal genérico hoje — write-only, não existe
   rota de leitura, e não vai precisar existir, a menos que o conteúdo seja cifrado (aí a "leitura"
   vira problema de gestão de chave, não de fetch).
2. **A cota diária atual (`pin.rs:19`, `DEFAULT_DAILY_LIMIT = 50`/dia) foi calibrada pra uso tipo
   "salvar a cada edição"**, não pra "commitar dezenas/centenas de objetos git numa sessão só" — um
   MCGit real provavelmente estoura essa cota num único push. Isso é trabalho genuinamente do lado
   do TruthID (ajustar o modelo de cota, ex. por operação em lote em vez de por chamada), não algo
   que o MCGit consiga contornar sozinho.

**Rename parcial feito na mesma sessão: `PinResult` → `PublishResult`, movido de `ipfs.rs` pra
`lib.rs`.** Escopo decidido explicitamente com o dono do projeto depois de mapear ~80 arquivos com
"pin" no monorepo (Rust, TS, Dart, Python) — o nome "pin" não fazia mais sentido pro que virou o tipo
de retorno de `vault_publish` (hoje sempre Arweave), mas a maior parte do que apareceu na busca é o
canal `pin_content`/`/truthid/v1/pin` — genuinamente ainda IPFS, "pin" ainda correto ali, e é rota
HTTP pública já consumida por fora deste repo (Practice Valuation, SDKs) — renomear isso agora seria
breaking change espalhado em 5 linguagens, sem necessidade (só faria sentido no dia que esse canal
for de fato generalizado pro Arweave, item já registrado acima). Decisão: só o rename interno e
seguro agora. `PublishResult` (struct compartilhada, usada tanto por `ipfs::pin_vault` quanto por
`arweave::publish_vault_blob*`/`publish_document*`) — `PinResult` morava em `ipfs.rs` mas já não era
IPFS-específico; movido pra `lib.rs` (módulo raiz que já une os dois backends). TS: `PinResult` →
`PublishResult` em `types.ts` + 3 consumidores (`useVaultPublish.ts`,
`vaultPublishViaDeviceKey.ts`, `rotateVaultKeyOnRevoke.ts`, incluindo a variável local
`pinResult`→`publishResult` neste último). `cargo build`/`cargo test --lib` (178/178) / `cargo
clippy` / `tsc` limpos. **Não tocado**: `pin_content`, `/truthid/v1/pin`, `PinningProvider`,
`ipfs::pin_vault` (nome da função), e todos os espelhos em Mobile/extensão/SDKs — permanecem "pin"
de propósito, aguardando o item de generalização pro Arweave já registrado acima.

**Sessão 190 (2026-08-10): Etapa 1 do porte do cliente Arweave pro Mobile (Dart) — fechada e
validada contra ArLocal real.** Fecha o gap descoberto na Sessão 189: o Mobile nunca recebeu a
Etapa 2 do Desktop (blob principal do vault ainda publicava só via IPFS) porque não existia nenhum
cliente Arweave em Dart. Escopo desta etapa, confirmado com o dono do projeto: só o núcleo do
cliente (wallet, deep hash, merkle, transação, HTTP), validado isoladamente — integrar no
`VaultPublishService` (Etapa 2) e UI de wallet (Etapa 3) ficam pra depois, mesmo padrão de
estagiamento que o Desktop usou.

- **Arquivos novos, todos em `mobile/lib/services/`** (flat, mesma convenção já existente no
  diretório, sem subpasta nova): `arweave_b64url.dart`, `arweave_deep_hash.dart`,
  `arweave_merkle.dart`, `arweave_jwk.dart`, `arweave_transaction.dart`, `arweave_client.dart`,
  `arweave_wallet_service.dart`, `arweave_isolate.dart` — espelham 1:1 os módulos Rust
  equivalentes (`desktop/src-tauri/src/arweave/`), sem pacote pronto (único candidato no pub.dev,
  `CDDelta/arweave-dart`, abandonado desde 2023). Todo o RSA-PSS/BigInt roda em cima do
  `pointycastle` já presente no `pubspec.yaml` — não precisou de dependência nova.
- **Achado real corrigindo a suposição do plano**: o `base64Url` nativo do Dart é **tão estrito
  quanto o do Rust** (não permissivo, como o plano supôs) — rejeita o mesmo anchor não-canônico do
  ArLocal. Precisou de um decoder permissivo hand-rolled (`b64UrlDecodeLenient`, bit-packing manual,
  já que `dart:convert` não expõe a opção "allow trailing bits" que a crate `base64` do Rust tem) —
  validado byte-a-byte contra o vetor cross-checado do Rust.
- **Módulo de maior risco (`arweave_merkle.dart`, achado real de porte)**: `resolve_branch_proofs`
  em Rust é seguro contra aliasing por ownership de `Vec<u8>` (`p.clone()` pra esquerda, `p` movido
  pra direita); em Dart, `Uint8List` é mutável/compartilhável por referência — mitigado construindo
  sempre uma cópia nova via spread a cada nível (nunca mutando o prefixo recebido in-place), com
  teste de não-aliasing dedicado. Os 3 vetores de prova cross-checados contra `arweave-js`
  (`merkle.rs:434-436`) bateram byte-a-byte, confirmando que não há bug de aliasing.
- **Cross-check em duas camadas antes do ArLocal** (mesmo princípio do Rust — não confiar só em
  auto-consistência): Camada A reaproveitou literalmente os vetores hex já provados corretos contra
  `arweave-js` real nas sessões do Desktop (deep hash, merkle, `signatureData`) — todos bateram.
  Camada B fechou **dois gaps que o próprio Rust nunca tinha fechado**: (1) `wallet_address` nunca
  fora cross-checado contra `arweave.wallets.jwkToAddress` real (só contra si mesmo) — rodou e bateu
  exatamente; (2) a assinatura RSA-PSS gerada pelo `pointycastle` foi verificada por um verificador
  **genuinamente independente** (`crypto.verify('RSA-PSS', ..., {saltLength:32, mgf1Hash:'sha256'})`
  nativo do Node/OpenSSL — nem pointycastle, nem a reimplementação de verificação em JS do ArLocal) —
  passou, e rejeitou corretamente uma mensagem adulterada. Essa validação é mais forte do que a que
  o Rust tem hoje.
- **Achado incidental relevante pro Rust também**: pesquisa no código-fonte real do node Arweave
  (Erlang, `rsa_pss.erl`) mostrou que o hash usado *dentro* do RSA-PSS é sempre SHA-256 (SHA-384 é só
  do deep hash) — conferido que `transaction.rs:147` já usa `SigningKey::<Sha256>` corretamente, sem
  bug. Achado extra (menor confiança — leitura de código por um agente de pesquisa, não linha a linha
  por mim): o `verify/4` do node real parece extrair o salt do próprio bloco decodificado em vez de
  exigir um comprimento fixo, o que sugeriria que o risco "salt length estrito" (aberto desde a
  Sessão 186) pode ser menor do que se pensava — não decisivo sozinho, mas a Camada B acima (OpenSSL
  aceitando salt length 32 de verdade) é evidência real na mesma direção.
- **`arweave_client.dart`**: mesma API de `mod.rs` (`getPrice`/`getTxAnchor`/`submitTransaction`/
  `submitTransactionNoData`/`submitChunk`/`getTxStatus`/`fetchData`/`getWalletBalance`/`publish()`),
  `dart:io HttpClient` puro (não `package:http`, que não é dependência do projeto). Teste dedicado
  provou a sequencialidade do upload de chunks (nunca concorrente, mesmo motivo do Rust) contra um
  `HttpServer` local instrumentado pra detectar concorrência real.
- **`arweave_isolate.dart`**: `signTransaction`/`generateJwk` sempre rodam em isolate dedicado
  (`Isolate.run`), nunca inline — confirmado empiricamente que `ArweaveJwk` (classe simples de
  strings) atravessa a fronteira do isolate sem problema; nenhum objeto `pointycastle`
  (`RSAPrivateKey`/`RSAPublicKey`) cruza a fronteira, só é reconstruído dentro do isolate a partir
  dos campos do JWK.
- **Testes**: 8 arquivos novos, ~571 testes na suíte inteira do Mobile passando (nenhuma regressão),
  `flutter analyze` limpo (mesmos 6 avisos pré-existentes, não relacionados). Testes de integração
  contra ArLocal (`arweave_arlocal_integration_test.dart`, tag `arlocal` — primeira vez que o Mobile
  ganha esse padrão, via `dart_test.yaml` com `skip:` + `flutter test --tags arlocal --run-skipped`,
  equivalente ao `#[ignore]`/`-- --ignored` do Rust) rodaram de fato contra ArLocal 1.1.20 real: os 3
  cenários (inline pequeno, multi-chunk, múltiplo exato de `maxChunkSize`) passaram, incluindo um
  retry pela mesma flakiness client-side já documentada (Sessões 186-188) — não é bug. **Achado de
  ambiente**: o container Docker do Mobile não alcança serviços do host via IP do gateway da bridge
  (firewall do host bloqueando, não limitação do ArLocal — o `.listen()` dele já bind em todas as
  interfaces) — validado com `network_mode: host` temporário no `docker-compose.yml`, revertido
  depois (não é mudança permanente).
- **Ainda em aberto, registrado explicitamente**: (1) micro-benchmark de `signTransaction` em
  hardware físico real, modo release — dono do projeto optou por adiar (sem celular conectado nesta
  sessão), UI de progresso (Etapa 3) só seria afetada se o tempo for alto, não bloqueia o resto; (2)
  Etapa 2 (integrar no `VaultPublishService`, cobrindo tanto blob principal quanto documentos — Mobile
  não tem hoje o equivalente de `document_needs_pin` sendo usado com Arweave) e Etapa 3 (UI de wallet,
  mesmo papel de `ArweaveWalletSection` no Desktop) — nenhuma das duas desenhada ainda.

**Sessão 191 (2026-08-11): Etapa 2 do porte Mobile — `VaultPublishService` migrado do IPFS pro
Arweave, mesmo corte direto sem fallback do Desktop.** Fecha o gap descoberto na Sessão 189 por
completo (blob principal + documentos anexados do Mobile agora publicam no Arweave de verdade).

- **`ArweaveVaultPublisher`/`ArweavePublishResult` novos em `arweave_client.dart`** — mirror direto
  de `arweave::publish_vault_blob(_with_jwk)`/`publish_document(_with_jwk)` (Rust): combina
  `ArweaveWalletService.load()` (já existia da Etapa 1, sem fallback, mesma mensagem de erro do
  Rust) + o orquestrador `publish()` já existente + tags certas por tipo de conteúdo (`Content-Type`
  genérico + `App-Name` pro blob; `Content-Type`=mimeType + `App-Name` + `File-Name` pro documento) +
  `contentHash` via `keccak256`. Sem conceito de "providers" — Arweave não tem, mesma simplificação
  que o Rust já tinha feito.
- **`VaultPublishService`**: troca `IpfsPinClient`/`PinningProviderService` por
  `ArweaveVaultPublisher` injetado (nenhum call site em `vault_screen.dart`/
  `vault_edit_approval_screen.dart` passava esses parâmetros explicitamente — usavam o default, não
  precisaram de edição). `documentNeedsPin` mantido sem renomear (Rust também não renomeou
  `document_needs_pin` ao migrar). `VaultPublishResult` perdeu `providersOk`/`providersFailed` —
  já eram código morto mesmo do lado IPFS (nenhum caller lia, achado nesta sessão), mesma limpeza já
  feita no TS/Desktop (Sessão 189). `IpfsPinClient`/`PinningProviderService` continuam existindo,
  intocados — servem o dead-drop LAN e o canal `/pin` de apps terceiros, fora de escopo.
- **Achado incidental**: dois testes de widget (`vault_edit_approval_screen_test.dart`) também
  instanciavam `VaultPublishResult` com os campos removidos — corrigidos junto.
- **Testes**: mocks reescritos (`MockArweaveVaultPublisher` no lugar de `MockIpfsPinClient`/
  `MockPinningProviderService`), mesma cobertura de antes (pending changes, TOCTOU do
  `markPublished`, Fase 15.7 de documentos) + teste novo de integração contra ArLocal real
  (`arweave_vault_publisher_arlocal_test.dart`, tag `arlocal`) validando `publishVaultBlob` e
  `publishDocument` ponta a ponta (wallet → publish → mine → status confirmado → fetch com bytes
  idênticos). Suíte completa: 571 testes, `flutter analyze` limpo.
- **Achado de test infra**: `TestWidgetsFlutterBinding.ensureInitialized()` instala um
  `HttpOverrides` que faz todo `HttpClient` devolver 400 sem tocar rede (proteção padrão contra
  testes de integração acidentais) — mas esse teste precisa de rede real (ArLocal) E do mock do
  canal `flutter_secure_storage` (que exige o binding). Resolvido com `HttpOverrides.global = null;`
  logo depois do `ensureInitialized()`. **A mesma flakiness client-side de sempre (Sessões 186-188)
  apareceu de novo**, confirmada desta vez também no teste já existente e já validado da Etapa 1
  (`arweave_arlocal_integration_test.dart`, rodado de novo aqui só pra isolar a causa) — não é
  regressão do código novo, é ambiental; resolvido com retry até uma rodada limpa, mesmo padrão de
  sempre. `network_mode: host` usado de novo temporariamente no `docker-compose.yml` pra validar,
  revertido depois.

**Em aberto**: Etapa 3 (UI de wallet Arweave no Mobile, mesmo papel de `ArweaveWalletSection` do
Desktop) — única peça que falta pra fechar 100% a paridade Desktop/Mobile do Arweave.

**Sessão 192 (2026-08-11): Etapa 3 fechada — UI de wallet Arweave no Mobile, paridade 100% com o
Desktop.** Fecha por completo o épico de migração de storage no lado Mobile (Etapas 1-3, Sessões
190-192).

- **Nova tela `mobile/lib/screens/arweave_wallet_screen.dart`**, mirror direto de
  `ArweaveWalletSection` (`desktop/src/components/VaultSettings.tsx:399-503`), mesmo padrão de
  UI já usado em `pinning_providers_screen.dart` (`StatefulWidget`/`setState`, sem
  `FutureBuilder`/Provider/Riverpod/Bloc). Reaproveita 100% da camada de serviço já existente
  (`ArweaveWalletService.exists/address/generate`, `getWalletBalance` de `arweave_client.dart`) —
  nenhum código novo de serviço, só UI.
- Fluxo idêntico ao Desktop: carrega existência/endereço/saldo no `initState` (saldo é
  best-effort, endereço aparece mesmo se a consulta de saldo falhar); botão "Gerar wallet Arweave"
  (desabilitado + "Gerando..." durante o keygen RSA-4096, que já roda em isolate no service);
  endereço em `SelectableText` monospace + botão copiar (`Clipboard.setData`, feedback "✓
  Copiado!" por 2s, mesmo padrão de `wallet_screen.dart`); saldo convertido de winston pra AR
  (`/1e12`, 6 casas decimais); dica extra se saldo == 0.
- **Escopo deliberadamente igual ao Desktop, sem ir além**: sem import/export de chave na UI
  (mesmo `ArweaveWalletService.import()` já existindo em Dart desde a Etapa 1) e sem QR code
  (embora `wallet_screen.dart` já use `QrImageView` pro endereço ETH) — ambos ficaram de fora por
  não fazerem parte do papel documentado da tela ("mesmo papel de `ArweaveWalletSection`").
- Novo `IconButton` (`Icons.account_balance_wallet_outlined`, tooltip "Arweave wallet") em
  `vault_screen.dart`, ao lado do de "Pinning providers", dentro do mesmo bloco `if (_canWrite)`.
- **Sem teste de widget novo**: `pinning_providers_screen.dart` (mirror mais próximo, também com
  chamada HTTP real não-injetada) não tinha teste de widget antes desta sessão — mesmo padrão
  seguido aqui; a lógica de negócio já é coberta por `arweave_wallet_service_test.dart` e
  `arweave_client_test.dart`. 571 testes Mobile continuam passando, `flutter analyze` limpo.
- **Não validado em hardware físico** (sem celular conectado nesta sessão, mesma limitação já
  registrada nas Sessões 190/191) — só revisão de código + `flutter analyze`/`flutter test`.

**Sessão 193 (2026-08-11): canal `pin_content`/`/truthid/v1/pin` (apps terceiros, ex: Practice
Valuation) migrado do IPFS pro Arweave — os dois pontos de entrada, Desktop (loopback HTTP) e
Mobile (cross-device via QR).** Pedido explícito do dono do projeto desde a Sessão 189: apps
terceiros usam a mesma wallet Arweave local que a pessoa já configura pro Vault, sem billing
central.

- **Rust**: `arweave::publish_pinned_content_with_jwk`/`publish_pinned_content` novos
  (`arweave/mod.rs`), mesmo padrão de wrapper por entry-point já usado por
  `publish_vault_blob`/`publish_document` (tags genéricas, corte direto sem fallback pro IPFS,
  erro claro se a wallet não estiver configurada). `pin_content` (`lib.rs`) passa a chamar essa
  função em vez de `ipfs::load_providers`/`ipfs::pin_vault` — assinatura não muda, continua
  injetada como a mesma closure em `pin::handle_incoming`. `PinResponse`/`PinOutcome` não mudam
  de schema (rota HTTP pública já consumida fora do repo): `cid` sai prefixado `ar://` (mesmo
  dispatch de `vault_document_read`), `providersOk: ["arweave"]`.
- **Achado que expandiu o escopo**: existem *dois* pontos de entrada do `/pin`, não um — o
  loopback HTTP do Desktop e o cross-device via QR pro Mobile
  (`TruthIDRequester.pin()`/`pin_approval_screen.dart`). Migrar só o Desktop deixaria pedidos
  roteados pro Mobile presos no IPFS. `ArweaveVaultPublisher.publishPinnedContent` novo em
  `arweave_client.dart` (mirror do Rust), `pin_approval_screen.dart::_approve()` reescrito pra
  chamar isso em vez de `_pinningProviderService.load()`/`_ipfsPinClient.pinVault(...)`.
  `_ipfsPinClient`/`_pinningProviderService` continuam no arquivo — servem só o dead-drop do
  envelope de *resultado* via `CrossDeviceDeliveryChannel`, mecanismo de transporte não
  relacionado ao backend do conteúdo publicado.
- **Segundo achado, confirmado com o dono do projeto antes de mexer**: depois dessa migração, o
  sistema de "Pinning Providers" (Kubo/PSA) do **Desktop** ficava inteiramente órfão — o Vault já
  não o usava desde a Sessão 189, e o `/pin` era o último chamador de
  `ipfs::pin_vault`/`load_providers`. Decisão já registrada na Sessão 184 ("remover o sistema de
  pinning por completo"), nunca fechada até agora. Removido nesta sessão:
  `PinningProvider`/`pin_vault`/`kubo_add`/`psa_pin`/`load_providers`/`save_providers` de
  `ipfs.rs` (mantidos `keccak256_hex`/`fetch_from_gateway`, ainda usados por
  `vault_document_read` pra ler documentos antigos em IPFS); comandos Tauri
  `vault_get_providers`/`vault_set_providers`; a seção inteira de gerenciamento de providers em
  `VaultSettings.tsx` (o componente vira só `<ArweaveWalletSection /><PinAuthorizationsSection />`);
  tipo `PinningProvider` de `types.ts`; dependência `futures` e feature `multipart` do `reqwest`
  em `Cargo.toml` (confirmado por grep que ficaram sem nenhum uso no crate). Header da view
  renomeado de "Providers de Pinning" pra "Wallet Arweave" em `VaultManagement.tsx`. **Isso é só
  sobre o Desktop** — no Mobile, `PinningProviderService`/`IpfsPinClient` continuam 100% vivos,
  usados pelo dead-drop LAN de várias outras telas de aprovação (sign-message, sign-request,
  autofill), sistema completamente separado.
- **Testes**: `mobile/test/screens/pin_approval_screen_test.dart` — grupo "fase 2 — Approve"
  reescrito com `MockArweaveVaultPublisher` no lugar de `MockIpfsPinClient`/
  `MockPinningProviderService`; teste "sem provider configurado" virou "sem wallet configurada".
  Nenhum teste de `pin.rs`/`local_signer_server.rs` mudou de comportamento (usam `fake_pin`
  sintético e só testam o caminho Rejected, respectivamente) — só comentários corrigidos.
  `cargo test --lib` 177/177, clippy limpo, `tsc --noEmit`/`npx vitest run` (101/101) limpos,
  Mobile 571/571 + `flutter analyze` limpo.
- **Não validado de ponta a ponta**: precisa de uma wallet Arweave financiada de verdade e do
  outro app (Practice Valuation) rodando pra exercitar o `/pin` contra um node Arweave real —
  mesma limitação de todo o épico de migração de storage.

**Sessão 194 (2026-08-12): validação de hardware real (Android físico + Desktop nativo) — fecha a
pendência de benchmark da Sessão 190, acha uma regressão real de onboarding pós-migração.**

- **Pareamento de device novo em hardware real, ponta a ponta**: build debug instalado num Samsung
  Galaxy S25 FE físico (adb wireless), identidade nova gerada localmente, pareado contra a
  identidade `@masterlxz` (Mainnet real) via `PairDevice.tsx` no Desktop — commit-reveal assinado
  pela Ledger física, os dois passos confirmaram, device apareceu registrado no Mobile via polling.
  Fluxo nunca tinha sido validado em hardware real desde que existe.
- **Achado real (regressão de onboarding, não corrigido ainda)**: o vault dessa identidade aponta
  pro último CID publicado no IPFS, de antes da migração pro Arweave (Sessão 193). Um device novo
  sem cache local não consegue carregar esse CID — todos os gateways públicos dão timeout, porque
  o pinning dedicado foi desligado na mesma sessão que migrou o Vault. O Desktop só continua
  funcionando porque já tinha o vault em cache local de antes; um device **novo** pareado a
  qualquer identidade que não republicou desde a Sessão 193 fica sem conseguir ler o vault (não é
  perda de dado — o Desktop original ainda tem o conteúdo — mas onboarding de device novo quebra
  silenciosamente pra essas identidades). Mitigação natural é republicar (qualquer save no Desktop
  gera um CID novo no Arweave), mas isso exige a wallet Arweave da identidade estar financiada.
  **Decisão do dono do projeto (mesma sessão): documentar como risco conhecido por agora, sem
  fallback automático implementado.** Identidades que não republicarem o vault desde a Sessão 193
  ficam sujeitas a esse onboarding quebrado pra device novo até republicarem (o que já resolve
  sozinho, sem código novo — só exige a wallet Arweave da identidade estar financiada). Reavaliar
  se compensa um fallback automático (detectar CID IPFS morto e sugerir republish) só se isso se
  mostrar um problema recorrente na prática.
- **Geração de wallet Arweave validada em hardware real nos dois lados**: Desktop (nativo, via
  `ArweaveWalletSection`) e Mobile (via pareamento acima, mesma lógica de `ArweaveWalletService`).
  Um travamento momentâneo da janela do Desktop durante o teste foi falso alarme (processo nunca
  morreu, CPU do container ainda ativa, janela voltou sozinha) — não é bug.
- **Publish real na Mainnet do Arweave tentado e falhou como esperado**: wallet recém-gerada com
  saldo zero recebeu `POST /tx` → `400 Bad Request: Transaction verification failed` do node
  Arweave. Confirma (não é bug novo) a pendência já registrada nas Sessões 190-193 — publish real
  exige AR de verdade na wallet, decisão consciente do dono do projeto de não financiar agora.
- **Benchmark de `signTransaction` em modo release, hardware físico real (Galaxy S25 FE) — fecha a
  pendência da Sessão 190**: medido via hook temporário (long-press no título "TruthID", revertido
  logo depois de coletar o dado, nunca commitado) chamando `generateJwkInIsolate`/
  `signTransactionInIsolate` diretamente. Resultado: **keygen (RSA-4096) = 1743ms, sign (PSS,
  20KB) = 16ms**. Conclusão: assinatura é rápida o bastante pra não precisar de UI de progresso
  dedicada; geração de chave (~1.7s, operação única de setup) já tem o loading state "Gerando..."
  implementado desde a Sessão 192, adequado ao tempo medido.

**Sessão 195 (2026-08-12): `/code-review` sobre os 15 commits da migração de storage pro Arweave
(`03c5828..40ba64b`) achou 10 problemas — os 5 mais graves corrigidos nos dois lados
(Rust+Dart).**

- **RSA exponent fixo em `verify_transaction_signature`/`verifyTransactionSignature`**
  (`transaction.rs`/`arweave_transaction.dart`): assumia `e = 65537` fixo em vez de ler o `e` real
  da wallet — uma wallet importada com expoente diferente assinava válido mas falhava na
  verificação local, ficando permanentemente incapaz de publicar. Corrigido nos dois lados
  (achado do review só apontava o Rust; confirmado que o Dart tinha o mesmo bug, corrigido
  também pra manter a paridade). Teste de regressão novo em cada lado usa uma chave de expoente
  não-padrão (17) pra provar que a wallet de teste fixa (que por acaso usa 65537) não mascarava o
  bug.
- **Checkpoint/resume pra publish multi-chunk** (`checkpoint.rs`/`arweave_checkpoint.dart`,
  módulos novos nos dois lados): antes, um chunk que falhasse no meio do upload deixava a tx
  presa on-chain incompleta pra sempre — só resolvia recomeçando do zero, o que desperdiça o
  reward já comprometido pela tx anterior. Decisão do dono do projeto: implementar
  checkpoint/resume completo (não só retry), um checkpoint por hash SHA-256 do conteúdo (não um
  único arquivo/entrada global — suporta múltiplas publicações parciais pendentes ao mesmo
  tempo). `publish()` salva o progresso depois de cada chunk confirmado; uma chamada seguinte com
  o mesmo conteúdo+wallet+node detecta o checkpoint e retoma do chunk certo, sem re-pagar
  preço/anchor/tx. Checkpoint com dados divergentes (conteúdo mudou) é descartado, não reusado.
  Rust guarda em `$HOME/.truthid/arweave_checkpoint_{hash}.json` (mesmos helpers de
  `config.rs` já usados pela wallet); Dart guarda no `FlutterSecureStorage` (mesmo padrão de
  `ArweaveWalletService`). **Achado no caminho**: os dois testes novos de mock-server geravam o
  mesmo conteúdo de teste (mesma fórmula usada em outros testes já existentes), colidindo no
  mesmo arquivo de checkpoint real quando `cargo test` roda em paralelo — corrigido dando um byte
  marcador distinto pra cada teste, não um bug da feature em si.
- **Texto enganoso na tela "Pinning Providers" do Mobile** (`pinning_providers_screen.dart`):
  ainda afirmava que o vault cifrado é enviado pra esses providers ao publicar — falso desde a
  migração pro Arweave. Corrigido pra explicar que o vault agora publica no Arweave e que esses
  providers seguem servindo só o canal de entrega cross-device (LAN/dead-drop) das aprovações com
  a extensão. Escopo só do texto — a tela/feature em si continua existindo, ainda usada por
  `CrossDeviceDeliveryChannel`.
- **Checagem de saldo antes de publicar** (`get_wallet_balance`/`getWalletBalance` já existiam,
  só nunca eram chamados antes de `publish()`): agora `publish()` compara saldo vs. reward (via
  `BigUint`/`BigInt`, evita overflow) logo após `get_price`, antes de qualquer chamada que muta
  estado — erro claro de "saldo insuficiente" em vez do `POST /tx 400` cru que a própria sessão
  anterior (194) bateu de frente durante a validação em hardware real. Corrigido nos dois lados
  (achado do review só testou o Rust; Dart tinha a mesma lacuna, corrigido também).
- **`get_tx_status`/`getTxStatus` mascarava erro real do node como "pendente"**: qualquer status
  HTTP diferente de 200 (incluindo 500/429 reais) caía no mesmo branch de "ainda não confirmada"
  que 202/404 (esses sim legítimos) — um node fora do ar ficava indistinguível de uma tx
  genuinamente não minerada. Corrigido nos dois lados (Dart também tinha o bug, não só o Rust
  apontado pelo review) pra só tratar 202/404 como pendente; qualquer outro status vira erro.
  Nenhum caller de produção existe ainda pra essa função em nenhum dos dois lados (só
  teste/validação manual).
- **Validação**: `cargo test --lib` 189/189, `cargo clippy` limpo (só 1 warning pré-existente não
  relacionado em `vault.rs`), `flutter test` 582/582, `flutter analyze` limpo (só ruído
  pré-existente não relacionado). `npx vitest run` do Desktop tem 6 falhas em `totp.test.ts`
  (`crypto.subtle.sign` incompatível com o polyfill do ambiente vitest) — confirmado
  pré-existente e sem relação (nenhum arquivo TS tocado nesta sessão). **Não validado**: cenário
  real contra ArLocal (matar o node no meio de um publish multi-chunk) — os testes de mock server
  já provam a lógica de forma determinística, fica como validação adicional possível antes de
  produção.

**Sessão 196 (2026-08-13): lacuna de documentação da Sessão 195 corrigida — `/code-review` sobre
`03c5828..HEAD` (mesma migração + o fix da própria S195) re-rodado pra registrar a lista completa
de achados, não só os corrigidos.**

- **Contexto da lacuna**: a S195 documentou só os 5 achados que viraram código; os outros 5 do
  `/code-review` original nunca foram persistidos em lugar nenhum (nem roadmap, nem commit) —
  ficaram só na conversa daquela sessão, que não é recuperável depois de encerrada. Re-rodar o
  review foi a única forma de reconstruir a lista. **A partir de agora, todo `/code-review` deve
  registrar os 10 achados completos no roadmap, corrigidos ou não, cada um com o motivo de ter
  ficado de fora — não só o que virou commit.**
- **Achados ainda não corrigidos (registrados aqui antes de decidir o que corrigir)**:
  1. `desktop/src-tauri/src/lib.rs:609` — `vault_publish` só persiste os resultados de publish por
     documento (`vault::save`) depois que o loop inteiro de documentos termina com sucesso; uma
     falha no meio do loop descarta publishes já pagos em AR real — o próximo `document_needs_pin`
     não vê o CID novo e republica (paga AR duas vezes) um documento já on-chain. O espelho em
     Dart (`vault_publish_service.dart`) salva cada resultado dentro do próprio loop e não tem
     esse problema — divergência real entre as duas implementações.
  2. `desktop/src-tauri/src/arweave/mod.rs:31` — `http_client()` não define timeout (diferente do
     `ipfs.rs`, que usa 15s deliberadamente); um node/gateway Arweave sem resposta trava qualquer
     comando `arweave_*` indefinidamente.
  3. `mobile/lib/screens/arweave_wallet_screen.dart:108` — texto de ajuda ainda diz que documentos
     anexados usam pinning providers IPFS; falso desde que `vault_publish_service.dart` passou a
     publicar documentos direto no Arweave sem fallback. Risco real: usuária não financia a wallet
     Arweave por achar que não precisa.
  4. `desktop/src-tauri/src/arweave/mod.rs:263` — `try_resume` recomputa a merkle data root do
     zero (re-chunka e re-hasheia o conteúdo inteiro) em vez de reusar `chunks`/`proofs` que o
     chamador já construiu e passou; custo extra O(tamanho do arquivo) a cada tentativa de resume.
     Mesmo padrão espelhado em `arweave_client.dart::_tryResume`.
  5. `desktop/src-tauri/src/arweave/wallet.rs:91` — `parse_jwk` reconstrói a chave privada RSA-4096
     só pra validar e descarta; `publish()` reconstrói a mesma chave de novo pra assinar — dobra o
     custo de CPU de reconstrução de chave por publish.
  6. `desktop/src-tauri/src/arweave/mod.rs:235` — checkpoint salvo a cada chunk individual do
     upload (não periodicamente); pra um arquivo grande (~4000 chunks) isso é ~4000 escritas de
     arquivo no desktop e ~4000 round-trips de IPC pro secure storage no mobile.
  7. `desktop/src-tauri/src/arweave/mod.rs:476` — `publish_vault_blob_with_jwk` e
     `publish_pinned_content_with_jwk` são cópias byte a byte idênticas (mesma duplicação em
     `arweave_client.dart`); mudança futura em uma tem boa chance de não propagar pra outra.
  8. `mobile/lib/services/ipfs_pin_client.dart:66` — `IpfsPinClient.pinVault` ficou sem nenhum
     chamador em produção depois da migração (só usado pelo próprio teste); o lado Rust já
     deletou o equivalente (`pin_vault`/`kubo_add`/`psa_pin`) no mesmo diff, o Dart não.
  9. `desktop/src-tauri/src/arweave/merkle.rs:7` — `MAX_CHUNK_SIZE`/`MIN_CHUNK_SIZE` (constantes
     de protocolo do Arweave) hardcoded independentemente em Rust e Dart, sem spec compartilhada.
  10. `mobile/lib/services/arweave_b64url.dart:19` — `b64UrlEncode` duplica
      `base64UrlEncodeNoPad` já existente em `webauthn_service.dart` (mesma lógica exata).
- **Decisão do dono do projeto**: registrar tudo primeiro (feito acima), decidir o que corrigir
  depois — em seguida, decidiu corrigir os 10.
- **Todos os 10 corrigidos, mesma sessão**:
  1. `vault_publish` reescrito pra salvar (`vault::save`) logo após cada documento publicado com
     sucesso (loop por índice em vez de `&mut v.entries`, pra poder salvar `v` sem conflito de
     borrow) — não só no fim do loop. O lado Dart já estava correto, não precisou de mudança.
  2. `http_client()` do Arweave ganhou timeout de 15s (mesmo valor do `ipfs.rs`). No Dart,
     `arweave_client.dart` não tinha timeout em nenhuma das 7 chamadas `HttpClient()` — achado
     equivalente não listado no review original mas corrigido do mesmo jeito, pra manter paridade
     (helper `_newClient()` com `connectionTimeout` + `.timeout()` no request).
  3. Texto da tela de wallet Arweave (Mobile) alinhado com o do Desktop (`VaultSettings.tsx`):
     "o vault (blob principal e documentos anexados) e os apps terceiros autorizados publicam no
     Arweave".
  4. `chunk_data_for_upload`/`chunkDataForUpload` passaram a devolver também o `data_root` do
     conjunto de chunks completo (calculado reusando os hashes que `chunk_data`/`chunkData` já
     produziu, antes do descarte do chunk vazio final) — `try_resume`/`_tryResume` usam esse valor
     em vez de rechunkar+rehashear o conteúdo inteiro de novo. Testes atualizados pra checar que o
     root devolvido bate com `compute_data_root(&chunk_data(&data))`/`computeDataRoot(chunkData(data))`
     calculado à parte.
  5. Novo `wallet::deserialize_jwk` (desserializa + confere `kty`, sem reconstruir a chave RSA) usado
     nos 4 pontos de entrada de publish (`publish_vault_blob`, `publish_document`,
     `publish_pinned_content`, comando `arweave_publish`) no lugar de `parse_jwk` — a validação
     completa (reconstrução da chave) continua acontecendo uma única vez, dentro de
     `jwk_to_private_key` no caminho de `publish()`. `parse_jwk` continua igual (usado em
     import/leitura, onde falhar rápido vale a pena). **Investigado e confirmado que o Dart não
     tinha o mesmo problema** — `parseJwk` faz validação matemática (BigInt) sem construir os
     objetos de chave; `jwkToKeyPair` (na hora de assinar) só constrói os objetos, não repete a
     validação — não precisou de mudança.
  6. Checkpoint agora salva a cada 16 chunks (`CHECKPOINT_SAVE_INTERVAL`/`_checkpointSaveInterval`)
     e sempre no último, não mais a cada chunk individual — reenviar até 15 chunks já aceitos pelo
     node numa segunda falha é aceitável (`POST /chunk` é idempotente pro mesmo conteúdo+prova).
  7. Extraído `publish_generic_content_with_jwk`/`_publishGenericContent` como núcleo compartilhado;
     `publish_vault_blob_with_jwk`/`publishVaultBlob` e `publish_pinned_content_with_jwk`/
     `publishPinnedContent` viraram wrappers finos — mantidos como funções/métodos separados (não
     um alias) porque já existe uma divergência futura conhecida (tag de app de origem no `/pin`).
  8. `IpfsPinClient.pinVault`/`PinResult`/`_psaPin` removidos do Mobile (o Rust já tinha removido o
     equivalente na S193) — o arquivo de teste `ipfs_pin_client_test.dart`, que testava só esse
     método morto, foi deletado inteiro. `publishDeadDrop` e o resto do transporte LAN continuam
     intactos, cobertos por outros arquivos de teste.
  9. Sem como compartilhar a constante de verdade entre Rust e Dart (sem pipeline de codegen
     cross-linguagem no projeto) — mitigação real foi documentar em comentário cruzado explícito
     nos dois arquivos (`merkle.rs`/`arweave_merkle.dart`) que são constantes de protocolo Arweave,
     não escolha de código, e que precisam ser atualizadas juntas se o protocolo mudar.
  10. `arweave_b64url.dart::b64UrlEncode` teve a assinatura relaxada de `Uint8List` pra `List<int>`
      (mesma assinatura de `base64Url.encode`) e virou o encoder canônico do projeto;
      `webauthn_service.dart::base64UrlEncodeNoPad` passou a delegar pra ele em vez de reimplementar.
- **Validação**: `cargo test --lib` 189/189, `cargo clippy` limpo (só o warning pré-existente de
  `vault.rs`, corrigi um `manual_is_multiple_of` novo que o clippy acusou na minha própria mudança
  do achado 6), `npx tsc --noEmit` limpo (nenhum arquivo TS tocado nesta sessão), `flutter test`
  578/578 (removidos os 6 do arquivo deletado do achado 8, adicionados testes novos nos achados 4
  e 9), `flutter analyze` limpo (só o ruído pré-existente já conhecido de `tool/`).

---

**Sessão 197 (2026-08-13): redeploy em cascata do débito #52 (P1/P2/P26) — migração real da
identidade Mainnet, primeira vez que uma cascata acontece com valor de verdade em jogo.**

- **Contexto**: C1-C9 (`/code-review` da Sessão 140) estavam corrigidos no código desde a Sessão
  150, mas nunca deployados — `DeviceRegistry` mudou (débito #52, re-registro após revogação) e é
  referenciado como `immutable` por `SessionRegistry`/`VaultRegistry`/`RecoveryManager`/
  `TruthIDAccountFactory`, forçando cascata completa. Toda cascata anterior (Sessões 70/77/88)
  aconteceu com `totalIdentities() == 0` — nada a perder. Desta vez `totalIdentities() == 1`: a
  identidade `masterlxz` (Sessão 116), com 7 devices, um vault publicado e saldo ETH reais.
- **Achado que mudou o escopo real do trabalho**: a `TruthIDAccount` da identidade real foi
  deployada *antes* do fix C8 (Sessão 140, endereços de registry mutáveis via `updateRegistries`)
  — bytecode antigo, sem essa função, nunca vai poder ser redirecionado pros contratos novos. Pra
  se beneficiar dos fixes (inclusive a reentrância crítica do C1), era obrigatório deployar uma
  smart account nova via uma factory nova — e como o CREATE2 da factory inclui o próprio endereço
  dela no salt, isso muda o endereço da smart account, sem alternativa. Confirmado com o dono do
  projeto antes de seguir.
- **Fase 1 — contrato**: novo `DeviceRegistry.migrateDevices()`, função de uso único por
  identidade. Constructor ganha `legacyDeviceRegistry`/`legacyIdentityRegistry` (`address(0)`
  desativa a migração, usado em deploys locais/frescos). A função resolve o próprio username no
  registry novo (nunca aceita como parâmetro — evita spoof do histórico de outra identidade),
  busca a identidade correspondente no par legado, copia label/`addedAt`/status revogado/chave
  ECIES do vault de cada device (dedupe automático via `_devices[pubKey].exists`), trava
  reexecução com `_migrated[identityId]` setado antes de qualquer leitura externa (mesmo padrão
  CEI do fix C1). `IdentityResolver._identityRegistry` promovido de `private` pra `internal`
  (o próprio comentário do arquivo já antecipava essa necessidade). 9 testes novos em
  `DeviceRegistryMigration.t.sol` (happy path com 3 devices simulando um par legado real, `Already
  Migrated`, identidade sem correspondente no legado, device já re-pareado organicamente não é
  sobrescrito). `Deploy.s.sol` estendido com `LEGACY_DEVICE_REGISTRY`/`LEGACY_IDENTITY_REGISTRY`
  via `vm.envOr`. `forge test` 285/285.
- **Fase 2/3 — deploy real**: rehearsal completo no Sepolia primeiro (deploy dos 6 contratos via
  Ledger real, `--mnemonic-indexes 1` — a conta certa da Ledger, achada testando índices até bater
  com o `owner()` da smart account real; migração de devices não ensaiada lá porque o
  `IdentityRegistry` legado do Sepolia tinha `totalIdentities() == 0`, decisão do dono do projeto
  de não criar identidade de teste só pra isso). Confirmado tudo via `cast call` independente
  antes de tocar na Mainnet. **Mainnet**: mesma cascata (6 contratos), depois runbook manual
  passo a passo, cada transação assinada fisicamente na Ledger e simulada via `cast call` antes de
  `cast send`: (1) `createIdentity` com o mesmo username e uma assinatura de consentimento nova
  pro endereço da smart account nova (previsto via `factory.getAddress`); (2)
  `factory.createAccount`; (3) `smartAccountNova.execute(deviceRegistryNovo,
  migrateDevices())` — os 7 devices migrados numa única transação, status idêntico ao legado (3
  revogados, 4 ativos, confirmado device a device via `cast call` nos dois registries); (4)
  `smartAccountAntiga.execute(smartAccountNova, saldo, "")` — ETH movido, conta antiga zerada; (5)
  mesmo CID/contentHash do vault replicado no `VaultRegistry` novo via `execute()` direto (sem
  precisar do app — CID já é público, não depende de qual registry aponta pra ele). Tudo
  confirmado de ponta a ponta por leituras `cast call` independentes ao final.
- **Fase 4 — propagação**: endereços novos em `desktop/src/config/{contracts,truthidAccount}.ts`,
  `mobile/lib/services/blockchain_service.dart`, os 4 SDKs (TS/Python/Ruby/Dart), `README.md`,
  `sdk/README.md`, `docs/docs/{intro,contracts,smart-account}.mdx` (Mainnet e Sepolia). Flags
  `SESSION_DOMAIN_SEPARATION_ENABLED`/`sessionDomainSeparationEnabled` (P26) ligadas — o
  `SessionRegistry` novo já tem o fix C4 live. Practice Valuation (projeto separado, fora deste
  workspace) fica pendente de atualização manual pelo dono do projeto.
- **2 achados reais no caminho da validação, ambos testes desatualizados (não bugs de produto)**:
  o vetor de paridade cross-linguagem `computeSmartAccountAddress` (TS/Python/Ruby/Dart) tinha o
  endereço esperado hardcoded contra a factory antiga do Sepolia — recomputado e confirmado
  batendo byte a byte nos 4 idiomas com a factory nova; `wallet_screen_test.dart` mockava
  `getLatestBlockNumber()` fixo em 48.3M, menor que o novo `deviceRegistryDeployBlock`
  (~49.9M) — o guard real do app (`fromBlock > latest` pula o scan) fazia o teste passar sem
  nunca chamar `scan()`, confirmado como regressão de teste (não de app) comparando contra a
  baseline via `git stash`.
- **Validação final**: `forge test` 285/285, `npx tsc --noEmit` limpo (Desktop e SDK TS),
  `npx vitest run` 101/101 (Desktop) + 17/17 (SDK TS), `pytest` 17/17 (SDK Python), `rspec` 17/17
  (SDK Ruby), `dart test` 69/69 (SDK Dart), `flutter analyze` limpo, `flutter test` 578/578
  (Mobile). `PENDING.md`/`ARCHITECTURE.md` atualizados (P1/P2/P26 resolvidos, débito #52 e item #5
  de Pendências de Deploy fechados).

**Sessão 198 (2026-08-13): checado o impacto real da migração de storage IPFS→Arweave (Sessões
184-196) nos 4 SDKs — achado bem menor do que a pergunta original supunha.**

- Pedido do dono do projeto: já que o storage do Vault e do canal `/truthid/v1/pin` (apps
  terceiros, ex: Practice Valuation) migrou pra Arweave, os SDKs (pensados originalmente pra IPFS)
  precisavam de algum ajuste? 3 agentes de exploração em paralelo (protocolo `/pin`, os 4 SDKs,
  transporte dead-drop) investigaram antes de qualquer código.
- **Achados convergentes**: o schema HTTP/JSON do `/pin` não mudou — `status`/`cid`/`contentHash`/
  `providersOk`/`providersFailed`/`error` continuam os mesmos campos, mesma decisão deliberada de
  não quebrar a rota pública. Só o *valor* de `cid` mudou (`"ar://<tx_id>"` em vez de CID IPFS);
  `providersOk`/`providersFailed` viraram constantes vestigiais (`["arweave"]`/`[]`).
  `TruthIDRequester.pin()` (único lugar nos 4 SDKs que toca nisso — TS/Python/Ruby confirmados sem
  nenhum código relacionado a pin/cid/ipfs, papel deles é só verificador) já tratava `cid` como
  string opaca, sem parsing/validação de formato — zero bug de código. O dead-drop (transporte
  IPFS/IPNS efêmero usado por `pin`/`sign-message`/`sign-request`/`vault-edit` quando não há LAN
  compartilhada) é mecanismo genuinamente separado do storage permanente — continua e deve
  continuar em IPFS (Arweave não serve pra "nome mutável com TTL curto"); vários comentários no
  código já documentam essa separação.
- **Único achado real**: `docs/docs/sdk/dart.md` — única doc pública do `pin()` (papel exclusivo
  do SDK Dart) — ainda descrevia "pin arbitrary bytes to its configured IPFS providers", falso
  desde a Sessão 193. Corrigido: texto do método, rótulo do exemplo (`'CID: ...'` →
  `'Content pointer: ...'`), e nota no doc comment de `PinResult.cid` explicando o prefixo
  `"ar://"`. Fixture de teste desatualizado corrigido junto (`sdk/dart/test/requester/pin_test.dart`:
  `'bafy123'`/`'local-kubo'` → `'ar://abc123'`/`'arweave'`, sem mudança de comportamento). Sem bump
  de versão (correção de doc/exemplo, não mudança de API). `dart analyze` limpo, `dart test` 69/69,
  build do Docusaurus validado. Commit `d775318`.

**Sessão 199 (2026-08-13): desenho refinado do Épico 2 (tier facilitado) — documento novo
`truthid-onboarding-sponsorship.md` (raiz do repo, sessão de arquitetura externa), registrado aqui
e removido da raiz. Ainda nada implementado.**

- **Continuação direta do Épico 2 registrado na Sessão 184** (ver acima) — não substitui aquele
  desenho, aprofunda as peças que ainda estavam vagas: como o customer que paga vira uma
  identidade TruthID de fato, e como o storage relay funciona especificamente contra **Arweave**
  (o desenho de 184 ainda citava Storacha; a migração real, decidida e executada depois, foi pra
  Arweave — Sessões 184-198. Este documento novo já nasceu escrito em cima de Arweave, sem
  precisar de correção).
- **Duas identidades separadas, só se conectam depois do bootstrap**: `Customer` (registro no
  backend de billing — email, customer id do Stripe/Mercado Pago, status de assinatura; criado via
  login social/magic link no site, sem nada de TruthID ainda) vs. **identidade TruthID** (a smart
  account ERC-4337 on-chain, só passa a existir no bootstrap).
- **Fluxo de onboarding**: (1) login social/magic link cria só o `Customer`; (2) paga assinatura
  recorrente, webhook de pagamento confirmado dispara o bootstrap; (3) **bootstrap**: device gera o
  keypair localmente (nunca sai do device), calcula o endereço counterfactual da smart account, e
  manda o primeiro UserOp (deploy + registro no `IdentityRegistry`) — sponsorizado, porque a conta
  ainda não tem ETH. **Elo pendente, não desenhado em detalhe**: como associar
  `smart_account_address` ↔ `customer_id` do Stripe — existe uma janela entre "pagou" e "identidade
  criada" onde o customer existe mas ainda não tem endereço pra vincular; precisa de um
  token/nonce de sessão emitido no passo 2 e consumido no passo 3.
- **Gas sponsorship via Verifying Paymaster (ERC-4337 padrão)**: signer off-chain do dono do
  projeto assina a autorização de sponsorship por UserOp; o contrato Paymaster só verifica a
  assinatura, não olha se a smart account tem fundos. Signer checa `isEntitled()` (ver abaixo)
  antes de assinar. **Opção descartada de novo, mesma linha da Sessão 184**: custódia temporária de
  chave pelo backend durante o bootstrap — quebraria self-sovereign desde o dia zero; o device já
  assina o próprio UserOp de deploy, backend só autoriza o gas. **Inativo não é "troca de dono"**:
  não existe transferência de controle — o signer só para de assinar sponsorship pro endereço; a
  conta continua on-chain, usuário continua dono da chave, só perde o gas grátis (fallback:
  self-funded, já grátis pra sempre desde a Fase 14).
- **Storage relay (Arweave), 2 chaves separadas**: chave TruthID (smart account, ERC-4337) cuida de
  identidade/auth/vault registry; **JWK Arweave local**, gerado no device, separado da smart
  account, serve só pra assinar/pagar upload. **Free tier**: usuário financia o próprio JWK
  (compra AR ou carrega crédito no bundler Irys/Turbo vinculado a ele), device assina e sobe direto,
  sem passar pelo backend. **Paid tier**: JWK do usuário fica ocioso; device manda o blob cifrado
  pro backend (`POST /vault/upload`), backend checa `isEntitled()` e sobe pro bundler usando a
  **conta do bundler do dono do projeto** (créditos pré-pagos), devolve o tx id pro device, que
  segue o commit normal no `VaultRegistry` (UserOp sponsorizado). **Por que relay e não financiar a
  chave do usuário diretamente**: transferência de AR/crédito pro JWK do usuário é on-chain e
  irreversível — se a pessoa exportar a chave, o saldo é dela pra sempre mesmo cancelando; não dá
  pra revogar valor já transferido. Relay evita isso porque o custo nunca sai da conta do usuário,
  cortar acesso ao expirar é trivial (mesmo padrão do paymaster). **Sem dimensionamento ainda**: como
  não há metering incremental por usuário (decisão: manter simples), precisa de um soft cap por
  usuário (MB/mês ou tamanho total do vault) pra evitar abuso do pool de créditos — não
  dimensionado.
- **Entitlement Service único, compartilhado entre gas e storage** — decisão explícita de não
  duplicar a lógica de "assinatura ativa" em dois lugares. Fonte de verdade: webhook Stripe/Mercado
  Pago atualizando uma tabela `subscriptions` (`customer_id`, `smart_account_address`, `status`,
  `expires_at`). Interface tipo `isEntitled(smartAccountAddress) → bool`, cache curto (Redis, TTL de
  minutos — paymaster signer e storage relay batem nele com frequência, latência importa nos dois).
  Consumidores: paymaster signer (antes de assinar sponsorship) e storage relay (antes de aceitar o
  blob). Benefício: um lugar único pra debugar perda de acesso e evoluir regras (grace period,
  planos com limites diferentes) depois.
- **4 pendências abertas, registradas no documento, nenhuma resolvida ainda**: (1) desenhar o
  token/nonce que fecha o elo `customer_id` ↔ `smart_account_address` na janela entre pagamento e
  bootstrap; (2) confirmar suporte a EIP-1271 nos bundlers candidatos (Irys/Turbo) — não é
  bloqueador porque o JWK Arweave é uma chave local separada da smart account, mas vale confirmar
  pra um fluxo futuro onde a smart account pagasse storage diretamente; (3) dimensionar o soft cap
  de storage por usuário no tier pago; (4) especificar o schema da tabela `subscriptions` e o cache
  do Entitlement Service.
- Documento fonte (`truthid-onboarding-sponsorship.md`, raiz do repo) removido depois de
  confirmado que todo o conteúdo está espelhado aqui — mesmo padrão já usado com
  `truthid-storacha-tier-facilitado.md` na Sessão 184.
- **Nada implementado ainda** — as 2.1-2.7 da Sessão 184 continuam de pé como estavam (2.5 rotação
  de device e 2.6 recovery seguem 100% composição do que já existe; 2.7 guardian-on-cancel segue
  sem desenho de contrato). Este documento adiciona detalhe de implementação a 2.1 (bootstrap),
  2.2 (paymaster) e ao lado de storage do tier pago, mas ainda é plano — a debater com o dono do
  projeto antes de qualquer `/plan` ou código.

**Sessão 199, continuação — novo `site/` no monorepo (v1: esqueleto + OAuth), fechado e validado
em hardware real na mesma sessão.**

- Decisão de arquitetura: `site/backend` (Ruby on Rails 8, API-only) + `site/frontend` (Next.js
  16, TypeScript, Tailwind) + Postgres, tudo via `site/docker-compose.yml` (decisão explícita do
  dono do projeto — tudo em Docker desde o início, mesma motivação de sempre: evitar fadiga de
  setup de novo, como já aconteceu ao trocar de PC). Rails é a fonte da verdade do login (OmniAuth
  google_oauth2) — Next.js só redireciona pro backend e consome a sessão via cookie
  (`credentials: "include"` + CORS com origin explícito, obrigatório porque `credentials: true`
  não aceita wildcard).
- Modelagem: `Customer` (email/nome/avatar — vira o `customer_id` de billing quando essa fase
  chegar) e `Identity` (`provider`+`uid`, `belongs_to :customer`, índice único), desenhada desde o
  início pra múltiplos providers por pessoa (Google agora; GitHub e o próprio TruthID como
  provider ficam de fora do v1, mas a modelagem já suporta sem migração nova). Sem Devise — um
  único fluxo de callback (`SessionsController`) e a futura strategy custom do TruthID
  (challenge-response, não OAuth2 padrão) encaixa mais fácil em OmniAuth puro.
- Simplificação deliberada, documentada em `site/README.md` pra revisitar antes de billing real:
  o link "Entrar com Google" é uma navegação GET simples (não passa por
  `omniauth-rails_csrf_protection`, que exigiria form POST coordenado entre origens diferentes) —
  mitigado com `OmniAuth.config.allowed_request_methods = [:get, :post]`, aceitando o risco baixo
  de login CSRF enquanto `Customer` não carrega billing nem dado sensível.
- Achado real no caminho: `config/database.yml` do Rails 8 gerado não dá pra usar com
  `DATABASE_URL` fixo no `docker-compose.yml` — a URL bakeia um nome de banco só, então um
  `RAILS_ENV=test` bateria no mesmo banco físico do dev. Corrigido usando
  `DATABASE_HOST`/`DATABASE_USERNAME`/`DATABASE_PASSWORD`/`DATABASE_NAME`/`DATABASE_NAME_TEST`
  separados, cada ambiente (`development`/`test`) resolvendo seu próprio nome de banco a partir do
  `database.yml`.
- Testado com `OmniAuth.config.test_mode`/`mock_auth` (sem precisar de credencial Google real):
  callback cria `Customer`+`Identity`, login duas vezes com a mesma conta reusa o `Customer`,
  `/api/me` retorna 401 sem sessão. 4/4 passando (`bin/rails test` dentro do container).
- **Validado em hardware real, mesma sessão**: dono do projeto criou o OAuth Client ID de verdade
  no Google Cloud Console, preencheu `site/.env`, e logou de ponta a ponta no navegador —
  `/auth/google_oauth2` redirecionou pro Google de verdade (confirmado também via `curl -L`, sem
  `invalid_client`/`redirect_uri_mismatch`), voltou autenticado pro `/dashboard`, `Customer` real
  criado no Postgres (`fabio.anjos.junior@gmail.com`). Achado real e corrigido na hora: a foto de
  perfil do Google veio esticada — `<img>` do avatar não tinha `object-fit`, corrigido com
  `object-cover` no `app/dashboard/page.tsx`.
- Fora de escopo deste v1, explícito no `site/README.md`: billing (Stripe/Mercado Pago),
  Entitlement Service, bootstrap de identidade TruthID, GitHub/TruthID como provider adicional,
  migração de `docs/` (Docusaurus) pro site — essa última decidida como "aos poucos", não
  bloqueia nada.

---

**Sessão 200 (2026-08-14): migração da doc pra `/docs` (Fumadocs) e decisão de sequenciamento —
doc primeiro, monetização continua em desenvolvimento mas sem lançamento ao vivo.**

- **Migração de `docs/` (Docusaurus) pro `site/frontend/docs`, começo do "aos poucos" citado no
  fim do v1 do `site/`.** Formato escolhido: **Fumadocs** (não Nextra), montado como rota `/docs`
  dentro do `site/frontend` já existente — MDX-based, integra oficialmente como docs num app
  Next.js App Router, Tailwind-nativo. Visual: tema padrão do Fumadocs com as fontes que já
  estavam no site (Geist) — decisão explícita de não recriar agora a paleta teal/cyan/Inter+Space
  Grotesk do Docusaurus antigo, já que o site ainda não tem design system próprio (refinamento
  visual fica pra depois). As 10 páginas de conteúdo (intro, quickstart, security, contracts,
  smart-account, sdk/{typescript,python,ruby,dart}) foram portadas com paridade total, incluindo
  tradução de `:::admonition:::` → `<Callout>`, `<Tabs>` do Docusaurus → `<Tabs>` do Fumadocs, e
  ordem do sidebar via `meta.json` (substitui `sidebar_position`/`_category_.json`). Busca ganha
  de graça (Fumadocs/Orama) — Docusaurus não tinha nenhuma configurada.
- Achado técnico verificado: os anchors de heading do Fumadocs batem byte-a-byte com os do
  Docusaurus (mesmo algoritmo de slug estilo github-slugger) — confirmado contra todos os links
  internos `/docs/...#anchor` que já existiam, nenhum quebrou. Não é garantia geral pra qualquer
  heading futuro, mas vale como precedente.
- Decisão técnica não prevista no plano original: o `RootProvider` do Fumadocs (tema/next-themes)
  e os dois imports de CSS (`fumadocs-ui/css/neutral.css` + `preset.css`) foram parar no
  `app/layout.tsx`/`globals.css` **raiz** (afetando `/` e `/dashboard` também), não escopados só a
  `/docs` — o preset do Fumadocs define `body { background-color; color }` via seletor global
  (`@layer base`), então uma segunda folha de CSS só-pra-docs entraria em conflito de cascata com
  o `globals.css` existente, e `next-themes` sempre mexe em `document.documentElement` (não dá pra
  escopar por subtree). Impacto visual medido é imperceptível (bg `#ffffff`→`hsl(0,0%,96%)`), já
  que o resto do site não tinha design system definido mesmo — registrado caso o dono do projeto
  note diferença visual no login/dashboard depois de definir um design system próprio.
- Fora de escopo, não migrado: landing page do Docusaurus (`docs/src/pages/index.tsx`) e
  `/donate` (usa `QRCodeSVG`, não é doc). O `docs/` antigo (Docusaurus, GitHub Pages) continua no
  ar — nenhum redirect/decommission feito, decisão de cutover fica pra depois.
- **Decisão de sequenciamento, pedida explicitamente pelo dono do projeto**: continuar
  desenvolvendo o Épico 2 (tier facilitado / monetização, ver P47 e a seção "Onboarding
  facilitado" acima) normalmente, mas **sem colocar no ar por um bom tempo** — fica pronto/testado
  porém não lançado/exposto publicamente. Ordem combinada: (1) doc primeiro — continuar
  migrando/melhorando `/docs`; (2) seguir usando GitHub normalmente como repositório; (3) só depois
  retomar o avanço da monetização, sabendo que o lançamento de fato demora. Nenhuma rota de
  billing deve ser exposta publicamente nem anunciada sem pedido explícito do dono do projeto.

**Sessão 200, continuação — identidade visual na doc Fumadocs + deploy estático no GitHub Pages,
mesma sessão.**

- **Decisão sobre escopo do deploy, perguntada explicitamente ao dono do projeto**: a doc agora
  mora dentro do mesmo app Next.js do `site/` (que também tem `/dashboard` e OAuth via Rails), mas
  GitHub Pages só serve estático — sem Rails, sem rota dinâmica. Decisão: **só a documentação vai
  pro Pages**, não o app inteiro. `/` (landing com botão de login) e `/dashboard` continuam de fora
  de qualquer deploy público por enquanto — consistente com a decisão de sequenciamento acima (nada
  de OAuth/billing exposto).
- **Identidade visual**: reaplicado o mesmo brand do Docusaurus antigo (`docs/src/css/custom.css`)
  — teal/cyan (`#0e7490` claro / `#4dd0e1` escuro) e Inter (corpo) + Space Grotesk (títulos) — via
  overrides de `--color-fd-*` (variáveis de tema do Fumadocs) em `app/globals.css`, usando `.dark`
  como seletor (não mais `@media (prefers-color-scheme)`) porque o `RootProvider` do Fumadocs já
  aplica tema via `next-themes` com `attribute: "class"` — confirmado lendo
  `node_modules/fumadocs-ui/dist/provider/base.js`. Fontes trocadas de Geist para Inter/Space
  Grotesk via `next/font/google` em `app/layout.tsx` (Geist Mono mantido pro código). Logo (o
  mesmo escudo-com-check do Docusaurus antigo) virou componente `components/logo.tsx` reusável,
  colorido via `currentColor`, usado no nav (`lib/layout.shared.tsx`) e como `app/icon.svg`
  (favicon, convenção do Next App Router). Validado visualmente com Playwright CLI
  (`npx playwright screenshot --color-scheme=light|dark`) — headings, cor de destaque e logo
  batendo com o brand em ambos os temas, nada quebrado.
- **Busca do Fumadocs trocada pra `staticGET`** (`fumadocs-core/search/server`, índice completo
  exportado como arquivo estático e buscado client-side via Orama) em vez do `GET` dinâmico
  original — necessário porque uma rota que lê query string por request não é compatível com
  `output: "export"`. Precisa de `export const dynamic = "force-static"` explícito na rota (Next
  não infere isso sozinho, erro de build claro quando falta). `RootProvider` ganhou
  `search={{ options: { type: "static" } }}` pra usar esse índice no cliente. Efeito colateral
  positivo: essa mudança vale também pro build normal (Docker) — não é código exclusivo do export.
- **`next.config.ts`**: `output: "export"` + `basePath` só ligam quando a env var
  `NEXT_BASE_PATH` está setada (usada só pelo workflow do GitHub Pages) — o build normal
  (`next start`/Docker) continua sem export, dinâmico, sem basePath. Testado local com uma cópia
  isolada de `site/frontend` (fora do worktree, `npm ci` limpo — testar com `node_modules`
  symlinkado quebra o Turbopack: "Symlink [project]/node_modules is invalid, it points out of the
  filesystem root") simulando exatamente o que o CI roda.
- **Workflow `deploy-docs.yml` reescrito**: builda `site/frontend` em vez de `docs/`, remove
  `app/page.tsx` e `app/dashboard` antes do build (routes que dependem do Rails, não fazem sentido
  num export estático), builda com `NEXT_BASE_PATH=/truthid` (mesmo `baseUrl` que o Docusaurus já
  usava — `masterlxz.github.io/truthid`, sem domínio próprio), e promove `out/docs/intro.html` a
  `out/index.html` no final (não existe página em `/docs` vazio — só `/docs/intro` — e todo link
  interno já é absoluto com o basePath, então copiar o HTML pra raiz funciona sem quebrar nada).
  Trigger trocado de `docs/**` pra `site/frontend/**` (a doc depende de vários arquivos
  compartilhados do app — layout, tema, `lib/source.ts` — não só do conteúdo MDX).
- **`docs/` (Docusaurus) mantido intocado por enquanto** — só para de ser o que é publicado no
  Pages (o workflow antigo apontava pra ele; o novo aponta pro Fumadocs). Dono do projeto confirmou
  explicitamente: vai ser removido quando não tiver mais utilidade nenhuma, não antes.
- **Achado de ambiente, não é bug de código**: `site/frontend/.next/dev/` tem arquivos donos de
  `root` (sobra de alguma execução anterior via Docker, que roda como root por padrão) —
  impede `next dev` local (erro de lockfile) mesmo depois de `rm -rf .next` (também barrado por
  permissão). `next build`/`next start` não tocam `.next/dev/` então não são afetados. Registrado
  caso o dono do projeto quera limpar com `sudo rm -rf site/frontend/.next` em algum momento; não
  bloqueia nada do que foi feito nesta sessão.
- Próximo passo, ainda não feito: conteúdo da doc. Dono do projeto pediu expansão grande — como o
  app funciona, objetivos, tudo sobre o software — bem além das 10 páginas atuais (paridade com o
  Docusaurus antigo, não cobertura completa do projeto).

**Sessão 200, continuação — expansão de conteúdo da doc (P48), mesma sessão.**

- **Metodologia**: 3 buscas de pesquisa em paralelo (Explore) leram o código-fonte de verdade
  (`contracts/src/*.sol`, `mobile/`, `desktop/`, `extension/`, `project/CONTEXT.md`) antes de
  qualquer linha de doc ser escrita — pedido explícito do dono do projeto ("cuidado com
  informações incorretas") tratado como restrição real, não figura de linguagem. Um agente de
  planejamento (Plan) desenhou a arquitetura de informação (lista de páginas, agrupamento,
  dono canônico de cada tópico) a partir dos achados, revisada e ajustada antes de escrever.
- **Achados reais nas 10 páginas antigas, todos corrigidos**: `VaultRegistry` (6º contrato,
  `0x07449b0c8dAE1252f59A5C0992D1413113a849B4` na Mainnet) nunca esteve documentado — `intro.mdx`/
  `contracts.mdx` diziam "quatro contratos"; claim de que os device keys ficam no "iOS Secure
  Enclave" é tecnicamente impossível (Secure Enclave só suporta P-256, os device keys são
  secp256k1 — corrigido pra "iOS Keychain", cifrado em repouso, sem isolamento de hardware);
  link quebrado pro `PROJECT_STATE.md` (arquivo não existe mais no repo); seção "Audit status"
  cobria só a revisão pré-mainnet, faltava o achado crítico de reentrância (C1) no
  `RecoveryManager.executeRecovery` de uma revisão posterior (Sessão 140, corrigido Sessão 150,
  deployado Sessão 197) — reescrita pra cobrir os dois; instruções de instalação do SDK Dart
  apontavam pro pub.dev, mas o pacote nunca foi publicado lá (confirmado ao vivo, 404) — trocado
  por instalação via git/path; claim de "todos os contratos são imutáveis" suavizado pra precisão
  real (sem proxy de upgrade, mas `TruthIDAccount`/`TruthIDAccountFactory` têm
  `updateRegistries` justamente pra permitir redeploys, dos quais já houve 4 no histórico do
  projeto); e o guardian default "3-de-5" documentado como se fosse padrão do contrato, quando na
  verdade não há default nenhum on-chain (achado ao verificar `configureGuardians` diretamente).
- **8 páginas novas**, cada uma com dono canônico do próprio tópico (as outras linkam em vez de
  duplicar): `concepts/vision.mdx` (objetivos, direto do PRD em `project/CONTEXT.md`, incluindo o
  princípio "nunca cobrar pelo que já é do usuário" citado só como filosofia, nunca como feature
  existente — decisão de sequenciamento da mesma sessão respeitada aqui também), `concepts/
  how-it-works.mdx` (walkthrough canônico do protocolo — criação de identidade, pareamento
  commit-reveal, formato exato de `AuthChallenge`/`AuthResponse`, sessões registradas pelo próprio
  Mobile via UserOp, não pelo SDK), `concepts/vault.mdx`, `concepts/recovery.mdx`, `concepts/
  cross-device-and-storage.mdx` (LAN+dead-drop em paralelo, não sequencial; migração Arweave;
  achado real não resolvido do onboarding de device novo com vault não republicado desde a
  migração, registrado como aviso explícito, não escondido), `apps/{desktop,mobile,extension}.mdx`,
  `structure.mdx` (mapa do repo, nota sobre o `docs/` legado continuar no repo até não ter mais
  utilidade — mesma decisão já registrada acima).
- **Precisão verificada, não assumida**: toda âncora interna (`#secao`) checada contra o HTML
  gerado pelo build antes de considerar pronto (Fumadocs não valida links internos no build —
  descoberto que um `grep` ingênuo pra checar isso precisa incluir `_` no regex, senão perde
  headings tipo `verify_session` silenciosamente). Trechos de código citados (assinaturas de
  função, constantes como `MAX_DEVICES=50`, `DEFAULT_DAILY_LIMIT=50`, magic bytes `TIDVLTB1` do
  backup) conferidos linha a linha contra o `.sol`/`.rs`/`.dart` real, não reconstituídos de
  memória da pesquisa.
- `npm run build`/`npm run lint` limpos; validado visualmente via Playwright CLI (`next start`,
  não `next dev` — mesmo motivo do achado de ambiente da sessão anterior) contra 3 páginas
  representativas (`contracts`, `concepts/how-it-works`, `apps/desktop`) — sidebar com os grupos
  novos ("Concepts", "Client Apps"), tabelas, `<Callout>` e navegação prev/next todos renderizando
  certo.
- Fecha P48 por completo. Nenhuma decisão de arquitetura nova ficou pendente — próximo trabalho
  de doc, se houver, é lapidação/expansão incremental, não um pilar em falta.

---

### Interface e identidade visual (UI/UX)

**Quando**: após Fase 4 (Mobile App completo) — pode ser uma Fase 5.5 intercalada com SDKs, ou uma Fase 8 dedicada pós-lançamento. A definir pelo dono do projeto.

**O que precisa ser feito**:
- Definir identidade visual: logo, paleta de cores, tipografia
- Aplicar no app mobile (Flutter): temas, ícones, animações, onboarding
- Aplicar no desktop (Tauri/React): mesma linguagem visual
- Revisar todos os fluxos (criar identidade, adicionar device, aprovar login, recovery) pensando em UX
- Telas de erro e estados vazios com mensagens amigáveis
- Possivelmente: dark mode

**Estado atual**: toda a UI é funcional mas usa Material Design padrão (indigo genérico, sem personalidade). Nenhuma tela tem polish de produto final.
