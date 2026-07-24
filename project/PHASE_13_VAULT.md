### Fase 13 — TruthID Vault (gerenciador de senhas)

**O que é**: módulo opcional de gerenciamento de senhas (estilo Bitwarden), construído sobre a mesma identidade on-chain do TruthID core. Não é um produto separado — é uma extensão que reaproveita o `DeviceRegistry` existente como camada de autorização.

**Nota de escopo**: o `CONTEXT.md` (PRD) listava "Password manager" em *Non Goals*. Decisão consciente de expandir o escopo — não de ignorar o documento. O `CONTEXT.md` foi atualizado para refletir essa expansão (ver seção "Non Goals").

**Motivação**:
1. Bridge entre "mundo de hoje, cheio de senha" e o objetivo final do TruthID (eliminar senha por completo) — enquanto sites de terceiros não adotam login sem senha, o usuário ainda precisa gerenciar senhas.
2. Tem valor de uso pessoal standalone mesmo sem nenhuma adoção externa do protocolo de auth — dogfooding real do `DeviceRegistry`/Keystore que já existe.
3. Reaproveita a mesma identidade, os mesmos dispositivos confiáveis e a mesma filosofia de segurança (chave privada nunca sai do device) — não é um produto do zero.

**Decisão de escopo de código**: Vault deve ser um módulo separado (pasta própria, ex. `vault/`), nunca misturado ao código do core de autenticação. Deve poder ser abandonado ou cindido em outro projeto sem afetar o TruthID auth.

---

#### O que vai on-chain vs. o que não vai

| Dado | Vai on-chain? | Onde fica |
|---|---|---|
| Conteúdo do vault (senhas, notas) | **Nunca** | Local no device, cifrado |
| Hash/CID da versão atual do vault | Sim | Novo contrato (`VaultRegistry`) |
| Chave de decriptação do vault | **Nunca** | Derivada localmente, nunca persistida em claro |
| Lista de devices autorizados a decifrar | Sim (já existe) | `DeviceRegistry` |

---

#### Arquitetura de criptografia

```
Device autoriza via assinatura (mesma chave do Keystore/Secure Enclave/TPM
                                 já usada pro login)
            |
            v
HKDF deriva chave de criptografia do vault a partir da chave privada do device
            |
            v
Chave decifra o vault local (AES-256-GCM ou XChaCha20-Poly1305)
            |
            v
Vault em claro, em memória, nunca persistido sem cifrar
```

**Sem master password.** A chave vem da posse do device (já provada on-chain), não de algo que o usuário "sabe".

**Múltiplos devices**: cada device tem sua própria chave derivada. O vault é cifrado com uma chave simétrica própria do vault (não derivada de nenhum device específico); essa chave é compartilhada entre os devices do usuário apenas no momento do pareamento, pelo mesmo canal já usado para registrar um novo Device — nunca via pin/chain.

---

#### Hierarquia de confiança: Devices vs. sessões de extensão

```
Desktop (root/controller)
   │
   ├── controla quais Devices são confiáveis      (já existe: DeviceRegistry)
   ├── controla TODAS as senhas (CRUD completo no vault)
   ├── pode revogar qualquer Device, em qualquer momento
   ├── concede/revoga permissão de escrita por Device (granular, não binário)
   │
   └── Mobile  (Device confiável, registrado on-chain)
          │
          ├── lê o vault (subconjunto ou completo, depende de permissão)
          ├── pode ESCREVER no vault apenas se o Desktop autorizou
          │     (permissão explícita — não decorre automaticamente de "ser
          │     um device confiável")
          │
          └── Extensão de navegador  (sessão efêmera — NÃO é um Device)
                 │
                 ├── nasce de um QR scan feito pelo Mobile
                 ├── recebe só o subconjunto de senhas do perfil ativo
                 │     no momento do scan (ex: "Trabalho")
                 ├── vive só durante a sessão (fecha aba/browser = some)
                 ├── nunca persiste nada em disco
                 └── nunca é registrada on-chain
```

**Por que a extensão NÃO é um "Device" no `DeviceRegistry`**: um Device confiável carrega permissão estrutural persistente. A extensão deve ter exatamente o oposto — confiança mínima, vida curta, escopo estreito (só o que o Mobile decidiu mostrar). Tratá-la como Device daria a ela, por construção, mais poder do que o desenho pretende. Além disso, sessões efêmeras não precisam de gas para existir — registrá-las on-chain seria custo desnecessário para algo que já nasce temporário.

**Permissão granular por Device**: `canWriteVault` (bool, ou enum `read` / `read_write`) por Device, configurável apenas pelo Desktop. Decisão de implementação aberta: campo on-chain (no `DeviceRegistry` ou no novo `VaultRegistry`) vs. estado local controlado só pelo Desktop — como não há terceiros desconfiados, local é provavelmente suficiente e mais barato.

**Perfis (nomeados pelo usuário — implementado na Sessão 97)**: metadado local de cada entrada do vault (tag), não algo on-chain. O Mobile decide, no momento do scan do QR da extensão, qual perfil está ativo e filtra o payload antes de enviar. **v1 não usa mais perfis fixos pré-definidos** (`Trabalho`/`Casa`/`Pessoal` hardcoded) — o usuário cria/nomeia perfis livremente e marca cada senha em quantos perfis quiser. Schema: novo campo `profile_names: Vec<String>`/`List<String>` no nível do `Vault`/`_VaultData` (não por-entrada), com backfill automático a partir da união das tags já em uso em vaults antigos. Implementado nos dois lados: Desktop (`Vault::add_profile/rename_profile/delete_profile` em `vault.rs`, seção "Gerenciar perfis" em `VaultManagement.tsx`) e Mobile (métodos espelhados em `VaultRepository`, tela `vault_profiles_screen.dart`). Renomear/apagar um perfil propaga em cascata pras entradas que o usam. `kVaultProfiles` (mobile) e `PROFILES` (desktop) foram removidos.

**Revogação em cascata**: revogar um Device (ex: Mobile perdido) via Desktop precisa invalidar em cascata qualquer sessão de extensão que aquele Device tenha aberto. O Desktop precisa manter localmente o registro de qual Device originou qual sessão ativa, para conseguir notificar/expirar essas sessões no momento da revogação.

**Fluxo da sessão de extensão**:
1. Usuário abre a extensão no browser → ela exibe um QR code (challenge efêmero, mesmo padrão do QR de login do TruthID core).
2. Mobile escaneia, usuário escolhe/confirma o perfil ativo.
3. Mobile filtra o vault local pelo perfil escolhido e envia o subconjunto direto pra extensão via canal P2P efêmero (ex: WebRTC).
4. Extensão guarda esse subconjunto **em memória apenas**, pelo tempo da sessão do browser. Faz autofill nos campos da página.
5. Fechar a aba/browser, ou expirar um timeout configurável, destrói a sessão. Reabrir exige novo scan.

**Confirmado**: o canal P2P efêmero (Mobile→Extensão) é mantido — entrega um payload já filtrado, não sincroniza estado de vault entre devices. É o mesmo padrão do canal P2P de login via QR já em produção. A remoção de P2P aplica-se **apenas** ao mecanismo de sincronizar o conteúdo do vault inteiro entre Desktop e Mobile (esse passou a ser via pin).

