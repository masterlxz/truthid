# TruthID — Estado do Projeto

> Este arquivo é o centro de controle do projeto. Atualizado a cada sessão de trabalho.
> Pode ser lido por qualquer instância do Claude Code em qualquer máquina para retomar o contexto.
> Última atualização: 2026-06-21 (Sessão 32)

---

## Diretriz de ensino (IMPORTANTE — ler antes de cada sessão)

O usuário é iniciante em blockchain e Solidity. O objetivo do projeto é aprender enquanto constrói.
Conhecimento prévio: **Python** (bom) e **Ruby** (básico). Usar Python como referência principal para analogias.

**Regras para o Claude:**
- Explicar o conceito ANTES de escrever o código
- Introduzir um conceito novo de cada vez — nunca vários ao mesmo tempo
- Usar analogias do mundo real antes de termos técnicos
- Comparar Solidity com Python sempre que possível (`mapping` = `dict`, `struct` = `dataclass`, `contract` = `class`)
- Perguntar se o usuário entendeu antes de avançar — esperar confirmação
- Não assumir conhecimento prévio de blockchain, Solidity, criptografia, Foundry ou qualquer ferramenta
- Ritmo lento e deliberado é melhor que velocidade
- **Nunca escrever um bloco grande de código sem explicar depois linha por linha**
- Quando escrever código novo, percorrer cada trecho explicando o que faz e por quê
- Quando explicar código já escrito, dividir em partes (estado → eventos/erros → funções uma a uma) e pedir confirmação antes de avançar para a próxima parte

---

## O que é o TruthID

Plataforma de autenticação descentralizada que substitui Google/Apple/Microsoft.
O usuário possui sua identidade via wallet (blockchain) e autentica com dispositivos confiáveis — sem senha, sem e-mail.

Stack principal:
- **Blockchain**: Base Mainnet (EVM, baixas taxas)
- **Smart Contracts**: Solidity
- **Desktop**: Tauri + Rust + React + TypeScript
- **Mobile**: Flutter (Dart)
- **Relay**: Serviço stateless de relay WebSocket
- **SDKs**: TypeScript, Ruby, Python

---

## Status Geral

```
Fase 1 — Smart Contracts        [x] Concluída
Fase 2 — Relay Service          [x] Concluída
Fase 3 — Desktop App            [x] Concluída
Fase 4 — Mobile App             [x] Concluída
Fase 5 — SDKs                   [x] Concluída
Fase 6 — Integração & Testes    [x] Concluída
Fase 7 — Mainnet & Lançamento   [x] Concluída
Fase 8 — Documentação Web       [~] Em andamento (8.7/11)
```

---

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
- [x] 3.2 — Integração com wallet (wagmi + viem)
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
    - RecoveryManager  : 0xA93123C1ca438D9F56E4E599363F4d973d61A307
    - SessionRegistry  : 0x24074587a2aFB3aa5491361BB0a5eBee90797D1B
  - Todos os 4 verificados no Basescan (`forge verify-contract`, Etherscan V2 API com `chainid=8453`)
  - Custo total: ~0,000055 ETH (saldo antes 0,010082 ETH → depois 0,010045 ETH) — gas price ~0,011 gwei
  - Sanity check: `owner()` do IdentityRegistry retorna a carteira deployer ✓; `totalIdentities()` retorna 0 ✓
  - **Endereços propagados (Sessão 26)** — desktop, mobile e os 3 SDKs agora apontam para Base Mainnet. Ver detalhes na Sessão 26 do Log de Sessões.
