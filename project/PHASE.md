## Fases Detalhadas

### Fase 1 — Smart Contracts

**Objetivo de aprendizado**: Entender como contratos inteligentes modelam identidade e autorização on-chain.

**Contratos a implementar**:

| Contrato | Responsabilidade |
|---|---|
| `IdentityRegistry` | Armazena: Identity ID, Username, Controller Wallet, Guardian Config |
| `DeviceRegistry` | Armazena: Public Keys dos dispositivos, Metadata, Status de revogação |
| `RecoveryManager` | Controla: Aprovações de guardians, operações de recovery com timelock |

**Etapas**:
- [x] 1.1 — Setup do ambiente (Foundry v1.7.1, pasta `contracts/`)
- [x] 1.2 — `IdentityRegistry`: criar identidade, resolver username → identity (16 testes passando)
- [x] 1.3 — `DeviceRegistry`: registrar device, revogar device, checar status (25 testes passando)
- [x] 1.4 — `RecoveryManager`: propor recovery, coletar aprovações, executar com timelock (7 dias) — 34 testes passando
- [x] 1.5 — Testes unitários completos — 80 testes passando (17 IdentityRegistry + 25 DeviceRegistry + 38 RecoveryManager)
- [x] 1.6 — Deploy em testnet (Base Sepolia)
  - **Redeployados na Sessão 24** (pós-auditoria de segurança, etapa 6.5) — endereços antigos abaixo ficaram obsoletos:
    - IdentityRegistry : 0x35D21c65980cBd2dAE7576e1bf6b8e46C9e180BF
    - DeviceRegistry   : 0x225c67a98c9D675fE595ae05a2F9249C34d9C60a
    - RecoveryManager  : 0xDd4CE29A35022741Bbe2F8f38aa185ddF41A8Fa7
    - SessionRegistry  : 0xdeD2Ad865069CA6546172926540D3A3Aa73C1CA6
  - Endereços originais (Sessão 7, obsoletos desde a Sessão 24):
    - IdentityRegistry : 0xd4484aDD6DCd0919568B6365882cDB207fE27D9c
    - DeviceRegistry   : 0xe87633b148cf7a7F6c60DdA84AD7f4D3a9eC187F
    - RecoveryManager  : 0x66be956D14b9383aE9a58f70edD6Cae406Eb960f
    - SessionRegistry  : 0x93B56d40B304269Ee23f84A1cF3BD7B338514b42
- [x] 1.7 — Verificar contratos no Basescan (refeito na Sessão 24 para os 4 endereços novos)

**Decisões pendentes**:
- Padrão de upgrade: Proxy ou imutável na v1?

---

### Fase 2 — Camada de Comunicação (WebRTC)

**⚠️ Retirado na Sessão 26 (continuação)**: o WebRTC real (`RTCPeerConnection`, SDP, ICE) nunca foi usado pelo app de produção — foi abandonado ainda na Sessão 20 por incompatibilidade do `flutter_webrtc`, substituído por um relay simples (`signaling/main.py`) que repassava mensagens 1:1 entre os dois lados de uma "sala". Esse relay (e o `turn/` que nunca chegou a ser usado de verdade) foi **removido do repositório** na Sessão 26 — pareamento e login não dependem mais de nenhum servidor do TruthID. Ver "Roadmap de Evoluções Planejadas → Sinalização on-chain" para o desenho atual. As etapas abaixo descrevem o que foi construído na época — histórico, não reflete o estado atual.

**Objetivo de aprendizado (histórico)**: Conectar website ↔ mobile diretamente, sem servidor no meio dos dados de autenticação.