**Nota de implementação**: como não há mais P2P nem handshake direto entre devices para sincronizar o conteúdo do vault, a complexidade de implementação cai bastante — não é preciso WebRTC, descoberta de peer, nem re-criptografia por device de destino para o fluxo Desktop/Mobile de sync. Isso é diferente do canal P2P efêmero do login via QR (já em produção) e do fluxo Mobile→Extensão (ambos mantidos, entregam payload já pronto/filtrado).

#### Transporte Mobile→Extensão — desenho fechado na Sessão 97 (2026-07-13)

O parágrafo acima deixava o transporte como "ex: WebRTC", nunca decidido de verdade. Investigação na Sessão 97 confirmou: não existe WebRTC, sinalização nem scaffold de extensão em lugar nenhum do repo — 13.9 é greenfield puro.

**Três rotas propostas e rejeitadas pelo dono do projeto**: (1) ponte via Desktop usando Native Messaging + servidor HTTP local na LAN — rejeitada porque exigiria o Desktop instalado no computador onde a extensão roda, e o caso de uso real inclui "computador aleatório" sem o Desktop; (2) WebRTC com handshake por 2 QR codes (extensão gera oferta, mostra QR; mobile responde, mostra 2º QR; extensão escaneia de volta) — rejeitada porque a extensão nunca deve precisar de câmera; (3) servidor de sinalização próprio (ex: Cloudflare Worker só pra troca de SDP/ICE, sem o payload do vault passar por ele) — rejeitada por introduzir infraestrutura operada por nós, contra o princípio "sem relay" que o projeto mantém desde o início (ver README).

**Restrição física por trás da rejeição das 3**: uma extensão de navegador (Chrome/Firefox) nunca consegue **escutar** conexão de entrada — só faz requisição de saída. É limite de sandbox da plataforma, não escolha de design. Isso elimina qualquer desenho onde o Mobile "empurra" dados direto pra extensão sem ela primeiro conseguir ser alcançada por algum meio.

**Dois transportes desenhados, mesma prioridade — tentados em sequência, não mutuamente exclusivos**:

1. **Descoberta automática na LAN** (tentado primeiro — mais simples e rápido):
   1. Extensão gera um par de chaves efêmero (mesmo padrão ECIES já usado na entrega da vault key no pareamento, Sessão 92) + um `sessionId` aleatório. Mostra um QR: `{action: 'truthid-vault-session', sessionId, ephemeralPubKey}`.
   2. Mobile escaneia (reaproveita `VaultSessionScreen`, que já faz esse scan hoje e termina num estado "not available yet" explícito — esse é o ponto de plugue da 13.9). Usuário escolhe o perfil ativo (`kVaultProfiles`, já existe).
   3. Mobile filtra o vault local (`VaultSyncService`/`VaultRepository.listEntries()`, já existem) pelo perfil, cifra o subconjunto via ECIES pra `ephemeralPubKey` — mobile hoje só *decifra* ECIES (chave do device no pareamento); cifrar é capacidade nova, espelhando o que o Desktop já faz em `lib.rs` na direção oposta.
   4. Mobile sobe um servidor HTTP local efêmero (porta aleatória, bind em `0.0.0.0`) servindo o payload cifrado em `/session/<sessionId>`, só por alguns minutos ou até ser servido uma vez.
   5. Extensão varre a sub-rede local (descobre sua própria faixa via WebRTC local ICE candidate gathering — não precisa de STUN pra isso, só descobrir o próprio IP local — e tenta `192.168.x.1..254:<portas comuns>/session/<sessionId>` em paralelo) até achar a resposta.
   6. Extensão decifra em memória com a chave privada efêmera, guarda só em RAM, morre ao fechar a aba/browser ou por timeout.
   - **Trade-offs**: só funciona na mesma rede Wi-Fi/LAN (não funciona com o celular no 4G, nem em wifi de convidado com isolamento de cliente); a varredura de sub-rede pode disparar alerta de firewall/antivírus em alguns computadores.

2. **Dead-drop via IPFS/IPNS público** (fallback quando a LAN falha — funciona em qualquer rede):
   1. Mesmo QR da rota LAN — não precisa de esquema diferente; os dois transportes competem pelo mesmo payload de sessão.
   2. Mobile cifra o subconjunto via ECIES pra `ephemeralPubKey` — payload cifrado idêntico ao da rota LAN, só muda o transporte.
   3. Mobile deriva um par de chaves IPNS a partir do `sessionId` (determinístico, sem trocar nada a mais com a extensão) e publica o blob cifrado nesse nome IPNS via um dos provedores de pin já configurados. Capacidade nova pro mobile: hoje só o Desktop publica em IPFS (`ipfs.rs`); mobile só lê, via `IpfsGatewayClient`. Precisa também de UI no mobile pra configurar provedor(es) de pin — hoje só existe no Desktop (`VaultSettings.tsx`/13.6).
   4. Extensão calcula o mesmo nome IPNS localmente (deriva de `ephemeralPubKey`/`sessionId` que ela mesma gerou) e faz polling num gateway público (`ipfs.io`, `dweb.link` — mesmo padrão de fallback que `IpfsGatewayClient` já usa no mobile) a cada poucos segundos, timeout generoso (~1–2 min).
   5. Extensão decifra em memória com a chave privada efêmera, mesmo destino final da rota LAN.
   - **Trade-offs**: propagação de IPNS é lenta e variável (segundos a ~1 minuto, às vezes mais). Publish de IPNS via a API REST simples da spec PSA (Pinata/Filebase/4EVERLAND) tem suporte incerto — a spec é sobre pinning de conteúdo, não sobre publicar registro IPNS mutável; funciona com confiança só via Kubo self-hosted (que expõe `ipfs name publish` de verdade). Se o usuário só tiver provedores PSA configurados (sem Kubo), essa rota pode não estar disponível — vai precisar de UI honesta avisando isso, não fingir que sempre funciona.

**Pendência em aberto gerada por essa escolha**: o parágrafo de "Revogação em cascata" acima assumia que o Desktop manteria localmente o registro de qual Device abriu qual sessão de extensão, porque estaria no meio do transporte. Com o Desktop fora do caminho nos dois transportes desenhados, essa premissa não vale mais tal como estava escrita — não há mais um ponto natural que veja a sessão sendo aberta em tempo real. Resposta provável: aceitar TTL curto (sessão morre sozinha em minutos, sem canal de revogação ativa) como o próprio modelo de segurança, em vez de construir infraestrutura de revogação ativa — mas é decisão de produto a confirmar com o dono do projeto quando a 13.9 for implementada de fato, não algo a decidir sozinho agora.

#### 13.9, fatia 1 (só transporte LAN) — implementada na Sessão 99 (2026-07-14)

