# TruthID — Estado do Projeto

> Este arquivo é o centro de controle do projeto. Atualizado a cada sessão de trabalho.
> Pode ser lido por qualquer instância do Claude Code em qualquer máquina para retomar o contexto.
> Última atualização: 2026-06-18 (Sessão 26)

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
Fase 7 — Mainnet & Lançamento   [ ] Não iniciada
Fase 8 — Documentação Web       [ ] Não iniciada
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
- [ ] 7.3 — Publicar SDKs (npm, pip, rubygems)
- [ ] 7.4 — Documentação pública
- [ ] 7.5 — Open source (GitHub)

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
docs.truthid.dev (ou truthid.github.io/truthid)
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
- [ ] 8.1 — Setup Docusaurus em `docs/` + configuração GitHub Pages (Action de deploy automático)
- [ ] 8.2 — Landing page: headline, diagrama do fluxo, botão "Get Started"
- [ ] 8.3 — Guia de introdução: o que é TruthID, pré-requisitos, arquitetura
- [ ] 8.4 — Quickstart interativo: passo a passo comentado do fluxo completo
- [ ] 8.5 — Referência de API: TypeScript SDK (migrar e expandir o README atual)
- [ ] 8.6 — Referência de API: Python SDK
- [ ] 8.7 — Referência de API: Ruby SDK
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