**Decisão**: WebRTC em vez de relay tradicional — website e celular se conectam P2P. Nenhum servidor vê o challenge ou a assinatura. O relay foi descartado por ser um ponto de centralização (mesmo sem comprometer segurança, compromete disponibilidade e vai contra o princípio descentralizado do projeto.

**Responsabilidades**:
- Conexão P2P direta entre website e celular
- Challenge vai direto do website para o celular
- Resposta assinada volta direto do celular para o website
- Sinalização: troca de informações de conexão antes do P2P (canal ainda a decidir)

**Componentes**:
- **STUN**: múltiplos servidores públicos (Google, Cloudflare) — grátis, failover automático, não veem dados
- **TURN**: fallback para ~10% dos casos onde P2P direto falha — self-hostável (coturn)
- **Sinalização**: servidor leve de sinalização WebSocket — stateless, open source, self-hostável

**Etapas**:
- [x] 2.1 — Decidir canal de sinalização → servidor leve (WebSocket, stateless, self-hostável)
- [x] 2.2 — Implementar sinalização (FastAPI + WebSocket, stateless, self-hostável via Docker)
- [x] 2.3 — Conexão WebRTC: website cria oferta → celular responde
- [x] 2.4 — Challenge trafega P2P: website → celular
- [x] 2.5 — Resposta assinada trafega P2P: celular → website
- [x] 2.6 — TTL de challenges (expiração, não-replay)
- [x] 2.7 — TURN self-hostável (coturn) como fallback
- [x] 2.8 — Testes de integração

**Decisões pendentes**:
- Stack do servidor de sinalização: Go vs Node.js

---

### Fase 3 — Desktop App (Tauri)

**Objetivo de aprendizado**: Construir uma aplicação desktop com Rust no backend e React no frontend, integrando wallet e blockchain.

**Ambiente de desenvolvimento**: Docker — rode `./dev.sh` dentro de `desktop/` para subir o container.
Antes de rodar pela primeira vez na sessão (ou após reiniciar o computador), o X11 precisa estar liberado para Docker. O script `dev.sh` já faz isso automaticamente — basta lembrar de usar `./dev.sh` em vez de `docker compose up` diretamente.

**Responsabilidades**:
- Criar e gerenciar identidade
- Gerenciar dispositivos (adicionar/revogar)
- Gerenciar sessões ativas
- Conectar wallet (MetaMask, Rabby, Ledger, Trezor, WalletConnect)

**Etapas**:
- [x] 3.1 — Setup Tauri + React + TypeScript
- [x] 3.2 — Integração com wallet (wagmi + viem). **Achado na Sessão 33 (revisão visual da Fase 9, testando o app de verdade)**: só o conector `injected` foi de fato implementado — Rabby/Ledger/Trezor listados nas responsabilidades acima nunca foram. Pior: `injected` **nunca funciona no app empacotado**, só em `npm run dev` num browser normal — o Tauri usa WebKitGTK como webview, que não suporta extensões de navegador (MetaMask etc.) de forma alguma. Corrigido parcialmente na mesma sessão: conector `walletConnect` adicionado (`desktop/src/config/wagmi.ts`, Project ID público do Reown Cloud), resolvendo a conexão via QR code/celular. Ledger/Trezor diretos (USB) ficaram pendentes — ver "Pendências" na Sessão 33. **Decisão tomada na Sessão 34**: implementar Ledger via USB direto em Rust (não documentar fallback via WalletConnect) — ver Fase 10.
- [x] 3.3 — Tela: Criar identidade (conectar wallet → escolher username → registrar)
- [x] 3.4 — Tela: Gerenciar dispositivos (adicionar via QR, revogar)
- [x] 3.5 — Tela: Sessões ativas (listar, revogar sessão individual ou todas)
  - Sessões NÃO ficam num servidor central — armazenadas como hash on-chain
  - Hash: `keccak256(identityId + devicePubkey + origin + timestamp + nonce)` → gravado na blockchain
  - Dados originais ficam localmente no dispositivo do usuário (para provar ownership)
  - Para revogar: usuário fornece dados originais → contrato recalcula hash → marca como revogado
  - SDK dos sites consulta "esse hash está revogado?" sem saber o que o hash representa
  - Privacidade: público que existe um registro, privado o que representa (site, device, horário)
  - Custo estimado por login: ~$0,0002 (Base Mainnet, gas ~0.001 gwei)
- [x] 3.6 — Geração de QR code para pareamento de novo dispositivo (implementado dentro da 3.4 — componente PairDevice em ManageDevices.tsx)
- [x] 3.7 — Armazenamento seguro de chaves (Windows TPM / Linux Keyring)
  - Dois comandos Tauri em Rust: `get_or_create_device_key` (gera/recupera chave do keyring do SO) e `sign_challenge` (assina com a chave privada)
  - Algoritmo secp256k1 + endereço Ethereum derivado via keccak256 — compatível com DeviceRegistry
  - `DesktopDevice.tsx`: componente que registra o próprio desktop como device na blockchain
  - Desktop pode autenticar sem celular após registro
- [x] 3.8 — Build para Linux, Windows, macOS
  - GitHub Actions com matrix ubuntu-22.04 / windows-latest / macos-latest
  - Gera .deb + AppImage (Linux), .msi (Windows), .dmg (macOS)
  - Release draft criado automaticamente no GitHub ao criar tag de versão
  - Trigger: `git tag vX.Y.Z && git push origin vX.Y.Z`

---

### Fase 4 — Mobile App (Flutter)

**Objetivo de aprendizado**: Construir o componente mais crítico do fluxo de autenticação — o aprovador que fica na mão do usuário.

**Responsabilidades**:
- Escanear QR code do website
- Exibir request de login ao usuário
- Assinar o challenge com chave privada do dispositivo
- Gerenciar dispositivos e sessões

**Etapas**:
- [x] 4.1 — Setup Flutter
- [x] 4.2 — Geração de key pair no dispositivo (Android Keystore / iOS Secure Enclave)
- [x] 4.3 — Scanner de QR code
- [x] 4.4 — Tela: Aprovar login (exibir quem está pedindo, aprovar/recusar)
- [x] 4.5 — Assinatura do challenge + envio via WebSocket relay
- [x] 4.6 — Tela: Meus dispositivos
- [x] 4.7 — Tela: Sessões ativas

---

### Fase 5 — SDKs

**Objetivo de aprendizado**: Criar uma API limpa que qualquer desenvolvedor pode integrar em minutos.

**Funções principais**:
```
verify_authentication(token) → bool
verify_session(session_id) → SessionInfo
check_device_status(device_pubkey) → DeviceStatus
check_revocation(identity_id) → RevocationInfo
```

**Etapas**:
- [x] 5.1 — TypeScript SDK (npm package)
  - `sdk/typescript/src/`: client.ts, types.ts, contracts.ts, index.ts
  - `TruthIDClient`: createChallenge(), verifyAuthResponse(), verifySession(), checkDeviceStatus()
  - Compila para `dist/` com declarações TypeScript (.d.ts)
  - viem v1.21.4 (CommonJS, sem dependência de ox)
- [x] 5.2 — Python SDK (pip package)
  - `sdk/python/truthid/`: client.py, types.py, contracts.py, __init__.py
  - `TruthIDClient`: create_challenge(), verify_auth_response(), verify_session(), check_device_status()
  - Síncrono (web3.py padrão), sem async/await
  - `separators=(',', ':')` no json.dumps — JSON compacto compatível com Dart/JS
- [x] 5.3 — Ruby SDK (gem)
  - `sdk/ruby/lib/truthid/`: client.rb, types.rb, contracts.rb
  - `TruthID::Client`: create_challenge, verify_auth_response, verify_session, check_device_status
  - `AuthChallenge#to_h` → camelCase para JSON; `AuthResponse.from_hash` → parseia JSON do mobile
  - `Struct.new(keyword_init: true)` para tipos de resultado (VerifyAuthResult, SessionInfo, DeviceStatus)
  - JSON.generate compacto por padrão — sem `separators` como no Python
- [x] 5.4 — Documentação e exemplos para cada SDK
  - `sdk/README.md`: documentação única em inglês cobrindo os 3 SDKs
  - Seções: How It Works (ASCII flow), Installation, Quick Start, API Reference completa, Full Examples (Express/Flask/Sinatra), Security Notes, Networks, Smart Contracts
- [x] 5.5 — Exemplo de integração: app Express.js protegido com TruthID
  - `sdk/typescript/example/server.js`
  - GET /auth/challenge → cria challenge (vai no QR)
  - POST /auth/verify → verifica resposta do mobile via SDK
  - GET /api/profile → rota protegida com Bearer token

---

### Fase 6 — Integração & Testes E2E

**Objetivo de aprendizado**: Validar que todos os componentes funcionam juntos como um sistema real.

**Etapas**:
- [x] 6.1 — Fluxo completo: criar identidade → adicionar device → login via QR
- [x] 6.2 — Fluxo de recovery: 3 de 5 guardians aprovam → timelock → novo wallet
- [x] 6.3 — Fluxo de revogação: revogar device → tentativa de login falha
- [x] 6.4 — Testes de segurança: replay attack, challenge expirado, device revogado
- [x] 6.5 — Auditoria de segurança dos contratos

**Relatório da auditoria (etapa 6.5, Sessão 24)** — revisão manual dos 4 contratos contra categorias clássicas (controle de acesso, reentrância, front-running, dependência de timestamp, DoS, validação de entrada). Sem ferramenta automatizada (Slither/Mythril) — só revisão funcional.

| # | Contrato | Local | Severidade | Achado | Status |
|---|---|---|---|---|---|
| 1 | IdentityRegistry | `setRecoveryManager` | **Crítico** | Sem controle de acesso — qualquer endereço pode chamar antes do deploy oficial (front-running de inicialização, mesmo padrão do hack Parity Multisig 2017). Quem chamar primeiro se torna o RecoveryManager e pode tomar qualquer identidade via `recoverController` | ✅ **Corrigido** — `owner` imutável capturado no construtor + `onlyOwner` em `setRecoveryManager` |
| 2 | SessionRegistry | `createSession` | Médio/Alto | Função permissionless, sem validar relação entre `msg.sender`/`identityId`/`devicePubKey`. Hoje inofensivo (nenhum código confia em `verifySession` como credencial de login), mas é armadilha para integração futura + permite spam barato de sessões falsas por identidade | ✅ **Corrigido** — `createSession` agora exige assinatura ECDSA (r,s,v) do próprio `devicePubKey` sobre o hash (prova de posse) + checagem cruzada no `DeviceRegistry` (device precisa estar ativo e pertencer ao `identityId` informado) |
| 3 | RecoveryManager + IdentityRegistry | `proposeRecovery` / `recoverController` | Médio | Falta validação de `address(0)` em `newController` — pode brickar o controller permanentemente, desativando a janela de cancelamento de 7 dias para futuras propostas | ✅ **Corrigido** — validação em `proposeRecovery` (fail-fast) e em `recoverController` (defesa em profundidade) |
| 4 | IdentityRegistry | `transferController` / `recoverController` | Baixo/Médio | Mesma falta de validação de `address(0)` em `newController` | ✅ **Corrigido** — validação adicionada nas duas funções |
| 5 | RecoveryManager | design (pós-recovery) | Médio/Informacional | Guardians configurados pelo controller anterior continuam válidos após recovery executada — novo controller precisa reconfigurar manualmente ou herda o risco do conjunto antigo | ✅ **Corrigido** — `executeRecovery` agora zera `_isGuardian` e `delete`a `_guardianConfigs` da identidade; novo controller precisa chamar `configureGuardians` para reativar a recovery social |
| 6 | RecoveryManager | `configureGuardians` / `proposeRecovery` | Baixo | Array de guardians sem limite de tamanho → DoS de gas em cenário de custódia hostil | ✅ **Corrigido** — `MAX_GUARDIANS = 20`, validado em `configureGuardians` |
| 7 | DeviceRegistry | `registerDevice` | Baixo | Front-running do `devicePubKey` antes da confirmação (griefing/DoS pontual, sem takeover de identidade) | ✅ **Corrigido** — esquema commit-reveal: `commitDevice(commitment)` em um bloco, `registerDevice(pubKey, label, salt)` revela em um bloco posterior; `commitment` inclui `msg.sender`, então ninguém além de quem commitou pode revelar |

**Correções aplicadas (Sessão 24)**: todos os 7 achados corrigidos. `IdentityRegistry.sol`, `DeviceRegistry.sol`, `RecoveryManager.sol` e `SessionRegistry.sol` modificados. 120 testes Foundry passando (103 originais + 17 novos). `integration/e2e.ts`, `e2e_recovery.ts`, `e2e_revocation.ts` e `e2e_security.ts` atualizados para o novo fluxo commit-reveal e revalidados. Desktop (`ManageDevices.tsx`, `DesktopDevice.tsx`, `contracts.ts`) atualizado para o fluxo de 2 transações; `npx tsc --noEmit` limpo.

**✅ Redeploy concluído (Sessão 24)** — os 4 contratos foram redeployados e verificados na Base Sepolia com o código corrigido. Endereços novos na Fase 1, etapa 1.6. Carteira deployadora: `0x8814D40EF00B829fe0412112192C6Fb778CC2787` (mesma da Sessão 7).

**Pontos positivos confirmados**:
- `executeRecovery` segue corretamente o padrão checks-effects-interactions (`executed = true` antes da chamada externa) — sem risco de reentrância
- `isSessionRevoked` falha de forma segura (fail-closed: sessão inexistente conta como revogada)
- `revokeAllSessions` é O(1) via timestamp — sem risco de DoS por loop
- `_validateUsername` restringe a ASCII (a-z, 0-9, -, .) — elimina ataques de homóglifo/phishing visual
- 103 testes unitários + 4 cenários E2E de ataque (replay, expiração, nonce, impostor) já cobrem a camada de aplicação; os achados acima são exclusivamente da camada de contrato

**Decisão em aberto**: quais achados corrigir antes do deploy em mainnet (Fase 7). O achado #1 (crítico) deve ser corrigido antes de qualquer deploy em rede pública — os demais são candidatos a discussão.

---

### Fase 7 — Mainnet & Lançamento

**Etapas**:
- [x] 7.1 — Deploy contratos em Base Mainnet
  - Carteira deployadora: `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265` — 2ª conta derivada da Ledger do usuário (HD path `m/44'/60'/1'/0/0`, mesma seed de 24 palavras, índice diferente da conta principal). Decisão registrada em memória: endereço do deployer fica público para sempre como `owner()`, então não se usa a conta pessoal.
  - RPC usado: pública `https://mainnet.base.org` (sem cadastro — volume baixo, suficiente para um deploy pontual)
  - Endereços (Base Mainnet, chain 8453):
    - IdentityRegistry : 0xbf097EC74d0Cc9b16D3d94EaCa62060d89A63b17
    - DeviceRegistry   : 0x4A7a307cb6872bde24BAf3E9de2BeC3Ddd03e144
    - RecoveryManager  : 0x01df431F6a2276aE3220dc6f3874454caA5F20f8
    - SessionRegistry  : 0x062c577C26067d04bBEEaa953F8E7675fF4849ab
  - Todos os 4 verificados no Basescan (`forge verify-contract`, Etherscan V2 API com `chainid=8453`)
  - Custo total: ~0,000055 ETH (saldo antes 0,010082 ETH → depois 0,010045 ETH) — gas price ~0,011 gwei
  - Sanity check: `owner()` do IdentityRegistry retorna a carteira deployer ✓; `totalIdentities()` retorna 0 ✓
  - **Endereços propagados (Sessão 26)** — desktop, mobile e os 3 SDKs agora apontam para Base Mainnet. Ver detalhes na Sessão 26 do Log de Sessões.
- [x] 7.2 — Eliminar o servidor de sinalização (substitui "Relay Service em produção" — não fazia sentido hospedar algo que ia ser removido). Implementado na Sessão 26 (continuação): pareamento via QR mostrado pelo mobile + polling on-chain; login via challenge embutido no QR + POST HTTPS direto pro backend do site. `signaling/`, `turn/` e `webrtc-demo/` removidos. Ver "Roadmap de Evoluções Planejadas → Sinalização sem servidor"
- [x] 7.3 — Publicar SDKs (npm, pip, rubygems). Implementado na Sessão 29: `truthid-sdk@0.1.0` publicado nos três registros — npm (https://www.npmjs.com/package/truthid-sdk), PyPI (https://pypi.org/project/truthid-sdk/0.1.0/) e RubyGems. Ver Sessão 29 no Log de Sessões para detalhes.
- [x] 7.4 — Documentação pública. `README.md` criado na raiz do repositório (Sessão 30) — escopo limitado a esse arquivo, a pedido do usuário (CONTRIBUTING.md/SECURITY.md ficaram fora). Cobre: o que é o TruthID, fluxo de auth (diagrama ASCII), arquitetura, tabela de endereços mainnet, SDKs publicados, como buildar cada componente, seção de segurança (aponta pra "GitHub Security tab" para reports privados, sem expor e-mail pessoal — decisão consciente do usuário)
- [x] 7.5 — Open source (GitHub). Descoberto na Sessão 30 que o repositório já estava público desde 2026-06-04 (criado assim, sem que tivesse sido uma decisão consciente registrada) — `curl` na API do GitHub sem autenticação retornou `"private": false`. Varredura em `git log --all -p` confirmou que nenhum segredo de verdade jamais foi commitado (só placeholders em `contracts/.env.example`; o PAT exposto era só na configuração local do git, nunca em conteúdo versionado). Decisão consciente do usuário: manter os arquivos de estado do projeto (dentro de `project/`) como estão, sem reescrever histórico nem mover pra repositório separado — o conteúdo "bastidor" (diretriz de ensino, log de sessões) não representa risco de segurança real hoje, é só uma questão de tom. Fechamento da etapa: README/project/INDEX.md commitados e enviados via SSH (`73de3e9`), e "Private vulnerability reporting" habilitado nas configurações do repositório (confirmado via API: `private-vulnerability-reporting` → `enabled: true`)

---

### Fase 8 — Documentação Web

**Objetivo**: Transformar o `sdk/README.md` em um site de documentação profissional, hospedado no GitHub Pages, com visual próprio do TruthID — o rosto público do projeto para desenvolvedores.

**Ferramenta**: [Docusaurus](https://docusaurus.io/) (React, criado pelo Meta para documentações de SDKs — exatamente o caso do TruthID)

**Por que Docusaurus?**
- Deploy no GitHub Pages com um comando (`npm run deploy`)
- Busca full-text embutida
- Versionamento de docs (útil quando os contratos evoluírem)
- MDX: Markdown + componentes React (permite demos interativos)
- Dark mode out of the box

**O que o site vai ter**:

```
masterlxz.github.io/truthid
├── / (landing page)  ← "Replace passwords forever"
├── /docs/intro        ← O que é TruthID, como funciona (diagrama animado)
├── /docs/quickstart   ← Do zero ao primeiro login em 5 minutos
├── /docs/sdk/typescript
├── /docs/sdk/python
├── /docs/sdk/ruby
├── /docs/security     ← Modelo de segurança, threat model
├── /docs/contracts    ← ABIs, endereços, Basescan links
└── /blog              ← (opcional) posts sobre decisões de arquitetura
```

**Etapas**:
- [x] 8.1 — Setup Docusaurus em `docs/` + configuração GitHub Pages (Action de deploy automático). Implementado na Sessão 31: `npx create-docusaurus@latest docs classic --typescript`; `docusaurus.config.ts` ajustado (title/tagline TruthID, `url`/`baseUrl`/`organizationName`/`projectName` para `masterlxz.github.io/truthid`, `editUrl` apontando pro repo, navbar/footer sem branding genérico do template); blog do template (posts de dinossauro) desativado (`blog: false`) e pasta removida — não fazia parte do roadmap e não fazia sentido publicar conteúdo de exemplo; `.github/workflows/deploy-docs.yml` criado (build + `actions/deploy-pages`, dispara em push na main que toque `docs/`); `npm run build` validado localmente sem erros. Commitado (`7737249`) e enviado via push. **Pages habilitado automaticamente pela própria Action**: `actions/configure-pages` tem permissão (`pages: write`) pra habilitar o GitHub Pages com source "GitHub Actions" caso ainda não esteja configurado — não precisou de nenhum passo manual no Settings. Workflow rodou (`build` + `deploy`, ambos `success`) e o site já está no ar em `https://masterlxz.github.io/truthid/` (confirmado via `curl -o /dev/null -w "%{http_code}"` → 200). **Fase 8.1 totalmente concluída.**
- [x] 8.2 — Landing page: headline, diagrama do fluxo, botão "Get Started". Implementado na Sessão 31 (continuação): hero com a tagline já configurada na 8.1 + botões "Get Started" (→ `/docs/intro`) e "View on GitHub"; seção "How a login works" com o diagrama ASCII do README; 3 cards de feature reais substituindo os de exemplo do template. Removidas as pastas de tutorial genérico do Docusaurus (`tutorial-basics/`, `tutorial-extras/`) e reescrito `docs/docs/intro.mdx` com conteúdo real (necessário porque o CTA "Get Started" apontava pra lá). **Tema visual também refeito** (feedback do usuário: o padrão do template estava "feio") — paleta dark/cripto com acento ciano (`#4DD0E1`) como modo padrão (toggle claro/escuro mantido), tipografia Space Grotesk+Inter, hero com fundo navy fixo e glow sutil, botões customizados, ícones SVG desenhados à mão nos cards (cadeado, carteira, code brackets), e logo padrão (dinossauro do Docusaurus) trocado por uma marca mínima provisória (escudo+check em ciano) — identidade visual definitiva continua sendo a etapa 8.10. Validado visualmente nos dois modos via screenshot (Playwright headless, instalado ad-hoc nesta sessão).
- [x] 8.3 — Guia de introdução: o que é TruthID, pré-requisitos, arquitetura. Implementado na Sessão 32: `docs/docs/intro.mdx` ganhou duas seções novas (a versão da 8.2 só tinha "o que é" + "how it works"). "Prerequisites" separa o que é preciso pra logar com TruthID (identidade on-chain + device pareado) do que é preciso pra integrar TruthID (backend que recebe POST HTTPS + lib de QR) — sem banco de dados, servidor ou conta de terceiro a provisionar. "Architecture" reaproveita a tabela de componentes do `README.md` raiz (contracts/desktop/mobile/sdk/integration), adaptando os links relativos do repo para URLs completas do GitHub (esse site é hospedado separado do repo, links relativos não funcionariam). `npm run build` validado sem erros; revisão visual via screenshot (Playwright headless, mesmo processo da 8.2) confirmou que as tabelas novas renderizam bem no tema dark, sem quebra de layout.
- [x] 8.4 — Quickstart interativo: passo a passo comentado do fluxo completo. Implementado na Sessão 32: nova página `docs/docs/quickstart.mdx` (sidebar_position 2, depois de Introduction), adicionada ao footer. 5 passos (instalar SDK → criar challenge → renderizar QR → verificar resposta → testar com device real) + "Next steps". Passos 1, 2 e 4 usam o componente `<Tabs groupId="sdk-lang">` do tema clássico do Docusaurus (primeiro uso desse componente no site) pra mostrar TypeScript/Python/Ruby lado a lado com seleção sincronizada entre as três seções. Antes de escrever cada snippet, os 3 SDKs (`sdk/typescript/src/{types,client}.ts`, `sdk/python/truthid/{types,client}.py`, `sdk/ruby/lib/truthid/types.rb`) foram lidos pra confirmar a API real — achado: o Python `AuthResponse` não tem `from_dict`/`from_json`, precisa ser construído campo a campo com chaves camelCase (`deviceAddress`, não `device_address`) porque os nomes dos campos do dataclass espelham o protocolo JSON; o Ruby tem `AuthResponse.from_hash` (existe de verdade). Passo 5 é honesto sobre uma limitação real: não há build pré-compilado do desktop/mobile publicado ainda (`gh api .../releases` retornou 0 releases) — testar de ponta a ponta hoje exige compilar a partir do código-fonte, com link pra seção "Building from source" do README raiz. Build (`npm run build`) validado sem erros; revisão visual via Playwright confirmou layout ok no tema dark e que o clique nas abas funciona (sincroniza seleção, usa o ciano do tema).
- [x] 8.5 — Referência de API: TypeScript SDK (migrar e expandir o README atual). Implementado na Sessão 32: nova categoria de sidebar "SDK Reference" (`docs/docs/sdk/_category_.json`, position 3 — depois de Introduction/Quickstart) com a primeira página, `docs/docs/sdk/typescript.md` (`/docs/sdk/typescript`). Cobre instalação, construtor (`TruthIDClientConfig`, incluindo a diferença de não ter default pro `network` — diferente de Python/Ruby), os 4 métodos (`createChallenge`, `verifyAuthResponse`, `verifySession`, `checkDeviceStatus`) com parâmetros/retornos/exemplos/razões de falha, todos os 7 tipos exportados (cada um com heading próprio pra permitir link direto, ex. `#authchallenge`), security notes (nonce invalidation, TTL, HTTPS only) e tabela de networks — tudo migrado e expandido a partir do `sdk/README.md`, mas específico de TypeScript (tipos `bigint`/`Date` exatos, em vez do placeholder genérico "bigint / int" do README compartilhado). `sdk/README.md` não foi tocado ainda — decisão consciente de só simplificá-lo/linkar pra essa página depois que Python e Ruby (8.6/8.7) também tiverem páginas próprias, pra não deixar a referência genérica do README quebrada pra 2 dos 3 SDKs no meio do caminho. **Bug pego durante a revisão visual**: a sintaxe de admonition `:::tip Título` (estilo Docusaurus v2) não funciona no v3 instalado (3.10.1) — o tema novo usa `remark-directive`, que exige título entre colchetes (`:::tip[Título]`); sem isso, o bloco inteiro renderiza como texto puro em vez da caixa estilizada. Corrigido e revalidado visualmente via screenshot. `npm run build` sem erros (inclusive sem "broken anchors" depois de dar heading próprio pra cada tipo, necessário pros links cruzados `#authchallenge` etc. funcionarem).
- [x] 8.6 — Referência de API: Python SDK. Implementado na Sessão 32: `docs/docs/sdk/python.md` (sidebar_position 2, depois de TypeScript), mesma estrutura da página TypeScript (instalação, construtor, 4 métodos, tipos, security notes, networks). Destaques específicos de Python: construtor tem default `network="base-mainnet"` (diferente de TS, que exige explícito); seção "Types" tem uma nota explicando uma assimetria real do SDK — `AuthChallenge`/`AuthResponse` usam campos camelCase (espelham o protocolo JSON que o mobile assina) enquanto `VerifyAuthResult`/`SessionInfo`/`DeviceStatus` usam snake_case normal de Python (nunca cruzam a rede); exemplo de `verify_auth_response` mostra explicitamente como construir `AuthResponse` campo a campo (sem `from_dict`), reaproveitando o achado já registrado na etapa 8.4. Página TypeScript atualizada pra linkar pra essa página nova em "Next steps" (antes dizia "Python and Ruby — coming soon"). `npm run build` sem erros; revisão visual via Playwright confirmou sidebar com as duas páginas lado a lado, admonition renderizando certo (já usando a sintaxe `:::tip[Título]` correta desde a criação) e blocos de código Python com syntax highlighting.
- [x] 8.7 — Referência de API: Ruby SDK. Implementado na Sessão 32: `docs/docs/sdk/ruby.md` (sidebar_position 3, fecha o trio na categoria "SDK Reference" — TypeScript/Python/Ruby agora completos, todos linkando entre si em "Next steps"). Mesma estrutura das outras duas páginas. Destaques específicos de Ruby: mostra as duas formas equivalentes de construir o client (`TruthID::Client.new` e o factory `TruthID.new_client`, achado já registrado na Sessão 26 como "fácil de esquecer" — ambos documentados agora); construtor com default `network: "base-mainnet"` (igual Python); seção "Types" explica que `AuthChallenge`/`AuthResponse` são o desenho mais limpo dos 3 SDKs — atributos sempre snake_case do jeito Ruby (`issued_at`, `device_address`), com a conversão pra camelCase isolada só nos métodos `to_h`/`from_hash` na borda do protocolo (diferente do Python, onde o próprio dataclass usa `issuedAt`/`deviceAddress` direto); `AuthResponse.from_hash` existe de verdade (contraste explícito com a ausência de equivalente no Python, já registrado nas etapas 8.4/8.6). Páginas TypeScript e Python atualizadas pra linkar pra `/docs/sdk/ruby` em "Next steps" (antes "coming soon"). `npm run build` sem erros; revisão visual confirmou as 3 páginas lado a lado na sidebar e os blocos de código Ruby corretos.
- [x] 8.8 — Página de segurança: modelo de ameaças, o que o TruthID protege e o que não protege. Implementado na Sessão 33: nova página `docs/docs/security.mdx` (sidebar_position 4, depois da categoria "SDK Reference"). Antes de escrever, investigação no código real (não só no que já estava documentado) confirmou 5 pontos que mudaram o conteúdo: (1) o app mobile mostra o `origin` do challenge na tela de aprovação (`approval_screen.dart`) — então o TruthID dá proteção real contra phishing, não só "confia no usuário"; (2) o mobile recusa `callbackUrl` que não seja `https://` (mesmo arquivo); (3) os 3 SDKs leem estado on-chain via um RPC escolhido pelo integrador (público por padrão) sem nenhuma prova client-side de que esse RPC não está mentindo — risco real de confiança que não estava em nenhum doc ainda; (4) a chave do device só existe via Android Keystore/iOS Secure Enclave, sem fallback em texto puro (`device_key_service.dart`); (5) `RecoveryManager.proposeRecovery` reverte com `GuardiansNotConfigured` se a identidade nunca configurou guardians — sem esse passo prévio, perda do controller é permanente, sem nenhum caminho alternativo. Estrutura da página: tabela "What TruthID protects against" (11 mecanismos reais, cada um linkado ao achado de auditoria correspondente quando aplicável), seção "What TruthID does not protect against" com admonition `:::danger[...]` pro caso de guardians não configurados + 6 bullets honestos (device comprometido, RPC não-confiável, sem auditoria externa, contratos imutáveis, segurança do backend do integrador é responsabilidade dele, engenharia social), e "Audit status" linkando pra tabela de achados em `project/ARCHITECTURE.md` (Sessão 24/Fase 6) e pro GitHub Security tab. Aproveitado pra corrigir duas pontas soltas que ficaram “coming soon” desde sessões anteriores: `intro.mdx` linkava pro `sdk/README.md` dizendo que a referência de API dedicada "está chegando" (já existia desde a 8.5-8.7, nunca foi atualizado) e `quickstart.mdx` tinha "Security model — coming soon" nos Next steps — os dois agora linkam pras páginas reais. Link "Security" adicionado ao footer (`docusaurus.config.ts`), mesmo padrão usado quando Quickstart foi criado (8.4). `npm run build` sem erros; revisão visual via Playwright (mesmo processo das etapas anteriores) confirmou o admonition vermelho renderizando corretamente, a tabela legível no tema dark, e o link novo no footer.
- [x] 8.9 — Página de contratos: endereços, ABIs, links Basescan, custo por operação. Implementado na Sessão 33 (continuação): nova página `docs/docs/contracts.mdx` (sidebar_position 5, depois de Security Model). Releitura dos 4 contratos reais (`contracts/src/*.sol`) pra montar a tabela "Contract reference" (função → quem pode chamar → propósito) sem reinventar a lógica já explicada em `intro.mdx`/`security.mdx`. Achado-chave da etapa: `forge test --gas-report` dá números reais de gas por função a partir dos 120 testes Foundry já existentes — usado pra montar a tabela "Cost per operation" (min/médio/máximo em gas por operação, ex. `registerDevice` ~204k gas mediano) em vez de estimar. Conversão pra ETH feita só como nota textual (não coluna por linha), usando o gas price de ~0,011 gwei observado no deploy de mainnet (Sessão 25), com aviso explícito de que o preço de gas flutua — linkado pro gas tracker ao vivo da Basescan (`basescan.org/gastracker`, confirmado funcionando via `curl`, apesar de uma resposta 302 transitória na primeira tentativa). Seção "Getting the ABI" explica que não existe pacote npm/pip/gem com o ABI completo (os SDKs só embutem fragmentos mínimos por função) — caminho real é a aba "Contract" da Basescan (contratos verificados) ou compilar a partir do código-fonte (`forge build`, gera `out/` que é gitignored). Cross-links adicionados: `intro.mdx` (seção de endereços agora linka pra essa página), `security.mdx` (Next steps), footer (`docusaurus.config.ts`, mesmo padrão das etapas anteriores). `npm run build` sem erros; revisão visual via Playwright confirmou as tabelas, o admonition `:::info[...]` explicando a variação de gas do `configureGuardians`, e os links do footer/sidebar.
- [x] 8.10 — Identidade visual: logo, cores, tipografia aplicados ao site. Implementado na Sessão 33 (continuação): usuário decidiu que cores (ciano `#4DD0E1`/dark `#0B0F14`) e tipografia (Space Grotesk+Inter), já aprovadas na 8.2, não precisavam ser revisitadas — escopo ficou só no logo. Antes de redesenhar, 3 evoluções do escudo+check (`A` costura vertical sutil, `B` vértice do check como nó preenchido, `C` silhueta angular) foram desenhadas em SVG e renderizadas lado a lado (grande/navbar/favicon) via Playwright pra comparação visual real, não só descrição em texto. Decisão do usuário: manter o escudo+check exatamente como estava (Sessão 31) — só remover o status de "provisório", sem nenhuma mudança de arquivo. **Achado relevante levantado nesta sessão, fora do que tinha sido pedido**: o card social (`docusaurus-social-card.jpg`, usado nas meta tags `og:image`/`twitter:image` — a imagem que aparece quando alguém compartilha o link do site) ainda era o dinossauro padrão do template Docusaurus, nunca substituído desde o scaffold da 8.1 — o mesmo personagem que o usuário já tinha rejeitado pra landing page na 8.2. Usuário confirmou que valia corrigir antes de fechar a etapa: card novo criado (fundo dark com o mesmo glow do hero, logo escudo+check, "TruthID" em Space Grotesk com o "ID" em ciano, tagline idêntica à do `docusaurus.config.ts`), renderizado via Playwright em 1200x630 (tamanho padrão de OG image) e revisado visualmente antes de aplicar. Arquivo renomeado de `docusaurus-social-card.jpg` pra `social-card.jpg` (`git mv`, sem branding do template no nome) e `docusaurus.config.ts` atualizado pra apontar pro novo nome. `npm run build` sem erros; confirmado via `grep` no HTML gerado que `og:image`/`twitter:image` apontam pra URL absoluta correta (`https://masterlxz.github.io/truthid/img/social-card.jpg`).
- [x] 8.11 — Deploy em produção (GitHub Pages ou domínio customizado). Já era automático desde a etapa 8.1 (Action `deploy-docs.yml` dispara em todo push na main que toque `docs/`) — sem domínio customizado, decisão consciente da 8.1 (GitHub Pages grátis). Fechamento formal na Sessão 33 (continuação): confirmado via API do GitHub (`api.github.com/repos/masterlxz/truthid/actions/runs`, sem autenticação) que a run do último push (`d144a26`, fix do social-card) completou com `success`; confirmado via `curl` que o site em produção reflete tudo da Fase 8 — home (200), `/docs/security` e `/docs/contracts` (200, via redirect normal de barra final), e o card social novo (`img/social-card.jpg`, 200, 1200x630, conteúdo correto) com a meta tag `og:image` apontando pra URL certa. **Fase 8 — Documentação Web: CONCLUÍDA** (etapas 8.1 a 8.11).

---

### Fase 9 — Identidade Visual: Mobile & Desktop

**Objetivo**: aplicar a identidade visual já aprovada no site de docs (Fase 8) aos dois apps reais — hoje ambos usam tema 100% padrão de template, sem nenhuma marca do TruthID.

**Estado de partida (levantado na Sessão 33)**:
- **Mobile** (Flutter): `ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo))` — Material padrão, sem fonte customizada, sem logo, AppBar genérica. 5 telas: `approval_screen.dart`, `devices_screen.dart`, `scan_screen.dart`, `sessions_screen.dart`, `show_device_qr_screen.dart` (~920 linhas).
- **Desktop** (Tauri+React): `App.css` é literalmente o template padrão do `create-tauri-app` (logos de hover do Vite/React/Tauri, fundo claro com fallback de dark mode genérico) — nenhuma linha de marca própria. 5 componentes + shell: `ConnectWallet.tsx`, `CreateIdentity.tsx`, `ManageDevices.tsx`, `DesktopDevice.tsx`, `ActiveSessions.tsx`, `App.tsx` (~920 linhas).

**Decisões já tomadas (Sessão 33, antes de iniciar)**:
- Reaproveitar a identidade do site (não abrir nova rodada de propostas): paleta dark `#0B0F14`/ciano `#4DD0E1`, tipografia Space Grotesk (headings) + Inter (corpo), logo escudo+check
- Mobile abre sempre no tema dark, igual ao site — sem alternância por tema do sistema (decisão consciente: não implementar uma segunda paleta clara)
- O logo de linha fina (pensado pra fundo escuro do site) continua dentro dos apps; uma versão preenchida/com fundo sólido é criada separadamente só para os ícones de app (launcher Android/iOS, ícone de janela do Tauri), que ficam sobre fundos arbitrários (wallpaper, dock)

**Etapas**:
- [x] 9.1 — Fundamentos compartilhados: paleta/tipografia adaptadas pra cada stack. Implementado na Sessão 33 (continuação): **mobile** — decisão consciente de NÃO usar o pacote `google_fonts` (que baixa a fonte da rede em tempo de execução, com cache); em vez disso, os arquivos `.ttf` reais de Space Grotesk e Inter (variable fonts, licença OFL) foram baixados direto do repositório oficial `google/fonts` no GitHub e bundlados em `mobile/assets/fonts/` (+ `OFL-*.txt` de cada uma, exigido pela licença) — motivo: um app de autenticação não deveria depender de rede pra renderizar a UI corretamente, mesma lógica de "sem servidor" já aplicada ao resto do projeto. `pubspec.yaml` ganhou uma seção `fonts:` declarando `SpaceGrotesk` (weights 500/600/700) e `Inter` (weights 400/500/600/700), cada um apontando pro mesmo arquivo variável com `weight:` diferente — forma documentada do Flutter de usar variable fonts. **Desktop**: os tokens de cor/fonte ficam direto no `:root` do `App.css` (mesmo padrão do `docs/src/css/custom.css`) — entregue junto da etapa 9.2, já que pra essa stack o arquivo de tema global E os tokens são o mesmo arquivo, não fazia sentido separar em 2 commits.
- [x] 9.2 — Desktop: tema global (`App.css`) — remove resíduos do template Vite/Tauri, aplica paleta dark+ciano, tipografia. Implementado na Sessão 33 (continuação): `App.css` reescrito do zero — era literalmente o CSS padrão do `create-tauri-app` (hover glow dos logos Vite/React/Tauri, fundo claro com fallback de dark mode genérico, nenhuma cor/fonte própria). Novo arquivo usa o mesmo `@import` do Google Fonts do site (Space Grotesk+Inter) e os mesmos tokens de cor (`#0B0F14` fundo, `#4DD0E1` acento ciano, `#1F2630` borda) via CSS custom properties — só que sempre dark, sem alternância por `prefers-color-scheme` (decisão já tomada antes de começar a fase: o app é 100% superfície própria do TruthID, não precisa de toggle). Resíduos removidos: `public/vite.svg`, `public/tauri.svg`, e as classes `.logo`/`.logo.vite:hover`/etc. (confirmado via grep que nenhum componente as referenciava). `index.html`: `<title>` trocado de "Tauri + React + Typescript" pra "TruthID", favicon trocado pro `logo.svg` real (escudo+check, copiado de `docs/static/img/logo.svg`). Validado com `npx tsc --noEmit` (sem erros) e visualmente via Playwright contra um `vite` dev server real (precisou de um `vite.config.ts` temporário com `cacheDir` alternativo — o `node_modules/.vite` do projeto tinha arquivos *root-owned* de uma sessão Docker anterior, sem permissão de escrita; arquivo temporário descartado depois, não committed).
- [x] 9.3 — Desktop: aplica o tema nos 5 componentes (`ConnectWallet`, `CreateIdentity`, `ManageDevices`, `DesktopDevice`, `ActiveSessions`) + shell do `App.tsx`. Implementado na Sessão 33 (continuação): `App.css` ganhou um pequeno conjunto de classes utilitárias (`.card`, `.status-badge`/`.status-badge--active`/`.status-badge--revoked`, `.muted`, `.error-text`, `.address`, `.field`, `.actions-row`, `.tabs`) — os 5 componentes e o shell do `App.tsx` foram reescritos pra usar essas classes em vez de `style={{...}}` inline e texto puro. Mudanças de conteúdo (não só estilo): emojis de status (✅/❌/⬜) trocados por badges coloridos (`status-badge--active` verde, `status-badge--revoked` neutro); `<hr/>` entre seções trocado por `.card` com borda própria (cada device/sessão agora é um cartão, não uma lista de texto separada por linha horizontal); `style={{ color: "red" }}` (3 ocorrências, todas hardcoded) trocado por `.error-text` (usa a variável de cor do tema). Nenhuma mudança de lógica/hooks — só estrutura JSX e classes. Validado com `npx tsc --noEmit` (sem erros) e visualmente via Playwright (estado "carteira desconectada", único alcançável sem mockar uma extensão de wallet de verdade — os demais estados, descritos em código, ficam pra validação manual na 9.8).
- [x] 9.4 — Desktop: ícone da janela. Implementado na Sessão 33 (continuação): logo de linha fina não funciona como ícone de app (pouco contraste em fundo arbitrário) — decisão já tomada antes da fase de criar uma variante preenchida só pra ícones. Desenhada via SVG (escudo ciano `#4DD0E1` sólido + check `#0B0F14` vazado por cima, fundo navy full-bleed 1024×1024) e revisada visualmente em 3 tamanhos antes de aplicar. Aplicada com `npx tauri icon <fonte.png>` — CLI oficial do Tauri que gera todos os formatos por SO a partir de uma única imagem-fonte (substituiu os ícones padrão do template em `src-tauri/icons/`: `.ico`/`.icns`/`.png` em vários tamanhos). Achado: o comando também gera por padrão pastas `icons/android/` e `icons/ios/` (assets pra Tauri Mobile) — removidas, já que o mobile deste projeto é Flutter, não Tauri Mobile; `tauri.conf.json` não referencia nenhum dos dois caminhos.
- [x] 9.5 — Mobile: tema global. Implementado na Sessão 33 (continuação): novo arquivo `mobile/lib/theme.dart` define `AppColors` (mesmos tokens do site/desktop — fundo `#0B0F14`, superfície `#111820`, acento `#4DD0E1`, mais variantes semânticas success/danger/warning/info pra status que os 5 screens já usavam em cores hardcoded) e `appTheme` (`ThemeData` completo: `ColorScheme.dark` explícito em vez de `ColorScheme.fromSeed` — fromSeed gera uma paleta tonal derivada algoritmicamente que não bateria com os hex exatos da marca; `textTheme` com headings em `SpaceGrotesk` e corpo em `Inter`; temas de `AppBar`, `BottomNavigationBar`, `Card`, botões (elevated/outlined/text), `Chip`, `SnackBar`, `InputDecoration`). `main.dart` atualizado pra usar `theme: appTheme` em vez do `ColorScheme.fromSeed(seedColor: Colors.indigo)` padrão, e a `AppBar` da tela raiz teve o `backgroundColor: Theme.of(context).colorScheme.inversePrimary` (padrão do template "contador" do Flutter) removido — agora herda do `appBarTheme` central. Validado com `./dev.sh flutter analyze` (sem erros) via o setup Docker do projeto (achado: invocação correta é `./dev.sh flutter <comando>`, não `./dev.sh <comando>` — o script não prefixa "flutter" sozinho).
- [x] 9.6 — Mobile: aplica o tema nas 5 telas + AppBar/bottom navigation. Implementado na Sessão 33 (continuação): as 5 telas usavam cores de Material claro hardcoded (`Colors.grey.shade50-300`, `Colors.green/red/blue/amber` em vários shades) espalhadas pelo código — confirmado via grep que NENHUMA tinha sido pega só pelo tema global da 9.5, porque eram valores literais, não `Theme.of(context)`. Todas substituídas pelos tokens semânticos de `AppColors` (success/danger/warning/info + textMuted/surfaceAlt). As 3 ocorrências restantes de `backgroundColor: Theme.of(context).colorScheme.inversePrimary` nas AppBars (`approval_screen.dart`, `show_device_qr_screen.dart` — a 3ª, em `main.dart`, já tinha sido removida na 9.5) também removidas, herdando do `appBarTheme` central. **Bug de correção (não só estética) achado e corrigido**: o QR code em `show_device_qr_screen.dart` (`QrImageView`) não tinha fundo explícito — em um tema sempre-claro isso nunca importou, mas no tema dark um QR com módulos pretos ficaria sobre um fundo quase preto (`#0B0F14`), ilegível pra câmera de qualquer dispositivo. Corrigido com um `Container` branco explícito por trás do QR. Validado com `./dev.sh flutter analyze` (sem erros) e grep confirmando zero `Colors.grey/red/green/blue/amber/indigo` remanescentes em `lib/screens/`. Confirmação visual de verdade (rodando o app, não só analisando o código) fica pra etapa 9.8, que já previa rodar os dois apps juntos no final da fase.
- [x] 9.7 — Mobile: ícone do app (launcher icon Android/iOS). Implementado na Sessão 33 (continuação): reaproveitada a mesma imagem-fonte da etapa 9.4 (escudo ciano sólido + check vazado, fundo navy 1024×1024 — já aprovada pelo usuário pro ícone do desktop, mesmo raciocínio de "logo de linha fina não funciona em fundo arbitrário" se aplica aqui), salva em `mobile/assets/icon/app_icon.png`. Pacote `flutter_launcher_icons: ^0.14.4` adicionado como dev dependency + bloco de configuração no `pubspec.yaml` (`android: true`, `ios: true`, sem ícone adaptativo — o projeto nunca teve esse recurso, mantido como estava). Gerado com `dart run flutter_launcher_icons` (achado de uso do `dev.sh`: o comando certo é `./dev.sh dart run ...`, não `./dev.sh flutter dart run ...` — `dart` é um executável próprio no `PATH` do container, não um subcomando do `flutter`). Substituiu os 5 `mipmap-*/ic_launcher.png` do Android (sem variante "round", o projeto nunca teve) e o conjunto completo `AppIcon.appiconset` do iOS (incluindo tamanhos legados que o projeto não tinha, como 50x50/57x57/72x72 — gerados pelo pacote por padrão, mantidos por não terem custo nenhum manter).
- [x] 9.8 — Revisão visual final: rodar os dois apps de verdade. Implementado na Sessão 33 (continuação):
  - **Desktop**: já validado durante a 9.3 (estado "carteira desconectada", via `vite` dev server real + Playwright — fundo dark, título em Space Grotesk, botão com borda ciano, hover preenchendo cyan com texto escuro).
  - **Mobile**: achados os volumes Docker `emu_avd`/`emu_sdk_extra` de uma sessão anterior (AVD `test` já criado + system image Android 34 `google_apis/x86_64` já baixada, ~8GB total) — sem script no repo pra montar o emulador, então construída uma imagem temporária (`FROM mobile-flutter:latest` + `sdkmanager "emulator"`, descartada ao final) e o container rodado com `--device=/dev/kvm`, os dois volumes montados nos paths esperados (`~/.android/avd` e `$ANDROID_SDK_ROOT/system-images`), headless (`-no-window -gpu swiftshader_indirect`). Boot completo confirmado via `adb shell getprop sys.boot_completed`. `flutter build apk --debug` (via `./dev.sh`) gerou o APK real, instalado no emulador (precisou `adb uninstall` primeiro — a instalação anterior tinha assinatura de debug diferente, de outra máquina) e testado de verdade: tela inicial (Dispositivos, não pareado), aba Sessões (vazio, não pareado) e a tela de pareamento/QR — essa última confirmando visualmente o fix da 9.6 (fundo branco por trás do QR, sem o qual ficaria ilegível no tema dark). Tela de aprovação de login (`approval_screen.dart`) **não** testada ao vivo — abrir ela de verdade exige simular um scan de QR pela câmera virtual do emulador, um desvio grande pra esse checkpoint; validada só por revisão sistemática de código (mesmo processo das outras 4 telas) + `flutter analyze`.
  - Ambiente do emulador inteiramente descartado ao final (container, imagem temporária, APK) — os dois volumes cacheados (`emu_avd`/`emu_sdk_extra`) preservados pra acelerar a próxima vez.
- **Fase 9 — Identidade Visual: Mobile & Desktop: CONCLUÍDA** (etapas 9.1 a 9.8).

---

### Fase 10 — Ledger via USB direto (Desktop, Rust)

**Objetivo**: conectar uma Ledger física ao desktop sem depender do celular/WalletConnect — comunicação USB feita no lado Rust do Tauri, exposta ao frontend via comando.

**Contexto da decisão (Sessão 33→34)**: na Sessão 33, testando o app empacotado de verdade, confirmou-se que `navigator.hid`/`navigator.usb` são `false` no WebKitGTK (motor de webview do Tauri no Linux) — WebHID/WebUSB simplesmente não existem nesse motor, então um conector Ledger em JS puro é inviável. Três caminhos ficaram na mesa (documentar Ledger Live via WalletConnect / implementar cliente Rust / deixar de lado). **Decisão (Sessão 34): implementar de verdade, opção (b)** — mesmo padrão já usado pelos comandos `get_or_create_device_key`/`sign_challenge` (etapa 3.7), que também fazem trabalho sensível no lado Rust em vez de depender de uma API do navegador.

**Fluxo de UX desejado**:
1. Usuário clica em "Conectar Ledger" no desktop.
2. App entra em polling, esperando a Ledger responder (ritmo planejado: ~1x/s).
3. Enquanto não detecta, mostra instrução contextual — ex. "Conecte sua Ledger, desbloqueie com o PIN no dispositivo e abra o app Ethereum" — variando a mensagem conforme o tipo de erro retornado (não conectada / bloqueada / app errado aberto).
4. **O PIN nunca passa pelo app TruthID** — é digitado nos botões físicos da própria Ledger. Proposital: protege contra malware no computador que tente capturar o PIN.
5. Ao detectar o app Ethereum aberto e desbloqueado, o comando lê o endereço e o fluxo segue igual aos outros conectores de wallet já existentes (`wagmi`).

**Arquitetura validada (não decidida ainda em código, só no desenho)**:
- Crate `hidapi` para abrir o dispositivo USB — enumerar pelo `vendor_id` da Ledger (`0x2c97`), ler/escrever bytes brutos.
- Protocolo APDU para falar com o app Ethereum da Ledger: frame `CLA (0xE0 p/ Ethereum) | INS | P1 | P2 | LC | DATA`; resposta vem com os dados + 2 bytes de status (`0x9000` = sucesso).
- Novo comando Tauri (`#[tauri::command]`), exposto via `invoke()`, no mesmo arquivo/padrão dos comandos de device key já existentes (`src-tauri/src/`, etapa 3.7).
- Frontend faz polling chamando esse comando repetidamente até sucesso, trocando a mensagem de instrução conforme o erro retornado.

**Pontos de atenção multiplataforma (Linux, macOS, Windows)**:
- **Linux**: pode precisar de regra `udev` pra acesso sem root ao `vendor_id` da Ledger — checar se a própria Ledger documenta a regra oficial.
- **macOS**: o app empacotado pode precisar de uma entitlement específica pra acesso USB/HID na hora de assinar o binário (sandboxing).
- **Windows**: geralmente mais simples, mas pode conflitar se o Ledger Live estiver aberto ao mesmo tempo, disputando o mesmo dispositivo.
- `hidapi` tem componente nativo em C — confirmar que os runners do GitHub Actions (`build.yml`, etapa 3.8, já cobre os 3 SOs) têm as dependências de sistema necessárias pra compilar essa parte.
- Permissão/sandboxing só dá pra validar de verdade em máquina real de cada SO — CI não simula isso 100%.

**Etapas**:
- [x] 10.1 — Detectar Ledger plugada via `hidapi` (enumerar por `vendor_id` 0x2c97), comando Tauri que retorna se o dispositivo foi encontrado. Implementado na Sessão 34: novo módulo `desktop/src-tauri/src/ledger.rs`, comando `is_ledger_connected` (enumera `HidApi::device_list()`, sem abrir o dispositivo). Achado de ambiente: faltava `libudev-dev`/`pkg-config` na imagem Docker do desktop pro `hidapi` linkar — corrigido no `Dockerfile`, numa camada própria *depois* da instalação de Rust/`tauri-cli` (camadas caras), pra não invalidar o cache delas a cada rebuild futuro. `cargo check` validado dentro do container. Ainda não testado contra uma Ledger física de verdade (sem botão na UI ainda) — fica pra etapa 10.8.
- [x] 10.2 — Implementar o protocolo APDU básico para o app Ethereum (montar frame, abrir conexão, ler resposta + status `0x9000`). Implementado na Sessão 34: transporte HID da Ledger (não é só o APDU cru — um relatório HID tem 64 bytes fixos, então a Ledger fatia o APDU em pacotes com canal `0x0101`+tag `0x05`+sequência, e só o 1º pacote leva o tamanho total). `open_ledger_device` (abre por `path` o primeiro device com o vendor_id certo), `write_apdu`/`read_apdu_response` (fatiamento/remontagem) e `check_status` (separa os 2 bytes finais — status word — e confere `0x9000`). Nenhuma dessas funções é chamada por um comando Tauri ainda (isso é a 10.3, que vai montar o APDU real de "pedir endereço" e expor pro frontend) — `cargo check` mostra avisos de "função nunca usada", esperado nesse ponto. **Risco real não resolvido**: o byte de "report ID" e o exato formato de pacote variam um pouco entre Linux/macOS/Windows na prática — a implementação segue o protocolo documentado publicamente (ex. `@ledgerhq/hw-transport-node-hid`), mas só uma Ledger física confirma se está certo (etapa 10.8).
- [x] 10.3 — Comando Tauri que retorna o endereço Ethereum da Ledger, distinguindo os 3 estados de erro (não conectada / bloqueada / app errado aberto). Implementado na Sessão 34: `build_get_address_apdu` monta o APDU `GET_ADDRESS` (CLA `0xE0`, INS `0x02`) do app Ethereum com o caminho de derivação padrão `m/44'/60'/0'/0/0` (conta 0), em modo silencioso — P1 sem confirmação na tela, necessário porque o frontend vai chamar isso em polling (~1x/s, etapa 10.4); confirmar na tela a cada poll não faria sentido. `parse_get_address_response` extrai só o endereço da resposta (ignora a chave pública, que vem junto mas não é usada aqui). `classify_error` traduz status words conhecidos em 3 rótulos (`not_connected`, `locked`, `wrong_app`) que a 10.4 vai usar pra trocar a mensagem de instrução. Novo comando `get_ledger_address` registrado no `lib.rs`. `cargo check` limpo, sem avisos (todas as funções da 10.1/10.2 agora são usadas). **Os status words de `locked`/`wrong_app` ainda não foram confirmados contra uma Ledger física** — só documentados publicamente; fica pra etapa 10.8 junto com o resto.
- [x] 10.4 — Frontend: botão "Conectar Ledger" + polling (~1x/s) + mensagens de instrução condicionais por estado. Implementado na Sessão 34: novo componente `desktop/src/components/ConnectLedger.tsx` (não usa wagmi — a Ledger não é um connector injetado, é um comando Tauri direto), com 3 estados (parado/procurando/achou) e um dicionário traduzindo `not_connected`/`locked`/`wrong_app` pra instrução em português. Plugado dentro de `ConnectWallet.tsx`, ao lado dos outros botões de conectar. `npx tsc --noEmit` limpo; validado visualmente com Playwright contra um `vite` dev server real (mesmo workaround de `cacheDir` temporário da etapa 9.2, por causa do `node_modules/.vite` root-owned) — confirmado que o botão aparece corretamente e que clicar nele entra no estado de polling com a mensagem + botão "Cancelar". Fora do Tauri (browser puro, sem `window.__TAURI_INTERNALS__`), o `invoke` lança um erro diferente do esperado (`TypeError: Cannot read properties of undefined`) — confirmado que o fallback genérico da UI (`Aguardando Ledger... (${status})`) absorve isso sem quebrar a tela, mas o teste real do fluxo de sucesso (achar o endereço) só é possível dentro do app Tauri empacotado, com uma Ledger física (etapa 10.8). Ajuste de CSS no caminho: `ConnectLedger` numa `.actions-row` própria, separada da dos outros botões — colocar tudo na mesma linha flex espremia os botões de carteira em texto de 3 linhas.
- [x] 10.5 — Integração com o fluxo de wallet existente (paridade com os outros conectores já usados pelo resto do app). Implementado na Sessão 35: o usuário escolheu explicitamente o escopo "paridade completa" (assinatura real, não só leitura de endereço) entre as duas opções discutidas. Três partes:
  - **Rust** (`ledger.rs`): novo comando `sign_ledger_transaction(unsigned_tx_hex)`. Reaproveita o transporte HID e o `classify_error` já existentes (10.1-10.3); só adiciona o protocolo de assinatura em si: `build_sign_tx_apdus` fatia a transação serializada (RLP, vinda do frontend) em múltiplos APDUs `INS_SIGN` (0x04) de até 150 bytes de dado cada — o 1º carrega o caminho de derivação + início da tx, os seguintes (`P1` = "continuação") só o resto —, mesmo limite documentado publicamente pelo `@ledgerhq/hw-app-eth`. `parse_sign_tx_response` extrai `v`/`r`/`s` do último APDU e devolve no mesmo formato de string única (`0x`+r+s+v, v na convenção 27/28) que `sign_challenge` já usa, em vez de inventar um formato novo só pra Ledger. `encode_derivation_path` foi extraído do `build_get_address_apdu` (10.3) pra ser reusado aqui também. `cargo check` limpo, sem avisos.
  - **Frontend — connector customizado** (`desktop/src/connectors/ledger.ts`, novo arquivo): em vez de só mostrar o endereço achado, virou um `Connector` de verdade da `wagmi` (`createConnector`), no mesmo "formato" dos conectores prontos (`injected`/`walletConnect`) — é isso que dá paridade real. `connect()`/`getAccounts()`/`getChainId()` chamam `get_ledger_address` (já existia). A parte nova é `getProvider()`: devolve um provider EIP-1193 customizado que trata `eth_chainId`/`eth_accounts` direto e, pra `eth_sendTransaction`, monta um `walletClient` interno da `viem` com uma conta local (`toAccount`) cujo `signTransaction` serializa a transação, manda pro Rust assinar (`sign_ledger_transaction`) e reserializa com a assinatura — reaproveita toda a lógica de preenchimento de nonce/gas/taxas da própria `viem` em vez de reimplementar isso à mão. `signMessage`/`signTypedData` lançam erro (nada no app usa hoje). O transporte RPC é o mesmo já configurado em `wagmi.ts` (`config.transports`), sem duplicar lista de RPC.
  - **Frontend — encaixe na UI existente**: `ledger` registrado no array `connectors` de `wagmi.ts` (pra entrar no `useAccount()`/`useWriteContract()` global, igual aos outros). `ConnectWallet.tsx` filtra esse connector do loop genérico de botões (pra não duplicar com o botão dedicado). `ConnectLedger.tsx` manteve o polling com mensagens de instrução (10.4), mas agora, ao achar o dispositivo, chama `connectAsync({connector: ledger})` da própria `wagmi` em vez de só guardar o endereço num estado local — isso é o que faz o resto do app (`CreateIdentity`, `ManageDevices`, `ActiveSessions`, `DesktopDevice`, todos via `useWriteContract`) passar a "ver" a Ledger como qualquer outra wallet conectada, sem precisar saber que é uma Ledger.
  - Validado por `cargo check` (limpo) e `npx tsc --noEmit` (limpo, depois de alguns ajustes de tipagem — a assinatura genérica `connect<withCapabilities>` da `wagmi`, pensada pra ERC-5792/batch de chamadas, não é inferida automaticamente a partir de um `if/else` em tempo de execução; precisou de um cast explícito documentado no código, já que nada no app usa `withCapabilities`). Visual com Playwright contra o `vite` dev server (mesmo workaround de `cacheDir` das etapas anteriores): só 1 botão "Conectar Ledger" aparece (sem duplicata), e o estado de polling/cancelamento se comporta igual à 10.4. **Não testado**: o fluxo de assinatura de verdade (`sign_ledger_transaction` end-to-end) exige hardware real — os status words de erro do SIGN_TX e o formato exato da resposta (byte de `v`) ainda não foram confirmados contra uma Ledger física, mesma ressalva já registrada pras etapas 10.1-10.4. Fica pra etapa 10.8, junto com o resto.
- [x] 10.6 — Multiplataforma: regra udev (Linux), entitlement USB/HID (macOS), checar conflito com Ledger Live aberto (Windows). Implementado na Sessão 37: **Linux** — arquivo `desktop/linux/99-ledger.rules` criado com `TAG+="uaccess"` pra `SUBSYSTEMS=="usb"` e `KERNEL=="hidraw*"` com `ATTRS{idVendor}=="2c97"` — cobre todos os modelos Ledger; instrução de instalação (`sudo cp` + `udevadm reload`) incluída como comentário no arquivo. **Windows** — erro `access_denied` adicionado ao `classify_error` do Rust para quando `HidApi::open_path` retorna "access denied/permission" (conflito com Ledger Live, que toma acesso exclusivo); mensagem correspondente adicionada ao dicionário de instruções do `ConnectLedger.tsx`. **macOS** — `tauri.conf.json` sem sandbox configurado (App Sandbox é opt-in, não ativado); `hidapi` no macOS usa `IOHidManager` via IOKit, framework público disponível pra qualquer processo sem entitlement específico — nenhuma alteração necessária.
- [x] 10.7 — Confirmar que `build.yml` compila a parte nativa do `hidapi` nos 3 SOs (CI). Implementado na Sessão 37: Linux — `libudev-dev` e `pkg-config` adicionados ao passo "Linux deps" do `build.yml` (são as dependências de sistema que o `hidapi` precisa pra linkar no Linux). macOS — `hidapi` usa `IOHidManager` (IOKit), framework embutido no SDK do macOS, sem dependência adicional a instalar. Windows — `hidapi` usa a API HID nativa do Windows (não precisa de pacote extra via Chocolatey/vcpkg). Ou seja: a única mudança necessária era o Linux; os outros dois SOs já compilam sem alteração.
- [x] 10.8 — Validação manual em máquina real de cada SO. **Linux validado na Sessão 36**: Ledger física conectada via USB, identidade `@masterlxz` criada e device desktop registrado em Base Mainnet end-to-end — confirma transporte HID, protocolo APDU, connector wagmi e fluxo de assinatura funcionando de verdade. macOS/Windows: deferred (sem hardware disponível no ambiente atual — "quando disponível" era a condição original, não bloqueante para fechar a fase).

---

### Fase 11 — Teste E2E Prático: Login, Revogação de Sessão e Device

**Status: CONCLUÍDA — Sessão 38 (2026-06-27)**

Todas as 4 etapas validadas ao vivo com Base Mainnet, Ledger física e app desktop real.

**Objetivo**: Validar de ponta a ponta o fluxo de autenticação real — não só o registro on-chain (já feito na Sessão 36), mas efetivamente criar uma sessão autenticada com o device registrado, revogar essa sessão, e revogar o device em seguida.

**Contexto de partida (pós-Sessão 36)**:
- Identidade `@masterlxz` (id=1, controller `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265`) criada em Base Mainnet
- Desktop device (`0x1073e02eB26b371Dd1f04BcC0b5fd76e7ae7fFDD`) registrado sob a identidade 1
- Chave privada do desktop em `$HOME/.truthid/device.key` (fallback do keyring)
- Servidor de exemplo TypeScript em `sdk/typescript/example/server.js` — já tem as rotas `GET /auth/challenge` e `POST /auth/verify` usando o SDK; é a base mais natural para esse teste

**Fluxo de login esperado (referência)**:
```
Desktop app                    Servidor exemplo (Express local)         Blockchain
     |                                    |                                 |
     |--- GET /auth/challenge ----------->|                                 |
     |<-- { challenge, nonce, ... } ------|                                 |
     |                                    |                                 |
     | assina challenge com sign_challenge|                                 |
     | (chave do device, Rust)            |                                 |
     |                                    |                                 |
     |--- POST /auth/verify ------------->|                                 |
     |   { challenge, signature,          |--- verifyAuthResponse() ------->|
     |     deviceAddress, identityId }    |   (SDK lê DeviceRegistry,       |
     |                                    |    SessionRegistry on-chain)    |
     |<-- { ok: true, sessionId } --------|                                 |
     |                                    |                                 |
     | SessionRegistry.createSession()    |                                 |
     |-----------------------------------------> on-chain                  |
     |                                                                      |
     SESSION CRIADA
```

**Etapas**:
- [x] 11.1 — Subir o servidor de exemplo local (`sdk/typescript/example/server.js`) e confirmar que `GET /auth/challenge` retorna um challenge válido. **CONCLUÍDO Sessão 38** — servidor rodando em localhost:3000, CORS adicionado.
- [x] 11.2 — Login real com o desktop: o desktop assina o challenge via `invoke("sign_challenge", ...)` com a chave do device registrado, envia `POST /auth/verify`. **CONCLUÍDO Sessão 38** — servidor retornou `{ "token": "c70882ad-d999-4ded-bc1c-c0d92931e905", "identityId": "1" }`. Device `0x0a0B7e76E331d83448F57640D8eE62438470438e` ativo on-chain confirmado.
- [x] 11.3 — Revogar a sessão criada: no tab "Login test", clicar em **Test Login** e depois em **Register session on-chain** (aguardar confirmação na Ledger). Navegar para "Active sessions", localizar a sessão pelo hash, clicar em Revoke. Confirmar que o badge muda para "Revoked". **CONCLUÍDO Sessão 38.**
- [x] 11.4 — Revogar o device desktop: navegar para "Dispositivos" (`ManageDevices.tsx`), localizar o device desktop e revogar. Confirmar que `isDeviceActive` retorna falso na blockchain. Tentar criar outro login com o mesmo device — deve falhar na etapa de verificação (`verifyAuthResponse()` checa o status do device no `DeviceRegistry`). **CONCLUÍDO Sessão 38** — servidor retornou `"Device is not active or has been revoked"`, confirmando que o SDK lê o estado on-chain corretamente.

**Pontos de atenção**:
- `sign_challenge` e `get_or_create_device_key` são comandos Tauri — só funcionam dentro do app Tauri empacotado (não no `vite` dev server puro). O teste de fato exige rodar com `npm run tauri dev` dentro do Docker (`./dev.sh`).
- `createSession` no `SessionRegistry` exige assinatura ECDSA do próprio device (auditoria, achado #2, corrigido na Sessão 24) — confirmar que o fluxo de login do desktop já monta essa assinatura ou implementar o que faltar.
- A revogação de sessão retorna `sessionId` apenas se o TruthID SDK foi configurado pra gravar isso localmente (os dados originais ficam no dispositivo — só o hash vai on-chain). Verificar onde o desktop guarda esses dados antes da etapa 11.3.
- Após revogar o device (11.4), o app vai mostrar "Não registrado" na tela de `DesktopDevice` — comportamento correto; documentar como ponto de validação visual.

---

---
## Fase 12 — Publicação & Release (próxima grande etapa)

**Objetivo**: empacotar tudo, assinar os binários e publicar o primeiro release público — desktop + mobile — via GitHub Releases, de forma que qualquer pessoa possa baixar e instalar.

### 12.1 — Keystore de assinatura do APK (pré-requisito bloqueante)

O Android exige que todo APK seja assinado com a mesma keystore para que atualizações funcionem. Se a keystore for perdida, o usuário precisa desinstalar e reinstalar o app (perde dados locais). **Deve ser feita uma única vez e a keystore guardada com muito cuidado.**

```bash
# Gerar a keystore (rodar uma vez, salvar em local seguro fora do repositório)
keytool -genkey -v \
  -keystore truthid-release.jks \
  -alias truthid \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

Onde guardar:
- Arquivo `.jks` — **nunca commitar no repositório** (git-ignored)
- Backup em local seguro (cofre de senhas, drive criptografado)
- Para o CI: encodar em base64 (`base64 truthid-release.jks`) e salvar como GitHub Secret (`KEYSTORE_BASE64`), junto com `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`

Configurar `mobile/android/app/build.gradle` para usar a keystore em release builds (via variáveis de ambiente que o CI injeta).

### 12.2 — Workflow CI para o APK (`.github/workflows/build-mobile.yml`)

O `build.yml` existente só constrói o desktop. Criar um workflow separado para o mobile que:
- Dispara no mesmo evento (`push` de tag `v*`)
- Usa `subosito/flutter-action@v2` com Flutter 3.44.x
- Decodifica o `KEYSTORE_BASE64` do GitHub Secret, configura as variáveis de assinatura
- Roda `flutter build apk --release`
- Faz upload do `app-release.apk` para o mesmo GitHub Release draft que o `build.yml` cria

Resultado: ao criar uma tag, o GitHub Actions entrega **5 arquivos** no release:
| Arquivo | Plataforma |
|---|---|
| `TruthID_linux_x86_64.AppImage` | Linux |
| `truthid_linux_amd64.deb` | Linux (Debian/Ubuntu) |
| `TruthID_windows_x64.msi` | Windows |
| `TruthID_macos_universal.dmg` | macOS |
| `TruthID_android.apk` | Android |

### 12.3 — Publicar o release

```bash
# Após todos os débitos (#14, #15, #16) estarem resolvidos e commitados:
git tag v1.0.0
git push origin v1.0.0
```

O GitHub Actions roda, constrói tudo, cria um release draft. Depois:
1. Abrir o draft no GitHub → escrever release notes
2. Publicar o release

**Instalação pelo usuário final (Android)**:
- Baixa o `.apk` do GitHub Releases
- No Android: Configurações → Segurança → "Instalar apps de fontes desconhecidas" (ou Instalar app desconhecido, dependendo da versão)
- Abre o `.apk` → instala
- Atualizações futuras: mesmo processo, o Android reconhece a mesma assinatura e faz update em cima

**Alternativa futura (mais fácil pro usuário)**: publicar na Google Play Store (exige conta de desenvolvedor, ~$25 taxa única) — o processo de build+assinatura seria o mesmo, só o destino muda.

### 12.4 — Atualizar o site de docs pós-release

- Adicionar seção "Download" na landing page (`docs/src/pages/index.tsx`) com links diretos para os binários do último release
- Ou usar a API do GitHub (`api.github.com/repos/masterlxz/truthid/releases/latest`) para mostrar os links dinamicamente sem atualizar o site a cada release

### Status das etapas

- [x] 12.1 — Gerar e guardar keystore de assinatura *(Sessão 47 — keystore gerada, 4 GitHub Secrets configurados, CI de release validado)*
- [x] 12.2 — Criar `build-mobile.yml` com CI de APK *(implementado na Sessão 45)*
- [x] 12.3 — Criar tag `v1.0.0` e publicar release *(Sessão 48 — tag criada, CI gerou 8 artefatos: .deb, AppImage, .rpm, .msi, .exe, .dmg, .app.tar.gz, .apk; release publicado no GitHub)*
- [x] 12.4 — Atualizar site com links de download *(Sessão 48 — seção "Download" adicionada à landing page com fetch dinâmico da GitHub API `releases/latest`)*

**Fase 12 concluída. TruthID v1.0.0 publicado.**


---
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

---
### Fase 14 — Smart Account (ERC-4337, Self-Funded)

**Objetivo**: substituir o EOA como controller da identidade por uma smart account ERC-4337. O usuário paga o próprio gás do celular sem precisar de wallet conectada. Nenhum dev/operador precisa manter hot wallet.

**Motivações**:
1. Celular (device key no Secure Enclave) assina UserOps localmente — sem MetaMask, sem wallet. Bundler público submete. Smart account paga do próprio saldo.
2. Projeto open source sem operador central: elimina o relayer/hot wallet que hoje é responsabilidade de quem deploya.

**Decisões travadas** (Sessão 52):
- Smart account base: fork do `SimpleAccount` (eth-infinitism, ERC-4337, ECDSA secp256k1)
- Sem Paymaster: auto-financiamento via depósito da smart account no EntryPoint
- Ledger = owner (assina qualquer UserOp). Devices = signers autorizados (bloqueados de chamar DeviceRegistry)
- Smart account mantém lista interna própria de devices autorizados (não consulta DeviceRegistry em `validateUserOp`)
- `createIdentity` passa a aceitar `address controller` explícito (endereço CREATE2 pré-computado)
- `emergencyWithdraw(address recipient)` na smart account, chamável só pelo RecoveryManager

**Regra de gas**: todo gas (mesmo de UserOps assinadas pelo Ledger) é debitado da smart account. O Ledger nunca precisa de ETH após o setup inicial.

**Setup inicial (único momento em que o Ledger age como EOA)**:
1. Ledger paga `createIdentity(username, smartAccountAddress)` — endereço pré-computado via CREATE2
2. Ledger deploya `TruthIDAccountFactory.deploy(ledgerAddress)` — smart account nasce no endereço previsto
3. Ledger transfere ETH para a smart account

A partir daí: Ledger assina UserOps off-chain → bundler submete → smart account paga.

**Nota de sequência**: a Fase 14 deve ser implementada **antes** das etapas 13.8 e 13.9 (Vault mobile e extensão), pois a 13.8 usa o fluxo de assinatura mobile que a 14 altera. Implementar na ordem 13.8 → 14 geraria retrabalho.

#### Etapas

- [x] 14.1 — Atualizar `IdentityRegistry.createIdentity` para aceitar `address controller` explícito (em vez de `msg.sender`). Atualizar validação e testes. *(Sessão 52 — 134 testes passando, `tsc --noEmit` limpo. Novo teste `test_CreateIdentity_ControllerCanDifferFromCaller` valida o caso smart account. Desktop passa `address` conectado como controller por ora — será substituído pelo endereço CREATE2 na etapa 14.7. **Gap de segurança aberto, achado no `/code-review` da Sessão 53**: `createIdentity` não valida que `msg.sender` tem autorização sobre o `controller` informado — qualquer um pode "ocupar" um endereço alheio (inclusive o CREATE2 pré-computado de uma smart account futura) chamando `createIdentity` primeiro, bloqueando o dono legítimo com `AddressAlreadyHasIdentity` até ele mesmo liberar via `transferController`. Confirmado, não corrigido — ver débito #17 na tabela de Débitos Técnicos de Arquitetura.)*
- [x] 14.2 — Implementar `TruthIDAccount.sol` (fork do SimpleAccount):
  - `address public owner` (Ledger)
  - `mapping(address => bool) public authorizedDevices`
  - `validateUserOp`: se signer == owner → libera tudo; se signer é device autorizado → bloqueia chamadas ao `DeviceRegistry`; senão rejeita
  - `addDevice(address device)` / `removeDevice(address device)` — só owner
  - Integração com EntryPoint já deployado na Base
  *(Sessão 53 — EntryPoint v0.7 (`PackedUserOperation`), zero imports/dependências, `forge build` e os 134 testes existentes passam. Checagem de malleability (low-s) adicionada manualmente no `ecrecover`, já que não há OpenZeppelin. Sem `addDeposit`/`getDeposit` — só `receive()` + pagamento just-in-time do prefund, suficiente pro padrão v0.7. Gap de segurança fechado: device autorizado não pode se autopromover via auto-chamada `execute(address(this), 0, addDevice(...))` — `validateUserOp` bloqueia, pra signers de tier device, qualquer `execute`/`executeBatch` cujo destino seja `address(this)` ou um destino bloqueado.
  **Correção pós-`/code-review`, mesma sessão**: o achado mais crítico do review apontou que a restrição original só bloqueava `deviceRegistry`/`address(this)` — um device continuava livre pra chamar `IdentityRegistry.transferController` (sequestro de identidade) ou `RecoveryManager.configureGuardians` (troca de guardiões), furando o próprio propósito do tier restrito. Corrigido substituindo a comparação de 2 endereços `immutable` por um mapping `blockedForDevices` semeado no constructor com `deviceRegistry`/`identityRegistry`/`recoveryManager`, extensível pelo owner via `blockDestinationForDevices`/`unblockDestinationForDevices` (sem precisar reimplantar a conta pra cada contrato privilegiado que surgir em fases futuras — a conta não tem proxy). `address(this)` continua checado à parte, fora do mapping, pra nunca poder ser desbloqueado. Também corrigidas 3 limpezas triviais sinalizadas no mesmo review (captura morta de `success`, atalho desnecessário do array `value` vazio em `executeBatch`, `abi.decode` decodificando campos não usados em `_isDeviceCallAllowed`) — na correção da última, uma extração via assembly introduzida por engano deixou de mascarar os bits superiores da palavra de calldata (risco de bypass do bloqueio de auto-chamada com calldata malicioso "sujo"); corrigido com uma máscara explícita antes de virar código commitado. Constructor de `TruthIDAccount` agora recebe `identityRegistry_`/`recoveryManager_` além dos parâmetros anteriores — a etapa 14.4 (factory) precisa passá-los. Débito aberto: considerar backport da checagem low-s pro `SessionRegistry.sol` por consistência.)*
- [x] 14.3 — Adicionar `emergencyWithdraw(address recipient)` ao `TruthIDAccount.sol`, chamável só pelo `RecoveryManager` (armazenado como imutável no construtor, mesmo padrão do `owner`) *(Sessão 54 — `recoveryManager` já existia como immutable desde a correção de segurança da 14.2, sem mudança de constructor. Transfere `address(this).balance` inteiro via `_call` já existente (reuso, sem duplicar lógica de revert). `forge build`/`forge fmt --check`/`forge test` (134 testes) limpos. **Gap aberto**: nada em `RecoveryManager.sol` chama essa função ainda — fica funcional mas inalcançável até alguma etapa futura conectar os dois lados; registrado como débito #19.)*
- [x] 14.4 — Implementar `TruthIDAccountFactory.sol` com CREATE2 determinístico *(Sessão 56 — factory em `contracts/src/TruthIDAccountFactory.sol`, testes em `contracts/test/TruthIDAccountFactory.t.sol`, deploy script atualizado).*
  - **Decisões tomadas**: salt = `keccak256(abi.encodePacked(owner_))` (apenas o endereço Ledger, padrão SimpleAccount); `createAccount(owner_)` é idempotente — se a conta já existe, retorna a instância existente sem reverter; endereço do EntryPoint v0.7 hardcoded (`0x0000000071727De22E5E9d8BAf0edAc6f37da032`) nos scripts de deploy, pois é o endereço oficial CREATE2-salt-zero do ERC-4337, idêntico em todas as EVM chains.
  - **Contrato `TruthIDAccountFactory`**: constructor recebe `entryPoint_`, `deviceRegistry_`, `identityRegistry_`, `recoveryManager_` e semeia os imutáveis; `createAccount(address owner_)` prevê o endereço via `getAddress`, checa `extcodesize`, e usa `new TruthIDAccount{salt: ...}(...)` se ainda não existe; `getAddress(address owner_)` replica a fórmula CREATE2 (`0xFF + deployer + salt + initCodeHash`) off-chain/on-chain; emite `AccountCreated` apenas no primeiro deploy real.
  - **Testes adicionados** (10 novos): endereço previsto == deployado; parâmetros da conta corretos; segunda chamada retorna a mesma conta e não emite evento novamente; owners diferentes geram contas diferentes; reverts de endereço zero no constructor; e teste de integração "ovo-e-galinha" com `IdentityRegistry` (pré-computa endereço → cria identidade apontando pra ele → depois deploya a conta → controller bate).
  - **`Deploy.s.sol` atualizado**: deploya `TruthIDAccountFactory` ao final do script, logando o endereço junto com `IdentityRegistry`/`DeviceRegistry`/`RecoveryManager`.
  - **Resultado**: `forge build`, `forge test` e `forge fmt` nos arquivos novos estão limpos; total de testes sobe de 137 para **147** (10 novos da factory + 3 existentes de `TruthIDAccount.t.sol`).
  - **`/code-review` (Sessão 57)**: nenhum bug de correção/segurança encontrado no código novo (matemática do CREATE2, ordem dos argumentos do constructor e idempotência conferidas). 6 nits de gas/limpeza registrados como débitos #21–#26 na tabela de Débitos Técnicos de Arquitetura; nenhum bloqueante pro commit.
  - **Próximo passo**: 14.5 — expandir testes gerais da `TruthIDAccount` (caminhos felizes de owner e device, `addDevice`/`removeDevice`, `emergencyWithdraw`) e da factory; ou 14.6 — utilitário off-chain de `computeSmartAccountAddress`.
- [x] 14.5 — Testes Foundry: `TruthIDAccount` (validateUserOp com ambos os tiers, addDevice/removeDevice, emergencyWithdraw, bloqueio de DeviceRegistry por device) + `TruthIDAccountFactory` (endereço determinístico, idempotência do deploy) *(Sessão 58 — `TruthIDAccount.t.sol` expandido de 3 para 44 testes; `TruthIDAccountFactory.t.sol` de 10 para 13. Total do projeto: 191 testes. Ver detalhes na Sessão 58 do Log de Sessões.)*
- [x] 14.6 — Utilitário off-chain (viem): função `computeSmartAccountAddress(ledgerAddress, factoryAddress)` que replica o CREATE2 off-chain. Integrado ao Desktop (Rust ou TS, a definir). *(Sessão 59 — implementado em TS com viem; `computeSmartAccountAddress()` async (lê immutables da factory via multicall) e `computeSmartAccountAddressSync()` para uso offline/pré-deploy; `TRUTHID_ACCOUNT_CREATION_CODE` extraído do artefato forge e hardcoded em `desktop/src/config/truthidAccount.ts`; 12 testes vitest passando; `tsc --noEmit` limpo. Total: 21 testes desktop passando.)*
- [x] 14.7 — Desktop: atualizar fluxo de criação de identidade *(Sessão 60)*
  - Pré-computar endereço da smart account via `computeSmartAccountAddressSync()` (CREATE2 off-chain)
  - `CreateIdentity.tsx` reescrito com fluxo de 3 transações sequenciais e barra de progresso
  - Tx 1: `IdentityRegistry.createIdentity(username, smartAccountAddress)` — Ledger paga como EOA
  - Tx 2: `TruthIDAccountFactory.createAccount(ledgerAddress)` — Ledger paga como EOA
  - Tx 3: `sendTransaction({ to: smartAccountAddress, value })` — Ledger paga como EOA
  - `App.tsx`: `getUsernameByController` consulta pelo `smartAccountAddress` (não mais pelo EOA)
  - Input de funding inicial (default 0.001 ETH) no form de criação
  - **Factory deployada**: Base Sepolia `0xbf097EC74d0Cc9b16D3d94EaCa62060d89A63b17` + Base Mainnet `0x062c577C26067d04bBEEaa953F8E7675fF4849ab`
  - **Script de deploy**: `DeployFactory.s.sol` criado (deploya só a factory, usando contratos existentes)
  - **Resultado**: `forge build` + `forge test` (191) + `npx tsc --noEmit` + `npm test` (21) — tudo limpo
- [x] 14.8 — Desktop: sincronizar lista de signers da smart account com o DeviceRegistry. *(Sessão 63 — implementação, testes e verificação end-to-end em Sepolia com o Ledger físico, todos concluídos: pareamento e revogação testados via o app real contra a identidade `teste` (identityId 1), device `0xfd23ed10b147F2557D0F072b1D10F6575C300F65` registrado/revogado com sucesso e `authorizedDevices` sincronizado nos dois sentidos (`true` após parear, `false` após revogar). Ver Log de Sessões, Sessão 63, para o desenho completo e a descoberta de que o pareamento já estava quebrado para identidades smart-account antes desta correção. Mobile fica de fora desta etapa — depende da 14.9, que introduz UserOps de verdade.)*
- [x] 14.9 — Mobile: atualizar fluxo de assinatura de transações (ex: `createSession`) para UserOps. **Quebrada em mini-etapas (Sessão 63) porque é bem mais pesada que a 14.8** — o celular é signer tier "device", não `owner`, então não tem o atalho de transação direta que a 14.8 usou; é obrigatório passar pela UserOperation de verdade via um bundler. Cada sub-etapa abaixo deve caber numa sessão pequena.
  - [x] 14.9.1 — Decidido: **Pimlico**. *(Sessão 63 — bundler "puro" sem exigir o paymaster deles (não usamos), suporta Base Mainnet e Base Sepolia, tier gratuito, software do bundler é open source (`alto`) — dá pra self-host no futuro sem depender deles. Decisão de design registrada: a URL do bundler deve ser **configurável** no mobile, não hardcoded — mesmo padrão do fallback de RPCs em `wagmi.ts` no desktop. Isso mantém aberta a porta pra quem quiser rodar o próprio bundler/nó um dia, sem exigir isso de todo mundo agora. Falta: dono do projeto criar conta em dashboard.pimlico.io e gerar a API key (ação de conta, fora do escopo de código) — pode ser feito quando conveniente, não bloqueia 14.9.2. Onde/como guardar a chave (arquivo local gitignored vs `--dart-define`) fica pra quando a 14.9.3 (cliente do bundler) for implementada de fato.)*
  - [x] 14.9.2 — Implementar em Dart (mobile) o encoding de `PackedUserOperation` + o cálculo do `userOpHash` (EIP-4337 v0.7). Funções puras, sem rede. Testar contra vetores conhecidos (dá pra gerar um "gabarito" usando `viem/account-abstraction` no desktop/Node e comparar byte a byte). *(Sessão 64 — `mobile/lib/utils/user_operation.dart`, testado contra 5 vetores gerados com `viem/account-abstraction` no Node do desktop, byte a byte. Ver Log de Sessões, Sessão 64.)*
  - [x] 14.9.3 — Cliente HTTP do bundler em Dart: `eth_estimateUserOperationGas`, `eth_sendUserOperation`, `eth_getUserOperationReceipt`. Só chamadas JSON-RPC, sem lógica de assinatura ainda. *(Sessão 65 — `mobile/lib/services/pimlico_bundler_client.dart`. Ver Log de Sessões, Sessão 65.)*
  - [x] 14.9.4 — Assinar o `userOpHash` com a device key e montar a assinatura no formato que `TruthIDAccount._validateSignature` espera (mesmo padrão `personal_sign`/r-s-v já usado hoje em `device_key_service.dart:signHash`). *(Sessão 66 — `mobile/lib/services/user_operation_signer.dart` + `copyWith` em `UserOperationV07`; reaproveita `DeviceKeyService.signHash` como já usado no `SessionRegistry`, sem migração pra Secure Enclave/Keystore (decisão explícita, registrada como débito #27). Vetor conhecido cruzado com `viem` (Node) e com `TruthIDAccount.validateUserOp` real (Foundry). Ver Log de Sessões, Sessão 66.)*
  - [x] 14.9.5 — Integrar tudo no fluxo real do `createSession`: construir calldata → montar UserOp → assinar → estimar gas → enviar → aguardar recibo. Ponta a ponta no app mobile, substituindo o fluxo atual (mobile assina, desktop/relayer submete). *(Sessão 67 — `mobile/lib/services/session_creator.dart` (novo) + `ApprovalScreen` reescrito pra chamar `SessionRegistry.createSession` ele mesmo via UserOp/bundler, em vez de só assinar e depender do relayer server-side do SDK. Achado que reenquadrou o escopo: o mobile nunca chamava `createSession` — quem sempre fez isso foi o backend do site via SDK (`registerSession`, `RELAYER_PRIVATE_KEY`). Ver Log de Sessões, Sessão 67, para o desenho completo e o débito aberto no SDK.)*
  - [x] 14.9.6 — Testar de ponta a ponta em Sepolia com a identidade/smart account de teste. *(Sessão 70 — completa: identidade, pareamento e sessão criados via UserOp real pelo mobile, sem relayer, confirmado on-chain via `getSession`. 5 contratos redeployados em Sepolia e Mainnet (débito #28) e mais 4 bugs reais encontrados e corrigidos em cascata (débitos #29–#32: salt CREATE2, resolução de username via eventos, keystore de debug efêmera, decodificação de struct com campo dinâmico no `web3dart`). **Nota**: a segunda parte do item original — "remover a dependência de `RELAYER_PRIVATE_KEY`" — não foi feita como remoção; o SDK ficou idempotente (`registerSession` checa on-chain antes de chamar `createSession`, retornando `alreadyRegistered: true` se o mobile já criou a sessão), mas a chave de relayer continua existindo em `sdk/typescript/example/server.js` e nos docs para o fluxo sem mobile. Ver Log de Sessões, Sessão 70, para o desenho completo.)*
- [x] 14.10 — Dashboard da smart account no Desktop (tab dedicada):
  - Saldo atual de ETH
  - Histórico de operações com custo por tipo (sessão, registro de device, vault)
  - Botão "Depositar" (mostra endereço + QR)
  - Botão "Sacar" (transfere ETH para endereço informado, assinado pelo Ledger)
  *(Sessão 71 — implementação + 18 testes novos, ver Log de Sessões. Falta só o checklist manual E2E com a Ledger física, pendente pro dono do projeto.)*
- [x] 14.11 — Deploy em Base Mainnet: `TruthIDAccount` (implementation) + `TruthIDAccountFactory`. Atualizar endereços em `contracts.ts`, mobile e SDKs. *(Coberto pelo redeploy completo da Sessão 70 — débito #28 — que já incluiu `TruthIDAccount`/`TruthIDAccountFactory` em Base Mainnet junto com os outros 3 contratos, com endereços propagados para `desktop/`, `mobile/` e os 3 SDKs. Este item ficou tecnicamente satisfeito como efeito colateral da correção do débito, não marcado até agora.)*
- [x] 14.12 — Atualizar site de docs: nova página explicando o modelo de smart account, custo de setup, como financiar. *(Sessão 74 — `docs/docs/smart-account.mdx`, nova página cobrindo os dois tiers de signer, o fluxo real de 4 passos do setup, custo do dia a dia via UserOp/bundler, financiamento, endereços de `TruthIDAccountFactory`/`EntryPoint` e uma tabela de gas real via `forge test --gas-report`. `contracts.mdx` e `intro.mdx` também atualizados — não mencionavam ERC-4337/smart account em lugar nenhum antes, e o `intro.mdx` chegou a descrever o modelo antigo de forma que contradizia a Fase 14. Ver Log de Sessões, Sessão 74.)*

---


---
### Fase 15 — Digital Identity Vault (documentos, endereços, cartões)

**O que é**: expansão do TruthID Vault (Fase 13) de um gerenciador de senhas para um **cofre de identidade digital completo**. Além de senhas, o usuário pode armazenar e preencher automaticamente:

- **Documentos** (PDFs, imagens de RG/CNH/passaporte, contratos, qualquer arquivo — cifrado, com limite de tamanho a definir)
- **Endereços** (residencial, comercial, entrega, cobrança — com autofill em formulários)
- **Cartões de crédito** (número, titular, validade, CVV — cifrados, autofill em checkout)

**Visão maior**: uma **Identidade Digital portátil** que o usuário carrega entre dispositivos, sem depender de Google/Apple/Microsoft — tudo cifrado, armazenado no mesmo IPFS vault que as senhas, acessível pelos mesmos dispositivos confiáveis.

**Status**: :hourglass: Em andamento — 15.1 (Sessão 167), 15.2 (Sessão 168) e 15.3 (Sessão 169)
concluídas; 15.4 fatia 1 concluída (Sessão 170); 15.4 fatia 2 — cartão de crédito (Sessão 171) e
dead-drop (Sessão 172) concluídos, só falta Desktop pra fechar a 15.4; demais etapas aguardando.

---

#### Princípios de arquitetura (decididos com o dono do projeto)

| Princípio | Decisão |
|---|---|
| **Onde ficam os dados** | Mesmo blob IPFS criptografado do Vault (Fase 13). Tudo junto: senhas, documentos, endereços, cartões — um único vault cifrado por identidade. |
| **Criptografia** | AES-256-GCM, mesma chave derivada da wallet (HKDF via `personal_sign("TruthID Vault Key v1")`). Nenhum dado em claro jamais sai do dispositivo. |
| **Autofill — browser** | Via extensão já existente (`extension/`, Fase 13.9). A extensão não acessa o vault diretamente — o **device** (Mobile/Desktop) envia P2P apenas as informações que o usuário aprovar, no mesmo padrão do fluxo de senhas já implementado. |
| **Autofill — SO** | Android Autofill Framework + iOS ASCredentialProviderViewController. O vault local no celular preenche formulários de sistema (checkout, cadastro) diretamente. |
| **Documentos** | Genéricos (qualquer tipo de arquivo). Limite de tamanho a ser decidido na implementação (sugestão inicial: 10MB por documento, ajustável). |
| **Sync entre devices** | Mesmo mecanismo da Fase 13: edição local → botão "Enviar" → IPFS multi-pin → `VaultRegistry.updateVault` on-chain. |
| **Relação com a extensão** | A extensão funciona como "agente de requisição": detecta campos de formulário, pede ao device os dados específicos via QR/LAN/dead-drop (mesmo padrão 13.9), o device mostra o que está sendo pedido e o usuário aprova/rejeita. |

---

#### O que vai on-chain vs. o que não vai

| Dado | Vai on-chain? | Onde fica |
|---|---|---|
| Conteúdo do vault (senhas, documentos, endereços, cartões) | **Nunca** | IPFS cifrado (blob único) |
| CID do blob | Sim | `VaultRegistry` (já existe) |
| Chave de decriptação | **Nunca** | Derivada localmente (wallet signature) |
| Metadados de cartão (nome do banco, apelido) | **Nunca** | Apenas no blob cifrado |

---

#### Fluxo de autofill (browser — extensão)

```
Usuário está num site de checkout (formulário de endereço + cartão)

    ┌─ Extensão (browser) ─────────────────────────────────┐
    │ 1. Detecta campos de endereço/cartão no DOM          │
    │ 2. Gera pedido: { type: "address" | "creditCard",    │
    │                   fields: [...], sessionId,           │
    │                   ephemeralPubKey }                   │
    │ 3. Exibe QR code (ou LAN discovery)                  │
    └──────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─ Mobile / Desktop (device confiável) ────────────────┐
    │ 4. Escaneia QR / descobre na LAN                     │
    │ 5. Decifra o vault localmente                        │
    │ 6. Mostra ao usuário: "O site X pede endereço        │
    │    residencial. Permitir?"                            │
    │ 7. Usuário aprova (ou escolhe qual endereço/cartão)  │
    │ 8. Cifra só os dados aprovados via ECIES             │
    │ 9. Envia de volta (LAN / dead-drop IPFS)             │
    └──────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─ Extensão (browser) ─────────────────────────────────┐
    │ 10. Decifra resposta com chave efêmera               │
    │ 11. Preenche campos do formulário                    │
    │ 12. Dados descartados ao fechar aba                  │
    └──────────────────────────────────────────────────────┘
```

---

#### Fluxo de autofill (SO — Android/iOS)

```
Usuário está num app de e-commerce, campo de endereço focado

    ┌─ Android Autofill Framework / iOS ASCredentialProvider ─┐
    │ 1. SO dispara pedido de autofill                        │
    │ 2. TruthID Vault Service recebe a requisição            │
    │ 3. (Opcional) Biometria (fingerprint/face)              │
    │ 4. Decifra vault local                                  │
    │ 5. Filtra entradas compatíveis com o contexto           │
    │ 6. Preenche formulário diretamente                      │
    └─────────────────────────────────────────────────────────┘
```

---

#### Schema do vault (extensão do formato atual)

O schema JSON atual do vault (`VaultEntry`) será estendido com novos tipos de entrada:

```typescript
// Atual (Fase 13)
type VaultEntryCredential = {
  type: "credential";
  site: string;
  username: string;
  password: string;
  notes?: string;
  profiles: string[];
};

// Novos (Fase 15)
type VaultEntryDocument = {
  type: "document";
  name: string;           // apelido: "RG", "CNH", "Contrato XYZ"
  fileName: string;       // nome original do arquivo
  fileData: string;       // base64 do arquivo, cifrado dentro do blob
  fileSizeBytes: number;
  mimeType: string;       // "application/pdf", "image/png", etc.
  notes?: string;
  profiles: string[];
};

type VaultEntryAddress = {
  type: "address";
  label: string;          // "Casa", "Trabalho", "Entrega"
  fullName: string;
  street: string;
  number: string;
  complement?: string;
  neighborhood: string;
  city: string;
  state: string;
  zipCode: string;
  country: string;
  phone?: string;
  notes?: string;
  profiles: string[];
};

type VaultEntryCreditCard = {
  type: "creditCard";
  label: string;          // "Nubank", "Itaú Platinum"
  cardHolderName: string;
  cardNumber: string;     // cifrado individualmente dentro do blob
  expiryMonth: string;
  expiryYear: string;
  cvv: string;            // cifrado individualmente dentro do blob
  bank?: string;
  cardNetwork: "visa" | "mastercard" | "amex" | "elo" | "hipercard" | "other";
  notes?: string;
  profiles: string[];
};

// Union type do vault
type VaultEntry = VaultEntryCredential | VaultEntryDocument
                | VaultEntryAddress | VaultEntryCreditCard;
```

**Nota de segurança**: `cardNumber` e `cvv` são cifrados individualmente (camada extra além da cifra do blob inteiro), para que o autofill possa expor o número sem nunca decifrar o CVV a menos que explicitamente necessário (ex: checkout com CVV).

---

#### Etapas planejadas (ordem sugerida)

1. ~~**15.1 — Schema**~~ — **concluída na Sessão 167** (2026-07-26): `VaultEntry` continua um
   struct único (não virou enum tagged) — ganhou `type: EntryType` + 3 grupos opcionais
   (`document`/`address`/`credit_card`), decisão confirmada com o dono do projeto via
   `AskUserQuestion` pra manter zero mudança nas UIs existentes (`EntryForm`/
   `VaultManagement.tsx` no Desktop, `vault_entry_form_screen.dart`/`vault_screen.dart` no
   Mobile — nenhum dos dois foi tocado). Campos novos com casing `snake_case` (convenção real do
   resto do schema), diferente do camelCase do esboço original desta seção — só os 4 valores do
   discriminante (`"credential"`/`"document"`/`"address"`/`"creditCard"`) seguem o esboço
   literalmente. `VaultEntry::validate()` novo garante que só o grupo correspondente ao `type`
   está presente, chamado no início de `Vault::upsert` (agora retorna `Result`). Cifra individual
   extra de `card_number`/`cvv` fica pra 15.8, como já previsto nesta seção — por ora os dois
   viajam em texto plano dentro do blob (que já é cifrado como um todo). `cargo test --lib`
   106/106 (9 novos), `flutter test` 415/415 (11 novos), `npx vitest run` 101/101, `tsc --noEmit`/
   `flutter analyze` limpos. **Não validado com clique real no Desktop nativo** — abrir a tela do
   Vault exige desbloquear a wallet (Ledger físico), indisponível nesta sessão automatizada; a
   prova de back-compat ficou pelos testes automatizados (deserialização de um JSON literal no
   formato antigo, sem nenhum dos 4 campos novos).
2. ~~**15.2 — CRUD Desktop**~~ — **concluída na Sessão 168** (2026-07-26): `EntryForm` em
   `VaultManagement.tsx` ganhou um seletor de tipo (Senha/Documento/Endereço/Cartão) no topo,
   grupos de campo condicionais por tipo (endereço e cartão como formulários normais; documento via
   upload de arquivo — `readFile`/base64, limite de 10MB validado no cliente, MIME adivinhado pela
   extensão), reusando os campos compartilhados (Notas/Grupos) entre os 4 tipos. Achado no caminho:
   trocar o `type` durante a edição de uma entrada existente exigia zerar explicitamente os 3
   grupos opcionais no payload (`document`/`address`/`credit_card`) — só omitir o campo não bastava
   porque `{...original, ...payload}` preservava o grupo antigo, o que `Vault::validate()` (Rust)
   rejeitaria (tipo e grupo de dados inconsistentes). `buildEntryPayload()` novo sempre zera os 3
   explicitamente antes de preencher o grupo certo. Lista de entradas ganhou renderização por tipo
   (ícone + título + subtítulo específico — nome do arquivo/tamanho pra documento com botão
   "Baixar" via `save()`+`writeFile`, rua/cidade pra endereço, bandeira+últimos 4 dígitos+validade
   pra cartão) e a busca (`entrySearchText()`) passou a indexar os campos certos por tipo em vez de
   só site/username. `npx tsc --noEmit` limpo, `npx vitest run` 101/101 (sem teste dedicado — este
   componente nunca teve suíte própria, mesma situação de sempre), `npm run build` (Vite) limpo.
   **Não validado com clique real** — mesma limitação de hardware (Ledger) já registrada na 15.1.
3. ~~**15.3 — CRUD Mobile**~~ — **concluída na Sessão 169** (2026-07-26): paridade com o Desktop
   (15.2) em `vault_entry_form_screen.dart` — seletor de tipo (chips), 3 grupos de campo
   condicionais (endereço, cartão com `DropdownButtonFormField<CardNetwork>`, documento via
   `FilePicker.platform.pickFiles(withData: true)` + `base64Encode` nativo do `dart:convert` +
   limite de 10MB), Notas/Perfis compartilhados, TOTP/Passkey exclusivos de `credential`.
   **Achado corrigido proativamente** (mesma classe de bug da 15.2, achada no Desktop): trocar o
   `type` de uma entrada existente exige zerar os outros 2 grupos explicitamente no save — em vez
   de um switch com 4 branches (como ficou no Desktop, onde um branch esqueceu de zerar), um único
   getter `_dataGroups` monta os 3 grupos de uma vez (só o do `_type` ativo fica não-nulo) e
   `_save()` sempre espalha os 3 num único call site, tornando o esquecimento estruturalmente
   impossível em vez de só coberto por teste. Novo `VaultEntry.validate()` em
   `vault_repository.dart` (mirror do Rust) chamado por `addEntry`/`updateEntry` — o Mobile não
   tinha nenhuma outra camada de validação desse invariante (repositório lê/escreve o arquivo
   cifrado local direto, sem chamada Rust nesse caminho). `vault_screen.dart` ganhou ícone/
   título/subtítulo por tipo (`_VaultEntryCard`) e busca por campo certo (`_entrySearchText`);
   `vault_entry_detail_screen.dart` ganhou corpo por tipo (documento com botão "Save to device"
   via `saveFile`, endereço em `InfoRow`s, cartão com número/CVV mascarados via `_CopyableRow`
   já existente). `flutter test` 429/429 (14 novos, incluindo um teste de regressão que reproduz
   exatamente o bug do Desktop), `flutter analyze` limpo. **Não validado com clique real** —
   mesma limitação de hardware da 15.1/15.2.
4. :hourglass: **15.4 — Autofill browser (extensão)**: extensão detecta campos de endereço/cartão
   e pede ao device os dados específicos (mesmo padrão P2P da 13.9). Aprovação no device mostra o
   que será preenchido. **Fatia 1 (só endereço, só transporte LAN, só Mobile) concluída na Sessão
   170** (2026-07-27) — escopo negociado com o dono do projeto via `AskUserQuestion` (fatiado do
   mesmo jeito que a 13.9: LAN antes de dead-drop; Mobile antes de Desktop, que ficaria
   loopback-only). Novo schema de QR `truthid-autofill-address` (`extension/src/session/
   qrPayload.ts`), transporte LAN reaproveitando o `RemoteSignerLanServer` genérico do Mobile
   (portas 48050-54 — não o bloco 47850-54, exclusivo da leitura do vault da 13.9), detecção de
   campo de endereço por token `autocomplete` WHATWG (`extension/src/autofill/
   addressFieldDetection.ts`), ícone Shadow-DOM com QR + fallback de IP manual
   (`addressOverlay.ts`), e uma tela de aprovação Mobile nova
   (`autofill_address_approval_screen.dart`) que introduz um padrão inédito no projeto: deixar o
   usuário escolher 1 de N entradas salvas antes de aprovar (nenhuma tela de aprovação anterior
   tinha esse picker). `npx vitest run` (extensão) 108/108 (14 novos), `flutter test` 444/444 (15
   novos), `flutter analyze`/`tsc --noEmit`/`npm run build` limpos. Faltam cartão de crédito,
   dead-drop e Desktop (fatia 2). **Primeira parte da fatia 2 (cartão de crédito) concluída na
   Sessão 171** (2026-07-27) — mesmo recorte de transporte da fatia 1 (só LAN, só Mobile
   responde), escolhido com o dono do projeto via `AskUserQuestion`. Novo schema de QR
   `truthid-autofill-creditcard`, `extension/src/autofill/{creditCardFieldDetection,
   creditCardFill,creditCardOverlay}.ts` (tokens WHATWG de pagamento: `cc-name`/`cc-number`/
   `cc-exp`/`cc-exp-month`/`cc-exp-year`/`cc-csc`), `mobile/lib/screens/
   autofill_creditcard_approval_screen.dart` (mesmo picker "1 de N" da fatia 1, mas com número/CVV
   mascarados por padrão na confirmação — mais sensíveis que endereço). Os 3 canais de
   `background.ts` que a fatia 1 criou (permissão de host/sweep de LAN/fetch manual) eram
   genéricos por natureza (nunca olhavam o conteúdo do pedido) — renomeados (sem "ADDRESS") e
   reusados pelo cartão em vez de triplicados. `npx vitest run` 117/117 (9 novos), `flutter test`
   462/462 (18 novos), `flutter analyze`/`tsc --noEmit`/`npm run build` limpos. Ainda faltam
   dead-drop e Desktop (resto da fatia 2). **Dead-drop (endereço + cartão) concluído na Sessão
   172** (2026-07-27) — escolhido sobre Desktop via `AskUserQuestion`, depois de uma exploração
   confirmar que os dois pedaços eram de tamanho parecido. Achado que reduziu bastante o escopo
   real: o lado Mobile já estava pronto — `CrossDeviceDeliveryChannel.deliver()` já publica
   dead-drop em paralelo com o LAN pra qualquer `result`, e a chave IPNS depende só do
   `sessionId` (não do par ECIES efêmero por pedido), então zero mudança em `mobile/`. O trabalho
   real ficou do lado extensão: o polling de dead-drop existente (`pollDeadDropOnce`/
   `DEAD_DROP_POLL_ALARM`) foi desenhado pra 1 sessão só em `chrome.storage.session`, incompatível
   com o autofill (várias sessões pendentes ao mesmo tempo, chave efêmera só no closure do content
   script) — novo `extension/src/session/autofillDeadDropAlarm.ts` (puro, testável) codifica
   `sessionId`+`expiresAt` no próprio nome do alarme do `chrome.alarms` em vez de um storage novo;
   novo `extension/src/autofill/deadDropPull.ts::pullFromDeadDrop()` com a mesma assinatura de
   `sweepMobileForBlob`/`fetchMobileBlobAt` (`lanPull.ts`), plugado em paralelo ao sweep de LAN
   já existente em `addressOverlay.ts`/`creditCardOverlay.ts` (nunca como fallback sequencial,
   mesma decisão já travada na 13.9). Mensagens novas (`AUTOFILL_START_DEAD_DROP_POLL_MESSAGE`/
   `AUTOFILL_DEAD_DROP_RESOLVED_MESSAGE`) genéricas desde o início, reusadas por endereço e cartão.
   `npx vitest run` 125/125 (8 novos), `tsc --noEmit`/`npm run build` limpos, `flutter test`
   462/462 continua verde (nada tocado no Mobile). Só falta Desktop pra fechar a 15.4 inteira.
5. **15.5 — Autofill SO Android**: implementar `AutofillService` (`android.app.service.AutofillService`). Lê vault local, filtra por tipo de campo, preenche.
6. **15.6 — Autofill SO iOS**: implementar `ASCredentialIdentityStore` / `ASCredentialProviderViewController`. Mesma lógica do Android.
7. **15.7 — Documentos**: upload/download/visualização de documentos genéricos. Limite de tamanho a definir. Chunking para arquivos grandes, se necessário.
8. **15.8 — Revisão de segurança**: auditoria focada nos cartões de crédito (cifra extra do CVV, exposição mínima no autofill, zero logging).

---

#### Dependências

- Fase 13 (Vault de senhas) — concluída, base para tudo
- Fase 13.9 (Extensão de navegador) — concluída, reusada para autofill de endereços/cartões
- Fase 14 (Smart Account) — concluída, usada para pagar gas do `updateVault` ao adicionar entradas novas
- Nenhum contrato novo necessário — `VaultRegistry` já serve

---