Escopo confirmado com o dono do projeto antes de implementar: só o transporte LAN desenhado acima (o dead-drop IPFS/IPNS fica pra uma fatia 2, não implementada); revogação confirmada como **TTL curto (3 min), sem canal de revogação ativa** — resolve a pendência em aberto acima. Permissão ampla da extensão (`http://*/*`, exigida pelo fetch-sweep já que manifests não têm sintaxe CIDR) pedida em runtime (`optional_host_permissions` + `chrome.permissions.request()`), não no install. Firefox suportado nesta fatia via fallback manual de IP (não tem `chrome.system.network`).

**Extensão nova, `extension/` (sibling de `desktop/`/`mobile/`), greenfield via WXT** (Vite-native, mesma família de bundler do `desktop/`; template vanilla-ts, sem framework de UI — superfície pequena e é código que manipula segredos, menos dependências é melhor). `manifestVersion: 3` forçado também no Firefox (WXT usa MV2 lá por padrão) — no MV2 o `optional_host_permissions` não é gerado no manifest, o que quebraria tanto a descoberta automática quanto o fallback manual (os dois dependem de `fetch()` pra um IP de LAN, atrás da mesma permissão). `system.network` entra no manifest só em Chrome/Edge via hook `build:manifestGenerated` do WXT — ausente do union type de permissões do `@types/chrome`, é real mesmo assim (documentada, só sem tipagem completa nesse pacote); tipado localmente via intersection (`ChromeWithSystemNetwork` em `lanDiscovery.ts`) em vez de brigar com merge de namespace ambiente.

**Estrutura**: `src/crypto/ecies.ts` (decrypt/encrypt ECIES via `@noble/curves`+Web Crypto), `src/session/{qrPayload,sessionState,lanDiscovery}.ts`, `src/storage/sessionStore.ts` (`chrome.storage.session` — não variável de módulo, service workers MV3 são suspensos e perdem isso), `src/ui/{renderQr,renderEntries}.ts`, `entrypoints/{background.ts,popup/}`. `qrcode`, `@noble/curves`, `@noble/hashes` como deps de runtime (`@noble/*` já presentes transitivamente via `viem` no `desktop/`, não é dependência nova pro repo).

**Schema do QR v1**: `{action: 'truthid-vault-session', v: 1, sessionId, ephemeralPubKey, expiresAt}`. `sessionId` (16 bytes aleatórios) funciona como path HTTP *e* bearer token — sem campo separado de "discoveryToken". `expiresAt` é timestamp absoluto (unix ms), evita ambiguidade de clock-skew entre os dois aparelhos.

**Descoberta LAN** (`extension/src/session/lanDiscovery.ts`): rejeitado o truque de WebRTC/ICE candidates especulado no desenho original da Sessão 97 (item 1.5 acima) — navegadores modernos ofuscam host candidates atrás de nomes mDNS `.local` por padrão, então esse truque retornaria lixo silenciosamente em builds atuais, não IPs reais. Substituído por `chrome.system.network.getNetworkInterfaces()` (API real, só Chrome/Edge) + fetch-sweep no /24 correspondente. Lista de portas é fixa e pequena (`[47850..47854]`), não porta aleatória como o desenho original especulava (resolve uma inconsistência do texto da Sessão 97, que falava em "porta aleatória" no mobile mas "portas comuns" na extensão — dois textos incompatíveis) — espelhada como constante nos dois lados (`extension/src/session/lanDiscovery.ts` ↔ `mobile/lib/services/vault_lan_server_service.dart`, comentário cruzado). Fallback manual de IP (campo de texto na popup) sempre disponível — Firefox sempre usa esse caminho, Chrome também se o sweep automático não achar nada.

**Mobile**: `mobile/lib/services/ecies_service.dart` novo (`encrypt`/`decrypt` genéricos, mirror de `encrypt_bytes_for_device` do Rust — `encrypt()` é capacidade nova, mobile nunca tinha precisado cifrar pra outra parte antes). `VaultKeyService.decryptVaultKeyFromPairing` refatorado pra delegar em `EciesService.decrypt` (comportamento idêntico, elimina duplicação). `mobile/lib/services/vault_lan_server_service.dart` novo (`dart:io HttpServer` cru, sem `shelf` — só 1 endpoint autenticado, não justifica dependência de roteamento; serve exatamente 1 request em `/session/<sessionId>`, 404 uniforme pra qualquer outro path/sessionId, fecha após 1 request ou no timeout do TTL). `vault_session_screen.dart`: estado stub `unavailable` (13.8) substituído por `sending`/`sent`/`timeout`/`error` reais, com envio de verdade (`_sendToExtension`) e IP local do celular mostrado na tela (fallback manual do lado extensão). iOS: `NSLocalNetworkUsageDescription` novo no `Info.plist` — iOS 14+ Local Network Privacy dispara diálogo do sistema no primeiro accept de conexão inbound; mitigação (disparar um acesso local-network inofensivo cedo, em `_loadProfiles()`, antes da janela sensível ao TTL) aplicada mas **não validada em hardware real** (pendência).

**Achado real durante a implementação, não hipotético**: ao escrever o primeiro teste de round-trip de verdade do lado Dart (`EciesService.encrypt` seguido de `EciesService.decrypt`), a decifra falhou com erro de MAC. Causa: o padrão `SecretBox(ciphertext, mac: Mac.empty)` com o tag do AES-GCM já concatenado ao ciphertext — usado desde sempre em `VaultKeyService.decryptVaultKeyFromPairing`, o código que a Sessão 92 corrigiu (SHA-256 do segredo ECDH) e considerou validado — **nunca decifra de verdade**: o pacote `cryptography` recalcula o MAC sobre `secretBox.cipherText` inteiro e compara contra `secretBox.mac`; passando `Mac.empty` (0 bytes) essa comparação falha sempre. A Sessão 92 nunca pegou isso porque o teste Rust de lá reimplementa o decrypt em Rust puro, sem nunca chamar o código Dart real — e a validação em hardware daquela sessão nunca chegou a confirmar a decifra ao vivo no celular (ficou registrado como pendência, não como sucesso). Ou seja: **a entrega de vault key via pareamento (ECIES, Sessão 76/92) provavelmente nunca funcionou de ponta a ponta em nenhum dispositivo real, silenciosamente, até esta sessão.** Corrigido usando `SecretBox.fromConcatenation(nonceLength: 12, macLength: 16)` — a API certa do pacote pra esse formato de blob; não muda o formato do blob em si (compatível com o que o Rust já produz e o que está gravado on-chain), só a forma como o Dart o interpreta. `VaultKeyService.decryptVaultKeyFromPairing` herda o fix automaticamente (agora delega em `EciesService.decrypt`). **Pendência nova**: validar a decifra da vault key de pareamento em hardware real de novo (a mesma validação que a Sessão 90/92 nunca fechou) — agora com razão a mais pra acreditar que vai funcionar, mas ainda não confirmado ao vivo.

