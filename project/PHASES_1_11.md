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
