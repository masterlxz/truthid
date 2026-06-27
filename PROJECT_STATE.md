# TruthID — Estado do Projeto

> Este arquivo é o centro de controle do projeto. Atualizado a cada sessão de trabalho.
> Pode ser lido por qualquer instância do Claude Code em qualquer máquina para retomar o contexto.
> Última atualização: 2026-06-13 (Sessão 17)

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
Fase 4 — Mobile App             [.] Em andamento
Fase 5 — SDKs                   [ ] Não iniciada
Fase 6 — Integração & Testes    [ ] Não iniciada
Fase 7 — Mainnet & Lançamento   [ ] Não iniciada
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
  - IdentityRegistry : 0xd4484aDD6DCd0919568B6365882cDB207fE27D9c
  - DeviceRegistry   : 0xe87633b148cf7a7F6c60DdA84AD7f4D3a9eC187F
  - RecoveryManager  : 0x66be956D14b9383aE9a58f70edD6Cae406Eb960f
  - SessionRegistry  : 0x93B56d40B304269Ee23f84A1cF3BD7B338514b42
- [x] 1.7 — Verificar contratos no Basescan

**Decisões pendentes**:
- Padrão de upgrade: Proxy ou imutável na v1?

---

### Fase 2 — Camada de Comunicação (WebRTC)

**Objetivo de aprendizado**: Conectar website ↔ mobile diretamente, sem servidor no meio dos dados de autenticação.

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
- [ ] 4.2 — Geração de key pair no dispositivo (Android Keystore / iOS Secure Enclave)
- [ ] 4.3 — Scanner de QR code
- [ ] 4.4 — Tela: Aprovar login (exibir quem está pedindo, aprovar/recusar)
- [ ] 4.5 — Assinatura do challenge + envio via relay
- [ ] 4.6 — Tela: Meus dispositivos
- [ ] 4.7 — Tela: Sessões ativas

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
- [ ] 5.1 — TypeScript SDK (npm package)
- [ ] 5.2 — Python SDK (pip package)
- [ ] 5.3 — Ruby SDK (gem)
- [ ] 5.4 — Documentação e exemplos para cada SDK
- [ ] 5.5 — Exemplo de integração: app Express.js protegido com TruthID

---

### Fase 6 — Integração & Testes E2E

**Objetivo de aprendizado**: Validar que todos os componentes funcionam juntos como um sistema real.

**Etapas**:
- [ ] 6.1 — Fluxo completo: criar identidade → adicionar device → login via QR
- [ ] 6.2 — Fluxo de recovery: 3 de 5 guardians aprovam → timelock → novo wallet
- [ ] 6.3 — Fluxo de revogação: revogar device → tentativa de login falha
- [ ] 6.4 — Testes de segurança: replay attack, challenge expirado, device revogado
- [ ] 6.5 — Auditoria de segurança dos contratos

---

### Fase 7 — Mainnet & Lançamento

**Etapas**:
- [ ] 7.1 — Deploy contratos em Base Mainnet
- [ ] 7.2 — Relay Service em produção
- [ ] 7.3 — Publicar SDKs (npm, pip, rubygems)
- [ ] 7.4 — Documentação pública
- [ ] 7.5 — Open source (GitHub)

---

## Decisões de Arquitetura em Aberto

| Decisão | Opções | Status |
|---|---|---|
| Framework de contratos | Foundry vs Hardhat | **Foundry** ✓ |
| Camada de comunicação | Relay tradicional vs WebRTC | **WebRTC** ✓ |
| Canal de sinalização WebRTC | On-chain / DHT / servidor leve | **Servidor leve (WebSocket)** ✓ |
| Padrão de upgrade dos contratos | Proxy (upgradeable) vs Imutável | Pendente |
| Formato do challenge de autenticação | JWT vs custom JSON | Pendente |
| Armazenamento de sessões | Servidor central vs on-chain hash | **Hash keccak256 on-chain** ✓ — dados originais locais, só o hash vai pra chain; privado mas auditável; revogação granular por sessão |
| Sinalização WebRTC (futuro) | Servidor fixo vs plugável | **SignalingAdapter** ✓ — interface abstrata com implementações trocáveis (WebSocketSignaling hoje, OnChainSignaling quando latência de L2 permitir); contratos de identidade ficam na Base, sinalização pode migrar de chain sem afetar o resto |

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