**Vetor cruzado fixo** (gerado uma vez rodando o `EciesService.encrypt` real do Dart, via `docker compose run flutter dart run`, contra uma chave privada de teste determinística): mesmo trio `{recipientPrivateKeyHex, blobBase64, expectedPlaintextHex}` usado em `desktop/src-tauri/src/lib.rs::dart_produced_blob_decrypts_correctly` (novo teste Rust), `mobile/test/services/ecies_service_test.dart` e `extension/src/crypto/ecies.test.ts` — os três decifram o mesmo blob e conferem o mesmo plaintext, provando interoperabilidade determinística entre Rust/Dart/JS sem precisar de dois dispositivos reais. Risco de interop documentado e testado no lado JS: `@noble/curves`' `getSharedSecret` retorna o ponto EC comprimido inteiro (prefixo `0x02`/`0x03` + 32 bytes de X) — precisa descartar o prefixo antes do SHA-256, senão a chave AES diverge silenciosamente (mesma classe dos bugs já documentados neste projeto).

**Testes**: `cargo test --lib` 27/27 (era 26 + o novo `dart_produced_blob_decrypts_correctly`). `flutter test` 166/166 (era 155 + 11 novos entre `ecies_service_test.dart` e `vault_session_screen_test.dart`), `flutter analyze` limpo (mesmos 8 avisos pré-existentes, nenhum novo). Extensão: `tsc --noEmit` limpo, `vitest run` 10/10 (`ecies.test.ts` + `lanDiscovery.test.ts`), `wxt build` testado pra `chrome-mv3` e `firefox-mv3` (manifests conferidos manualmente).

**Pendências**:
- ~~Fatia 2 (dead-drop IPFS/IPNS) — não iniciada~~ — **fatia 2a (só o lado Mobile) implementada na Sessão 100**, ver abaixo. Fatia 2b (extensão consome) segue pendente.
- Validação manual E2E de verdade: extensão carregada unpacked + celular real na mesma Wi-Fi, scan → perfil → envio → confirmação das entradas na popup. Nada disso rodou contra hardware real ainda.
- Diálogo de Local Network Privacy do iOS — mitigação de timing aplicada, não validada em device real.
- Revalidar a decifra da vault key de pareamento (ECIES, Sessão 76/92) em hardware real, à luz do bug de `Mac.empty` achado e corrigido nesta sessão.
- "Extensão pedindo alteração de senha, aprovada só pelo Device" (brainstorm da Sessão 97) — continua só brainstorm, não decidido.

#### 13.9, fatia 2a (Mobile publica o dead-drop IPFS/IPNS) — implementada na Sessão 100 (2026-07-14)

Escopo negociado com o dono do projeto antes de implementar (via `/plan`, mesmo padrão da fatia 1): só o lado **Mobile** nesta fatia — derivar a chave IPNS, publicar via Kubo, provar que a derivação bate contra um Kubo real. O consumo pela extensão (poll/resolve + UI) fica pra uma fatia 2b futura. Gatilho: o Mobile dispara o publish IPNS **em paralelo, sempre**, junto com `VaultLanServerService.serveOnce()` — não como fallback sequencial (esconde a latência de propagação do IPNS, que pode levar até ~1min, atrás do tempo que o usuário já ia esperar de qualquer forma).

**Erro real pego antes de escrever código**: uma revisão técnica (agente `Plan`) encontrou que o desenho original usava `format=libp2p-key` no `POST /api/v0/key/import` do Kubo — esse valor não existe (`libp2p-key` é o *codec* CIDv1 0x72, não um formato de import de chave). O valor certo é `libp2p-protobuf-cleartext` (que já é o default). Confirmado contra a doc oficial do Kubo antes de qualquer implementação.

**Derivação determinística do nome IPNS** (`mobile/lib/services/ipns_key_service.dart`, matemática pura, sem I/O): `sessionId` (16 bytes, hex, já no QR) → `HKDF-SHA256` → seed Ed25519 → par de chaves via `package:cryptography`'s `Ed25519().newKeyPairFromSeed()` → protobuf `PrivateKey`/`PublicKey` do libp2p (`crypto.proto`, hand-rolled — só 2 campos fixos, não precisa de encoder protobuf genérico) → multihash "identity" (peer-id de Ed25519 sempre cabe no limite de 42 bytes) → CIDv1 codec `libp2p-key` (0x72) → multibase base36-lower via `BigInt` (formato `k51...`). HKDF promovido de `_hkdfSha256` (antes privado em `vault_key_service.dart`) pra `mobile/lib/services/hkdf_util.dart` compartilhado — elimina duplicação, `VaultKeyService` passou a usar a versão pública.

**Validado contra um Kubo 0.42.0 real, não só round-trip interno** (mesmo padrão que pegou o bug do ECIES na Sessão 92 — "bate por acaso só isolado, nunca testado ponta-a-ponta" já mordeu o projeto 2x): subiu um daemon Kubo isolado (`IPFS_PATH` temporário, API `127.0.0.1:5501`, offline), gerou a chave via um probe Dart temporário (rodado no Docker do Mobile), importou de verdade via `curl -X POST .../api/v0/key/import?format=libp2p-protobuf-cleartext`, e o `Id` que o Kubo devolveu (`k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh`) bateu **byte-a-byte** com o `computeIpnsName` calculado no Dart. Esse valor virou o fixture travado em `mobile/test/services/ipns_key_service_test.dart`. Também confirmado via curl: o erro exato do Kubo em reimport de chave já existente (`"key with name '...' already exists"`) — `IpfsPinClient.kuboImportKey` trata isso como sucesso (chave determinística, se já existe é a mesma).

**Publish no Kubo** (`mobile/lib/services/ipfs_pin_client.dart`, novos `kuboImportKey`/`kuboPublishName`/`kuboRemoveKey` + orquestração `publishDeadDrop`): `POST /api/v0/add` (reaproveita `_kuboAdd` já existente) → `key/import` (idempotente) → `POST /api/v0/name/publish?...&lifetime=5m&ipns-base=base36` → `POST /api/v0/key/rm` (limpeza best-effort — o registro assinado já propagou, não precisa manter a chave local). Só roda contra provider `kind == 'kubo'` (PSA não tem garantia de suportar publish de IPNS, ver Sessão 97); usa só o primeiro configurado, sem redundância multi-provider nesta fatia (simplificação deliberada).

**Plugado em `vault_session_screen.dart`**: `_sendToExtension()` dispara `_lanServer.serveOnce()` e `_publishDeadDrop()` em paralelo, com erro do dead-drop isolado do try/catch principal (uma falha do publish IPNS — ex: Kubo fora do ar — não pode mascarar um LAN que funcionou). UI ganhou uma linha discreta de status na tela "Sent" (publicado / indisponível) — sem redesenhar o fluxo, já que ainda não há consumidor do lado extensão.

**Testes**: `mobile/test/services/ipns_key_service_test.dart` novo (8 testes, incluindo o fixture validado contra Kubo real); `vault_session_screen_test.dart` ganhou mock de `PinningProviderService` (retorna `[]` por padrão — o dead-drop cai no early-return silencioso do `publishDeadDrop`, sem I/O real, evitando o mesmo problema de teste travado que a Sessão 98 já tinha resolvido pra outras telas do Vault). `flutter test` 174/174, `flutter analyze` limpo (mesmos 8 avisos pré-existentes, nenhum novo).

