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