- [x] 7.2 — Eliminar o servidor de sinalização (substitui "Relay Service em produção" — não fazia sentido hospedar algo que ia ser removido). Implementado na Sessão 26 (continuação): pareamento via QR mostrado pelo mobile + polling on-chain; login via challenge embutido no QR + POST HTTPS direto pro backend do site. `signaling/`, `turn/` e `webrtc-demo/` removidos. Ver "Roadmap de Evoluções Planejadas → Sinalização sem servidor"
- [x] 7.3 — Publicar SDKs (npm, pip, rubygems). Implementado na Sessão 29: `truthid-sdk@0.1.0` publicado nos três registros — npm (https://www.npmjs.com/package/truthid-sdk), PyPI (https://pypi.org/project/truthid-sdk/0.1.0/) e RubyGems. Ver Sessão 29 no Log de Sessões para detalhes.
- [x] 7.4 — Documentação pública. `README.md` criado na raiz do repositório (Sessão 30) — escopo limitado a esse arquivo, a pedido do usuário (CONTRIBUTING.md/SECURITY.md ficaram fora). Cobre: o que é o TruthID, fluxo de auth (diagrama ASCII), arquitetura, tabela de endereços mainnet, SDKs publicados, como buildar cada componente, seção de segurança (aponta pra "GitHub Security tab" para reports privados, sem expor e-mail pessoal — decisão consciente do usuário)
- [x] 7.5 — Open source (GitHub). Descoberto na Sessão 30 que o repositório já estava público desde 2026-06-04 (criado assim, sem que tivesse sido uma decisão consciente registrada) — `curl` na API do GitHub sem autenticação retornou `"private": false`. Varredura em `git log --all -p` confirmou que nenhum segredo de verdade jamais foi commitado (só placeholders em `contracts/.env.example`; o PAT exposto era só na configuração local do git, nunca em conteúdo versionado). Decisão consciente do usuário: manter `PROJECT_STATE.md` como está, sem reescrever histórico nem mover pra repositório separado — o conteúdo "bastidor" (diretriz de ensino, log de sessões) não representa risco de segurança real hoje, é só uma questão de tom. Fechamento da etapa: README/PROJECT_STATE.md commitados e enviados via SSH (`73de3e9`), e "Private vulnerability reporting" habilitado nas configurações do repositório (confirmado via API: `private-vulnerability-reporting` → `enabled: true`)

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
- [ ] 8.8 — Página de segurança: modelo de ameaças, o que o TruthID protege e o que não protege
- [ ] 8.9 — Página de contratos: endereços, ABIs, links Basescan, custo por operação
- [ ] 8.10 — Identidade visual: logo, cores, tipografia aplicados ao site
- [ ] 8.11 — Deploy em produção (GitHub Pages ou domínio customizado)

---

## Decisões de Arquitetura em Aberto

| Decisão | Opções | Status |
|---|---|---|
| Framework de contratos | Foundry vs Hardhat | **Foundry** ✓ |
| Camada de comunicação | Relay tradicional vs WebRTC | **WebRTC** ✓ |
| Canal de sinalização WebRTC | On-chain / DHT / servidor leve | **Servidor leve (WebSocket)** ✓ |
| Padrão de upgrade dos contratos | Proxy (upgradeable) vs Imutável | **Imutável** ✓ — decidido na Sessão 25, antes do deploy em mainnet (etapa 7.1). Motivo: evitar superfície de ataque extra (controle de upgrade) e complexidade adicional; processo de redeploy + migração já é conhecido (feito 2x na Sessão 24) |
| Formato do challenge de autenticação | JWT vs custom JSON | Pendente |
| Armazenamento de sessões | Servidor central vs on-chain hash | **Hash keccak256 on-chain** ✓ — dados originais locais, só o hash vai pra chain; privado mas auditável; revogação granular por sessão |
| Sinalização WebRTC (histórico) | Servidor fixo vs plugável | **Substituído** — o `SignalingAdapter` (decisão da Sessão 15) nunca foi implementado; o código usava WebSocket direto. Resolvido na Sessão 26 (continuação) removendo a dependência de servidor por completo, em vez de construir o adapter — ver linha abaixo |
| Sinalização sem servidor do TruthID | On-chain (eventos+gas) vs transporte direto sem blockchain | **Transporte direto, sem blockchain** ✓ — Sessão 26 (continuação). Pareamento: o device mostra seu próprio endereço em QR, o controller (desktop) lê e registra on-chain; confirmação via polling (`getDevice`), sem canal ao vivo. Login: o challenge vai embutido no QR, a resposta assinada vai via HTTPS direto pro `callbackUrl` do próprio site (backend que o integrador já roda). Zero gas extra, zero latência de handshake on-chain — `signaling/`, `turn/` e `webrtc-demo/` removidos do repositório |
| Interface e experiência do usuário | UI funcional vs identidade visual própria | **Pendente** — app e desktop têm UI funcional (Material Design padrão) mas sem logo, cores, tipografia ou fluxos polidos; previsto para uma fase dedicada após Fase 4 ou como Fase 8 pós-lançamento |
| Endereços de contrato nos SDKs (multi-rede) | Endereço fixo único vs mapa por rede | **Mapa por rede** ✓ — decidido na Sessão 26. Os 3 SDKs já tinham um parâmetro `network` desde a Fase 5, mas os endereços eram fixos (só Sepolia); completar o design original em vez de descartá-lo. Python/Ruby agora default para `"base-mainnet"`; TypeScript continua exigindo `network` explícito (sem default) |
| Domínio do site de docs (Fase 8) | Domínio próprio (ex: truthid.dev) vs subdomínio grátis do GitHub Pages | **GitHub Pages grátis** ✓ — decidido na Sessão 31. Usuário ainda não tem domínio próprio registrado; `masterlxz.github.io/truthid` configurado no `docusaurus.config.ts` (etapa 8.1). Dá pra trocar pra domínio próprio depois (basta um arquivo `CNAME` em `docs/static/` + DNS) sem precisar redeployar nada além disso |

---

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

**Trade-off aceito conscientemente**: o mobile não consegue mais resolver `@username` ao parear — o `IdentityRegistry` só tem `username → id`, não o inverso, e adicionar isso exigiria mudar e re-deployar um contrato que já está em mainnet. O app mostra "Identidade #&lt;id&gt;" em vez de "@username". Decisão: não vale o custo de redeploy só por uma label cosmética.

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

---

## Fluxo de Autenticação (Referência Rápida)

```
Website          Relay           Mobile App        Blockchain
   |                |                 |                 |
   |-- cria QR ---->|                 |                 |
   |  (challenge)   |                 |                 |
   |                |<-- subscreve ---|                 |
   |                |   (scan QR)     |                 |
   |                |--- entrega ---->|                 |
   |                |   (challenge)   |                 |
   |                |                 |-- assina ------>|
   |                |                 |  (verifica      |
   |                |<-- resposta ----|   device ativo) |
   |<-- verifica ---|                 |                 |
   |   (assinatura) |                 |                 |
   |                                                    |
   LOGIN OK
```

---

## Log de Sessões

### 2026-06-21 — Sessão 32

- **Etapa 8.3 concluída** — guia de introdução expandido com pré-requisitos e arquitetura
  - `docs/docs/intro.mdx`: duas seções novas entre "Why" e "How it works"
    - "Prerequisites": separa as duas audiências do site — quem só vai logar num site que integrou TruthID (precisa de uma identidade on-chain criada com qualquer wallet EVM + um device pareado, desktop ou mobile) e quem está integrando TruthID no próprio app (precisa só de um backend que receba `POST` HTTPS e uma lib de QR no frontend — sem banco, sem servidor, sem conta de terceiro)
    - "Architecture": tabela de componentes (contracts/desktop/mobile/sdk/integration) — mesma tabela do `README.md` raiz, mas com os links relativos (`contracts/`, `desktop/`...) trocados por URLs completas do GitHub, porque o site de docs é publicado separado do repositório e link relativo apontaria pro domínio errado
  - `npm run build` validado sem erros dentro de `docs/`
  - Verificação visual: `npx docusaurus serve` (build estático, não dev server) + screenshot via Playwright headless (mesmo processo já usado na etapa 8.2) — tabelas novas renderizam corretamente no tema dark, sem quebra de layout
- **Favicon trocado** (a pedido do usuário, fora do roadmap formal da etapa 8.3) — `docs/static/img/favicon.ico` era ainda o ícone padrão do Docusaurus (nunca substituído desde o scaffold da 8.1); trocado pelo mesmo logo escudo+check ciano usado na navbar (`logo.svg`, criado na 8.2). Gerado com `rsvg-convert` (SVG → PNG em 16/32/48px) + `magick` (PNGs → `.ico` multi-resolução) — ferramentas de linha de comando já instaladas no sistema, sem precisar de serviço externo. Validado conferindo o HTML servido (`<link rel="icon" href="/truthid/img/favicon.ico">`) e visualmente nos três tamanhos antes de empacotar
- Conceitos ensinados: nenhum conceito novo de blockchain/Solidity nesta sessão — trabalho foi só de documentação (reorganizar conteúdo já decidido em sessões anteriores) e um ajuste visual pequeno (favicon)
- **Próximo passo ao retomar**: etapa 8.4 (quickstart interativo) ou qualquer outra dentro da Fase 8 (8.5-8.7 referência de SDK, 8.8 segurança, 8.9 contratos, 8.10 identidade visual definitiva, 8.11 deploy — já automático)

### 2026-06-21 — Sessão 32 (continuação — etapa 8.4)

- **Etapa 8.4 concluída** — quickstart interativo
  - Nova página `docs/docs/quickstart.mdx` (sidebar_position 2, logo após Introduction); link adicionado no footer (`docusaurus.config.ts`)
  - 5 passos: instalar SDK → criar challenge → renderizar QR code → verificar resposta → testar com device real, mais uma seção "Next steps" linkando pro `sdk/README.md`, pra seção de contratos do `intro.mdx` e avisando que segurança/threat model ainda não tem página própria
  - Passos 1, 2 e 4 usam `<Tabs groupId="sdk-lang">` (componente `@theme/Tabs` do tema clássico do Docusaurus) — primeiro uso desse componente no site — pra mostrar TypeScript/Python/Ruby lado a lado com a seleção sincronizada entre as três seções da página
  - Antes de escrever os snippets, lidos os 3 SDKs de verdade (`sdk/typescript/src/{types,client}.ts`, `sdk/python/truthid/{types,client}.py`, `sdk/ruby/lib/truthid/types.rb`) pra garantir que a API documentada existe — achado: o `AuthResponse` do Python **não** tem `from_dict`/`from_json`; precisa ser construído campo a campo com chaves camelCase (`deviceAddress`, não `device_address`), porque os nomes dos campos do dataclass espelham o protocolo JSON do mobile direto. Já o Ruby tem `AuthResponse.from_hash` de verdade — API ligeiramente menos ergonômica em um SDK do que no outro, registrado só como observação, sem mudar código
  - Passo 5 ("Test it with a real device") é honesto sobre uma limitação real do projeto: `curl .../releases` confirmou **zero releases publicados** no GitHub — não existe build pré-compilado do desktop nem do mobile ainda, então testar de ponta a ponta hoje exige compilar a partir do código-fonte (link pra "Building from source" do README raiz) em vez de "baixe o app"
  - `npm run build` validado sem erros; revisão visual via Playwright (build estático servido com `docusaurus serve`, mesmo processo das etapas 8.2/8.3) — layout ok no tema dark, e o clique numa aba (testado com a aba "Python" da seção 1) sincroniza a seleção e usa o ciano do tema pro indicador ativo
- Conceitos ensinados:
  - Por que vale a pena ler o código-fonte real do SDK antes de documentar um exemplo, mesmo quando já existe um exemplo parecido em outro arquivo (`sdk/README.md`) — a Sessão 26 já tinha corrigido um SDK (Ruby) que ficou esquecido numa atualização anterior; ler de novo evita repetir esse tipo de divergência
  - `groupId` no componente `Tabs` do Docusaurus: como múltiplos blocos de abas na mesma página (ou em páginas diferentes) podem compartilhar a seleção — útil quando o leitor já escolheu "sou dev Python" na primeira seção e não quer reescolher a cada bloco de código
- **Próximo passo ao retomar**: etapa 8.5 (referência de API do SDK TypeScript) ou qualquer outra dentro da Fase 8 (8.6-8.7 Python/Ruby, 8.8 segurança, 8.9 contratos, 8.10 identidade visual definitiva, 8.11 deploy — já automático)

### 2026-06-21 — Sessão 32 (continuação — etapa 8.5)

- **Etapa 8.5 concluída** — referência de API do SDK TypeScript
  - Nova categoria de sidebar "SDK Reference" (`docs/docs/sdk/_category_.json`, position 3) com a primeira página, `docs/docs/sdk/typescript.md` (rota `/docs/sdk/typescript`) — pensada pra acomodar Python (8.6) e Ruby (8.7) como páginas-irmãs depois
  - Conteúdo: instalação, construtor (`TruthIDClientConfig`, com nota de que `network` não tem default em TS, diferente de Python/Ruby), os 4 métodos (`createChallenge`, `verifyAuthResponse`, `verifySession`, `checkDeviceStatus`) com parâmetros/retorno/exemplo/razões de falha, os 7 tipos exportados (cada um com heading próprio, ex. `#authchallenge`, pra permitir link direto de outras páginas), security notes (nonce invalidation, TTL, HTTPS only) e tabela de networks — migrado e expandido do `sdk/README.md`, mas com os tipos exatos de TypeScript (`bigint`, `Date`) em vez do placeholder genérico "bigint / int" do README compartilhado entre os 3 SDKs
  - Antes de escrever, relidos `sdk/typescript/src/{types,client,index}.ts` pra confirmar a API real (mesmo cuidado da etapa 8.4)
  - **Decisão de escopo**: `sdk/README.md` não foi tocado — fica como está até Python e Ruby também terem página própria (8.6/8.7), pra não deixar a seção "API Reference" dele pela metade linkando pra um SDK só
  - **Bug pego na revisão visual**: a sintaxe de admonition `:::tip Título` (Docusaurus v2) não é reconhecida pelo tema v3 instalado (3.10.1) — virou texto puro em vez de caixa estilizada. O v3 trocou pra `remark-directive`, que exige o título entre colchetes: `:::tip[Título]`. Corrigido e revalidado com screenshot (caixa verde com ícone, como esperado)
  - `npm run build` reportou "broken anchors" na primeira tentativa (links cruzados pra `#authchallenge` etc. apontando pra headings que não existiam, porque os 7 tipos estavam num bloco de código só) — corrigido dando heading próprio (`#### AuthChallenge`) pra cada tipo; rebuild limpo
- Conceitos ensinados:
  - Por que vale a pena rodar `npm run build` (não só abrir a página no navegador) antes de fechar uma etapa de docs — o build do Docusaurus valida link interno quebrado e admonition mal-formada de um jeito que só olhar a página renderizada não pega sempre (a admonition quebrada, por exemplo, "funcionava" no sentido de não dar erro nenhum — só ficava feia)
  - Diferença entre Docusaurus v2 e v3 na sintaxe de admonition — útil porque tutoriais/exemplos antigos na internet (inclusive os que viriam do treinamento da própria IA) usam a sintaxe v2, que silenciosamente não funciona mais
- **Próximo passo ao retomar**: etapa 8.6 (referência de API do SDK Python) ou qualquer outra dentro da Fase 8 (8.7 Ruby, 8.8 segurança, 8.9 contratos, 8.10 identidade visual definitiva, 8.11 deploy — já automático)

### 2026-06-21 — Sessão 32 (continuação — etapa 8.6)

- **Etapa 8.6 concluída** — referência de API do SDK Python
  - Nova página `docs/docs/sdk/python.md` (sidebar_position 2, logo depois de TypeScript na categoria "SDK Reference"), mesma estrutura da página TypeScript: instalação, construtor, 4 métodos, tipos, security notes, networks
  - Diferenças reais documentadas (não cosméticas — refletem a API de verdade): construtor com default `network="base-mainnet"` (TS exige explícito); nota na seção "Types" explicando por que `AuthChallenge`/`AuthResponse` usam camelCase (espelham o JSON que o mobile assina) enquanto os 3 tipos de retorno usam snake_case normal (nunca saem do processo Python); exemplo de `verify_auth_response` mostrando a construção manual de `AuthResponse` sem `from_dict`
  - Página TypeScript (`typescript.md`) atualizada: "Next steps" agora linka pra `/docs/sdk/python` em vez de "coming soon"
  - `npm run build` sem erros; revisão visual via Playwright confirmou sidebar com as duas páginas, admonition (`:::tip[Título]`, sintaxe já correta desde a criação) e syntax highlighting Python ok
- Conceitos ensinados: por que dois dataclasses do mesmo SDK podem ter convenções de nomenclatura diferentes de propósito — não é inconsistência acidental, é o campo "vazando" o formato de quem o consome (protocolo JSON vs. uso interno Python)
- **Próximo passo ao retomar**: etapa 8.7 (referência de API do SDK Ruby) ou qualquer outra dentro da Fase 8 (8.8 segurança, 8.9 contratos, 8.10 identidade visual definitiva, 8.11 deploy — já automático)

### 2026-06-21 — Sessão 32 (continuação — etapa 8.7)

- **Etapa 8.7 concluída** — referência de API do SDK Ruby, fecha o trio de referências de SDK (8.5/8.6/8.7)
  - Nova página `docs/docs/sdk/ruby.md` (sidebar_position 3), mesma estrutura das páginas TypeScript e Python
  - Diferenças reais documentadas: as duas formas de construir o client (`TruthID::Client.new` e `TruthID.new_client`, o factory que a Sessão 26 já tinha registrado como fácil de esquecer numa atualização — agora os dois caminhos estão documentados); construtor com default `network: "base-mainnet"`; nota explicando que o design do Ruby é o mais limpo dos 3 — atributos sempre snake_case (`issued_at`, `device_address`), conversão pra camelCase isolada em `to_h`/`from_hash` só na borda do protocolo, ao contrário do Python (que usa `issuedAt` direto no dataclass); `AuthResponse.from_hash` existe de verdade, em contraste explícito com a ausência de `from_dict` no Python (achado já registrado nas etapas 8.4 e 8.6)
  - Páginas TypeScript e Python atualizadas: "Next steps" agora linka pra `/docs/sdk/ruby` em vez de "coming soon" — as 3 páginas se referenciam mutuamente
  - `npm run build` sem erros; revisão visual via Playwright confirmou as 3 páginas lado a lado na sidebar "SDK Reference" e os blocos de código Ruby corretos
- **Decisão em aberto, levantada mas não resolvida nesta sessão**: agora que os 3 SDKs têm página própria no site, o que fazer com a seção "API Reference" do `sdk/README.md` (que documenta os 3 de forma genérica, com placeholders como "bigint / int")? Não tocado ainda — decisão de produto (simplificar/linkar pro site vs. manter como está, já que o README também é a página inicial dos pacotes no npm/PyPI/RubyGems) fica pro usuário decidir antes de qualquer mudança
- Conceitos ensinados: como o mesmo problema (JSON camelCase vs. convenção idiomática da linguagem) teve 3 soluções de design diferentes nos 3 SDKs — Python expõe camelCase direto no dataclass, Ruby isola a conversão na borda, TypeScript nem precisa de conversão (camelCase é idiomático em JS). Nenhuma é "errada", são trade-offs diferentes entre fidelidade ao protocolo e idiomaticidade da linguagem
- **Próximo passo ao retomar**: decidir o que fazer com `sdk/README.md` (ver decisão em aberto acima), depois etapa 8.8 (segurança), 8.9 (contratos), 8.10 (identidade visual definitiva) ou 8.11 (deploy — já automático)

### 2026-06-21 — Sessão 32 (continuação — simplificação do sdk/README.md)

- **Decisão em aberto da etapa 8.7 resolvida**: usuário escolheu simplificar a seção "API Reference" do `sdk/README.md` e linkar pro site, em vez de manter a versão completa duplicada
  - Substituída a tabela detalhada de cada método (createChallenge/verifyAuthResponse/verifySession/checkDeviceStatus — parâmetros, retorno, exemplo, razões de falha pros 3 SDKs misturados, ~150 linhas) por um resumo de 1 linha por método + links pras 3 páginas novas (`/docs/sdk/typescript`, `/docs/sdk/python`, `/docs/sdk/ruby`)
  - Escopo da simplificação ficou só na seção "API Reference" — "How It Works", "Installation", "Quick Start", "Full Examples" (Express/Flask/Sinatra, que o site linka de volta pra eles), "Security Notes", "Networks" e "Smart Contracts" não foram tocados, por não terem sido o que o usuário pediu pra simplificar nesta rodada
  - Arquivo caiu de 530 para 406 linhas. Nenhum link interno (no repo) apontava pras âncoras antigas (`#createchallenge--create_challenge` etc.) — confirmado via grep antes de remover
- **Próximo passo ao retomar**: etapa 8.8 (página de segurança), 8.9 (contratos), 8.10 (identidade visual definitiva) ou 8.11 (deploy — já automático)

### 2026-06-21 — Sessão 31

- **Etapa 8.1 concluída** — setup inicial do site de documentação (Docusaurus), início da Fase 8
  - `npx create-docusaurus@latest docs classic --typescript` — scaffold criado dentro de `docs/` na raiz do repositório
  - `docusaurus.config.ts` configurado para GitHub Pages: `title`/`tagline` TruthID, `url: https://masterlxz.github.io`, `baseUrl: /truthid/`, `organizationName: masterlxz`, `projectName: truthid`, `editUrl` apontando pro repo real ("Edit this page" vai abrir o GitHub de verdade); navbar e footer com os links genéricos do template (Docusaurus/Facebook, Discord, X, Stack Overflow) trocados pelos do projeto
  - Blog do template desativado (`blog: false` no preset, pasta `docs/blog/` removida) — vinha com posts de exemplo sobre dinossauros; blog é "opcional" no roadmap da Fase 8 e não há decisão de usar, então não fazia sentido publicar conteúdo de exemplo
  - `.github/workflows/deploy-docs.yml` criado — builda `docs/` e publica via `actions/upload-pages-artifact` + `actions/deploy-pages`; dispara em push na `main` que toque `docs/**` (mais `workflow_dispatch` manual)
  - `npm run build` validado localmente dentro de `docs/` — gerou `docs/build/` sem erros
  - **Decisão de domínio confirmada com o usuário**: sem domínio próprio registrado ainda, então o site fica em `masterlxz.github.io/truthid` (GitHub Pages grátis) por agora — já é o que está configurado no `docusaurus.config.ts`, nenhuma mudança de código necessária. Ver tabela de Decisões de Arquitetura
  - Commit `7737249` (`feat: etapa 8.1 — setup Docusaurus + GitHub Pages`) enviado via push (chave SSH precisou ser recarregada no agente com `SSH_ASKPASS=/usr/bin/ksshaskpass SSH_ASKPASS_REQUIRE=force ssh-add ~/.ssh/id_ed25519_github` — o agente persistente da Sessão 30 estava com o socket certo mas sem nenhuma identidade carregada ainda nesta sessão de login)
  - **Achado**: a expectativa inicial era que fosse preciso um passo manual no GitHub (Settings → Pages → Source → "GitHub Actions") antes do primeiro deploy funcionar. Não foi necessário — `actions/configure-pages@v5` (usado no `deploy-docs.yml`) habilita o Pages automaticamente (source "GitHub Actions") quando o workflow tem permissão `pages: write` e o Pages ainda não está configurado. Os dois jobs (`build`, `deploy`) rodaram com sucesso já no primeiro push, e o site ficou no ar em `https://masterlxz.github.io/truthid/` (HTTP 200) sem nenhuma ação manual no navegador
- Conceitos ensinados:
  - O que o Docusaurus resolve (site de docs com busca, dark mode, sidebar, versionamento) e por que foi a ferramenta escolhida já no planejamento original da Fase 8
  - Diferença entre o `docs/` da raiz do repo (o projeto Docusaurus inteiro) e o `docs/docs/` interno (só as páginas de conteúdo em Markdown/MDX) — convenção do próprio framework, não uma escolha nossa
  - Por que GitHub Pages com deploy via Actions (`actions/deploy-pages`) é preferível ao antigo método de publicar numa branch `gh-pages`: não deixa artefato de build commitado no histórico do git, e usa OIDC (`id-token: write`) em vez de um token de longa duração
- **Etapa 8.1 totalmente concluída — site no ar em `https://masterlxz.github.io/truthid/`.** Próximo passo ao retomar: etapa 8.2 (landing page) ou outra ordem que o usuário preferir dentro da Fase 8

### 2026-06-21 — Sessão 31 (continuação — etapa 8.2)

- **Etapa 8.2 concluída** — landing page real + tema visual (o usuário achou o resultado da 8.1 "muito simples e feio" e pediu pra melhorar antes de seguir)
  - Landing (`docs/src/pages/index.tsx`): hero com a tagline da 8.1, botões "Get Started" (→ `/docs/intro`) e "View on GitHub"; nova seção "How a login works" com o diagrama ASCII do fluxo (mesmo do README); 3 cards de feature reais ("No Passwords, No Servers", "Self-Sovereign Identity", "Open Source SDKs") substituindo os 3 cards de exemplo do template (Easy to Use / Focus on What Matters / Powered by React)
  - `docs/docs/intro.mdx` reescrito com conteúdo real (o que é TruthID, why, how it works, SDKs, endereços dos contratos, link pro repo) — precisou ser feito junto porque o botão "Get Started" apontava pra lá e ainda tinha o tutorial genérico de 5 minutos do Docusaurus
  - Removidas `docs/docs/tutorial-basics/` e `docs/docs/tutorial-extras/` (tutorial genérico do Docusaurus, fora do roadmap de conteúdo da Fase 8) e as imagens de exemplo (`undraw_*.svg`, `docusaurus.png`) que ficaram órfãs
  - **Decisão de estilo com o usuário**: ofereci 3 direções (dark/cripto, minimalista claro, cor de marca forte com previews) — escolhida **dark/cripto moderno**
  - Tema (`docs/src/css/custom.css`): paleta ciano (`#4dd0e1` no dark, `#0e7490` no light) substituindo o verde padrão do Docusaurus; fundo `#0b0f14` no dark mode (navbar/footer/surface ajustados); fontes Space Grotesk (títulos) + Inter (corpo) via Google Fonts; `colorMode.defaultMode: 'dark'` no `docusaurus.config.ts` (toggle pro claro continua disponível, só mudou o padrão)
  - Hero (`index.module.css`): fundo navy fixo com glow ciano sutil, sempre escuro independente do toggle (mesma lógica que `hero--primary` já usava antes, só que com cor própria); botões customizados (`ctaPrimary` sólido ciano, `ctaSecondary` outline ciano) em vez do cinza padrão do Infima
  - `HomepageFeatures`: 3 ícones SVG desenhados à mão (cadeado, carteira, code brackets — não copiados de nenhuma lib de ícones, pra evitar problema de licença/precisão sem acesso à internet pra conferir paths) + visual de card (borda, fundo, padding)
  - `docs/static/img/logo.svg`: o dinossauro padrão do Docusaurus trocado por uma marca mínima (escudo com check, em ciano) — provisória; identidade visual de verdade continua sendo a etapa 8.10
  - Achado pequeno: o rodapé tinha um link em português ("Introdução") sobrando da configuração da 8.1 — corrigido para "Introduction"
  - **Verificação visual real**: sem `chromium-cli` disponível neste ambiente, instalei `playwright` (CLI via `npx`, depois o pacote local em `/tmp/pwtest` pra rodar um script que clica no toggle de tema) e o Chromium headless (`npx playwright install chromium`, já estava em cache de uma sessão anterior). Tirei screenshots da home e da `/docs/intro` nos dois modos (claro/escuro) e revisei visualmente antes de fechar a etapa — nenhuma quebra de layout, contraste ok nos dois modos
- Conceitos ensinados:
  - Por que o hero pode ter uma cor fixa (sempre escuro) enquanto o resto do site segue o toggle claro/escuro — é o mesmo padrão que o tema padrão do Docusaurus já usa com `hero--primary`, só que aqui generalizado pra cor de marca em vez da paleta default
  - CSS Modules + `:global()`: como estilizar uma classe global do Infima (`.hero__title`) de dentro de um arquivo `.module.css` que por padrão escopa tudo localmente
  - Diferença entre instalar só o *browser* do Playwright (`npx playwright install chromium`, baixa o binário) e instalar o *pacote* (`npm install playwright`, dá acesso à API JS pra script de automação) — precisou dos dois pra simular o clique no toggle de tema
- **Próximo passo ao retomar**: etapa 8.3 (guia de introdução — já tem uma versão mínima real em `docs/docs/intro.mdx` da 8.2, mas a etapa formal do roadmap pode expandir) ou seguir a ordem que o usuário preferir dentro da Fase 8 (8.4-8.9 são referência de SDK/segurança/contratos; 8.10 é a identidade visual definitiva, que já tem uma base provisória desta sessão; 8.11 é o deploy final, que via Actions já está automático desde a 8.1)

### 2026-06-20 — Sessão 30

- **Achado de segurança da Sessão 29 resolvido** — token do GitHub que estava em texto puro na URL do `origin` (`git remote -v`)
  - Investigação ampliou o achado: além do token atual (`ghp_nb9Sts...`), o `~/.bash_history` tinha **mais um token antigo** (`ghp_eZSoJ2...`, de um `set-url` anterior) — total de 2 tokens vazados, 3 linhas no histórico
  - Usuário revogou os 2 tokens manualmente no GitHub (Settings → Developer settings → Personal access tokens)
  - Gerada chave SSH nova (`~/.ssh/id_ed25519_github`, ed25519) com passphrase, dedicada a esta máquina; usuário adicionou a chave pública em Settings → SSH and GPG keys
  - `origin` trocado de `https://ghp_...@github.com/...` para `git@github.com:masterlxz/truthid.git`
  - As 3 linhas com token foram removidas do `~/.bash_history` (resto do histórico preservado)
  - **Configurado agente SSH persistente via systemd** (`ssh-agent.socket`, antes existia mas estava `disabled`/`inactive` — habilitado com `systemctl --user enable --now`) + `export SSH_AUTH_SOCK=".../ssh-agent.socket"` adicionado ao `~/.bashrc`. Resultado: a partir de agora, qualquer terminal novo já enxerga o mesmo agente — passphrase é pedida uma vez por sessão de login, não uma vez por terminal
- **Obstáculo real, não trivial**: digitar a passphrase interativamente não funcionou nem rodando o comando direto (Bash tool) nem via o prefixo `!` (execução no terminal do usuário) — em ambos os casos o processo não tinha um TTY de verdade atrelado (`tty` retornava "not a tty"), e como a sessão tinha `DISPLAY` setado (ambiente gráfico KDE Plasma), o `ssh-add` (diferente do `ssh-keygen`, que abre `/dev/tty` direto e funcionou normalmente) preferiu tentar um askpass gráfico — e o caminho padrão hardcoded `/usr/lib/ssh/ssh-askpass` não existe no Arch. Resolvido encontrando o `ksshaskpass` (KDE Plasma, pacote `ksshaskpass`, já instalado) e forçando seu uso com `SSH_ASKPASS=/usr/bin/ksshaskpass SSH_ASKPASS_REQUIRE=force` — abre uma janela gráfica de senha de verdade na tela do usuário, fora do terminal/chat
- Verificação: `ssh -T git@github.com` retornou "Hi masterlxz!"; `git fetch origin` funcionou via SSH sem nenhuma credencial em texto puro
- Conceitos ensinados:
  - Por que uma URL com token embutido (`https://TOKEN@github.com/...`) é pior que SSH: o token fica em texto puro em qualquer lugar que registre o comando (histórico do shell, `git remote -v`, logs) — a chave privada SSH nunca trafega nem é exibida, só a assinatura
  - Diferença entre um agente SSH "ad-hoc" (`ssh-agent -s`, processo solto, morre se for matado ou a máquina reiniciar) e um agente "socket-activated" do systemd (nasce sob demanda na primeira conexão, mesmo socket compartilhado por todos os terminais da sessão de login)
  - `SSH_ASKPASS` / `SSH_ASKPASS_REQUIRE=force`: como o OpenSSH decide entre pedir a senha no terminal (via `/dev/tty`) ou abrir um programa gráfico — `ssh-add` (mas não `ssh-keygen`) cai pro caminho gráfico quando não acha um TTY E existe `DISPLAY` no ambiente
  - Por que revogar e gerar uma chave nova é melhor que só trocar a URL do remote: o token antigo continuava válido (e utilizável por qualquer um que tivesse visto o histórico) até ser revogado de propósito na origem (GitHub), não só removido localmente
- **Próximo passo ao retomar**: etapa 7.4 (documentação pública) ou 7.5 (abrir o repositório no GitHub) — o bloqueio de segurança que adiava a 7.5 está resolvido

### 2026-06-20 — Sessão 30 (continuação — etapa 7.4)

- **Etapa 7.4 concluída** — criado `README.md` na raiz do repositório (não existia nenhum antes; só havia `CONTEXT.md` e `PROJECT_STATE.md`, ambos documentos internos)
  - Escopo decidido com o usuário: só o README raiz por agora — `CONTRIBUTING.md`/`SECURITY.md` ficam pra depois (talvez etapa 7.5, quando o repositório for aberto)
  - Conteúdo: tagline, diagrama ASCII do fluxo de login (mesmo estilo do `sdk/README.md`), seção "Why", "How it works" resumido, tabela de arquitetura (contracts/desktop/mobile/sdk/integration com link relativo pra cada pasta), tabela de endereços Base Mainnet (linkados pro Basescan), tabela dos 3 SDKs publicados (linkados pro npm/PyPI/RubyGems), instruções de build pra cada componente, seção de segurança, license
  - `desktop/README.md` e `mobile/README.md` são boilerplate puro do `tauri create`/`flutter create` (nunca customizados) — decisão de não editá-los agora e manter as instruções de build auto-contidas no README raiz em vez de linkar pra eles
  - **Decisão sobre contato de segurança**: primeira versão do README usava o e-mail pessoal do usuário pra reports de vulnerabilidade — antes de fixar isso permanentemente num arquivo público (e no histórico do git), perguntado ao usuário; decisão final foi apontar pra "GitHub Security tab" (private vulnerability reporting nativo do GitHub) em vez de expor e-mail. Esse recurso precisa ser habilitado nas configurações do repositório quando ele for aberto (etapa 7.5)
  - Todos os links relativos (`contracts/`, `sdk/README.md`, `LICENSE` etc.) validados com `[ -e "$f" ]` antes de fechar — todos existem
  - Âncora `sdk/README.md#smart-contracts` confirmada batendo com o heading real (`## Smart Contracts`); âncora equivalente pra `PROJECT_STATE.md` foi evitada (heading tem "—" e "&", slug do GitHub pra esses casos é difícil de prever sem testar de verdade) — link aponta só pro arquivo, sem fragmento
- Conceitos ensinados:
  - Por que o README raiz é "a porta de entrada" de um projeto open source — diferente de um doc interno (`PROJECT_STATE.md`) ou de um PRD (`CONTEXT.md`), ele é escrito pra quem nunca viu o projeto antes
  - Risco de fixar dados pessoais (e-mail) em texto versionado: mesmo que removido depois, o histórico do git mantém a versão antiga acessível pra sempre (mesmo princípio do achado dos tokens, mais cedo nesta sessão)
  - GitHub Security Advisories / private vulnerability reporting: mecanismo nativo que permite reportar bugs de segurança sem expor contato pessoal nem abrir issue pública
- **Próximo passo ao retomar**: etapa 7.5 (abrir o repositório no GitHub) — decidir nessa etapa o que fazer com `PROJECT_STATE.md`/`CONTEXT.md` (manter público, trimar, ou mover pra fora do controle de versão) e habilitar o private vulnerability reporting

### 2026-06-20 — Sessão 30 (continuação — etapa 7.5)

- **Etapa 7.5 concluída — e com ela, a Fase 7 inteira.**
- **Descoberta importante**: o repositório já estava público desde a criação (2026-06-04) — `curl https://api.github.com/repos/masterlxz/truthid` sem nenhuma autenticação retornou `"private": false`. A etapa nunca foi de fato "abrir" o repositório; era mais sobre arrumar a casa antes de tratar ele como aberto de propósito
  - Varredura em `git log --all -p` (todos os commits, todos os branches) procurando por padrões de segredo (`ghp_`/`gho_`, chaves PEM, chaves AWS, `.env` commitado, `PRIVATE_KEY=`/`MNEMONIC=` com valor real): **nenhum segredo de verdade foi encontrado em momento algum do histórico**. Os únicos "falsos positivos" foram bytecode Solidity (hex longo) e os placeholders do `contracts/.env.example` (`PRIVATE_KEY=0xsua_chave_privada_aqui`). O PAT do achado da Sessão 29 nunca esteve em conteúdo versionado — só na configuração local do git (`.git/config`, fora do repositório)
  - Decisão consciente do usuário sobre `PROJECT_STATE.md`/`CONTEXT.md`: manter os dois como estão. `CONTEXT.md` é um PRD limpo, fica público sem ressalvas. `PROJECT_STATE.md` tem conteúdo "de bastidor" (diretriz de ensino endereçada à IA, log sessão-a-sessão) mas, sem segredo real, isso é só uma questão de tom/apresentação — não vale o esforço de criar um repositório separado ou reescrever histórico só por isso
- Fechamento prático:
  - `README.md` (novo) e as edições do `PROJECT_STATE.md` da etapa 7.4 foram commitados (`73de3e9`, mensagem `docs: etapa 7.4 — criar README.md público na raiz`) e enviados via SSH — primeiro push do repositório usando a chave nova em vez do PAT
  - "Private vulnerability reporting" habilitado pelo usuário em Settings → Code security and analysis — confirmado via API (`GET /repos/.../private-vulnerability-reporting` → `{"enabled": true}`)
  - Descrição e topics do repositório (campo "About") ficaram como melhoria opcional, não bloqueante — usuário pode fazer quando quiser
- Conceitos ensinados:
  - Por que consultar a API REST do GitHub sem autenticação é um jeito confiável de checar se um repositório é público (retorna 404 pra privado sem auth, 200 com `"private": false` pra público) — mais rápido que confiar na memória de decisões antigas
  - Diferença entre "segredo na configuração local do git" (`.git/config`, nunca sai da máquina a menos que alguém leia o disco) e "segredo no conteúdo versionado" (vai pra todo lugar que clonar o repositório, inclusive em commits antigos) — o achado da Sessão 29 era do primeiro tipo, por isso nunca esteve realmente exposto publicamente mesmo com o repo já sendo público
- **Fase 7 — Mainnet & Lançamento: CONCLUÍDA.** Próximo passo, se o usuário quiser continuar: Fase 8 (Documentação Web — site Docusaurus) ou qualquer outra prioridade fora do roadmap original

### 2026-06-20 — Sessão 29

- **Etapa 7.3 (publicar SDKs) concluída** — os três pacotes `truthid-sdk@0.1.0` publicados:
  - npm: https://www.npmjs.com/package/truthid-sdk
  - PyPI: https://pypi.org/project/truthid-sdk/0.1.0/
  - RubyGems: `truthid-sdk` (gem push concluído pelo usuário)
- **Trabalho de preparação antes da publicação** (nenhum dos 3 manifests tinha metadata suficiente pra um publish de qualidade):
  - Licença decidida com o usuário: **MIT**. Criado `LICENSE` na raiz + cópia em `sdk/typescript/`, `sdk/python/`, `sdk/ruby/` (cada gerenciador de pacote só inclui arquivos dentro da própria pasta do pacote, não da raiz do monorepo)
  - `sdk/typescript/package.json`: adicionado `license`, `author`, `repository` (com campo `directory` pra apontar pro subdiretório no monorepo), `homepage`, `bugs`, `keywords`, `engines`, e principalmente `files: ["dist", "README.md", "LICENSE"]` — sem isso o tarball publicaria `src/` e o `example/` também. Script `prepublishOnly` adicionado pra garantir build antes de publicar
  - `sdk/python/pyproject.toml`: adicionado `authors`, `license = "MIT"` (formato SPDX, moderno), `readme`, `classifiers`, `[project.urls]`. Testado com `python -m build` + `twine check` (PASSED nos dois artefatos) antes de publicar
  - `sdk/ruby/truthid-sdk.gemspec`: adicionado `authors`, `license`, `homepage`, `metadata` (homepage/source/bug tracker), `description` maior, e `README.md`/`LICENSE` em `spec.files` (antes só pegava `lib/**/*`)
  - Criado um `README.md` curto em cada pasta de SDK (resumo + link pro `sdk/README.md` completo) — necessário porque os 3 registros (npm, PyPI, RubyGems) só pegam o README de dentro da própria pasta do pacote, não de um nível acima
  - Antes de tocar em qualquer arquivo, confirmado via `registry.npmjs.org`/`pypi.org`/`rubygems.org` (HTTP 404 nos três) que o nome `truthid-sdk` estava livre nos três registros
  - Cada pacote foi empacotado localmente antes do publish real (`npm pack --dry-run`, `python -m build` + `twine check`, `gem build`) pra confirmar que só os arquivos certos entravam no pacote — pegou erros de configuração sem gastar uma tentativa de publish de verdade
- **Obstáculo no npm**: primeira tentativa de `npm publish` falhou com `403 Forbidden — Two-factor authentication or granular access token with bypass 2fa enabled is required`. O usuário não tinha 2FA ativado na conta npm. Resolvido ativando 2FA — o `npm publish` subsequente abriu um fluxo de autenticação via navegador (`Authenticate your account at: https://www.npmjs.com/auth/cli/...`) em vez de pedir OTP no terminal (fluxo mais novo do npm CLI)
- **Obstáculo no PyPI**: primeira tentativa de `twine upload` teve um aviso de "password empty" e falhou com 403 — aparentemente o token não foi colado corretamente no prompt interativo (`Enter your API token:`). Repetir o comando e colar de novo funcionou
- **Achado de segurança, fora do escopo da 7.3**: o `git remote -v` revelou um Personal Access Token do GitHub em texto puro na URL do `origin` (`https://ghp_...@github.com/...`). Reportado ao usuário — recomendação de revogar esse token e trocar pra SSH ou credential helper antes da etapa 7.5 (abrir o repositório)
- Conceitos ensinados:
  - Por que cada gerenciador de pacote (npm/pip/gem) só empacota arquivos dentro da pasta do próprio manifest — README/LICENSE de um nível acima (compartilhados entre os 3 SDKs do monorepo) não entram automaticamente, por isso a cópia/duplicação
  - Diferença entre testar o empacotamento (`--dry-run`, `build`, `gem build`) e o publish real — o primeiro é local e repetível, o segundo é público e praticamente irreversível (não dá pra "despublicar" de verdade em nenhum dos 3 registros)
  - Por que 2FA é hoje obrigatório (ou efetivamente exigido) pra publicar em registros públicos de pacotes — mitiga o cenário de uma conta comprometida injetar uma versão maliciosa numa dependência usada por terceiros (ataque de supply chain)
- **Próximo passo ao retomar**: etapa 7.4 (documentação pública) ou 7.5 (abrir o repositório no GitHub — não esquecer de revogar o token exposto antes)

### 2026-06-18 — Sessão 26

- **Propagação dos endereços de Base Mainnet** — fecha a pendência deixada na etapa 7.1 (Sessão 25)
  - Antes de editar, investigação revelou que a troca não era só endereço: os 3 SDKs (TypeScript, Python, Ruby) já tinham um parâmetro `network` desde a Fase 5, mas os endereços de contrato eram constantes fixas (sempre Sepolia) — ou seja, escolher `"base-mainnet"` conectaria no RPC certo mas consultaria o contrato errado
  - Decisão tomada com o usuário: completar o design multi-rede já existente nos SDKs (endereços passam a ser um mapa por rede) em vez de descartá-lo; desktop e mobile (apps finais, não SDKs) ficam fixos em mainnet
  - **SDK TypeScript** (`sdk/typescript/src/`):
    - `contracts.ts`: `IDENTITY_REGISTRY_ADDRESS`/`DEVICE_REGISTRY_ADDRESS`/`SESSION_REGISTRY_ADDRESS` (string fixa) → `..._ADDRESSES` (`Record<Network, string>` com as duas redes)
    - `client.ts`: construtor agora lê `DEVICE_REGISTRY_ADDRESSES[config.network]` e `SESSION_REGISTRY_ADDRESSES[config.network]`, guarda em propriedades de instância (`this.deviceRegistryAddress`, `this.sessionRegistryAddress`) usadas nas chamadas `readContract`
    - `network` continua obrigatório (sem default) — decisão original da Fase 5 mantida
  - **SDK Python** (`sdk/python/truthid/`): mesmo padrão com dicts (`_ADDRESSES[network]`); default do construtor mudou de `"base-sepolia"` para `"base-mainnet"`
  - **SDK Ruby** (`sdk/ruby/lib/truthid/`): mesmo padrão com hashes (`.fetch(network)`); default mudou para `"base-mainnet"` em `Client.new` e também no factory `TruthID.new_client` (estava em arquivo separado, `lib/truthid.rb`, achado só depois de já ter corrigido `client.rb` — fácil de esquecer porque é a API alternativa "estilo Ruby" do mesmo client)
  - **Desktop**: `wagmi.ts` (chain `baseSepolia` → `base`, RPCs trocados para mainnet — `blockpi` testado e estava fora do ar (erro 521), substituído por `base.drpc.org` depois de validar com `eth_chainId` via curl), `App.tsx` (textos "Base Sepolia" → "Base Mainnet"), `config/contracts.ts` (3 endereços)
  - **Mobile**: `blockchain_service.dart` — RPC e endereço do SessionRegistry trocados (único contrato que o mobile consulta diretamente; Identity/Device Registry não são chamados pelo app mobile)
  - **Achado extra**: `sdk/README.md` tinha uma tabela "Smart Contracts (Base Sepolia)" com os endereços **originais da Sessão 7**, já obsoletos desde o redeploy da Sessão 24 — nunca tinha sido atualizada. Corrigida e expandida com duas tabelas (Mainnet + Sepolia). Quickstart e exemplos completos (Express/Flask/Sinatra) atualizados para usar mainnet por padrão; seção "Networks" reescrita para refletir os novos defaults
  - Verificação: `tsc --noEmit` limpo no SDK TypeScript e no desktop; `ruby -c` e `ast.parse` confirmaram sintaxe válida nos arquivos Python/Ruby alterados
- Conceitos ensinados:
  - Endereço de contrato não é universal — o mesmo bytecode deployado em redes diferentes gera endereços diferentes; um SDK multi-rede precisa de um endereço por rede, não um endereço fixo com um RPC trocável
  - Por que validar RPCs antes de colocar em produção: um RPC público pode cair (blockpi retornou erro 521 da Cloudflare no teste) — `eth_chainId` é uma forma rápida de confirmar que o endpoint está de pé E aponta pra rede certa (retorno `0x2105` = 8453 = Base Mainnet)
  - Diferença entre "endereço fixo importado" e "propriedade de instância": ao migrar de constante de módulo para mapa por rede, o valor precisa ser resolvido uma vez no construtor e guardado no objeto — não pode mais ser referenciado direto do import dentro dos métodos
- **Próximo passo ao retomar**: ver continuação desta sessão abaixo — etapa 7.2 foi redefinida como "sinalização on-chain"

### 2026-06-18 — Sessão 26 (continuação)

- **Correção de imprecisão no PROJECT_STATE.md**: investigando a ideia de remover o servidor de sinalização antes do lançamento, descobri que o `SignalingAdapter` — citado em várias linhas como "✓ já existe no desktop" — **nunca foi implementado**. É uma decisão registrada na Sessão 15, mas o código sempre usou WebSocket direto:
  - `desktop/src/components/ManageDevices.tsx`: `new WebSocket(...)`
  - `mobile/lib/screens/pairing_screen.dart` e `approval_screen.dart`: `WebSocket.connect(...)`
  - Corrigidas as linhas na tabela "Decisões de Arquitetura em Aberto" e na seção "Roadmap de Evoluções Planejadas → Sinalização on-chain" para refletir o estado real
  - Também achei e registrei uma contradição que já existia no documento: uma linha dizia que a migração on-chain estava condicionada a "latência Base < 1s", outra dizia "~2s é aceitável" — sinal de que a viabilidade real (latência de handshake WebRTC completo, não só tempo de bloco) nunca foi validada na prática
- **Decisão do usuário**: o servidor de sinalização precisa desaparecer **antes do lançamento público** (antes de publicar os SDKs, documentação, abrir o repositório) — não é mais uma evolução opcional do roadmap, é requisito do lançamento
  - Etapa 7.2 redefinida: em vez de "Relay Service em produção" (que seria jogar trabalho fora, hospedando algo que vai ser removido), passa a ser "Sinalização on-chain"
- **Próximo passo**: desenhar a arquitetura de sinalização sem servidor (sem código ainda) — ver continuação 2 abaixo, que descartou a ideia on-chain em favor de transporte direto

### 2026-06-18 — Sessão 26 (continuação 2)

- **Arquitetura de sinalização sem servidor desenhada e implementada** — substitui o plano de "sinalização on-chain" da continuação anterior
  - Discussão com o usuário revelou que o app de produção nunca usou WebRTC de verdade (sem `RTCPeerConnection`/SDP/ICE — abandonado na Sessão 20) — o "relay" (`signaling/main.py`) era só um repassador de mensagens 1:1, o que simplificou bastante o problema
  - Descoberta importante: os exemplos do `sdk/README.md` (Express/Flask/Sinatra) já assumiam o site rodando seu próprio backend pra `/auth/verify` — ou seja, o SDK nunca precisou do relay; só o app mobile (`approval_screen.dart`) tinha ficado presa no protocolo antigo
  - Usuário pediu pra manter a direção original do pareamento (computador mostra QR, celular lê) — investigação mostrou que isso é impossível sem servidor: o computador precisa aprender o endereço do celular, e a única forma de um dado viajar celular→computador sem rede é o celular mostrar (a chave do device não tem fundos pra pagar gas e anunciar on-chain, por design da Fase 4). Resolvido invertendo a direção: celular mostra, computador lê
  - Avaliada e descartada a opção on-chain pra sinalização: custaria gas por tentativa de login (mesmo as não completadas), seria mais lento (múltiplas transações em sequência), e a chave do device não tem fundos pra pagar gas de qualquer forma
  - **Login**: QR do site passa a conter `{action: "truthid-auth", challenge: {...}, callbackUrl}` — challenge embutido direto (sem round-trip pra receber), resposta assinada vai via `POST` HTTPS direto pro `callbackUrl` (o próprio `/auth/verify` do site). `https://` obrigatório, checado no mobile antes de enviar
  - **Pareamento**: mobile mostra QR com `{action: "truthid-device", pubKey, label}` + endereço em texto selecionável; desktop cola o endereço (câmera fica pra depois, Fase 8) e segue com commit-reveal já existente, sem mudança on-chain. Confirmação via polling de `getDevice()` (leitura gratuita), não por mensagem — o antigo "pair-confirmed" nunca tinha funcionado de verdade (achado da Sessão 22)
  - Trade-off aceito: mobile não resolve mais `@username` ao parear (sem getter on-chain de id→username sem mudar contrato já em mainnet) — mostra "Identidade #&lt;id&gt;"
  - **Mobile**: `blockchain_service.dart` generalizado (`_ethCall` aceita qualquer endereço de contrato, antes só funcionava com SessionRegistry) + novo `getDevice()`; `local_storage_service.dart` simplificado pra só `identityId`; nova tela `show_device_qr_screen.dart` (substitui `pairing_screen.dart`, deletado); `devices_screen.dart` e `sessions_screen.dart` atualizados pra nova API; `approval_screen.dart` reescrito sem WebSocket (HTTP POST direto); `main.dart` perdeu o `GlobalKey` (não precisa mais — pareamento não é mais disparado por scan); nova dependência `qr_flutter` no `pubspec.yaml`
  - **Desktop**: `ManageDevices.tsx` (`PairDevice`) perdeu WebSocket/fetch/`QRCodeSVG`, ganhou campo de colar endereço validado com `isAddress` (viem); dependência `qrcode.react` removida do `package.json` (sem mais uso)
  - **SDK/docs**: `sdk/README.md` — diagrama "How It Works" corrigido (já estava errado antes desta sessão, mostrava um "TruthID Relay" que nem os exemplos documentavam), nova seção "Building the QR code" documentando o payload esperado, exemplos Express/Flask/Sinatra atualizados pra retornar `{action, challenge, callbackUrl}`; mesma mudança no `sdk/typescript/example/server.js`
  - **Removido do repositório**: `signaling/`, `turn/`, `webrtc-demo/` — confirmado código morto (não usados pelo app real)
  - **CONTEXT.md (PRD) também atualizado**, a pedido do usuário (decisão consciente de manter um doc histórico em sincronia, diferente da recomendação inicial de deixar como estava) — seções "Add Device", "Authentication Flow", "Communication Layer" e a ideia de monetização "hosted relay service" (não fazia mais sentido)
  - Bug pré-existente encontrado e corrigido de passagem: `test/widget_test.dart` referenciava uma classe `MyApp` que não existe desde a Sessão 18 (app renomeado pra `TruthIDApp`) — `flutter analyze` nunca tinha sido rodado nesse projeto antes desta sessão
  - Verificação: `tsc --noEmit` limpo no desktop; `flutter analyze` rodado via Docker (ver resultado final no início da próxima sessão se não tiver sido confirmado ainda nesta)
- Conceitos ensinados:
  - Por que a direção de um QR code é determinada por quem TEM o dado, não por quem inicia a ação — analogia com compartilhar senha de Wi-Fi por QR
  - Diferença entre "sem servidor" (não tem nenhum servidor) e "sem servidor do TruthID" (o backend do site integrador continua existindo, só não é mais operado pelo TruthID) — não é P2P de verdade, é só remover um intermediário de terceiro
  - Por que a chave do device não pode pagar gas: separação deliberada entre device key (só assina) e controller wallet (tem fundos e autoridade) — decisão da Fase 4, reaproveitada aqui pra descartar a opção on-chain
  - SDK como biblioteca agnóstica de transporte: nunca decidiu como o challenge/resposta viajam — só a lógica de criar/verificar. Analogia: como a biblioteca `requests` do Python não decide pra qual URL você chama
- **Próximo passo ao retomar**: confirmar resultado do `flutter analyze`/`flutter test` no mobile, depois testar o fluxo de pareamento e login manualmente (ver skill `/verify` ou `/run`). Depois disso, seguir pra etapa 7.3 (publicar SDKs) ou 7.4 (documentação pública)

### 2026-06-19 — Sessão 27 (interrompida por limite de sessão)

- **Objetivo**: verificação manual end-to-end do fluxo pós-Sessão 26 (pareamento + login sem servidor do TruthID) contra Anvil local, antes de seguir pra etapa 7.3
- **Ambiente de teste montado** (tudo local, nada em mainnet):
  - Anvil em `127.0.0.1:8545`, os 4 contratos redeployados localmente: IdentityRegistry `0x5FbDB2315678afecb367f032d93F642f64180aa3`, DeviceRegistry `0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512`
  - Desktop (`App.tsx`, `wagmi.ts`, `config/contracts.ts`) temporariamente apontado pra `foundry` em vez de `base` mainnet — tudo marcado `// TEMP (verify session)... revertido após o teste`
  - `vite.config.ts` ganhou `cacheDir: "/tmp/vite-cache-truthid"` (workaround: `node_modules/.vite` tinha sido criado como root via Docker numa sessão anterior, sem permissão de escrita no host)
  - `desktop/_tmp_wallet_relay.mjs`: servidor HTTP na porta 8546 fazendo o papel do MetaMask pro Playwright, assina de verdade com a conta 0 do Anvil
  - `desktop/_tmp_playwright_test4.mjs`: automação Playwright do desktop (wallet fake via `window.ethereum` mockado, cola endereço do device, registra) — versão final após 3 iterações de debug (endereço EIP-55 malformado etc., ver `_tmp_playwright_test.mjs`/`test2`/`test3`)
  - `desktop/_tmp_test_backend.mjs`: backend HTTPS (porta 8443, cert self-signed em `/tmp/truthid-test-cert/`) fazendo o papel do "site integrador" — mesma lógica de `TruthIDClient.verifyAuthResponse`, mas com viem direto contra o Anvil
  - `mobile/lib/main.dart`: `_openScanner()` temporariamente pula a câmera e busca o challenge direto de `https://10.0.2.2:8443/auth/challenge` (10.0.2.2 = alias do host visto pelo emulador Android)
  - `mobile/lib/services/blockchain_service.dart`: RPC e endereço do DeviceRegistry trocados pro Anvil/local
  - Emulador Android dentro do container `truthid-emu` (imagem `mobile-flutter:latest`, `docker run -d --device /dev/kvm --network host`), com `emulator` + `system-images;android-34;google_apis;x86_64` + `platforms;android-34` instalados via `sdkmanager` **em tempo de execução** (não vêm do `mobile/Dockerfile` — esse só tem `cmdline-tools`/`platform-tools`/`platforms;android-36`/`build-tools`)
  - Certificado self-signed instalado no trust store do sistema do emulador (precisou `adb root` + `disable-verity` + `remount` + reboot, duas vezes — primeira tentativa com hash de subject errado)
- **Resultado confirmado até a interrupção**:
  - ✅ Pareamento desktop↔mobile via colar endereço, commit-reveal, confirmado on-chain (`getDevice` retornou `identityId=1, label="Pixel de teste (Anvil)", exists=true, revoked=false`) e detectado pelo mobile via polling ("Identidade #1" na tela)
  - 🔄 Fluxo de login (mobile assina challenge real do backend → POST HTTPS → backend verifica on-chain) **estava em andamento**: backend confirmado respondendo (`curl https://127.0.0.1:8443/auth/challenge` ok), app mobile reconstruído com o bypass do scanner — mas a sessão travou logo após o toque no ícone de scan (coordenada 1017,200); nunca confirmamos se a `ApprovalScreen` abriu e se a assinatura/POST funcionou
  - ⬜ Não feito: reverter as configurações TEMP e escrever o relatório de verificação final
- **IMPORTANTE pra retomada — o ambiente efêmero morreu**: a máquina parece ter reiniciado entre sessões (container `truthid-emu` saiu com exit 137, Anvil não está mais rodando, `/tmp` foi limpo — cert, screenshots e logs perdidos). **O emulador Android (pacote `emulator` + imagem de sistema `android-34`) não estava em volume nomeado** (só `mobile_flutter_pub_cache`/`mobile_gradle_cache` são volumes) — vai precisar ser reinstalado do zero (~20min de download/descompressão na sessão anterior). Se for repetir esse tipo de teste de novo, considerar `docker commit truthid-emu mobile-flutter:latest` depois de instalar emulator+system-image, ou um volume nomeado pra `/opt/android-sdk`, pra não pagar esse custo outra vez
- **Para retomar**: recriar o ambiente (Anvil + redeploy + container + emulador + AVD + cert) do zero seguindo os passos acima, terminar o teste de login, depois reverter TODAS as mudanças marcadas `// TEMP (verify session)` (`git diff` em App.tsx/contracts.ts/wagmi.ts/vite.config.ts/main.dart/blockchain_service.dart) e apagar os arquivos `_tmp_*` e `contracts/broadcast/Deploy.s.sol/31337/` (deploy local efêmero, sem valor de registro — diferente de `8453`/`84532`, que SÃO versionados). Depois disso, etapa 7.2 fica de fato encerrada e segue pra 7.3 (publicar SDKs) ou 7.4 (documentação)

### 2026-06-20 — Sessão 28 (continuação da Sessão 27 — verificação concluída)

- **Ambiente recriado com sucesso**, reaproveitando os volumes Docker `emu_avd` e `emu_sdk_extra` que a Sessão 27 já tinha deixado prontos (achado só agora — não estavam documentados, ficaram como volumes órfãos). Isso evitou os ~20min de reinstalação do `emulator`+imagem de sistema: só foi preciso reinstalar o pacote `emulator` em si (pequeno, ~1min) e reaproveitar a AVD `test` já provisionada (`docker run ... -v emu_avd:/root/.android/avd -v emu_sdk_extra:/opt/android-sdk/system-images ...`)
- **Obstáculo real encontrado**: o disco da máquina estava com só 1.1GB livres (94% cheio) ao tentar persistir a instalação via `docker commit` — a operação ficou pendurada e pausou o container. Causa raiz: ~40GB em imagens Docker `<none>` (dangling), sobras de builds/commits anteriores, nunca limpas. `docker image prune -f` liberou esse espaço. Lição: **antes de instalar algo grande num container Docker neste projeto, checar `df -h /` e `docker system df` primeiro** — o host historicamente acumula imagens soltas
- Criar uma AVD nova do zero exige a emulator reservar ~7.4GB pra partição de userdata; reaproveitar uma AVD já existente (com os `.img`/`.qcow2` já alocados) evita essa exigência — por isso montar `emu_avd` directly em vez de rodar `avdmanager create avd` de novo foi o que resolveu, não a limpeza de disco em si (a limpeza só evitou o risco de o host ficar sem espaço durante o teste)
- **Bug de rede descoberto e corrigido**: o emulador (API 34 com WiFi simulado/netsim) tem duas interfaces de rede — `eth0` (SLIRP clássico, gateway `10.0.2.2`) e `wlan0` (rede WiFi simulada própria, sem rota pra fora). O kernel do Android escolhia a rota mais específica (`wlan0`, /24) pra alcançar `10.0.2.2`, e como essa interface não tem saída real, toda conexão do app pro backend de teste falhava com `SocketException: Network is unreachable`. Resolvido com `adb shell svc wifi disable`, forçando o roteamento de volta pro `eth0` clássico. Isso é específico de emuladores com API recente (netsim) — não acontecia nas sessões anteriores possivelmente por terem usado uma imagem/config diferente, ou por terem feito o teste rápido demais para a rota errada se estabelecer
- **Resultado final — fluxo de login completo testado e validado**, com app mobile real (Flutter rodando no emulador, não mock) e backend de teste fazendo o papel do site integrador com `viem` + verificação on-chain real:
  1. Mobile fez `GET https://10.0.2.2:8443/auth/challenge` (bypass temporário da câmera, ver Sessão 27)
  2. `ApprovalScreen` abriu mostrando o challenge real (`Site: 10.0.2.2:8443`)
  3. Usuário (automatizado) tocou "Aprovar" → mobile assinou com a chave do device e fez `POST https://10.0.2.2:8443/auth/verify`
  4. Backend recuperou o signer da assinatura, conferiu contra `deviceAddress`, chamou `isDeviceActive`/`getDevice` no `DeviceRegistry` on-chain → **`{ valid: true, identityId: 1n, deviceAddress: '0xb808037eFD76E834929b4F4927061E227962b8aF' }`**
  - Pareamento (Sessão 27) e login (Sessão 28) juntos cobrem o fluxo completo descrito na Sessão 26 (continuação 2) ponta a ponta, com componentes reais (não só testes automatizados em `integration/*.ts`)
- **Etapa 7.2 agora está de fato verificada e encerrada.** Próximo passo: etapa 7.3 (publicar SDKs) ou 7.4 (documentação pública)
- Limpeza pós-teste: todas as mudanças `// TEMP (verify session)` revertidas (`git checkout` em App.tsx/contracts.ts/wagmi.ts/vite.config.ts/main.dart/blockchain_service.dart), arquivos `_tmp_*.mjs` apagados, `contracts/broadcast/Deploy.s.sol/31337/` removido, processos (Anvil/vite/relay/backend) e container `truthid-emu` finalizados. **Os volumes `emu_avd` e `emu_sdk_extra` foram mantidos de propósito** (não são limpos automaticamente por `docker system prune` porque não estão "dangling") — útil pra próxima vez que precisar repetir esse tipo de teste manual
- Conceitos ensinados: por que uma AVD nova precisa de mais espaço em disco do que uma reaproveitada (alocação de partição vs. arquivos já existentes); diferença entre a rede "celular" (SLIRP, sempre tem saída) e a rede "WiFi simulada" (netsim, isolada) num emulador Android; por que limpar imagens Docker `dangling` é seguro (não tem tag, não é referenciada por nenhum container)

### 2026-06-17 — Sessão 25

- **Etapa 7.1 concluída** — Deploy dos 4 contratos em Base Mainnet
  - Decisão de arquitetura registrada antes do deploy: contratos **imutáveis** (sem proxy) — ver tabela "Decisões de Arquitetura em Aberto"
  - Carteira deployer: 2ª conta derivada da Ledger do usuário (não a principal) — endereço público para sempre via `owner()`, então separado da carteira pessoal
  - Descoberta do HD path da Ledger: testado por tentativa com `cast wallet address --ledger --mnemonic-derivation-path "..."` — índice 0 (`m/44'/60'/0'/0/0`) é a conta principal; a conta certa usa o padrão "Ledger Live legacy" `m/44'/60'/1'/0/0` (índice de conta no 3º componente do path, não no último)
  - Fluxo seguido para cada um dos 2 scripts (`Deploy.s.sol`, `DeploySessionRegistry.s.sol`): simulação primeiro (`forge script` sem `--broadcast`, mostra endereços previstos e custo estimado sem gastar nada) → confirmação explícita do usuário → execução real com `--broadcast` e confirmação física na Ledger por transação
  - `DeploySessionRegistry.s.sol` atualizado com os endereços novos de IdentityRegistry/DeviceRegistry antes de rodar (mesmo padrão da Sessão 24)
  - Todos os 4 contratos verificados no Basescan via `forge verify-contract` com Etherscan V2 API (`--verifier-url ".../v2/api?chainid=8453"`)
  - Custo real total: ~0,000055 ETH — bem abaixo da estimativa de simulação, gas da Base Mainnet seguiu o mesmo padrão de custo baixíssimo da testnet
  - Endereços (Base Mainnet): ver tabela na etapa 7.1 acima
- Bug encontrado e corrigido: `.env` não tinha quebra de linha final — `echo "VAR=valor" >> .env` colou a nova variável na mesma linha da anterior (`BASESCAN_API_KEY` + `BASE_MAINNET_RPC_URL` viraram uma string só), e o forge não achava a variável. Corrigido separando as linhas.
- Conceitos ensinados:
  - HD path / derivação de contas numa mesma seed: uma Ledger gera infinitas contas a partir das mesmas 24 palavras, cada uma com um caminho `m/44'/60'/.../.../...` diferente — só muda qual número vai em qual posição do caminho
  - Padrão "Ledger Live legacy" vs padrão comum (MetaMask/outros): a posição do índice da conta no HD path muda entre os dois — por isso testar por tentativa foi necessário
  - Por que simular antes de fazer broadcast: `forge script` sem `--broadcast` roda a transação contra uma cópia local da blockchain (fork), mostra o resultado e o custo, sem nunca enviar nada de verdade — permite revisar antes de gastar
  - Por que a carteira do deploy não é a pessoal: `owner()` fica público e permanente no contrato; qualquer um pode olhar no Basescan e ligar aquele endereço ao projeto para sempre
- **Próximo passo ao retomar**: decidir quando propagar os endereços novos (mainnet) para desktop/mobile/SDKs, hoje ainda apontando para Base Sepolia — depois seguir para etapa 7.2 (Relay/sinalização em produção) ou 7.3 (publicar SDKs)

### 2026-06-15 — Sessão 23

- **Etapas 5.1 e 5.5 concluídas** — TypeScript SDK + exemplo Express.js
  - `sdk/typescript/src/contracts.ts`: ABIs e endereços dos 3 contratos (sem wagmi)
  - `sdk/typescript/src/types.ts`: tipos TypeScript — TruthIDClientConfig, AuthChallenge, AuthResponse, VerifyAuthResult, SessionInfo, DeviceStatus
  - `sdk/typescript/src/client.ts`: classe TruthIDClient
    - `constructor`: `createPublicClient` do viem — conexão somente-leitura com a blockchain
    - `createChallenge(origin)`: gera challenge com `randomUUID()` + timestamp — formato exato que o mobile assina
    - `verifyAuthResponse({ challenge, response })`: 6 verificações em sequência — approved, TTL, nonce, assinatura (recoverMessageAddress), device ativo, identityId
    - `verifySession(hash)`: lê SessionRegistry — `getSession` + `isSessionRevoked` em paralelo com Promise.all
    - `checkDeviceStatus(devicePubKey)`: lê DeviceRegistry — `getDevice`
  - `sdk/typescript/src/index.ts`: barrel export
  - `sdk/typescript/example/server.js`: servidor Express.js de exemplo
    - GET /auth/challenge: cria challenge, guarda em Map por nonce, auto-remove em 35s
    - POST /auth/verify: recupera challenge por nonce, remove (anti-replay), chama SDK, cria sessionToken
    - GET /api/profile: rota protegida com middleware requireAuth (Bearer token)
  - viem v1.21.4 (não v2.x) — v2 depende de `ox` que só funciona com moduleResolution: bundler
- Conceitos ensinados:
  - `createPublicClient` vs wagmi: conexão somente-leitura sem wallet, sem estado de UI — equivale a requests.Session() do Python
  - `recoverMessageAddress({ message, signature })`: recovers o endereço que assinou — inverso do signPersonalMessage
  - 6 camadas de verificação: cada uma cobre um vetor de ataque diferente (repúdio, replay por tempo, replay por conteúdo, assinatura falsa, device revogado, device inexistente)
  - `pendingChallenges.delete(nonce)`: remover o nonce após uso — impede replay mesmo dentro do TTL
  - `requireAuth` middleware: padrão Express de proteção de rotas — `req.headers.authorization?.split(' ')[1]`
  - Por que viem v1 e não v2: v2.x exige moduleResolution bundler (Vite); v1.x funciona com CommonJS puro
- **Próximo passo ao retomar**: Fase 6 — Integração & Testes E2E (etapa 6.2)

### 2026-06-16 — Sessão 24

- **Etapa 6.1 concluída** — Teste E2E do fluxo completo: criar identidade → registrar device → autenticar
  - Criado `integration/e2e.ts` — script TypeScript com tsx, sem framework de testes
  - Criado `integration/package.json` — projeto Node isolado com viem + tsx
  - Estratégia: Anvil (blockchain local em memória) para rodar sem gas, sem rede, sem ETH real
    - Deploy dos contratos reais (bytecodes do Foundry em `contracts/out/`) — mesmo código que vai para mainnet
    - Carteiras de teste do Anvil (private keys do mnemônico padrão "test test test ... junk")
  - Passo 1: Deploy do `IdentityRegistry` + `DeviceRegistry` com `walletClient.deployContract`
  - Passo 2: `createIdentity("alice")` — transação real, confirmada com `waitForTransactionReceipt`
  - Passo 3: `generatePrivateKey()` + `registerDevice(deviceAddress, label)` — simula Android Keystore/Secure Enclave
  - Passo 4: challenge/response completo — `crypto.randomUUID()` → `deviceAccount.signMessage()` → `recoverMessageAddress()` → `isDeviceActive()` → `getDevice()`
  - Todos os 6 passos passaram com ✅
- Conceitos reforçados:
  - `createPublicClient` (somente leitura) vs `createWalletClient` (escrita com conta)
  - `walletClient.deployContract()`: deploy pelo bytecode — parâmetros `abi`, `bytecode`, `args` (constructor)
  - `waitForTransactionReceipt({ hash })`: aguarda mineração e retorna receipt com `contractAddress`
  - `generatePrivateKey()` do viem — simula geração de chave no dispositivo móvel
  - Por que usar Anvil em vez de testnet: sem latência (block instantâneo), sem ETH necessário, reproducível
- **Próximo passo**: Fase 6 — etapa 6.5 (auditoria de segurança dos contratos)

### 2026-06-16 — Sessão 24 (continuação 7)

- **Redeploy dos 4 contratos na Base Sepolia** — necessário porque os 4 contratos mudaram de código (auditoria de segurança) desde o deploy original da Sessão 7
  - Carteira deployadora: `0x8814D40EF00B829fe0412112192C6Fb778CC2787` (mesma de sempre, saldo ~0,045 ETH antes do deploy)
  - `forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --private-key $PRIVATE_KEY`: deploya IdentityRegistry → DeviceRegistry → RecoveryManager → chama `setRecoveryManager` em sequência, tudo numa única execução de script (4 transações, todas confirmadas com `status: 0x1`)
  - `script/DeploySessionRegistry.s.sol` atualizado com os novos endereços de IdentityRegistry/DeviceRegistry antes de rodar (recebe os 2 endereços como constantes hardcoded no script)
  - Todos os 4 verificados no Basescan via `forge verify-contract` com Etherscan V2 API (`--verifier-url ".../v2/api?chainid=84532"`) — mesma receita da Sessão 8
  - Sanity check pós-deploy: `owner()` do IdentityRegistry retorna o endereço do deployer (confirma o fix do achado #1) e `totalIdentities()` retorna 0 (contrato novo, sem dados antigos)
  - Endereços antigos propagados e atualizados em 5 arquivos que tinham os endereços hardcoded: `desktop/src/config/contracts.ts`, `mobile/lib/services/blockchain_service.dart`, `sdk/typescript/src/contracts.ts`, `sdk/python/truthid/contracts.py`, `sdk/ruby/lib/truthid/contracts.rb` — confirmado via grep que nenhum endereço antigo restou, `tsc --noEmit` do desktop continua limpo
  - Endereços novos:
    - IdentityRegistry : 0x35D21c65980cBd2dAE7576e1bf6b8e46C9e180BF
    - DeviceRegistry   : 0x225c67a98c9D675fE595ae05a2F9249C34d9C60a
    - RecoveryManager  : 0xDd4CE29A35022741Bbe2F8f38aa185ddF41A8Fa7
    - SessionRegistry  : 0xdeD2Ad865069CA6546172926540D3A3Aa73C1CA6
- Erro encontrado e corrigido: primeira tentativa de deploy rodou só como simulação local (sem `--private-key`) — Foundry detectou o "sender padrão" (carteira de teste conhecida, insegura para broadcast real) e abortou antes de enviar qualquer transação. Nenhum ETH foi gasto nessa tentativa (confirmado comparando saldo antes/depois)
- Conceitos ensinados:
  - `forge script` sempre simula localmente primeiro (fork da chain real) antes de decidir se envia de verdade — só envia com `--broadcast` E um signer válido
  - "Sender padrão" do Foundry: endereço de teste bem conhecido (chave pública, sem segurança real) — usado só para simulação; broadcast real exige um signer explícito (`--private-key`, `--account` etc.)
  - `cast wallet address --private-key`: deriva o endereço público a partir da chave privada sem nunca expor a chave em texto — útil para confirmar qual carteira vai assinar antes de gastar gas de verdade
  - Verificação no Basescan exige reproduzir os mesmos `constructor args` ABI-encoded (`cast abi-encode`) que foram usados no deploy — o Basescan recompila o código e compara o bytecode resultante

### 2026-06-16 — Sessão 24 (continuação 6)

- **Achados #2, #6 e #7 da auditoria corrigidos** — usuário pediu para fechar "de vez", optando pelas versões completas em vez de mitigações leves
  - **Achado #6 (limite de guardians)**: `RecoveryManager.sol` ganhou `MAX_GUARDIANS = 20` + checagem em `configureGuardians`. 2 testes novos (`TooManyGuardians`, `ExactlyMaxGuardians`)
  - **Achado #2 (createSession permissionless)**: investigação prévia confirmou que `createSession` não tinha NENHUM caller real no código (nem desktop, nem mobile, nem SDKs) — liberdade total para redesenhar a assinatura sem quebrar integrações
    - `SessionRegistry.sol`: construtor passou a receber também o endereço do `DeviceRegistry`
    - `createSession(hash, identityId, devicePubKey, r, s, v)`: primeira verificação de assinatura ECDSA on-chain do projeto — `ecrecover` sobre `keccak256("\x19Ethereum Signed Message:\n32" + hash)`, comparado contra `devicePubKey` (prova de posse da chave privada)
    - Cross-check adicional: `_deviceRegistry.getDevice(devicePubKey)` precisa retornar `identityId` igual ao informado e `revoked == false` — sem isso, um atacante com SEU PRÓPRIO device real poderia criar sessões falsas atribuídas à identidade de outra pessoa
    - `contracts/script/DeploySessionRegistry.s.sol` atualizado com o novo argumento de construtor
    - Testes reescritos com `makeAddrAndKey` (em vez de `makeAddr`) para ter a chave privada disponível e assinar de verdade com `vm.sign`; 4 testes novos (assinatura inválida, identidade errada, device revogado, device desconhecido)
  - **Achado #7 (front-running em registerDevice)**: esquema commit-reveal
    - `DeviceRegistry.sol`: novo `commitDevice(bytes32 commitment)` grava `block.number`; `registerDevice` ganhou parâmetro `salt` e agora exige `commitment == keccak256(devicePubKey, salt, msg.sender)` já registrado em um bloco ANTERIOR
    - Por que incluir `msg.sender` no commitment: sem isso, alguém que visse devicePubKey+salt no momento da revelação (mempool) poderia "roubar" o registro copiando esses valores
    - 5 testes novos: sem commitment, revelar no mesmo bloco, salt errado, tentativa de roubar commitment de outra pessoa
    - Atualizado em cascata: `ManageDevices.tsx` e `DesktopDevice.tsx` (fluxo de 2 transações com máquina de estados `idle → committing → registering`), `contracts.ts` (ABI), e os 3 scripts de integração (`e2e.ts`, `e2e_revocation.ts`, `e2e_security.ts`)
  - Total: 120 testes Foundry passando (103 + 17 novos ao longo da sessão). `npx tsc --noEmit` limpo no desktop. 4 scripts de integração revalidados
  - **Os 4 contratos testnet (Base Sepolia) ficaram desatualizados** — redeploy necessário antes da Fase 7
- Conceitos ensinados:
  - Mempool e front-running: transações pendentes são públicas antes de confirmar — qualquer um pode "ler" e reagir antes da confirmação
  - Commit-reveal: esconder um valor por trás de um hash, revelar depois — clássico contra front-running (ex: leilões às cegas)
  - Por que incluir `msg.sender` no hash do commitment: liga o commitment a quem pode revelá-lo, fechando a janela de "roubo" na fase de reveal
  - Prova de posse via ECDSA: só quem tem a chave privada produz uma assinatura que recupera o endereço esperado via `ecrecover`
  - `"\x19Ethereum Signed Message:\n32"`: prefixo EIP-191 (personal_sign) para assinar um hash de 32 bytes — mesmo padrão usado em todo o resto do projeto (mobile, desktop, SDK)
  - `vm.sign` / `makeAddrAndKey` no Foundry: para assinar de verdade em teste, precisa da chave privada, não só do endereço — por isso a troca de `makeAddr` para `makeAddrAndKey`
  - Por que checar IDENTIDADE no DeviceRegistry além da assinatura: a assinatura prova posse da chave, mas não prova que aquele device "pertence" à identidade alegada — são dois fatos independentes que precisam ser verificados separadamente

### 2026-06-16 — Sessão 24 (continuação 4)

- **Etapa 6.5 concluída** — Auditoria de segurança manual dos 4 contratos (`IdentityRegistry`, `DeviceRegistry`, `RecoveryManager`, `SessionRegistry`)
  - Revisão função por função contra categorias clássicas: controle de acesso, reentrância, front-running, dependência de timestamp, DoS, validação de entrada
  - 7 achados registrados na tabela da Fase 6 (1 Crítico, 2 Médio/Alto, 2 Médio, 2 Baixo) — ver seção "Relatório da auditoria" acima
  - Achado crítico: `IdentityRegistry.setRecoveryManager` sem controle de acesso — qualquer endereço pode chamar antes do deploy oficial e se tornar o RecoveryManager (mesmo padrão do hack Parity Multisig 2017), ganhando poder de tomar qualquer identidade via `recoverController`
  - Achado SessionRegistry: `createSession` é permissionless por design (confirmado por teste `test_CreateSession_QualquerUmPodeCriar`) — investigação confirmou que isso é inofensivo hoje porque nenhum SDK usa `verifySession` como prova de login (o `server.js` de exemplo usa UUID próprio), mas é uma armadilha de confiança para integrações futuras
  - **Fase 6 — Integração & Testes E2E: CONCLUÍDA**
- Conceitos ensinados:
  - Front-running de inicialização: janela entre deploy e configuração — qualquer um pode "vencer a corrida" numa rede pública (MEV bots monitoram a mempool)
  - Checks-effects-interactions: atualizar estado antes de chamada externa evita reentrância — `executeRecovery` já segue esse padrão corretamente
  - Fail-closed vs fail-open: `isSessionRevoked` trata "não existe" como "revogado" — padrão de erro seguro
  - Trust boundary (limite de confiança): um contrato pode ser "seguro hoje" mas plantar uma armadilha se um integrador futuro confiar em uma garantia que o código nunca prometeu
  - Por que validar `address(0)`: sem chave privada correspondente, qualquer coisa atribuída a esse endereço fica permanentemente inacessível
- **Próximo passo**: decidir quais dos 7 achados corrigir antes da Fase 7 (Mainnet) — achado crítico (#1) deve ser corrigido antes de qualquer deploy público

### 2026-06-16 — Sessão 24 (continuação 5)

- **Correções da auditoria aplicadas** — achados #1, #3, #4 e #5 corrigidos (usuário decidiu corrigir Crítico + Médios, deixando #2/#6/#7 documentados para depois)
  - `IdentityRegistry.sol`:
    - Adicionado `address public immutable owner` + `constructor() { owner = msg.sender; }`
    - `setRecoveryManager`: adicionado `if (msg.sender != owner) revert NotOwner();` — fecha a janela de front-running de inicialização (achado #1)
    - `transferController` e `recoverController`: adicionado `if (newController == address(0)) revert InvalidNewController();` (achados #3/#4)
  - `RecoveryManager.sol`:
    - `proposeRecovery`: mesma validação de `address(0)` em `newController`, fail-fast para o guardian (achado #3)
    - Novo helper `_clearGuardianFlags(identityId, guardians)` — refatorado de um loop que já existia em `configureGuardians`
    - `executeRecovery`: depois de `recoverController` ter sucesso, chama `_clearGuardianFlags` e `delete _guardianConfigs[identityId]` — guardians antigos perdem o poder de propor recovery contra o novo controller (achado #5); novo controller precisa chamar `configureGuardians` para reativar
  - 7 testes novos no Foundry (`IdentityRegistry.t.sol` + `RecoveryManager.t.sol`): `test_Revert_TransferController_ToZeroAddress`, `test_Revert_SetRecoveryManager_NotOwner`, `test_SetRecoveryManager_OwnerCanCall`, `test_Owner_IsDeployer`, `test_Revert_ProposeRecovery_NewControllerIsZeroAddress`, `test_Revert_RecoverController_ToZeroAddress`, `test_ExecuteRecovery_ClearsOldGuardianConfig`
  - Total: 110 testes passando (103 + 7)
  - Reexecutados `integration/e2e.ts` e `integration/e2e_recovery.ts` contra os contratos corrigidos — passaram sem precisar alterar os scripts (já chamavam `setRecoveryManager` com a mesma wallet do deploy)
- Conceitos ensinados:
  - Por que `immutable` no `owner`: gravado direto no bytecode no deploy, sem slot de storage — leitura mais barata que uma variável normal
  - Refatorar um loop repetido (`configureGuardians` e `executeRecovery` precisavam da mesma lógica de "zerar guardian") em uma função interna reutilizável
  - `delete` em struct com mapping aninhado: `delete _guardianConfigs[identityId]` zera `guardians`, `threshold` e `configured` de uma vez — mas o `_isGuardian` (mapping separado) precisa ser limpo manualmente antes, senão fica "órfão" com `true` para endereços que já não deveriam contar
  - Ordem importa: ler `config.guardians` para limpar `_isGuardian` ANTES do `delete`, senão a lista já estaria vazia

### 2026-06-16 — Sessão 24 (continuação 3)

- **Etapa 6.4 concluída** — Testes de segurança (4 cenários de ataque)
  - Criado `integration/e2e_security.ts` com classe `SimulatedServer` (Map<nonce, challenge> + deleteAfterUse)
  - Teste 1 — Replay attack: 1ª tentativa aprovada → nonce deletado → 2ª tentativa rejeitada "Challenge not found or already used"
    - Demonstração de bug: sem `deleteAfterUse`, replay é aprovado — vulnerabilidade explícita
  - Teste 2 — Challenge expirado: `SimulatedServer` com TTL=1ms → aguarda 5ms → rejeitado "Challenge expired"
  - Teste 3 — Nonce mismatch: response com nonce fabricado → servidor não encontra no Map → rejeitado
  - Teste 4 — Assinatura de device errado: impostor assina com chave própria mas declara deviceAddress da Alice → `recoverMessageAddress` expõe o endereço real → rejeitado "Signature does not match device address"
- Conceitos ensinados:
  - Por que a assinatura continua válida no replay: criptografia não muda — a proteção é semântica (nonce one-time)
  - deleteAfterUse DEPOIS de todas as verificações: evita race condition onde dois requests concorrentes passam
  - `recoverMessageAddress`: dado mensagem + assinatura, devolve o endereço real do signatário — impostor não pode fingir outro endereço

### 2026-06-16 — Sessão 24 (continuação 2)

- **Etapa 6.3 concluída** — Teste E2E do fluxo de revogação
  - Criado `integration/e2e_revocation.ts`
  - Extraída função `verifyAuth()` independente (retorna `{valid, reason}` em vez de lançar exceção) para poder testar o caso de falha sem encerrar o processo
  - Passo 3: login com device ativo → aprovado ✅
  - Passo 4: `revokeDevice(devicePubKey)` + confirmação de `isDeviceActive` == false
  - Passo 5: mesmo device assina um novo challenge válido → rejeitado com "Device is not active or has been revoked" ❌ (esperado)
  - Ponto crítico do teste: device ainda tem chave privada e assina corretamente — a rejeição vem exclusivamente da consulta `isDeviceActive` na blockchain

### 2026-06-16 — Sessão 24 (continuação)

- **Etapa 6.2 concluída** — Teste E2E do fluxo de recovery M-de-N (3 de 5 guardians + timelock 7 dias)
  - Criado `integration/e2e_recovery.ts`
  - Deploy: IdentityRegistry + RecoveryManager (sem DeviceRegistry — não necessário para recovery)
  - `setRecoveryManager()` vincula o contrato ao IdentityRegistry (chamada one-time, só controller)
  - `configureGuardians("alice", [g1…g5], 3)` — Alice define quem pode recuperar e quantos precisam aprovar
  - `proposeRecovery()` → `approvalCount = 0` (propor ≠ aprovar — proposer precisa chamar approveRecovery separadamente)
  - G1, G2, G3 chamam `approveRecovery()` individualmente → approvalCount 1→2→3
  - `evm_increaseTime(7 * 24 * 3600 + 1)` + `evm_mine` — simula passagem do timelock no Anvil
  - `executeRecovery()` chamado por Bob (não precisa ser guardian — qualquer um executa)
  - Verificação: `getIdentity("alice").controller == bob.address` ✅ + `proposal.executed == true` ✅
- Bug encontrado e corrigido: chave privada do account 4 do Anvil termina em `...926a` (não `...926b`) — 1 caractere diferente
- Conceitos ensinados:
  - `evm_increaseTime` vs `evm_mine`: dois passos — agendar o offset e minerar o bloco para efetivar
  - Por que propor ≠ aprovar: o proposer pode querer revisar antes de votar; separação explícita de intenção
  - `executed: true` é gravado no contrato para impedir re-execução da mesma proposta
  - Qualquer endereço pode executar: beneficiado (Bob) pode não estar online quando o último guardian aprova

### 2026-06-14 — Sessão 22

- **Etapa 4.7 concluída** — Tela: Sessões ativas — **Fase 4 completa**
  - `lib/services/blockchain_service.dart`: novo serviço de leitura on-chain
    - `_ethCall(fn, params)`: faz `eth_call` JSON-RPC via `dart:io` (sem pacote `http`)
      - `fn.encodeCall(params)`: codifica parâmetros em ABI binário
      - Converte bytes → hex para enviar ao nó RPC
      - `fn.decodeReturnValues(hexString)`: decodifica resposta do nó em tipos Dart
    - `getSessionsForIdentity(identityId)`: busca hashes via `getSessionsByIdentity`, depois
      `getSession` + `isSessionRevoked` em paralelo com `Future.wait`
    - `SessionInfo`: data class com hash, devicePubKey, createdAt, isRevoked
    - Fix: `decodeReturnValues` recebe `String` hex (sem `0x`), não `Uint8List`
  - `lib/screens/sessions_screen.dart`: nova tela de sessões
    - Se não pareado: tela explicativa ("Pareie este dispositivo...")
    - Se pareado: lê `identityId` do storage, consulta blockchain, exibe lista
    - `_SessionCard`: card com hash truncado, data, "Este device" se for o device atual, chip Ativa/Revogada
    - Aviso amarelo: revogação requer controller wallet (desktop)
    - `RefreshIndicator` para recarregar manualmente
  - `lib/main.dart`: `_SessionsPlaceholder` removido, substituído por `SessionsScreen`
  - APK debug gerado com sucesso
- Conceitos ensinados:
  - `eth_call` JSON-RPC: leitura de contrato via HTTP — não gasta gas, não precisa de wallet
  - `ContractAbi.fromJson` + `DeployedContract`: define o contrato em Dart para encoding/decoding
  - `fn.encodeCall(params)` / `fn.decodeReturnValues(hex)`: conversão ABI ↔ Dart sem biblioteca extra
  - `dart:io HttpClient`: fazer requisições HTTP sem o pacote `http` — nativo do Dart
  - `Future.wait([a, b])`: disparar múltiplas chamadas async em paralelo — equivalente a `asyncio.gather()` em Python
  - `whereType<T>()`: filtrar nulls e fazer cast em uma lista — equivale a `[x for x in lista if x is not None]`
  - Revogação requer controller wallet: o device key só assina challenges, não transações de gerenciamento
- **Fase 4 — Mobile App: CONCLUÍDA**
- **Próximo passo ao retomar**: Fase 5 — SDKs (TypeScript SDK primeiro)

### 2026-06-14 — Sessão 21

- **Etapa 4.6 concluída** — Tela: Meus dispositivos
  - `lib/services/local_storage_service.dart`: novo serviço para persistir identidade pareada
    - `savePairedIdentity(identityId, username)`: grava no `flutter_secure_storage`
    - `getPairedIdentity()`: retorna record `({String identityId, String username})?` ou null
    - `clearPairedIdentity()`: apaga os dados salvos
  - `lib/screens/devices_screen.dart`: nova tela "Dispositivos"
    - `DevicesScreenState` (público, sem `_`): necessário para `GlobalKey` funcionar de fora do arquivo
    - `reload()`: método público chamado pelo `RootScreen` via `GlobalKey` após pareamento
    - Mostra card com endereço do device (copiável), chip de status (pareado / não registrado)
    - Se pareado: exibe `@username` e botão "Remover pareamento"
    - Se não pareado: exibe dica informativa em azul
    - `RefreshIndicator` + `ListView`: habilita gesto "puxar para atualizar"
    - Botão "Parear com identidade" chama `onScanPairing` (callback do pai)
  - `lib/screens/pairing_screen.dart`: nova tela do fluxo de pareamento
    - Estados: `connecting → sent → confirmed / error`
    - Conecta ao relay WebSocket com `signalingUrl` e `roomId` do QR
    - Envia `{ type: "pair-request", pubKey, label: "TruthID Mobile" }`
    - Aguarda `{ type: "pair-confirmed", username, identityId }` do desktop
    - `Navigator.pop(context, true/false)`: avisa o pai se o pareamento foi bem-sucedido
    - Desktop atual não manda `pair-confirmed` ainda — mobile fica em estado `sent`
  - `lib/main.dart`: refatorado para estrutura com abas
    - `DeviceInfoScreen` substituído por `RootScreen`
    - `IndexedStack`: mantém todas as abas na memória (não destrói ao trocar de aba)
    - `BottomNavigationBar`: abas "Dispositivos" e "Sessões"
    - `GlobalKey<DevicesScreenState>`: referência ao State do DevicesScreen para chamar `reload()`
    - Botão de scan movido para o `AppBar` (ícone no canto superior direito)
    - `push<bool>` para `PairingScreen`: recebe `true/false` como resultado da navegação
    - Aba "Sessões" é um placeholder (`_SessionsPlaceholder`) para a etapa 4.7
  - APK debug gerado com sucesso
- Conceitos ensinados:
  - `BottomNavigationBar`: barra de abas no rodapé — padrão de navegação de apps mobile
  - `IndexedStack`: empilha todas as telas, mostra apenas a do índice ativo — preserva estado entre trocas de aba
  - `GlobalKey<T>`: referência direta ao `State` de um widget — permite chamar métodos de fora do widget
  - State público (sem `_`): necessário quando o `GlobalKey` é usado em outro arquivo
  - `push<T>` + `pop(context, value)`: retornar valores entre telas — o filho avisa o pai do resultado
  - `RefreshIndicator`: gesto "puxar para atualizar" — requer filho scrollável (`ListView`)
  - Record Dart `({String a, String b})`: retornar múltiplos valores nomeados sem criar uma classe — equivalente a `namedtuple` do Python
- **Próximo passo ao retomar**: Etapa 4.7 — Tela: Sessões ativas

### 2026-06-14 — Sessão 20

- **Etapas 4.4 e 4.5 concluídas** — Tela de aprovação de login + assinatura do challenge
  - `lib/screens/approval_screen.dart`: nova tela com máquina de estados (`_Status` enum)
    - `_connect()`: abre WebSocket (`dart:io`) com servidor de sinalização, envia `{ type: "ready" }`
    - `_handleMessage()`: recebe `{ type: "challenge", nonce, issuedAt, origin }`, muda estado para `challenge`
    - `_buildChallengeUI()`: exibe nome do site, hora do pedido, botões Aprovar/Recusar
    - `_approve()`: chama `signChallenge()` do `DeviceKeyService`, envia `auth-response` com assinatura secp256k1 + deviceAddress
    - `_reject()`: envia `auth-response { approved: false }` sem assinar
  - `lib/main.dart`: roteamento por `action` — `"truthid-auth"` abre `ApprovalScreen`; outros actions mostram snackbar
  - `webrtc-demo/website.html`: reformulado como demo de auth completo
    - Gera QR com `{ action: "truthid-auth", signalingUrl, roomId }` via `qrcodejs`
    - Aguarda `{ type: "ready" }` do mobile, libera botão de challenge
    - Envia challenge via WebSocket (não P2P), recebe resposta via WebSocket
    - Verifica assinatura secp256k1 com `ethers.verifyMessage()` (compatível com `signPersonalMessageToUint8List()`)
  - APK debug gerado com sucesso
  - Fix recorrente: `sudo chown -R masterlxz:masterlxz mobile/lib/` (Docker cria como root)
  - `flutter_webrtc 0.10.8` incompatível com Flutter 3.44.2 (remove `PluginRegistry.Registrar` da V1 API) — decisão: usar WebSocket relay em vez de WebRTC P2P (segurança equivalente: nonce + TTL + secp256k1; privacidade P2P pode ser adicionada quando o pacote tiver compat)
- Conceitos ensinados:
  - `dart:io` `WebSocket.connect()`: conexão persistente bidirecional — diferente de `http.get` (dispara e esquece), fica aberta e recebe eventos assíncronos
  - `ws.listen(onData, onError, onDone)`: 3 callbacks para os 3 eventos do ciclo de vida do WebSocket
  - Máquina de estados com `enum`: quando uma tela tem muitos estados possíveis, um enum é mais claro que múltiplos `bool` (`_scanned`, `_loading`, `_hasError`...)
  - `switch (_status)` no `build()`: expressão pattern matching do Dart 3 — cada estado gera uma UI diferente sem `if/else` aninhados
  - `_responded` flag: mesmo padrão do `_scanned` do scanner — garante que a resposta seja enviada exatamente uma vez mesmo que o usuário toque duas vezes
  - `jsonEncode(_challenge)`: serializar o challenge exatamente como recebido antes de assinar — qualquer diferença de espaço/ordem invalidaria a verificação
  - `ethers.verifyMessage(msg, sig)`: recupera o endereço Ethereum que assinou a mensagem — é o inverso de `signPersonalMessageToUint8List()`; se a assinatura for válida, retorna o endereço correto
- **Próximo passo ao retomar**: Etapa 4.6 — Tela: Meus dispositivos

### 2026-06-14 — Sessão 19

- **Etapa 4.3 concluída** — Scanner de QR code
  - `pubspec.yaml`: adicionado `mobile_scanner: ^6.0.0` (instalou 6.0.11)
  - `android/app/src/main/AndroidManifest.xml`: adicionado `<uses-permission android:name="android.permission.CAMERA" />`
  - `lib/screens/scan_screen.dart`: tela de câmera com `MobileScanner`
    - `_scanned` flag: evita processar o mesmo QR múltiplas vezes (câmera roda a 30fps)
    - `onDetect`: extrai `rawValue`, tenta parsear como JSON, retorna payload via `Navigator.pop`
    - QR inválido: reseta `_scanned` e exibe SnackBar — usuário pode tentar de novo
  - `lib/main.dart`: adicionado botão "Escanear QR" na `DeviceInfoScreen`
    - `_openScanner`: abre `ScanScreen` com `Navigator.push`, aguarda retorno assíncrono
    - Resultado temporário: dialog com `action` + `roomId` (será substituído pela `ApprovalScreen` na 4.4)
  - APK debug gerado com sucesso (instalou Android SDK Platform 34/35 e CMake 3.22.1 automaticamente)
  - Fix recorrente: `sudo chown -R masterlxz:masterlxz mobile/android` (Docker criou pasta como root)
- Conceitos ensinados:
  - Permissão de câmera Android: declarar no manifest (quais recursos o app pode usar) + runtime dialog (o sistema pede ao usuário na primeira vez)
  - `mobile_scanner`: wrapper Dart sobre as APIs nativas de câmera/barcode — lida com o popup de permissão automaticamente
  - `Navigator.push` / `Navigator.pop`: pilha de telas — `pop(valor)` devolve dados para a tela anterior
  - `await Navigator.push<T>()`: `Future<T?>` — a tela anterior espera assincronamente o retorno
  - `_scanned` flag: padrão para operações que devem ocorrer exatamente uma vez (câmera emite eventos contínuos)
  - `firstOrNull`: extensão de List em Dart 3 — retorna primeiro elemento ou null (equivale a `next(iter, None)` em Python)
  - `mounted`: checar se o widget ainda está na árvore antes de usar `context` após um `await`
- **Próximo passo ao retomar**: Etapa 4.4 — Tela: Aprovar login (exibir quem está pedindo, aprovar/recusar)

### 2026-06-14 — Sessão 18

- **Etapa 4.2 concluída** — Geração de key pair no dispositivo (Android Keystore)
  - `pubspec.yaml`: adicionados `flutter_secure_storage: ^9.2.4` e `web3dart: ^2.7.3`
  - `lib/services/device_key_service.dart`: serviço de chave do device
    - `_getOrCreateKey()`: gera key pair secp256k1 na primeira execução, carrega do storage nas seguintes
    - `getDeviceAddress()`: retorna endereço Ethereum (formato EIP-55 checksumado) — é isso que vai pro `DeviceRegistry`
    - `signChallenge()`: assina JSON do challenge com prefixo Ethereum personal_sign
    - Chave privada armazenada como hex no `flutter_secure_storage` (cifrado pelo Android Keystore)
  - `lib/main.dart`: substituído contador demo por `DeviceInfoScreen` que exibe o endereço do device
  - APK debug gerado com sucesso (148MB)
  - Fix: `sudo chown -R masterlxz:masterlxz mobile/lib` (Docker criou pasta como root na sessão anterior)
- Conceitos ensinados:
  - Device key vs controller wallet: são chaves separadas — device key não tem fundos, só assina challenges
  - Android Keystore/iOS Secure Enclave: cofre de hardware que cifra o storage; não suporta secp256k1 nativamente
  - Solução: chave secp256k1 gerada em software, privada cifrada pelo Keystore (padrão de wallets mobile)
  - `Random.secure()`: fonte de entropia do SO — equivalente a `secrets.token_bytes()` em Python
  - `Future<T>` + `async/await` em Dart: equivalente a `async def` + `await` em Python
  - `setState()`: notifica Flutter que o estado mudou e a tela precisa ser redesenhada
  - `initState()`: roda uma vez quando a tela é criada — lugar certo para carregar dados assíncronos
  - `signPersonalMessageToUint8List()`: adiciona prefixo Ethereum antes de assinar (evita assinar transações acidentalmente)
  - EIP-55: formato checksumado de endereço Ethereum (maiúsculas/minúsculas como checksum visual)
- **Próximo passo ao retomar**: Etapa 4.4 — Tela: Aprovar login

### 2026-06-13 — Sessão 17

- **Etapa 4.1 concluída** — Setup Flutter com Docker
  - Docker data-root movido para `/home/masterlxz/.docker/storage` (root estava 100% cheia)
  - VM Kali Linux removida (liberou 16GB no root)
  - `mobile/Dockerfile`: Ubuntu 22.04 + JDK 17 + Android SDK 36 + Flutter stable (3.44.2)
  - `mobile/docker-compose.yml`: volumes para pub cache e Gradle cache (em /home, não na raiz)
  - `mobile/dev.sh`: `./dev.sh shell` (bash interativo) ou `./dev.sh build` (APK direto)
  - Projeto Flutter criado com `flutter create --org com.truthid --project-name truthid_mobile .`
  - Primeiro APK debug gerado com sucesso: `build/app/outputs/flutter-apk/app-debug.apk`
  - Fix: `--allow-unauthenticated` no apt (GPG signature issue com Ubuntu 22.04 no Docker)
  - Fix: `flutter clean && flutter pub get` para resolver pub cache interrompido pelo disco cheio
- Conceitos ensinados:
  - Flutter: um código → iOS e Android (Dart, tipagem obrigatória, async/await nativo)
  - Docker para mobile: compila o APK no container, instala no celular — sem X11 necessário
  - `data-root` do Docker: onde ficam imagens e volumes — pode ser movido para qualquer partição
  - `gradle_cache` como volume: Gradle baixa ~400MB na primeira vez; volume persiste entre sessões
  - `flutter clean && flutter pub get`: reset do estado de build quando pub cache fica inconsistente
- **Próximo passo ao retomar**: Etapa 4.2 — Geração de key pair no dispositivo (Android Keystore)

### 2026-06-13 — Sessão 16

- **Fase 3 concluída** — etapa 3.8 completa
- Conceitos ensinados:
  - GitHub Actions: runners são VMs na nuvem (ubuntu/windows/macos-latest) que o GitHub sobe automaticamente
  - `strategy.matrix`: gera múltiplos jobs a partir de uma lista — evita repetir o workflow 3x
  - `fail-fast: false`: se um SO falhar, os outros continuam
  - Cache Rust (`Swatinem/rust-cache`): primeira execução ~15min, seguintes ~3min
  - `tauri-apps/tauri-action`: action oficial que compila e já cria GitHub Release com instaladores anexados
  - `releaseDraft: true`: release fica como rascunho para revisão antes de publicar
  - `GITHUB_TOKEN`: precisa de `permissions: contents: write` para criar Release — não vem habilitado por padrão
  - `targets: "all"` no tauri.conf.json: gera todos os formatos suportados por SO (Linux: .deb + AppImage)
  - Trigger em tags (`v*`): build só dispara ao criar tag de versão (ex: `git tag v0.1.2 && git push origin v0.1.2`)
  - PAT do GitHub precisa do escopo `workflow` para fazer push em `.github/workflows/`
- Arquivo criado: `.github/workflows/build.yml`
  - Linux: ubuntu-22.04, gera `.deb` + AppImage, instala libwebkit2gtk/libdbus/libsecret (keyring)
  - Windows: windows-latest, gera `.msi`
  - macOS: macos-latest, gera `.dmg`
  - `npm ci --legacy-peer-deps` (wagmi requer TS >=5.9.3, projeto usa 5.8.3)
- Builds v0.1.2 passaram nos 3 SOs — Release draft criada no GitHub com instaladores anexados
- **Próximo passo ao retomar**: Fase 4 — Mobile App (Flutter)

### 2026-06-13 — Sessão 15
- Sessão de arquitetura + etapa 3.5 concluída
- Decisão: sessões armazenadas como hash keccak256 on-chain
  - Dados originais (site, device, timestamp, nonce) ficam locais no dispositivo do usuário
  - Blockchain guarda só o hash → privado (ninguém sabe o que representa) mas auditável
  - Revogação granular: usuário fornece dados originais → contrato verifica hash → marca como revogado
  - SDK dos sites consulta "hash está revogado?" sem ver os dados reais
  - Custo estimado: ~R$ 0,002 por login na Base. Latência aceitável: ~2s para gravação
- Decisão: SignalingAdapter — sinalização WebRTC abstraída atrás de interface plugável
  - Hoje: WebSocketSignaling (servidor FastAPI já implementado na Fase 2)
  - Futuro: OnChainSignaling (eventos na blockchain, ~R$ 0,002/login, latência ~7-10s hoje tendendo a cair)
  - Motivação: sinalização é stateless — pode migrar de implementação sem afetar contratos de identidade
  - Contratos de identidade ficam na Base; sinalização pode usar qualquer chain ou protocolo
- `SessionRegistry.sol`: novo contrato — createSession, revokeSession, revokeAllSessions (truque O(1) via timestamp), isSessionRevoked
  - 23 testes novos, total geral: 103 testes passando
  - Deployado e verificado na Base Sepolia: 0x93B56d40B304269Ee23f84A1cF3BD7B338514b42
- `DeploySessionRegistry.s.sol`: script de deploy isolado (reutiliza contratos já deployados)
- `contracts.ts`: adicionado SESSION_REGISTRY_ADDRESS + SESSION_REGISTRY_ABI (funções + eventos)
- `ActiveSessions.tsx`: tela de sessões ativas
  - 4 leituras encadeadas: getIdentity → getSessionsByIdentity → getSession (paralelo) → getDevice (paralelo)
  - Revogação individual e revogação em massa
  - Mostra label do device em vez do endereço bruto
- `App.tsx`: navegação por abas entre Dispositivos e Sessões ativas
- Conceito consolidado: contratos Solidity = PostgreSQL (estrutura + regras), TypeScript = ORM (lê e escreve via wagmi)
- Próximo passo: etapa 3.8 — build para Linux, Windows, macOS

### 2026-06-09 — Sessão 14
- Etapa 3.4 concluída — tela gerenciar dispositivos
  - `contracts.ts`: adicionado `getIdentity` ao IdentityRegistry ABI; adicionado DeviceRegistry (endereço + ABI com `registerDevice`, `revokeDevice`, `getDevicesByIdentity`, `getDevice`)
  - `ManageDevices.tsx`: componente com 3 partes — lista de devices, revogação, pareamento via QR
    - Leituras encadeadas: `getUsernameByController` → `getIdentity` → `getDevicesByIdentity` → `getDevice` por device
    - `useReadContracts` (plural) para buscar detalhes de múltiplos devices em paralelo
    - Revogação: padrão `writeContract` + `useWaitForTransactionReceipt` (mesmo da 3.3)
    - Pareamento: `POST /rooms` no signaling server → gera QR com `{ action, signalingUrl, roomId }` → WebSocket aguarda mobile
    - `useEffect` + `useRef` para ciclo de vida do WebSocket
  - `App.tsx`: verificação de rede com `useSwitchChain` (Base Sepolia chain 84532); estado de carregamento enquanto lê username; roteamento CreateIdentity vs ManageDevices
  - `wagmi.ts`: transport com `fallback` em 3 RPCs públicos da Base Sepolia; corrigido mapeamento de porta do signaling server (8000→8080)
  - Bugs encontrados e corrigidos:
    - Carteira na rede errada (Sepolia vs Base Sepolia) → adicionado `useSwitchChain`
    - `useWaitForTransactionReceipt` travado → RPC sem URL explícita; corrigido com `fallback` de RPCs
    - Conflito MetaMask + Rabby sobre `window.ethereum` (cosmético, não bloqueante)
    - Signaling server mapeamento de porta errado (container 8080, host 8000)
    - `useReadContracts` retorna `.result` não `.data`
  - Conceitos ensinados: hooks React (useState, useEffect, useRef), useReadContracts plural, wagmi transport fallback, network switching, EIP-6963
- Próximo passo: etapa 3.5 — tela sessões ativas (listar, revogar selecionadas, revogar todas)

### 2026-06-08 — Sessão 13
- Etapas 3.2 e 3.3 concluídas
  - 3.2: integração com wallet (wagmi + viem)
    - Pacotes instalados dentro do Docker: `wagmi`, `viem`, `@tanstack/react-query` (--legacy-peer-deps por TypeScript 5.8 vs 5.9 exigido pelo wagmi v3)
    - `src/config/wagmi.ts`: configuração central — Base Sepolia, conector `injected`, transporte HTTP
    - `src/main.tsx`: WagmiProvider + QueryClientProvider envolvendo o app
    - `src/components/ConnectWallet.tsx`: botão conectar/desconectar usando useAccount, useConnect, useDisconnect
    - Conector `injected` funciona no browser (dev); WalletConnect será adicionado na etapa 3.8 (build Tauri)
  - 3.3: tela de criar identidade
    - `src/config/contracts.ts`: endereço e ABI mínimo do IdentityRegistry (3 funções)
    - `src/components/CreateIdentity.tsx`: formulário com validação, 3 hooks wagmi encadeados
    - useReadContract: leitura gratuita (isUsernameTaken, getUsernameByController)
    - useWriteContract: chama createIdentity, cobre fase MetaMask (isPending)
    - useWaitForTransactionReceipt: aguarda confirmação da rede (isConfirming → isSuccess)
    - App.tsx: renderização condicional — ConnectWallet sempre visível, CreateIdentity só quando conectado
  - Conceitos ensinados: ABI, leitura vs escrita on-chain, ciclo de vida de transação, hooks React como observadores, desestruturação, renderização condicional, `as const`, `enabled` no useReadContract
- Próximo passo: etapa 3.4 — tela gerenciar dispositivos (adicionar via QR, revogar)

### 2026-06-07 — Sessão 12
- Etapas 2.7 e 2.8 concluídas — **Fase 2 completa**
  - 2.7: TURN self-hostável (coturn) como fallback WebRTC
    - `turn/turnserver.conf`: porta 3478, realm `truthid.local`, `lt-cred-mech` explícito
    - `turn/Dockerfile`: imagem `coturn/coturn`, expõe TCP+UDP 3478
    - ICE_SERVERS atualizado nos dois HTMLs (STUN + TURN com credenciais)
    - Discussão: TURN centraliza disponibilidade, não segurança (dados DTLS-cifrados)
  - 2.8: testes manuais de integração — todos passaram
    - Happy path: P2P → challenge → aprovação → assinatura válida ✅
    - Login recusado: mobile recusa → website exibe mensagem correta ✅
    - TTL expirado: 31s de espera → website rejeita por expiração ✅
  - Conceitos ensinados: STUN vs TURN, NAT simétrico, relay vs P2P, lt-cred-mech
- Próximo passo: Fase 3 — Desktop App (Tauri + React + TypeScript)

### 2026-06-06 — Sessão 11
- Etapas 2.5 e 2.6 concluídas
  - 2.5: resposta assinada trafega P2P do mobile para o website
    - Mobile gera key pair ECDSA P-256 na inicialização (Web Crypto API)
    - Botões Aprovar/Recusar aparecem ao receber o challenge
    - Aprovação assina o challenge com chave privada e envia `{type, approved, nonce, signature, publicKey}` pelo data channel
    - Website verifica assinatura com a chave pública recebida
  - 2.6: proteção anti-replay com TTL + nonce tracking
    - TTL de 30s: `Date.now() - issuedAt > 30_000` → rejeita antes da verificação
    - `usedNonces` (Set): mesmo nonce não pode ser aceito duas vezes
    - As duas camadas juntas bloqueiam replay attacks mesmo de bots rápidos
  - Conceitos ensinados: ECDSA, par de chaves, assinatura digital, replay attack, TTL, nonce
- Próximo passo: etapa 2.7 — TURN self-hostável (coturn) como fallback

### 2026-06-06 — Sessão 10
- Etapas 2.3 e 2.4 concluídas
  - 2.3: conexão WebRTC P2P funcionando entre website e mobile (browser)
    - Fix race condition: mobile envia "ready" antes do website criar oferta
    - Fix CORS: adicionado CORSMiddleware no FastAPI
    - Fix link do mobile: URL relativa em vez de absoluta com /webrtc-demo/
  - 2.4: challenge trafega P2P do website para o mobile
    - Formato: `{type, nonce, issuedAt, origin}` — nonce via `crypto.randomUUID()`
    - Mobile exibe pedido de login formatado ao receber o challenge
  - Conceitos ensinados: fetch vs requests, WebSocket, RTCPeerConnection, ICE candidates, STUN, SDP offer/answer, data channel
- Próximo passo: etapa 2.5 — resposta assinada trafega P2P do mobile para o website

### 2026-06-06 — Sessão 9
- Etapas 2.1 e 2.2 concluídas — servidor de sinalização WebRTC implementado
  - Decisão: servidor leve WebSocket (stateless, open source, self-hostável) — descartados on-chain (lento, caro) e DHT (complexo, experimental)
  - Stack: Python + FastAPI + uvicorn — escolha baseada no conhecimento do usuário (vs Go/Node.js)
  - Implementação: `signaling/main.py` (~35 linhas) com 3 endpoints: `GET /health`, `POST /rooms`, `WS /rooms/{id}`
  - Lógica: sala criada pelo website (UUID), celular entra com o mesmo ID, mensagens retransmitidas entre os dois, sala deletada quando vazia
  - Self-hosting: `signaling/Dockerfile` (python:3.12-slim, ~10MB) — `docker build` + `docker run` testados e funcionando
  - Conceitos ensinados: WebSocket vs HTTP, async/await, venv no Arch Linux, Docker básico
- Próximo passo: etapa 2.3 — conexão WebRTC real no browser (website cria oferta → celular responde via sinalização)

### 2026-06-05 — Sessão 8
- Etapa 1.7 concluída — 3 contratos verificados no Basescan
  - Ferramenta: `forge verify-contract` com Etherscan V2 API (`https://api.etherscan.io/v2/api?chainid=84532`)
  - IdentityRegistry: sem constructor args — verificação direta
  - DeviceRegistry e RecoveryManager: constructor arg = endereço do IdentityRegistry (encodado com `cast abi-encode`)
  - Links: sepolia.basescan.org/address/<endereço> para cada contrato
- **Fase 1 concluída** — todos os 7 contratos implementados, testados, deployados e verificados
- Próximo passo: Fase 2 — decidir canal de sinalização WebRTC (etapa 2.1)

### 2026-06-05 — Sessão 7
- Etapas 1.6 concluída — deploy dos 3 contratos na Base Sepolia
  - Script de deploy: `contracts/script/Deploy.s.sol`
  - Conceito ensinado: scripts Foundry herdam de `Script`, `vm.startBroadcast()` delimita transações reais
  - IdentityRegistry : 0xd4484aDD6DCd0919568B6365882cDB207fE27D9c
  - DeviceRegistry   : 0xe87633b148cf7a7F6c60DdA84AD7f4D3a9eC187F
  - RecoveryManager  : 0x66be956D14b9383aE9a58f70edD6Cae406Eb960f
  - Custo total: ~0.000068 ETH (gas Base Sepolia é quase zero)
  - Carteira deployadora: 0x8814D40EF00B829fe0412112192C6Fb778CC2787
- Próximo passo: etapa 1.7 — verificar contratos no Basescan

### 2026-06-04 — Sessão 6
- Etapa 1.5 concluída — revisão e complemento dos testes unitários
- 5 lacunas identificadas e corrigidas:
  - RecoveryManager: guardian removido na reconfiguração não pode mais propor
  - RecoveryManager: `approveRecovery` em proposta cancelada → `ProposalAlreadyCancelled`
  - RecoveryManager: `cancelRecovery` em proposta já cancelada → `ProposalAlreadyCancelled`
  - RecoveryManager: reconfigurar guardians após cancelamento (simétrico ao após execução)
  - IdentityRegistry: evento `ControllerTransferred` testado com `vm.expectEmit`
- Total: 80 testes passando (17 + 25 + 38)
- Próximo passo: etapa 1.6 — deploy em Base Sepolia (testnet)

### 2026-06-04 — Sessão 5
- `RecoveryManager` implementado e testado — 34 testes passando
  - Guardians configuráveis por identidade com threshold M-de-N
  - `configureGuardians`: só controller, bloqueia com proposta ativa
  - `proposeRecovery`: só guardian, uma proposta ativa por vez
  - `approveRecovery`: cada guardian vota uma vez, contador de aprovações
  - `executeRecovery`: qualquer um executa após threshold + 7 dias de timelock
  - `cancelRecovery`: controller cancela dentro da janela de 7 dias
  - `IdentityRegistry` modificado: `setRecoveryManager` (one-time) + `recoverController` (só RecoveryManager)
- Total geral: 75 testes passando (16 IdentityRegistry + 25 DeviceRegistry + 34 RecoveryManager)
- Próximo passo: etapa 1.5 — revisar se os testes unitários estão completos, ou partir para 1.6 (deploy em Base Sepolia)

### 2026-06-04 — Sessão 3
- Sessão de entendimento — sem código escrito
- Revisão do quadro geral: blockchain, relay, fluxo de login, contratos
- Decisão de arquitetura: WebRTC em vez de relay tradicional para a camada de comunicação
  - Motivo: relay é ponto de centralização de disponibilidade, contra o princípio descentralizado
  - Website e celular se conectam P2P — nenhum servidor vê challenge ou assinatura
  - STUN: múltiplos servidores públicos com failover automático
  - TURN: self-hostável (coturn) como fallback para ~10% dos casos
  - Sinalização: decisão pendente para próxima sessão
- Próximo passo: decidir canal de sinalização (etapa 2.1)

### 2026-06-03 — Sessão 2
- `DeviceRegistry` implementado e testado — 25 testes passando
  - Chave pública do device armazenada como `address` (Ethereum, secp256k1) — facilita `ecrecover` nos SDKs
  - Registrar device (só o controller da identidade)
  - Revogar device (só o controller; revogação não remove da lista, apenas marca)
  - `isDeviceActive`: função principal para verificação nos SDKs
  - `getDevicesByIdentity`: lista todos os devices (inclui revogados para auditoria)
  - Controller identificado pelo wallet — não precisa passar username nos parâmetros
- Total geral: 41 testes passando (16 IdentityRegistry + 25 DeviceRegistry)
- Próximo passo: `RecoveryManager` (etapa 1.4)

### 2026-06-03 — Sessão 1
- Projeto iniciado, CONTEXT.md (PRD) lido e analisado
- PROJECT_STATE.md criado com planejamento completo das 7 fases
- Decidido: Foundry (vs Hardhat) — motivos: fuzzing nativo, testes em Solidity, velocidade
- Foundry v1.7.1 instalado e configurado em `contracts/`, Solidity fixado em 0.8.24
- `IdentityRegistry` implementado e testado — 16 testes passando
  - Criar identidade (username + controller wallet)
  - Busca nos dois sentidos (username → identity, wallet → username)
  - Validação de username (só a-z, 0-9, hífen, ponto, máx 64 chars)
  - Transferência de controller
- Próximo passo: `DeviceRegistry` (etapa 1.3)

---

## Como Usar Este Arquivo

1. **Ao começar uma sessão**: Diga ao Claude Code "leia o PROJECT_STATE.md e me ajude a continuar"
2. **Ao terminar uma sessão**: O Claude atualiza o Log de Sessões e marca etapas concluídas
3. **Ao tomar uma decisão**: Registrar em "Decisões de Arquitetura em Aberto"
4. **Ao mudar de máquina**: Sincronizar via git (recomendado: `git init` neste diretório)