**Pendências**:
- ~~Fatia 2b (extensão consome o dead-drop)~~ — **implementada na Sessão 101**, ver abaixo. É a última etapa da 13.9 (e da Fase 13).
- Publish HTTP real (`kuboImportKey`/`kuboPublishName`/`kuboRemoveKey`) validado via `curl` contra Kubo real nesta sessão, mas não exercitado via `flutter test`/hardware real ainda (só a derivação matemática tem teste automatizado).

#### 13.9, fatia 2b (extensão consome o dead-drop) — implementada na Sessão 101 (2026-07-14) — fecha a 13.9 e a Fase 13

Duas decisões de arquitetura tomadas com o dono do projeto antes de implementar (via `/plan`): (1) **o polling roda no background service worker** (`chrome.alarms`), não na popup — a popup fecha ao perder foco e a propagação de IPNS pode levar até ~1-2min, então rodar só na popup (como o `sweepLan` da fatia 1) exigiria o usuário parado olhando a popup o tempo todo, anulando boa parte do valor do dead-drop; (2) **o polling começa automaticamente assim que o QR aparece**, sem esperar clique em "Find" — mesma lógica do "sempre em paralelo" já travada no Mobile na fatia 2a.

**Derivação em TS** (`extension/src/session/ipnsKey.ts`, mirror da metade pública de `ipns_key_service.dart` — a extensão nunca guarda segredo, só recalcula onde resolver): `HKDF-SHA256` (`@noble/hashes/hkdf`) → seed Ed25519 → `ed25519.getPublicKey(seed)` (`@noble/curves`, RFC 8032, mesma implementação que `package:cryptography` no Dart) → protobuf `PublicKey` do libp2p (hand-rolled, só 4 bytes de header) → `multiformats@14.0.4` (pacote oficial Protocol Labs, novo na extensão) faz o resto: multihash identity, CIDv1 codec `libp2p-key`, multibase base36 — ao contrário do Dart, aqui existe pacote maduro, sem precisar hand-roll nada além do protobuf. **Vetor cruzado reaproveitado da fatia 2a bateu de primeira**: mesmo par `sessionIdHex`/`expectedIpnsName` (`k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh`) validado contra Kubo real na Sessão 100 — fecha o loop de interoperabilidade Mobile↔Kubo↔Extensão nas 3 linguagens (Dart/Rust já provado antes, agora TS também).

**Polling** (`extension/src/session/deadDropPolling.ts`, testável via `fetchGateway` injetado, mesmo padrão de `lanDiscovery.ts` — sem mock de `fetch` global): `tryFetchDeadDrop(sessionId)` busca `https://ipfs.io/ipns/<name>?cachebust=<ts>` com `cache: 'no-store'`. Achado ao vivo: o gateway responde **500, não 404**, quando o nome ainda não propagou — o polling trata qualquer não-200 como "ainda não", nunca lança. Achado que **contraria a hipótese inicial**: o gateway já manda `Access-Control-Allow-Origin: *`, então o fetch funciona **sem nenhuma `host_permission` nova** no manifest (diferente do LAN, onde o servidor efêmero do Mobile não manda CORS e por isso precisa de `http://*/*` via `chrome.permissions.request()`).

**`entrypoints/background.ts`** ganhou um segundo braço no listener de `chrome.alarms` (além do `SESSION_EXPIRY_ALARM` já existente): mensagem `START_DEAD_DROP_POLL` (mandada pela popup ao criar sessão) dispara uma tentativa imediata + agenda `chrome.alarms.create(..., {delayInMinutes: 1, periodInMinutes: 1})` — período mínimo prático de alarmes em produção é ~1min, mas como a própria propagação de IPNS já opera nessa escala, não é limitação real (~3 tentativas dentro do TTL de 3min da sessão). Cada tick relê a sessão atual do storage (só existe 1 por vez — criar sessão nova "cancela" o polling da anterior sem lógica extra), decifra se achar algo, salva `status: 'received'`, e limpa o alarme. Notifica a popup via `chrome.runtime.sendMessage` (`DEAD_DROP_RESOLVED`) se estiver aberta — best-effort, não necessário pra correção: `init()` na popup já mostra as entradas do storage na próxima abertura de qualquer jeito.

**`entrypoints/popup/main.ts`**: `handleBlob(blobBase64)` virou wrapper fino de `handleBlobBytes(Uint8Array)` (LAN chega como JSON `{blob: base64}`, dead-drop chega como bytes crus do gateway — mesmo blob ECIES sem envelope nos dois casos, confirmado lendo `vault_session_screen.dart`). Novo listener de `DEAD_DROP_RESOLVED` pra atualizar a UI ao vivo se a popup estiver aberta. Dedupe pequeno: `hexToBytes`/`bytesToHex` (antes duplicados em `ecies.ts` e `main.ts`) extraídos pra `extension/src/util/bytes.ts` — o background precisaria de uma terceira cópia.

**Testes**: `ipnsKey.test.ts` (4, vetor cruzado) + `deadDropPolling.test.ts` (4, fake `fetchGateway`) novos — `vitest run` 18/18 (era 10). `tsc --noEmit` limpo. `wxt build` validado pra `chrome-mv3` e `firefox-mv3` — manifest confirma que nenhuma `host_permission` nova foi adicionada (só `storage`/`alarms`/`system.network` + `optional_host_permissions: http://*/*`, igual antes).

**Pendências finais da Fase 13**:
- Validação manual E2E completa (extensão + celular real, LAN e dead-drop) — nunca rodou contra hardware real, é a única coisa que falta pra fechar a Fase 13 de verdade.
- Revalidar a decifra da vault key de pareamento (ECIES, Sessão 76/92) em hardware real.
- Diálogo de Local Network Privacy do iOS — não validado em device real.
- "Extensão pedindo alteração de senha, aprovada só pelo Device" (brainstorm da Sessão 97) — continua só brainstorm.

#### Mobile ganha escrita completa no Vault — implementado na Sessão 97

Até então (13.8) o Mobile era somente-leitura pro Vault por design — só o Desktop criava/editava entradas e perfis. O dono do projeto pediu paridade real: Mobile também cria/edita senhas e gerencia perfis, e publica as próprias mudanças (pin IPFS + `VaultRegistry.updateVault` on-chain), sem depender do Desktop.

**Investigação que destravou o trabalho**: `SessionCreator._executeViaUserOp` (Fase 14) já permitia ao Mobile assinar e enviar qualquer UserOperation genérica com a device key local (sem Ledger) — usado hoje por `createSession`/`revokeSession`/`withdraw`. `VaultRegistry` não está bloqueado pra devices em `TruthIDAccount.sol` (só `DeviceRegistry`/`IdentityRegistry`/`RecoveryManager` estão em `blockedForDevices`), e o próprio Desktop já roteia `updateVault` pelo mesmo padrão `TruthIDAccount.execute(...)` (débito #33/Sessão 78). Ou seja: nada de novo era necessário no caminho de assinatura — só faltava (1) UI e (2) a capacidade de pin IPFS, que o Mobile nunca teve (só lê via `IpfsGatewayClient`, nunca fez upload).

**Decisão de arquitetura tomada nesta sessão**: `canWriteVault` (antes um arquivo local só no Desktop, `~/.truthid/vault_permissions.json`, nunca checado por ninguém nem pelo contrato) foi movido pra dentro do próprio blob sincronizado do vault (`device_permissions: Vec<DeviceVaultPermission>` no `Vault`/`_VaultData`, mesmo padrão do `profile_names`), com backfill automático do arquivo legado na migração. Isso permite o Mobile ler sua própria permissão antes de oferecer a UI de escrita — continua sendo só trava de UX (o contrato não impõe nada, mesma razão já documentada na 13.7: não há terceiros desconfiados), mas agora vale nos dois lados de verdade.

**Implementado (3 fases)**:
- **Fase A — infra de publicação no Mobile**: `IpfsPinClient` novo (`mobile/lib/services/ipfs_pin_client.dart`, mirror de `ipfs.rs::pin_vault` via `dart:io HttpClient` puro — upload Kubo `/api/v0/add` + pin PSA `/pins`); `PinningProviderService` + `pinning_providers_screen.dart` (config de provedores de pin **própria do Mobile**, não sincronizada com o Desktop — não existe canal pra isso, cada device configura a própria); `vaultRegistryAbi` novo + `SessionCreator.updateVault()` (mesmo padrão de `createSession`/`revokeSession`); `VaultRepository.readRawBlob()`/`markPublished()`/`pendingChanges()` (mirror de `mark_published`/`pending_changes` do Rust); `VaultPublishService` orquestrando tudo (lê blob cru → pina → publica on-chain → marca versão).
- **Fase B — CRUD de entradas**: `vault_entry_form_screen.dart` novo (criar/editar compartilhado, mirror do `EntryForm` do Desktop); `VaultEntryDetailScreen` ganhou ações de editar/apagar (só visíveis com `canWrite`); `VaultScreen` ganhou botão "+" e banner de "Publicar" com contagem de pendências, tudo condicionado a `canWriteVault`.
- **Fase C — perfis no Mobile**: `addProfile`/`renameProfile`/`deleteProfile` no `VaultRepository` (mirror exato dos métodos Rust da Fase de perfis, ver acima); `vault_profiles_screen.dart` novo.

**Incidente no meio da sessão**: a build Docker do Flutter (primeira vez nesta máquina) esgotou a partição raiz (`/`, sda2, só 32GB — separada de `/home`, que tem 140GB+ livres). Resolvido com `docker container prune`/`docker image prune` (recuperou ~7GB, sem tocar em nenhum dado real) e remoção do volume `practice-valuation_cargo-target` (15,6GB, cache de build de outro projeto, autorizado pelo dono do projeto). Detalhe fica só aqui — não é um problema do TruthID, é do ambiente da máquina.

**Pendência real, não código**: nada disso rodou via `flutter test`/`flutter analyze` de verdade — a build Docker do Flutter (necessária pra rodar testes Dart) ficou arriscada demais com o disco apertado, e o dono do projeto pediu pra registrar como pendência em vez de insistir. Testes novos já estão escritos (`ipfs_pin_client_test.dart`, extensões em `vault_repository_test.dart`, `session_creator_test.dart`, `vault_publish_service_test.dart`, `vault_entry_detail_screen_test.dart`, `vault_profiles_screen_test.dart`) e o Rust já validado (22/22 passando, `cargo check` limpo), mas o lado Dart só passou por revisão manual — inclusive achei e corrigi uma quebra real que minha própria mudança introduziu em `vault_screen_test.dart` (métodos novos chamados sem stub). Próximo passo: rodar `./dev.sh flutter test`/`flutter analyze` quando o disco permitir, com atenção a possíveis erros de tipo/import que a revisão manual pode ter deixado passar.

#### Extensão pedindo alteração de senha, aprovada só pelo Device — ideia registrada na Sessão 97, não implementada

Pedido do dono do projeto: além de só *receber* um subconjunto do vault (o fluxo já desenhado acima), a extensão deveria poder **mandar um pedido de alteração** (ex: usuário troca a senha de um site direto pelo autofill/gerador da extensão) — mas esse pedido só pode ser *aceito* pelo Device (Mobile), nunca aplicado direto pela extensão. Mesmo princípio de "login não dá poder de escrita" já usado no brainstorm da Sessão 96 (delegação de assinatura pro Practice Valuation) — aqui aplicado ao próprio Vault, não a um app terceiro. Provável desenho (a confirmar num `/plan` futuro): canal reverso Extensão→Mobile (mesmo transporte desenhado acima, LAN ou IPFS/IPNS, só que na direção contrária), Mobile mostra uma tela de aprovação (mesmo padrão do `approval_screen.dart` já usado pro login via QR) com o que mudaria, usuário aprova ou rejeita, só then o Mobile aplica a mudança localmente e (se Mobile já tiver ganho escrita completa, ver item acima) publica. Só brainstorm — não decidido nem planejado ainda.

---

#### Fluxo de sincronização (Desktop ↔ Mobile)

**Decisão final**: P2P direto entre devices foi **removido do desenho**. O mecanismo de disponibilidade é apenas: edição local → botão "Enviar" → pinning (IPFS).

**Botão "Enviar" (batching de updates)**:
1. Empacotar todas as mudanças acumuladas num único novo blob cifrado.
2. Subir esse blob para os serviços de pinning configurados.
3. Disparar **uma única transação** on-chain atualizando a referência (hash/CID) no `VaultRegistry`.

Reduz custo de "1 transação por senha trocada" para "1 transação por sessão de edição".

**Pinning (IPFS) — mecanismo principal e contínuo de disponibilidade**:

Conteúdo sem pin no IPFS não desaparece instantaneamente. A remoção depende do garbage collection de cada nó (sem TTL universal — pode levar de horas a semanas, dependendo de quantos nós têm cópia em cache). Isso dá folga de tempo entre o usuário apertar "Enviar" e o pin se completar, mas **não é motivo para pular o health-check** — sem prazo previsível, a única forma confiável de saber se o vault ainda está seguro é checar ativamente.

**Abstração de pinning — IPFS Pinning Service API (spec padrão)**:

O app integra com **uma única interface**: a [IPFS Pinning Service API](https://ipfs.github.io/pinning-services-api-spec/) — spec REST padrão do ecossistema IPFS. Qualquer provedor que implemente essa spec funciona automaticamente, sem código específico por provedor. Isso cobre:

| Opção | Endpoint | Configuração |
|---|---|---|
| Pinata | `https://api.pinata.cloud/psa` | API key gerada no painel |
| Filebase | `https://api.filebase.io/v1/ipfs` | API key gerada no painel |
| 4EVERLAND | `https://ipfs.4everland.xyz/psa` | API key gerada no painel |
| Infura | `https://ipfs.infura.io:5001` | Project ID + Secret |
| **Self-hosted (Kubo)** | `http://localhost:5001/api/v0` | Node local — zero custo externo |
| Qualquer outro | URL customizada | API key customizada |

O usuário configura: `{ name, endpoint_url, api_key }` — o app não precisa saber qual provedor é. O self-hosted funciona da mesma forma que os externos: basta apontar para o node Kubo local.

- **Multi-pin por padrão**: cada "Enviar" sobe o blob simultaneamente em todos os provedores configurados (mínimo recomendado: 2). Se um cair, os outros garantem disponibilidade.
- **Zero-config para quem não quer se preocupar**: usuário configura API keys uma vez na configuração inicial (13.6); todo "Enviar" sobe automaticamente.
- **Custo real de pinning externo**: Filebase e 4EVERLAND oferecem 5GB grátis; Pinata oferece 1GB + 10GB de bandwidth + 500 arquivos grátis — qualquer tier gratuito cobre uma vida inteira de vault de senhas.
- **Self-host com Kubo**: usuário instala o Kubo (node IPFS de referência, ~50MB), habilita a Pinning Service API (`ipfs config --json Pinning.RemoteServices ...`), aponta o app para `http://localhost:5001`. Nenhum custo externo, nenhum dado sai do computador. O app vai fornecer guia de setup com os comandos exatos (13.6).
- **Health-check periódico**: verificação automática de que os pins em todos os provedores configurados ainda estão ativos; alerta individual por provedor se algum caiu.
- **Aviso de risco na UI** caso nenhum pin esteja ativo: descrever a incerteza real ("sem pin ativo, o conteúdo pode se tornar inacessível em algum momento, sem aviso prévio") em vez de um prazo fixo inventado.
- **O que o provedor de pin vê**: apenas o blob cifrado + o CID. Nunca a chave, nunca o conteúdo em claro — deixar isso explícito na UI.

---

#### Alternativas descartadas

| Alternativa | Por que foi descartada |
|---|---|
| Vault cifrado direto on-chain | Custo de gas por update, latência, exposição pública permanente mesmo cifrado (risco de quebra futura de criptografia), sem possibilidade de remoção retroativa |
| IPFS sem pinning como mecanismo primário (posição intermediária descartada no meio da discussão) | A objeção original era achar que IPFS sem pinning desaparece "na hora"; isso foi corrigido (sem TTL universal, leva de horas a semanas). A decisão final adotou IPFS **com** pinning como mecanismo principal — não mais como algo a evitar |
| P2P direto entre Desktop/Mobile para sync do vault inteiro | Proposto inicialmente para evitar dependência externa, mas o usuário decidiu simplificar: exigir pelo menos um device online era fricção real demais e o custo de pinning externo (efetivamente zero, tiers gratuitos cobrem o caso de uso) não justificava manter dois caminhos de sync. **Escopo da remoção**: só o P2P de sync do vault. O P2P efêmero do login via QR e do fluxo Mobile→Extensão foram mantidos — são canais de entrega de payload pronto, não de sincronização de estado |
| Master password digitada pelo usuário | Reintroduz exatamente o problema que o TruthID existe para eliminar |
| L2 Ethereum genérica para sync ("gas é barato") | Confunde "posso pagar o custo" com "o problema exige essa ferramenta" — sincronizar dados entre os próprios dispositivos do usuário não é um problema de consenso público; disponibilidade do vault ficaria acoplada ao uptime/congestionamento da rede e ao preço do gas sem necessidade técnica real |

---

#### O que é aproveitável do código já existente

- **`DeviceRegistry`**: fonte de verdade de quais Devices são confiáveis. Vault não precisa de sistema de confiança paralelo.
- **Padrão hash-only on-chain do `SessionRegistry`**: mesmo princípio vira o desenho do `VaultRegistry` (guardar referência, nunca conteúdo).
- **Padrão QR + transporte direto sem servidor**, já implementado para login (QR contém challenge, resposta vai direto via HTTPS/P2P, sem relay do TruthID no meio): é o mesmo padrão que resolve a extensão de navegador — QR como veículo de "iniciar canal efêmero", sem reinventar transporte novo.
- **Padrão de pareamento via QR mostrado pelo device que tem a informação** (decisão já tomada para mobile↔desktop): mesma lógica aplicada à extensão — quem **PRECISA** receber dado mostra o QR; quem **TEM** o dado lê e envia.
- **Geração/armazenamento de chave no Keystore/Secure Enclave (mobile) e TPM/Keyring (desktop)**, já implementado para a device key de auth: a mesma chave (ou derivada via HKDF) é a base da criptografia do vault — não precisa de um segundo sistema de gestão de chave.
- **Commit-reveal do `registerDevice`**: não se aplica diretamente ao Vault, mas é o tipo de padrão de segurança (mitigar front-running) que vale revisar se o `VaultRegistry` ganhar alguma função pública sensível a ordem de transações.

#### O que é novo (não existe ainda)

- Contrato `VaultRegistry` (hash/CID atual + timestamp de última atualização).
- Derivação de chave local via HKDF a partir da chave do device.
- Cifra/decifra local do vault (formato: site, usuário, senha, notas, tag de perfil).
- Lógica de batching de updates locais + botão "Enviar".
- Integração multi-pin: upload automático para 2+ provedores externos a cada "Enviar".
- Fluxo de configuração inicial de API keys dos provedores de pin.
- Health-check periódico de pin + alerta na UI.
- Textos de aviso de risco (cenário "sem nenhum pin ativo").
- Self-host de pinning como opção avançada (script/guia), não como requisito.
- Permissão `canWriteVault` por Device.
- Extensão de navegador "burra" (sem storage próprio) + lógica de sessão efêmera em memória no lado da extensão.
- Tela no Mobile de seleção/confirmação de perfil antes do scan da extensão.
- Registro local (no Desktop) de qual Device originou qual sessão de extensão (para revogação em cascata).
- Canal P2P efêmero Mobile→Extensão para entregar o subconjunto de senhas já filtrado por perfil (mantido — mesmo padrão do login via QR já em produção).
- ~~UI de gerenciar perfis nomeados pelo usuário~~ — **implementado na Sessão 97** (Desktop `VaultManagement.tsx` + Mobile `vault_profiles_screen.dart`), ver seção "Perfis" acima. Pré-requisito da 13.9 destravado: o scan da extensão já mostra a lista real de perfis, não mais fixa.

#### Não-escopo explícito (por agora)

- Autofill nativo via Credential Provider Extension (iOS) / Autofill Framework (Android).
- Native messaging host entre extensão e app desktop.
- Import/export de outros password managers.
- Compartilhamento de credenciais entre identidades diferentes (multi-usuário/empresa).
- Qualquer flow que exija o usuário digitar uma senha mestre.

#### Ordem sugerida de implementação

1. **Núcleo Desktop + Mobile**: `VaultRegistry`, derivação de chave (HKDF), cifra/decifra local, botão "Enviar" com batching.
2. **Multi-pin automático**: configuração inicial de API keys (2+ provedores externos), upload automático a cada "Enviar", health-check periódico, textos de aviso de risco. Self-host como opção avançada depois.
3. **Extensão de navegador**: QR de sessão, seleção de perfil no Mobile, canal P2P efêmero de entrega do payload filtrado (mesmo padrão do login via QR), revogação em cascata.

#### Status das etapas

- [x] 13.1 — Contrato `VaultRegistry` (hash/CID + timestamp, ligado ao `DeviceRegistry`) *(Sessão 49 — contrato em `contracts/src/VaultRegistry.sol`, script de deploy em `contracts/script/DeployVaultRegistry.s.sol`; deployado em Sepolia/Mainnet na Sessão 88, 215 testes Forge passando na suite completa)*
- [x] 13.2 — Derivação de chave HKDF no Desktop (Rust) e Mobile (Dart) *(Sessão 49 — `derive_vault_key()` interno em `desktop/src-tauri/src/lib.rs` usando `hkdf`+`sha2`; `VaultKeyService` em `mobile/lib/services/vault_key_service.dart` com HKDF-SHA256 puro; 5 testes Dart passando)*
- [x] 13.3 — Cifra/decifra local do vault (AES-256-GCM) *(Sessão 50 — `vault.rs` em `desktop/src-tauri/src/vault.rs` com `encrypt`/`decrypt` + 5 testes Rust; `VaultCipherService` em `mobile/lib/services/vault_cipher_service.dart` + 8 testes Dart; Tauri commands `vault_encrypt`/`vault_decrypt` via Base64; formato do blob: nonce(12) || ciphertext || tag(16))*
- [x] 13.4 — CRUD local de entradas do vault (site, usuário, senha, notas, perfil) *(Sessão 50 — structs `VaultEntry`+`Vault` + métodos `upsert`/`delete` + `load`/`save` em `desktop/src-tauri/src/vault.rs`; Tauri commands `vault_list_entries`/`vault_upsert_entry`/`vault_delete_entry`; 11 testes Rust passando. `VaultEntry`+`VaultRepository` em `mobile/lib/services/vault_repository.dart` com `path_provider`; 11 testes Dart passando. Formato JSON compartilhado: `{version, entries[]}`, blob cifrado em `$HOME/.truthid/vault.enc` no desktop e `{docs}/vault.enc` no mobile)*
- [x] 13.5 — Botão "Enviar" com batching + upload multi-pin (2+ provedores externos) *(Sessão 51 — novo módulo `desktop/src-tauri/src/ipfs.rs`: struct `PinningProvider { name, kind, endpoint_url, api_key }` onde `kind` é `"kubo"` (upload via `/api/v0/add`) ou `"psa"` (pin via IPFS Pinning Service API `/pins`); `pin_vault()` faz upload para todos os Kubo providers e pina o CID nos PSA providers; `load_providers`/`save_providers` persistem config em `~/.truthid/pinning_providers.json`. Em `vault.rs`: `mark_published(version)` salva `~/.truthid/vault.meta.json`; `pending_changes()` retorna vault.version - last_published_version. 4 novos Tauri commands: `vault_publish` (async, lê vault.enc, chama pin_vault, marca publicado, retorna `{cid, content_hash, providers_ok, providers_failed}`), `vault_pending_changes`, `vault_get_providers`, `vault_set_providers`. content_hash = keccak256(blob cifrado) com prefixo "0x", pronto para passar direto ao `VaultRegistry.updateVault`. 14 testes Rust passando)*
- [x] 13.6 — Configuração de provedores de pin: UI de adicionar/remover provedores (endpoint + API key), suporte à IPFS Pinning Service API como interface única (cobre terceiros como Pinata/Filebase/4EVERLAND e self-hosted via Kubo local), guia de setup do Kubo no app, health-check periódico por provedor + alerta na UI *(Sessão 51 — nova tab "Vault" em `App.tsx`; novo componente `desktop/src/components/VaultSettings.tsx`: lista de providers com badge kubo/psa + botão "Testar" (health-check via fetch GET/POST) + botão "✕" para remover; formulário de adição com campos nome/tipo/endpoint/api-key; botão "Adicionar Kubo local" quando lista vazia; guia collapsible de setup do Kubo com comandos exatos; tipo `PinningProvider` adicionado a `types.ts`)*
- [x] 13.7 — UI Desktop: tela de gerenciamento do vault, permissão `canWriteVault` por Device *(Sessão 51 — breaking change: `profile: String` → `profiles: Vec<String>` no Rust e `List<String>` no Dart, com migração automática de vaults antigos; novo `permissions.rs` + 2 commands (`vault_get_device_permissions`, `vault_set_device_permission`), permissões em `~/.truthid/vault_permissions.json`; `VAULT_REGISTRY_ADDRESS` + ABI adicionados a `contracts.ts` (endereço placeholder — aguardando deploy); novo componente `VaultManagement.tsx`: lista de entradas com filtro, formulário add/edit inline, delete com confirm, seletor de grupos multi-select (Trabalho/Casa/Pessoal), fluxo "Enviar" em 2 fases (vault_publish → updateVault on-chain), status on-chain (versão + data), botão "⚙ Providers" → VaultSettings, seção colapsável de permissões por device; tab "Vault" em App.tsx aponta agora para VaultManagement. 14 testes Rust + 13 testes Dart passando)*
- [x] 13.8 — UI Mobile: leitura do vault, tela de perfil para scan da extensão *(Sessão 89 — gap descoberto: o vault.enc local do mobile nunca era populado com conteúdo real, então a etapa precisou de um pipeline de sync completo, não só uma UI. Novo `BlockchainService.hasVault`/`getVault` (decode manual, mesmo padrão de `getIdentityByUsername`/débito #32 — `VaultRef.cid` é dinâmico e vem primeiro no struct). Novo `IpfsGatewayClient` (gateways públicos fixos `ipfs.io`/`dweb.link` com fallback, binary-safe via `consolidateHttpClientResponseBytes` de `package:flutter/foundation.dart`). Novo `VaultSyncService` orquestra hasVault→getVault→download→verifica keccak256 contra o contentHash on-chain→decifra (via novo `VaultRepository.overwriteCache` + `listEntries()` já existente) — hash não bate nunca é tratado como sucesso, sempre cai pro cache local (`VaultSyncStatus.offlineUsingCache`/`syncFailedNoCache`). Novo `VaultScreen` (4ª aba, leitura + busca por site/usuário/perfil, senha sempre mascarada com placeholder fixo) e `VaultEntryDetailScreen` (reveal/copy). Novo `VaultSessionScreen` — scan do QR da extensão (`action: 'truthid-vault-session'`) → escolhe um dos 3 perfis fixos (`kVaultProfiles`, paridade com `VaultManagement.tsx`) → mostra quantas entradas bateriam → termina em estado explícito "ainda não disponível (13.9)", sem fingir sucesso. `InfoRow` extraído de `approval_screen.dart` (era privado) pra reuso nas telas novas. `flutter analyze` limpo (0 erros novos) e `flutter test` verde (só as 5 falhas pré-existentes e não relacionadas de `vault_key_service_test.dart` isolado, confirmadas antes desta sessão via `git stash`))*
- [x] 13.9 — Extensão de navegador: sessão efêmera, autofill, revogação em cascata *(Sessão 99 — **fatia 1: transporte LAN**; Sessão 100 — **fatia 2a: Mobile publica o dead-drop IPFS/IPNS**; Sessão 101 — **fatia 2b: extensão consome o dead-drop**, fecha a 13.9 e a Fase 13. Falta só validação manual E2E em hardware real. Ver seção "Extensão de navegador (13.9)" abaixo para o desenho completo, achados e pendências)*
