# TruthID — Estado do Projeto

> Este arquivo é o centro de controle do projeto. Atualizado a cada sessão de trabalho.
> Pode ser lido por qualquer instância do Claude Code em qualquer máquina para retomar o contexto.
> Última atualização: 2026-07-06 (Sessão 76 — débito #34: vault key derivada da wallet via RFC 6979 + ECIES no pareamento; DeviceRegistry com encryptedVaultKey)
>
> ⚠️ **LEMBRETE**: ao final do projeto (todas as fases concluídas), fazer uma revisão completa deste arquivo — consolidar endereços, remover seções obsoletas, e garantir que a tabela de Pendências de Deploy está zerada. Sessão 68.

---

## Diretriz de código (IMPORTANTE — sempre seguir)

**Todo código novo deve ser escrito em inglês — sem exceção.**
- Strings visíveis ao usuário (UI, mensagens de erro, labels, placeholders): inglês
- Nomes de variáveis, funções, classes, arquivos: inglês
- Comentários no código: podem ficar em português (não são visíveis ao usuário e facilitam o aprendizado)
- Esta regra vale para todos os arquivos: `.tsx`, `.ts`, `.rs`, `.dart`, `.py`, `.rb`, `.sol`

**I18n (múltiplos idiomas) está planejado para uma fase futura:**
Hoje o app é 100% inglês. Quando houver demanda, a estratégia é extrair todas as strings visíveis para arquivos de tradução (ex: `i18n/en.json`, `i18n/pt.json`) e usar uma biblioteca de i18n por plataforma (react-i18next no desktop, Flutter's `intl` no mobile). O inglês será o idioma base (source of truth); português e outros idiomas serão adicionados sobre ele.

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
Fase 8 — Documentação Web       [x] Concluída
Fase 9 — Identidade Visual: Mobile & Desktop  [x] Concluída
Fase 10 — Ledger via USB (Rust/hidapi)         [x] Concluída
Fase 11 — Teste E2E Prático (login, sessão, revogação) [x] Concluída
Fase 12 — Publicação & Release (v1.0.0)        [x] Concluída
Fase 13 — TruthID Vault (gerenciador de senhas) [~] Em andamento (13.1–13.8 ✓, 13.9 fatia 1/LAN ✓, fatia 2/IPFS-IPNS pendente)
Fase 14 — Smart Account (ERC-4337, Self-Funded)  [x] Concluída
```

---

## Checklist antes do próximo release oficial

**Protocolo final: `/code-review` por pasta principal**, como última etapa antes de cortar
a versão de produção (depois de todas as fases fechadas, incluindo 13.8/13.9). Cada revisão
individual de débito/PR já cobriu o arquivo específico conforme foi escrito — o que falta é
uma passada holística por pasta, olhando como as peças de cada uma interagem entre si, algo
que só aparece quando se olha o conjunto de uma vez.

1. **`contracts/`** — considerar `ultra`, é a pasta mais crítica (sem "hotfix" pós-deploy em
   mainnet). Motivado pela Sessão 53: o `/code-review` rodado sobre um único contrato
   recém-escrito (`TruthIDAccount.sol`) já achou uma falha crítica (device sequestrando a
   identidade via `IdentityRegistry`/`RecoveryManager`) e, durante a própria correção, uma
   tentativa de otimização introduziu um bug novo (bits não mascarados numa extração via
   assembly) só pego numa releitura cuidadosa antes do commit. Olhar as interações entre
   `IdentityRegistry`/`DeviceRegistry`/`RecoveryManager`/`TruthIDAccount`/`VaultRegistry`
   como um todo, não só contrato a contrato. Débito #17 (aberto, não bloqueia o progresso
   mas deve ser resolvido ou conscientemente aceito antes do release) — #18 e #20 (achados
   na mesma correção) já foram resolvidos na Sessão 55.
2. **`desktop/`** — maior superfície de UI e onde mais apareceram bugs de "cola" entre
   frontend e contratos (débitos #33, #39, entre outros da leva #33-43 do Vault).
3. **`mobile/`** — Flutter; fluxos de autenticação, pareamento e vault local.
4. **`sdk/`** — as 3 linguagens (TypeScript, Python, Ruby) são API pública para integradores
   externos; um bug aqui afeta qualquer app de terceiro que use o TruthID, não só o próprio
   projeto.

**Por quê como protocolo (não um único review geral)**: cada pasta tem uma superfície e um
tipo de risco diferente (contratos = fundos/identidades perdidos permanentemente; SDK =
quebra de integrações de terceiros; desktop/mobile = UX e bugs de integração local) — revisar
por pasta deixa o escopo de cada passada gerenciável e comparável a reviews anteriores.

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
- [x] 8.8 — Página de segurança: modelo de ameaças, o que o TruthID protege e o que não protege. Implementado na Sessão 33: nova página `docs/docs/security.mdx` (sidebar_position 4, depois da categoria "SDK Reference"). Antes de escrever, investigação no código real (não só no que já estava documentado) confirmou 5 pontos que mudaram o conteúdo: (1) o app mobile mostra o `origin` do challenge na tela de aprovação (`approval_screen.dart`) — então o TruthID dá proteção real contra phishing, não só "confia no usuário"; (2) o mobile recusa `callbackUrl` que não seja `https://` (mesmo arquivo); (3) os 3 SDKs leem estado on-chain via um RPC escolhido pelo integrador (público por padrão) sem nenhuma prova client-side de que esse RPC não está mentindo — risco real de confiança que não estava em nenhum doc ainda; (4) a chave do device só existe via Android Keystore/iOS Secure Enclave, sem fallback em texto puro (`device_key_service.dart`); (5) `RecoveryManager.proposeRecovery` reverte com `GuardiansNotConfigured` se a identidade nunca configurou guardians — sem esse passo prévio, perda do controller é permanente, sem nenhum caminho alternativo. Estrutura da página: tabela "What TruthID protects against" (11 mecanismos reais, cada um linkado ao achado de auditoria correspondente quando aplicável), seção "What TruthID does not protect against" com admonition `:::danger[...]` pro caso de guardians não configurados + 6 bullets honestos (device comprometido, RPC não-confiável, sem auditoria externa, contratos imutáveis, segurança do backend do integrador é responsabilidade dele, engenharia social), e "Audit status" linkando pra tabela de achados em `PROJECT_STATE.md` (Sessão 24/Fase 6) e pro GitHub Security tab. Aproveitado pra corrigir duas pontas soltas que ficaram “coming soon” desde sessões anteriores: `intro.mdx` linkava pro `sdk/README.md` dizendo que a referência de API dedicada "está chegando" (já existia desde a 8.5-8.7, nunca foi atualizado) e `quickstart.mdx` tinha "Security model — coming soon" nos Next steps — os dois agora linkam pras páginas reais. Link "Security" adicionado ao footer (`docusaurus.config.ts`), mesmo padrão usado quando Quickstart foi criado (8.4). `npm run build` sem erros; revisão visual via Playwright (mesmo processo das etapas anteriores) confirmou o admonition vermelho renderizando corretamente, a tabela legível no tema dark, e o link novo no footer.
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

## Decisões de Arquitetura em Aberto

| Decisão | Opções | Status |
|---|---|---|
| Framework de contratos | Foundry vs Hardhat | **Foundry** ✓ |
| Camada de comunicação | Relay tradicional vs WebRTC | **WebRTC** ✓ |
| Canal de sinalização WebRTC | On-chain / DHT / servidor leve | **Servidor leve (WebSocket)** ✓ |
| Padrão de upgrade dos contratos | Proxy (upgradeable) vs Imutável | **Imutável** ✓ — decidido na Sessão 25, antes do deploy em mainnet (etapa 7.1). Motivo: evitar superfície de ataque extra (controle de upgrade) e complexidade adicional; processo de redeploy + migração já é conhecido (feito 2x na Sessão 24) |
| Formato do challenge de autenticação | JWT vs custom JSON | **Custom JSON** ✓ — decidido na prática desde a Fase 2. Formato: `{ type, nonce, issuedAt, origin }`. Mobile assina `JSON.stringify(challenge)` com `personal_sign`. JWT foi descartado por não adicionar valor aqui — o objetivo é assinar um nonce efêmero, não carregar claims, e o formato simples é mais fácil de auditar. |
| Armazenamento de sessões | Servidor central vs on-chain hash | **Hash keccak256 on-chain** ✓ — dados originais locais, só o hash vai pra chain; privado mas auditável; revogação granular por sessão |
| Sinalização WebRTC (histórico) | Servidor fixo vs plugável | **Substituído** — o `SignalingAdapter` (decisão da Sessão 15) nunca foi implementado; o código usava WebSocket direto. Resolvido na Sessão 26 (continuação) removendo a dependência de servidor por completo, em vez de construir o adapter — ver linha abaixo |
| Sinalização sem servidor do TruthID | On-chain (eventos+gas) vs transporte direto sem blockchain | **Transporte direto, sem blockchain** ✓ — Sessão 26 (continuação). Pareamento: o device mostra seu próprio endereço em QR, o controller (desktop) lê e registra on-chain; confirmação via polling (`getDevice`), sem canal ao vivo. Login: o challenge vai embutido no QR, a resposta assinada vai via HTTPS direto pro `callbackUrl` do próprio site (backend que o integrador já roda). Zero gas extra, zero latência de handshake on-chain — `signaling/`, `turn/` e `webrtc-demo/` removidos do repositório |
| Interface e experiência do usuário | UI funcional vs identidade visual própria | **Pendente** — app e desktop têm UI funcional (Material Design padrão) mas sem logo, cores, tipografia ou fluxos polidos; previsto para uma fase dedicada após Fase 4 ou como Fase 8 pós-lançamento |
| Endereços de contrato nos SDKs (multi-rede) | Endereço fixo único vs mapa por rede | **Mapa por rede** ✓ — decidido na Sessão 26. Os 3 SDKs já tinham um parâmetro `network` desde a Fase 5, mas os endereços eram fixos (só Sepolia); completar o design original em vez de descartá-lo. Python/Ruby agora default para `"base-mainnet"`; TypeScript continua exigindo `network` explícito (sem default) |
| Domínio do site de docs (Fase 8) | Domínio próprio (ex: truthid.dev) vs subdomínio grátis do GitHub Pages | **GitHub Pages grátis** ✓ — decidido na Sessão 31. Usuário ainda não tem domínio próprio registrado; `masterlxz.github.io/truthid` configurado no `docusaurus.config.ts` (etapa 8.1). Dá pra trocar pra domínio próprio depois (basta um arquivo `CNAME` em `docs/static/` + DNS) sem precisar redeployar nada além disso |
| Conexão com Ledger (desktop) | USB direto via Rust (`hidapi`+APDU) vs documentar Ledger Live via WalletConnect (sem código novo) vs deixar de lado | **USB direto via Rust** ✓ — decidido na Sessão 34. WebHID/WebUSB confirmados ausentes no WebKitGTK (Sessão 33) — só dá pra fazer via comando Tauri em Rust, mesmo padrão de `get_or_create_device_key`/`sign_challenge` (etapa 3.7). Ver Fase 10 |
| Controller da identidade | EOA do Ledger vs smart account pré-computada via CREATE2 | **Smart account via CREATE2** ✓ — Sessão 52. `createIdentity` passa a aceitar `address controller` explícito. Ledger paga as 3 txs iniciais como EOA (createIdentity + deploy + fund). Depois é só chave de assinatura. Ver Fase 14 |
| Gas das operações do usuário | Dev mantém hot wallet (relayer) vs Paymaster centralizado vs auto-financiamento via EntryPoint | **Auto-financiamento via EntryPoint** ✓ — Sessão 52. Sem Paymaster, sem hot wallet do dev. Smart account deposita ETH no EntryPoint e paga bundler diretamente. Open source: cada deployment é independente, sem operador central. Ver Fase 14 |
| Base da smart account | Safe / Coinbase Smart Wallet / SimpleAccount / custom | **Fork do SimpleAccount** ✓ — Sessão 52. Referência do ERC-4337, ECDSA secp256k1 (Ledger-native), CREATE2 via factory, ~150 linhas, sem dependências extras além do EntryPoint já deployado na Base |
| Permissões na smart account | Uma tier única vs duas tiers (owner/devices) | **Duas tiers** ✓ — Sessão 52. Ledger = owner (assina tudo, inclusive DeviceRegistry). Devices (celular, etc.) = signers autorizados, bloqueados de chamar DeviceRegistry. Smart account mantém lista interna própria (não consulta DeviceRegistry em `validateUserOp` — evita restrições de storage cross-contract do ERC-4337). |
| Recovery com saldo zero na smart account | Aceitar perda do saldo vs `emergencyWithdraw` | **`emergencyWithdraw`** ✓ — Sessão 52. Função na smart account chamável só pelo RecoveryManager, migra o saldo para a nova smart account durante a recovery. Recovery da identidade (via RecoveryManager → IdentityRegistry) nunca depende do saldo da smart account. |

---

## Débitos Técnicos de Arquitetura

Problemas identificados na revisão de arquitetura da Sessão 36 (2026-06-25). Nenhum quebra o app hoje — são pontos que dificultam manutenção ou introduzem fragilidade a médio prazo. Ordenados por impacto.

| # | Arquivo(s) | Problema | O que fazer |
|---|---|---|---|
| ~~1~~ | ~~`desktop/src/components/ManageDevices.tsx`~~ | ~~Arquivo com 347 linhas mistura 3 responsabilidades.~~ | **RESOLVIDO — Sessão 39**. Separado em `DeviceList.tsx` e `PairDevice.tsx`; `ManageDevices.tsx` virou shell de ~90 linhas. |
| ~~2~~ | ~~`mobile/lib/services/blockchain_service.dart`~~ | ~~ABI dos contratos embutida como string JSON literal inline.~~ | **RESOLVIDO — Sessão 41**. ABIs extraídas para `mobile/lib/contracts/abis.dart` como constantes nomeadas (`sessionRegistryAbi`, `deviceRegistryAbi`). `blockchain_service.dart` importa essas constantes. |
| ~~3~~ | ~~`sdk/typescript/src/client.ts:22`~~ | ~~`private publicClient: any`~~ | **RESOLVIDO — Sessão 41**. Tipado como `ReturnType<typeof createPublicClient>`. `tsc --noEmit` limpo. |
| ~~4~~ | ~~`desktop/src/components/ManageDevices.tsx:133`~~ | ~~`DeviceInfo` type definido localmente.~~ | **RESOLVIDO — Sessão 39**. Movido para `desktop/src/types.ts` (criado). |
| ~~5~~ | ~~Desktop (React geral)~~ | ~~Nenhum `ErrorBoundary` no app.~~ | **RESOLVIDO — Sessão 41**. `ErrorBoundary` criado em `desktop/src/components/ErrorBoundary.tsx` e adicionado em `main.tsx` envolvendo toda a árvore. Mostra mensagem de erro + botão "Try again" em vez de tela em branco. |
| ~~6~~ | ~~Desktop (React geral)~~ | ~~Estado todo local via `useState`, sem estado compartilhado.~~ | **RESOLVIDO — Sessão 41**. `IdentityContext` criado em `desktop/src/contexts/IdentityContext.tsx` com `{ username, identityId }`. `ManageDevices` e `ActiveSessions` eliminaram o prop `username` e a chamada duplicada `getIdentity(username)` — usam `useIdentity()`. Novos componentes que precisarem de identidade já têm o hook disponível. |
| ~~7~~ | ~~Desktop + Mobile (geral)~~ | ~~Zero testes de UI/frontend.~~ | **RESOLVIDO — Sessão 43**. Desktop: Vitest + RTL — 9 testes em `PairDevice` (abertura do form, validação de endereço, fluxo sem/com wallet, commitDevice). Mobile: flutter_test + mocktail — 7 testes em `ApprovalScreen` (QR inválido, UI do challenge, approve, reject, proteção contra dupla resposta). `ApprovalScreen` refatorado para injetar `keyService` e `postResponse` opcionais. `widget_test.dart` corrigido (labels PT→EN). |
| ~~8~~ | ~~Desktop (UX/layout)~~ | ~~Posição dos botões, organização das telas e fluxos de navegação nunca foram revisados com olhar de produto.~~ | **RESOLVIDO — Sessão 40**. Tela de login full-viewport com ícones de wallet, fluxo Ledger separado em sub-tela, app shell com topbar fixo (`@username` · `↻` · `⎋ Login`), modal de Quick Login, aba "Login test" removida. |
| ~~9~~ | ~~`desktop/src/components/ConnectLedger.tsx`~~ | ~~Tela de espera da Ledger exibia só texto puro, sem hierarquia visual.~~ | **RESOLVIDO — Sessão 40** (junto com o #8). Stepper visual de 3 passos em `ConnectLedger.tsx`: conectar USB → desbloquear PIN → abrir app Ethereum. Passo ativo destacado em ciano, passos anteriores em verde ✓, posteriores em cinza. |
| ~~10~~ | ~~`desktop/src/components/ConnectLedger.tsx`~~ | ~~O seletor de conta da Ledger não mostrava os endereços Ethereum — o usuário não sabia qual índice era o seu.~~ | **RESOLVIDO — Sessão 40 (parte 2)**. Ao entrar na fase `account-select`, busca sequencialmente (HID é serial) os endereços 0–4 via `invoke("get_ledger_address")` e exibe cada um abreviado (`0x1234…abcd`) abaixo do nome da conta. Slots ainda carregando mostram "loading…" sutil. |
| ~~11~~ | ~~`sdk/typescript/src/`, `sdk/typescript/example/server.js`, `sdk/README.md`~~ | ~~O fluxo de registro de sessão on-chain (`createSession`) está incompleto no SDK.~~ | **RESOLVIDO — Sessão 39**. Ver log da sessão para detalhes. |
| ~~12~~ | ~~wagmi auto-reconnect~~ | ~~O wagmi reconectava automaticamente o conector Ledger na abertura do app.~~ | **RESOLVIDO — Sessão 41**. `storage: null` no wagmi config (sem persistência de conector). Username salvo em `useStoredUsername` (`localStorage`, chave `truthid:username`). `WalletModalContext` permite qualquer componente abrir o modal de conexão. App shell carrega direto do localStorage; "Disconnect wallet" mantém modo leitura; "Log out" limpa o localStorage. Ações de escrita (revoke/register) abrem o modal se não há wallet conectada. |
| ~~13~~ | ~~Site de documentação web (Fase 8)~~ | ~~`sdk/README.md` atualizado mas site não refletia a seção Session Registration.~~ | **RESOLVIDO — Sessão 42**. `typescript.md`: método `registerSession`, tipos `RegisterSessionParams`/`RegisterSessionResult`, campo `sessionSignature` no `AuthResponse`. `quickstart.mdx`: passo 5 opcional de registro on-chain. `python.md`/`ruby.md`: nota que `registerSession` é TypeScript-only por enquanto. Build do Docusaurus validado sem erros. |
| ~~14~~ | ~~`mobile/lib/screens/devices_screen.dart`~~ | ~~`DevicesScreen` não detecta automaticamente que o device foi registrado on-chain — só checa no `_reload()` manual ou pull-to-refresh.~~ | **RESOLVIDO — Sessão 46**. `_reload()` chama `_blockchain.getDevice(address)` on-chain em toda execução (abertura da tela e pull-to-refresh). Auto-descobre pareamento se `identityId == null` em storage. Detecta revogação e limpa storage automaticamente. Botão "Show QR to pair" agora condicional (`_pairedIdentityId == null`) — some quando pareado, reaparece se revogado. Dica "Pull down to check if already paired" adicionada ao card de info. |
| ~~15~~ | ~~`mobile/lib/screens/show_device_qr_screen.dart`~~ | ~~`ShowDeviceQrScreen` tem polling automático a cada 3s, mas se a rede cair pontualmente e o timer perder a confirmação, o usuário não tem como forçar uma nova tentativa sem fechar e reabrir a tela.~~ | **RESOLVIDO — Sessão 46**. Botão "Check now" adicionado abaixo do spinner em `_buildQrUI()`. Estado `_isChecking` desabilita o botão durante a verificação e exibe "Checking...". `SessionsScreen._load()` também enriquecido com verificação on-chain completa: auto-descobre pareamento se `identityId` ausente em storage; detecta revogação e limpa storage. Padrão idêntico ao #14. |
| ~~16~~ | ~~Desktop (`App.tsx`, AppBar) + Mobile (`main.dart`, `_NavTab`)~~ | ~~Não existe nenhum mecanismo de doação no app.~~ | **RESOLVIDO — Sessão 47**. Botão ♥ no topbar do desktop abre modal com QR code EIP-681 + botão copiar (`qrcode.react`). Ícone ♥ no AppBar do mobile abre bottom sheet com mesmo conteúdo (`qr_flutter` já disponível). Página `/donate` adicionada ao site de docs (Docusaurus) com QR code + copiar; link "♥ Support" adicionado ao footer. Endereço: `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265` (deployer, já público on-chain). |
| ~~17~~ | ~~`contracts/src/IdentityRegistry.sol:80`~~ | ~~`createIdentity(username, controller)` não verificava se `msg.sender` tinha qualquer autorização sobre o `controller` informado. Achado (CONFIRMED) no `/code-review` da Sessão 53. Permitia squatting/griefing: qualquer um podia "ocupar" um endereço alheio (inclusive o CREATE2 pré-computado de uma smart account que ainda vai ser deployada) chamando `createIdentity` primeiro.~~ | **RESOLVIDO — Sessão 62, opção (a)**: `createIdentity` agora exige assinatura de consentimento (v,r,s) — do próprio controller (EOA) ou do owner via `factory.getAddress(signer)` (smart account pré-deploy). Redeploy dos 5 contratos completo em Base Sepolia **e Base Mainnet**. Testado de ponta a ponta em Sepolia (incluindo um bug de gas real encontrado e corrigido no funding da smart account). Endereços novos propagados para `desktop/`, `mobile/`, `sdk/typescript`, `sdk/python`, `sdk/ruby` e a documentação pública (`README.md`, `docs/`). Ver Log de Sessões, Sessão 62, para o desenho completo. |
| ~~18~~ | ~~`contracts/src/TruthIDAccount.sol`~~ | ~~`_isDeviceCallAllowed` retorna via `abi.decode`, que pode reverter (em vez de retornar `SIG_VALIDATION_FAILED` de forma limpa) se um signer de tier device mandar `callData` com o seletor certo mas payload truncado/malformado. Achado (PLAUSIBLE) no `/code-review` da Sessão 53.~~ | **RESOLVIDO — Sessão 55**. Decode movido pra função nova `_decodeExecuteBatchDest` (`external pure`), chamada via `try/catch` em vez de `abi.decode` direto — qualquer revert/panic do decode vira `false` (→ `SIG_VALIDATION_FAILED`) em vez de propagar. Evitou reintroduzir assembly manual na área que já causou o bug do débito relacionado à máscara (item 4 do review da Sessão 53). Testes novos em `contracts/test/TruthIDAccount.t.sol` (não existia antes). |
| ~~19~~ | ~~\`contracts/src/RecoveryManager.sol\`~~ | ~~Etapa 14.3 (Sessão 54) adicionou \`emergencyWithdraw\` na \`TruthIDAccount\`, chamável só pelo \`RecoveryManager\` — mas nada no \`RecoveryManager.sol\` de fato chama essa função (\`executeRecovery\` só invoca \`IdentityRegistry.recoverController\`, não rastreia endereço de smart account nenhum). A função fica funcional mas inalcançável até essa conexão ser feita.~~ | **RESOLVIDO — Sessão 68**. \`executeRecovery\` agora tenta \`emergencyWithdraw\` com \`try/catch\` + \`extcodesize\` check antes de trocar o controller. Testado com TA (2 ETH transferidos) e com EOA (recovery segue sem migrar fundos). **Deploy pendente do RecoveryManager em Base Sepolia + Base Mainnet** (código mudou, ver Pendências de Deploy). |
| ~~20~~ | ~~`contracts/src/TruthIDAccount.sol:69`~~ | ~~A constante `_SECP256K1N_DIV_2` (limiar low-s, EIP-2) tinha 1 dígito hex a menos (`...681B20A` em vez de `...681B20A0`), fazendo o valor real ser `n/32` em vez de `n/2` — rejeitava ~97% das assinaturas canônicas válidas como `SIG_VALIDATION_FAILED`, afetando owner e devices igualmente (checagem roda antes de identificar quem assinou). Introduzido junto com a 14.2 (Sessão 53), nunca pego porque não havia teste de caminho feliz pra `TruthIDAccount` até agora.~~ | **RESOLVIDO — Sessão 55**. Achado ao escrever o teste de regressão do débito #18 (caminho feliz de `executeBatch` falhava mesmo com assinatura correta). Corrigido adicionando o `0` faltante; valor conferido matematicamente (`== n // 2`) antes de commitar. |
| ~~21~~ | ~~`contracts/src/TruthIDAccountFactory.sol:54,65`~~ | ~~`createAccount` sempre recomputa o hash completo do init code antes de checar `extcodesize` — desperdiça gas no caminho idempotente. `_salt(owner_)` calculado duas vezes por chamada.~~ | **RESOLVIDO — Sessão 61**. Mapping `accounts[owner => account]` adicionado; `createAccount`/`getAddress` checam o mapping primeiro e só computam `_computeAddress` (hash do init code) se a conta ainda não existir. Salt calculado uma vez por chamada e reusado. |
| ~~22~~ | ~~`contracts/src/TruthIDAccountFactory.sol:56`, `contracts/test/TruthIDAccountFactory.t.sol:74`~~ | ~~Checagem de `extcodesize` via assembly manual, duplicada entre produção e teste.~~ | **RESOLVIDO — Sessão 61**. Produção não usa mais `extcodesize` nenhum (substituído pelo mapping do débito #21). Testes trocaram os 2 usos de assembly por `.code.length` (builtin). |
| ~~23~~ | ~~`contracts/script/Deploy.s.sol:13`, `contracts/test/TruthIDAccountFactory.t.sol:18`~~ | ~~Endereço `ENTRY_POINT_V07` hardcoded de forma independente em dois arquivos (na prática, três: também em `DeployFactory.s.sol`).~~ | **RESOLVIDO — Sessão 61**. Constante extraída para `contracts/src/ERC4337Constants.sol` (free constant a nível de arquivo), importada nos 3 lugares. |
| ~~24~~ | ~~`contracts/src/TruthIDAccountFactory.sol:40`~~ | ~~Constructor validava os 4 endereços com 4 erros customizados separados, estilo diferente do `TruthIDAccount.sol` (1 erro combinado).~~ | **RESOLVIDO — Sessão 61**. Padronizado para 1 erro combinado (`InvalidConstructorArgs`), igual ao `TruthIDAccount.sol`. Os 4 testes de revert mantidos (um por campo zerado), agora todos esperando o mesmo seletor. |
| ~~25~~ | ~~`contracts/src/TruthIDAccountFactory.sol:97`~~ | ~~`_salt(owner_)` depende só do endereço do owner — um Ledger só pode ter UMA `TruthIDAccount` nessa factory pra sempre. Se um dia precisar de múltiplas contas por owner (ex: reset após comprometimento suspeito), é breaking change em `createAccount`/`getAddress` e em todo consumidor off-chain do CREATE2 (mobile, desktop, utilitário `computeSmartAccountAddress` da 14.6). Achado (CONFIRMED) no `/code-review` da Sessão 57.~~ | **RESOLVIDO — código na Sessão 68, deploy confirmado na Sessão 69**. `_salt(owner_, index)` agora recebe um `index` explícito (`createAccount(owner, index)`/`getAddress(owner, index)`); `index=0` é a conta principal, `index>0` fica disponível para reset/contas adicionais no futuro. Verificado on-chain (Sessão 69, via `cast call`) que a Mainnet **e** a Base Sepolia já rodam a factory nova — Sepolia foi redeployada nesta sessão (`0x78d34582607e4790BCec66b6AaE3d755061F1F67`, `IdentityRegistry.setFactory` já apontando pra ela). |
| ~~26~~ | ~~`contracts/test/TruthIDAccountFactory.t.sol:40`~~ | ~~Helper `_predictAndCreate` definido mas usado em só 1 dos 3 testes que repetem a mesma sequência prever→criar→assert.~~ | **RESOLVIDO — Sessão 61**. Helper agora usado nos 3 testes aplicáveis (`test_GetAddress_EqualsDeployedAddress`, `test_CreateAccount_DeploysWithCorrectParameters`, `test_DifferentOwners_DifferentAddresses`); o 4º teste (`test_IdentityCreationBeforeDeploy_MatchesPredictedAddress`) não usa porque intercala uma chamada ao `IdentityRegistry` entre prever e criar. |
| ~~27~~ | ~~\`mobile/lib/services/pimlico_bundler_client.dart\`, \`mobile/lib/config/secrets.dart\`~~ | ~~A 14.9.3 introduziu \`secrets.dart\` (gitignored) com a API key do Pimlico do próprio dev, só pra testes locais/E2E em Sepolia. Se o app for distribuído pra usuários finais com essa chave embutida no build, todo mundo usaria a mesma conta/quota do dev — vaza a chave (decompilação do app) e centraliza custo/rate-limit num "operador" único, contradizendo o objetivo do projeto de não ter operador central.~~ | **RESOLVIDO — Sessão 68**. Criado \`BundlerConfigService\` (lê/salva API key + network do \`flutter_secure_storage\` em runtime, com fallback para \`secrets.dart\`). Nova \`SettingsScreen\` (gear icon no AppBar) permite ao usuário configurar sua própria chave Pimlico + rede. \`ApprovalScreen\` agora lê a config do bundler em tempo de execução em vez de usar a constante de compilação. \`secrets.example.dart\` atualizado com nota sobre config runtime. |
| ~~28~~ | ~~\`contracts/src/IdentityRegistry.sol\` deployado (Sepolia e Mainnet)~~ | ~~O \`IdentityRegistry\` deployado chamava a factory internamente com o seletor antigo \`getAddress(address)\` (1 argumento), mas a fonte já usava \`getAddress(signer, 0)\` (2 argumentos, débito #25) desde que essa mudança foi feita — só a factory tinha sido redeployada (Sessão 69), o \`IdentityRegistry\` não. Resultado: **toda chamada a \`createIdentity\` com \`controller\` do tipo smart account pré-deploy revertia**, nas duas redes — bloqueava o fluxo padrão de criação de identidade desde então. Descoberto na Sessão 70, durante o teste E2E da 14.9.6, via \`cast call ... --trace\` (mostrou o staticcall interno pra factory revertendo) e confirmado via \`cast code | grep\` pelos seletores (\`ae22c57d\` presente, \`8cb84e18\` ausente nas duas redes).~~ | **RESOLVIDO — Sessão 70**. Redeploy completo dos 5 contratos (\`IdentityRegistry\`, \`DeviceRegistry\`, \`RecoveryManager\`, \`TruthIDAccountFactory\`, \`SessionRegistry\`) em Base Sepolia **e** Base Mainnet, via \`Deploy.s.sol\` + \`DeploySessionRegistry.s.sol\` com a Ledger física. \`totalIdentities()\` era \`0\` nas duas redes antes do redeploy — nenhum dado perdido. Endereços novos propagados por todo o repositório (\`desktop/\`, \`mobile/\`, \`sdk/typescript\`, \`sdk/python\`, \`sdk/ruby\`, \`README.md\`, \`docs/\`). Verificado on-chain depois: seletor \`8cb84e18\` presente no novo \`IdentityRegistry\`, \`factory.getAddress(...)\` responde sem reverter, \`totalIdentities()\` continua \`0\` (fresh deploy). |
| ~~29~~ | ~~\`desktop/src/utils/computeSmartAccountAddress.ts\`~~ | ~~O comentário da função já dizia "salt = keccak256(abi.encodePacked(ledgerAddress, index))" — igual à Solidity — mas o código de fato usava \`encodeAbiParameters\` (ABI padrão, endereço com left-pad pra 32 bytes) em vez de \`encodePacked\` (endereço cru, 20 bytes). Produzia um salt diferente do que \`TruthIDAccountFactory._salt\` calcula on-chain (\`abi.encodePacked(owner_, index)\`), gerando um \`controller\` (smart account prevista) que nunca bate com \`factory.getAddress(...)\` — \`createIdentity\` sempre revertia com \`InvalidConsentSignature\` pra qualquer identidade criada via smart account. Bug independente do #28 (esse era no contrato deployado; este é no desktop), só apareceu depois do #28 ser corrigido — descoberto na Sessão 70 comparando o resultado local (\`0x9ED7A1B...\`) contra o \`cast call factory getAddress(...)\` (\`0x0912e64a...\`).~~ | **RESOLVIDO — Sessão 70**. Trocado \`encodeAbiParameters\` por \`encodePacked\` no cálculo do salt (única mudança). \`tsc --noEmit\`/\`vitest\` (29/29, incluindo os 13 de \`computeSmartAccountAddress.test.ts\`) limpos sem precisar ajustar nenhum teste — os testes existentes checavam propriedades relativas (mesma entrada → mesmo endereço, owners diferentes → endereços diferentes), não endereços fixos hardcoded, então não estavam mascarando o bug nem quebraram com o fix. |
| ~~30~~ | ~~\`mobile/lib/services/blockchain_service.dart\`, \`mobile/lib/screens/devices_screen.dart\`~~ | ~~\`getUsernameForIdentity\` fazia \`eth_getLogs\` no evento \`IdentityCreated\` sem especificar \`fromBlock\`/\`toBlock\` — RPCs públicos assumem \`fromBlock: "latest"\` nesse caso, nunca encontrando eventos de identidades criadas há mais de 1 bloco. \`DevicesScreen._reload()\` chamava essa função como fire-and-forget (sem \`await\`), então o username nunca era salvo no \`LocalStorageService\`, mesmo com o \`identityId\` já salvo corretamente. \`ApprovalScreen\` exige os dois não-nulos pra aprovar um login — resultado: "This device is not paired with any identity yet." sempre, mesmo com \`DevicesScreen\` mostrando pareado corretamente. Descoberto na Sessão 70 testando o login de ponta a ponta pela primeira vez (nunca tinha sido exercitado antes).~~ | **RESOLVIDO — Sessão 70**. \`getUsernameForIdentity\` agora pagina pra trás a partir do bloco mais recente em faixas de 2000 blocos, até 50 faixas (~55h de histórico — cobre identidades pareadas recentemente; limitação conhecida, não é indexação genérica). \`DevicesScreen._reload()\` passou a \`await\` a chamada em vez de fire-and-forget. \`flutter analyze\`/\`flutter test\` (68/68) limpos, nenhum teste existente cobria essa função diretamente. |
| ~~31~~ | ~~\`mobile/docker-compose.yml\`~~ | ~~\`/root/.android\` (onde fica a keystore de debug do Android) não era persistido como volume — como \`docker compose run --rm\` cria um container efêmero a cada execução, o Gradle gerava uma keystore de debug (e assinatura) nova em **cada build**. \`adb install -r\` recusa atualizar um app com assinatura diferente da instalada, forçando desinstalar primeiro — o que apaga o \`flutter_secure_storage\`, incluindo a chave do device. Resultado: cada rebuild do APK durante testes gerava um device novo, "perdendo" o pareamento anterior sem aviso. Relatado pelo dono do projeto na Sessão 70 ("a cada instala/atualiza gera um endereço novo").~~ | **RESOLVIDO — Sessão 70**. Volume nomeado \`android_debug_keystore:/root/.android\` adicionado ao \`docker-compose.yml\`. A partir do próximo build limpo, a keystore persiste entre execuções do container — \`adb install -r\` volta a atualizar em vez de exigir reinstalação, preservando a chave do device entre rebuilds. |
| ~~32~~ | ~~\`mobile/lib/services/blockchain_service.dart\`~~ | ~~\`getIdentityByUsername\` chamava \`getIdentity(string)\` (struct de retorno com um campo dinâmico — \`string username\` — no meio de campos fixos) através de \`ContractFunction\`/\`ContractAbi.fromJson\` do \`web3dart\` (2.7.3). Qualquer contato com essa definição ABI (montar a chamada via \`fn.encodeCall\` **ou** decodificar via \`fn.decodeReturnValues\`) reproduzia \`type 'null' is not a subtype of type 'bool' in type cast\" — não era só um bug de decode, era o caminho inteiro de definição/encode dessa função no \`web3dart\` que não lida com esse formato de struct. Bloqueava o login de ponta a ponta (a etapa final da 14.9.6) — nunca tinha sido exercitado antes desta sessão.~~ | **RESOLVIDO — Sessão 70**. \`getIdentityByUsername\` monta o calldata inteiramente à mão (seletor via \`keccak256\`, ABI-encoding manual do parâmetro string) e decodifica a resposta manualmente por offsets fixos — sem tocar em \`ContractFunction\`/\`ContractAbi.fromJson\` em nenhum momento pra essa chamada. Campo \`_identityContract\` (ficou sem uso) removido. Login testado de ponta a ponta com sucesso real, confirmado on-chain (\`getSessionsByIdentity\`/\`getSession\`). |
| ~~33~~ | ~~`desktop/src/components/VaultManagement.tsx` (fluxo "Enviar"), `contracts/src/VaultRegistry.sol:71`~~ | ~~`VaultRegistry.updateVault` só aceita chamada de quem `IdentityRegistry.getUsernameByController(msg.sender)` resolve como controller da identidade. `VaultManagement.tsx` (escrito na Sessão 51, antes da Fase 14 existir) disparava `writeContract` direto pela wallet conectada (Ledger/EOA), em vez de rotear via `TruthIDAccount.execute(...)` contra o `smartAccountAddress`.~~ | **RESOLVIDO — Sessão 78**. `writeContract` trocado por `execute(VAULT_REGISTRY_ADDRESS, 0n, calldata)` contra `smartAccountAddress` (obtido de `useIdentity()`), calldata de `updateVault` via `encodeFunctionData`, mesmo padrão do `WithdrawModal.tsx`/`PairDevice.tsx`. Efeito ganhou guard `if (!smartAccountAddress) return`. Auditoria do restante do fluxo do Vault (13.1–13.7): `VaultManagement.tsx` tem só essa 1 chamada `useWriteContract`/on-chain; `VaultSettings.tsx` é só config local de providers (sem chamada on-chain) — nenhuma outra instância do mesmo bug encontrada. `tsc --noEmit`/`vitest` (47/47) limpos; sem teste dedicado pra este componente hoje (nada a atualizar). |
| ~~34~~ | ~~\`mobile/lib/services/vault_key_service.dart:23\`~~ | ~~A chave AES do vault é derivada da chave privada do próprio device (\`DeviceKeyService.getPrivateKeyBytes()\` via HKDF), não de um segredo compartilhado da identidade — mesmo padrão em \`desktop/src-tauri/src/lib.rs\` (\`derive_vault_key()\`). Isso contradiz o design documentado (linha ~708 deste arquivo): "o vault é cifrado com uma chave simétrica própria do vault... compartilhada entre os devices do usuário apenas no momento do pareamento". Nenhum código (\`PairDevice.tsx\`, mobile, desktop) implementa esse compartilhamento/wrapping de chave hoje. Achado no \`/code-review high\` da Sessão 75 (escopo: arquivos do Vault).~~ | **RESOLVIDO — Sessão 76**. A chave do vault agora é derivada da assinatura da wallet (RFC 6979, \`personal_sign("TruthID Vault Key v1")\` → HKDF), não mais da device key. Isso resolve o problema de raiz: mesma wallet + mesma mensagem = mesma chave do vault em qualquer dispositivo, sem precisar de compartilhamento no pareamento. O compartilhamento via ECIES durante o pareamento também foi implementado como caminho adicional (Desktop cifra a vault key com a chave pública do mobile e envia no \`encryptedVaultKey\` do \`registerDevice\`), mas o caminho canônico agora é a derivação determinística da wallet. Detalhes completos na Sessão 76 do Log de Sessões. Redeploy do \`DeviceRegistry\` (+ cascata de 5 contratos) feito na **Sessão 77** — ver Pendências de Deploy (item #3, resolvido). |
| ~~35~~ | ~~`desktop/src/components/VaultManagement.tsx:386`~~ | ~~`handleTogglePerm` chama `invoke("vault_set_device_permission", { pub_key, can_write })` com chaves snake_case, mas o comando Rust (`fn vault_set_device_permission(pub_key: String, can_write: bool)`, sem `rename_all`) espera as chaves JS em camelCase (`pubKey`/`canWrite`) — mesma convenção já usada em outras chamadas funcionais do próprio arquivo (ex: `get_ledger_address` com `accountIndex`). O toggle "Pode escrever"/"Só leitura" por device nunca funcionou; o erro era engolido por um `catch` vazio.~~ | **RESOLVIDO — Sessão 79**. `invoke` corrigido pra `{ pubKey, canWrite }`. `catch` vazio trocado por um estado `permError` exibido no painel de Permissões (mesmo padrão do `mutateError` já usado pras entradas), pra esse tipo de falha não ficar mais invisível. `tsc --noEmit`/`vitest` (47/47) limpos. |
| ~~36~~ | ~~`desktop/src/components/VaultManagement.tsx:317`~~ | ~~A condição que decide sucesso/erro após `vault_publish` só lançava erro quando **todos** os provedores de pin falhavam (`providers_failed.length > 0 && providers_ok.length === 0`). Falha parcial (alguns provedores ok, outros não) era tratada como sucesso total — o `updateVault` prosseguia on-chain sem avisar que a redundância de pinning foi perdida.~~ | **RESOLVIDO — Sessão 80**. Novo estado `pinWarning`: quando `providers_failed` não está vazio (mesmo com `providers_ok` não-vazio), mostra aviso não-bloqueante (`⚠ Redundância parcial: falhou em X (ok em Y)...`) e a publicação segue normalmente. `tsc --noEmit`/`vitest` (47/47) limpos. |
| ~~37~~ | ~~`desktop/src/components/VaultSettings.tsx:70`~~ | ~~`healthStatus` (resultado do health-check por provedor) era indexado pela posição no array `providers`. `handleRemove` apagava só a chave do índice removido, sem reindexar os provedores seguintes — depois de remover um provedor do meio da lista, o status de saúde exibido ficava associado ao provedor errado.~~ | **RESOLVIDO — Sessão 81**. `handleRemove` agora limpa `healthStatus` inteiro (`setHealthStatus({})`) em vez de tentar reindexar — força um novo health-check, mais simples que inventar um id estável pra um tipo que hoje não tem um. `tsc --noEmit`/`vitest` (47/47) limpos. |
| ~~38~~ | ~~`mobile/lib/services/vault_repository.dart:155`~~ | ~~`updateEntry` não verificava se encontrou uma entrada com o id informado antes de salvar — um id inexistente/obsoleto virava um no-op silencioso que ainda assim incrementava `version` e devolvia a entrada como se tivesse sido atualizada.~~ | **RESOLVIDO — Sessão 82**. `updateEntry` agora lança (`throw Exception(...)`) quando nenhuma entrada com o id existe, em vez de reportar sucesso silencioso — optei por lançar (não por replicar o `upsert`-insere-como-nova do Rust) porque o port Dart já separa `addEntry`/`updateEntry` como operações distintas, então "atualizar algo que não existe" é um erro de uso, não um caso de criação implícita. Novo teste em `vault_repository_test.dart` cobrindo o throw e confirmando que a lista não ganha uma entrada nova. `flutter test` (15/15) e `flutter analyze` (0 erros, mesmos 5 avisos pré-existentes não relacionados) limpos via Docker. |
| ~~39~~ | ~~`desktop/src/components/VaultManagement.tsx:288`~~ | ~~O `useEffect` que dispara `updateVault` depois do `vault_publish` só dependia de `[pendingUpdate]`. Se a wallet não estivesse conectada quando o efeito rodava, ele abria o modal de conexão e retornava sem chamar `writeContract` — mas como `isConnected` não estava nas dependências, conectar a wallet depois nunca reexecutava o efeito sozinho (contorno manual: clicar "Enviar" de novo).~~ | **RESOLVIDO — Sessão 83**. `isConnected` e `smartAccountAddress` (este último lido pelo efeito desde o fix do débito #33) adicionados ao array de dependências — sem adicionar `writeContract`/`openConnectModal` (referências potencialmente instáveis entre renders, que arriscariam reabrir o modal repetidamente). Sem risco de disparo duplicado: o guard `if (!pendingUpdate) return` já barra reexecuções depois que `setPendingUpdate(null)` roda. `tsc --noEmit`/`vitest` (47/47) limpos. |
| ~~40~~ | ~~`desktop/src/components/VaultSettings.tsx:90`~~ | ~~`handleFormAdd` só exigia `name`/`endpoint_url` preenchidos, mesmo quando `kind === "psa"` — a API key (obrigatória pra qualquer provedor PSA funcionar) não tinha validação equivalente antes de salvar.~~ | **RESOLVIDO — Sessão 84**. Nova variável `formInvalid` (componente PSA exige `api_key` não-vazio também) usada tanto no `handleFormAdd` quanto no `disabled` do botão "Adicionar" — evita duplicar a condição em 2 lugares que podiam divergir. `tsc --noEmit`/`vitest` (47/47) limpos. |
| ~~41~~ | ~~`contracts/src/VaultRegistry.sol:71`~~ | ~~`updateVault` validava que `cid` não é vazio mas nunca validava que `contentHash` é diferente de zero, apesar do comentário do struct dizer que esse campo existe pra verificação de integridade.~~ | **RESOLVIDO — Sessão 85**. Novo erro `EmptyContentHash()` + `if (contentHash == bytes32(0)) revert EmptyContentHash();`, mesmo padrão do `EmptyCid()`. Novo teste `test_Revert_UpdateVault_ContentHashVazio`. `forge test` 213/213 (era 212, +1). Sem redeploy necessário — `VaultRegistry` ainda não foi deployado em rede nenhuma. |
| ~~42~~ | ~~`contracts/src/VaultRegistry.sol:117`~~ | ~~`_getCallerIdentityId()` era cópia verbatim da mesma função em `SessionRegistry.sol`/`DeviceRegistry.sol` (inclusive redefinindo o mesmo erro `NotIdentityController`), e fazia 2 chamadas externas + copiava o struct `Identity` inteiro (incluindo a string `username`) só pra extrair o `id` — padrão repetido nos 3 contratos.~~ | **RESOLVIDO (código) — Sessão 86**. Novo contrato-base `IdentityResolver.sol` (primeiro uso de herança em `contracts/src/`), herdado por `DeviceRegistry`/`SessionRegistry`/`VaultRegistry`; novo accessor `IdentityRegistry.getIdentityIdByController(address)` reduz a resolução de 2 chamadas externas pra 1, sem copiar o struct inteiro. Gas medido (`forge test --gas-report`, antes/depois via `git stash`): `registerDevice` 204.428→195.037, `revokeDevice` 51.490→40.767, `revokeSession` 53.880→43.157, `revokeAllSessions` 65.169→54.446 (todas ~10.7k gas mais baratas na mediana). 215/215 testes Foundry (era 213, +2 novos em `IdentityRegistry.t.sol`). `docs/docs/contracts.mdx` atualizado com os números novos. **Deploy feito na Sessão 88** — ver Pendências de Deploy (item #4). |
| ~~43~~ | ~~`desktop/src/components/VaultManagement.tsx:199`~~ | ~~Toda a orquestração de publicação on-chain (máquina de estados do wagmi) vivia inline num único componente de UI de 743 linhas, ao contrário do padrão já estabelecido no repo de extrair essa lógica pra um hook reutilizável (ex: `desktop/src/hooks/useSmartAccountActivity.ts`).~~ | **RESOLVIDO — Sessão 87**. Extraída pra `desktop/src/hooks/useVaultPublish.ts` (novo) — estados de publish, leituras `hasVault`/`getVault`, os 2 `useEffect` de execute/confirmação, `handleEnviar` e o label do botão, tudo isolado do JSX. Componente caiu de 743 → 632 linhas. `tsc --noEmit`/`vitest` (47/47) limpos. |
| 44 | `desktop/src/components/CreateIdentity.tsx` | Se a transação 2 (`deployAccount`) ou 3 (`fundAccount`) falhar por qualquer motivo (achado real, Sessão 90: erro "Nonce provided for the transaction is lower than the current nonce of the account", provavelmente causado pela Ledger tendo assinado várias transações fora do app minutos antes — o redeploy em cascata da Sessão 88/89 — deixando o nonce que o wagmi tinha em cache desatualizado), o fluxo fica travado pra sempre: os refs `tx2Submitted`/`tx3Submitted` nunca resetam, então recarregar a página não tenta de novo — em vez disso, `existingUsername` (que já é `true`, pois a identidade foi criada com sucesso na tx1) faz o componente cair direto no branch "Identity already registered", escondendo que a smart account nunca foi deployada nem financiada. Sem essa etapa, `smartAccountAddress` fica um endereço CREATE2 previsto mas sem código (`0x`) e sem saldo — a identidade existe on-chain mas é inutilizável (qualquer UserOperation reverteria). Contornado manualmente nesta sessão via `cast send --ledger` chamando `factory.createAccount(owner, 0)` e depois enviando 0.001 ETH pro endereço previsto (confirmado via `cast code`/`cast balance` antes e depois). Não corrigido no código ainda. | **RESOLVIDO — Sessão 91**. Novo botão "Try again" aparece quando `tx2Error`/`tx3Error` está setado no step correspondente; ao clicar, reseta `tx2Submitted.current`/`tx3Submitted.current` para `false` e chama o `reset()` do `useWriteContract`/`useSendTransaction` (limpa `data`/`isError` do wagmi), permitindo que o mesmo `useEffect` já existente reenvie a transação com o nonce atualizado — sem precisar recarregar a página (o que antes mascarava o problema atrás de "Identity already registered"). `tsc --noEmit`/`vitest` (47/47) limpos. Validação manual com a Ledger física ainda pendente (dono do projeto). |
| 45 | `desktop/src/components/ConnectLedger.tsx` | Mesma classe de bug já resolvida em `CreateIdentity.tsx` (chamadas HID concorrentes travando a Ledger sem erro): o polling de detecção (a cada 1s), a listagem sequencial de 5 contas, e o `handleConnect` competiam pelo mesmo dispositivo físico sem nenhum guard — um clique em "Connect" antes da listagem terminar (ou o próprio polling reentrante) podia disparar 2 chamadas HID simultâneas. Além disso, `device.write()` no lado Rust (`ledger.rs`) não tem timeout (só a leitura tem, 5s) — uma chamada que trave na escrita nunca retorna, e sem timeout nenhum do lado do frontend, o botão "Connecting..." ficava travado pra sempre, sem nenhuma forma de tentar de novo a não ser matar o processo inteiro do app (achado real, Sessão 90 — travou de verdade depois do erro `locked` numa assinatura de "Unlock Vault", exigindo matar/religar o app repetidas vezes). | **RESOLVIDO — Sessão 90**. Novo `hidBusyRef` garante no máximo 1 chamada HID em voo por vez a partir do componente (polling, listagem e connect todos checam/setam o mesmo ref). Novo `withTimeout()` (8s) envolve todo `invoke()`/`connectAsync()` — mesmo que o lado Rust nunca retorne, o frontend desiste e libera o botão pra tentar de novo. `tsc --noEmit`/`vitest` (47/47) limpos. Não resolve a causa raiz de o `device.write()` do Rust não ter timeout (registrado como observação, não numerado à parte). |
| 46 | `desktop/src/components/VaultSettings.tsx` (guia "Como configurar o Kubo local") | O guia embutido no app (instalar Kubo, `ipfs init`, `ipfs daemon`, clicar "+ Adicionar Kubo local") não menciona configurar CORS no Kubo. Sem `API.HTTPHeaders.Access-Control-Allow-Origin`, o `fetch()` do health-check (`checkHealth` em `VaultSettings.tsx:24`, chamado direto do frontend, não via Rust) é bloqueado pelo WebKitGTK por origem diferente (`http://localhost:1420` → `http://localhost:5001`) — mesmo com o Kubo respondendo normalmente (confirmado via `curl` direto, Sessão 90). Qualquer usuário seguindo o guia do próprio app do jeito que está escrito veria o provider aparecer com "✕" permanentemente, mesmo com tudo funcionando. | **RESOLVIDO — Sessão 91**. Guia reordenado: novo passo 3 "Liberar CORS pro app" (`ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["*"]'` + `Access-Control-Allow-Methods`) antes do passo de iniciar o daemon, com nota explicando o porquê (origens diferentes `localhost:1420`/`localhost:5001`); "Configurar no TruthID" virou o passo 5. `tsc --noEmit`/`vitest` (47/47) limpos. |
| 47 | `mobile/lib/contracts/abis.dart` | `deviceRegistryAbi` nunca incluiu a função `deviceVaultKeys` (getter automático do mapping público em `DeviceRegistry.sol`) — `_deviceContract.function('deviceVaultKeys')` lançava `Bad state: No element`, engolido em silêncio pelo try/catch de `getDeviceVaultKey`, sempre retornando `null`. **Bug raiz real por trás de toda a saga "vault key not available" desde a Sessão 76** — nenhuma vault key jamais poderia ter sido recuperada via pareamento, em nenhuma sessão anterior, independente de qualquer outro fator (app em background, formato de chave, etc.). Só achado ao instrumentar o código com prints de debug e testar contra Base Mainnet real (Sessão 92). | **RESOLVIDO — Sessão 92**. Função `deviceVaultKeys(address) returns (bytes)` adicionada ao ABI. Teste de regressão novo `mobile/test/contracts/abis_test.dart` — parseia os ABIs reais (não mockados) e confirma que toda função chamada em `blockchain_service.dart` existe; falha exatamente como o bug original quando revertido manualmente (verificado). |
| 48 | `desktop/src-tauri/src/lib.rs` (`encrypt_vault_key_for_device`) | O comentário dizia "Deriva chave AES do shared secret via SHA-256" mas o código nunca fazia esse hash — usava o segredo ECDH cru (32 bytes) direto como chave `Aes256Gcm`. O mobile (`decryptVaultKeyFromPairing`) sempre fez `sha256(sharedSecret)` corretamente. As duas pontas nunca derivavam a mesma chave AES — toda vault key entregue via pareamento falhava a decifra com `SecretBoxAuthenticationError` (MAC), desde que o ECIES existe (Sessão 76). Junto com o débito #47, explica por completo por que a Sessão 90 nunca conseguiu ver uma senha decifrada de verdade. | **RESOLVIDO — Sessão 92**. `Sha256::digest(shared_bytes)` adicionado antes de construir a chave AES. Lógica extraída pra `encrypt_bytes_for_device` (função pura, sem depender do keyring do SO) pra ficar testável; novo `#[cfg(test)] mod tests` em `lib.rs` faz o round-trip completo (cifra com a função real, decifra reimplementando o algoritmo do mobile) — falha sem o hash, passa com ele. `cargo test`: 15/15. |
| 49 | `mobile/lib/services/device_key_service.dart` | `_getOrCreateKey()` fazia "check-then-write" sem nenhuma trava: cada tela cria sua própria instância de `DeviceKeyService`, e num install novo, se duas chamam o método quase ao mesmo tempo, cada uma via a storage vazia e gerava sua própria chave aleatória — quem escrevia por último "vencia", deixando a outra tela com um endereço órfão em memória (observado na prática: "Devices" e "Pair device" mostrando endereços diferentes logo após reinstalar, Sessão 92). | **RESOLVIDO — Sessão 92**. Campo `_keyFuture` agora é `static` — memoiza a criação da chave entre todas as instâncias da classe, garantindo que só a primeira chamada gera/grava, as demais esperam o mesmo resultado. |
| 50 | `mobile/lib/services/device_key_service.dart` (`getDevicePublicKeyHex`) | Retornava os 64 bytes crus (X\|\|Y) que o `web3dart` usa pra derivar endereço (convenção Ethereum), sem o prefixo SEC1 `0x04`. O lado Rust (`encrypt_vault_key_for_device`) exige exatamente 33 (comprimida) ou 65 bytes (não-comprimida) e rejeitava os 64 bytes — erro engolido em silêncio, deixando `encryptedVaultKey` vazio (`0x`) pra sempre pra aquele device (mesmo sintoma dos débitos #47/#48, causa adicional). | **RESOLVIDO — Sessão 92**. `getDevicePublicKeyHex()` agora prependa `0x04` antes dos 64 bytes, produzindo o formato SEC1 uncompressed (65 bytes) que o Rust espera. |
| 51 | `desktop/src/components/PairDevice.tsx` | Mesma classe de bug já resolvida no débito #44 (`CreateIdentity.tsx`): quando o commit ou o reveal do pareamento revertia on-chain, `registerPhase` ficava preso em `"committing"`/`"registering"` pra sempre — o botão "Register device" ficava desabilitado sem nenhuma forma de tentar de novo, mesmo com endereço/label ainda preenchidos (achado ao validar ao vivo contra Base Mainnet, Sessão 92 — o erro genérico "unknown error executing 'execute'"/"executeBatch reverted" é comum nesse fluxo, ex: nonce desatualizado ou `DeviceAlreadyRegistered`). | **RESOLVIDO — Sessão 92**. Novo `useEffect` reseta `registerPhase` pra `"idle"` quando `isCommitError \|\| isRegisterError`; `resetCommit()`/`resetRegister()` (novo `reset` de `useWriteContract`) chamados no início de `handleRegister()` pra limpar o estado da tentativa anterior. Teste novo em `PairDevice.test.tsx` (re-habilita o botão após erro). `tsc --noEmit`/`vitest` (48/48) limpos. |
| 52 | `contracts/src/DeviceRegistry.sol:139` (`revokeDevice`) | `revokeDevice` seta `revoked = true` mas nunca reseta `exists` — e `registerDevice` reverte com `DeviceAlreadyRegistered` pra qualquer endereço onde `exists` já seja `true`, mesmo revogado. **Resultado: um endereço de device, uma vez registrado, nunca mais pode ser registrado de novo — nem pela mesma identidade, nem por outra — mesmo depois de revogado.** Descoberto ao tentar "revogar + parear de novo" pra resolver os débitos #47/#48 (Sessão 92): a mesma chave de device física (persistida permanentemente no `flutter_secure_storage`) fica banida pra sempre assim que revogada uma vez. Contorno usado: reinstalar o app mobile gera uma chave nova (endereço novo), viável só em dispositivos de teste/dev. | **NÃO RESOLVIDO** — decisão de design pendente do dono do projeto (exigiria uma função nova no contrato tipo `reregisterDevice`/resetar `exists`, ou aceitar a limitação como intencional, + redeploy em cascata dos 5 contratos). Registrado na Sessão 92. |
| ~~53~~ | ~~`mobile/lib/services/blockchain_service.dart`~~ | ~~As 7 chamadas JSON-RPC do mobile (eth_call, eth_getLogs, eth_getBalance, eth_blockNumber, eth_getTransactionReceipt, eth_getBlockByNumber) dependiam de uma única RPC pública hardcoded (`mainnet.base.org`), sem fallback nem timeout — cada uma repetia o mesmo boilerplate de `HttpClient().postUrl()`. Diferente do Desktop, que já usa `fallback()` do wagmi com 3 RPCs (`desktop/src/config/wagmi.ts`), o mobile ficava fora do ar inteiro assim que essa RPC aplicava rate limit — foi exatamente o que aconteceu ao vivo no fim da Sessão 92 (`-32016 over rate limit`), impedindo a confirmação final da decifra da vault key no celular.~~ | **RESOLVIDO — Sessão 93**. Novo helper único `_rpcCall()`/`_rpcCallOnce()` tenta 3 RPCs públicos da Base em ordem (`mainnet.base.org` → `base-rpc.publicnode.com` → `base.drpc.org`, mesma lista do Desktop), timeout de 10s por tentativa, cai pro próximo RPC em qualquer falha (rede, timeout ou erro no corpo) — mesmo padrão de fallback já usado pelo `IpfsGatewayClient` pros gateways IPFS. Os 7 call sites refatorados pra usar o helper, eliminando ~150 linhas de HTTP duplicado. Não validado contra o Docker (Flutter não instalado neste host, só via `mobile/dev.sh`) — revisão manual linha a linha do arquivo inteiro. |

---

## Pendências de Deploy (constantes placeholder no código)

Endereços de contrato que estão com placeholder `0x0` no código e precisam ser atualizados após o deploy em mainnet. **A fonte da verdade dessas pendências é esta seção, NÃO comentários no código.**

> ⚠️ **Nota de confiabilidade (Sessão 69)**: esta tabela e o Log de Sessões tinham ficado dessincronizados do estado real on-chain — o item #0 abaixo dizia "pendente" quando a Mainnet já rodava o código novo, e o log da Sessão 68 tinha um trecho corrompido (identificadores entre crases sumiram numa edição malformada). Antes de confiar nesta tabela para decidir um próximo redeploy, **verificar on-chain** (`cast call`/`cast code`) em vez de só ler aqui — ver Sessão 69 no Log de Sessões para o método.

> ✅ **Sessão 70 — redeploy completo dos 5 contratos** (débito #28: `IdentityRegistry` chamava a factory com o seletor antigo de 1 argumento) tornou os itens 0, 0b, 1 e 1b abaixo obsoletos — todos os 5 contratos (`IdentityRegistry`, `DeviceRegistry`, `RecoveryManager`, `TruthIDAccountFactory`, `SessionRegistry`) foram redeployados do zero em Sepolia e Mainnet. Endereços atuais: ver débito #28 na tabela acima e o Log de Sessões, Sessão 70. Linhas mantidas abaixo só como histórico.

| # | Constante | Arquivo | Valor atual | Deploy previsto | Etapa |
|---|---|---|---|---|---|
| 0 | `RecoveryManager` (débito #19) | `desktop/`, `mobile/`, `sdk/` (todos os endereços) | ver Fase 14.11 e Sessão 68 | ✅ Superado pelo redeploy completo da Sessão 70 (débito #28) | 14.11 / débito #19 |
| 0b | `TruthIDAccountFactory` (débito #25 — `index` no salt) | `desktop/src/config/truthidAccount.ts` | ver débito #28 | ✅ Superado pelo redeploy completo da Sessão 70 (débito #28) | 14.11 / débito #25 |
| 1 | `TRUTHID_ACCOUNT_FACTORY_ADDRESS` (deploy original da 14.7) | `desktop/src/config/truthidAccount.ts` | `0xe8aC0654515e11176CDBCD9D01521bEAbB7c545e` | ✅ Superado pelo redeploy completo da Sessão 70 (débito #28) | 14.7 |
| 1b | (Sepolia) | `desktop/src/config/truthidAccount.ts` (comentário) | `0x4A7a307cb6872bde24BAf3E9de2BeC3Ddd03e144` | ✅ Superado pelo redeploy completo da Sessão 70 (débito #28) | 14.7 |
| 2 | ~~`VAULT_REGISTRY_ADDRESS`~~ | ~~`desktop/src/config/contracts.ts`~~ | ~~`0x00...00`~~ | **RESOLVIDO — Sessão 88**. Primeiro deploy do `VaultRegistry` (feature implementada desde a Sessão 78-87, débitos #33-43), na mesma leva do redeploy do item #4. Sepolia `0x27E9288F06C42664812a1819235776D801Fd7Cf1`, Mainnet `0x602Fa39611960e5ef17D95a5d7b16816eE0ff734`. `VAULT_DEPLOYED`/`ZERO_ADDRESS` (feature flag em `SmartAccountDashboard.tsx`/`scanSmartAccountActivity.ts`) removido — o bucket "Vault" do dashboard e o scan de `VaultUpdated` agora rodam incondicionalmente. | 13.x / Sessão 88 |
| 3 | ~~`DeviceRegistry` (débito #34)~~ | ~~`contracts/src/DeviceRegistry.sol`~~ | ~~ver Fase 1.6~~ | **RESOLVIDO — Sessão 77**. Redeploy completo dos 5 contratos (mesma cascata da Sessão 70 — `SessionRegistry` e `TruthIDAccountFactory` têm o endereço do `DeviceRegistry` como `immutable`) em Sepolia e Mainnet, `totalIdentities()` confirmado em 0 nas duas redes antes do redeploy (sem identidade real perdida). Endereços novos e propagação completa (desktop, mobile, 3 SDKs, docs, README) na Sessão 77 do Log de Sessões. | ~~Sessão 76~~ / Sessão 77 / débito #34 |
| 4 | ~~`IdentityRegistry` + `DeviceRegistry` + `SessionRegistry` (débito #42)~~ | ~~`contracts/src/{IdentityRegistry,DeviceRegistry,SessionRegistry}.sol`~~ | ~~ver débito #42~~ | **RESOLVIDO — Sessão 88**. Cascata completa dos 5 contratos de novo (mesmo formato das Sessões 70/77) + primeiro deploy do `VaultRegistry` (item #2), em Sepolia e Mainnet. `totalIdentities()` confirmado em 0 nas duas redes antes do redeploy (sem identidade real perdida). Endereços novos e propagação completa (desktop, mobile, 3 SDKs, docs, README) na Sessão 88 do Log de Sessões. | Sessão 86 (código) / Sessão 88 (deploy) / débito #42 |

Ao fazer o deploy, atualizar:
1. A constante no código com o novo endereço
2. Esta tabela (remover a linha ou marcar como concluída)
3. Os endereços também precisam ser propagados para `mobile/lib/services/blockchain_service.dart` e `sdk/typescript/src/contracts.ts`

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

### 2026-06-30 — Sessão 52

- **Objetivo**: debate de arquitetura sobre Smart Account / ERC-4337 — leitura do `PROJECT_STATE_UPDATE_smart_account_paymaster.md` (Downloads) e resolução dos 4 problemas identificados.

**Contexto**: o documento de entrada levantava a vontade de eliminar hot wallet do dev e deixar o usuário bancar o próprio gás. Não era decisão travada — era brainstorm. Claude Code analisou os contratos existentes antes de debater.

**Problema 1 — `msg.sender` como controller**:
- Todos os contratos usam `msg.sender` como controller. No ERC-4337, quem chama é a smart account, não o EOA.
- Decisão: `createIdentity` aceita `address controller` explícito (CREATE2 pré-computado). Único contrato a mudar.
- DeviceRegistry e SessionRegistry ficam sem mudança — quando chamados pela smart account, `msg.sender` == smart account == controller registrado. Tudo alinha.

**Problema 2 — Bootstrap (ovo-e-galinha)**:
- Resolvido pelo CREATE2: smart account é pré-computada antes de existir. Ledger paga as 3 txs iniciais como EOA puro (createIdentity + deploy + fund). Após isso, só assina.

**Problema 3 — Permissões e DeviceRegistry**:
- Só o Ledger pode registrar/revogar devices. Devices do dia a dia (celular) têm permissões limitadas.
- Implementação: smart account com dois tiers (owner = Ledger / devices = lista interna). `validateUserOp` bloqueia chamadas ao DeviceRegistry quando signer é device.
- Lista interna própria (não consulta DeviceRegistry em validação) — evita restrições de cross-contract storage do ERC-4337.
- Todo gas (mesmo de UserOps do Ledger) debitado da smart account. Ledger nunca precisa de ETH após setup.

**Problema 4 — Recovery com saldo zero**:
- Recovery da identidade: RecoveryManager chama `IdentityRegistry.recoverController` diretamente. Guardiões pagam como EOAs. Zero bloqueio independente do saldo.
- ETH parado na smart account antiga: `emergencyWithdraw(address recipient)` na smart account, chamável só pelo RecoveryManager, migra saldo para nova smart account.

**Paymaster descartado**: projeto é open source, sem operador central. Auto-financiamento via EntryPoint é suficiente.

**Base da smart account**: fork do SimpleAccount (eth-infinitism) — referência ERC-4337, ECDSA secp256k1 (Ledger-native), CREATE2 via factory, ~150 linhas, sem dependências extras.

**Nota de sequência**: Fase 14 deve ser implementada antes das etapas 13.8 e 13.9 do Vault para evitar retrabalho no fluxo de assinatura mobile.

- **Resultado**: Fase 14 planejada com 12 etapas. Todas as decisões de arquitetura travadas.
- **Próximo passo**: iniciar 14.1 (atualizar `createIdentity`) ou concluir 13.8/13.9 primeiro (não recomendado — ver nota de sequência).

---

### 2026-06-30 — Sessão 53

- **Objetivo**: Fase 14, etapa 14.2 — implementar `TruthIDAccount.sol`.

**Decisões tomadas nesta sessão** (faltavam na Sessão 52):
- **EntryPoint v0.7** (`PackedUserOperation`), não v0.6 nem v0.8 — padrão mais maduro/suportado por bundlers públicos hoje. Trocar de versão depois (se necessário) segue o mesmo caminho que recovery social já usa (`emergencyWithdraw` + `transferController` pra smart account nova), sem exigir upgradeability/proxy — confirmado com o dono do projeto que essa migração é aceitável.
- **Checagem de malleability (low-s, EIP-2)** no `ecrecover` manual — o `SimpleAccount` original ganha de graça via OpenZeppelin; como não há essa dependência aqui, foi replicada manualmente (~100 gas a mais). Débito aberto: considerar o mesmo backport pro `SessionRegistry.sol`, que hoje faz `ecrecover` cru sem essa checagem.
- **Sem `addDeposit`/`getDeposit`** — só `receive()` + pagamento just-in-time do prefund. Suficiente e correto pro padrão ERC-4337 v0.7 (que verifica saldo recebido durante `validateUserOp`, não um ledger de depósito separado). Dashboard da 14.10 pode ler `address(this).balance` direto.

**Gap de segurança identificado e fechado** (via agente de planejamento que estressou o design antes da implementação): um device autorizado poderia se autopromover mandando `execute(address(this), 0, abi.encodeCall(addDevice, (atacante)))` — auto-chamada que faz `addDevice` enxergar `msg.sender == address(this)`. Fechado bloqueando, em `validateUserOp` para signers de tier device, qualquer `execute`/`executeBatch` cujo destino seja `deviceRegistry` OU `address(this)`. Como consequência, `addDevice`/`removeDevice` aceitam três chamadores (`owner`, `entryPoint`, `address(this)`) — os três só são alcançáveis quando o signer da UserOp original era o owner.

**Implementação** (`contracts/src/TruthIDAccount.sol`, arquivo novo, zero imports):
- `struct PackedUserOperation` declarada no escopo do arquivo (não importada).
- `validateUserOp`, `execute`/`executeBatch`, `addDevice`/`removeDevice`, `receive()`.
- `_isDeviceCallAllowed`/`_isDestAllowed`: only-allow-list de seletor (`execute`/`executeBatch`) + bloqueio de destino para signers de tier device.
- `forge build`: compila limpo. `forge fmt --check`: sem alterações necessárias. `forge test`: 134 testes existentes continuam passando (nenhum teste novo nesta etapa — são a 14.5).

**`/code-review` (high effort) rodado sobre o diff da 14.1+14.2 antes do commit — 8 achados, ranqueados por severidade:**

1. **[CONFIRMED, corrigido nesta sessão]** `_isDestAllowed` só negava `deviceRegistry`/`address(this)` — device conseguia sequestrar a identidade via `IdentityRegistry.transferController` ou reconfigurar guardiões via `RecoveryManager.configureGuardians`. Corrigido com o mapping `blockedForDevices` extensível (ver acima).
2. **[CONFIRMED, aberto]** `IdentityRegistry.createIdentity` (14.1, já commitado antes desta sessão) aceita `controller` arbitrário sem checar autorização — squatting/griefing de endereço alheio. Registrado como débito #17 na tabela de Débitos Técnicos de Arquitetura.
3. **[PLAUSIBLE, aberto]** `_isDeviceCallAllowed` pode reverter (via `abi.decode`) em vez de retornar `SIG_VALIDATION_FAILED` de forma limpa se o calldata vier malformado. Registrado como débito #18. Impacto baixo (bundlers pré-simulam).
4. **[PLAUSIBLE, corrigido]** `abi.decode` gastava gas decodificando `value`/`func` não usados em `_isDeviceCallAllowed`. Otimizado com leitura direta de calldata (`execute`) e decode parcial do primeiro elemento do tuple (`executeBatch`). A correção introduziu um bug próprio — bits superiores não mascarados na extração via assembly, o que reabriria o bypass do bloqueio de auto-chamada com calldata malicioso; identificado e corrigido (máscara explícita) antes do commit.
5. **[PLAUSIBLE, aceito como está]** `address(this)` como chamador autorizado de `execute`/`executeBatch` é generalidade não estritamente necessária hoje (só `addDevice`/`removeDevice` usam esse caminho) — mantido por simplicidade de ter um único gate `_requireAuthorized` para as 4 funções, em vez de dois gates distintos.
6. **[PLAUSIBLE, parcialmente aberto]** Padrão `ecrecover` + prefixo `"\x19Ethereum Signed Message:\n32"` duplicado do `SessionRegistry.sol`, com a checagem low-s presente só na `TruthIDAccount`. Mesmo débito já citado acima (backport da checagem low-s pro `SessionRegistry`).
7. **[PLAUSIBLE, resolvido com comentário]** Captura de `success` no pagamento do prefund parecia código morto — na verdade é proposital (silencia o linter `unchecked-call` do `forge build`); comentário reescrito pra deixar isso explícito em vez de remover a linha (tentativa de remover reintroduziu o warning do linter).
8. **[PLAUSIBLE, corrigido]** `executeBatch` tinha um atalho de array `value` vazio (= todas as chamadas sem ETH) que exigia uma checagem e um ternário extras. Simplificado: agora exige `value.length == dest.length` sempre.

- **Resultado**: 14.2 concluída, com a correção de segurança do achado #1 já commitada (`5396b16`).
- **Próximo passo**: 14.3 — `emergencyWithdraw(address recipient)` na `TruthIDAccount`, chamável só pelo `RecoveryManager`.

---

### 2026-06-30 — Sessão 54

- **Objetivo**: Fase 14, etapa 14.3 — `emergencyWithdraw` no `TruthIDAccount.sol`.

`address public immutable recoveryManager` já existia desde a correção de segurança da 14.2 (Sessão 53) — nenhuma mudança de constructor necessária. Adicionado `emergencyWithdraw(address recipient)`, restrito a `msg.sender == recoveryManager`, transferindo `address(this).balance` inteiro via `_call` (reuso do helper já existente, que já propaga revert reason — sem duplicar lógica). Novos erros `NotRecoveryManager`/`InvalidRecipient`, novo evento `EmergencyWithdraw`. Comentário de topo do arquivo atualizado pra mencionar essa terceira autoridade (além dos dois tiers de signer). `forge build`/`forge fmt --check`/`forge test` (134 testes) limpos, sem warnings novos.

**Gap identificado e registrado (não resolvido nesta sessão)**: nada em `RecoveryManager.sol` chama `emergencyWithdraw` ainda — a função fica funcional mas inalcançável até uma etapa futura conectar os dois lados (o `RecoveryManager` também não rastreia endereço de smart account nenhum hoje, só teria acesso ao endereço do controller antigo via o evento `ControllerTransferred` do `IdentityRegistry`). Nenhuma das etapas 14.4–14.12 do roadmap cobre essa conexão explicitamente. Registrado como débito #19 na tabela de Débitos Técnicos de Arquitetura — decisão de design pendente do dono do projeto sobre quando/como resolver.

- **Resultado**: 14.3 concluída.
- **Próximo passo**: 14.4 — `TruthIDAccountFactory.sol` com CREATE2 determinístico.

---

### 2026-06-30 — Sessão 55

- **Objetivo**: resolver débito #18 — `_isDeviceCallAllowed` podia reverter em vez de retornar `SIG_VALIDATION_FAILED` de forma limpa em `executeBatch` malformado.

`abi.decode(callData[4:], (address[]))` movido pra uma função nova `_decodeExecuteBatchDest` (`external pure`), chamada via `try this._decodeExecuteBatchDest(callData) returns (...) { ... } catch { return false; }`. Qualquer revert/panic do decode passa a virar `false` em vez de propagar pra fora de `validateUserOp`. Escolhida em vez de reimplementar o decode manualmente em assembly com bounds-checks porque essa mesma função já causou um bug real de máscara uma vez (item 4 do review da Sessão 53) — `try/catch` reaproveita o `abi.decode` já correto no caminho feliz, sem introduzir aritmética ABI nova pra errar. Custo extra de um STATICCALL só no caminho device+`executeBatch` (menos comum que owner).

Criado `contracts/test/TruthIDAccount.t.sol` do zero (não existia nenhum teste pra esse contrato) — escopo restrito ao débito #18, não é suíte geral: 3 testes (calldata malformado retorna `1` sem reverter; destino permitido retorna `0`; destino bloqueado retorna `1`, garantindo que o `try/catch` não afrouxou `_isDestAllowed`).

**Bug crítico achado ao escrever o teste do caminho feliz** (não relacionado ao débito #18): o teste falhava mesmo com assinatura correta. Causa raiz: `_SECP256K1N_DIV_2` (introduzida na 14.2, Sessão 53) tinha 1 dígito hex a menos (`...681B20A` em vez de `...681B20A0`), fazendo o limiar real ser `n/32` em vez de `n/2` — rejeitava ~97% das assinaturas canônicas válidas como `SIG_VALIDATION_FAILED`, afetando owner e devices igualmente (a checagem roda antes de identificar quem assinou). Nunca foi pego porque não havia teste de caminho feliz pra `TruthIDAccount` até agora. Corrigido (dígito `0` adicionado) e conferido matematicamente (`== n // 2` via Python) antes de commitar. Registrado como débito #20 na tabela — já resolvido na mesma sessão.

`forge fmt --check`/`forge build`/`forge test` limpos: 137 testes passando (134 pré-existentes + 3 novos).

- **Débitos fechados**: #18, #20 (achado e resolvido na mesma sessão).
- **Próximo passo**: 14.4 — `TruthIDAccountFactory.sol` com CREATE2 determinístico.

---

### 2026-06-29 — Sessão 47

- **Objetivo**: resolver débito #16 — botão de doação em cripto.

**Abordagem escolhida**: endereço ETH + QR code (EIP-681) + botão copiar. Sem terceiros, sem JavaScript externo — QR gerado localmente em cada plataforma.

**Desktop** (`desktop/src/components/DonateModal.tsx`, `App.tsx`, `App.css`):
- Nova dependência: `qrcode.react` adicionada ao `package.json`.
- `DonateModal.tsx`: componente presentacional com `<QRCodeSVG>` (data=`ethereum:0xB54...`, fundo branco explícito para legibilidade no tema dark), endereço em `<code>`, botão "Copy address" com feedback "Copied!" por 2s via `navigator.clipboard.writeText()`.
- Botão `♥` adicionado ao `topbar-right` em `App.tsx` → abre modal com o padrão já existente (`.modal-overlay` → `.modal-box` → `DonateModal`).
- CSS: 2 classes novas (`.donate-qr-wrapper`, `.donate-address`).

**Mobile** (`mobile/lib/main.dart`):
- Sem nova dependência (`qr_flutter: ^4.1.0` já disponível, `Clipboard` built-in de `flutter/services.dart`).
- `IconButton(Icons.favorite_border)` adicionado nas `actions` do `AppBar`.
- `_showDonationSheet()` usa `showModalBottomSheet` + `StatefulBuilder` (variável `copied` no escopo de fechamento para não resetar a cada rebuild).
- `_DonationSheet`: handle bar, título, `QrImageView` com fundo branco, `SelectableText` com endereço, `ElevatedButton.icon` copiar, hint de valor sugerido.

**Docs** (`docs/src/pages/donate.tsx`, `docs/docusaurus.config.ts`):
- Nova dependência: `qrcode.react` adicionada ao `docs/package.json`.
- Página `/donate` em React (Docusaurus suporta páginas em `src/pages/`): layout padrão + QR code + endereço + botão copiar com estado `copied`.
- Link "♥ Support" adicionado ao footer ("More") em `docusaurus.config.ts`.
- `npm run build` do Docusaurus: sucesso sem erros.

**Verificação**: `flutter analyze` → `No issues found!`; `flutter test` → 8/8; `npm run build` (docs) → success.

- **Débitos fechados**: #16 (último débito — tabela de débitos totalmente limpa).
- **Próximo passo**: ~~Fase 12~~ — concluída na Sessão 48. TruthID v1.0.0 publicado.

### 2026-06-29 — Sessão 49

- **Objetivo**: Iniciar Fase 13 (TruthID Vault) — etapas 13.1 e 13.2.

**O que foi feito**:

- Título do app corrigido para "TruthID" em todas as plataformas: `desktop/src-tauri/tauri.conf.json` (`productName` + `windows[0].title`), `mobile/android/app/src/main/AndroidManifest.xml` (`android:label`), `mobile/web/index.html` (`<title>` + `apple-mobile-web-app-title`), `mobile/ios/Runner/Info.plist` (`CFBundleDisplayName` + `CFBundleName`).
- **13.1 — `VaultRegistry`**: contrato Solidity em `contracts/src/VaultRegistry.sol`. Guarda `identityId → { cid, contentHash, updatedAt, version }` — apenas a referência ao blob cifrado no IPFS, nunca o conteúdo. Funções: `updateVault` (só o controller da identidade), `getVault`, `getVaultHistory`, `hasVault`. 12 testes Forge passando. Script de deploy em `contracts/script/DeployVaultRegistry.s.sol` apontado para Base Mainnet — deploy pendente para quando cifra/decifra estiver pronta.
- **13.2 — HKDF**: Desktop: adicionados `hkdf = "0.12"` e `sha2 = "0.10"` ao `Cargo.toml`; função `pub(crate) derive_vault_key()` em `lib.rs` — deriva 32 bytes via HKDF-SHA256 (RFC 5869) a partir da chave privada do device, nunca exposta como comando Tauri. Mobile: adicionado `package:crypto ^3.0.3` ao `pubspec.yaml`; `DeviceKeyService` ganhou `getPrivateKeyBytes()`; novo `VaultKeyService` em `mobile/lib/services/vault_key_service.dart` com implementação HKDF manual (Extract + Expand); 5 testes Dart passando.

**Verificação**: `forge test --match-contract VaultRegistryTest` → 12/12; `flutter test test/services/vault_key_service_test.dart` → 5/5.

- **Próximo passo**: ~~13.3~~ — concluída na Sessão 50.

### 2026-06-29 — Sessão 50

- **Objetivo**: Fase 13.3 — cifra/decifra local do vault com AES-256-GCM.

**O que foi feito**:

- **13.3 — AES-256-GCM**: Desktop: adicionados `aes-gcm = "0.10"` e `base64 = "0.22"` ao `Cargo.toml`; novo módulo `desktop/src-tauri/src/vault.rs` com `pub(crate) fn encrypt(plaintext: &[u8])` e `pub(crate) fn decrypt(blob: &[u8])`; dois Tauri commands `vault_encrypt`/`vault_decrypt` (entrada/saída em Base64) registrados em `lib.rs`; 5 testes Rust passando. Mobile: adicionado `cryptography: ^2.7.0` ao `pubspec.yaml`; novo `VaultCipherService` em `mobile/lib/services/vault_cipher_service.dart` usando `AesGcm.with256bits()` do pacote `cryptography`; 8 testes Dart passando.

- **Formato do blob** (idêntico em ambas as plataformas): `nonce(12 bytes) || ciphertext || tag(16 bytes)`. Nonce gerado aleatoriamente por encrypt — cifrar o mesmo plaintext duas vezes produz blobs distintos.

**Verificação**: `cargo test vault` (Docker) → 5/5; `flutter test test/services/vault_cipher_service_test.dart` (Docker) → 8/8.

- **Próximo passo**: ~~13.4~~ — concluída na Sessão 50.

### 2026-06-29 — Sessão 50 (continuação)

- **Objetivo**: Fase 13.4 — CRUD local de entradas do vault.

**O que foi feito**:

- **13.4 — CRUD local**: Desktop: structs `VaultEntry` (id, site, url, username, password, notes, profile, created_at, updated_at) e `Vault` (version, entries) com `#[derive(Serialize, Deserialize)]`; `impl Vault { upsert, delete }`; funções `load()`/`save()` que cifram/decifram via `vault::encrypt`/`decrypt` e persistem em `$HOME/.truthid/vault.enc`; geração de ID via `rand::OsRng` + `hex::encode` (sem dependência nova); três novos Tauri commands (`vault_list_entries`, `vault_upsert_entry`, `vault_delete_entry`) registrados em `lib.rs`; 11 testes Rust passando (6 de CRUD + 5 de cifra do 13.3). Mobile: classe `VaultEntry` com `fromJson`/`toJson`/`copyWith`; `VaultRepository` com `listEntries`/`addEntry`/`updateEntry`/`deleteEntry`; persistência via `path_provider` + `VaultCipherService`; cipher `_FakeCipherService` no-op para testes; `path_provider: ^2.1.0` adicionado ao `pubspec.yaml`; 11 testes Dart passando.

- **Formato JSON do vault** (idêntico nas duas plataformas): `{"version": N, "entries": [...]}` — o mesmo blob que vai ao IPFS em 13.5.

**Verificação**: `cargo test vault` (Docker) → 11/11; `flutter test test/services/vault_repository_test.dart` (Docker) → 11/11.

- **Próximo passo**: ~~13.5~~ — concluída na Sessão 51.

### 2026-06-29 — Sessão 51

- **Objetivo**: Fase 13.5 — botão "Enviar" com batching + upload multi-pin IPFS.

**O que foi feito**:

- **13.5 — upload multi-pin**: novo módulo `desktop/src-tauri/src/ipfs.rs`. `PinningProvider { name, kind, endpoint_url, api_key }` — `kind = "kubo"` faz upload via `POST {endpoint}/api/v0/add` (Kubo HTTP RPC); `kind = "psa"` pina CID existente via IPFS Pinning Service API (`POST {endpoint}/pins`). Fluxo: upload para todos os Kubo providers → obtém CID → pina nos PSA providers. `content_hash = keccak256(blob cifrado)` prefixado com "0x" — passado direto ao `VaultRegistry.updateVault`. Config de providers em `~/.truthid/pinning_providers.json`. Em `vault.rs`: `mark_published(v)` e `pending_changes()` rastreiam versão publicada via `~/.truthid/vault.meta.json`. 4 novos Tauri commands: `vault_publish` (async — lê `vault.enc`, chama `ipfs::pin_vault`, retorna `{cid, content_hash, providers_ok, providers_failed}`), `vault_pending_changes`, `vault_get_providers`, `vault_set_providers`. Dependência adicionada: `reqwest = { version = "0.12", features = ["json", "multipart"] }`.

**Verificação**: `cargo test` (Docker) → 14/14 passando.

- **Próximo passo**: ~~13.6~~ — concluída na Sessão 51 (mesma sessão).

### 2026-06-29 — Sessão 48

- **Objetivo**: Fase 12.3 e 12.4 — publicar o release v1.0.0 e atualizar o site de docs.

**O que foi feito**:

- Bump de versão: `desktop/package.json` e `desktop/src-tauri/tauri.conf.json` atualizados de `0.1.0` para `1.0.0`.
- Fix de CI: `desktop/tsconfig.json` — adicionado `exclude` para arquivos de teste (`src/**/__tests__/**`, `*.test.ts`, `*.test.tsx`), que estavam sendo incluídos no `tsc` de produção e causando erro de tipo com mocks do vitest.
- Tag `v1.0.0` criada e publicada. CI gerou 8 artefatos: `app-release.apk`, `.deb`, `.AppImage`, `.rpm`, `.msi`, `.exe`, `.dmg`, `.app.tar.gz`.
- Release publicado manualmente no GitHub a partir do draft gerado pelo CI.
- `docs/src/pages/index.tsx`: novo componente `DownloadSection` que faz fetch de `api.github.com/repos/masterlxz/truthid/releases/latest` e renderiza botões de download por plataforma (Android, Linux, Windows, macOS) sem necessidade de atualizar o site a cada release.
- `docs/src/pages/index.module.css`: estilos para `.downloadSection`, `.downloadGrid`, `.downloadBtn`.

**Verificação**: build do Docusaurus (`npm run build`) passou sem erros; CI desktop + mobile: ambos `success`.

- **Fase concluída**: 12 (todas as etapas — 12.1, 12.2, 12.3, 12.4).
- **Próximo passo**: projeto v1.0.0 publicado. Sem etapas obrigatórias pendentes.

### 2026-06-28 — Sessão 46

- **Objetivo**: resolver débitos #14 e #15 — verificação on-chain passiva em todas as telas e refresh manual na tela de QR.

**Mudanças em `mobile/lib/screens/devices_screen.dart` (débito #14):**

- **`_reload()` enriquecido com checagem on-chain**: adicionado `BlockchainService` como dependência. `_reload()` agora sempre chama `_blockchain.getDevice(address)` (leitura gratuita via `eth_call`). Cobre três casos: (1) auto-descoberta — se device registrado on-chain mas `identityId` não está em storage, salva e busca username em background; (2) detecção de revogação — se device revogado ou removido, limpa storage automaticamente (`clearPairedIdentity()`); (3) estado normal — device ativo e storage já preenchido, sem mudança.
- **Botão "Show QR to pair" agora condicional**: movido para dentro do bloco `if (_pairedIdentityId == null)`, junto com o card de dica. Some quando o device está pareado e ativo; reaparece se revogado ou não registrado.
- **Dica visual**: texto "Pull down to check if already paired." adicionado abaixo das instruções no card de info.

**Mudanças em `mobile/lib/screens/show_device_qr_screen.dart` (débito #15):**

- **Botão "Check now"**: adicionado `TextButton.icon` com `Icons.refresh` abaixo do spinner em `_buildQrUI()`. Chama `_checkIfRegistered(_address!)` imediatamente ao tocar.
- **Estado `_isChecking`**: desabilita o botão durante a verificação e troca o label para "Checking..." — evita cliques duplicados e dá feedback visual.

**Mudanças em `mobile/lib/screens/sessions_screen.dart` (complemento ao #15):**

- **`_load()` enriquecido**: mesmo padrão do `DevicesScreen` — chama `getDevice()` on-chain em toda execução. Auto-descobre pareamento se `identityId` ausente; detecta revogação e limpa storage. `RefreshIndicator` já existente cobre o pull-to-refresh automaticamente.

- **`flutter analyze`**: sem issues. **`flutter test`**: 8/8 passando.

- **Débitos fechados**: #14, #15.
- **Próximo passo**: débito #16 (doação no desktop e mobile).

### 2026-06-28 — Sessão 45

- **Objetivo**: implementar @username no mobile, botão de scan centralizado no estilo Steam, e realizar teste E2E completo com o celular real (parear device, fazer login, revogar).

**Features implementadas (mobile):**

- **@username via `eth_getLogs`**: o `IdentityRegistry` não expõe `id → username`, mas o evento `IdentityCreated(uint256 indexed id, string username, address indexed controller)` é indexado pelo `id`. Novo método `getUsernameForIdentity(BigInt id)` em `blockchain_service.dart` faz `eth_getLogs` filtrando topic[0] = keccak256 da assinatura do evento + topic[1] = id (padded 32 bytes). Decodificação manual do ABI-encoded `string` no `log.data` (offset 32 bytes → length → bytes UTF-8). Chamada feita em background após o pareamento (`show_device_qr_screen.dart`). Username cacheado em `FlutterSecureStorage` via `savePairedUsername`/`getPairedUsername` (novo em `local_storage_service.dart`); limpo junto com `clearPairedIdentity`. Chips e headers de `devices_screen.dart` e `sessions_screen.dart` mostram `@username` se disponível, fallback para `Identity #X`.
- **Scanner centralizado (estilo Steam)**: `BottomNavigationBar` substituído por `BottomAppBar(shape: CircularNotchedRectangle(), notchMargin: 8)` + `FloatingActionButton(location: centerDocked)` ciano/navy. Nova widget `_NavTab` (`InkWell` + `Column`: ícone + label) para as duas abas laterais. Botão de scan removido do `AppBar` (redundante). Fix de layout: `SizedBox(height: 2)` removido do `_NavTab` pra evitar overflow de 2px na altura do `BottomAppBar` detectado pelos testes.
- **APK gerado**: `flutter build apk --debug` — não instalado ainda (usuário optou por testar o APK anterior).
- **Testes**: `flutter analyze` — `No issues found!`; `flutter test` — 8/8 passando.

**Teste E2E mobile (celular físico Samsung, Base Mainnet):**

- **Parear**: usuário copiou o endereço da tela de QR e colou no desktop app (em vez de escanear o QR com a câmera do desktop). Device registrado on-chain pelo desktop. Celular não detectou automaticamente porque o polling de `ShowDeviceQrScreen` só corre enquanto aquela tela está aberta — usuário precisou mantê-la aberta para o polling pegar a confirmação. **Descoberta**: mesmo quando se para via endereço colado, ainda é necessário estar na tela de QR. Registrado como débito #14 e #15.
- **Login real**: SDK de exemplo (`sdk/typescript/example/server.js`) expandido com página HTML de demo (`GET /`) e endpoint de QR server-side (`GET /auth/qr/:nonce` — `QRCode.toFileStream` gerando PNG no backend, sem CDN). Endpoint de polling (`GET /auth/poll/:nonce`) para a demo page detectar aprovação. Túnel HTTPS via `localhost.run` necessário porque o mobile exige `callbackUrl: https://` e `localhost` não é alcançável pelo celular. Resultado: **login aprovado** — `{ token, identityId, deviceAddress }` retornado e exibido na página. Sessão não registrada on-chain (sem `RELAYER_PRIVATE_KEY` no ambiente de teste — normal).
- **Revogar device**: feito pelo desktop app. Confirmado que após revogação o device não consegue mais logar (SDK retorna erro de device inativo).

**Problemas encontrados e resolvidos durante a sessão:**

| Problema | Solução |
|---|---|
| Disco root 0% durante `flutter build apk` | Removida imagem `ghcr.io/cirruslabs/flutter:stable` (7GB desnecessária) — root voltou para 73% livre (8.1GB) |
| QR library CDN (`cdn.jsdelivr.net/qrcode`) não carregou na demo page | Trocado para geração server-side com `npm install qrcode` + endpoint `GET /auth/qr/:nonce` que serve PNG via `QRCode.toFileStream` |
| `xhost` não instalado — desktop app Docker não abreria janela | Contornado passando `DISPLAY=:1 XAUTHORITY=/run/user/1000/xauth_JPkkZq` diretamente no `docker compose up` via `sg docker` |
| Túnel SSH bloqueado pelo modo automático do Claude Code | Usuário rodou `ssh -R 80:localhost:3000 nokey@localhost.run` no próprio terminal |

**Débitos registrados nesta sessão**: #14 (polling passivo em `DevicesScreen`), #15 (refresh manual em `ShowDeviceQrScreen`), #16 (doação no desktop e mobile).

**Features implementadas (continuação da Sessão 45 — GitHub CI e update checker):**

- **GitHub Actions — CI de APK** (`.github/workflows/build-mobile.yml`): workflow que dispara em tags `v*`. Usa `subosito/flutter-action@v2` com Flutter 3.44.4. Se o secret `KEYSTORE_BASE64` estiver configurado, decodifica a keystore e define as variáveis de assinatura antes do build. Roda `flutter build apk --release`. Faz upload do APK para o GitHub Release draft via `softprops/action-gh-release@v2`. Sem secrets configurados ainda — build funciona com debug key como fallback.
- **Signing config Android** (`mobile/android/app/build.gradle.kts`): `signingConfigs { create("release") }` lê `KEYSTORE_PATH`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` de variáveis de ambiente. Release build usa config de release se `KEYSTORE_PATH` presente, senão usa debug key. Permite builds locais sem configuração e builds CI com assinatura correta.
- **Update checker — desktop** (`desktop/src/hooks/useUpdateCheck.ts`, `App.tsx`, `vite.config.ts`): versão atual injetada em build time via `define: { __APP_VERSION__: pkg.version }` no Vite. Hook `useUpdateCheck()` busca `api.github.com/repos/masterlxz/truthid/releases/latest` no mount, compara semver. Se há versão mais nova, `App.tsx` exibe banner dismissível com link de download (botão ✕ para fechar). TypeScript: `declare const __APP_VERSION__: string` em `vite-env.d.ts`.
- **Update checker — mobile** (`mobile/lib/main.dart`, `pubspec.yaml`, `AndroidManifest.xml`): constante `_kAppVersion = '1.0.0'` hardcoded. `_checkForUpdate()` chamado no `initState` via `HttpClient` (já disponível no projeto). Semver comparison com `_isNewer()`. Widget `_UpdateBanner` com ícone de update, texto com versão, botão "Download" (`url_launcher`) e botão ✕. Adicionado `url_launcher: ^6.3.0` no `pubspec.yaml`. Query `https` scheme adicionada ao `AndroidManifest.xml` (obrigatório Android 11+ para `launchUrl` abrir browser). `flutter analyze`: sem issues. `flutter test`: 8/8 passando.
- **Commit**: `97d1cd9` — `feat: session 45 — @username display, FAB nav, GitHub CI, update checker`.

---

### 2026-06-28 — Sessão 44

- **Objetivo**: revisão de UX do app mobile — identificar e resolver todos os problemas de experiência do usuário encontrados na Sessão 43.
- **Planejamento**: 7 problemas identificados e mapeados para 5 arquivos. Plano gravado em `/home/masterlxz/.claude/plans/jazzy-swinging-raven.md`.
- **Fixes implementados**:
  - `mobile/lib/main.dart` — ícones da bottom nav: `phone_android` → `phonelink_lock` (phone com cadeado), `history` → `verified_user` (usuário verificado).
  - `mobile/lib/screens/devices_screen.dart` — string PT→EN: chip "Identidade #X" → "Identity #X"; Unpair com `showDialog` AlertDialog de confirmação antes de `clearPairedIdentity()` (ação destrutiva sem rollback precisa de confirmação).
  - `mobile/lib/screens/sessions_screen.dart` — string PT→EN: cabeçalho "Identidade #X" → "Identity #X"; formato de data: `28/06 at 12:30` → `Jun 28 at 12:30` (novo `_formatDate` com array de nomes de mês em inglês).
  - `mobile/lib/screens/scan_screen.dart` — overlay de scan: `body` trocado de `MobileScanner` puro por `Stack` com `MobileScanner` + `IgnorePointer(CustomPaint(_ScanOverlayPainter()))` + texto de instrução. `_ScanOverlayPainter` usa `saveLayer` + `BlendMode.dstOut` pra criar recorte transparente 260×260 sobre fundo `Colors.black54`, com borda ciano (`AppColors.accent`) e cantos arredondados. Importação de `../theme.dart` adicionada.
  - `mobile/lib/screens/approval_screen.dart` — 2 mudanças: (1) `LocalStorageService().getPairedIdentityId().then(...)` em `initState` carrega `_identityId` async; `_InfoRow(label: 'Signing as', value: 'Identity #$_identityId')` exibido quando disponível. (2) `displaySite` derivado do `callbackUrl` validado (`Uri.parse(_callbackUrl!).scheme + '://' + host`) em vez do campo `origin` do challenge — mostra `https://example.com` em vez de só `example.com`.
- **Teste atualizado**: `test/screens/approval_screen_test.dart` — `expect(find.text('example.com'), ...)` → `expect(find.text('https://example.com'), ...)` para refletir a nova exibição de site.
- **Verificação**:
  - `flutter analyze` (imagem `mobile-flutter:latest`, Flutter 3.44.4): `No issues found!`
  - `flutter test`: 8/8 passando.
- **Commit**: `14723ea` — `feat(mobile): UX polish — scanner overlay, unpair confirmation, identity display`.
- **Próximo passo**: sem débitos ou itens planejados abertos. Projeto completo.

### 2026-06-28 — Sessão 41

- **Objetivo**: resolver débitos técnicos #2, #3, #5, #6 e #12.
- **#2** — ABIs do mobile (`blockchain_service.dart`) extraídas de strings JSON inline para constantes nomeadas em `mobile/lib/contracts/abis.dart` (`sessionRegistryAbi`, `deviceRegistryAbi`). Agora há um lugar óbvio pra atualizar quando o contrato mudar. `flutter analyze`: sem erros.
- **#3** — `publicClient` no SDK TypeScript (`sdk/typescript/src/client.ts`) tipado como `ReturnType<typeof createPublicClient>` (era `any`). `tsc --noEmit`: limpo.
- **#5** — `ErrorBoundary` criado em `desktop/src/components/ErrorBoundary.tsx` e adicionado na raiz do `main.tsx` envolvendo toda a árvore. Erro em qualquer componente agora mostra mensagem + botão "Try again" em vez de tela branca.
- **#6** — `IdentityContext` criado em `desktop/src/contexts/IdentityContext.tsx` com hook `useIdentity()` que expõe `{ username, identityId }`. `ManageDevices` e `ActiveSessions` eliminaram o prop `username` e a chamada `getIdentity(username)` duplicada — usam `useIdentity()`. Novos componentes têm o hook disponível sem prop drilling.
- **#12** — Modo leitura sem wallet. Quatro mudanças coordenadas:
  - `desktop/src/config/wagmi.ts`: `storage: null` — wagmi não persiste o conector, sem auto-reconexão.
  - `desktop/src/hooks/useStoredUsername.ts` (novo): salva/lê username em `localStorage` com chave `truthid:username`, independente do wagmi.
  - `desktop/src/contexts/WalletModalContext.tsx` (novo): hook `useWalletModal()` que expõe `openConnectModal()` — qualquer componente pode abrir o modal de conexão.
  - `desktop/src/App.tsx`: nova máquina de estados — se há username no localStorage, mostra app shell direto (sem wallet); quando wallet conecta e username é verificado on-chain, salva no localStorage. Topbar: "Disconnect wallet" mantém modo leitura; "Log out" limpa localStorage e desconecta, voltando ao login. `ConnectWallet` agora aceita `asModal` para renderizar dentro de modal overlay.
  - `ManageDevices`, `ActiveSessions`, `PairDevice`, `DesktopDevice`: ações de escrita (`handleRevoke`, `handleRegister`) chamam `openConnectModal()` se wallet não está conectada, em vez de falhar silenciosamente.
- **Débitos fechados nesta sessão**: #2, #3, #5, #6, #12.
- **Próximo passo**: débito #13 (site de docs com Session Registration) ou débito #7 (testes de UI).

### 2026-06-28 — Sessão 43

- **Objetivo**: resolver débito #7 — testes de UI (desktop React + mobile Flutter).
- **Desktop** — Vitest + React Testing Library:
  - Instalado: `vitest`, `@testing-library/react`, `@testing-library/user-event`, `@testing-library/jest-dom`, `jsdom`, `@testing-library/dom`.
  - `vitest.config.ts` criado (environment jsdom, globals, setupFiles).
  - `src/test/setup.ts`: importa `@testing-library/jest-dom`.
  - `src/components/__tests__/PairDevice.test.tsx`: 9 testes — form fechado no início, abre ao clicar, botão Register disabled sem campos, erro de endereço inválido, botão habilitado com inputs válidos, Cancel fecha, sem wallet abre modal, com wallet chama `commitDevice`.
  - Todos os wagmi hooks mockados via `vi.mock`; endereços usam apenas dígitos hex para passar validação EIP-55 do viem.
  - **Resultado**: 9/9 passando (`npm test`).
- **Mobile** — flutter_test + mocktail:
  - `pubspec.yaml`: adicionado `mocktail: ^0.3.0` (dev_dependencies).
  - `ApprovalScreen` refatorado: `keyService` e `postResponse` agora são parâmetros opcionais do widget (injeção de dependências sem quebrar a API de produção).
  - `test/screens/approval_screen_test.dart`: 7 testes — 3 erros de QR inválido, UI do challenge com site name, approve (assina + posta + verifica mocks), reject (sem assinatura), proteção contra dupla resposta.
  - Timer de 800ms (`Future.delayed`) gerenciado com `pump(1000ms)` explícito após `pumpAndSettle` para evitar "pending timer" assertion do framework.
  - `test/widget_test.dart` corrigido: labels "Dispositivos"/"Sessões" → "Devices"/"Sessions" (tinham sido renomeados na Sessão 40).
  - **Resultado**: 8/8 passando (`flutter test`).
- **Infra**: `desktop/Dockerfile` — remoção do `cargo install tauri-cli` (commitado separadamente no início da sessão).
- **SDK Python** — `register_session` implementado:
  - `types.py`: novo dataclass `RegisterSessionResult(tx_hash, session_hash)`; `sessionSignature: Optional[str] = None` adicionado em `AuthResponse`.
  - `client.py`: `register_session(nonce, identity_id, device_pub_key, session_signature, relayer_private_key)` — `Web3.keccak(text=nonce)`, split `(r, s, v)` via `bytes.fromhex`, `build_transaction` → `sign_transaction` → `send_raw_transaction`.
  - `__init__.py`: `RegisterSessionResult` exportado.
- **SDK Ruby** — `register_session` implementado:
  - `types.rb`: `RegisterSessionResult = Struct.new(:tx_hash, :session_hash, ...)`; `session_signature` adicionado em `AuthResponse` (attr + `from_hash` mapeia `"sessionSignature"`).
  - `client.rb`: `register_session(nonce:, ...)` — `Eth::Util.keccak256(nonce)`, split com `.pack("H*")`, `@rpc.transact(..., sender_key: Eth::Key.new(...))`.
- **Docs**:
  - `docs/sdk/python.md` e `ruby.md`: seção `register_session` completa (parâmetros, exemplo, tip non-blocking, setup relayer, nota mobile v1.1+) — remove nota "TypeScript-only".
  - `docs/quickstart.mdx`: passo 5 sem "TypeScript only" no título; exemplo expandido em tabs TypeScript/Python/Ruby; link de referência aponta para os três SDKs.
  - Build Docusaurus: sem erros.
- **Próximo passo**: sem débitos ou itens planejados abertos. Projeto completo.

### 2026-06-28 — Sessão 42

- **Objetivo**: auditoria do site de docs + resolver débito #13.
- **Auditoria**: site comparado com o código atual. Tudo consistente (endereços, fluxo de auth, contratos, componentes removidos) exceto pelo débito #13 e pela ausência de `registerSession` no Python e Ruby SDKs.
- **#13** — `docs/docs/sdk/typescript.md`: seção `registerSession()` adicionada (parâmetros, retorno, exemplo, setup do relayer, nota de compatibilidade mobile); `sessionSignature` adicionado ao tipo `AuthResponse`; tipos `RegisterSessionParams` e `RegisterSessionResult` adicionados. `docs/docs/quickstart.mdx`: passo 5 opcional "Register session on-chain" (TypeScript). `docs/docs/sdk/python.md` e `ruby.md`: nota que `registerSession` é TypeScript-only por enquanto, com link para a referência TypeScript. Build do Docusaurus: sem erros.
- **Próximo passo**: débito #7 (testes de UI) é o único débito aberto. Sem outras pendências identificadas.

### 2026-06-27 — Sessão 40

- **Objetivo**: Redesign de UX do desktop — débito #8 (e #9 junto).
- **O que mudou**:
  - `ConnectWallet.tsx`: tela de login full-viewport com logo, tagline e dois botões com ícones SVG (WalletConnect azul, Ledger dark). Clicar em Ledger navega para sub-tela dedicada; clicar em WalletConnect abre o modal WC existente.
  - `ConnectLedger.tsx`: redesenhado como fluxo completo de 2 fases. Fase 1: stepper de 3 passos com estado visual por cor (ciano = ativo, verde ✓ = concluído, cinza = pendente), polling inicia ao montar. Fase 2: seleção de conta (Account 0–4) após device detectado. Botão Back em ambas as fases.
  - `App.tsx`: shell com topbar fixo (logo | `⎋ Login` · `@username` · `↻` · `Disconnect`); modal de Quick Login abre ao clicar `⎋ Login`; abas só Devices e Active Sessions (Login test removido); ConnectWallet renderiza full-screen quando não conectado (sem container wrapper).
  - `TestLogin.tsx` → `QuickLogin.tsx`: lógica idêntica (authenticate + register session on-chain), UI limpa para o modal (sem labels "Step 1/2", sem `<pre>` verde com JSON bruto).
  - `App.css`: novos estilos — `.wallet-screen`, `.wallet-option`, `.ledger-connect`, `.stepper`/`.step--*`, `.account-option`, `.topbar`, `.main-content`, `.modal-overlay`.
- **Débitos resolvidos**: #8 (UX/layout), #9 (stepper visual Ledger), #10 (endereços Ethereum no seletor de conta).
- **Próximo passo**: débito #12 (desabilitar auto-reconexão wagmi), #13 (site de docs com Session Registration), ou outros da lista.

### 2026-06-27 — Sessão 39

- **Objetivo**: Resolver débito técnico #11 — registro de sessão on-chain para logins mobile.
- **Problema**: O mobile não tem ETH para pagar gas, então nunca chamava `createSession` no `SessionRegistry`. `ActiveSessions` ficava vazio para logins mobile. O SDK não tinha helper para isso, e o mobile não assinava o session hash (só o challenge JSON).
- **Design adotado**: Padrão relayer — o servidor do integrador usa uma carteira financiada para submeter `createSession`. O hash da sessão é `keccak256(utf8_bytes_do_nonce)`, derivado deterministicamente por ambos os lados sem round-trip extra. Mobile produz duas assinaturas no approve: a já existente (challenge JSON) + uma nova sobre o session hash de 32 bytes (`personal_sign` no formato que o contrato espera).
- **Arquivos modificados**:
  - `sdk/typescript/src/contracts.ts`: `createSession` adicionado ao `SESSION_REGISTRY_ABI`
  - `sdk/typescript/src/types.ts`: novos tipos `RegisterSessionParams` e `RegisterSessionResult`
  - `sdk/typescript/src/index.ts`: novos tipos exportados
  - `sdk/typescript/src/client.ts`: novo método `registerSession(...)` — computa session hash, split (r,s,v), cria walletClient com a chave do relayer, chama `SessionRegistry.createSession`. Também armazena `chain` e `rpcUrl` como campos da classe (necessário para criar o walletClient).
  - `sdk/typescript/example/server.js`: `/auth/verify` atualizado — após autenticação bem-sucedida, chama `registerSession` se `response.sessionSignature` e `RELAYER_PRIVATE_KEY` presentes. Não-fatal: se falhar, auth ainda retorna ok.
  - `sdk/README.md`: nova seção "Session Registration" explicando o padrão relayer, custo (frações de centavo no Base), setup (`RELAYER_PRIVATE_KEY` env var), e exemplo de código.
  - `mobile/lib/services/device_key_service.dart`: novo método `signHash(Uint8List hash32)` — `personal_sign` sobre 32 bytes, formato que o contrato espera.
  - `mobile/lib/screens/approval_screen.dart`: `_approve()` agora computa `sessionHash = keccak256(utf8.encode(nonce))`, assina com `signHash`, e inclui `sessionSignature` no POST. Backward-compatible: servidores antigos ignoram o campo novo.
- **Próximo passo**: débitos #8 (redesign UX desktop) ou #9 (stepper visual Ledger).
- **Também na Sessão 39 (segunda parte)**: débitos #1 e #4 resolvidos — `ManageDevices.tsx` quebrado em `DeviceList.tsx` + `PairDevice.tsx`; `DeviceInfo` movido para `desktop/src/types.ts`.

### 2026-06-27 — Sessão 38

- **Contexto**: retomada com o objetivo de fechar a Fase 11 — teste E2E prático de login com o device desktop registrado na Sessão 36 (identidade `@masterlxz`, id=1; device `0x0a0B7e76E331d83448F57640D8eE62438470438e`). Todas as 4 etapas foram validadas ao vivo com Base Mainnet e Ledger física.
- **Correções feitas antes/durante o teste**:
  - `sign_challenge` estava usando assinatura ECDSA pura — o SDK (`verifyAuthResponse`) esperava Ethereum `personal_sign` (prefixo `\x19Ethereum Signed Message:\n`). Corrigido no Rust pra usar o prefixo correto, alinhando desktop e SDK.
  - `send_apdu` no Rust tinha timeout fixo de 30s — insuficiente para a Ledger aguardar confirmação física do usuário. Parametrizado: detecção usa 5s, assinatura usa 120s.
  - `SESSION_REGISTRY_ABI` em `contracts.ts` não tinha a função `createSession` — estava faltando desde a auditoria da Sessão 24. Adicionado.
  - Novo comando Tauri `sign_session_hash`: assina um hash de 32 bytes com a chave do device usando `personal_sign`, devolvendo `(r, s, v)` separados para uso direto como argumentos ABI em `createSession`.
  - CORS não estava configurado no `sdk/typescript/example/server.js` — o app desktop (Tauri/WebKitGTK) é origem diferente de `localhost:3000`; adicionado middleware `cors()` no Express.
- **Novos componentes**:
  - `TestLogin.tsx`: componente de 2 etapas — Step 1 autentica no servidor (sign challenge → POST `/auth/verify`), Step 2 registra a sessão on-chain via `SessionRegistry.createSession` assinada pela chave do device. Arquivo criado nesta sessão mas não commitado (esquecido o `git add` — corrigido na Sessão 39 logo em seguida).
  - Aba "Login test" adicionada ao `App.tsx` com botão ↻ Refresh para recarregar o estado on-chain.
  - `invalidateQueries` + delay de 3s adicionados nos effects de sucesso de `ManageDevices` e `DesktopDevice` para que o cache do wagmi reflita o novo estado da blockchain após escritas on-chain.
- **Resultado do teste (Base Mainnet, Ledger física)**:
  - 11.1 — servidor retornou challenge válido ✓
  - 11.2 — desktop login retornou `{ token, identityId: "1" }` ✓
  - 11.3 — sessão criada on-chain e revogada via aba "Active sessions" ✓
  - 11.4 — device revogado → servidor retornou `"Device is not active or has been revoked"` ✓
- **Débitos técnicos registrados**: #11 (relayer server-side para `createSession` no fluxo mobile) e #12 (auto-reconexão do wagmi / modo leitura sem wallet).
- **Fase 11 — Teste E2E Prático: CONCLUÍDA.**
- **Próximo passo**: a definir — candidatos são redesign de UX (débito #8), stepper visual da Ledger (débito #9), ou implementação do relayer para sessões mobile (débito #11).

### 2026-06-27 — Sessão 37

- **Contexto**: retomada após crash do PC no meio da sessão anterior. Estado recuperado via `git diff HEAD` e revisão dos arquivos não commitados. Nenhum trabalho foi perdido.
- **Etapas concluídas**: 10.6 (multiplataforma udev/macOS/Windows) e 10.7 (CI hidapi nos 3 SOs) — trabalho estava completo mas não commitado antes do crash.
- **Fase 10 agora em 7/8**: só resta a etapa 10.8 (validação manual com Ledger física em cada SO).
- **Strings traduzidas para inglês**: todas as strings visíveis ao usuário no desktop (React/TypeScript) e mobile (Flutter/Dart) foram traduzidas de português para inglês. Comentários no código preservados. Diretriz de código em inglês registrada no PROJECT_STATE.md.
- **Próximo passo**: Fase 11 (teste E2E prático: login, revogação de sessão, revogação de device).

### 2026-06-25 — Sessão 36

- **Contexto**: retomada com o objetivo de fazer um teste prático real de ponta a ponta com o app desktop — conectar a Ledger, criar identidade, registrar o device, e observar o resultado na blockchain. Sessão também foi oportunidade de revisão de arquitetura (débitos técnicos registrados antes de iniciar).
- **Revisão de débitos técnicos de arquitetura**: antes de testar, lista de débitos registrada na seção "Débitos Técnicos de Arquitetura" (7 itens numerados, ordenados por impacto). Nenhum foi corrigido nesta sessão — registrados pra não perder.
- **Correções feitas durante o teste real**:
  - `encode_derivation_path(account_index: u32)` parametrizado no Rust — usuário precisava da conta 1 da Ledger (não a conta 0 padrão); campo `account_index` propagado para `get_ledger_address` e `sign_ledger_transaction`
  - Seletor de conta (Conta 0–4) adicionado ao `ConnectLedger.tsx`; `setLedgerAccountIndex` exportado do connector
  - `sign_ledger_transaction`: status words `0x6985`/`0x6750` mapeados para `"rejected_by_user"` (antes era `"locked"`, causando mensagem errada na UI)
  - Keyring do SO não disponível dentro do Docker → fallback para arquivo `$HOME/.truthid/device.key`; volume `${HOME}/.truthid:/root/.truthid` adicionado ao `docker-compose.yml` para persistência entre sessões
  - `JSC crash "err2 is not an Object"` (WebKit não suporta `"data" in primitiveValue`): corrigido com `toError()` em todos os caminhos de erro do connector Ledger e forwarding direto via `fetch()` para chamadas RPC que não eram `eth_sendTransaction`
  - `RevealTooEarly` revert no `registerDevice`: contrato exige `block.number > commitBlock`; corrigido com `setTimeout(sendRegister, 4000)` após `isCommitSuccess` no `DesktopDevice.tsx` e `ManageDevices.tsx`
  - Cache da wagmi não invalidado após registro → UI não atualizava; corrigido com `queryClient.invalidateQueries()` nos effects de sucesso
- **Resultado do teste**: identidade `@masterlxz` (id=1, controller `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265`, conta 1 da Ledger, HD path `m/44'/60'/1'/0/0`) criada em Base Mainnet. Device desktop (`0x1073e02eB26b371Dd1f04BcC0b5fd76e7ae7fFDD`) registrado sob essa identidade. Device foi registrado 3 vezes por equívoco (falha de feedback de UI antes da correção do `invalidateQueries`) — as 2 primeiras transações `commitDevice` foram cobradas sem completar o `registerDevice`.
- **Fase 11 criada**: nova fase de teste E2E prático registrada — próximo passo natural depois de ter identidade + device on-chain reais; cobre login real com o device, revogação de sessão e revogação do device (ver Fase 11 neste documento).
- **Próximo passo ao retomar**: iniciar a Fase 11 (etapa 11.1 — subir o servidor de exemplo e confirmar leitura de estado on-chain) ou continuar com Fase 10 (etapas 10.6-10.8 ainda pendentes).

### 2026-06-24 — Sessão 35

- **Contexto**: retomada direta da pendência registrada no fim da Sessão 34 — próximo passo era a etapa 10.5 (Fase 10, Ledger). Antes de implementar, perguntado ao usuário se valia revisitar a pendência #2 (teste E2E mobile↔desktop, ainda aberta desde a Sessão 33) em vez disso; usuário confirmou seguir com 10.5.
- **Escopo de 10.5 decidido com o usuário**: hoje só existe leitura de endereço (`get_ledger_address`, etapas 10.1-10.3) — nenhum comando de assinatura. "Paridade com os outros conectores" tinha duas leituras possíveis (só guardar o endereço como "conta ativa" vs. permitir assinar transações de verdade pela Ledger, igual aos outros conectores). Apresentadas as duas opções com o trade-off (a segunda exige implementar o protocolo de assinatura no Rust + um `Connector` customizado da `wagmi`, só validável de fato com hardware real). **Usuário escolheu a opção completa** (assinatura real).
- **Etapa 10.5 implementada** (ver detalhes na própria etapa, Fase 10): comando Rust `sign_ledger_transaction` (protocolo APDU `SIGN_TX`, reaproveitando o transporte HID das etapas 10.1-10.2) + `Connector` customizado da `wagmi` (`desktop/src/connectors/ledger.ts`, novo arquivo) que dá à Ledger o mesmo tratamento dos conectores prontos — passa a aparecer em `useAccount()`/`useWriteContract()` pro resto do app (`CreateIdentity`, `ManageDevices`, `ActiveSessions`, `DesktopDevice`) sem precisar saber que é uma Ledger. `ConnectLedger.tsx` manteve o polling com instruções (10.4), só que agora, ao achar o dispositivo, conecta de fato no estado global da wagmi em vez de só mostrar o endereço localmente.
- **Validação**: `cargo check` limpo; `npx tsc --noEmit` limpo (depois de resolver um caso de tipagem genérica da `wagmi` — ver nota na própria etapa 10.5); visual com Playwright contra o `vite` dev server (mesmo workaround de `cacheDir` por causa do `node_modules/.vite` root-owned). Confirmado: só 1 botão "Conectar Ledger" na tela (sem duplicata do connector genérico) e o fluxo de polling/cancelamento intacto. **Assinatura de verdade não testada** — exige hardware real, fica pra etapa 10.8 junto com a detecção/leitura de endereço das etapas anteriores.
- **Próximo passo ao retomar**: etapa 10.6 (multiplataforma: regra udev no Linux, entitlement USB/HID no macOS, conflito com Ledger Live no Windows) ou 10.7 (CI compilando a parte nativa do `hidapi` nos 3 SOs) — ordem livre entre as duas. Etapa 10.8 (validação com hardware real) só faz sentido depois, e a pendência #2 (teste E2E mobile↔desktop, aberta desde a Sessão 33) continua não resolvida, sem prioridade definida entre as duas.

### 2026-06-23 — Sessão 34

- **Contexto**: retomada das pendências da Sessão 33. Usuário decidiu resolver a pendência #1 (caminho do Ledger) antes de validar o pareamento E2E (pendência #2, ainda em aberto).
- **Decisão tomada**: implementar suporte a Ledger via USB direto no desktop, em Rust (opção "b" das 3 que estavam na mesa) — sem documentar Ledger Live via WalletConnect como atalho. Motivo: WebHID/WebUSB não existem no WebKitGTK (confirmado na Sessão 33), então só dá pra fazer com um comando Tauri em Rust, mesmo padrão já usado por `get_or_create_device_key`/`sign_challenge`.
- **Planejamento**: nova **Fase 10 — Ledger via USB direto (Desktop, Rust)** criada no documento (objetivo, fluxo de UX, arquitetura validada — `hidapi` + protocolo APDU para o app Ethereum —, pontos de atenção multiplataforma, 8 etapas). Tabela de "Decisões de Arquitetura em Aberto" atualizada.
- **Etapas 10.1 e 10.2 implementadas** (ver detalhes nas próprias etapas, Fase 10): módulo `desktop/src-tauri/src/ledger.rs` criado com `is_ledger_connected` (detecção via enumeração HID) e o transporte HID completo (`open_ledger_device`, `write_apdu`, `read_apdu_response`, `check_status`) — ainda não ligado a nenhum comando exposto pro frontend (isso é a 10.3).
- **Incidente de disco evitado por pouco**: ao adicionar `libudev-dev` na mesma linha `RUN apt-get install` que já existia no `Dockerfile` do desktop, isso invalidou o cache de uma camada cara e posterior (instalação de Rust + `cargo install tauri-cli`), disparando um rebuild pesado não-intencional. Disco caiu de 6.9GB pra 3.4GB livres rapidamente — build abortado a tempo (`kill` no processo). Um `docker container prune -f && docker image prune -f` (sem `--volumes`) recuperou 7GB, mas como efeito colateral apagou as camadas de cache do build (imagens "dangling" que eram, na prática, o cache do Rust/tauri-cli) — então o rebuild subsequente, já com o `Dockerfile` corrigido (nova camada separada, depois da instalação cara, só com `libudev-dev`+`pkg-config`), teve que refazer aquela parte cara do zero de qualquer forma (~15min). Disco monitorado de perto durante esse rebuild (chegou a 1.8GB livres, nunca cruzou a linha de 1GB de segurança, recuperou pra 2.7GB ao terminar). **Lição de ambiente pra próximas mudanças no `Dockerfile` do desktop**: adicionar dependências de sistema numa camada nova *depois* das etapas caras (Rust/tauri-cli), nunca editando a `RUN apt-get install` original — e não usar `docker image prune` sem necessidade enquanto um build alheio ainda pode precisar do cache.
- **Etapa 10.3 implementada** (ver detalhes na própria etapa, Fase 10): comando `get_ledger_address` (GET_ADDRESS do app Ethereum, caminho `m/44'/60'/0'/0/0`, modo silencioso pro polling) + classificação de erro em 3 rótulos (`not_connected`/`locked`/`wrong_app`). `cargo check` limpo, sem avisos.
- **Refinamento de estilo de explicação de código (ver [[user-truthid-profile]])**: usuário perguntou diretamente se valia entender o código Rust/hidapi sintaticamente ou só "mais ou menos" — confirmado que, pra esse tipo de código (protocolo/transporte, baixo risco), prefere explicações por blocos em linguagem simples, não linha por linha, daqui pra frente.
- **Etapa 10.4 implementada** (ver detalhes na própria etapa, Fase 10): botão "Conectar Ledger" + polling + mensagens de instrução, validado por `tsc` e visualmente via Playwright (estado "parado" e "procurando" — o estado de sucesso depende de hardware real).
- **Próximo passo ao retomar**: etapa 10.5 — integração com o fluxo de wallet existente (paridade com os outros conectores: o que acontece depois de achar o endereço da Ledger — hoje só mostra o endereço, não conecta de fato pro resto do app usar em transações). Validação contra uma Ledger física de verdade (etapa 10.8) ainda não foi feita — nenhuma das etapas 10.1-10.4 foi testada com hardware real ainda.

### 2026-06-22/23 — Sessão 33 (continuação — testando os apps de verdade, pós-Fase 9)

- **Contexto**: depois de fechar a Fase 9, o usuário pediu pra rodar os dois apps de verdade (não só os prints já tirados) pra interagir pessoalmente — primeiro só visualização, depois testes reais de conexão de wallet.
- **Incidente de disco resolvido**: durante o primeiro build do ambiente Tauri (`desktop/Dockerfile` — Rust + `cargo install tauri-cli`, do zero, nunca buildado nesta máquina), o usuário fechou a janela sem querer e a partição `/` (raiz, 46G) ficou 100% cheia, travando o sistema. Investigação: o Docker desse host tem `data-root` relocado para `/home/masterlxz/.docker/storage` (86G livres) via `/etc/docker/daemon.json`, mas o **containerd do sistema** (que guarda as camadas de verdade das imagens, conectado via `--containerd=/run/containerd/containerd.sock`) continua usando o caminho padrão `/var/lib/containerd`, na partição raiz — não foi migrado junto. Resolvido removendo containers parados + imagens "dangling" (3 imagens órfãs de builds falhos/superados, ~11GB) via `docker container prune`/`docker image prune` — confirmado antes de apagar que nenhuma tinha conteúdo realmente em uso (`lsof`/`stat`/`daemon.json`). Nenhum volume foi tocado (`emu_avd`, `emu_sdk_extra`, `mobile_gradle_cache`, `desktop_cargo-*` preservados). Disco: 0 → 12GB livres.
  - **Nota de ambiente pra próxima sessão**: esse desalinhamento entre `docker info` (data-root relocado) e o `containerd` do sistema (ainda no padrão) é estrutural, não foi corrigido — só o sintoma (disco cheio) foi. Se builds pesados (Rust/Android) acontecerem de novo, o mesmo risco existe. Correção definitiva exigiria configurar `root` em `/etc/containerd/config.toml` pra apontar pro mesmo lugar relocado, ou builds vão sempre consumir a partição raiz.
- **Mobile validado interativamente**: emulador remontado (mesmo processo da etapa 9.8) com janela visível na tela do usuário via X11 (`-v /tmp/.X11-unix:/tmp/.X11-unix -e DISPLAY=:1`, sem `-no-window`) — precisou adicionar `libpulse0` e libs gráficas (`libgl1`, `libgtk-3-0`, etc.) na imagem temporária do emulador, que faltavam e causavam `error while loading shared libraries: libpulse.so.0`. App instalado e aberto, usuário viu as telas de verdade.
- **Desktop validado interativamente**: `./dev.sh`/`docker compose up` com X11 passthrough (`xhost +local:docker`) — primeira vez rodando esse ambiente nesta máquina, build do zero (apt + Rust + `cargo install tauri-cli`, ~3 tentativas: 1ª travou no disco cheio, 2ª teve um timeout de rede transiente no `cargo install`, 3ª completou). Janela `tauri-app` confirmada na tela via `wmctrl -l`. Avisos de `MESA`/`libGL`/`iris` (fallback pra software rendering) não impediram o app de abrir.
- **Achado real (não só do ambiente de teste)**: clicar em "Conectar com Injected" não fazia nada — confirmado que **não é bug do Docker/X11**, é arquitetural: o Tauri usa WebKitGTK como motor de webview no Linux, que não suporta extensões de navegador (MetaMask, Rabby) de forma alguma, em nenhum ambiente (Docker ou instalação nativa). `desktop/src/config/wagmi.ts` só tinha o conector `injected()` configurado — Ledger/Trezor/WalletConnect, listados desde a Fase 3 como objetivo, nunca foram implementados de fato.
  - **Corrigido nesta sessão**: conector `walletConnect` adicionado (Project ID público do Reown Cloud, fornecido pelo usuário). Precisou instalar `@walletconnect/ethereum-provider@^2.21.1` com `--legacy-peer-deps` (mesmo conflito de TypeScript 5.8 vs 5.9+ já documentado em sessões anteriores pro `wagmi`). Validado com `tsc --noEmit` e testado ao vivo — o modal de QR code do WalletConnect abriu corretamente no app empacotado.
  - **Pendência levantada, não resolvida**: usuário quis testar conectar uma wallet física (Ledger) e pediu um botão dedicado de conexão USB direta (sem precisar do celular/WalletConnect). Teste empírico feito ao vivo no app real (diagnóstico temporário em `App.tsx`, removido depois): `navigator.hid` e `navigator.usb` são **ambos `false`** nesse WebKitGTK — **WebHID e WebUSB não estão disponíveis nesse motor de webview**, confirmando que um conector Ledger via JS do navegador é inviável aqui (diferente de Chrome/Edge, onde isso é comum). Caminho alternativo identificado mas não implementado: comunicação USB com o Ledger feita no lado **Rust** do Tauri (crate `hidapi` + protocolo APDU do app Ethereum do Ledger), exposta via comando Tauri (`invoke`) — mesmo padrão já usado pelo app pra falar com o keyring do SO (`get_or_create_device_key`/`sign_challenge`). É trabalho real (não um conector pronto, precisa implementar o protocolo), não decidido ainda se vale a pena vs. usar o Ledger Live via WalletConnect (zero código novo, já funciona com o que foi feito hoje).
- **Limpeza final da sessão**: container do emulador e a imagem temporária `truthid-emulator` removidos; `docker compose down` no desktop (mas a imagem `desktop-desktop:latest` e os caches `desktop_cargo-*` ficaram, agora populados — ~4.6GB de cache Rust — pra acelerar o próximo `./dev.sh`). Disco final: 6.9GB livres na raiz.
- Conceitos ensinados: diferença entre o "Docker Root Dir" (metadados/volumes do Docker) e o root do containerd (camadas de imagem de verdade) — podem estar configurados em lugares diferentes no mesmo host; por que WebHID/WebUSB são specs recentes com suporte desigual entre motores de browser (Chromium tem, WebKit não); por que Tauri resolve esse tipo de limitação fazendo o trabalho sensível no lado Rust em vez de depender de APIs do navegador.

**PENDÊNCIAS PRA PRÓXIMA SESSÃO**:
1. **Decidir o caminho do Ledger**: (a) só documentar que dá pra usar Ledger Live como peer WalletConnect, sem código novo; (b) implementar o cliente Ledger em Rust (`hidapi` + APDU); (c) deixar de lado por agora. Usuário não decidiu ainda.
2. Validar o fluxo de pareamento real ponta-a-ponta (mobile mostra QR → desktop lê/cola endereço → registra on-chain) — chegamos a montar os dois apps reais lado a lado mas não completamos esse teste específico antes de parar por hoje.
3. (Opcional, baixo risco) Corrigir o desalinhamento `containerd` vs `data-root` do Docker neste host, pra builds pesados futuros não arriscarem enchar a partição raiz de novo.

### 2026-06-22 — Sessão 33 (continuação — Fase 9 completa)

- **Fase 9 concluída** (etapas 9.1 a 9.8) — identidade visual aplicada ao mobile (Flutter) e desktop (Tauri+React), reaproveitando a marca já aprovada no site (Fase 8): fundo `#0B0F14`, acento ciano `#4DD0E1`, Space Grotesk+Inter, logo escudo+check
  - **9.1**: fontes bundladas como assets locais no Flutter (não `google_fonts` via rede — um app de auth não devia depender de internet pra renderizar a UI)
  - **9.2/9.3**: `App.css` do desktop reescrito do zero (era o template padrão do `create-tauri-app`), tema aplicado nos 5 componentes + shell
  - **9.4/9.7**: variante preenchida do logo (escudo ciano sólido + check vazado, fundo navy) criada pra ícones de app — a linha fina não funciona em fundo arbitrário. Mesma imagem-fonte usada nos dois: `tauri icon` pro desktop, `flutter_launcher_icons` pro mobile
  - **9.5/9.6**: tema global do Flutter (`ThemeData` com `ColorScheme.dark` explícito) + todas as cores hardcoded das 5 telas (`Colors.grey/red/green/blue/amber` em vários shades) substituídas pelos tokens semânticos. **Bug de correção achado nessa etapa**: o QR code da tela de pareamento não tinha fundo explícito — no tema dark, ficaria ilegível pra câmera (módulos pretos sobre fundo quase preto). Corrigido com fundo branco explícito.
  - **9.8**: desktop validado via `vite` dev server real + Playwright (já feito na 9.3). Mobile validado num emulador Android real — os volumes Docker `emu_avd`/`emu_sdk_extra` de uma sessão anterior já tinham um AVD e a system image prontos, mas sem script de montagem; construída uma imagem temporária com o pacote `emulator` do Android SDK, descartada ao final. APK debug real instalado e testado: tela inicial, aba Sessões, e a tela de QR (confirmando visualmente o fix do fundo branco). Tela de aprovação de login não testada ao vivo (exigiria simular scan de câmera) — validada só por revisão de código + `flutter analyze`.
  - Achados de ambiente registrados: `./dev.sh` do mobile exige o comando completo (`./dev.sh flutter pub get`, não `./dev.sh pub get`; `./dev.sh dart run ...`, não `./dev.sh flutter dart run ...`); `node_modules/.vite` do desktop tinha cache root-owned de uma sessão Docker anterior, sem permissão de escrita — contornado com um `vite.config.ts` temporário apontando `cacheDir` pra `/tmp`.
- Conceitos ensinados: variable fonts no Flutter (um arquivo, múltiplos `weight:` no pubspec); por que um ícone de app precisa de uma versão preenchida/alto-contraste separada do logo de linha fina usado dentro da UI; como montar um emulador Android a partir de volumes Docker já populados (sem precisar rebaixar a system image); por que testar com o app de verdade pegou um bug (QR ilegível) que nem a leitura cuidadosa do código nem o `flutter analyze` teriam pego
- **Próximo passo ao retomar**: nenhuma fase nova definida ainda — decisão do usuário sobre prioridade seguinte

### 2026-06-22 — Sessão 33

- **Etapa 8.8 concluída** — página de segurança (modelo de ameaças)
  - Antes de escrever, investigação no código real (não só no que já estava documentado em README/SDKs) confirmou 5 pontos novos: origin do challenge é mostrado na tela de aprovação do mobile (proteção real contra phishing); mobile recusa `callbackUrl` não-https; os 3 SDKs confiam no RPC configurado pelo integrador sem prova client-side (risco de confiança real, nunca documentado); chave do device só existe via Keystore/Secure Enclave, sem fallback inseguro; sem guardians configurados, perda do controller é permanente (sem caminho alternativo)
  - Nova página `docs/docs/security.mdx` (sidebar_position 4): tabela "What TruthID protects against" (11 mecanismos reais), seção "does not protect against" com admonition `:::danger[...]` + 6 bullets honestos, "Audit status" linkando pra tabela de achados da Sessão 24 em `PROJECT_STATE.md` e pro GitHub Security tab
  - Corrigidas duas pontas soltas "coming soon" de sessões anteriores: `intro.mdx` ainda dizia que a referência de SDK "está chegando" (já existia desde 8.5-8.7) e `quickstart.mdx` tinha "Security model — coming soon" — ambos agora linkam pras páginas reais
  - Link "Security" adicionado ao footer (mesmo padrão da 8.4 com Quickstart)
  - `npm run build` sem erros; revisão visual via Playwright confirmou admonition vermelho, tabela legível no tema dark e link novo no footer
- Conceitos ensinados: por que vale a pena reler o código-fonte (não confiar só na documentação já escrita) antes de escrever uma página de "o que isso protege" — vários pontos do threat model real (origin no mobile, validação de https, ausência de prova de honestidade do RPC) não estavam registrados em nenhum lugar até essa sessão
- **Próximo passo ao retomar**: etapa 8.9 (página de contratos: endereços, ABIs, links Basescan, custo por operação), 8.10 (identidade visual definitiva) ou 8.11 (deploy — já automático)

### 2026-06-22 — Sessão 33 (continuação — etapa 8.9)

- **Etapa 8.9 concluída** — página de contratos
  - Nova página `docs/docs/contracts.mdx` (sidebar_position 5): endereços mainnet+testnet com links Basescan, seção "Getting the ABI" (Basescan verificado + `forge build` local, já que `out/` é gitignored e não existe pacote com ABI completo), "Contract reference" (tabela função/caller/propósito por contrato, lida direto de `contracts/src/*.sol`), "Cost per operation" (gas real via `forge test --gas-report`) e "Audit status" linkando pra página de segurança
  - Achado: `forge test --gas-report` já dava números de gas reais a partir dos 120 testes existentes — não foi preciso estimar nada. Conversão pra ETH só como nota textual (gas price ~0,011 gwei do deploy de mainnet), com aviso de que o preço flutua, linkando pro gas tracker ao vivo da Basescan
  - Cross-links adicionados em `intro.mdx`, `security.mdx` e no footer
  - `npm run build` sem erros; revisão visual via Playwright confirmou tabelas e admonition `:::info[...]`
- Conceitos ensinados: como ler um gas report do Foundry (`forge test --gas-report`) e por que esses números são mais confiáveis que estimar — vêm de execução real dos testes, não de cálculo manual
- **Próximo passo ao retomar**: etapa 8.10 (identidade visual definitiva) ou 8.11 (deploy — já automático, falta só marcar)

### 2026-06-22 — Sessão 33 (continuação — etapa 8.10)

- **Etapa 8.10 concluída** — identidade visual definitiva
  - Usuário decidiu manter cores/tipografia da 8.2 sem revisitar, escopo só no logo
  - 3 evoluções do escudo+check desenhadas em SVG e comparadas visualmente (grande/navbar/favicon) via Playwright antes de qualquer decisão — usuário escolheu manter o design atual exatamente como está, só remover o status "provisório"
  - Achado fora do pedido original: o card social (`og:image`/`twitter:image`) ainda era o dinossauro padrão do Docusaurus, nunca substituído — usuário confirmou que valia corrigir. Card novo criado (fundo dark com glow do hero, logo, "TruthID" em Space Grotesk, tagline do `docusaurus.config.ts`), renderizado em 1200x630 via Playwright, arquivo renomeado pra `social-card.jpg` (`git mv`) sem branding do template no nome
  - `npm run build` sem erros; `og:image`/`twitter:image` confirmados via grep no HTML apontando pra URL absoluta correta
- Conceitos ensinados: por que vale a pena renderizar e comparar variações visuais reais (não só descrever em texto) antes de pedir uma decisão estética — e por que o card social é parte da identidade visual mesmo não aparecendo no site em si (só no preview de link em redes sociais)
- **Próximo passo ao retomar**: etapa 8.11 (deploy — já automático desde a 8.1, falta só marcar como concluído e fechar a Fase 8)

### 2026-06-22 — Sessão 33 (continuação — correção do social-card.jpg + etapa 8.11)

- **Bug pego e corrigido**: o commit da etapa 8.10 renomeou `docusaurus-social-card.jpg` → `social-card.jpg` mas o conteúdo novo (card de marca própria) nunca foi commitado de fato — um `git add` com um pathspec inválido (caminho antigo, já renomeado) abortou o add inteiro silenciosamente, e o `git commit` seguinte só capturou o que já estava staged do `git mv` (a imagem antiga, só com nome trocado). `PROJECT_STATE.md` e `docusaurus.config.ts` também ficaram de fora pelo mesmo motivo. Detectado ao extrair o blob do HEAD (`git show HEAD:caminho`) e comparar com o arquivo no working tree — tamanhos e dimensões diferentes (55746 bytes/1200x675 no HEAD vs. 34287 bytes/1200x630 no disco). Corrigido com um novo commit (`d144a26`), sem reescrever o que já tinha sido enviado.
- **Etapa 8.11 concluída** — deploy em produção, fechando a Fase 8 inteira
  - Já era automático desde a 8.1; fechamento foi confirmar que continua funcionando depois de todo o trabalho da Fase 8
  - Run do GitHub Actions do último push confirmada `success` via API pública (sem autenticação)
  - Site em produção verificado via `curl`: home, `/docs/security`, `/docs/contracts` (200), card social novo (200, conteúdo correto) com `og:image` apontando certo
- **Fase 8 — Documentação Web: CONCLUÍDA** (etapas 8.1 a 8.11)
- Conceitos ensinados: por que `git add` com um pathspec que não casa com nenhum arquivo pode abortar o comando inteiro silenciosamente (especialmente perigoso com `2>/dev/null`) — sempre vale checar `git diff --staged --stat` antes de comitar, não só `git status --short`
- **Próximo passo ao retomar**: Fase 8 fechada. Não há próxima fase definida no roadmap ainda — decisão do usuário sobre o que vem depois (ex: app mobile/desktop com identidade visual própria, conforme "Roadmap de Evoluções Planejadas → Interface e identidade visual", ou outra prioridade)

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

### 2026-07-01 — Sessão 56

- **Objetivo**: Fase 14, etapa 14.4 — implementar `TruthIDAccountFactory.sol` com CREATE2 determinístico.

**Contexto**: a factory é o elo que permite o desktop pré-computar o endereço da smart account ANTES de ela existir, resolvendo o problema "ovo-e-galinha" da Fase 14 (`IdentityRegistry.createIdentity` exige um `controller`, mas a conta só é deployada depois).

**Decisões de design confirmadas com o usuário**:
- **Salt**: `keccak256(abi.encodePacked(owner_))` (endereço Ledger). Padrão do SimpleAccount (eth-infinitism); basta saber o endereço Ledger para prever a conta.
- **Idempotência**: `createAccount(owner_)` retorna silenciosamente a conta existente se já deployada, em vez de reverter. Isso evita que o desktop precise fazer `extcodesize` off-chain antes de chamar a factory.
- **EntryPoint v0.7**: endereço oficial `0x0000000071727De22E5E9d8BAf0edAc6f37da032` hardcoded no `Deploy.s.sol`, pois foi deployado via CREATE2 com salt zero e é idêntico em todas as EVM chains.

**Arquivos criados/modificados**:
- `contracts/src/TruthIDAccountFactory.sol` (novo): factory com `createAccount`, `getAddress`, evento `AccountCreated`, reverts de endereço zero no constructor e sanity check `assert(address(ret) == predicted)` após o CREATE2.
- `contracts/test/TruthIDAccountFactory.t.sol` (novo): 10 testes cobrindo CREATE2 determinístico, idempotência, parâmetros da conta, isolamento entre owners, validação de constructor e dinâmica "ovo-e-galinha" com `IdentityRegistry`.
- `contracts/script/Deploy.s.sol` (modificado): adicionada constante `ENTRY_POINT_V07` e deploy da factory ao final do script.

**Detalhes técnicos relevantes**:
- A factory conhece os 4 endereços compartilhados (`entryPoint`, `deviceRegistry`, `identityRegistry`, `recoveryManager`) via `immutable` no próprio constructor; cada `TruthIDAccount` criada recebe esses mesmos endereços + `owner_`.
- A verificação de existência usa `extcodesize` em assembly puro; se maior que zero, a conta já existe e é retornada sem novo deploy.
- O teste de integração valida o fluxo completo da Fase 14: (1) `factory.getAddress(owner)` prevê endereço; (2) `identityRegistry.createIdentity("masterlxz.id", predictedAccount)` como EOA; (3) `factory.createAccount(owner)` deploya e bate com o endereço previsto; (4) `identityRegistry.getIdentity(...)` confirma que o controller registrado é o endereço da conta.

**Verificação**:
- `forge build`: sucesso.
- `forge test`: 147 testes passando (137 anteriores + 10 novos).
- `forge fmt`: aplicado somente aos arquivos novos/alterados (`src/TruthIDAccountFactory.sol`, `test/TruthIDAccountFactory.t.sol`, `script/Deploy.s.sol`) para evitar ruído no diff de arquivos antigos do codebase.

**Débitos técnicos**: nenhum novo aberto. Os débitos #17 (`createIdentity` sem validação de autorização sobre `controller`) e #19 (`RecoveryManager` não chama `emergencyWithdraw`) continuam pendentes e devem ser decididos antes de qualquer deploy em mainnet.

**Próximo passo**: 14.5 — expandir testes gerais da `TruthIDAccount` e da factory; ou 14.6 — utilitário off-chain `computeSmartAccountAddress`.

---

### 2026-07-02 — Sessão 59

- **Objetivo**: Fase 14, etapa 14.6 — utilitário off-chain `computeSmartAccountAddress`.

**O que foi feito**:

Três arquivos novos + um arquivo modificado:

- **`desktop/src/config/truthidAccount.ts`** (novo): constantes `TRUTHID_ACCOUNT_CREATION_CODE` (bytecode de criação do `TruthIDAccount.sol`, 9.185 bytes extraídos do artefato forge `contracts/out/TruthIDAccount.sol/TruthIDAccount.json` → campo `bytecode.object`), `TRUTHID_ACCOUNT_FACTORY_ADDRESS` (placeholder `0x0` — será preenchido após deploy da factory em 14.11), e `ENTRY_POINT_V07` (`0x0000000071727De22E5E9d8BAf0edAc6f37da032` — endereço oficial CREATE2-salt-zero do ERC-4337, idêntico em todas as chains EVM).

- **`desktop/src/utils/computeSmartAccountAddress.ts`** (novo): função principal que replica a matemática do `TruthIDAccountFactory.getAddress()` em TypeScript/viem. Dois modos: (1) **async com publicClient** — lê os 4 immutables da factory via `multicall` (4 `eth_call` em uma única request, sem gas); (2) **sync com valores explícitos** (`computeSmartAccountAddressSync`) — recebe `entryPoint`/`deviceRegistry`/`identityRegistry`/`recoveryManager` direto, útil para uso offline ou pré-deploy da factory. Algoritmo: `salt = keccak256(ledgerAddress)` (equivale a `abi.encodePacked(address)` do Solidity) → `constructorArgs = encodeAbiParameters(address×5)` → `initCode = concat(creationCode, constructorArgs)` → `initCodeHash = keccak256(initCode)` → `address = slice(keccak256(concat(0xFF, factory, salt, initCodeHash)), 12)` com checksum EIP-55 via `getAddress()`.

- **`desktop/src/utils/__tests__/computeSmartAccountAddress.test.ts`** (novo): 12 testes cobrindo: endereço válido não-zero, determinismo, diferenciação por owner/factory/immutable, checksum EIP-55, formato do salt e do creationCode, reprodutibilidade em 10 chamadas consecutivas. Usa `makeAddr()` (replicação do helper do Foundry em TypeScript via `keccak256(toBytes(label))`) para endereços determinísticos.

**Verificação**: `npx tsc --noEmit` limpo; `npx vitest run` → 21/21 passando (12 novos + 9 existentes do PairDevice).

**Decisão de design**: implementação em TypeScript (viem), não em Rust. Motivo: a função é puramente matemática (sem segredos, sem hardware), e o viem já tem todas as primitivas necessárias (`keccak256`, `encodeAbiParameters`, `concat`, `slice`, `getAddress`) — zero dependências novas. Rust exigiria adicionar `ethers-core` ou `alloy-sol-types` para ABI encoding.

- **Resultado**: 14.6 concluída.
- **Próximo passo**: 14.7 — Desktop: atualizar fluxo de criação de identidade para usar smart account.

---

### 2026-07-02 — Sessão 60

- **Objetivo**: Fase 14, etapa 14.7 — atualizar fluxo de criação de identidade no Desktop para usar smart account (CREATE2) + deployar a factory na Base Sepolia e Base Mainnet.

**O que foi feito**:

**Bloco A — Deploy da factory:**

- **`contracts/script/DeployFactory.s.sol`** (novo): script que deploya apenas o `TruthIDAccountFactory`, recebendo os endereços dos contratos existentes via variáveis de ambiente (`DEVICE_REGISTRY`, `IDENTITY_REGISTRY`, `RECOVERY_MANAGER`). Não redeploya os contratos que já estão na chain.
- **Base Sepolia** (chain 84532): factory deployada em `0xbf097EC74d0Cc9b16D3d94EaCa62060d89A63b17`. ETH obtido via Google faucet (Sepolia L1) + bridge `depositETH` direto no `L1StandardBridge` (`0xfd0Bf71F60660E2f608ed56e1659C450eB113120`) via `cast send --ledger`.
- **Base Mainnet** (chain 8453): factory deployada em `0x062c577C26067d04bBEEaa953F8E7675fF4849ab` via Ledger conta 1 (`m/44'/60'/1'/0/0`).

**Bloco B — Desktop: fluxo de criação de identidade:**

- **`desktop/src/config/truthidAccount.ts`** (modificado): `TRUTHID_ACCOUNT_FACTORY_ADDRESS` atualizado com o endereço da mainnet. `FACTORY_IMMUTABLES` adicionado com entryPoint/deviceRegistry/identityRegistry/recoveryManager (mainnet). Endereços da Sepolia documentados em comentário para devs.
- **`desktop/src/config/contracts.ts`** (modificado): ABI da `TruthIDAccountFactory` adicionada (`createAccount`, `getAddress`). Re-exporta `FACTORY_ADDRESS` do `truthidAccount.ts`.
- **`desktop/src/components/CreateIdentity.tsx`** (reescrito): fluxo de 3 transações sequenciais com barra de progresso visual (✓/●/○ por etapa). Tx 1: `createIdentity(username, smartAccountAddress)`. Tx 2: `factory.createAccount(ledgerAddress)`. Tx 3: `sendTransaction({ to: smartAccountAddress, value })`. Input de funding inicial (default 0.001 ETH). As 3 txs auto-encadeiam via `useEffect` observando `isSuccess` de cada uma. Mensagem explicativa: "Your Ledger pays gas one time only."
- **`desktop/src/App.tsx`** (modificado): `smartAccountAddress` pré-computado via `useMemo` usando `computeSmartAccountAddressSync()` + `FACTORY_IMMUTABLES`. `getUsernameByController` consulta pelo `smartAccountAddress` (não mais pelo EOA da Ledger). `CreateIdentity` recebe `smartAccountAddress` como prop.

**Verificação**: `forge build` + `forge test` (191) limpos. `npx tsc --noEmit` limpo. `npm test` → 21/21 passando.

- **Resultado**: 14.7 concluída.
- **Próximo passo**: 14.8 — Desktop + Mobile: sincronizar lista de signers da smart account com o DeviceRegistry (addDevice/removeDevice).

---

### 2026-07-02 — Sessão 61

- **Objetivo**: usuário pediu pendências rápidas. Escolhida a limpeza dos débitos técnicos #21–#26 (nits de gas/estilo da `TruthIDAccountFactory`, apontados no `/code-review` da Sessão 57) seguida de redeploy, já que nenhum bloqueava correção — eram só gas/consistência.

**Antes de mexer no código**: confirmado via `cast logs`/`eth_getLogs` na Base Mainnet que a factory deployada na Sessão 60 (`0x062c577C...`) nunca teve um evento `AccountCreated` emitido — zero contas reais criadas. Isso liberou o redeploy sem risco de quebrar identidades já existentes (o endereço da smart account de cada usuário depende do endereço da factory via CREATE2).

**Mudanças em `contracts/`**:
- **`src/ERC4337Constants.sol`** (novo): free constant `ENTRY_POINT_V07`, compartilhada agora por `Deploy.s.sol`, `DeployFactory.s.sol` e `TruthIDAccountFactory.t.sol` — antes hardcoded independentemente em cada um (débito #23).
- **`src/TruthIDAccountFactory.sol`**: adicionado `mapping(address => address) public accounts` — `createAccount`/`getAddress` checam o mapping antes de recalcular o `initCodeHash` (que copia o creation code inteiro da `TruthIDAccount`), eliminando o recálculo redundante no caminho idempotente e a dupla computação do salt (débito #21). Isso também eliminou o uso de `extcodesize` via assembly na produção (débito #22 — resolvido de forma mais completa do que o fix sugerido). Os 4 erros de validação do constructor (`InvalidEntryPoint`/`InvalidDeviceRegistry`/`InvalidIdentityRegistry`/`InvalidRecoveryManager`) foram unificados em `InvalidConstructorArgs`, no mesmo padrão do `TruthIDAccount.sol` (débito #24).
- **`test/TruthIDAccountFactory.t.sol`**: os 2 usos de assembly `extcodesize` trocados por `.code.length` (débito #22); helper `_predictAndCreate` agora usado nos 3 testes aplicáveis em vez de só 1 (débito #26); os 4 testes de revert do constructor atualizados para esperar `InvalidConstructorArgs`.
- **Débito #25 (uma conta por owner) deliberadamente não tocado** — é decisão de design (breaking change de formato), não nit de limpeza; continua registrado como pendente.
- **Resultado**: `forge build`/`forge test` (191 testes) limpos; `forge fmt` aplicado só nos arquivos tocados (resto do repo já tinha drift de formatação pré-existente, não mexido).

**Redeploy** (Ledger conta secundária, `m/44'/60'/1'/0/0` → `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265`, mesmo endereço do deployer original do projeto):
- Base Sepolia: nova factory em `0x4A7a307cb6872bde24BAf3E9de2BeC3Ddd03e144`.
- Base Mainnet: nova factory em `0xe8aC0654515e11176CDBCD9D01521bEAbB7c545e`.
- **`desktop/src/config/truthidAccount.ts`** atualizado com os dois endereços novos (constante + comentário do Sepolia). `tsc --noEmit` e os 21 testes do desktop continuam limpos (o `TRUTHID_ACCOUNT_CREATION_CODE` da `TruthIDAccount` não mudou — só a factory foi redeployada — então o hash do init code é o mesmo; muda apenas o endereço do deployer usado na fórmula CREATE2).

**Descoberta lateral (não é bug)**: durante a verificação, notei que `0xbf097EC74d0Cc9b16D3d94EaCa62060d89A63b17` aparece tanto como `IdentityRegistry` na Base Mainnet quanto (antes deste redeploy) como a antiga `TruthIDAccountFactory` na Base Sepolia — confirmado via `cast call` que são contratos diferentes em chains diferentes que coincidentemente calharam no mesmo endereço (nonce do deployer bateu nas duas chains independentes). Não afeta nada, só registrado para não confundir uma sessão futura.

- **Resultado**: débitos #21, #22, #23, #24 e #26 resolvidos e verificados; #25 permanece aberto (decisão pendente). Factory redeployada e funcional nas duas redes.
- **Próximo passo**: 14.8 — Desktop + Mobile: sincronizar lista de signers da smart account com o DeviceRegistry (addDevice/removeDevice).

---

### 2026-07-03 — Sessão 62

- **Objetivo**: resolver o débito #17 — opção (a) escolhida pelo dono do projeto (assinatura de consentimento em `createIdentity`).

**Desenho da consentimento**: `createIdentity(username, controller, v, r, s)` agora aceita duas formas de prova de consentimento:
1. `controller` é EOA comum → ele mesmo assina (`signer == controller`).
2. `controller` é smart account pré-deploy (caso real da Fase 14) → quem assina é o dono da chave Ledger que vai virar owner dela; o registry verifica via `ITruthIDAccountFactory(_factory).getAddress(signer) == controller`.

Mensagem assinada: `keccak256(abi.encode(chainid, address(registry), username, controller))`, com o prefixo manual `"\x19Ethereum Signed Message:\n32"` por cima — mesma convenção já usada em `TruthIDAccount`/`SessionRegistry` (hash cru + ecrecover, sem EIP-712, sem OpenZeppelin).

**Mudanças em `contracts/src/IdentityRegistry.sol`**: novo campo `_factory` (mutável, não one-shot — diferente do `_recoveryManager` — porque a factory já foi redeployada 2x no histórico por motivos de gas/limpeza), `setFactory(address)` só-owner, interface mínima `ITruthIDAccountFactory` a nível de arquivo, erro `InvalidConsentSignature`, evento `FactorySet`.

**Testes**: novo helper compartilhado `contracts/test/IdentityConsentHelper.sol` (usado por 6 arquivos de teste que chamavam `createIdentity` — todos precisaram trocar atores de `makeAddr` pra `makeAddrAndKey`). `IdentityRegistry.t.sol` ganhou casos novos: EOA direto, smart account via factory real (`TruthIDAccountFactory` de verdade, não mock), assinatura de terceiro, `v` inválido, replay entre pares diferentes, factory não configurada (fail-closed), `setFactory` access control e não-one-shot. **201 testes Foundry passando.**

**Descoberta que expandiu o escopo — Ledger não assina mensagens hoje**: `desktop/src/connectors/ledger.ts` tinha `signMessage`/`signTypedData` explicitamente `unsupported(...)` — só existia assinatura de transação. Implementado do zero: `sign_ledger_personal_message` em `desktop/src-tauri/src/ledger.rs` (APDU `INS=0x08`, `SIGN_PERSONAL_MESSAGE`, mesmo esquema de chunking de `sign_ledger_transaction`), registrado em `lib.rs`, e wireado em `ledger.ts` via um case novo `personal_sign` dentro do `request()` do provider (não via o `toAccount()` interno, que é escopo só do `eth_sendTransaction`). `cargo check` rodado dentro do container Docker do desktop (`docker compose run --rm desktop sh -c "cd src-tauri && cargo check"`) — o host Arch Linux não tem as libs WebKitGTK, só o container tem (ver `env_setup` na memória).

**Desktop — novo passo no fluxo de criação de identidade**: `desktop/src/utils/buildIdentityConsentHash.ts` (espelha o hash on-chain, usa `encodeAbiParameters`, testado em `__tests__/buildIdentityConsentHash.test.ts`). `CreateIdentity.tsx` ganhou um passo 1 novo ("Signing consent") antes das 3 transações existentes (agora 4 passos no total), usando `useSignMessage()` do wagmi com `message: { raw: hash }` — funciona com qualquer conector (Ledger, WalletConnect, injected) sem código condicional na UI. `IDENTITY_REGISTRY_ABI` em `contracts.ts` atualizado com os 3 parâmetros novos (`v`, `r`, `s`). `tsc --noEmit` e `vitest` (28/28) limpos.

**Scripts de deploy atualizados**: `Deploy.s.sol` e `DeployFactory.s.sol` chamam `identityRegistry.setFactory(...)` no ponto certo. `DeploySessionRegistry.s.sol` deixou de ter os endereços do `IdentityRegistry`/`DeviceRegistry` hardcoded (mesmo padrão de bug que o débito #23 já tinha corrigido em outro lugar) — agora usa `vm.envAddress`, igual ao `DeployFactory.s.sol`.

**Achado que bloqueia o redeploy — 1 identidade real já existe na mainnet**: `totalIdentities()` no `IdentityRegistry` atual (`0xbf097EC7...`) retorna `1` (confirmado via `cast call` read-only). Como a assinatura de `createIdentity` mudou (breaking change), o registry precisa ser redeployado — e como `DeviceRegistry`, `RecoveryManager`, `SessionRegistry` e `TruthIDAccountFactory` recebem o endereço do `IdentityRegistry` como `immutable` no construtor, **os 5 contratos precisam ser redeployados juntos** nas duas redes (`VaultRegistry` fica de fora — ainda não foi deployado, endereço é placeholder `0x0`). Decisão do dono do projeto: **aceitar a perda dessa identidade e recriá-la manualmente depois do redeploy** (sem script de migração).

**PENDENTE — próxima sessão, com o Ledger físico em mãos**:
1. Redeploy dos 5 contratos em Base Sepolia primeiro (`forge script script/Deploy.s.sol --rpc-url base_sepolia --broadcast --ledger --hd-paths "m/44'/60'/1'/0/0"`, depois `DeploySessionRegistry.s.sol` com `IDENTITY_REGISTRY`/`DEVICE_REGISTRY` como env vars).
2. Testar o fluxo completo de criação de identidade no app contra Sepolia (passo de assinatura + 3 transações).
3. Repetir em Base Mainnet.
4. Atualizar `desktop/src/config/contracts.ts` e `truthidAccount.ts` com os 5 endereços novos (Sepolia + Mainnet).
5. Recriar manualmente a identidade mainnet perdida.
6. Marcar débito #17 como resolvido na tabela de Débitos Técnicos e fechar esta entrada do Log de Sessões.

---

**Continuação (mesmo dia, Ledger em mãos) — Sepolia deployado e testado**:

Flag `--hd-paths` do `forge script` não existe — o nome certo é `--mnemonic-derivation-paths` (plural). `cast wallet address --ledger --mnemonic-derivation-path "m/44'/60'/1'/0/0"` confirmou o dispositivo antes de qualquer broadcast: `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265`, mesmo deployer das Sessões 60/61.

**Base Sepolia — 5 contratos redeployados** (via RPC público `https://sepolia.base.org`, sem precisar de `.env`/API key):
- `IdentityRegistry`: `0x01df431F6a2276aE3220dc6f3874454caA5F20f8`
- `DeviceRegistry`: `0x5F92f95ABaACC85ADAde04F072d30b67eD8c896e`
- `RecoveryManager`: `0x062c577C26067d04bBEEaa953F8E7675fF4849ab`
- `TruthIDAccountFactory`: `0x056b826e8E31F1dCD95886571e92CA206cFB6337`
- `SessionRegistry`: `0x925a0bCE2EA3AcF25454354197565B799E786e97`

**Teste end-to-end no app real** (desktop apontado temporariamente pra Sepolia — 4 arquivos editados e depois revertidos: `wagmi.ts`, `contracts.ts`, `truthidAccount.ts`, `App.tsx`. **Achado extra**: `App.tsx` importa `base` de `wagmi/chains` **separado** do `wagmi.ts` — trocar só o `wagmi.ts` não bastava, o app mostrava "Switch to Base Mainnet" preso porque a checagem de rede errada estava em `App.tsx`; precisou trocar os dois): identidade `teste.id` criada com sucesso, incluindo o passo novo de assinatura de consentimento na Ledger (`personal_sign` via APDU `INS=0x08` funcionando de ponta a ponta), smart account deployada com sucesso.

**Bug real encontrado — funding revertia por falta de gas**: a 4ª transação (enviar 0.001 ETH pra smart account recém-deployada) minerou com `status: 0 (failed)`, `gasLimit: 21000` — o padrão de uma transferência EOA→EOA simples. Mandar ETH pra um **contrato** custa mais que isso mesmo com `receive()` vazio (medido via `cast estimate`: ~21220 gas real). Rastreei o código do wagmi/viem a fundo e não achei nenhum default hardcoded de 21000 — a hipótese mais provável é uma corrida contra o RPC público: a estimativa de gas rodou pouco depois do deploy da smart account (tx anterior), e o node que respondeu ao `eth_estimateGas` ainda não via o bytecode novo, tratando o destino como EOA. **Corrigido** em `desktop/src/components/CreateIdentity.tsx`: `fundAccount` agora passa `gas: 30_000n` explícito (margem generosa sobre os ~21220 medidos), evitando depender da estimativa automática nessa janela de corrida. `tsc`/`vitest` (28/28) continuam limpos. A tx de funding do teste foi completada manualmente via `cast send --gas-limit 30000 --ledger` pra fechar a verificação (identidade + smart account + funding, os 3 confirmados on-chain).

Config do desktop revertida de volta pra mainnet (4 arquivos, backups tinham sido feitos antes de editar). Container Docker do teste parado (`docker compose down`).

**Deploy em Base Mainnet — continuação, mesmo dia, dono do projeto decidiu seguir na hora**:

**Base Mainnet — 5 contratos redeployados** (mesmo Ledger, `m/44'/60'/1'/0/0`, via RPC público `https://mainnet.base.org`):
- `IdentityRegistry`: `0xDe7a0f1918Ee39cc1792e709Edde17e8ea858998`
- `DeviceRegistry`: `0x2be6a81B22823510c7F3Fa93E70B85aAd4fB488d`
- `RecoveryManager`: `0xbBe777145D32fdbf8A5878eAa3a21b5f1A7d67F7`
- `TruthIDAccountFactory`: `0x859c297342db9baa4531aC959578063646131668`
- `SessionRegistry`: `0xbf8b940dDC3754D06ee5281209Bd3dD58852BF65`

Custo real: ~0.00013 ETH nas duas redes combinadas (deploy + `setFactory`/`setRecoveryManager` + `SessionRegistry`), gas da Base em ~0.01-0.011 gwei. `totalIdentities()` confirmado em `0` no registry novo (esperado — fresh deploy).

**Endereços propagados em todo o repositório**, não só no desktop — achado ao grepar o repo inteiro pelos endereços antigos: também precisavam de atualização `mobile/lib/services/blockchain_service.dart`, `sdk/typescript/src/contracts.ts`, `sdk/python/truthid/contracts.py`, `sdk/ruby/lib/truthid/contracts.rb` (nenhum desses chama `createIdentity` — só leitura, então só endereço mudou, sem mudança de ABI) e a documentação pública (`README.md`, `docs/docs/contracts.mdx`, `docs/docs/intro.mdx`, `sdk/README.md`, endereços de mainnet E sepolia). `contracts/script/DeployVaultRegistry.s.sol` também tinha os endereços antigos hardcoded (igual o `DeploySessionRegistry.s.sol` tinha antes de eu corrigir) — convertido pro mesmo padrão `vm.envAddress`, já que o `VaultRegistry` ainda não foi deployado (evita este mesmo bug se repetir quando ele for).

Verificação final: `forge build` limpo, `tsc --noEmit`/`vitest` (28/28) limpos no desktop, sintaxe Python/Ruby ok (`ast.parse`/`ruby -c`). Dart não verificado (mobile roda só via Docker neste PC, não tentei subir o container só pra isso — a mudança é uma troca trivial de string literal, risco baixo).

Config do desktop revertida de volta pra Sepolia→Mainnet antes desse redeploy (já estava assim desde o teste), e agora atualizada com os endereços REAIS da mainnet nova (não mais temporário).

**Ainda pendente**: recriar manualmente a identidade mainnet perdida (dono do projeto vai fazer isso pelo app, quando quiser).

**Anotado para depois (fora do escopo do débito #17)**: dono do projeto pediu pra registrar que falta construir a parte visual da smart account no desktop — uma tela de **extrato**: saldo, lista de lançamentos/transações e o tipo de cada lançamento (ex: funding, gas de UserOp, transferência). Ainda não tem desenho de arquitetura nem etapa no roadmap da Fase 14 — só o registro de que é a próxima coisa "visual" a fazer depois do débito #17 fechar de vez. Vale desenhar isso numa sessão dedicada antes de codar (vai precisar decidir fonte de dados — indexar eventos on-chain via `eth_getLogs`/multicall, ou usar um indexer terceiro tipo Etherscan/Blockscout API).

- **Resultado**: débito #17 resolvido de ponta a ponta — código, testes, Sepolia e Mainnet deployados e propagados por todo o repositório (desktop, mobile, 3 SDKs, docs públicas).
- **Próximo passo**: recriar a identidade mainnet do dono do projeto pelo app; desenhar a tela de extrato da smart account (etapa 14.10 do roadmap).

---

### 2026-07-03 — Sessão 63

- **Objetivo**: etapa 14.8 — sincronizar a lista de signers da smart account (`TruthIDAccount.authorizedDevices`) com o `DeviceRegistry`.

**Achado que reenquadrou a etapa**: `DeviceRegistry._getCallerIdentityId()` (`contracts/src/DeviceRegistry.sol:175`) exige `msg.sender == controller`. Desde o débito #17 (Sessão 62), `controller` é o endereço da smart account, não o Ledger. Só que `PairDevice.tsx`/`DesktopDevice.tsx`/`ManageDevices.tsx` chamavam `commitDevice`/`registerDevice`/`revokeDevice` **diretamente do Ledger como EOA** — ou seja, **pareamento e revogação de device já estavam quebrados** para qualquer identidade criada via smart account (toda identidade desde a Sessão 62). A 14.8 deixou de ser "só adicionar uma chamada" e passou a ser "consertar o `msg.sender`, aproveitando pra sincronizar".

**Decisão de arquitetura**: o Ledger aciona `TruthIDAccount.execute`/`executeBatch` via **transação direta** (`msg.sender == owner`, permitido por `_requireAuthorized` sem precisar de `EntryPoint`/UserOp/bundler) — mesmo padrão de gás já usado nas 3 transações de setup da 14.7. UserOp/bundler via viem (`viem/account-abstraction`, já disponível na versão instalada — `createBundlerClient`, `getUserOperationHash`, etc., confirmado por exploração) fica pra 14.9, onde é genuinamente necessário porque devices móveis não são o `owner`.

**Mudanças**:
- `desktop/src/config/contracts.ts`: `TRUTHID_ACCOUNT_ABI` novo (`execute`, `executeBatch`, `addDevice`, `removeDevice`, `authorizedDevices`).
- `desktop/src/contexts/IdentityContext.tsx`: `IdentityContextValue` ganhou `smartAccountAddress`; `App.tsx` passa o valor já calculado (`computeSmartAccountAddressSync`) pro `IdentityProvider` em vez de só usá-lo em `CreateIdentity`.
- `desktop/src/utils/buildAccountCalls.ts` (novo): monta os arrays `dest`/`value`/`func` de um `executeBatch` a partir de uma lista de `{ address, abi, functionName, args }`, via `encodeFunctionData` (viem).
- `PairDevice.tsx`/`DesktopDevice.tsx`: commitment agora hasheia `smartAccountAddress` (não mais o endereço do Ledger); tx de commit vira `execute(DEVICE_REGISTRY_ADDRESS, 0n, commitDevice(...))`; tx de reveal vira `executeBatch([DeviceRegistry.registerDevice, TruthIDAccount.addDevice])`.
- `ManageDevices.tsx`: revogação vira `executeBatch([DeviceRegistry.revokeDevice, TruthIDAccount.removeDevice])`.
- `PairDevice.test.tsx`: mocks de `IdentityContext`/`contracts` atualizados (ABIs reais, não vazias — `encodeFunctionData` não é mockado); teste final passou a checar `execute`/endereço da smart account em vez de `commitDevice` direto no `DeviceRegistry`.

**Verificação**: `tsc --noEmit` e `vitest` (28/28) limpos. **Teste end-to-end em Base Sepolia com o Ledger físico, mesmo dia** (desktop apontado temporariamente pra Sepolia — mesmo processo da Sessão 62 — `wagmi.ts`/`App.tsx` com `baseSepolia`, `contracts.ts`/`truthidAccount.ts` com os 5 endereços de Sepolia; revertido ao final): usando a identidade `teste` já existente (identityId 1, smart account `0x362dC9570CC35C7Fa04635167a891Df02445B7DB`), registrado o device "This Desktop" (`0xfd23ed10b147F2557D0F072b1D10F6575C300F65`) via `DesktopDevice.tsx` — confirmado via `cast call` que `DeviceRegistry.getDevice(...)` retornou `revoked=false` **e** `TruthIDAccount.authorizedDevices(device)` retornou `true`. Revogado o mesmo device pelo app — confirmado `revoked=true` e `authorizedDevices=false`. Os dois lados permaneceram sincronizados nos dois sentidos, com `msg.sender` batendo (nenhum revert de `NotIdentityController`). Fluxo de `PairDevice.tsx` (parear um endereço colado manualmente, em vez de auto-registro do próprio desktop) não foi exercitado nesta sessão — mesmo padrão de código do `DesktopDevice.tsx`, risco residual baixo. Mobile (`DevicesScreen`/`ShowDeviceQrScreen`) não foi tocado nesta sessão — o celular só *exibe* o próprio endereço pra colar no desktop, quem executa a transação é sempre o desktop/Ledger, então não há mudança necessária no lado mobile para esta etapa.

- **Resultado**: 14.8 implementada, testada (unitário) e verificada de ponta a ponta em Sepolia com o Ledger físico; descoberto e corrigido um bug real de pareamento quebrado para identidades smart-account, que passou despercebido desde a Sessão 62.
- **Próximo passo**: 14.9 (UserOps no mobile) ou 14.10 (tela de extrato da smart account).

---

### 2026-07-02 — Sessão 58

- **Objetivo**: Fase 14, etapa 14.5 — expandir a suíte de testes Foundry da `TruthIDAccount` (hoje só 3 testes narrow do débito #18) e preencher lacunas na `TruthIDAccountFactory` (hoje 10 testes, focados em CREATE2/idempotência).

**Bloco A — `TruthIDAccountFactory.t.sol`** (10 → 13 testes): 3 testes novos preenchendo lacunas identificadas no planejamento — `test_GetAddress_BeforeDeploy_NonZeroAddress` (confirma que `getAddress` retorna endereço não-zero e sem código *antes* de qualquer deploy — o pré-requisito real do fluxo "ovo-e-galinha"), `test_Revert_CreateAccount_ZeroOwner` (`createAccount(address(0))` propaga o revert do constructor da `TruthIDAccount`) e `test_GetAddress_SameOwner_SameAddress_AcrossTime` (determinismo: uma ação intermediária — deploy de outro owner — não muda o endereço previsto do primeiro). **Achado ao escrever o teste de owner zero**: a expectativa inicial era `TruthIDAccount.InvalidDevice` (erro usado em `addDevice`); o teste revelou que o revert real é `InvalidConstructorArgs` (checagem genérica de endereço zero no topo do constructor) — corrigido antes de comitar.

**Bloco B — `TruthIDAccount.t.sol`** (3 → 44 testes): arquivo reescrito do zero mantendo os 3 testes originais do débito #18 como regressão (seção B5), organizado em 8 blocos:
- **B1** Constructor (5 reverts de endereço zero, 1 por parâmetro) + `test_Constructor_SeedsBlockedForDevices` (confirma que `deviceRegistry`/`identityRegistry`/`recoveryManager` já nascem bloqueados — trava a correção do achado crítico #1 da Sessão 53).
- **B2** `addDevice`/`removeDevice`: caminho feliz + eventos, todos os reverts (`NotAuthorized`, `InvalidDevice` nos 2 ramos, `DeviceAlreadyAuthorized`, `DeviceNotAuthorized`).
- **B3** `blockDestinationForDevices`/`unblockDestinationForDevices`: eventos, efeito real sobre `validateUserOp` (device perde/recupera acesso a um destino), access control.
- **B4** `validateUserOp` tier owner: caminho feliz mirando um destino normalmente bloqueado (prova que a restrição de tier não se aplica ao owner), assinatura non-canônica rejeitada (regressão do débito #20), signer desconhecido rejeitado, revert se chamado fora do EntryPoint.
- **B5** `validateUserOp` tier device: destino permitido, os 3 destinos bloqueados por padrão (1 teste por destino), auto-chamada a `address(this)` (achado crítico #1 da Sessão 53), `executeBatch` com 1 destino bloqueado no meio falha o lote inteiro (fail-closed — documentado como decisão de design existente, não alterada), seletor fora de `execute`/`executeBatch` rejeitado, calldata curto (<4 bytes) rejeitado, signer não cadastrado em `authorizedDevices` rejeitado.
- **B6** `emergencyWithdraw`: transferência do saldo total pelo RecoveryManager + evento; reverts para owner (decisão deliberada — a função existe justamente para quando o owner já não tem mais acesso), endereço aleatório e `recipient` zero.
- **B7** `execute`/`executeBatch` como camada de execução (não validação): chamada real a um `MockTarget` novo (contrato mínimo criado no próprio arquivo de teste, só para registrar chamadas), tanto via owner quanto via EntryPoint — documentado explicitamente que a restrição de tier vive só em `validateUserOp`, não em `execute` em si (quem chama `execute` direto não passa pela checagem de destino de novo). Revert para chamador não autorizado, `ArrayLengthMismatch`, batch com múltiplas chamadas.
- **B8** `receive()`: aceita ETH direto, sem revert.

**Bug de teste pego e corrigido antes do commit** (não é bug de contrato): o teste `test_BlockDestination_EmitsEvent_AndBansDeviceCalls` inicialmente usava um helper `_validate(callData, signature)` que derivava o `userOpHash` internamente a partir de `keccak256(abi.encode(callData, signature, block.timestamp))` — mas a assinatura já tinha sido gerada por `_sign(deviceKey, userOpHash)` contra um hash *diferente* (`keccak256("op-block-test")`). O teste passava, mas por acidente: falhava por "signer não reconhecido" (hash não corresponde à assinatura), não pela verificação de destino bloqueado que o teste dizia estar validando. Identificado ao revisar por que havia um helper (`_validate`) declarado e usado uma única vez, fora do padrão dos outros 43 testes (que sempre assinam o mesmo `userOpHash` que constroem a `PackedUserOperation`). Corrigido removendo o helper e reescrevendo o teste no mesmo padrão dos demais — passou a validar de fato o bloqueio de destino.

**Decisões de escopo confirmadas antes de codar** (não são débitos, ficam registradas para não serem revisitadas sem necessidade):
- Nenhum teste de integração real com o EntryPoint v0.7 oficial (fork de rede ou deploy do contrato real) — fora do escopo de "testes unitários"; cabe na 14.7/14.9.
- `executeBatch` fail-closed (1 destino bloqueado invalida o lote inteiro) foi apenas documentado em teste, não alterado.
- Débitos #21–#26 (nits de gas/limpeza da Sessão 57) não foram tocados nesta sessão — são mudanças em contrato de produção, não em testes.

**Verificação**: `forge build` limpo (só warnings pré-existentes em outros arquivos). `forge test` → **191 testes passando** (147 anteriores + 44 novos na `TruthIDAccount` + 3 novos na `TruthIDAccountFactory` − os 3 já existentes que ficaram embutidos na contagem de 44). `forge fmt --check` limpo nos dois arquivos (após uma passada de `forge fmt` para ajustar quebras de linha).

- **Débitos**: nenhum novo aberto. #17, #19, #25 continuam pendentes (decisões de design, não bugs).
- **Próximo passo**: 14.6 — utilitário off-chain (viem) `computeSmartAccountAddress(ledgerAddress, factoryAddress)`, a integrar ao Desktop.

---

### 2026-07-04 — Sessão 64

- **Objetivo**: etapa 14.9.2 — implementar em Dart (mobile) o encoding de `PackedUserOperation` e o cálculo do `userOpHash` (EIP-4337 v0.7), como funções puras sem rede, testadas contra vetores conhecidos.

**Desenho**: `mobile/lib/utils/user_operation.dart` espelha bit a bit `viem/account-abstraction` (`toPackedUserOperation`/`getUserOperationHash`, `entryPointVersion: "0.7"`) e, por trás, o `EntryPoint.getUserOpHash`/`UserOperationLib.hash` do eth-infinitism:
- `UserOperationV07`: forma "não empacotada" da user operation, com os campos separados que os métodos JSON-RPC do bundler esperam (`eth_sendUserOperation` etc. — consumido de fato só na 14.9.3). Suporta `factory`/`factoryData` (conta ainda não deployada) e `paymaster`/`paymasterData` (não usado hoje pelo projeto — sem Paymaster central — mas implementado para cobrir o formato completo do struct).
- `toPackedUserOperation`: converte para a forma "empacotada" que o `EntryPoint`/`TruthIDAccount` decodifica on-chain — `accountGasLimits` e `gasFees` como dois `uint128` concatenados em 32 bytes cada; `initCode` = `factory ++ factoryData` (vazio se não há factory); `paymasterAndData` análogo (vazio se não há paymaster).
- `computeUserOperationHash`: como todos os campos do `abi.encode` de referência são de tamanho estático (`address`, `uint256`, `bytes32`), a codificação é só concatenação de palavras de 32 bytes sem cabeçalho de offset — dispensou um encoder ABI genérico, só helpers manuais de padding/uint→bytes.

**Vetores de teste**: gerados rodando `viem@2.52.2` (`getUserOperationHash`) num script Node descartável dentro de `desktop/` (reaproveitando o `node_modules` já instalado lá — o mesmo pacote que o desktop já usa para outras contas). 5 casos cobrindo: todos os campos zerados, caminho comum sem factory/paymaster, com `factory`/`factoryData` (conta pré-deploy), com `paymaster` completo, e valores grandes (nonce de 128 bits, calldata realista, assinatura não vazia) em Base Sepolia/Mainnet. Hashes resultantes hardcoded em `mobile/test/utils/user_operation_test.dart` — bateram byte a byte na primeira tentativa, sem precisar de ajuste na implementação Dart.

**Verificação**: `flutter test` (43 testes, incluindo os 8 novos) e `flutter analyze` limpos (os 2 únicos avisos do analyzer são pré-existentes em `vault_repository.dart`, não tocados nesta sessão) — rodados via Docker (`mobile-flutter:latest`, já buildada em sessão anterior).

**Incidente de ambiente — root partition encheu de novo durante a sessão**: `/dev/sda2` (root, 32GB) bateu 100% cheio (0 disponível) enquanto o container Docker rodava. Investigação encontrou o real culpado, diferente do que a memória de ambiente já registrava: `/var/lib/docker` já tinha sido movido para `/home` (symlink) numa sessão anterior, mas `/var/lib/containerd` — diretório **separado**, usado pelo `containerd.service` do sistema (dependência do pacote `docker` no Arch) para armazenar snapshots/conteúdo de imagem — nunca foi migrado e continuava no root, com **16GB** (12GB de snapshots overlayfs + 4.1GB de content store). Isso explica por que a migração anterior não preveniu o problema recorrente.
- Liberado ~10GB no total via `docker rm`/`docker rmi`/`docker image prune` de um container de teste já finalizado e imagens `<none>` órfãs, sem tocar nas imagens em uso (`mobile-flutter`, `desktop-desktop`).
- **Achado colateral**: remover uma imagem `<none>` órfã (mas usada como fonte de cache de build) invalidou a cache do `docker compose build` do mobile, disparando uma reconstrução completa da imagem (~200 pacotes apt, SDK do Flutter, Android SDK) que por pouco não encheu o disco de novo — processo morto a tempo (`kill` no `docker compose build`), sem chegar a produzir/commitar uma imagem final nova (a tag `mobile-flutter:latest` original ficou intacta).
- Contornado rodando os testes via `docker run` direto contra a imagem já existente (`mobile-flutter:latest`), replicando os volumes do `docker-compose.yml` manualmente, em vez de deixar o `dev.sh` chamar `docker compose build` de novo.
- **Correção durável ainda pendente** (não aplicada nesta sessão — precisa de sudo interativo, que o Claude Code não tem neste ambiente): mover `/var/lib/containerd` para `/home/masterlxz/.docker-data/containerd` (symlink), mesmo padrão já usado para `/var/lib/docker`. Comandos registrados na memória de ambiente para rodar quando conveniente.

- **Débitos**: nenhum novo.
- **Próximo passo**: 14.9.3 — cliente HTTP do bundler em Dart (`eth_estimateUserOperationGas`, `eth_sendUserOperation`, `eth_getUserOperationReceipt`), só chamadas JSON-RPC, sem lógica de assinatura ainda.

---

### 2026-07-04 — Sessão 65

- **Objetivo**: etapa 14.9.3 — cliente HTTP do bundler Pimlico em Dart (`eth_estimateUserOperationGas`, `eth_sendUserOperation`, `eth_getUserOperationReceipt`), só chamadas JSON-RPC, sem lógica de assinatura (isso é a 14.9.4).

**Achado que redesenhou o escopo**: o formato que o bundler espera via JSON-RPC (confirmado lendo `viem/account-abstraction/utils/formatters/userOperationRequest.js`) é **diferente** do `PackedUserOperation` já implementado na 14.9.2 — no wire v0.7, `factory`/`factoryData` e os 4 campos de paymaster (`paymaster`/`paymasterVerificationGasLimit`/`paymasterPostOpGasLimit`/`paymasterData`) ficam **separados**, não fundidos em `initCode`/`paymasterAndData` como no struct on-chain. Não dava pra reaproveitar `toPackedUserOperation()` — precisou de um serializador próprio (`_userOperationToRpc`).

**Novo arquivo `mobile/lib/services/pimlico_bundler_client.dart`**:
- `pimlicoBundlerUrl({apiKey, network})` — helper de conveniência pra montar a URL (`https://api.pimlico.io/v2/$network/rpc?apikey=$apiKey`), sem valor default de `network` (o app ainda não tem conceito de chain selecionável — decisão deliberada de não embutir uma suposição implícita).
- `JsonRpcTransport` — classe (não `typedef` de função) que isola a parte de HTTP cru, espelhando o `dart:io HttpClient` já usado em `BlockchainService._ethCall`. Usar classe em vez de função solta foi escolha deliberada pra bater com o único padrão de DI/mock já estabelecido no repo (`VaultKeyService`/`MockDeviceKeyService`), em vez de introduzir um idioma novo só pra este arquivo.
- `_userOperationToRpc` — serializa `UserOperationV07` pro formato hex-string do bundler. Ponto de atenção real (evitado): os campos de gas/fee/nonce são **sempre** incluídos, mesmo quando zero — só `factory`/`factoryData` e o grupo de paymaster são condicionais, e a condição certa é **presença do endereço**, não "valor diferente de zero" (gating por valor teria sido um bug sutil, já que `UserOperationV07` não distingue "não setado" de "zero" nesses campos).
- `UserOperationGasEstimate` e `UserOperationReceipt` — classes de resultado mínimas (só os campos que algo vai consumir depois; não modela o tx receipt/logs completo). `getUserOperationReceipt` devolve `null` quando a UserOp ainda não foi minerada — único dos 3 métodos cujo `result` pode vir `null` sem vir acompanhado de `error`, então precisa de checagem explícita antes do cast pra `Map`.
- `PimlicoBundlerClient` — as 3 chamadas, `entryPoint` default pro endereço padrão do EntryPoint v0.7 (constante `entryPointV07Address`, extraída pra `user_operation.dart` nesta sessão pra não duplicar o literal que já existia hardcoded no teste da 14.9.2).

**Verificação**: `flutter analyze` limpo (mesmos 2 avisos pré-existentes de sempre, não tocados). 12 testes novos em `mobile/test/services/pimlico_bundler_client_test.dart` (`mocktail`, mesmo padrão de `vault_key_service_test.dart`/`approval_screen_test.dart`) cobrindo serialização (3 casos: sem factory/paymaster, com factory, com paymaster — inclusive confirmando que as chaves condicionais ficam **ausentes**, não zeradas, quando não aplicável), parsing de resposta dos 3 métodos, o caso `null` do receipt pendente, e propagação de erro. `flutter test` completo (54 testes) sem regressão. **Checagem cruzada** (mesmo espírito da 14.9.2): rodei o `formatUserOperationRequest` real do viem em Node, dentro de `desktop/`, com os mesmos valores dos fixtures de teste (casos com factory e com paymaster) — bateu campo a campo com a saída do `_userOperationToRpc` em Dart, sem nenhuma discrepância.

- **Débitos**: nenhum novo.
- **Próximo passo**: 14.9.4 — assinar o `userOpHash` com a device key (Secure Enclave) e montar a assinatura no formato que `TruthIDAccount._validateSignature` espera.

---

### 2026-07-04 — Sessão 66

- **Objetivo**: etapa 14.9.4 — assinar o `userOpHash` com a device key e montar a assinatura no formato que `TruthIDAccount._validateSignature` espera. Escopo confirmado com o dono do projeto: reaproveitar o `DeviceKeyService` como está (chave software em `flutter_secure_storage`), sem migrar pra Secure Enclave/Android Keystore de hardware — o parênteses "(Secure Enclave)" do item do roadmap era aspiracional, não reflete a implementação atual. Migração pra hardware real registrada como débito #27 na tabela de Débitos Técnicos, pra não virar decisão implícita.

**Achado principal**: não foi preciso nenhuma criptografia nova. `DeviceKeyService.signHash(hash32)` (já usado em produção por `SessionRegistry.createSession`) já produz exatamente o formato que `TruthIDAccount._validateSignature` exige — `personal_sign` sobre o hash de 32 bytes, canonicalização low-s (EIP-2), `r(32)||s(32)||v(1)` com `v ∈ {27,28}`. A etapa inteira ficou reduzida a "plugar" essa função existente no lugar novo.

**`UserOperationV07.copyWith`** (`mobile/lib/utils/user_operation.dart`): como todo campo da classe é `final` e não havia como produzir "mesma UserOp com assinatura diferente" sem repetir os 15 argumentos na mão, adicionado `copyWith` cobrindo todos os campos (mesmo só `signature` sendo usado por enquanto). Limitação aceita e documentada em comentário: não dá pra "resetar pra null" `factory`/`paymaster` via `copyWith` — só deixar como está ou substituir por um valor; não é problema pro único uso atual.

**Novo arquivo `mobile/lib/services/user_operation_signer.dart`**: função `signUserOperation({userOperation, entryPoint, chainId, deviceKeyService})` — calcula o `userOpHash` via `computeUserOperationHash` (14.9.2, reaproveitada sem mudança), assina via `DeviceKeyService.signHash`, e devolve uma cópia da UserOp com a assinatura anexada (via `copyWith`). Função de topo, não classe — não tem estado pra guardar entre chamadas, diferente do `PimlicoBundlerClient`. Fica em `services/` (não em `utils/`) por depender de `flutter_secure_storage`/IO, diferente das funções puras da 14.9.2.

**Verificação**:
- `flutter analyze` limpo (mesmos 2 avisos pré-existentes de sempre).
- `flutter test` completo (59 testes, 6 novos) sem regressão: 3 testes de `copyWith` (troca só a assinatura, preserva o resto, não muta o original) em `user_operation_test.dart`; 2 testes de `signUserOperation` em `user_operation_signer_test.dart` (mocktail, mesmo padrão de `approval_screen_test.dart`/`pimlico_bundler_client_test.dart`) confirmando que o hash certo é passado pro `signHash` (reaproveitando o vetor `no_factory_no_paymaster` já validado na 14.9.2 contra o viem) e que erros propagam.
- **Prova de correção criptográfica** (o ponto que realmente importava nesta etapa): como a chave do `DeviceKeyService` não é injetável (gerada/lida do secure storage internamente), a prova não passa por ele — passa direto pela API pública do `web3dart` que ele usa por baixo (`EthPrivateKey.signPersonalMessageToUint8List`), testada com a conta #0 padrão do Anvil/Hardhat (chave pública de teste, sem fundos reais). Gerei o vetor de referência com `viem/accounts` `signMessage({ message: { raw: hash } })` em Node (dentro de `desktop/`) e bati byte a byte contra a saída do Dart em `mobile/test/services/device_key_signature_vector_test.dart`. Fechei o ciclo com **1 teste novo em `contracts/test/TruthIDAccount.t.sol`** (`test_ValidateUserOp_KnownVector_MatchesMobilePipeline`) usando o mesmo vetor (mesma chave, mesmo hash, mesma assinatura) contra o `validateUserOp` real — `forge test` (45 testes, 1 novo) confirmou `SIG_VALIDATION_SUCCESS`. Prova ponta a ponta: a assinatura que sai do pipeline mobile é aceita pelo contrato de verdade, não só "parece compatível por inspeção".

**Débitos**: nenhum novo (o item da Secure Enclave já foi registrado à parte como débito #27, antes desta sessão).
- **Próximo passo**: 14.9.5 — integrar tudo no fluxo real do `createSession`: construir calldata → montar UserOp → assinar (usando `signUserOperation`, desta sessão) → estimar gas → enviar → aguardar recibo.

---

### 2026-07-04 — Sessão 67

- **Objetivo**: etapa 14.9.5 — integrar as peças da 14.9.1-14.9.4 no fluxo real do `createSession`: construir calldata → montar UserOp → assinar → estimar gas → enviar ao bundler → aguardar recibo, ponta a ponta no app mobile.

**Achado que reenquadrou a etapa** (levantamento feito com um agente Explore antes de codar): o mobile **nunca chamou `SessionRegistry.createSession`**, nem direta nem indiretamente. O fluxo real (`ApprovalScreen._approve()`) sempre foi: assinar o challenge + assinar o `sessionHash`, e fazer um POST HTTPS desses dados pro `callbackUrl` do site. Quem de fato chama `createSession` on-chain é o **backend do site integrador**, via `sdk/typescript/src/client.ts` (`registerSession`), usando uma **relayer wallet financiada** (`RELAYER_PRIVATE_KEY`) — um servidor do lado do site, não o desktop nem nada do TruthID. A 14.9.5 não era "trocar uma chamada existente por UserOp": era **construir do zero**, no mobile, o caminho ponta a ponta que hoje só existe no SDK server-side, reaproveitando as peças prontas de 14.9.1–14.9.4. Confirmado com o dono do projeto antes de codar: o mobile passa a chamar `createSession` ele mesmo via UserOp/bundler (sem POST-relay pro site fazer isso), e a smart account precisa ter ETH próprio pra pagar o gás (mesmo padrão de funding já usado no desktop, sem paymaster).

**Novos ABIs** (`mobile/lib/contracts/abis.dart`): `createSession` adicionado ao `sessionRegistryAbi`; `getIdentity` adicionado ao `identityRegistryAbi` (pra resolver o `controller` — endereço da smart account, desde o débito #17 — a partir do `@username`); `truthidAccountAbi` novo (só `execute`, pra encapsular a chamada); `entryPointAbi` novo (só `getNonce`).

**`BlockchainService` estendido**: `sessionRegistryAddress` exposto publicamente (era só privado); `chainId` (Base Mainnet, `8453` — único RPC configurado hoje); `getIdentityByUsername(username)` (novo `IdentityInfo { id, controller }`); `getSmartAccountNonce(sender)` via `EntryPoint.getNonce(sender, 0)`.

**`PimlicoBundlerClient` ganhou `getUserOperationGasPrice()`** (`pimlico_getUserOperationGasPrice`, tier "fast") — método específico da Pimlico (não é ERC-4337 padrão), necessário porque `eth_estimateUserOperationGas` não devolve `maxFeePerGas`/`maxPriorityFeePerGas`.

**Novo `mobile/lib/services/session_creator.dart`** (`SessionCreator.createSession`): recebe `identityId`, `smartAccountAddress`, `sessionHash`, `devicePubKey`, `sessionSignatureHex` (a assinatura r∥s∥v já produzida por `DeviceKeyService.signHash`, mesmo formato que o SDK já espera em `registerSession` — só reparte os bytes, não assina de novo); monta `execute(SessionRegistry, 0, createSession(...))` via `web3dart` `ContractFunction.encodeCall` (sem reimplementar um encoder ABI — diferente da 14.9.2, aqui não há necessidade, já que o encoder da lib já é usado em produção em `BlockchainService`); lê o nonce; busca gas price; monta a `UserOperationV07` com assinatura placeholder pra estimativa; estima gas; assina de verdade via `signUserOperation` (14.9.4); envia; faz polling do recibo (30 tentativas × 2s por padrão, configurável — necessário pra testar o caminho de timeout sem esperar 60s de verdade).

**`ApprovalScreen` reescrito**: novo `_Status.submitting` (UI de loading) entre `challenge` e `done`. `_approve()` passou a: assinar challenge + sessionHash (igual antes) → checar se o device está pareado (`_identityId`/`_username`, agora lidos via `LocalStorageService` injetável) → resolver a smart account via `BlockchainService.getIdentityByUsername` → chamar `SessionCreator.createSession` → só então fazer o POST ao `callbackUrl` (mantido sem mudança de formato — vira só uma notificação, já que a sessão já existe on-chain quando o site recebe). `BlockchainService`/`SessionCreator`/`LocalStorageService` viraram injetáveis no construtor, mesmo padrão já usado pra `DeviceKeyService`.

**Bug de layout pré-existente, achado e corrigido nesta sessão** (não é da 14.9.5 em si): a `_InfoRow` "Signing as: Identity #..." em `_buildChallengeUI()` já existia desde antes, mas nunca renderizava nos testes porque o `LocalStorageService()` real (não mockado) sempre devolvia `null` no ambiente de teste. Ao injetar um mock com identidade pareada de verdade (necessário pra testar a 14.9.5 de forma realista), essa linha passou a aparecer e estourou a altura fixa do viewport de teste (`RenderFlex overflowed`) — um bug real de layout que existiria em qualquer tela pequena o bastante, só nunca tinha sido exercitado. Corrigido envolvendo `_buildChallengeUI()` num `SingleChildScrollView` e trocando o `Spacer()` (incompatível com scroll — exige altura limitada de um ancestral `Flex`) por um `SizedBox` fixo.

**Escopo deliberadamente deixado de fora, registrado como próximo passo (14.9.6)**: o SDK (`registerSession`) ainda chama `createSession` — como o mobile agora já cria a sessão on-chain antes do POST chegar ao site, qualquer integrador que já rode o SDK atual veria esse `registerSession` reverter com `SessionAlreadyExists`. Isso é aceitável nesta fase (app ainda não distribuído publicamente — débito #26/#27 já bloqueiam release por outros motivos) mas precisa ser resolvido antes de qualquer uso real: ajustar o SDK (3 linguagens) pra não chamar `createSession` de novo, ou verificar existência antes.

**Verificação**: `flutter analyze` limpo (mesmos 2 avisos pré-existentes + 3 infos novas de estilo em `session_creator.dart`, aceitas deliberadamente — corrigir exigiria expor nomes de campos privados como parâmetros públicos do construtor, pior que o atual). `flutter test` completo (68 testes, 14 novos: 4 em `session_creator_test.dart`, 2 em `pimlico_bundler_client_test.dart` pro gas price, 4 novos + os antigos ajustados em `approval_screen_test.dart`) sem regressão, rodado via `docker run` direto contra `mobile-flutter:latest` (mesmo padrão das Sessões 64/65, sem `docker compose build`).

- **Débitos**: nenhum novo além do já registrado (#27). Aberto explicitamente como pendência de escopo: ajuste do SDK pra parar de chamar `createSession` (14.9.6).
- **Próximo passo**: 14.9.6 — testar de ponta a ponta em Sepolia com a identidade/smart account de teste; ajustar o SDK pra não chamar `createSession` de novo (remover a dependência de `RELAYER_PRIVATE_KEY` nos lugares que hoje existem só por causa do mobile).

---


---

### 2026-07-04 — Sessão 68

- **Objetivo**: resolver débitos técnicos #19 e #27.

**Débito #19 — RecoveryManager + emergencyWithdraw** (implementação + testes) e **deploy dos 5 contratos**:

- **Base Sepolia** (5 contratos redeployados via Ledger, `m/44'/60'/1'/0'/0`):
  - `IdentityRegistry`: `0x01df431F6a2276aE3220dc6f3874454caA5F20f8`
  - `DeviceRegistry`: `0x5F92f95ABaACC85ADAde04F072d30b67eD8c896e`
  - `RecoveryManager`: `0x062c577C26067d04bBEEaa953F8E7675fF4849ab`
  - `TruthIDAccountFactory`: `0x056b826e8E31F1dCD95886571e92CA206cFB6337`
  - `SessionRegistry`: `0x925a0bCE2EA3AcF25454354197565B799E786e97`
- **Base Mainnet** (5 contratos redeployados via Ledger):
  - `IdentityRegistry`: `0xDe7a0f1918Ee39cc1792e709Edde17e8ea858998`
  - `DeviceRegistry`: `0x2be6a81B22823510c7F3Fa93E70B85aAd4fB488d`
  - `RecoveryManager`: `0xbBe777145D32fdbf8A5878eAa3a21b5f1A7d67F7`
  - `TruthIDAccountFactory`: `0x859c297342db9baa4531aC959578063646131668`
  - `SessionRegistry`: `0xbf8b940dDC3754D06ee5281209Bd3dD58852BF65`
- Custo total nas duas redes: ~0.00015 ETH (gas Base ~0.011 gwei).
- **Endereços propagados**: 11 arquivos atualizados (desktop, mobile, 3 SDKs, docs públicas) — todos os replaces feitos por script, `tsc --noEmit`/python/ruby/vitest(28/28) confirmados limpos.
- **A identidade `@masterlxz` da mainnet anterior foi perdida** (fresh deploy) — dono do projeto vai recriá-la via app desktop com a Ledger.

> ⚠️ **Nota (Sessão 69)**: o texto abaixo, descrevendo a implementação do débito #19, estava corrompido no arquivo (identificadores entre crases tinham sumido numa edição malformada anterior). Reconstruído a partir do código real em `contracts/src/RecoveryManager.sol` e `contracts/test/RecoveryManager.t.sol`.

`RecoveryManager.sol` — dentro de `executeRecovery`, antes de trocar o `controller` da identidade, checa `identity.controller.code.length > 0` (o controller antigo é um contrato, não um EOA) e, se for, chama `TruthIDAccount(payable(identity.controller)).emergencyWithdraw(proposal.newController)` dentro de um `try/catch` — qualquer revert do lado da smart account é engolido silenciosamente, a recovery da identidade nunca fica bloqueada por causa do saldo. A checagem de `code.length` evita o revert automático que o Solidity 0.8 insere ao tentar uma chamada de alto nível contra um endereço sem código (EOA).

2 testes novos em `RecoveryManager.t.sol`: `test_ExecuteRecovery_EmergencyWithdraw_TransfersEthFromTA` (deploy da factory + `TruthIDAccount` com owner charlie, identidade apontando pra ela, 2 ETH depositados, guardians 2-de-3, recovery executada → confirma saldo zerado na TA antiga e os 2 ETH no novo controller) e `test_ExecuteRecovery_EOAController_DoesNotRevert` (controller é EOA comum → `emergencyWithdraw` é pulado, recovery segue normalmente).

**Total**: 204 testes Foundry passando (eram 202, +2 novos).

**Débito #27 — Bundler configurável no mobile** (detalhes completos na tabela de Débitos Técnicos, linha #27): novo `BundlerConfigService` (lê/salva API key + network do `flutter_secure_storage` em runtime, com fallback pra `secrets.dart`); nova `SettingsScreen` com gear icon no AppBar; `ApprovalScreen` passou a montar o `PimlicoBundlerClient` sob demanda lendo essa config em runtime em vez de usar a constante de compilação; `secrets.example.dart` ganhou nota sobre a config em runtime.

**Verificação**: `forge build`/`forge test` (204/204) e `flutter test` (68/68) limpos.

- **Débitos fechados nesta sessão**: #19 e #27 (o #25, mencionado no fechamento original, não estava de fato resolvido ainda — ver Sessão 69 abaixo).
- **🚨 Deploy pendente registrado ao final desta sessão**: a `TruthIDAccountFactory` mudou (`_salt` passou a incluir `index`, débito #25) e precisaria de redeploy em Sepolia + Mainnet; os outros 4 contratos não, já que `setFactory()` no `IdentityRegistry` pode ser chamado de novo sem redeploy geral.
- **Próximo passo**: 14.9.6, ou fechar o redeploy pendente da factory.

---

### 2026-07-04 — Sessão 69

- **Objetivo**: antes de continuar codando, o dono do projeto pediu para confirmar no estado real (não só no que este arquivo dizia) se o redeploy pendente do fim da Sessão 68 já tinha sido feito — suspeita de que sim, feito fora de uma sessão de código — e para consertar as inconsistências deste arquivo encontradas no caminho.

**Auditoria on-chain (sem Ledger, só leitura via `cast call`/`cast code` contra os RPCs públicos)**:
- Débito #19 (`RecoveryManager` chama `emergencyWithdraw`): bytecode do `RecoveryManager` já deployado contém o selector `emergencyWithdraw(address)` (`0x6ff1c9bc`) **tanto em Base Sepolia quanto em Base Mainnet**, nos mesmos endereços já configurados no repositório. Nenhum redeploy pendente para este débito.
- Débito #25 (`TruthIDAccountFactory` com `index`): a Mainnet (`0x859c297342db9baa4531aC959578063646131668`) **já respondia** a `getAddress(address,uint256)` — código novo já estava lá (origem não documentada em nenhuma sessão anterior, possivelmente feito manualmente pelo dono do projeto). A Sepolia (`0x056b826e8E31F1dCD95886571e92CA206cFB6337`, endereço que este arquivo listava como o atual) **ainda respondia só à assinatura antiga de 1 argumento** — ou seja, quebrada para o código do app, que já espera o `index`.

**Redeploy da factory em Base Sepolia** (via Ledger físico, `cast wallet address --ledger --mnemonic-derivation-path "m/44'/60'/1'/0/0"` confirmou `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265` antes de broadcastar): `forge script script/DeployFactory.s.sol --rpc-url base_sepolia --ledger --broadcast` com `DEVICE_REGISTRY`/`IDENTITY_REGISTRY`/`RECOVERY_MANAGER` das envs — nova factory em `0x78d34582607e4790BCec66b6AaE3d755061F1F67`, `IdentityRegistry.setFactory(...)` chamado na mesma transação (evento `FactorySet` confirmado no trace). Verificado depois via `cast call getAddress(address,uint256)` — responde corretamente.

**Achado durante a verificação**: `desktop/src/config/truthidAccount.ts` já tinha um comentário (não usado em código, só documentação) apontando para **um terceiro endereço** de factory em Sepolia, `0x662b406E0A6f5EB8DF7C2ea9C898C8d2A4347c3E` — checado on-chain, esse contrato **já tinha o código novo** (2 argumentos) também, mas o `IdentityRegistry` de Sepolia nunca tinha sido apontado pra ele (`setFactory` nunca chamado com esse valor, aparentemente). Ou seja: alguém já tinha deployado a correção do débito #25 em Sepolia antes desta sessão, só não tinha conectado ao registry — esse endereço ficou órfão (tem código, mas nada aponta pra ele) e não deve ser referenciado em lugar nenhum daqui pra frente. O comentário em `truthidAccount.ts` foi corrigido para o endereço novo desta sessão (`0x78d34582...`), que é o que o `IdentityRegistry` de fato usa agora.

**Limpeza do `PROJECT_STATE.md`**:
- Débito #25 (tabela de Débitos Técnicos): marcado resolvido, com os dois endereços atuais.
- Tabela de Pendências de Deploy: item #0 (RecoveryManager) marcado confirmado on-chain; item novo #0b (Factory) documentando o estado real dos dois endereços; nota de confiabilidade adicionada no topo da tabela, lembrando de verificar on-chain antes de confiar cegamente nela.
- Log da Sessão 68: trecho corrompido (identificadores entre crases haviam sumido — provavelmente uma edição malformada anterior) reconstruído a partir do código-fonte real (`RecoveryManager.sol`/`RecoveryManager.t.sol`).
- Tabela de Status Geral (topo do arquivo): Fase 13 e Fase 14 atualizadas para refletir o progresso real (13.1–13.7 concluídas, 13.8–13.9 pendentes; 14.1–14.9.5 concluídas, 14.9.6/14.10/14.11/14.12 pendentes).

**Lição pra próximas sessões**: quando o `PROJECT_STATE.md` disser "deploy pendente" ou "débito aberto" envolvendo contratos já deployados, **verificar on-chain primeiro** (`cast call`/`cast code`, sem precisar do Ledger — é leitura) antes de assumir que o texto está certo ou de repetir um deploy que talvez já tenha sido feito fora de uma sessão registrada.

- **Débitos fechados**: #25 (deploy em Sepolia; o código e o deploy em Mainnet já existiam, só não documentados).
- **Próximo passo**: em aberto — dono do projeto vai decidir entre 14.9.6 (testar E2E em Sepolia agora que a factory está consistente nas duas redes + ajustar SDK), Fase 13 (Vault, 13.8/13.9), ou outra frente.

---

### 2026-07-04 — Sessão 70

- **Objetivo**: 14.9.6 — testar E2E em Sepolia (mobile criando sessão on-chain via UserOp) + ajustar os 3 SDKs pra não chamar `createSession` de novo depois que o mobile já criou a sessão.

**Parte 1 — SDK idempotente (TS/Python/Ruby)**: `registerSession`/`register_session` agora checam (leitura, sem gas) se a sessão já existe via `getSession` antes de chamar `createSession` — se o mobile já criou (fluxo pós-14.9.5), retorna `alreadyRegistered: true` sem enviar transação nem reverter com `SessionAlreadyExists`. `RegisterSessionResult` ganhou o campo `alreadyRegistered` e `txHash`/`tx_hash` virou opcional (breaking change intencional, documentado nos 4 lugares: `sdk/README.md` + `docs/docs/sdk/{typescript,python,ruby}.md`). De brinde, corrigido um bug latente em `verifySession`/`verify_session`: `getSession` reverte on-chain quando o hash não existe (não retorna struct zerada como o código antigo assumia) — extraído um helper privado (`readSession`/`_read_session`/`read_session`) com `try/catch` que trata qualquer revert como "não existe", reaproveitado nos dois métodos.

**Parte 2 — mobile apontado pra Sepolia**: `mobile/lib/services/blockchain_service.dart` editado temporariamente (RPC, 3 endereços, chainId) — mesmo padrão de edição-temporária-e-reverter já usado 3x no desktop. APK gerado via Docker (`./dev.sh build`), `flutter test` 68/68 sem regressão.

**Teste manual no device físico revelou 3 problemas reais, em cascata**:

1. **RPC bloqueado pelo fingerprint TLS do WebKitGTK**: `sepolia.base.org` e `base-sepolia-rpc.publicnode.com` (ambos atrás da Cloudflare) devolviam 403 só para requests vindas do webview do Tauri — `curl`/`cast` do mesmo container funcionavam normal. Trocado temporariamente pro RPC da Tenderly (`base-sepolia.gateway.tenderly.co`, atrás de Envoy, sem esse bloqueio) em `desktop/src/config/wagmi.ts` e no fallback manual de `desktop/src/connectors/ledger.ts` (que usava `chain.rpcUrls.default.http[0]`, o RPC embutido no viem, ignorando a config do app).

2. **Bug de corrida real no `CreateIdentity.tsx`**: os `useEffect` que disparam `createIdentity`/`deployAccount`/`fundAccount` checavam `!txNPending` como guarda contra disparo duplicado — mas `isPending` do React Query não atualiza no mesmo tick da chamada de `mutate()`. Se o efeito rodasse de novo antes do próximo render, a mutation disparava duas vezes. Confirmado com logs de debug temporários: duas chamadas `eth_sendTransaction` concorrentes, a segunda chegando no meio do `prepareTransactionRequest` da primeira — as duas brigavam pelo mesmo HID da Ledger, travando o dispositivo sem erro nenhum (nem o timeout de 120s do lado Rust disparava, porque o travamento era antes de qualquer `invoke` chegar no Rust). **Corrigido** com guardas `useRef` (síncronas, cobrem a janela que o state assíncrono não cobre) nos 3 efeitos de transação.

3. **`IdentityRegistry` deployado desatualizado (débito #28, novo)**: depois dos dois problemas acima corrigidos, a transação de `createIdentity` reverteu de verdade. `cast call ... --trace` mostrou o motivo: o staticcall interno do `IdentityRegistry` pra `factory.getAddress(...)` revertia. `cast code | grep` confirmou: o `IdentityRegistry` deployado (nas duas redes) ainda tem o seletor antigo `getAddress(address)` (1 argumento, `ae22c57d`), não o novo de 2 argumentos (`8cb84e18`) que a fonte atual usa desde o débito #25. Ou seja, só a factory tinha sido redeployada (Sessão 69) — o `IdentityRegistry` não, apesar da fonte já ter mudado. Bug bloqueava **toda** criação de identidade via smart account, nas duas redes, desde então.

**Redeploy completo (Sepolia + Mainnet)**: confirmado via `totalIdentities()` que ambas as redes tinham **0 identidades reais** — redeploy fresh sem risco de perda de dados. `Deploy.s.sol` (`IdentityRegistry` → `DeviceRegistry` → `RecoveryManager` → `setRecoveryManager` → `TruthIDAccountFactory` → `setFactory`, tudo numa run) + `DeploySessionRegistry.s.sol`, via Ledger física (`--ledger --mnemonic-derivation-paths "m/44'/60'/1'/0/0"`, deployer confirmado `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265` antes de cada broadcast). `VaultRegistry` deliberadamente não deployado (feature ainda não implementada).

Endereços novos:

| Contrato | Base Sepolia | Base Mainnet |
|---|---|---|
| IdentityRegistry | `0xDe7a0f1918Ee39cc1792e709Edde17e8ea858998` | `0x1313C576403F89eE265C880b33373d5DFB504cF2` |
| DeviceRegistry | `0x2be6a81B22823510c7F3Fa93E70B85aAd4fB488d` | `0x48e0862c43339f29ED850a59f5DBd08A4786EaDf` |
| RecoveryManager | `0xbBe777145D32fdbf8A5878eAa3a21b5f1A7d67F7` | `0x889d45C27264e1f59576FDb06722DF9Cf970CBFD` |
| TruthIDAccountFactory | `0xA438f4CF6712361001Fd07fD386596B657D98080` | `0xEd6018EE14109636F0141F2a95f9C82ef8a21eCB` |
| SessionRegistry | `0xbf8b940dDC3754D06ee5281209Bd3dD58852BF65` | `0x6531a5Ed42e077cf1b2D78d441248dC7a3ab9776` |

Coincidência a notar (nonce do deployer alinhou entre as redes): os 4 endereços novos de **Sepolia** (exceto a factory) ficaram idênticos aos que eram da **Mainnet antiga** — cuidado extra foi tomado na propagação pra não trocar os dois conjuntos entre si.

Verificado on-chain depois do redeploy, nas duas redes: seletor `8cb84e18` presente no `IdentityRegistry` novo, `factory.getAddress(...)` responde sem reverter, `totalIdentities()` continua `0`.

**Propagação dos endereços**: `desktop/src/config/contracts.ts` e `truthidAccount.ts` (Sepolia ativo temporário + Mainnet em comentário), `mobile/lib/services/blockchain_service.dart` (Sepolia ativo temporário — backup do mainnet original atualizado com os endereços novos), `sdk/typescript/src/contracts.ts`, `sdk/python/truthid/contracts.py`, `sdk/ruby/lib/truthid/contracts.rb` (só Device/Session — Ruby nunca referenciou `IdentityRegistry`, confirmado intencional), `sdk/README.md`, `docs/docs/contracts.mdx` (+ um link de exemplo de gas), `docs/docs/intro.mdx`, `README.md` raiz.

**Verificação**: `tsc --noEmit`/`vitest` (29/29) no desktop, `npm run build` no SDK TS, sintaxe Python/Ruby ok, `flutter test` no mobile via Docker — todos limpos.

- **Débitos**: #28 aberto e resolvido na mesma sessão (redeploy completo).
- **Próximo passo**: retomar o checklist manual da 14.9.6 a partir da criação da identidade de teste — agora contra o `IdentityRegistry` corrigido.

---

**Continuação (mesmo dia) — segundo bug, independente do #28**: depois do redeploy, `createIdentity` reverteu de novo, mas com um erro diferente e real (`InvalidConsentSignature`, seletor `0x71ee0a3e`). `cast call ... --trace` mostrou que dessa vez o `ecrecover` e o staticcall pra factory funcionavam sem reverter — só que o endereço que a factory computou (`0x0912e64a...`) não batia com o `controller` que o desktop tinha submetido (`0x9ED7A1B...`). Reproduzindo a fórmula do TS manualmente (`desktop/src/utils/computeSmartAccountAddress.ts`) bateu com o valor errado (`0x9ED7A1B...`) — isolando o bug no cálculo local, não no contrato.

**Causa raiz**: o comentário da função já dizia `salt = keccak256(abi.encodePacked(ledgerAddress, index))`, igual à Solidity (`TruthIDAccountFactory._salt`), mas o código usava `encodeAbiParameters` (ABI padrão — endereço com left-pad pra 32 bytes) em vez de `encodePacked` (endereço cru, 20 bytes). Produz um hash de salt completamente diferente do que a factory calcula on-chain. Bug provavelmente presente desde que o parâmetro `index` foi adicionado (débito #25) — não é novo desta sessão, só nunca tinha sido exercitado com uma factory que já respondesse corretamente ao `getAddress` de 2 argumentos (débito #28 bloqueava antes disso).

**Corrigido**: trocado `encodeAbiParameters` por `encodePacked` no cálculo do salt, em `computeAddress()`. Verificado manualmente com um script Node reproduzindo a fórmula com os dois encodings — só o `encodePacked` bate com `cast call factory getAddress(...)`. `tsc --noEmit`/`vitest` (29/29, incluindo os 13 de `computeSmartAccountAddress.test.ts`) limpos sem precisar tocar em nenhum teste existente — os testes checam propriedades relativas (mesma entrada → mesmo endereço; owners diferentes → endereços diferentes), não endereços fixos hardcoded, então não mascaravam o bug nem quebraram com o fix.

Único ponto de uso da função é `App.tsx` (fluxo de criação de identidade) — mobile e os 3 SDKs não são afetados, já que lêem o `controller` diretamente do `IdentityRegistry` on-chain em vez de recalcular o endereço localmente.

- **Débitos**: #29 aberto e resolvido na mesma sessão.
- **Próximo passo**: retomar o checklist manual da 14.9.6 — criar a identidade de teste pelo desktop, agora com os dois bugs (#28 e #29) corrigidos.

---

**Continuação (mesmo dia) — terceiro bug, no mobile**: identidade `teste` (id 1) criada com sucesso no desktop, smart account financiada automaticamente (0.001 ETH, passo 4 do `CreateIdentity`). Pareamento do celular funcionou on-chain (confirmado via `DeviceRegistry.getDevicesByIdentity(1)` e `TruthIDAccount.authorizedDevices`), mas o teste de login falhava sempre com "This device is not paired with any identity yet." mesmo com a `DevicesScreen` mostrando pareado.

**Causa raiz**: `ApprovalScreen` exige `_identityId` **e** `_username` não-nulos (`local_storage_service.dart`). A tela de Devices mostrava "Signing as: Identity #1" corretamente, mas o username nunca era salvo — `DevicesScreen._reload()` chamava `_blockchain.getUsernameForIdentity(...)` como fire-and-forget (sem `await`), e essa função (`mobile/lib/services/blockchain_service.dart`) fazia `eth_getLogs` no evento `IdentityCreated` **sem especificar `fromBlock`/`toBlock`** — RPCs públicos assumem `fromBlock: "latest"` nesse caso, então nunca encontravam o evento de uma identidade criada há mais de 1 bloco. Confirmado via `curl` direto no RPC: sem `fromBlock` retorna vazio; com `fromBlock: "earliest"` retorna erro do provedor (`query exceeds max block range 2000`, limite do `sepolia.base.org`).

**Corrigido**: `getUsernameForIdentity` agora pagina pra trás a partir do bloco mais recente em faixas de 2000 blocos (`_maxLogRangeBlocks`), até 50 faixas (`_maxLogLookbackChunks`, ≈100k blocos ≈ 55h de histórico na Base) — cobre confortavelmente o caso de uso real (username resolvido logo após um pareamento novo). **Limitação conhecida**: identidades pareadas há mais de ~55h não seriam encontradas por essa busca — não é uma solução de indexação genérica, só o suficiente pro caso de uso atual. `DevicesScreen._reload()` também passou a `await` essa chamada em vez de fire-and-forget, eliminando a janela de corrida onde `_pairedIdentityId` já estava salvo mas `_pairedUsername` ainda não.

**Verificação**: `flutter analyze` limpo (só os avisos pré-existentes de sempre), `flutter test` 68/68 sem regressão (nenhum teste existente cobria `getUsernameForIdentity` diretamente, então nada precisou ser ajustado).

- **Débitos**: #30 aberto e resolvido na mesma sessão.
- **Próximo passo**: retomar o teste de login no celular — reabrir Devices (deve resolver o username dessa vez) e tentar aprovar de novo.

---

**Continuação (mesmo dia) — quarto e quinto achados**: username resolvido (não apareceu mais "not paired"), mas o login passou a falhar com "Could not find this identity on-chain. Check your connection." (`getIdentityByUsername` retornando `null`). Reproduzido manualmente via `curl` (o mesmo `eth_call` que o app faria) contra `sepolia.base.org` **e** Tenderly — os dois retornam os dados certos (`id=1, controller=0x0912e64a..., exists=true`), ABI em `mobile/lib/contracts/abis.dart` confere com a struct real do contrato. Trocar o RPC do mobile pra Tenderly (mesma hipótese do bloqueio Cloudflare já visto no desktop) não resolveu — indicando que a causa não era essa.

**Achado real (relatado pelo dono do projeto)**: a cada instalação/atualização do APK, o app gerava um endereço de device **novo**. Investigado: `mobile/docker-compose.yml` não persistia `/root/.android` — como `docker compose run --rm` cria um container efêmero a cada execução, o Gradle gerava uma **keystore de debug nova a cada build**, com uma chave de assinatura diferente. O Android recusa `adb install -r` quando a assinatura muda (precisa desinstalar primeiro), e desinstalar apaga o `flutter_secure_storage` — incluindo a chave do device. Isso explica os 3 devices diferentes vistos antes no `DeviceRegistry` (um por rebuild) e levanta a suspeita real de que **os builds mais recentes (RPC Tenderly, fix do username) podem nunca ter sido de fato instalados** — o usuário possivelmente continuou testando um APK antigo sem perceber, por causa da necessidade de reinstalar a cada vez.

**Corrigido**: adicionado volume nomeado `android_debug_keystore:/root/.android` no `mobile/docker-compose.yml` — a keystore de debug agora persiste entre builds, então `adb install -r` volta a funcionar normalmente e o device key deixa de ser resetado a cada rebuild. Necessário desinstalar o app **uma última vez** pra estabilizar (a primeira build com o volume novo ainda gera uma keystore nova, mas as próximas reaproveitam essa mesma).

- **Débitos**: #31 aberto e resolvido na mesma sessão (keystore de debug efêmera).
- **Próximo passo**: desinstalar o app uma última vez, instalar a build mais nova (RPC Tenderly + keystore persistente), parear de novo, e só então confirmar se "Could not find this identity on-chain" ainda acontece com certeza de que é a build certa rodando.

---

**Continuação (mesmo dia) — sexto achado**: com a keystore persistente, a build ficou estável (update por cima funcionando) e o erro "Could not find this identity" se confirmou real, não resíduo de build antiga. Adicionado debug temporário (erro real vazando até a tela, em vez de engolido em `catch(_)`) revelou: `type 'null' is not a subtype of type 'bool' in type cast` — o campo `exists` (bool) da struct `Identity` vinha `null` depois de decodificado.

**Causa raiz**: `getIdentityByUsername` usava `fn.decodeReturnValues()` do `web3dart` (2.7.3) pra decodificar o retorno de `getIdentity(string)`, que é uma **struct/tuple com um campo dinâmico no meio** (`{ uint256 id; string username; address controller; bool exists; }`) — layout ABI que exige um offset interno apontando pro texto dinâmico na cauda da tupla. O decoder de tuplas dessa versão do `web3dart` não segue esse offset corretamente, desalinhando os campos seguintes (`controller`/`exists`). Confirmado reconstruindo manualmente o layout hex esperado (`[outerOffset][id][stringOffset][controller][exists][stringLen][stringBytes]`) e comparando com a resposta real do RPC — os dados on-chain sempre estiveram corretos, só a decodificação do lado do app que falhava.

**Corrigido**: `getIdentityByUsername` agora decodifica manualmente pelos offsets fixos (`id` em `hex[64:128]`, `controller` em `hex[216:256]`, `exists` em `hex[256:320]`), sem passar pelo decoder de tupla do `web3dart` — mesmo padrão manual já usado (e já funcionando) em `getUsernameForIdentity`. Extraído `_ethCallRawHex` (retorna o hex cru do `eth_call`, sem decodificar) reaproveitado tanto por `_ethCall` (decodificação via `web3dart`, pros casos sem esse problema) quanto pela decodificação manual nova.

**Verificação inicial**: `flutter analyze` limpo. Rebuild + reteste mostraram que **esse fix não era suficiente** — mesmo erro exato (`type 'null' is not a subtype of type 'bool' in type cast`) continuou aparecendo, inclusive depois de um `flutter clean` completo (descartando a hipótese de build em cache) e de um marcador único no texto de debug confirmando que a build nova estava rodando de verdade.

**Causa raiz real**: o bug não estava só na decodificação (`fn.decodeReturnValues`) — estava em **qualquer contato** com a definição ABI de `getIdentity` via `ContractFunction`/`ContractAbi.fromJson` do `web3dart` (a struct de saída com campo dinâmico no meio quebra esse caminho inteiro, não só o decode). Mesmo montando a chamada manualmente só pra pular o decode, `_identityContract.function('getIdentity')` e `fn.encodeCall(...)` ainda tocavam essa mesma definição problemática e reproduziam o erro antes de qualquer resposta de rede chegar.

**Corrigido de vez**: `getIdentityByUsername` agora monta o calldata inteiramente à mão — `keccak256("getIdentity(string)")` pro seletor, ABI-encoding manual do parâmetro `string` (offset + tamanho + bytes) — sem tocar em `ContractFunction`/`ContractAbi.fromJson` pra essa chamada em nenhum momento. O campo `_identityContract` (agora sem uso) foi removido do `BlockchainService`.

**Verificação final**: `flutter analyze` limpo, `flutter test` sem regressão, e **login testado de ponta a ponta com sucesso real** — confirmado on-chain via `cast call getSessionsByIdentity(1)`/`getSession(...)`: sessão criada pelo próprio mobile via UserOperation, sem relayer, sem paymaster. Todo o código de debug temporário (timeouts com mensagens `DEBUG`/`DEBUG-BUILD2`) foi removido depois, mantendo só os `try/catch` que já eram melhorias reais (chamadas que antes travavam a tela pra sempre sem erro nenhum em caso de falha).

- **Débitos**: #32 resolvido de verdade nesta continuação (a resolução anterior, só no decode, era incompleta) — bug real era no caminho de definição/encode do ABI do `web3dart` para structs com campo dinâmico no meio, não só no decode. Vale revisitar se outras chamadas do app usarem esse mesmo padrão de ABI no futuro (evitar `ContractFunction`/`ContractAbi.fromJson` pra funções com esse formato de retorno, preferir encode/decode manual como feito aqui).
- **Resultado da 14.9.6**: **completa**. SDK idempotente (3 linguagens), mobile apontado pra Sepolia, 5 contratos redeployados (débito #28) em Sepolia e Mainnet, bug do CREATE2 salt corrigido (débito #29), keystore de debug persistente (débito #31), bug de decodificação de identidade corrigido (débito #32), identidade/pareamento/sessão testados de ponta a ponta com sucesso real em Sepolia.

---

**Continuação (mesmo dia) — revertendo as configs de Sepolia pra mainnet**: teste confirmado com sucesso, dono do projeto pediu pra reverter tudo e fechar a sessão.

Revertido (todos os valores de mainnet já eram os endereços **novos** do redeploy, não os antigos pré-Sessão 70):
- `desktop/src/config/contracts.ts`, `desktop/src/config/truthidAccount.ts` — endereços de mainnet ativos de novo (Sepolia voltou a ficar só em comentário).
- `desktop/src/config/wagmi.ts`, `desktop/src/App.tsx` — `base` (mainnet) de volta, fallback de RPC original restaurado (`mainnet.base.org`/`publicnode.com`/`drpc.org`).
- `desktop/src/connectors/ledger.ts` — fallback de RPC do provider revertido pra `chain.rpcUrls.default.http` puro (sem o override de Tenderly).
- `desktop/src/components/CreateIdentity.tsx` — removido um `console.log` de debug esquecido (`[DEBUG overallError completo]`) que não fazia parte de nenhum fix permanente.
- `mobile/lib/services/blockchain_service.dart` — RPC (`mainnet.base.org`), 3 endereços e `chainId` (8453) de volta pra mainnet.
- `sdk/typescript/example/server.js` — `network: "base-mainnet"` de novo; `sdk/typescript` recompilado (`npm run build`).
- Infra de teste derrubada: processo do `node server.js`, túnel `cloudflared`, container Docker do desktop.

**Risco descoberto que NÃO foi revertido silenciosamente** (fora do escopo de "reverter", registrado aqui pra decisão futura): o override temporário do RPC pra Tenderly no desktop (`wagmi.ts`/`ledger.ts`) existiu porque `sepolia.base.org` (Cloudflare) bloqueava com 403 o fingerprint TLS do WebKitGTK. O RPC de mainnet padrão (`mainnet.base.org`) **também é Cloudflare** — o mesmo bloqueio pode acontecer em produção real com usuários do desktop, não só em teste. Não corrigido agora (fora do pedido de "reverter"), mas vale investigar/decidir separadamente antes de distribuir o desktop pra usuários finais.

**Verificação final**: `tsc --noEmit`/`vitest` (29/29) no desktop, `flutter analyze`/`flutter test` (68/68) e build limpo no mobile (agora contra mainnet) — tudo confirmado depois da reversão.

- **Débitos**: nenhum novo aberto por esta continuação — só o risco do Cloudflare/mainnet.base.org acima, registrado como observação, não como débito numerado (precisa de decisão do dono do projeto sobre se/como investigar).
- **14.9.6 encerrada.** Próximo passo em aberto: 14.10 (tela de extrato da smart account) ou Fase 13 (Vault, 13.8/13.9).

---

### 2026-07-05 — Sessão 71

- **Objetivo**: 14.10 — dashboard da smart account no Desktop (tab dedicada): saldo, histórico de operações com custo por tipo, depósito (QR) e saque (assinado pela Ledger).

**Decisões de escopo confirmadas com o dono do projeto antes de implementar**: (1) o histórico cobre só os 3 tipos com evento nativo on-chain (sessão criada/revogada, device registrado/revogado, vault atualizado) via scan de `eth_getLogs` — sem indexador externo (nada de Basescan/Etherscan API), consistente com o projeto não ter operador central; depósito/saque não aparecem como linha do histórico (não emitem evento), só refletem no saldo. (2) o primeiro scan busca desde o bloco de deploy de cada contrato na Base Mainnet, não uma janela recente — histórico completo, não uma otimização tipo a do mobile (que desiste depois de 50 chunks).

**Novos arquivos**:
- `desktop/src/utils/scanSmartAccountActivity.ts` — função pura de scan, sem React/wagmi (recebe um client viem tipado como `Pick<PublicClient, "getContractEvents" | "getTransactionReceipt" | "getBlock">`, pra ser mockável em teste). Caminha o range **pra frente** (não pra trás como o padrão do mobile) em chunks de 2000 blocos — mesmo valor já validado contra RPCs públicos da Base em `mobile/lib/services/blockchain_service.dart`. Direção pra frente escolhida porque dá um cursor de retomada estável (`lastScannedBlock`) e uma barra de progresso honesta, ao contrário de um scan pra trás cujo ponto de parada (`latest`) muda a cada bloco novo. Escaneia 5 eventos (`DeviceRegistered`/`DeviceRevoked`/`SessionCreated`/`SessionRevoked`/`AllSessionsRevoked`) e pula `VaultUpdated` inteiramente enquanto `VAULT_REGISTRY_ADDRESS` for o zero address. Deduplica receipts (por tx hash) e blocks (por número) pra não buscar o mesmo dado 2x quando eventos compartilham transação/bloco. Custo de cada operação = `receipt.gasUsed * receipt.effectiveGasPrice`.
- `desktop/src/hooks/useSmartAccountActivity.ts` — hook que liga a função pura ao `usePublicClient()`, cacheia progresso em `localStorage` (`truthid.activity.<identityId>`, bigints serializados como string) pra que cada visita à tab depois da primeira só escaneie o delta desde o último bloco visto, em vez de refazer o histórico completo. Sem versionamento de schema — cache corrompido/ausente cai automaticamente pra um scan completo (tudo é rederivável da chain).
- `desktop/src/components/SmartAccountDashboard.tsx` — saldo (`useBalance`, primeiro uso desse hook no repo), resumo de custo por tipo (Sessions/Devices/Vault, com "Not available yet" pro Vault enquanto não deployado), lista de atividade mais recente primeiro, botões Deposit/Withdraw.
- `desktop/src/components/DepositModal.tsx` — clone do `DonateModal.tsx` existente (QR + endereço + copiar), apontando pro endereço da smart account em vez do endereço de doação.
- `desktop/src/components/WithdrawModal.tsx` — form de saque (endereço + quantidade + botão Max), validação (`isAddress`, `amount <= availableBalance`, sem buffer de gás porque quem paga o gás da chamada `execute()` é a Ledger, não a smart account sendo sacada), transação única via `TruthIDAccount.execute(dest, value, "0x")` — mesmo mecanismo já usado pelo pareamento de device (14.8), sem UserOp/bundler, com o mesmo guard `useRef` de disparo duplicado do `CreateIdentity.tsx`.

**Mudanças em arquivos existentes**:
- `desktop/src/config/contracts.ts` — adicionados os eventos `DeviceRegistered`/`DeviceRevoked` ao `DEVICE_REGISTRY_ABI` (não existiam, ao contrário de `SESSION_REGISTRY_ABI`/`VAULT_REGISTRY_ABI` que já tinham os deles) e as constantes `DEVICE_REGISTRY_DEPLOY_BLOCK`/`SESSION_REGISTRY_DEPLOY_BLOCK` (blocos `48207828`/`48207855` na Base Mainnet, confirmados diretamente nos artefatos de broadcast do Foundry — batem com os endereços atuais, redeploy da Sessão 70/débito #28).
- `desktop/src/types.ts` — novos tipos `SmartAccountActivityType`/`SmartAccountActivity`.
- `desktop/src/App.tsx` — nova tab `"dashboard"`, primeira da lista (antes de "Devices"), landing tab padrão do app.

**Testes novos**: `scanSmartAccountActivity.test.ts` (6 testes — chunking com chunk parcial final, short-circuit do Vault quando endereço é zero, dedup de receipt/block, mapeamento de custo, `onChunkScanned` incremental e ordenado), `SmartAccountDashboard.test.tsx` (7 testes) e `WithdrawModal.test.tsx` (5 testes) — seguindo a estrutura de mocks já usada em `PairDevice.test.tsx`. Suite completa do desktop: 29 → 47 testes, todos passando. `tsc --noEmit` e `npm run build` limpos.

- **Débitos**: nenhum novo.
- **Pendência**: o checklist manual E2E em Base Sepolia com a Ledger física (abrir a tab contra a identidade `teste`, conferir saldo/histórico batendo com `cast`, testar depósito/saque de verdade, confirmar retomada incremental do scan numa segunda visita) fica pro dono do projeto rodar — depende de hardware físico, não foi executado nesta sessão.
- **14.10 concluída** (implementação + testes automatizados). Próximo passo em aberto: validação manual E2E acima, 14.12 (docs) ou Fase 13 (Vault, 13.8/13.9).

### 2026-07-06 — Sessão 72

- **Objetivo**: fechar uma paridade desktop↔mobile encontrada numa conversa de acompanhamento — o mobile não mostrava o saldo da smart account (só o Desktop, via 14.10) e a `SessionsScreen` trazia um aviso fixo dizendo "para revogar sessões, use o desktop" que ficou desatualizado desde a 14.9.5.

**Achado**: `SessionRegistry.revokeSession` só exige que `msg.sender` seja o controller da identidade (a smart account) — não distingue quem assinou a UserOp que chegou até ali. Como a Fase 14 (Problema 3) só bloqueia devices de chamar o `DeviceRegistry`, um device já podia revogar sessões via UserOp desde que a 14.9.5 implementou `createSession` pelo mobile; o aviso na UI nunca foi atualizado para refletir isso.

**Mudanças**:
- `mobile/lib/services/blockchain_service.dart` — novo método `getBalance(EthereumAddress)`, via `eth_getBalance` cru (mesmo padrão JSON-RPC manual do resto do arquivo, sem depender de `Web3Client`).
- `mobile/lib/contracts/abis.dart` — adicionada a função `revokeSession(bytes32)` ao `sessionRegistryAbi` (só tinha `createSession`/getters).
- `mobile/lib/services/session_creator.dart` — extraído o núcleo de `createSession` (montar `execute()`, ler nonce, estimar gas, assinar, enviar, aguardar recibo) num método privado `_executeViaUserOp`, reaproveitado por um novo método público `revokeSession({smartAccountAddress, sessionHash})`. `SessionCreationResult` (só `userOpHash`/`transactionHash`) reaproveitado como retorno de ambos — não é específico de criação, apesar do nome.
- `mobile/lib/screens/sessions_screen.dart` — reescrita: (1) card de saldo no topo, resolvido via `getIdentityByUsername` (mesma chamada que a `ApprovalScreen` já fazia) seguido de `getBalance`, carregado em paralelo à lista de sessões sem bloquear a tela; (2) botão de revogar (ícone `logout`) em cada sessão ativa, com diálogo de confirmação, spinner por linha durante a UserOp e recarga da lista ao concluir; erro de rede/gas insuficiente vira snackbar em vez de travar a tela. `SessionCreator`/`BundlerConfigService` são construídos sob demanda na primeira revogação, mesmo padrão de lazy-init da `ApprovalScreen` (débito #27). Aviso fixo "use o desktop" removido.
- Construtor de `SessionsScreen` ganhou parâmetros injetáveis (`blockchainService`, `localStorageService`, `deviceKeyService`, `bundlerConfigService`, `sessionCreator`) para testes, mesmo padrão da `ApprovalScreen`.

**Testes novos**: 2 casos em `session_creator_test.dart` (grupo `revokeSession` — monta/assina/envia a UserOp de revogação e confirma o recibo; propaga erro do bundler) e `sessions_screen_test.dart` (novo — 5 casos: saldo exibido, botão de revogar só em sessões ativas, confirmar chama `revokeSession` e recarrega, cancelar não chama nada, erro vira snackbar sem travar). Suite completa do mobile: 68 → 75 testes, todos passando. `flutter analyze` limpo (só os 5 lints pré-existentes, nenhum novo).

- **Débitos**: nenhum novo.
- **Próximo passo**: sem pendência aberta por esta sessão. Candidatos de continuação: 14.12 (docs), Fase 13 (Vault, 13.8/13.9), ou o checklist manual E2E da Ledger física (Sessão 71).

### 2026-07-06 — Sessão 73

- **Objetivo**: completar a paridade desktop↔mobile iniciada na Sessão 72 — o mobile ainda não tinha histórico de atividade nem depósito/saque (só saldo). Adicionada uma aba "Wallet" dedicada, espelhando a dashboard da smart account do Desktop (14.10).

**Decisões confirmadas com o dono do projeto antes de implementar**: (1) aba nova dedicada na bottom nav, não expandir a `SessionsScreen`; (2) histórico completo desde o bloco de deploy dos contratos, com cache de progresso (não a janela bounded de ~100k blocos que `getUsernameForIdentity` usa); (3) Vault fica de fora do histórico (VaultRegistry ainda não deployado), mesma decisão do Desktop.

**Achado de arquitetura que viabilizou o saque sem o owner**: confirmado em `TruthIDAccount._isDeviceCallAllowed` (contracts/src/TruthIDAccount.sol) que o `value` de `execute(dest, value, func)` não é restringido pro tier device — só o `dest` precisa não ser a smart account nem um contrato bloqueado. Logo o mobile pode sacar ETH via UserOp assinada pelo device, sem precisar do Ledger (diferente do `WithdrawModal` do Desktop, que assina uma tx direta porque a Ledger é o owner).

**Novos arquivos**:
- `mobile/lib/models/smart_account_activity.dart` — `SmartAccountActivityType` (sem `vaultUpdated`), `SmartAccountActivity` (toJson/fromJson, costWei serializado como string) e `ScanProgress`.
- `mobile/lib/services/smart_account_activity_scanner.dart` — porta de `desktop/src/utils/scanSmartAccountActivity.ts`: 5 fontes de evento (topic0 computado à mão via keccak256, mesmo estilo de `getUsernameForIdentity`), chunks de 2000 blocos pra frente, dedup de receipt/timestamp por chamada, `onChunkScanned` incremental.
- `mobile/lib/services/activity_cache_service.dart` — cache de progresso do scan (`lastScannedBlock` + atividades) via `flutter_secure_storage` (reaproveitando a dependência já usada por `LocalStorageService`/`BundlerConfigService`, sem adicionar `shared_preferences`), espelhando `readCache`/`writeCache`/`clearCache` de `useSmartAccountActivity.ts`.
- `mobile/lib/screens/wallet_screen.dart` — nova aba: card de saldo + Deposit/Withdraw, resumo de custo por tipo (Sessions/Devices), lista de atividade (mais recente primeiro). Deposit é um bottom sheet com QR + endereço (mesmo padrão do `_DonationSheet` de `main.dart`). Withdraw é um bottom sheet com formulário (endereço + quantidade + Max), validado e enviado via `SessionCreator.withdraw` (novo). Parser manual de ETH decimal→wei (`_parseEtherToWei`) — **achado**: `EtherAmount.fromBase10String` do web3dart 2.7.3 não entende ponto decimal (faz só `BigInt.parse` cru multiplicado pelo fator da unidade), então não dava pra usar direto pra um input tipo "0.05".
- `mobile/test/services/smart_account_activity_scanner_test.dart`, `mobile/test/services/activity_cache_service_test.dart`, `mobile/test/screens/wallet_screen_test.dart` — novos.

**Mudanças em arquivos existentes**:
- `mobile/lib/services/blockchain_service.dart` — `_getLatestBlockNumber` virou público (`getLatestBlockNumber`); novos `getLogs` (genérico, lança exceção em erro — ao contrário de `_fetchIdentityCreatedLogs`, que engole erro e tenta o chunk anterior), `getTransactionReceipt`, `getBlockTimestamp` (ambos novos nesta base de código); nova classe `TxReceiptInfo`; novas constantes `deviceRegistryDeployBlock`/`sessionRegistryDeployBlock` (48207828/48207855, mesmos valores do Desktop) e `deviceRegistryAddress` público.
- `mobile/lib/services/session_creator.dart` — `_executeViaUserOp` ganhou parâmetro `value` (antes hardcoded em `BigInt.zero`); novo método público `withdraw({smartAccountAddress, destination, amountWei})`.
- `mobile/lib/main.dart` — 3ª aba "Wallet" (`IndexedStack` + `_NavTab`, ícone `account_balance_wallet`), espaço do FAB realocado entre a 2ª e a 3ª aba.
- `mobile/lib/screens/sessions_screen.dart` — card de saldo (`_balanceWei`/`_balanceLoading`/`_formatBalance`) removido, migrado pra `WalletScreen`; `_loadBalance` virou `_resolveSmartAccount` (só resolve `_smartAccountAddress`, ainda necessário como `sender` da UserOp de revoke).
- `mobile/test/screens/sessions_screen_test.dart`, `mobile/test/services/session_creator_test.dart` (grupo `withdraw` novo), `mobile/test/widget_test.dart` — atualizados.

**Testes novos**: 7 no scanner (chunk único, ordenação por blockNumber/logIndex, dedup de receipt/timestamp, chunking >2000 blocos, `onChunkScanned` incremental, propagação de erro de `getLogs`/`getTransactionReceipt`), 5 no cache (round-trip, JSON corrompido, sem cache, clear, falha de escrita engolida), 2 em `withdraw` (encoding do `execute` com `value` correto — comparado byte a byte contra um `encodeCall` reconstruído, já que aqui o `value` varia; propagação de erro), 6 na `WalletScreen` (saldo, custo por tipo via cache, deposit mostra QR, withdraw com sucesso, withdraw com falha, refresh limpa cache e re-escaneia). Suite completa do mobile: 75 → 94 testes, todos passando. `flutter analyze` limpo (mesmos 5 lints pré-existentes, nenhum novo).

**Bugs pegos e corrigidos durante os próprios testes** (não chegaram a produção): (1) sheet de depósito estourava a altura da tela em viewports menores — trocado `Padding` por `SingleChildScrollView`; (2) teste inicial usava hashes de teste curtos demais (`'0xTx1'`) que quebravam o slice de exibição (`substring`) — corrigido pra hashes de 66 chars, formato real de tx hash; (3) mock de `getLatestBlockNumber` retornava um bloco bem menor que os deploy blocks reais, fazendo o guard "já passamos do tip" (`fromBlock > latest`) pular o scan silenciosamente em todo teste — corrigido o valor mockado.

- **Débitos**: nenhum novo.
- **Pendência**: validação manual contra a Base Mainnet real (saldo/atividade batendo com o que a dashboard do Desktop já mostra pra mesma identidade; saque de verdade com valores pequenos, exige saldo pra bundler + Pimlico API key configurada; cache incremental entre reinícios do app) — fica pro dono do projeto, análogo à pendência da 14.10.
- **Próximo passo**: sem pendência de código aberta por esta sessão. Candidatos de continuação: 14.12 (docs), Fase 13 (Vault, 13.8/13.9), ou os checklists manuais acumulados (Ledger física da Sessão 71 + validação da Wallet mobile desta sessão).

### 2026-07-06 — Sessão 74

- **Objetivo**: etapa 14.12 — última pendência da Fase 14. Nova página de docs explicando o modelo de smart account, custo de setup e como financiar. Com isso, a **Fase 14 fica concluída**.

**Achado antes de escrever**: o site de docs (`docs/`, Docusaurus) não mencionava ERC-4337, `TruthIDAccount`, `TruthIDAccountFactory`, UserOp ou bundler em lugar nenhum. Pior: `intro.mdx` descrevia o modelo antigo ("identidade criada com qualquer wallet EVM segurando um pouco de ETH pra cobrir gas"), o que hoje é impreciso — o controller real é uma smart account que se autofinancia depois do setup. Corrigido junto, não só a página nova.

**Dado interessante descoberto durante a implementação**: a memória de ambiente registrada anteriormente ("Foundry/forge não instalado") estava desatualizada — `forge` já está instalado (`~/.foundry/bin/forge`). Rodado `forge test --gas-report` em `TruthIDAccount.t.sol`/`TruthIDAccountFactory.t.sol` (62 testes) pra obter números reais de gas, seguindo a mesma disciplina do resto do site ("never estimate, always measure") — não havia nenhum número de gas documentado pra esses dois contratos até agora.

**Novos arquivos**:
- `docs/docs/smart-account.mdx` (`sidebar_position: 6`) — dois tiers de signer (owner/device), CREATE2, sem paymaster; os 4 passos reais do setup (assinatura de consentimento + createIdentity + deploy + funding, citando a UI real do `CreateIdentity.tsx`); custo do dia a dia via UserOp/bundler; como financiar depois (Deposit do Desktop/mobile); endereços de `TruthIDAccountFactory`/`EntryPoint` (mainnet+sepolia); tabela de gas real (`createAccount` primeiro deploy vs já-existente, `execute`, `addDevice`, `removeDevice`), com a ressalva de que o gas medido não inclui overhead do bundler.

**Mudanças em arquivos existentes**:
- `docs/docs/contracts.mdx` — `TruthIDAccountFactory` adicionado às tabelas de endereço (mainnet/sepolia); novas subseções `### TruthIDAccount`/`### TruthIDAccountFactory` no "Contract reference" (mesmo formato function/caller/purpose das outras quatro); linhas de gas novas na tabela "Cost per operation"; nota sobre a fonte dos 62 testes novos; link pra `/docs/smart-account` no "Next steps" e na frase sobre o gas mais pesado da tabela (que deixou de ser `registerDevice` depois de incluir `createAccount`).
- `docs/docs/intro.mdx` — "Prerequisites" deixa claro que a wallet externa só paga gas uma vez; tabela "Smart contracts" ganhou `TruthIDAccountFactory` e a frase final agora explica o modelo self-funded, linkando pra página nova.
- `docs/docusaurus.config.ts` — item "Smart Account & Gas" adicionado à lista "Docs" do footer.

- **Débitos**: nenhum novo.
- **Verificação**: `cd docs && npm run build` — sucesso, sem links quebrados (`onBrokenLinks: 'throw'` no config, então qualquer link interno errado teria derrubado o build). Página nova presente em `docs/build/docs/smart-account/`.
- **Fase 14 concluída** (14.1–14.12, todos os itens). Próximo passo: Fase 13 (Vault, 13.8/13.9), ou os checklists manuais acumulados (Ledger física da Sessão 71 + validação da Wallet mobile da Sessão 73) — nenhum débito de código aberto.


### Sessão 76 — 2026-07-06: Vault key via wallet (RFC 6979) + ECIES no pareamento (débito #34)

- **Objetivo**: Resolver o débito #34 — cada device derivava sua própria chave do vault (da device key), impossibilitando sincronização entre 2+ devices. O usuário pediu que a chave fosse derivada da wallet (root), recuperável apenas com a wallet em qualquer dispositivo.

- **Decisão de arquitetura**: derivar a vault key da assinatura `personal_sign("TruthID Vault Key v1")` via RFC 6979 (k determinístico). Mesma wallet + mesma mensagem = mesma assinatura = mesma vault key em qualquer lugar. A chave é cacheada no keyring do SO após a primeira derivação (wallet não é necessária no dia a dia).

- **Contrato — DeviceRegistry**: novo parâmetro `bytes encryptedVaultKey` em `registerDevice` (4º argumento, opcional — `""` mantém comportamento anterior). Novo mapping `deviceVaultKeys(address => bytes)` + getter público. Evento `DeviceRegistered` ganhou 4º campo `encryptedVaultKey` (não-indexado). 4 novos testes (33 total no DeviceRegistry, 212 total na suite). **Precisa de redeploy** em Base Sepolia e Base Mainnet (ver Pendências de Deploy).

- **Desktop — Rust**:
  - `lib.rs`: removida `derive_vault_key()` → renomeada `derive_vault_key_legacy()` (mantida pra migração). Novas funções: `get_vault_key()` (lê do keyring, fallback legacy), `set_vault_key()` (persiste no keyring), `vault_key_exists()` (Tauri command), `derive_vault_key_from_wallet(r, s, v)` (HKDF-SHA256 com info `"vault-key-v2"`, armazena no keyring). Nova constante `VAULT_KEY_ACCOUNT = "vault-key"`.
  - `vault.rs`: `encrypt()`/`decrypt()` agora usam `get_vault_key()` (não mais `derive_vault_key()`). `load()` com migração automática: tenta chave nova → fallback chave legada → recifra com chave nova.
  - `encrypt_vault_key_for_device(device_pubkey_hex)`: ECIES secp256k1 (ECDH ephemeral → SHA-256 → AES-256-GCM). Aceita chave comprimida (33 bytes) ou não-comprimida (65 bytes). Retorna blob Base64: `ephemeral_pub(33) || nonce(12) || ciphertext+tag`. Dependência `k256` ganhou feature `ecdh` em `Cargo.toml`.

- **Desktop — TypeScript/React**:
  - `hooks/useVaultKey.ts` (novo): hook que verifica `vault_key_exists()`, gerencia derivação via `signMessage` + `derive_vault_key_from_wallet`.
  - `CreateIdentity.tsx`: após `tx3Success`, mostra seção "Setup vault key" com botão pra assinar e derivar. Importa `invoke` do Tauri.
  - `VaultManagement.tsx`: guard no topo — se `vault_key_exists()` retorna false, mostra tela "Unlock Vault" com botão pra conectar wallet e assinar. Importa `useSignMessage` e `hexToSignature`.
  - `PairDevice.tsx`: campo novo "Encryption key (optional)" pra colar a chave pública do mobile (do QR). Hook `setTimeout` virou async — chama `encrypt_vault_key_for_device` e passa o blob cifrado como 4º arg do `registerDevice`. Importa `invoke` e `Hex`.

- **Mobile — Dart**:
  - `pubspec.yaml`: adicionado `elliptic: ^0.3.11` (ECDH secp256k1).
  - `device_key_service.dart`: novo método `getDevicePublicKeyHex()` — retorna chave pública comprimida (33 bytes, `privateKeyToPublic`).
  - `vault_key_service.dart` reescrito: `deriveVaultKey()` agora lê do `FlutterSecureStorage` (`truthid_vault_key`), com fallback `_deriveLegacyKey()`. Novo método `decryptVaultKeyFromPairing(encryptedBlob)` — ECDH via `elliptic` (`computeSecret`) + AES-256-GCM via `cryptography` (`AesGcm.with256bits()`). `hasVaultKey()` verifica se chave existe no storage.
  - `show_device_qr_screen.dart`: QR payload agora inclui `encryptionKey` (chave pública comprimida). Após pareamento confirmado, chama `getDeviceVaultKey` + `decryptVaultKeyFromPairing`.
  - `blockchain_service.dart`: novo método `getDeviceVaultKey(address)` — lê mapping público `deviceVaultKeys` do contrato.

- **ABI/Config**:
  - `desktop/src/config/contracts.ts`: `registerDevice` ganhou 4º input `encryptedVaultKey`. Evento `DeviceRegistered` ganhou 4º campo. Novo entry `deviceVaultKeys` (view function).
  - `desktop/src/components/__tests__/PairDevice.test.tsx`: mock ABI atualizado com 4º parâmetro.
  - Integration tests (`integration/e2e*.ts`): 3 arquivos atualizados com 4º arg `"0x"`.

- **Migração**: automática e transparente. `vault::load()` tenta decifrar com a chave nova (wallet-derived). Se falhar, tenta a chave legada (device-key). Se sucesso na legada, recifra com a chave nova e salva. Mobile: `deriveVaultKey()` tenta storage primeiro, fallback `_deriveLegacyKey()`.

- **Testes**: Rust 14/14, vitest (desktop) 47/47, Foundry 212/212 (33 DeviceRegistry + 4 novos), Flutter analyze 0 errors.

- **Pendência de deploy**: `DeviceRegistry` alterado (novo parâmetro `encryptedVaultKey` em `registerDevice` + mapping `deviceVaultKeys` + evento expandido). Precisa de redeploy em Base Sepolia e Base Mainnet, e atualizar `DEVICE_REGISTRY_ADDRESS` + `DEVICE_REGISTRY_DEPLOY_BLOCK` em `desktop/src/config/contracts.ts`, `mobile/lib/services/blockchain_service.dart`, SDKs e docs. Ver tabela de Pendências de Deploy.

- **Próximo passo**: o usuário mencionou querer continuar com outras pendências. Candidatos: redeploy do DeviceRegistry, ou os débitos #35–#43 restantes da Sessão 75.


### Sessão 77 — 2026-07-06: Redeploy completo dos 5 contratos (débito #34 — pendência de deploy)

- **Objetivo**: fechar a pendência de deploy deixada pela Sessão 76 — o `DeviceRegistry` mudou (novo parâmetro `encryptedVaultKey`, mapping `deviceVaultKeys`, evento expandido) e precisava de redeploy em Sepolia + Mainnet.

- **Achado antes de deployar**: `DeviceRegistry` não é isolado — `SessionRegistry` e `TruthIDAccountFactory` guardam o endereço dele como `immutable` no construtor (`TruthIDAccountFactory` repassa esse endereço pra cada `TruthIDAccount` deployado, que usa pra bloquear devices de chamarem o `DeviceRegistry` diretamente — a separação owner/device da Fase 14). Redeployar só o `DeviceRegistry` deixaria o `SessionRegistry` existente validando contra um registry abandonado, e as smart accounts existentes bloqueando o endereço errado. Decisão do dono do projeto: repetir a mesma cascata da Sessão 70 — redeploy completo dos 5 contratos (`IdentityRegistry`, `DeviceRegistry`, `RecoveryManager`, `TruthIDAccountFactory`, `SessionRegistry`; `VaultRegistry` continua de fora, ainda não implementado).

- **Verificação pré-deploy**: `cast call ... totalIdentities()` no `IdentityRegistry` atual da Mainnet (`0x1313C576...`) confirmou **0** identidades reais — redeploy sem risco de orfanar identidade de usuário (diferente da Sessão 62, onde havia 1 e foi perdida deliberadamente).

- **Deploy via Ledger físico** (`--ledger --mnemonic-derivation-paths "m/44'/60'/1'/0/0"`, deployer confirmado `0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265` antes de cada broadcast, RPC público em ambas as redes, sem `.env`): `Deploy.s.sol` (4 contratos + `setRecoveryManager`/`setFactory`) e `DeploySessionRegistry.s.sol`, primeiro Sepolia depois Mainnet.

**Endereços novos**:

| Contrato | Sepolia | Mainnet |
|---|---|---|
| IdentityRegistry | `0xe399DbA342558Bc8937BBb4C33060cCE1F936AD0` | `0xAC24F39e7Abdd819578d96A040c2DF4394c43423` |
| DeviceRegistry | `0xC61b82C29D80098558D7Ca73CC47D907B62f9e3F` | `0xea61a59810Ee981B5FB7C1d42FE348Cbe8aE5344` |
| RecoveryManager | `0xfFBA6E09E7170183F61B00723ef2255eaf765e2e` | `0x62795F69a4e815E3A79737122C7Fdd45D857C94D` |
| TruthIDAccountFactory | `0xD6f2c3Ef24d647f381CD2467B9485cA022520a91` | `0xD154B28F60500348cFCbb0F6511b8EF51D0D29B8` |
| SessionRegistry | `0x80878CC2B339D187051EEd905699613a0ed84B12` | `0x1F34F33f1061E44028e28a4e17E43d4eaE92f7FA` |

Custo real: ~0.00013 ETH nas duas redes combinadas (mesma ordem de grandeza da Sessão 70). `totalIdentities()` e `factory.deviceRegistry()`/`FACTORY_IMMUTABLES` conferidos on-chain nas duas redes após o deploy.

- **Propagação dos endereços** (mesmo escopo da Sessão 62): `desktop/src/config/contracts.ts` (endereços + `DEVICE_REGISTRY_DEPLOY_BLOCK`/`SESSION_REGISTRY_DEPLOY_BLOCK`, novos blocos `48_291_335`/`48_291_355` extraídos dos artefatos de broadcast), `desktop/src/config/truthidAccount.ts` (factory + `FACTORY_IMMUTABLES`, comentário de Sepolia), `mobile/lib/services/blockchain_service.dart` (endereços + blocos de deploy), `sdk/typescript/src/contracts.ts`, `sdk/python/truthid/contracts.py`, `sdk/ruby/lib/truthid/contracts.rb`, `README.md`, `sdk/README.md`, `docs/docs/contracts.mdx`, `docs/docs/intro.mdx`, `docs/docs/smart-account.mdx`.

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos no desktop; sintaxe Python (`ast.parse`)/Ruby (`ruby -c`) ok nos SDKs; `docs && npm run build` limpo (sem links quebrados, `onBrokenLinks: 'throw'`). Dart não verificado nesta sessão (mudança é troca trivial de literais, mesmo risco baixo já aceito na Sessão 62; mobile só roda via Docker neste PC).

- **Débitos**: nenhum novo. Débito #34 (tabela de Débitos Técnicos) e a linha #3 da tabela de Pendências de Deploy marcados como resolvidos.
- **Próximo passo**: débitos #35–#43 (achados do `/code-review high` da Sessão 75, ver tabela de Débitos Técnicos) ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 78 — 2026-07-06: Débito #33 — updateVault roteado pela smart account

- **Objetivo**: resolver o débito #33 — `VaultManagement.tsx` disparava `updateVault` direto pela wallet conectada (Ledger/EOA) em vez de rotear via `TruthIDAccount.execute()` contra a smart account, o que reverteria (`NotIdentityController`) assim que o `VaultRegistry` fosse deployado e alguém clicasse em "Enviar".

- **Fix**: `desktop/src/components/VaultManagement.tsx` — `smartAccountAddress` desestruturado de `useIdentity()`; o `useEffect` que dispara `updateVault` depois do `vault_publish` agora chama `writeContract({ address: smartAccountAddress, abi: TRUTHID_ACCOUNT_ABI, functionName: "execute", args: [VAULT_REGISTRY_ADDRESS, 0n, calldata] })`, com `calldata` de `updateVault` via `encodeFunctionData` — mesmo padrão já usado em `WithdrawModal.tsx`/`PairDevice.tsx`. Guard novo `if (!smartAccountAddress) return`.

- **Auditoria do resto do fluxo do Vault (13.1–13.7)**, pedida pelo próprio débito #33 antes de destravar 13.8/13.9: `VaultManagement.tsx` tem uma única chamada `useWriteContract`/on-chain (a que foi corrigida); `VaultSettings.tsx` só mexe com config local de providers de pinning, sem nenhuma chamada on-chain. Nenhuma outra instância do mesmo bug encontrada.

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos no desktop. Sem teste dedicado pra `VaultManagement.tsx` hoje, então nada precisou de atualização de mock. Sem verificação e2e on-chain possível ainda — `VaultRegistry` continua não deployado (`VAULT_REGISTRY_ADDRESS` = placeholder `0x00...00`).

- **Débitos**: nenhum novo. Débito #33 marcado como resolvido na tabela de Débitos Técnicos.
- **Próximo passo**: débitos #35–#43, ou avançar a Fase 13 (13.8/13.9) — nada mais bloqueia essas etapas do lado do bug do controller.

---

### Sessão 79 — 2026-07-06: Débito #35 — mismatch de nomenclatura no toggle de permissão do Vault

- **Objetivo**: resolver o débito #35 — o toggle "Pode escrever"/"Só leitura" por device no Vault nunca funcionava de verdade, por causa de um mismatch de convenção Rust↔JS no Tauri.

- **Causa**: `handleTogglePerm` chamava `invoke("vault_set_device_permission", { pub_key: pubKey, can_write: canWrite })` (snake_case), mas o Tauri converte por padrão os parâmetros do Rust (`pub_key`, `can_write`) pra camelCase do lado do JS — mesma convenção já usada em `get_ledger_address(account_index)` → `invoke(..., { accountIndex })` no próprio arquivo. A chamada com as chaves erradas falhava silenciosamente porque o `catch` estava vazio; o estado local (`permissions`) era atualizado de forma otimista mesmo com a falha, então a UI parecia responder ao clique sem persistir nada.

- **Fix**: `desktop/src/components/VaultManagement.tsx` — `invoke` corrigido pra `{ pubKey, canWrite }`; novo estado `permError` (mesmo padrão do `mutateError` já usado nas entradas do vault), setado no `catch` e exibido como `<p className="error-text">` dentro do painel "Permissões por device".

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos. Sem teste dedicado pra esse componente hoje.

- **Débitos**: nenhum novo. Débito #35 marcado como resolvido.
- **Próximo passo**: débitos #36–#43, ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 80 — 2026-07-06: Débito #36 — falha parcial de pinning tratada como sucesso total

- **Objetivo**: resolver o débito #36 — `handleEnviar` (`VaultManagement.tsx`) só considerava erro quando **todos** os provedores de pin falhavam; falha parcial (ex: 1 de 2 provedores) seguia como sucesso silencioso, sem avisar que a redundância de pinning configurada foi perdida naquela publicação.

- **Fix**: novo estado `pinWarning`. Depois do `vault_publish`, se `providers_failed.length > 0` (mesmo com `providers_ok` não-vazio), monta uma mensagem listando quais provedores falharam/tiveram sucesso e segue a publicação normalmente (não bloqueia — pelo menos 1 provedor teve sucesso). A mensagem aparece como aviso não-bloqueante (`⚠`, cor âmbar `#d9a441` — não havia uma cor de "warning" no design system atual, só `--color-danger`/`--color-success`, então usei um hex ad-hoc como já se faz em `VaultSettings.tsx` pro ✓ verde) logo abaixo do bloco de erro de publicação.

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos. Sem teste dedicado pra esse componente hoje.

- **Débitos**: nenhum novo. Débito #36 marcado como resolvido.
- **Próximo passo**: débitos #37–#43, ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 81 — 2026-07-06: Débito #37 — healthStatus desalinhado após remover provider

- **Objetivo**: resolver o débito #37 — `handleRemove` (`VaultSettings.tsx`) apagava só a entrada do índice removido em `healthStatus` (indexado por posição no array `providers`), sem reindexar os providers seguintes. Remover um provider do meio da lista deixava o indicador ✓/✗ de saúde associado ao provider errado.

- **Fix**: `handleRemove` agora chama `setHealthStatus({})` em vez de tentar apagar só a chave removida — limpa tudo e força um novo health-check na próxima vez que o usuário clicar "Testar". Mais simples que introduzir um identificador estável (`PinningProvider` não tem `id` hoje, só `name`/`kind`/`endpoint_url`/`api_key`), e evita edge case de colisão se dois providers compartilharem o mesmo `endpoint_url`.

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos. Sem teste dedicado pra esse componente hoje.

- **Débitos**: nenhum novo. Débito #37 marcado como resolvido.
- **Próximo passo**: débitos #38–#43, ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 82 — 2026-07-06: Débito #38 — updateEntry silencioso quando id não existe (mobile)

- **Objetivo**: resolver o débito #38 — `VaultRepository.updateEntry` (mobile) não verificava se o id informado existia antes de salvar; um id inexistente/obsoleto virava um no-op silencioso que ainda incrementava `version` e devolvia a entrada como se tivesse sido atualizada de verdade. A implementação irmã em Rust (`desktop/src-tauri/src/vault.rs::upsert`) trata esse caso inserindo como nova entrada; o port Dart descartou esse tratamento ao separar `addEntry`/`updateEntry` em vez de um `upsert` único.

- **Decisão**: lançar exceção em vez de replicar o comportamento "insere como nova" do Rust — como o Dart já expõe `addEntry` separado, chamar `updateEntry` com um id que não existe é um erro de uso do chamador, não uma criação implícita. Mantém a API dos dois lados com uma semântica levemente diferente (motivada pela própria diferença de shape entre `upsert` único vs. `add`/`update` separados), documentado aqui para não ser confundido com inconsistência acidental.

- **Fix**: `mobile/lib/services/vault_repository.dart::updateEntry` — checa `data.entries.any((e) => e.id == entry.id)` antes de prosseguir; lança `Exception('Vault entry not found: ${entry.id}')` se não encontrar, seguindo a convenção `throw Exception(...)` já usada no resto do mobile (`vault_key_service.dart`, `blockchain_service.dart`, etc.).

- **Teste novo**: `mobile/test/services/vault_repository_test.dart` — `updateEntry — lança quando id não existe`, verifica o throw e que a lista de entradas continua com o tamanho original (sem virar insert acidental).

- **Verificação**: sem `flutter`/`dart` instalados neste PC — rodado via `docker compose run --rm flutter sh -c "flutter test ..."` (15/15 passando) e `flutter analyze` (0 erros; 5 avisos pré-existentes de outro arquivo/linhas não tocadas, mesmos já vistos na Sessão 76).

- **Débitos**: nenhum novo. Débito #38 marcado como resolvido.
- **Próximo passo**: débitos #39–#43, ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 83 — 2026-07-06: Débito #39 — useEffect do updateVault não reagia à conexão da wallet

- **Objetivo**: resolver o débito #39 — o `useEffect` que dispara `updateVault` (mesmo efeito mexido no débito #33) só dependia de `[pendingUpdate]`. Se a wallet não estivesse conectada quando o efeito rodava, ele abria o modal de conexão e retornava sem chamar `writeContract`, mas conectar a wallet depois não reexecutava o efeito sozinho (só clicando "Enviar" de novo, o que republicava no IPFS à toa).

- **Fix**: `isConnected` e `smartAccountAddress` adicionados ao array de dependências do efeito. Quando `isConnected` vira `true` com `pendingUpdate` ainda setado, o efeito reexecuta sozinho e prossegue. Não incluí `writeContract`/`openConnectModal` nas deps — são referências de função potencialmente instáveis entre renders, e incluí-las arriscaria reabrir o modal de conexão repetidamente enquanto a wallet ainda está desconectada. Sem risco de disparo duplicado do `writeContract`: o guard `if (!pendingUpdate) return` já barra qualquer reexecução depois que `setPendingUpdate(null)` roda.

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos.

- **Débitos**: nenhum novo. Débito #39 marcado como resolvido.
- **Próximo passo**: débitos #40–#43, ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 84 — 2026-07-06: Débito #40 — formulário de provider PSA sem api_key obrigatória

- **Objetivo**: resolver o débito #40 — `handleFormAdd` (`VaultSettings.tsx`) só exigia `name`/`endpoint_url` preenchidos, mesmo pra provedores `kind === "psa"`, que sem `api_key` não funcionam de verdade (falhariam só na hora de publicar o vault, com 401/403).

- **Fix**: nova variável `formInvalid` (`!name.trim() || !endpoint_url.trim() || (kind === "psa" && !api_key.trim())`), usada tanto no guard do `handleFormAdd` quanto no `disabled` do botão "Adicionar" — antes as duas checagens estavam duplicadas inline, arriscando divergir; agora é uma fonte só.

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos.

- **Débitos**: nenhum novo. Débito #40 marcado como resolvido.
- **Próximo passo**: débitos #41–#43, ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 85 — 2026-07-06: Débito #41 — VaultRegistry não validava contentHash zerado

- **Objetivo**: resolver o débito #41 — `updateVault` validava `cid` não-vazio mas nunca validava `contentHash != bytes32(0)`, apesar do comentário do struct `VaultRef` dizer que esse campo existe pra verificação de integridade.

- **Fix**: `contracts/src/VaultRegistry.sol` — novo erro `EmptyContentHash()`; `updateVault` ganhou `if (contentHash == bytes32(0)) revert EmptyContentHash();`, logo depois do `EmptyCid()` já existente (mesmo padrão).

- **Teste novo**: `contracts/test/VaultRegistry.t.sol::test_Revert_UpdateVault_ContentHashVazio`, espelhando `test_Revert_UpdateVault_CidVazio`.

- **Verificação**: `forge test` — 213/213 (era 212, +1 novo). Sem necessidade de redeploy: `VaultRegistry` ainda não foi deployado em nenhuma rede (feature não lançada).

- **Débitos**: nenhum novo. Débito #41 marcado como resolvido.
- **Próximo passo**: débitos #42–#43, ou avançar a Fase 13 (13.8/13.9).

---

### Sessão 86 — 2026-07-06: Débito #42 — extrai `IdentityResolver` compartilhado + accessor mais barato (planejado via Plan Mode)

- **Objetivo**: resolver o débito #42 — `_getCallerIdentityId()` era cópia byte-a-byte em `DeviceRegistry.sol`, `SessionRegistry.sol` e `VaultRegistry.sol` (mesmo campo `_identityRegistry`, mesmo erro `NotIdentityController`, 2 chamadas externas + cópia do struct `Identity` inteiro só pra extrair o `id`). Planejado em Plan Mode (dado o impacto em contratos já deployados) antes de implementar.

- **Investigação prévia**: confirmado que `_identityRegistry` só é usado dentro de `_getCallerIdentityId()` nos 3 contratos (seguro extrair). `RecoveryManager.sol` tem um campo parecido mas usa de forma bem diferente (recebe `username` como parâmetro, nunca resolve a partir de `msg.sender`) — **fica fora de escopo**, não é o mesmo padrão. Não existe herança em `contracts/src/` hoje — este é o primeiro uso.

- **Decisão de escopo (usuário)**: implementar o refactor completo, incluindo um accessor novo no `IdentityRegistry` (`getIdentityIdByController`) que resolve com 1 chamada externa em vez de 2 — aceitando que isso muda o bytecode de `IdentityRegistry`/`DeviceRegistry`/`SessionRegistry` (já deployados desde a Sessão 77) e portanto vai exigir outra cascata de redeploy dos 5 contratos no futuro (não feita nesta sessão — ver Pendências de Deploy, item #4).

- **Novo arquivo `contracts/src/IdentityResolver.sol`**: `abstract contract` com o campo `_identityRegistry` (private, immutable), o erro `NotIdentityController`, o constructor, e `_getCallerIdentityId()` reescrito pra usar o accessor novo (1 chamada externa).

- **`contracts/src/IdentityRegistry.sol`**: novo `getIdentityIdByController(address) returns (uint256)` — encadeia as duas mappings existentes (`_usernameByController` → `_identityByUsername`) internamente, retorna `0` se não encontrado (mesma convenção "soft not-found" de `getUsernameByController`, sem reverter; seguro porque ids reais nunca são `0`).

- **`DeviceRegistry.sol`/`SessionRegistry.sol`/`VaultRegistry.sol`**: ganharam `is IdentityResolver`; campo `_identityRegistry`, erro `NotIdentityController` e a função `_getCallerIdentityId()` duplicados foram removidos (agora herdados); constructors encadeiam pra `IdentityResolver(identityRegistry)`, mantendo a assinatura externa idêntica (testes que constroem via `new X(...)` não precisaram mudar nesse ponto).

- **Achado durante a implementação**: `vm.expectRevert(DeviceRegistry.NotIdentityController.selector)` (e o equivalente em `SessionRegistry`/`VaultRegistry`) **não compilou** depois do erro virar herdado — Solidity não expõe erros do contrato-base através do nome do contrato derivado nesse contexto (`Member "NotIdentityController" not found`). Corrigido trocando as 7 referências (3 em `DeviceRegistry.t.sol`, 3 em `SessionRegistry.t.sol`, 1 em `VaultRegistry.t.sol`) para `IdentityResolver.NotIdentityController.selector`, com o import correspondente adicionado nos 3 arquivos de teste. `RecoveryManager.t.sol` não foi tocado (usa seu próprio `RecoveryManager.NotIdentityController`, contrato fora de escopo).

- **Teste novo**: `contracts/test/IdentityRegistry.t.sol` — `test_GetIdentityIdByController_Success` e `test_GetIdentityIdByController_ReturnsZeroWhenNotFound`.

- **Gas medido de verdade (antes/depois via `git stash`, não estimado)** — `forge test --gas-report`, mesmo filtro de contratos nas duas medições:

  | Função | Antes (min/mediana/max) | Depois | Δ mediana |
  |---|---|---|---|
  | `registerDevice` | 23.757 / 205.761 / 229.010 | 23.757 / 195.037 / 218.286 | -10.724 |
  | `revokeDevice` | 24.411 / 51.490 / 51.490 | 24.411 / 40.767 / 40.767 | -10.723 |
  | `revokeSession` | 24.501 / 53.880 / 56.224 | 24.501 / 43.157 / 45.501 | -10.723 |
  | `revokeAllSessions` | 28.694 / 65.169 / 65.169 | 27.961 / 54.446 / 54.446 | -10.723 |
  | `updateVault` | 22.584 / 209.444 / 292.697 | 22.584 / 201.139 / 281.973 | -10.724 |

  Redução consistente de ~10,7k gas por chamada nas 5 funções (1 chamada externa a menos + sem copiar a string `username` do struct `Identity`). Pegadinha na medição: `git stash` não inclui arquivo novo não-trackeado (`IdentityResolver.sol`) — precisei mover o arquivo manualmente pra fora da pasta antes de medir o "antes", senão o `IdentityResolver.sol` ficava presente chamando uma função (`getIdentityIdByController`) que não existia no `IdentityRegistry.sol` restaurado pelo stash, e o build quebrava.

- **`docs/docs/contracts.mdx`**: tabela "Cost per operation" atualizada com os 4 números novos (`registerDevice`/`revokeDevice`/`revokeSession`/`revokeAllSessions`); frase sobre "a operação mais pesada" atualizada de `~204k gas`/`0.0000022 ETH` pra `~195k gas`/`0.0000021 ETH`. De brinde, a contagem "120 tests" citada no mesmo parágrafo estava desatualizada (hoje são 140, incluindo os 2 novos desta sessão) — corrigida também, já que a convenção do projeto é nunca deixar número estimado/desatualizado no lugar de um medido.

- **Verificação**: `forge build`/`forge test` — 215/215 (era 213, +2). `docs && npm run build` — limpo, sem links quebrados.

- **Débitos**: nenhum novo. Débito #42 marcado como **resolvido (código)** — deploy fica pendente (Pendências de Deploy, item #4, cascata completa dos 5 contratos, mesmo formato de #34/Sessão 77).
- **Próximo passo**: débito #43 (extrair hook `useVaultPublish` do `VaultManagement.tsx`), ou decidir quando fazer o redeploy em cascata pendente do débito #42.

---

### Sessão 87 — 2026-07-06: Débito #43 — extrai `useVaultPublish` do `VaultManagement.tsx`

- **Objetivo**: resolver o débito #43, o último da leva de achados do `/code-review high` da Sessão 75 — a máquina de estados de publicação do vault (estado local + leituras on-chain + `updateVault` via smart account) vivia inline no componente de UI, diferente do padrão já usado em `useSmartAccountActivity.ts`.

- **Novo `desktop/src/hooks/useVaultPublish.ts`**: recebe `pendingCount` (contagem de mudanças locais pendentes, que continua vivendo no componente — vem do `vault_pending_changes` do Rust, junto com entradas e permissões) e um callback `onPublished` (chamado quando a tx confirma, pra o componente zerar `pendingCount`). Internamente chama `useIdentity()`/`useAccount()`/`useWalletModal()` direto (mesmo padrão de outros hooks do repo, sem precisar prop-drilling) e concentra: os estados `publishState`/`publishError`/`pinWarning`/`pendingUpdate`/`justPublished`; os reads `hasVault`/`getVault`; os 2 `useEffect` (dispara `execute()` na smart account quando `vault_publish` retorna, e trata a confirmação da tx); `handleEnviar`; e o cálculo do label do botão. Retorna um objeto flat (`hasVault`, `vaultRef`, `publishError`, `pinWarning`, `txErrorMessage`, `buttonLabel`, `buttonDisabled`, `handleEnviar`) — `buttonDisabled`/`txErrorMessage` substituem checagens que antes ficavam espalhadas na JSX (`publishState === "error" && publishError`, `isTxError && txError`), sem mudar o comportamento (a lógica das 2 é logicamente equivalente às condições antigas).

- **`VaultManagement.tsx`**: caiu de 743 para 632 linhas. Removidos os imports que só serviam pro publish (`useWriteContract`, `useWaitForTransactionReceipt`, `encodeFunctionData`, `VAULT_REGISTRY_ADDRESS`/`ABI`, `TRUTHID_ACCOUNT_ABI`, `PinResult`) e `smartAccountAddress` do destructure de `useIdentity()` (só era usado dentro do bloco extraído). O componente principal agora só chama `useVaultPublish(pendingCount, () => setPendingCount(0))` e usa o objeto retornado na JSX.

- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos. Sem teste dedicado pro hook ainda (nenhum dos dois arquivos tinha teste antes; escopo do débito era só a extração estrutural).

- **Débitos**: nenhum novo. Débito #43 marcado como resolvido — **fecha a leva inteira de achados do `/code-review high` da Sessão 75** (débitos #33 a #43, todos resolvidos entre as Sessões 78-87).
- **Próximo passo**: Fase 13 (13.8/13.9 — UI mobile de leitura do vault + extensão de navegador), ou decidir quando fazer o redeploy em cascata pendente do débito #42.

---

### Sessão 88 — 2026-07-06: Redeploy em cascata (débito #42) + primeiro deploy do `VaultRegistry` (item #2 de Pendências de Deploy)

- **Objetivo**: fechar as duas pendências de deploy acumuladas — a cascata do débito #42 (`IdentityResolver` compartilhado mudou o bytecode de `DeviceRegistry`/`SessionRegistry`, que arrasta `RecoveryManager`/`TruthIDAccountFactory` por causa dos endereços `immutable`) e o primeiro deploy do `VaultRegistry` (feature completa desde a Sessão 87, mas nunca deployada — endereço ainda era `0x00...00`).

- **Pré-checagens**: `forge test` 215/215 antes do deploy. `totalIdentities()` **0** nas duas redes (Sepolia e Mainnet) nos `IdentityRegistry` então-atuais — redeploy sem risco de orfanar identidade real. Endereço da Ledger confirmado via `cast wallet address --ledger --mnemonic-derivation-path "m/44'/60'/1'/0/0"` (`0xB54fe9909D76d98e87a9fD76bDB5C69fABe10265`, mesmo deployer das sessões anteriores) antes de qualquer broadcast. Simulação (`forge script` sem `--broadcast`) rodada em cada rede antes do broadcast real, mostrando custo estimado.

- **Deploy via Ledger física**, Sepolia primeiro, depois Mainnet: `Deploy.s.sol` (`IdentityRegistry` → `DeviceRegistry` → `RecoveryManager` → `TruthIDAccountFactory`) → `DeploySessionRegistry.s.sol` → `DeployVaultRegistry.s.sol` (novo, primeira vez rodado de verdade). No Mainnet, a 1ª tentativa do `VaultRegistry` falhou por rejeição acidental na Ledger (`APDU_CODE_CONDITIONS_NOT_SATISFIED`) — o `SessionRegistry` já tinha confirmado antes disso; reexecutar o script sozinho (sem repetir os passos anteriores) resolveu, reconsultando o nonce on-chain corretamente.

**Endereços novos**:

| Contrato | Sepolia | Mainnet |
|---|---|---|
| IdentityRegistry | `0x7582E1c55fAFF19619A6c0a8b6575855d4e933d0` | `0xC11426fd1cB103bC56dD3263325b34f2AcEe9903` |
| DeviceRegistry | `0x867EA636FDF324B0Cc4a631C70421580e2Bbe91c` | `0x4Fd53d70553df00D42c015EB35E2626cB80b1614` |
| RecoveryManager | `0xC60AE3D7Fc7991A48B780E3bF2838027079204Ce` | `0x1d51daD35Bd3562f8B56B334a9B8637873fE40e9` |
| TruthIDAccountFactory | `0x490A82AD72705fA92e0BBc0Dc5A894883fE90a9E` | `0x6b1a78656510f734c7072040000A428e125C50df` |
| SessionRegistry | `0xFE49Cec3a927136f7F18E521BF1547f00b09B17f` | `0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df` |
| VaultRegistry (novo) | `0x27E9288F06C42664812a1819235776D801Fd7Cf1` | `0x602Fa39611960e5ef17D95a5d7b16816eE0ff734` |

Custo real: ~0.00015 ETH nas duas redes combinadas. `totalIdentities()` e `factory.deviceRegistry()` conferidos on-chain nas duas redes após o deploy.

- **Propagação dos endereços** (mesmo escopo das Sessões 70/77): `desktop/src/config/contracts.ts` (5 endereços + `DEVICE_REGISTRY_DEPLOY_BLOCK`/`SESSION_REGISTRY_DEPLOY_BLOCK`/`VAULT_REGISTRY_DEPLOY_BLOCK` novo, blocos extraídos dos artefatos de broadcast), `desktop/src/config/truthidAccount.ts` (factory + `FACTORY_IMMUTABLES`, comentário de Sepolia), `mobile/lib/services/blockchain_service.dart`, `sdk/typescript/src/contracts.ts`, `sdk/python/truthid/contracts.py`, `sdk/ruby/lib/truthid/contracts.rb`, `README.md`, `sdk/README.md`, `docs/docs/contracts.mdx`, `docs/docs/intro.mdx`, `docs/docs/smart-account.mdx`.

- **Cleanup habilitado pelo `VaultRegistry` deixar de ser placeholder**: `VAULT_REGISTRY_ADDRESS` deixou de ser o zero address, então o `VAULT_DEPLOYED`/`ZERO_ADDRESS` feature-flag em `SmartAccountDashboard.tsx` (branch "Not available yet" do bucket Vault) e em `scanSmartAccountActivity.ts` (que pulava o evento `VaultUpdated` inteiramente) pararam de fazer sentido — o TypeScript inclusive passou a reclamar (`This comparison appears to be unintentional`, já que o literal do endereço não é mais comparável ao zero address). Ambos simplificados para tratar o Vault incondicionalmente, igual a Session/Device. Testes atualizados: `scanSmartAccountActivity.test.ts` (o teste que checava "pula VaultUpdated" virou "escaneia todos os 6 event sources") e `SmartAccountDashboard.test.tsx` (o teste de "Not available yet" virou um teste de soma do bucket vault, espelhando o teste já existente pra session/device).

- **Verificação**: `tsc --noEmit`/`vitest` (47/47) limpos no desktop; `forge test` 215/215; sintaxe Python (`ast.parse`)/Ruby (`ruby -c`) ok; `docs && npm run build` limpo. `flutter analyze` via Docker — mesmos 5 avisos pré-existentes, nenhum novo. `flutter test` via Docker — 85/90 passam; os 5 testes de `vault_key_service_test.dart` falham com `Binding has not yet been initialized` (erro do `flutter_secure_storage` sem `TestWidgetsFlutterBinding.ensureInitialized()`) — **confirmado pré-existente**, não relacionado a esta sessão (reproduzido isoladamente revertendo só a mudança do `blockchain_service.dart`, mesma falha). Não corrigido nesta sessão, registrado como observação para investigar depois (não numerado como débito ainda).

- **Débitos**: nenhum novo. Débito #42 (tabela de Débitos Técnicos) e as linhas #2/#4 da tabela de Pendências de Deploy marcados como resolvidos.
- **Próximo passo**: Fase 13 (13.8/13.9 — UI mobile de leitura do vault + extensão de navegador), agora destravada com o `VaultRegistry` deployado nas duas redes. Opcionalmente investigar a falha pré-existente do `vault_key_service_test.dart` isolado.

---

### Sessão 89 — 2026-07-06: 13.8 — UI Mobile do Vault (leitura) + tela de perfil pra scan da extensão

- **Objetivo**: implementar a 13.8 — dar ao mobile uma forma de ler o Vault, e uma tela que prepara o terreno pro scan do QR da extensão (13.9). Planejado via Plan Mode antes de implementar, dado o escopo maior que o nome da etapa sugeria.

- **Gap descoberto na pesquisa (Explore + Plan agents)**: o `vault.enc` local do mobile nunca era populado com conteúdo real — o vault publicado só existe cifrado no IPFS, referenciado on-chain por `{cid, contentHash, updatedAt, version}` no `VaultRegistry`. O mobile não tinha nenhum código pra ler esse contrato, baixar do IPFS, ou verificar hash. A 13.8 precisou de um pipeline de sync completo, não só uma UI em cima do repositório já existente.

- **`mobile/lib/services/blockchain_service.dart`**: novo `VaultRef` (cid/contentHashHex/updatedAt/version) + `hasVault(BigInt)`/`getVault(BigInt)`, decodificação manual (selector via keccak256, encode/decode por offset fixo) — mesmo padrão de `getIdentityByUsername` (débito #32): `VaultRef.cid` é o campo dinâmico do struct de retorno, então `ContractFunction`/`ContractAbi.fromJson` do web3dart não é confiável aqui. `getVault` reverte (`VaultNotFound`) se não existir vault — confirmado lendo `VaultRegistry.sol` antes de implementar; `hasVault` é o único seguro pra chamar especulativamente.

- **`mobile/lib/services/ipfs_gateway_client.dart`** (novo): `IpfsGatewayClient.fetch(cid)` tenta gateways públicos em ordem (`ipfs.io`, `dweb.link`, injetáveis via construtor), leitura binária via `consolidateHttpClientResponseBytes` (`package:flutter/foundation.dart` — não `services.dart` como o plano original supôs; corrigido durante o `flutter analyze`).

- **`mobile/lib/services/vault_repository.dart`**: novo `overwriteCache(Uint8List)` — grava um blob já cifrado vindo de fora (do sync) sem recifrar nada, reusando `_vaultPath()` já existente.

- **`mobile/lib/services/vault_sync_service.dart`** (novo): `VaultSyncService.sync(identityId)` orquestra hasVaultKey (checagem local, sem rede) → hasVault → getVault → download IPFS → verifica `keccak256(bytes)` contra o `contentHash` on-chain → decifra. **Hash não bate nunca é tratado como sucesso** — cai pro fallback de cache local (`VaultSyncStatus.offlineUsingCache` se há cache, `syncFailedNoCache` se não há). Mesmo fallback pra qualquer falha de rede.

- **`mobile/lib/constants/vault_profiles.dart`** (novo): `kVaultProfiles = ['Trabalho', 'Casa', 'Pessoal']`, paridade exata com `desktop/src/components/VaultManagement.tsx`.

- **`mobile/lib/widgets/info_row.dart`** (novo): `InfoRow` extraído do `_InfoRow` privado de `approval_screen.dart`, reusado pelas telas novas abaixo.

- **`mobile/lib/screens/vault_screen.dart`** (novo, 4ª aba): leitura + busca por site/usuário/perfil, estados de loading/not-paired/noVaultPublished/noVaultKey/syncFailedNoCache/offlineUsingCache/synced, senha sempre mostrada como `'••••••••'` fixo (não derivado do tamanho real). `mobile/lib/screens/vault_entry_detail_screen.dart` (novo): detalhe com reveal/copy, sem chamada de rede (entrada já em memória).

- **`mobile/lib/main.dart`**: `VaultScreen` como 4ª aba (bottom nav rebalanceado de 2+gap+1 pra 2+gap+2); novo case `'truthid-vault-session'` no dispatch do `_openScanner()`.

- **`mobile/lib/screens/vault_session_screen.dart`** (novo): scan → mostra `sessionId` (payload provisório, `{action, sessionId}` — o protocolo real é escopo da 13.9) → escolhe perfil (`kVaultProfiles`) → mostra contagem de entradas compatíveis (via `VaultSyncService` reusado) → termina em estado explícito **"Not available yet"** (depende da extensão, 13.9) — decisão confirmada com o usuário via AskUserQuestion durante o planejamento, ao invés de fingir sucesso ou adiar a tela inteira.

- **Verificação**: `flutter analyze` via Docker — 0 erros novos (só os 5 avisos pré-existentes de sempre). `flutter test` via Docker — só as mesmas 5 falhas pré-existentes de `vault_key_service_test.dart` (não relacionadas, já confirmadas na Sessão 88); todos os testes novos passam: `vault_sync_service_test.dart` (9 casos, incluindo os pares red/green do mismatch de hash com/sem cache prévio — o caminho de segurança mais importante desta sessão), `ipfs_gateway_client_test.dart` (fallback entre gateways via `HttpServer` local), `vault_screen_test.dart`, `vault_entry_detail_screen_test.dart`, `vault_session_screen_test.dart`, e um teste novo de `overwriteCache` em `vault_repository_test.dart`. `approval_screen_test.dart` continua passando após a extração do `InfoRow` (mudança transparente).

- **Débitos**: nenhum novo.
- **Próximo passo**: 13.9 (extensão de navegador — sessão efêmera, autofill, revogação em cascata), última etapa da Fase 13. Opcionalmente investigar a falha pré-existente do `vault_key_service_test.dart` isolado (mencionada desde a Sessão 88, ainda não corrigida).

---

### Sessão 90 — 2026-07-06/07: Teste manual E2E da 13.8 em hardware real (celular físico + Ledger + Base Mainnet) — vários problemas reais achados e corrigidos pelo caminho

- **Objetivo**: validar a 13.8 de ponta a ponta com dados reais — não só testes automatizados. Fluxo completo: parear um celular Android físico, publicar um vault de teste pelo Desktop (Ledger + Base Mainnet real), e confirmar que o mobile lê e decifra corretamente. Sessão longa, cheia de obstáculos de ambiente e alguns bugs reais — registrado em detalhe a pedido do dono do projeto.

#### Ambiente (antes de qualquer teste funcional)

1. **`~/.truthid` era dono de `root`** (sobra de alguma sessão anterior rodada como root) — bloquearia o Desktop de gravar `vault.enc`/permissões/config de pin. Corrigido com `sudo chown -R masterlxz:masterlxz ~/.truthid`.
2. **`desktop/node_modules/.vite` também era dono de `root`** — o `npm run tauri dev` falhava no `vite` com `EACCES: permission denied, unlink .../.vite/deps/@tanstack_react-query.js` antes mesmo de compilar o Rust. Mesmo tipo de correção (`chown -R`).
3. **Faltava o pacote de sistema `webkit2gtk-4.1`** (motor de webview do Tauri no Linux) — `cargo build` falhava em `javascriptcore-rs-sys` com `pkg-config` não encontrando `javascriptcoregtk-4.1.pc`. Instalado via `pacman`. Depois disso, o Tauri compilou limpo (638 crates, ~2min12s a primeira vez).
4. **Celular físico não aparecia nem no `lsusb`** a princípio (cabo/modo USB errado — precisou trocar pra "Transferência de arquivos"/MTP). Depois de aparecer no `lsusb`, o `adb devices` continuava vazio — faltava (a) o pacote `android-tools` (fornece `adb`, não vinha instalado) e (b) uma regra `udev` pra dar permissão de acesso ao device (Arch não vem com uma por padrão) — criada `/etc/udev/rules.d/51-android.rules` (`SUBSYSTEM=="usb", ATTR{idVendor}=="04e8", MODE="0666", TAG+="uaccess"`, mesmo padrão do `99-ledger.rules` já existente no repo pra Ledger). Só depois disso, com "Depuração USB" ativada nas Opções do desenvolvedor do celular, o `adb devices` finalmente reconheceu o aparelho.
5. Sem passthrough USB configurado no `mobile/docker-compose.yml`, o `adb` só funciona no **host**, não dentro do container Flutter — build do APK continuou via `docker compose run --rm flutter flutter build apk --debug` (bind mount já deixa o artefato acessível no host), instalação via `adb install -r` direto no host.

#### Bug real #1 — bottom nav de 4 abas estourava a tela (achado só em aparelho real)

Print do celular real mostrou `RIGHT OVERFLOWED BY 18 PIXELS` na aba Vault recém-adicionada — o layout antigo (`mainAxisAlignment: spaceAround`, larguras intrínsecas) não sobrava espaço pra 4 abas + o vão do FAB. Primeira correção (envolver cada aba em `Expanded`) resolveu o overflow horizontal mas **causou um novo**: `BOTTOM OVERFLOWED BY 12 PIXELS` embaixo de "Devices"/"Sessions" — com a largura de cada aba agora dividida igualmente entre 4, o texto "Sessions"/"Devices" (mais longos que "Wallet"/"Vault") quebrava pra 2 linhas dentro do padding de 20px de cada lado, estourando a altura fixa da barra. Corrigido reduzindo o padding horizontal de `_NavTab` (20→4) e adicionando `maxLines: 1, overflow: TextOverflow.ellipsis` no texto — só percebido rodando de verdade num Galaxy físico (nenhum teste widget pega isso, já que os testes não simulam a largura real de tela).

#### Bug real #2 — `CreateIdentity.tsx` sem retry após falha de nonce (débito #44, corrigido na Sessão 91)

Ao criar a identidade `masterlxz` pela primeira vez no Desktop, a etapa "Deploying smart account" (tx 2 de 4) falhou com `Error: Nonce provided for the transaction is lower than the current nonce of the account` — provavelmente porque a Ledger tinha acabado de assinar uma dúzia de transações fora do app (o redeploy em cascata das Sessões 88/89) minutos antes, e o wagmi tinha um nonce em cache desatualizado. **O componente não tem nenhum caminho de retry**: os refs `tx2Submitted`/`tx3Submitted` nunca resetam, e recarregar a página faz o `existingUsername` (já `true`, a tx1 tinha confirmado) esconder o problema atrás de "Identity already registered" — sem nunca deployar/financiar a smart account. Diagnosticado via `cast call getIdentity("masterlxz")` (identidade existe, controller = endereço CREATE2 previsto) + `cast code`/`cast balance` nesse endereço (ambos vazios/zero). **Contornado manualmente**: `cast send factory "createAccount(address,uint256)" <ledger> 0 --ledger` seguido de `cast send <smart-account> --value 0.001ether --gas-limit 30000 --ledger` — confirmado depois via `cast code`/`cast balance` que a conta passou a ter bytecode e saldo. Registrado como débito #44, não corrigido no código ainda.

#### Bug real #3 — Ledger travava de vez (débito #45, corrigido)

Na tela "Unlock Vault" (assinatura RFC 6979 pra derivar a vault key), a assinatura falhou com `Error: An unknown RPC error occurred. Details: locked Version: viem@2.52.2` — e a partir daí o botão "Confirm signature on wallet..." ficou permanentemente desabilitado, sem forma de tentar de novo. Matar e reabrir o app (`pkill`+`npm run tauri dev` de novo) levou pra tela "Select account", mas o botão "Connecting..." também travou — **e continuou travado através de vários restarts completos do app, e mesmo depois de desconectar/reconectar fisicamente o cabo USB da Ledger e reabrir manualmente o app Ethereum nela**. Investigação do código (`ledger.rs` + `ConnectLedger.tsx`) achou dois problemas reais: (a) `device.write()` no lado Rust não tem timeout (só `read_timeout`, 5s, tem) — uma escrita que trave nunca retorna; (b) `ConnectLedger.tsx` não tem nenhum guard contra chamadas HID concorrentes (o polling de detecção a cada 1s, a listagem sequencial de 5 contas, e o clique em "Connect" podiam se sobrepor) — mesma classe de bug já resolvida antes em `CreateIdentity.tsx`, mas nunca replicada aqui. **Corrigido**: novo `hidBusyRef` (garante no máximo 1 chamada HID em voo) + novo `withTimeout()` (8s) envolvendo todo `invoke()`/`connectAsync()`, liberando o botão pra tentar de novo mesmo que o lado Rust nunca responda. `tsc --noEmit`/`vitest` (47/47) limpos. Depois da correção + mais um restart do app, a reconexão funcionou (com um pequeno atraso de UI pra refletir o estado conectado, não travando mais).

#### Pareamento do celular

Funcionou via "+ Add device" no Desktop → "Show QR to pair" no celular. A tela de Devices do Desktop não atualizou sozinha depois (mesmo padrão de "sem refetch automático" já visto antes nesta fase) — precisou clicar no ícone de refresh (⟲) manualmente pra mostrar "cellphone ✓ Active". Pareamento confirmado on-chain via `cast call getDevice(...)` antes mesmo do refresh da UI.

#### Configuração do Kubo — CORS ausente do guia do próprio app (débito #46, corrigido na Sessão 91)

Escolhido Kubo local (self-hosted) como provedor de pin. Instalado via `pacman -S kubo`, `ipfs init` + `ipfs daemon` seguindo o guia embutido no app — mas o botão "Testar" voltou com "✕" (falha). `curl -X POST http://127.0.0.1:5001/api/v0/version` direto no terminal respondeu normalmente — confirmando que o problema era CORS (o WebKitGTK bloqueia o `fetch()` do health-check, que roda direto no frontend, não via Rust, por origem diferente `localhost:1420` → `localhost:5001`). **O guia do app não menciona configurar CORS nenhuma vez.** Corrigido manualmente: `ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["*"]'` + `Access-Control-Allow-Methods` + reiniciar o daemon — confirmado via `curl -i` que o header `Access-Control-Allow-Origin: *` passou a vir na resposta. Depois disso, "Testar" passou a mostrar sucesso. Registrado como débito #46 (guia incompleto).

#### Publicação do vault — sucesso, validado em 3 camadas

Criada uma entrada de teste (`github.com` / `teste@teste.com`), clicado "Enviar" — publicou com sucesso: "Versão 2 registrada on-chain". Validação manual, ponta a ponta, com dados reais:
1. **On-chain**: `cast call getVault(1)` no `VaultRegistry` (`0x602Fa39...`) retornou `cid="QmPHcGAKD7jgccRaoNPr2E8gciB8a5GdMuEQYRerdoKHCY"`, `contentHash`, `version=2`, `exists=true`.
2. **IPFS**: o blob foi buscado com sucesso tanto do gateway local (`http://127.0.0.1:8080/ipfs/...`) quanto do **gateway público `ipfs.io`** (confirmando que o node Kubo local já está anunciando o conteúdo na DHT pública, alcançável de fora) — os dois retornaram os mesmos 254 bytes (`diff` idêntico).
3. **Integridade**: `keccak256` do blob baixado (calculado via `cast keccak` sobre o hex do arquivo, já que não havia `eth_hash`/`pysha3` disponível) bateu **exatamente** com o `contentHash` on-chain.

Essa validação cobre exatamente o caminho que o `VaultSyncService` novo da 13.8 percorre (hasVault → getVault → download → verificação de hash) — confirmando que a lógica funciona com infraestrutura e dados 100% reais, não só nos testes automatizados com mocks.

#### Mobile: dois bloqueios encontrados na aba Vault

1. **"Device not paired" mesmo pareado**: a aba Vault mostrou isso mesmo com o pareamento já confirmado on-chain (e a aba Devices do próprio celular reconhecendo corretamente). Causa: `IndexedStack` mantém as 4 abas montadas desde a abertura do app — `VaultScreen._load()` roda uma única vez no `initState`, e nesse caso rodou **antes** do pareamento confirmar on-chain (o app tinha sido reinstalado antes do pareamento acontecer). Diferente da aba Devices (que reconfere a cada abertura/pull-to-refresh desde o débito #14 da Sessão 46), a Vault não tinha motivo pra reconferir sozinha. Resolvido fechando o app por completo (`adb shell am force-stop` + reabrir) — um processo novo faz todas as abas reconferirem do zero. Não é um bug novo introduzido pela 13.8 — é a mesma limitação de design já presente em `SessionsScreen` (que também não envolve o estado "not paired" num `RefreshIndicator`) — mas vale considerar um refresh automático mais esperto no futuro.
2. **"Vault key not available"**: depois do restart, a Vault reconheceu o pareamento mas mostrou esse novo estado — a vault key (entregue cifrada via ECIES durante o `registerDevice`) nunca chegou a ser decifrada no celular, provavelmente porque o app foi derrubado (o Android/Samsung mata apps em background agressivamente) no meio da janela em que `show_device_qr_screen.dart` fica com um polling esperando a confirmação pra então chamar `decryptVaultKeyFromPairing`. Tentativa de contornar clicando "Unpair" no celular e pareando de novo: **não funcionou** — descoberto que o "Unpair" local não revoga nada on-chain, e a auto-descoberta (mesmo mecanismo que resolve o caso "registrado on-chain mas não salvo localmente") readota o pareamento sozinha no próximo carregamento, sem nunca re-disparar uma transação `registerDevice` nova (que é a única forma de reenviar a vault key). Pra resolver de verdade precisaria: revogar o device no Desktop (transação real) + parear de novo (outra transação) — mais 2 assinaturas na Ledger. **Decisão do usuário**: parar por aqui por hoje, já que o essencial (pipeline de sync da 13.8 validado com dados reais) estava confirmado; esse último passo (ver a senha decifrada de verdade na tela) fica pendente pra uma sessão futura.

#### Resumo do que foi validado vs. não validado

✅ Layout/navegação da 13.8 num aparelho Android real (após o fix do bottom nav) · ✅ Estados vazios corretos ("not paired", "vault key not available") · ✅ Publicação real do vault (Desktop + Ledger + Base Mainnet) · ✅ Pipeline completo de leitura (on-chain → IPFS → verificação de hash) validado manualmente com dados reais, camada por camada · ❌ Entrada decifrada aparecendo de fato na tela do celular (bloqueado pela vault key nunca entregue neste device específico — pendência de uma fase anterior, não da 13.8 em si).

- **Débitos**: #44 (novo, não corrigido — `CreateIdentity.tsx` sem retry), #45 (novo, **corrigido** — concorrência HID em `ConnectLedger.tsx`), #46 (novo, não corrigido — guia do Kubo sem CORS).
- **Próximo passo**: pra fechar a validação 100% end-to-end da 13.8, revogar o device atual no Desktop e parear de novo, com cuidado pra manter o app em primeiro plano até o `decryptVaultKeyFromPairing` completar. Considerar também corrigir o débito #44 (retry em `CreateIdentity.tsx`) e #46 (guia do Kubo) antes do próximo release.

---

### Sessão 91 — 2026-07-07: Débitos #44 e #46 — retry em `CreateIdentity.tsx` + guia do Kubo com CORS

- **Objetivo**: fechar os dois débitos de código ainda abertos da Sessão 90 que não dependiam da Ledger física pra implementar — só pra validação manual completa.
- **Débito #44** (`desktop/src/components/CreateIdentity.tsx`): `tx2Submitted`/`tx3Submitted` (refs de guard contra disparo duplicado, débito de concorrência já resolvido antes) nunca resetavam depois de um erro, travando o fluxo pra sempre sem forma de tentar de novo. Adicionado `reset: resetTx2`/`reset: resetTx3` (desestruturado de `useWriteContract`/`useSendTransaction`), uma função `handleRetry()` e um botão "Try again" (renderizado quando `tx2Error`/`tx3Error` está setado no step 3/4) que zera o ref correspondente e chama o `reset()` do wagmi — o `useEffect` existente (inalterado) reenvia a transação sozinho assim que o guard libera. Decisão deliberada de exigir clique manual (em vez de auto-retry no próprio `useEffect` de erro): um reset automático reenviaria a transação imediatamente e sem controle do usuário, potencialmente loopando prompts na Ledger se o erro persistisse.
- **Débito #46** (`desktop/src/components/VaultSettings.tsx`): guia do Kubo embutido no app não mencionava CORS. Inserido um novo passo 3 "Liberar CORS pro app" (`ipfs config --json API.HTTPHeaders.Access-Control-Allow-Origin '["*"]'` + `Access-Control-Allow-Methods`) entre "Inicializar" e "Iniciar o daemon", com uma frase explicando a causa (origens diferentes `localhost:1420` → `localhost:5001`, bloqueadas pelo WebKitGTK). Passo "Configurar no TruthID" virou o passo 5.
- **Verificação**: `tsc --noEmit` e `vitest` (47/47) limpos no desktop, nenhum teste dedicado pra nenhum dos dois componentes hoje (nada a atualizar). Nenhuma das duas correções exigiu a Ledger/wallet pra implementar — validação manual de ponta a ponta (retry real após um nonce desatualizado; guia novo seguido do zero num Kubo limpo) fica pendente pro dono do projeto.
- **Débitos**: nenhum novo. Débitos #44 e #46 (tabela de Débitos Técnicos) marcados como resolvidos — fecha todos os débitos de código abertos da Sessão 90.
- **Próximo passo**: Etapa 13.9 (extensão de navegador, última etapa da Fase 13), ou fechar a validação 100% end-to-end da 13.8 pendente desde a Sessão 90 (revogar device + parear de novo com o app em primeiro plano).

---

### Sessão 92 — 2026-07-07: Vault key não entregue no pareamento não precisa de re-parear — corrigido retry direto do que já está on-chain

- **Objetivo**: revisitar a pendência da Sessão 90 ("vault key not available" nunca resolvido no celular de teste) antes de avançar pra 13.9 — o registro dizia que só dava pra resolver revogando o device e parando de novo (2 assinaturas na Ledger). Investigação encontrou que essa premissa estava errada.
- **Achado**: `DeviceRegistry.deviceVaultKeys` é um mapping on-chain permanente, gravado durante o `registerDevice` — não é um dado transiente que só existe durante a janela do pareamento (`blockchain_service.dart:368`, `getDeviceVaultKey`). O único motivo do celular de teste nunca ter conseguido decifrar a chave é que a busca+decifra (`_blockchain.getDeviceVaultKey` → `decryptVaultKeyFromPairing`) só acontecia dentro do `_checkIfRegistered` de `show_device_qr_screen.dart` — uma tela efêmera, fechada/matada pelo Android antes de completar. Como a chave cifrada já está on-chain pra sempre, dá pra tentar buscar e decifrar de novo a qualquer momento, sem nenhuma transação nova.
- **Fix**: novo `VaultKeyService.tryRecoverFromChain(BlockchainService)` (`mobile/lib/services/vault_key_service.dart`) — busca `getDeviceVaultKey(address)` e chama `decryptVaultKeyFromPairing` de novo, retornando `false` sem lançar se ainda não há nada on-chain ou se a decifra falhar. `show_device_qr_screen.dart` refatorado pra usar esse método (elimina duplicação). `VaultScreen` (`mobile/lib/screens/vault_screen.dart`) ganhou um botão "Try again" no estado `noVaultKey`, que chama `tryRecoverFromChain` e recarrega a tela se der certo, ou mostra um snackbar se ainda não tiver nada on-chain — texto do estado vazio deixou de dizer "re-pair" (falso) e agora explica que não precisa parear de novo.
- **Testes novos**: 2 casos em `vault_key_service_test.dart` (`tryRecoverFromChain` — sem chave on-chain retorna `false`; blob corrompido retorna `false` sem lançar) e 3 casos em `vault_screen_test.dart` (botão aparece no estado `noVaultKey`; retry com sucesso recarrega a tela; retry sem sucesso mostra snackbar e mantém o estado). Suite completa do mobile: 121 passando (+5 novos), mesmos 5 pré-existentes falhando em `deriveVaultKey` (bug conhecido de binding do `flutter_secure_storage` isolado, não relacionado). `flutter analyze` limpo (só os 5 lints pré-existentes).
- **Débitos**: nenhum novo (na hora — ver achados abaixo, na mesma sessão, ao validar ao vivo).

#### Validação ao vivo (mesma sessão): 4 bugs reais adicionais achados, 3 corrigidos, 1 é limitação de infra

Ao validar o "Try again" com o celular físico de verdade (não só testes automatizados), a cadeia completa de pareamento foi exercitada em Base Mainnet real várias vezes, revelando problemas mais profundos que a pendência original:

1. **Bug real — `DeviceRegistry.revokeDevice` nunca reseta `exists`, então um endereço revogado não pode ser registrado de novo, pra sempre.** `registerDevice` reverte com `DeviceAlreadyRegistered` pra qualquer endereço que já tenha existido antes, mesmo revogado (confirmado via `cast call getDevice(...)` → `revoked=true, exists=true`). Isso invalida a suposição da Sessão 90 de que "revogar + parear de novo" resolveria — não resolve pro mesmo device físico (a chave do device é gerada uma vez e persiste no `flutter_secure_storage`). **Não corrigido** (mudar isso exigiria uma função nova no contrato + redeploy em cascata dos 5 contratos) — só documentado. Contorno usado nesta sessão: reinstalar o app mobile gera uma chave de device nova (endereço novo), permitindo parear "do zero" sem esbarrar nisso — funciona, mas só serve pra dispositivos de teste/dev.

2. **Bug real — `DeviceKeyService._getOrCreateKey()` tinha uma race condition clássica de "check-then-write".** Cada tela (`DevicesScreen`, `ShowDeviceQrScreen`) cria sua própria instância de `DeviceKeyService`, e num install novo, se duas chamam `_getOrCreateKey()` quase ao mesmo tempo, cada uma via a storage vazia, gerava sua própria chave aleatória, e quem escrevia por último "vencia" — a outra tela ficava mostrando um endereço órfão em memória (observado na prática: "Devices" e "Pair device" mostrando endereços diferentes logo após reinstalar). **Corrigido**: `_keyFuture` agora é `static` em `mobile/lib/services/device_key_service.dart` — memoiza a criação entre todas as instâncias da classe, garantindo que só a primeira chamada gera/grava a chave.

3. **Bug real — a chave pública do device enviada pro Desktop estava no formato errado.** `getDevicePublicKeyHex()` retornava os 64 bytes crus (X||Y) que o `web3dart` usa pra derivar endereço (convenção Ethereum), sem o prefixo SEC1 `0x04`. O lado Rust (`encrypt_vault_key_for_device`) exige exatamente 33 (comprimida) ou 65 bytes (não-comprimida) — um valor de 64 bytes é rejeitado, o erro é engolido silenciosamente pelo try/catch do `PairDevice.tsx`, e `encryptedVaultKey` ficava vazio (`0x`) pra sempre (mesmo sintoma de sempre, causa raiz nova). **Corrigido**: `getDevicePublicKeyHex()` agora prependa `0x04` antes dos 64 bytes.

4. **Bug real — `PairDevice.tsx` tinha o mesmo bug de "sem retry" já visto em `CreateIdentity.tsx` (débito #44).** Quando o commit ou o reveal revertia on-chain, `registerPhase` ficava preso em `"committing"`/`"registering"` pra sempre — o botão "Register device" ficava desabilitado sem nenhuma forma de tentar de novo, mesmo com o formulário ainda preenchido. **Corrigido**: novo `useEffect` que reseta `registerPhase` pra `"idle"` quando `isCommitError || isRegisterError`, mais `resetCommit()`/`resetRegister()` (novo `reset` desestruturado de `useWriteContract`) no início de `handleRegister()`.

5. **Bug real, o mais sério — `deviceVaultKeys` nunca esteve no ABI do mobile.** `mobile/lib/contracts/abis.dart`'s `deviceRegistryAbi` só tinha `getDevice` — `deviceVaultKeys` (mapping público, getter automático) nunca foi adicionado desde a Sessão 76. `_deviceContract.function('deviceVaultKeys')` lançava `Bad state: No element`, engolido pelo try/catch de `getDeviceVaultKey`, retornando `null` sempre. **Este é o bug raiz real por trás de TODA a saga "vault key not available" desde a Sessão 76** — não a app-backgrounding (Sessão 90), não o formato da chave pública (achado #3 acima): mesmo com tudo mais certo, a busca on-chain nunca teria funcionado. **Corrigido**: função `deviceVaultKeys(address) returns (bytes)` adicionada ao ABI. **Teste de regressão novo**: `mobile/test/contracts/abis_test.dart` — parseia os ABIs reais (não mockados) e confirma que toda função chamada em `blockchain_service.dart` existe neles; falha exatamente como o bug original quando revertido manualmente (verificado).

6. **Bug real, mais fundamental ainda — o Desktop (Rust) nunca fazia o hash SHA-256 da chave AES.** `encrypt_vault_key_for_device` (`desktop/src-tauri/src/lib.rs`) tinha o comentário "Deriva chave AES do shared secret via SHA-256" mas o código só fazia `Key::<Aes256Gcm>::from_slice(&shared_bytes)` — o segredo ECDH cru virava a chave AES direto, sem hash. O mobile (`decryptVaultKeyFromPairing`) sempre fez `crypto.sha256.convert(sharedSecret).bytes` corretamente. Resultado: mesmo com os achados #3 e #5 corrigidos, a decifra falhava com `SecretBoxAuthenticationError: SecretBox has wrong message authentication code (MAC)` — as duas pontas nunca deriva(ra)m a mesma chave AES, desde que o ECIES foi implementado (Sessão 76). **Corrigido**: `let aes_key_bytes = Sha256::digest(shared_bytes);` antes de construir a chave AES. Lógica de criptografia extraída pra uma função pura testável (`encrypt_bytes_for_device`, sem depender do keyring), com **teste novo em Rust** (`cargo test`, `#[cfg(test)] mod tests` em `lib.rs`) que faz o round-trip completo (cifra com a função real, decifra reimplementando exatamente o algoritmo do mobile) — falha sem o hash, passa com ele.

**Validação final**: depois de todos os 5 fixes, um pareamento novo (revoke + parear com endereço novo, repetido 3x ao longo da sessão pra isolar cada bug) confirmou via `cast call deviceVaultKeys(...)` que o blob cifrado chega on-chain corretamente (93 bytes, formato certo: 33+12+48). A decifra no celular em si não foi confirmada 100% ao vivo nesta sessão — a RPC pública gratuita (`mainnet.base.org`) começou a responder "over rate limit" (`-32016`) bem no fim, provavelmente por causa do volume de chamadas simultâneas que o app dispara ao abrir (Devices+Wallet+Sessions todas montadas via `IndexedStack`) somado a todas as chamadas de diagnóstico (`cast call`) feitas ao longo da sessão. Isso é uma limitação de infraestrutura (RPC pública gratuita, sem chave), não um bug de código restante. A prova de correção da criptografia vem do teste Rust determinístico (achado #6), que passa de forma isolada e reproduzível.

- **Testes novos totais desta sessão**: 2 (`vault_key_service_test.dart`) + 3 (`vault_screen_test.dart`) + 3 (`abis_test.dart`, novo arquivo) no mobile; 1 (`PairDevice.test.tsx`, retry) no desktop TS; 1 (`lib.rs`, round-trip ECIES) no desktop Rust. Suites finais: mobile 124/129 (5 falhas pré-existentes, não relacionadas — `deriveVaultKey` isolado precisa de binding do `flutter_secure_storage`); desktop `vitest` 48/48; desktop `cargo test` 15/15. `flutter analyze` e `tsc --noEmit` limpos nos dois.
- **Débitos**: nenhum novo de código. Um débito de arquitetura documentado, não corrigido: `DeviceRegistry.revokeDevice` não permite re-registro do mesmo endereço depois de revogado (achado #1) — decisão de design pendente do dono do projeto sobre se/como resolver (exigiria redeploy).
- **Próximo passo**: validar a decifra no celular com a RPC descansada (ou trocar pra uma RPC com chave, menos sujeita a rate limit) — depois disso, ou fechar de vez a 13.8, ou avançar pra Etapa 13.9 (extensão de navegador, última etapa da Fase 13).

---

### Sessão 93 — 2026-07-08: Fallback entre 3 RPCs no mobile — resolve o rate limit visto ao vivo na Sessão 92

- **Objetivo**: o dono do projeto relatou o problema de RPC da Sessão 92 (`-32016 over rate limit` numa RPC pública gratuita, durante os testes do Vault no celular) e pediu uma forma de evitar que aconteça de novo.
- **Achado**: `mobile/lib/services/blockchain_service.dart` tinha uma única RPC hardcoded (`mainnet.base.org`), sem fallback, repetida em 7 pontos diferentes do arquivo (cada leitura JSON-RPC — `eth_call`, `eth_getLogs`, `eth_getBalance`, `eth_blockNumber`, `eth_getTransactionReceipt`, `eth_getBlockByNumber` — montava seu próprio `HttpClient().postUrl()`). O Desktop já não tinha esse problema: `desktop/src/config/wagmi.ts` usa `fallback()` do wagmi com 3 RPCs desde antes. O mobile nunca ganhou o mesmo tratamento — é a causa raiz direta do que quebrou a validação final da Sessão 92.
- **Fix**: novo helper `_rpcCall(method, params)` / `_rpcCallOnce(url, method, params)` — tenta, em ordem, `mainnet.base.org` → `base-rpc.publicnode.com` → `base.drpc.org` (mesma lista do Desktop), com timeout de 10s por tentativa; qualquer falha (rede, timeout, ou `error` no corpo da resposta) passa pro próximo RPC da lista. Mesmo esquema de fallback já usado pelo `IpfsGatewayClient` (`ipfs_gateway_client.dart`) pros gateways IPFS — consistente com o padrão já existente no projeto. Os 7 call sites (`_ethCallRawHex`, `getLatestBlockNumber`, `_fetchIdentityCreatedLogs`, `getBalance`, `getLogs`, `getTransactionReceipt`, `getBlockTimestamp`) refatorados pra usar o helper, eliminando ~150 linhas de HTTP boilerplate duplicado.
- **Não validado**: Flutter não está instalado neste host (novo PC, roda via Docker — ver seção de ambiente), então não rodei `flutter analyze`/`flutter test` nem build. Revisão manual do arquivo inteiro, linha a linha, no lugar. Validação real (Docker build + teste no celular) fica pendente pro dono do projeto.
- **Débitos**: #53 (nova, tabela de Débitos Técnicos) já nasce resolvida nesta mesma sessão.
- **Próximo passo**: rodar `cd mobile && ./dev.sh build` pra confirmar que compila de verdade, e então repetir a validação da decifra da vault key (pendência restante da Sessão 92) — agora sem depender de uma única RPC.

---

### Sessão 94 — 2026-07-12: Ideia externa — login sem callback (fallback on-chain) + Vault genérico

- Não foi trabalho no TruthID em si — o dono do projeto estava desenhando sync multi-dispositivo pro Practice Valuation (outro projeto dele) e queria reaproveitar a identidade/infra do TruthID. Duas lacunas do TruthID apareceram e foram investigadas contra o código real (`approval_screen.dart`, `client.ts`, `SessionRegistry.sol`, `VaultRegistry.sol`), não só de memória.
- Achado 1: `callbackUrl` https é obrigatório no QR de login hoje (`approval_screen.dart:88-96`), mas a escrita da sessão on-chain já acontece incondicionalmente antes do POST — dá pra expor um modo "sem callback" (polling on-chain) barato, só tornando o campo opcional. Ressalva: não afrouxar pra `http://` (LAN) — reabriria o risco que o `https://` obrigatório existe pra evitar.
- Achado 2 (levantado nesta sessão, **corrigido na Sessão 95**): `VaultRegistry` (Fase 13) já resolve "CID + criptografia local + pinning redundante" — só é 1 vault por identidade hoje (password manager). Cheguei a propor generalizar pra múltiplos vaults por identidade pra servir o Practice Valuation.
- Nada implementado, nenhum `/plan` rodado — registrado em "Roadmap de Evoluções Planejadas" pra quando o assunto voltar (ver também `PROJECT_STATE.md` do `practice-valuation`, Fase 8).

---

### Sessão 95 — 2026-07-12: Correção — Vault não muda, Practice Valuation só usa o login

- O dono do projeto corrigiu o Achado 2 da Sessão 94: ele **não** quer generalizar o `VaultRegistry`. O Vault continua ligado diretamente à identidade, 1 vault por `identityId`, sem alteração — é exclusivo do password manager.
- O Practice Valuation é outro software; ele só precisa do esquema de login/autenticação do TruthID (o "callback opcional no login" do Achado 1, que continua válido). Se ele sincronizar dados via IPFS, é mecanismo próprio dele, sem passar pelo `VaultRegistry` nem pela cifra ECIES derivada do pareamento do TruthID.
- Entrada do Roadmap (`Callback opcional no login (fallback on-chain) + Vault genérico`) reescrita pra remover a parte do Vault genérico e deixar só o item de callback opcional, que é o único que segue relevante pro TruthID.
- Nada implementado — só correção de registro/roadmap.

---

### Sessão 96 — 2026-07-13: Brainstorm — Vault genérico multi-app + delegação de assinatura via session key (reabre parte da Sessão 95)

- De novo puxado pelo Practice Valuation (Fase 8 do `PROJECT_STATE.md` dele): sincronizar valuations/alertas entre desktop e celular via IPFS, com o CID registrado on-chain no mesmo padrão do `VaultRegistry` do TruthID.
- Reabre, sob desenho diferente, a parte que a Sessão 95 tinha fechado ("Vault não muda"): agora não é generalizar o vault de senhas em si, é um mecanismo de `identityId + appId → VaultRef` pra apps terceiros terem seu próprio slot de CID, deixando o slot do password manager intocado.
- Questão nova levantada nesta sessão (não estava nas 94/95): como um app terceiro paga gas pra atualizar seu CID sem o usuário precisar da Ledger toda hora e sem dar poder de assinatura a qualquer app "logado". Direção que fez mais sentido na conversa: login (prova de identidade) e assinatura (smart account) continuam separados; o app terceiro monta a UserOperation sem assinar, pede aprovação ao TruthID (IPC local ou QR/P2P entre devices), o TruthID mostra tela de aprovação (mesmo padrão do approval screen da extensão) e assina com uma **session key escopada** (contrato + função + slot do `appId`, com expiração/revogação em cascata) — nunca com a chave raiz/Ledger. Paymaster cobre o gas.
- Só brainstorm, nenhum `/plan` rodado, nada implementado. Registrado em "Roadmap de Evoluções Planejadas" com os pontos em aberto (contrato generalizado vs. irmão dedicado; canal de aprovação; UX de clique único vs. sessão; onde mora o registro de apps autorizados) pra decidir num `/plan` futuro.

---

### Sessão 97 — 2026-07-13: Transporte da extensão de navegador (13.9) — dois canais desenhados, descoberta na LAN + dead-drop via IPFS/IPNS

- 13.9 é a única etapa pendente da Fase 13 (Vault) — ver seção "Hierarquia de confiança: Devices vs. sessões de extensão". O desenho existente só dizia "canal P2P efêmero (ex: WebRTC)", nunca decidido de verdade; confirmado que não existe WebRTC, sinalização nem scaffold de extensão em lugar nenhum do repo — greenfield puro.
- Propus 3 rotas de transporte (ponte via Desktop/Native Messaging, WebRTC com handshake por 2 QR, servidor de sinalização próprio) e o dono do projeto rejeitou as três: não quer depender do Desktop instalado no computador onde a extensão roda, não quer câmera na extensão, não quer servidor operado por nós.
- Expliquei a restrição física real por trás da rejeição: uma extensão de navegador nunca consegue escutar conexão de entrada (limite de sandbox da plataforma, não escolha de design) — só faz requisição de saída.
- Desenhados dois transportes, mesma prioridade, tentados em sequência (não mutuamente exclusivos, a pedido do dono do projeto): **descoberta automática na LAN** (extensão varre a sub-rede local procurando um servidor HTTP efêmero que o mobile sobe, mais simples/rápido mas exige rede compartilhada) e **dead-drop via IPFS/IPNS público** (reaproveita a infra de pinning já usada pelo Vault, funciona em qualquer rede mas com propagação lenta e suporte incerto em provedores PSA simples sem Kubo). Detalhes completos na seção de desenho acima.
- Pendência nova gerada por essa escolha: a "revogação em cascata" do desenho original assumia o Desktop no meio do transporte pra saber qual Device abriu qual sessão — sem o Desktop no caminho, isso não vale mais como estava escrito. Provável resposta é TTL curto sem canal de revogação ativa, mas fica como decisão de produto pra confirmar quando 13.9 for implementada.
- **Mudança de escopo pedida na mesma sessão**: perfis deixam de ser os 3 fixos pré-definidos (`Trabalho`/`Casa`/`Pessoal`) — o dono do projeto quer criar/nomear perfis livremente e marcar cada senha em quantos perfis quiser. **Implementado ainda nesta sessão**: `Vault::add_profile/rename_profile/delete_profile` em Rust (22 testes passando) + seção "Gerenciar perfis" no `VaultManagement.tsx` (Desktop); métodos espelhados em `VaultRepository` + `vault_profiles_screen.dart` (Mobile). `kVaultProfiles`/`PROFILES` removidos.
- **Pedido seguinte na mesma sessão**: dono do projeto perguntou se o Mobile também ganharia escrita completa (criar/editar senha, gerenciar perfis) — confirmei que sim, era escopo novo, e expandi com `/plan`. Investigação mostrou que o Mobile já podia assinar UserOperations genéricas (Fase 14) e que `VaultRegistry` não é bloqueado pra devices — só faltava UI e capacidade de pin IPFS. **Implementado em 3 fases nesta sessão**: (A) infra de publicação no Mobile — `IpfsPinClient` (mirror de `ipfs.rs` em Dart puro), `PinningProviderService`+tela (config própria do Mobile), `SessionCreator.updateVault`, `VaultPublishService`; (B) CRUD de entradas — `vault_entry_form_screen.dart`, editar/apagar em `VaultEntryDetailScreen`, botão "+" e banner "Publicar" em `VaultScreen`; (C) perfis no Mobile (ver item acima). `canWriteVault` foi movido do arquivo local do Desktop pro blob sincronizado do vault, pra o Mobile conseguir ler a própria permissão — continua trava de UX, não de contrato. Detalhe completo nas seções "Perfis" e "Mobile ganha escrita completa no Vault" acima.
- **Pedido registrado pra depois, não implementado**: extensão poder mandar um pedido de alteração de senha, aprovado só pelo Device (não a própria extensão aplicando direto) — ver seção "Extensão pedindo alteração de senha" acima. Só brainstorm.
- **Incidente de disco no meio da sessão**: a build Docker do Flutter (primeira vez nesta máquina) esgotou a partição raiz (32GB, separada de `/home`). Resolvido com prune de containers/imagens órfãs (~7GB) + remoção do volume de cache `practice-valuation_cargo-target` (15,6GB, autorizado pelo dono do projeto) — detalhe é do ambiente, não do projeto.
- **Pendência real**: nada do lado Dart rodou via `flutter test`/`flutter analyze` de verdade — só revisão manual (que já pegou e corrigiu uma quebra real em `vault_screen_test.dart`). Rust validado (22/22 + `cargo check` limpo). Dono do projeto pediu pra registrar como pendência em vez de insistir com o disco apertado.
- **Próximo passo**: rodar `./dev.sh flutter test`/`flutter analyze` quando o disco permitir (pendência acima); depois, 13.9 (extensão de navegador) com os dois transportes desenhados, quando o dono do projeto retomar.

---

### Sessão 98 — 2026-07-13: `flutter test`/`flutter analyze` rodados de verdade — 20 falhas achadas e corrigidas (regressão de teste, não de produto)

- Retomando a pendência da Sessão 97: disco tinha só 6.4GB livres em `/` (sda2, 32GB, separada de `/home`). Com autorização do dono do projeto, `docker image prune -a` liberou ~9GB de imagens de outros projetos (`desktop-desktop`, `practice-valuation-desktop`) não usadas no momento — rebuildáveis a qualquer hora. Build da imagem Docker do Flutter (1ª vez desta sessão, a da Sessão 97 tinha sido removida no prune de disco daquela sessão) completou normal, deixando ~9GB livres.
- `flutter analyze`: limpo, 0 erros — só 6 avisos de estilo pré-existentes (`prefer_initializing_formals`, 1 `unnecessary_non_null_assertion`), nenhum novo.
- `flutter test` (suíte completa): travou de verdade — rodou 10+ minutos sem terminar, 20 falhas em `vault_screen_test.dart`, `vault_profiles_screen_test.dart` e `vault_entry_detail_screen_test.dart` (todos os testes que passam por essas telas, exceto os que retornam antes de tocar o repositório), todas com "pumpAndSettle timed out" ou timeout real de 10 minutos.
- **Causa raiz isolada por reprodução controlada** (não é bug de produto — o app funciona normal no engine real): esses 3 arquivos de teste, escritos na Sessão 97, usam um `VaultRepository` **real** (I/O real de arquivo via `dart:io`, só com `testPath`/cipher fake) diretamente dentro do `initState()`/`_load()` das telas (`canWriteVault`, `pendingChanges`, `listProfileNames`, `deleteEntry` etc). Testes de widget do Flutter (`testWidgets`) rodam dentro de uma zona `FakeAsync` que nunca deixa uma operação real de I/O (fora de `tester.runAsync()`) completar — ela fica pendurada pra sempre, não apenas lenta. Confirmado com um teste mínimo isolado: um `test()` puro (não-widget) fazendo o mesmo I/O terminou em milissegundos; o mesmo I/O disparado de dentro de um `testWidgets` nunca resolveu, nem depois de 20 pumps manuais. Antes da Sessão 97, essas telas só usavam serviços 100% mockados no `initState`, por isso o problema nunca tinha aparecido.
- **Fix aplicado**: converter os 3 arquivos de teste pra usar `MockVaultRepository` (mocktail) em vez do repositório real, com `verify()` no lugar de reler o estado real do repo. O CRUD de verdade do `VaultRepository` já é coberto por `vault_repository_test.dart` (testes `test()` puros, sem widget, onde I/O real funciona sem problema). Não foi preciso tocar em nenhum código de produto — o bug era só na forma de testar.
- **Dois débitos pré-existentes, sem relação com a Sessão 97, achados no caminho e também corrigidos**: (1) `vault_key_service_test.dart` (já documentado como falha conhecida, "Binding has not yet been initialized") e (2) `vault_publish_service_test.dart` (2 testes, mesmo erro de binding em `VaultRepository.markPublished`, mascarado antes por um `registerFallbackValue` faltando pra `Uint8List`) — ambos usam o campo estático `FlutterSecureStorage()` de `VaultKeyService`/`VaultRepository`, não injetável; corrigido com `TestWidgetsFlutterBinding.ensureInitialized()` + `setMockMethodCallHandler` simulando o canal `plugins.it_nomads.com/flutter_secure_storage` (leitura/escrita num Map em memória).
- **Resultado final**: suíte completa 100% verde — 155/155 testes, ~18 segundos (antes: nunca terminava). `flutter analyze` limpo.
- **Próximo passo**: 13.9 (extensão de navegador) — transporte já desenhado na Sessão 97 (LAN + IPFS/IPNS), agora com a suíte de testes finalmente validada e servindo de rede de segurança pra próximas mudanças no Vault.

---

### Sessão 99 — 2026-07-14: 13.9 fatia 1 implementada — extensão de navegador via transporte LAN, achado bug real de ECIES no pareamento

- **Objetivo**: retomar a 13.9 (última etapa da Fase 13), agora com a suíte de testes validada (Sessão 98). Escopo negociado antes de implementar via `/plan`: só o transporte LAN nesta fatia (dead-drop IPFS/IPNS fica pra depois), revogação confirmada como TTL curto sem canal ativo, permissão ampla da extensão pedida em runtime, Firefox suportado com fallback manual de IP. Ver seção "13.9, fatia 1 — implementada na Sessão 99" acima (dentro de "Fase 13 — TruthID Vault") para o desenho técnico completo.
- **Extensão nova, `extension/`**: greenfield via WXT (vanilla-ts, sem framework de UI), MV3 forçado também no Firefox (WXT usa MV2 lá por padrão, o que quebraria `optional_host_permissions`). `system.network` só no manifest do Chrome/Edge (via hook do WXT — API real, mas ausente da tipagem de `@types/chrome`). Módulos: `crypto/ecies.ts` (ECIES em JS via `@noble/curves`+Web Crypto), `session/{qrPayload,sessionState,lanDiscovery}.ts`, `storage/sessionStore.ts` (`chrome.storage.session`), `ui/{renderQr,renderEntries}.ts`, popup + background.
- **Descoberta LAN**: rejeitado o truque de WebRTC/ICE candidates que o desenho original da Sessão 97 tinha especulado — navegadores modernos ofuscam isso atrás de mDNS `.local`, retornaria lixo silenciosamente. Substituído por `chrome.system.network.getNetworkInterfaces()` (Chrome/Edge) + fetch-sweep numa lista fixa de 5 portas (não porta aleatória — resolve uma inconsistência do texto da Sessão 97), com fallback manual de IP sempre disponível (único caminho no Firefox).
- **Mobile**: `EciesService` novo (`mobile/lib/services/ecies_service.dart`, `encrypt`+`decrypt` genéricos, mirror do Rust); `VaultKeyService.decryptVaultKeyFromPairing` refatorado pra delegar nele; `VaultLanServerService` novo (`dart:io HttpServer` cru, 1 request autenticado); `vault_session_screen.dart` ganhou os estados reais `sending`/`sent`/`timeout`/`error` no lugar do stub `unavailable` da 13.8; `Info.plist` ganhou `NSLocalNetworkUsageDescription` (iOS 14+ Local Network Privacy).
- **Achado real, não hipotético**: o primeiro teste de round-trip de verdade do `EciesService` (escrito nesta sessão) revelou que `SecretBox(ciphertext, mac: Mac.empty)` com o tag do AES-GCM concatenado ao ciphertext **nunca decifra** — o pacote `cryptography` recalcula o MAC sobre o ciphertext inteiro e nunca bate contra `Mac.empty`. Esse é o exato padrão que `VaultKeyService.decryptVaultKeyFromPairing` já usava desde a Sessão 76/92, o que significa que **a entrega de vault key via pareamento (ECIES) provavelmente nunca funcionou de ponta a ponta em nenhum dispositivo real** — a Sessão 92 só validou via teste Rust puro (que reimplementa o decrypt em Rust, sem chamar o Dart de verdade), e a validação em hardware real ficou sempre como pendência, nunca como sucesso confirmado. Corrigido com `SecretBox.fromConcatenation(nonceLength: 12, macLength: 16)` — não muda o formato do blob (compatível com tudo que já está on-chain), só a forma como o Dart o interpreta. Gera uma pendência nova: revalidar essa decifra em hardware real à luz do fix.
- **Vetor cruzado fixo**: gerado uma vez rodando o `EciesService.encrypt` real do Dart (via Docker), usado idêntico em 3 lugares — novo teste Rust `dart_produced_blob_decrypts_correctly`, `mobile/test/services/ecies_service_test.dart`, `extension/src/crypto/ecies.test.ts` — provando interoperabilidade Rust/Dart/JS de forma determinística e offline.
- **Testes**: `cargo test --lib` 27/27, `flutter test` 166/166 (+11 novos), `flutter analyze` limpo, extensão com `tsc --noEmit` limpo + `vitest run` 10/10 + `wxt build` validado pra Chrome e Firefox (MV3 nos dois).
- **Próximo passo**: validação manual E2E em hardware real (extensão unpacked + celular na mesma Wi-Fi) — nada disso rodou contra dispositivos reais ainda, incluindo o diálogo de Local Network Privacy do iOS e a revalidação da decifra da vault key de pareamento. Depois: fatia 2 da 13.9 (dead-drop IPFS/IPNS).

### Sessão 100 — 2026-07-14: 13.9 fatia 2a implementada — Mobile publica o dead-drop IPFS/IPNS, validado contra Kubo real

- **Objetivo**: continuar a 13.9 depois da fatia 1 (Sessão 99). Escopo negociado via `/plan` com o dono do projeto: só o lado Mobile nesta fatia (2a) — derivar a chave IPNS, publicar via Kubo, provar a derivação contra um Kubo real; consumo pela extensão fica pra uma fatia 2b futura. Gatilho: publish IPNS sempre em paralelo com o transporte LAN, nunca como fallback sequencial. Ver seção "13.9, fatia 2a" acima (dentro de "Fase 13 — TruthID Vault") para o desenho técnico completo.
- **Revisão técnica pegou um erro real antes de qualquer código**: `format=libp2p-key` no `POST /api/v0/key/import` do Kubo não existe (confusão com o codec CIDv1 `libp2p-key`, 0x72) — o valor certo é `libp2p-protobuf-cleartext` (default do Kubo).
- **Derivação hand-rolled**: HKDF-SHA256(sessionId) → seed Ed25519 → protobuf `PrivateKey`/`PublicKey` do libp2p → multihash identity → CIDv1 libp2p-key → base36. HKDF promovido de privado (`vault_key_service.dart`) pra `mobile/lib/services/hkdf_util.dart` compartilhado.
- **Validação cruzada contra Kubo real (não só round-trip interno)**: daemon Kubo isolado local (offline, `IPFS_PATH` temporário) + probe Dart temporário rodado via Docker do Mobile — o nome IPNS que o Kubo devolveu depois de importar a chave bateu byte-a-byte com o calculado no Dart (`k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh`). Virou fixture travada no teste.
- **Publish no Kubo**: `IpfsPinClient` ganhou `kuboImportKey`/`kuboPublishName`/`kuboRemoveKey` + `publishDeadDrop` (orquestração). Plugado em `vault_session_screen.dart._sendToExtension()`, disparado em paralelo com `VaultLanServerService.serveOnce()`, erro isolado por transporte.
- **Testes**: `flutter test` 174/174 (era 155 + 8 novos em `ipns_key_service_test.dart` + ajuste no mock de `vault_session_screen_test.dart`), `flutter analyze` limpo (mesmos 8 avisos pré-existentes).
- **Próximo passo**: fatia 2b (extensão deriva o mesmo IPNS name em TS, faz polling contra gateway público, decifra, UI de progresso). Também pendente: exercitar o publish HTTP real (`kuboImportKey`/`kuboPublishName`/`kuboRemoveKey`) via `flutter test`/hardware real — só a derivação matemática tem teste automatizado hoje, o publish HTTP foi validado via `curl` manual nesta sessão.

### Sessão 101 — 2026-07-14: 13.9 fatia 2b implementada — extensão consome o dead-drop, fecha a 13.9 e a Fase 13

- **Objetivo**: fechar a última etapa da 13.9 (e da Fase 13) — a extensão precisa recalcular o nome IPNS que o Mobile publica (fatia 2a) e resolver de verdade. Duas decisões de arquitetura negociadas via `/plan`: polling roda no background service worker via `chrome.alarms` (não na popup, que fecha ao perder foco e não sobreviveria aos ~1-2min de propagação do IPNS), e começa automaticamente assim que o QR aparece (não espera clique em "Find"). Ver seção "13.9, fatia 2b" acima para o desenho completo.
- **`multiformats@14.0.4`** (pacote oficial Protocol Labs) entrou como dependência nova — cobre multihash/CIDv1/multibase base36 sem hand-roll, ao contrário do Dart (fatia 2a), onde não existia pacote maduro.
- **Vetor cruzado da fatia 2a bateu de primeira do lado TS** — mesmo `sessionIdHex`/`expectedIpnsName` validado contra Kubo real na Sessão 100, sem nenhum ajuste. Fecha a interoperabilidade Dart/Rust/TS nas 3 pontas.
- **Achado ao vivo que contraria a hipótese inicial**: o gateway `ipfs.io` já manda `Access-Control-Allow-Origin: *`, então o fetch pro `/ipns/<name>` funciona sem nenhuma `host_permission` nova no manifest — diferente do LAN, que precisa de `http://*/*` porque o servidor efêmero do Mobile não manda CORS. Também achado: o gateway responde 500 (não 404) pra nome ainda não propagado.
- **Dedupe pequeno**: `hexToBytes`/`bytesToHex` extraídos pra `extension/src/util/bytes.ts` (antes duplicados em `ecies.ts`/`main.ts`) — o background precisaria de uma terceira cópia.
- **Testes**: `vitest run` 18/18 (era 10, +8 novos entre `ipnsKey.test.ts` e `deadDropPolling.test.ts`), `tsc --noEmit` limpo, `wxt build` validado pra `chrome-mv3` e `firefox-mv3` — manifest confirma nenhuma permissão nova.
- **Próximo passo**: só falta validação manual E2E em hardware real (extensão + celular, LAN e dead-drop) pra fechar a Fase 13 de verdade — nada de código pendente.

### Sessão 102 — 2026-07-14: retomado o brainstorm da Sessão 96 (Practice Valuation paga gás via smart account do TruthID) — Desktop ganha assinatura via device key (fatia 1), validação real pendente

- **Objetivo**: destravar a ideia da Sessão 96 (Practice Valuation delega assinatura pro TruthID) rodando um `/plan` de verdade, como o dono do projeto pediu. Pedido explícito de explicação didática (usuário iniciante em blockchain) — plano escrito com seção de conceitos (UserOperation, bundler, owner vs. device key, EIP-191) antes do desenho técnico.
- **2 achados corrigiram o desenho antes de codar**: (1) não existe Paymaster no TruthID (descartado na Sessão 52) — quem paga o gás é a própria smart account, com ETH próprio; (2) não existe "approval screen da extensão" pra copiar (a Sessão 96 citava algo que não existe — a extensão usa `VaultSessionScreen`, um fluxo totalmente diferente).
- **Reescopo a partir de uma pergunta do dono do projeto**: "isso não é problema do app terceiro?" — levou a descartar a ideia de um contrato `AppVaultRegistry` novo do lado TruthID. Practice Valuation traz o próprio contrato; TruthID vira só um "assinador genérico" após aprovação do usuário, com decodificação real da chamada (não confiar em descrição livre do app terceiro).
- **Escopo desta sessão restrito ao pré-requisito técnico**: o Desktop não tinha pipeline de UserOperation+bundler (só o Mobile tinha) — sem isso, "assinar sem toque físico" não é possível no Desktop. Portado o pipeline inteiro do Mobile (empacotamento/hash de UserOp, cliente do bundler Pimlico, orquestração) + reaproveitada a primitiva de assinatura Rust que já existia (`sign_session_hash` já fazia exatamente o wrap EIP-191 necessário).
- **Validação com vetores cruzados do Mobile**: os 5 vetores de hash de UserOp e o vetor de assinatura (chave #0 do Anvil) bateram de primeira, sem nenhum ajuste — mesma matemática, duas linguagens.
- **Bloqueado na validação real contra o Mainnet**: o device key do Desktop nunca foi registrado on-chain (achado via leitura pública, sem custo) — precisa ser pareado antes (fluxo já existe em `DesktopDevice.tsx`), e falta configurar a API key do bundler Pimlico (segredo, ação do dono do projeto).
- **Próximo passo**: dono do projeto configura o bundler e pareia o Desktop como device; depois disso, testar o botão "Publicar via device key" contra o Mainnet de verdade. Só então: fatia 2 (canal local com apps terceiros + tela de aprovação genérica + decodificação de chamada arbitrária).

### Sessão 103 — 2026-07-14/15: fatias 2a, 2b e 3 da delegação de assinatura implementadas — canal local, sign-request com aprovação, e Practice Valuation fala com o TruthID

- **Objetivo**: continuar a delegação de assinatura de onde a Sessão 102 parou (fatia 1 pronta, fatia 2 não iniciada). Cada sub-fatia negociada via `/plan` antes de codar, mesmo padrão usado na 13.9.
- **Fatia 2a — canal local (só transporte)**: confirmado que o app terceiro é outro processo nativo na mesma máquina, não web app; fatia 2 quebrada em sub-fatias menores por decisão do dono do projeto. `local_signer_server.rs` novo (servidor `axum` em `127.0.0.1:47950-47954`, sobe automático, só `ping`/`handshake`). Ver seção "Vault genérico multi-app..." acima para o desenho técnico completo.
- **Fatia 2b — sign-request + aprovação + decodificação**: duas decisões negociadas (app terceiro declara a `functionSignature`, TruthID confere o seletor mas não bloqueia se não bater; POST fica pendurado até decisão humana, timeout de 5min no Rust). `sign_request.rs` novo + `SignRequestModal.tsx`. Achado de design: decoupling do núcleo Rust de `tauri::AppHandle` (usa closure genérica) permitiu testar a rota HTTP inteira via `reqwest` real em `#[tokio::test]`, sem precisar da feature `test` do crate `tauri` que o plano original achava necessária.
- **Fatia 3 — Practice Valuation fala com o TruthID**: escopo negociado explicitamente (prova de conceito mínima, não a Fase 8 completa dele) antes de tocar no outro repositório. Novo `commands/truthid.rs` + aba "TruthID Sync" lá. Achado de segurança sem impacto: o subagente Explore usado pra levantar o estado do repo Practice Valuation recebeu de volta uma tentativa de prompt injection (um "system-reminder" falso alegando plan mode ativo, instruindo a criar um arquivo via uma ferramenta Write que o Explore não tem) — ignorado corretamente, sem efeito, registrado só por transparência.
- **`cargo test`/`tsc --noEmit` limpos nos dois repos** (TruthID: 41/41 Rust; Practice Valuation: `cargo check` limpo). Validação via curl real dos endpoints de handshake/sign-request (busy=409, invalid=400, parking real confirmado).
- **Duas coisas nunca validadas, registradas como pendência**: (1) nenhum clique real na UI do Desktop foi observado (janela do Tauri não é capturável pelas ferramentas de screenshot deste ambiente) — toda validação de UI foi via curl+testes automatizados; (2) os 2 apps nunca rodaram juntos de verdade — colidem na porta 1420 do Vite, e a Practice Valuation trava fora do Docker dela (`unable to open database file`). Não subi o Docker dela sem pedir (disco compartilhado entre os 2 projetos, histórico de disco cheio).
- **Achado de UX/transparência não corrigido**: `SignRequestModal.tsx` nunca mostra a `functionSignature` declarada pelo app terceiro quando a verificação de seletor falha — só o aviso + bytes crus. Fora do escopo negociado, registrado como pendência.
- **Próximo passo**: validar E2E real com os 2 apps rodando juntos (resolver Docker/porta da Practice Valuation); validação em Mainnet (pendência antiga da fatia 1 — bundler + pareamento); corrigir a lacuna de transparência do `SignRequestModal.tsx`; decidir se/quando a fatia 3 vira integração de produção de verdade (hoje é só prova de conceito).

### Sessão 104 — 2026-07-15: corrigida a lacuna de transparência do `SignRequestModal.tsx`

- **Objetivo**: das 4 pendências deixadas pela Sessão 103, o dono do projeto escolheu a única que não depende dele (Docker/porta da Practice Valuation e Mainnet ficam pra depois) — mostrar a `functionSignature` declarada pelo app terceiro quando o seletor não bate contra o `callData`.
- **Fix pequeno e isolado**: no branch `!decoded.verified` do JSX, adicionado `request.functionSignature` (rotulado como não verificado) antes do `callData` cru já existente — nenhuma mudança em `decodeIncomingCall` nem no protocolo Rust, o campo já chegava no `IncomingSignRequest` mas não era renderizado.
- **`tsc --noEmit` limpo, `vitest run` 56/56** (sem testes novos — é puramente uma mudança de apresentação num branch já coberto indiretamente pelos testes de decodificação existentes; nenhum teste unitário isola o JSX do modal ainda).
- **Próximo passo**: as outras 3 pendências continuam abertas — validação E2E real (Docker/porta da Practice Valuation), validação em Mainnet (bundler + pareamento, ação do dono do projeto), e decidir se a fatia 3 vira integração de produção.

### Sessão 105 — 2026-07-15: validação E2E real dos 2 apps rodando juntos, achado que destrava screenshot/clique automatizado em janelas Tauri neste ambiente

- **Objetivo**: atacar a pendência de validação E2E real (TruthID + Practice Valuation rodando ao mesmo tempo), autorizada pelo dono do projeto especificamente pra subir o Docker da Practice Valuation (histórico de disco cheio era só sobre a partição `/`, que não é onde o Docker deste host guarda dados — `Docker Root Dir` já está em `/home`, com 136G livres, então o risco antigo não se aplicava).
- **Achado 1 — bug real no `docker-compose.yml` da Practice Valuation**: nenhum `.dockerignore` existia, então o build enviava ~6GB de contexto (o `src-tauri/target` de builds nativos anteriores) pro daemon Docker a cada rebuild. Criado `desktop/.dockerignore` (`node_modules`, `dist`, `src-tauri/target`, `.git`) nesse repo.
- **Achado 2 — bug real de permissão no volume Docker**: o volume nomeado `cargo-target` é criado pelo Docker com dono `root`, mas o container roda como `user: "1000:1000"` — primeira tentativa de subir morreu com `Permission denied` ao criar `target/debug`. Corrigido rodando `docker compose run --rm --user root --entrypoint sh desktop -c "chown -R 1000:1000 /app/src-tauri/target"` uma vez; depois disso o container sobe normal. Não é um problema do TruthID resolver — fica registrado aqui só porque bloqueava a validação.
- **Colisão de porta 1420 do Vite**: resolvida temporariamente igual da vez anterior — `vite.config.ts`/`tauri.conf.json` da Practice Valuation apontados pra `1425` só nesta sessão (TruthID ficou na 1420 nativa). **Não revertido ainda** — ver Pendências.
- **Achado 3, o mais importante — a limitação "janela do Tauri não é capturável" das Sessões 99/103 tinha uma causa raiz simples, não uma limitação de fato do ambiente**: a sessão do Claude Code roda com `GDK_BACKEND=wayland` no ambiente (herdado do host, Wayland/KWin), o que faz o WebKitGTK do Tauri renderizar como superfície Wayland nativa — invisível pras ferramentas X11 (`xdotool`, `spectacle`). O container da Practice Valuation não herda essa variável (só recebe `DISPLAY`/`XAUTHORITY` no `docker-compose.yml` dela), então já caía em X11/XWayland por padrão e por isso a janela dela sempre apareceu. Forçando `GDK_BACKEND=x11` (+ os mesmos `WEBKIT_DISABLE_DMABUF_RENDERER`/`WEBKIT_DISABLE_COMPOSITING_MODE` que a Practice Valuation já usava) no `npm run tauri dev` nativo do TruthID, a janela do TruthID também passou a aparecer pro `xdotool`/`spectacle`. **Isso destrava validação visual real de UI do Tauri neste ambiente daqui pra frente** — não só nesta feature, qualquer fatia futura que precise de clique real na UI do Desktop.
- **Fluxo completo validado com cliques reais, pela primeira vez**: TruthID Desktop rodando nativo (`GDK_BACKEND=x11 WEBKIT_DISABLE_DMABUF_RENDERER=1 WEBKIT_DISABLE_COMPOSITING_MODE=1 npm run tauri dev`) + Practice Valuation rodando no Docker dela (porta 1425) simultaneamente, ambos com janela real. Sequência clicada de verdade (`xdotool mousemove --window <id> x y click 1`, coordenadas calculadas a partir de screenshots reais via `spectacle -a -b -n`): aba "TruthID Sync" → **Test connection** (`Found TruthID Desktop 0.1.0 on port 47950` — handshake real) → **Send test sign-request** → modal `SignRequestModal.tsx` real aparece no TruthID, mostrando exatamente a correção da Sessão 104 ao vivo (`practiceValuationTestPing()` como função declarada não verificada, `0x` como callData cru, já que o "sign-request de mentira" da fatia 3 é transferência de valor zero sem callData) → **Reject** clicado de verdade → Practice Valuation mostra `Status: rejected` em tempo real. Fecha, pela primeira vez, as pendências "nenhum clique real foi observado" e "fluxo de rejeição nunca confirmado de ponta a ponta" das Sessões 102/103.
- **Caminho de Approve testado até onde dá sem Ledger/WalletConnect real**: clicar Approve abre o modal `ConnectWallet` (WalletConnect/Ledger) em vez de assinar direto — confirma que o gate de `smartAccountAddress` no `handleApprove` funciona corretamente mesmo com uma identidade já logada no dashboard (login e conexão de wallet são coisas distintas, como o desenho original já prescrevia). Não fui adiante (fecharia exigindo Ledger físico ou uma sessão WalletConnect real) — bate com a pendência de Mainnet já conhecida, agora confirmada via UI real em vez de só inferida lendo código. Segundo sign-request também rejeitado pra deixar o estado limpo.
- **Nenhum segredo tocado**: só confirmei que `~/.truthid/bundler_config.json` não existe (`test -f`), nunca li nem escrevi conteúdo.
- **Próximo passo**: reverter a porta temporária da Practice Valuation (`1420` → `1425` em `vite.config.ts`/`tauri.conf.json`) quando a sessão de validação terminar — deixada de pé de propósito pro dono do projeto poder testar o Approve com Ledger/WalletConnect real se quiser. Caminho de Approve (assinatura real via UserOp) continua não confirmado de ponta a ponta — precisa Ledger físico ou WalletConnect real, mais o bundler configurado (pendência antiga da fatia 1, segredo do dono do projeto). Decidir se/quando a fatia 3 vira integração de produção continua em aberto.

---

### Sessão 107 — 2026-07-16: `/truthid/v1/sign-message` implementado — assinatura genérica de mensagem pra apps terceiros

- **Objetivo**: destravar a pendência mais barata registrada pela Sessão 106 (Practice Valuation, Fase 8 dele) — a rota genérica que qualquer app terceiro usa pra pedir uma assinatura `personal_sign` sobre uma mensagem própria, sem nunca segurar segredo, no mesmo molde do `/sign-request` já implementado. `/pin` e o transporte cross-device continuam como pendência separada, não atacados nesta sessão. `/plan` rodado antes de codar.
- **Diferença de desenho em relação ao `/sign-request`**: lá o Rust só aprova/rejeita e o frontend monta/executa a UserOperation; aqui não tem bundler nem wallet — a mensagem final é montada no próprio Rust (`format!("TruthID Message Signing: {appName}:{purpose}")`, nunca vinda direto do chamador, garantindo domain separation e nunca colidindo com o `"TruthID Vault Key v1"` interno do password manager) e a assinatura é feita com a mesma **device key** que `sign_challenge` já usa — sem round-trip pro frontend. O clique de aprovação só libera o oneshot que o Rust está esperando; a resposta HTTP pro app terceiro já sai com a assinatura, resolvida dentro da mesma requisição.
- **Novo módulo `sign_message.rs`** (mirror de `sign_request.rs`): mesmo protocolo de parking/single-flight/timeout (5min) via oneshot, mas com uma segunda closure injetada (`sign`, além do `notify` que já existia) — chamada só depois de um `Approved`, o que manteve o módulo testável sem tocar o keyring do SO (testes usam uma assinatura fake). `purpose` validado contra `^[A-Za-z0-9_.-]{1,64}$` (identificador curto, não texto livre, conforme a nota da Sessão 106).
- **Extração em `lib.rs`**: `sign_challenge` (que já implementava `personal_sign`/EIP-191 pra mensagem string arbitrária) virou um wrapper fino sobre duas funções novas reutilizáveis — `sign_personal_message_raw(priv_bytes, message)` (lógica pura, testável com chave fixa, mesmo padrão de `sign_eip191_hash_raw`) e `sign_personal_message(message)` (busca a device key e chama a anterior) — é essa última que `sign_message.rs` injeta como `sign`. `get_device_key_hex` virou `pub(crate)`.
- **`local_signer_server.rs`**: `SignRequestRouterState` ganhou `sign_messages`/`on_sign_message` ao lado dos campos já existentes de sign-request; `start()` ganhou dois parâmetros novos (mesma forma que os de sign-request); nova rota `/truthid/v1/sign-message`. Todos os call sites de teste existentes (`start_for_test`, os dois testes de sign-request que chamam `start()` direto) ajustados pra passar o estado/notifier novos — nenhum teste pré-existente mudou de comportamento.
- **`lib.rs`**: novo `mod sign_message`, comandos `get_pending_sign_message`/`respond_to_sign_message`, `.manage(Arc<SignMessageState>)`, wiring do evento `"truthid://sign-message"` tanto em `local_signer_start` quanto no `setup()` (mesmo padrão duplicado que já existia pro sign-request, por conta do app rodar o servidor automaticamente no boot e também expor um comando manual).
- **Frontend**: `useIncomingSignMessage.ts` (mirror exato de `useIncomingSignRequest.ts`) + `SignMessageModal.tsx` — bem mais simples que o `SignRequestModal` (sem gate de wallet, sem estágio "signing", sem `smartAccountAddress`), já que a assinatura inteira acontece no Rust. Por transparência (mesma filosofia da correção da Sessão 104 no outro modal), mostra a `message` exata que será assinada, não só o `purpose`. Montado em `App.tsx` ao lado do `SignRequestModal`, nos dois pontos de retorno.
- **Testes**: `cargo test` 49/49 (eram 41 na Sessão 103 + 8 novos: 6 em `sign_message.rs` — parking/assinatura via `sign` injetado/rejeição nunca chama `sign`/concorrência/id errado/timeout — e 2 em `local_signer_server.rs`, round-trip HTTP real via `reqwest` mirror dos testes de `/sign-request`). `npx tsc --noEmit` limpo.
- **Não validado nesta sessão** (mesma situação das fatias 2a/2b originais do `/sign-request`, que só foram validadas de ponta a ponta duas sessões depois, na Sessão 105): nenhum clique real na UI nem chamada HTTP de ponta a ponta contra um app terceiro de verdade — só testes automatizados e revisão manual.
- **Próximo passo**: validar manualmente (curl local + clique real no modal, técnica do `GDK_BACKEND=x11` já destravada na Sessão 105) quando o dono do projeto quiser; depois, `/pin` (proxy de pinning) e o transporte cross-device (LAN/dead-drop) continuam como pendências registradas na Sessão 106, ainda não atacadas.

---

### Sessão 108 — 2026-07-16: cross-device `/sign-message` fatia 1 — Mobile ganha o canal via transporte LAN

- **Objetivo**: destravar a pergunta do dono do projeto ("isso funciona na rede?") sobre o
  `/sign-message` implementado na Sessão 107 (só loopback, `127.0.0.1`). Confirmado que ele quer os
  dois transportes da 13.9 (LAN + dead-drop IPFS/IPNS) eventualmente; pediu pra já começar a
  primeira fatia. `/plan` rodado antes de codar.
- **Investigação encontrou um gap real**: o Mobile não tinha nenhum equivalente ao
  `local_signer_server.rs`/`sign_request.rs` do Desktop — o único servidor HTTP do Mobile era o
  `VaultLanServerService`, 100% específico da entrega da vault key no pareamento. Confirmado
  também, via leitura de `scan_screen.dart`/`popup/main.ts` (extensão), que na 13.9 quem **mostra**
  o QR é o lado sem câmera (a extensão) e quem **escaneia** é o celular — o mesmo padrão vale aqui:
  o app terceiro mostra um QR com o pedido inteiro (`{appName, purpose}` cabe fácil), o celular
  escaneia, e só a resposta (assinatura/rejeição) precisa viajar de volta via LAN.
- **Escopo desta fatia, negociado via `/plan`**: só o lado Mobile + só transporte LAN (dead-drop
  IPFS/IPNS fica pra uma fatia 2, mesma sequência que a 13.9 seguiu) + só `/sign-message` (não
  `/sign-request`, mais simples, sem bundler/UserOp envolvidos). O lado "requisitante" (app
  terceiro que gera o QR e varre a LAN) não existe em nenhum repositório ainda — fora de escopo,
  mesmo princípio já registrado em `local_signer_server.rs` ("precisa ser espelhado manualmente do
  lado do app terceiro").
- **Novo `mobile/lib/services/remote_signer_lan_server.dart`**: mirror estrutural exato do
  `VaultLanServerService` (bind na primeira porta livre, serve 1 `GET /session/<id>` com
  `{"blob": base64}`, 404 uniforme, fecha no timeout) — módulo separado, bloco de portas próprio
  (`48050-48054`, distinto de `47850-54` Vault LAN e `47950-54` Desktop local_signer), mesma razão
  que o Desktop já mantém o canal de terceiros fora de tudo que é Vault.
- **Novo `mobile/lib/screens/sign_message_approval_screen.dart`**: schema de QR v1
  (`action: 'truthid-sign-message', v, sessionId, ephemeralPubKey, expiresAt, appName, purpose`),
  validação de `purpose` com a **mesma regex exata** do Rust (`^[A-Za-z0-9_.-]{1,64}$`) e a mesma
  construção de mensagem (`'TruthID Message Signing: $appName:$purpose'`, nunca aceita pronta do
  QR — mesmo motivo de domain separation do lado Desktop). Approve assina via
  `DeviceKeyService.signChallenge` (já existia, `personal_sign` genérico) e cifra via
  `EciesService.encrypt` (já existia) antes de servir; Reject serve `{"status":"rejected"}` cifrado
  do mesmo jeito — os dois usam os mesmos nomes de campo (`status`/`message`/`signature`) que o
  `SignMessageResponse` do Rust, pra um app terceiro reconhecer o mesmo formato nos dois canais.
- **Roteamento**: `main.dart._openScanner` ganhou `else if (action == 'truthid-sign-message')` ao
  lado dos dois já existentes (`truthid-auth`, `truthid-vault-session`).
- **Testes**: novo `test/services/remote_signer_lan_server_test.dart` (`test()` puro, bind e HTTP
  reais via `HttpClient`/`Socket` — não `testWidgets`, pra evitar o travamento de I/O real dentro de
  `FakeAsync` já documentado na Sessão 98) + novo
  `test/screens/sign_message_approval_screen_test.dart` (`testWidgets`, `DeviceKeyService`/
  `EciesService`/`RemoteSignerLanServer` mockados via `mocktail`, nunca I/O real). `flutter test`
  188/188 (era 174 + 14 novos), `flutter analyze` limpo (mesmos 8 avisos pré-existentes).
- **Não validado nesta sessão** (mesma situação de toda fatia da 13.9 até validação em hardware
  real numa sessão futura): nenhuma troca de ponta a ponta com um app terceiro de verdade — não
  existe lado requisitante em nenhum repositório ainda, então não há como gerar um QR real e
  escanear no celular físico.
- **Próximo passo**: lado requisitante de referência (Practice Valuation ou um demo no TruthID
  Desktop) pra validar de ponta a ponta em hardware real; depois, fatia 2 (dead-drop IPFS/IPNS,
  mesmo padrão da 13.9 fatia 2a/2b) e o mesmo transporte pro canal `/sign-request`. `/pin` continua
  como pendência separada.

---

### Sessão 109 — 2026-07-16: cross-device `/sign-message` fatia 2 — dead-drop IPFS/IPNS ao lado da LAN

- **Objetivo**: das opções deixadas em aberto pela Sessão 108, o dono do projeto escolheu a fatia 2
  (dead-drop IPFS/IPNS) em vez do lado requisitante de referência ou do transporte pro
  `/sign-request` — mesma sequência que a 13.9 seguiu (LAN primeiro, dead-drop depois). Só o lado
  Mobile de novo (publicar); não existe consumidor de referência em nenhum repositório, mesmo
  princípio já registrado na Sessão 108.
- **Achado que encurtou o trabalho**: `IpfsPinClient.publishDeadDrop(sessionIdHex, content,
  providers)` (`mobile/lib/services/ipfs_pin_client.dart`, feito na 13.9 fatia 2a) já é uma
  primitiva genérica — não amarrada a vault — então não foi preciso nenhum código novo de
  IPFS/IPNS, só reaproveitar a mesma chamada que `vault_session_screen.dart` já faz.
- **`sign_message_approval_screen.dart`**: mirror exato do padrão de `vault_session_screen.dart` —
  novos campos `ipfsPinClient`/`pinningProviderService` (injetáveis, default real), `_deadDropIpnsName`/
  `_deadDropError` de estado, e `_deliver` agora dispara `_publishDeadDrop` em paralelo com
  `_lanServer.serveOnce` (nunca sequencial, nunca lança — mesma decisão travada da 13.9: uma falha
  do dead-drop, ex. sem provider Kubo configurado, não pode derrubar o transporte LAN que já
  funciona sozinho). Tela de "Sent" ganhou a mesma nota condicional ("Dead-drop backup published"
  vs "unavailable this time") que `vault_session_screen.dart` já mostra.
- **Testes**: `test/screens/sign_message_approval_screen_test.dart` ganhou `MockIpfsPinClient`/
  `MockPinningProviderService` + grupo novo "Dead-drop (IPFS/IPNS)" (provider configurado publica
  em paralelo e mostra a mensagem certa; erro no dead-drop não impede o "Sent" via LAN). Setup
  default estabiliza `publishDeadDrop` pra devolver `null` (mimetiza o early-return real sem
  provider), evitando que os testes já existentes (Approve/Reject/timeout) acidentalmente
  exercitem o caminho de erro do dead-drop sem querer. `flutter test` 190/190 (188 + 2 novos),
  `flutter analyze` limpo (mesmos 8 avisos pré-existentes).
- **Não validado nesta sessão** (mesma pendência da Sessão 108, sem mudança): nenhuma troca real
  ponta a ponta — não existe app terceiro de referência que gere QR e consuma a resposta via
  IPNS, só testes automatizados e o mesmo Kubo real que já validou a derivação IPNS na 13.9.
- **Próximo passo**: lado requisitante de referência (Practice Valuation ou demo no TruthID
  Desktop) continua sendo o item que mais destrava validação E2E real, tanto pro `/sign-message`
  quanto pra decidir se vale a pena levar o mesmo transporte cross-device pro `/sign-request`.
  `/pin` continua como pendência separada, não atacada.

---

### Sessão 110 — 2026-07-16: cross-device `/sign-request` fatia 1 — Mobile ganha o canal via
transporte LAN

- **Objetivo**: das pendências deixadas pela Sessão 109, o dono do projeto escolheu levar o
  mesmo padrão cross-device do `/sign-message` (Mobile como "responder" via QR + LAN) pro
  `/sign-request` — que hoje só funciona em loopback no Desktop. `/plan` rodado antes de codar;
  duas perguntas negociadas explicitamente: (1) confirmado que o Mobile vira o responder remoto
  (o Desktop nunca abre `local_signer_server.rs` pra LAN — decisão de segurança deliberada da
  fatia 2a, "nunca `0.0.0.0`"); (2) escopo desta sessão é só transporte **LAN**, dead-drop
  IPFS/IPNS fica marcado como fatia 2 pra depois (mesma sequência do sign-message).
- **Diferença real em relação ao `/sign-message`**: lá o Mobile só assina (a resposta HTTP já
  sai assinada). Aqui o Mobile precisa **assinar E executar** a UserOperation (bundler + espera
  de recibo, até ~60s) antes de responder — é isso que o Desktop já faz em
  `SignRequestModal.tsx`/`userOpExecutor.ts`. Investigação confirmou que o núcleo genérico já
  existia: `SessionCreator._executeViaUserOp({smartAccountAddress, dest, value, innerCallData})`
  (`mobile/lib/services/session_creator.dart`) já é o mesmo motor usado por
  `createSession`/`revokeSession`/`withdraw`/`updateVault` — só faltava expor um método público
  fino (`executeArbitraryCall`) que repassa os mesmos parâmetros sem lógica nova.
- **Novo `mobile/lib/screens/sign_request_approval_screen.dart`** (mirror estrutural de
  `SignMessageApprovalScreen`, com duas diferenças reais): schema de QR v1
  (`action: 'truthid-sign-request', v, sessionId, ephemeralPubKey, expiresAt, appName, dest,
  value, callData, functionSignature` — nunca `smartAccountAddress`, resolvido sempre localmente
  a partir da identidade pareada no celular, mesma postura de `SignRequestBody` no Rust, que nem
  tem esse campo). Dois estados novos no enum: `loading` (resolve a smart account via
  `LocalStorageService.getPairedIdentityId/Username` + `BlockchainService.getIdentityByUsername`,
  mirror do padrão já usado em `wallet_screen.dart`) e `executing` (roda a UserOp de verdade).
  Verificação de seletor (`keccak256(functionSignature)[0:4]` vs `callData`, mesma técnica já
  usada em `blockchain_service.dart` pra outros seletores) rotula `functionSignature` como
  verified/unverified sem bloquear — mesma decisão consciente da fatia 2b do Desktop (aprovação
  humana é o ponto de confiança final). **Achado de design importante, espelhando o
  `SignRequestModal.tsx` do Desktop**: uma falha de execução (bundler rejeitar, etc.) não vira um
  erro local silencioso — ainda assim dispara `_deliver({'status': 'failed', 'error': ...})`, pra
  o app terceiro saber o que aconteceu, exatamente como o Desktop já faz (`respond_to_sign_request`
  com `outcome: "failed"` mesmo quando a execução lança). Os nomes de campo da resposta
  (`status`/`userOpHash`/`transactionHash`/`error`) espelham exatamente `SignRequestResponse` do
  Rust, pra um futuro app requisitante tratar os dois canais de forma uniforme. `RemoteSignerLanServer`
  (porta `48050-48054`) reaproveitado sem nenhuma mudança — já era genérico o bastante.
- **Roteamento**: `main.dart._openScanner` ganhou `else if (action == 'truthid-sign-request')`
  ao lado dos 3 já existentes.
- **Testes**: `mobile/test/services/session_creator_test.dart` ganhou grupo `executeArbitraryCall`
  (2 testes, mesmo padrão do grupo `withdraw`). Novo
  `mobile/test/screens/sign_request_approval_screen_test.dart` (mocka `SessionCreator`/
  `BlockchainService`/`LocalStorageService`/`BundlerConfigService`/`EciesService`/
  `RemoteSignerLanServer` via `mocktail`), casos: validação de schema, não pareado, seletor
  batendo/não batendo, Approve com sucesso (mostra `userOpHash` no "Sent"), Approve com exceção
  (ainda assim entrega `status: failed`), timeout, Reject nunca chama `executeArbitraryCall`.
  **Achado no caminho**: o teste de Reject falhava com "would not hit test" — a tela pendente tem
  mais conteúdo que a de sign-message (3 `InfoRow` + callData cru), então o botão Reject cai fora
  do viewport padrão de teste (800×600) sem rolar primeiro; corrigido com
  `tester.ensureVisible(find.text('Reject'))` antes do `tap`. `flutter analyze` limpo (mesmos 8
  avisos pré-existentes), `flutter test` 205/205 (190 + 13 novos: 2 em `session_creator_test.dart`
  + ~23 na tela nova, contando `setUpAll`/`tearDownAll`).
- **Não validado nesta sessão** (mesma situação de toda fatia anterior): nenhuma troca real ponta
  a ponta — não existe app requisitante de referência em nenhum repositório ainda, só testes
  automatizados e revisão manual do fluxo lendo o código.
- **Próximo passo**: fatia 2 (dead-drop IPFS/IPNS) pro `/sign-request`, reaproveitando
  `IpfsPinClient.publishDeadDrop` sem código novo de IPFS (mesma economia que a fatia 2 do
  sign-message teve); lado requisitante de referência continua sendo o item que mais destrava
  validação E2E real de tudo; `/pin` continua como pendência separada, não atacada.

---

### Sessão 111 — 2026-07-16: cross-device `/sign-request` fatia 2 — dead-drop IPFS/IPNS ao lado da LAN

- **Objetivo**: das pendências deixadas pela Sessão 110, o dono do projeto escolheu fatia 2
  (dead-drop IPFS/IPNS) do `/sign-request` em vez do app requisitante de referência ou de `/pin`
  — fecha o mesmo padrão de dois transportes em paralelo (LAN + dead-drop) nos dois canais
  genéricos (`/sign-message` e `/sign-request`), mesma sequência que a Sessão 109 já fez pro
  `/sign-message`.
- **Mudança mecânica**: `IpfsPinClient.publishDeadDrop` já era genérico (achado da Sessão 109),
  então a fatia foi um mirror exato do que `sign_message_approval_screen.dart` já tinha —
  `sign_request_approval_screen.dart` ganhou os mesmos campos injetáveis
  (`ipfsPinClient`/`pinningProviderService`), estado (`_deadDropIpnsName`/`_deadDropError`), e
  `_deliver` passou a disparar `_publishDeadDrop` em paralelo com `_lanServer.serveOnce` (nunca
  sequencial, nunca lança) tanto no caminho de Approve (sucesso ou falha de execução) quanto no
  de Reject — igual ao `/sign-message`, o dead-drop nunca decide o status (`sent`/`timeout`),
  só é best-effort ao lado. Tela de "Sent" ganhou a mesma nota condicional ("Dead-drop backup
  published" vs "unavailable this time"). Nenhum código novo de IPFS/IPNS foi necessário.
- **Testes**: `sign_request_approval_screen_test.dart` ganhou `MockIpfsPinClient`/
  `MockPinningProviderService` + grupo "Dead-drop (IPFS/IPNS)" (mirror exato dos 2 testes do
  `/sign-message`: provider configurado publica em paralelo e mostra a mensagem certa; erro no
  dead-drop não impede o "Sent" via LAN). `flutter analyze` limpo (mesmos 8 avisos
  pré-existentes), `flutter test` 207/207 (205 + 2 novos).
- **Não validado nesta sessão** (mesma pendência de toda fatia anterior, sem mudança): nenhuma
  troca real ponta a ponta — não existe app requisitante de referência em nenhum repositório
  ainda, só testes automatizados.
- **Próximo passo**: com LAN + dead-drop fechados nos dois canais genéricos
  (`/sign-message` e `/sign-request`), o item que mais destrava validação E2E real de tudo passa
  a ser só um: o app requisitante de referência (Practice Valuation ou um demo no TruthID
  Desktop). `/pin` continua como pendência separada, não atacada.

---

### Sessão 112 — 2026-07-16: app requisitante de referência — Practice Valuation vira cliente
cross-device do `/sign-request`

- **Objetivo**: fechar a pendência que mais bloqueava validação E2E real de toda a frente de
  delegação de assinatura desde a Sessão 108 — nenhum app terceiro real gerava QR nem consumia a
  resposta via LAN. O dono do projeto escolheu explicitamente Practice Valuation (outro
  repositório, `~/Documents/workspace/practice-valuation`, tocar nele confirmado explicitamente)
  em vez de um demo no TruthID Desktop, só canal `/sign-request` (mais representativo do uso real
  planejado — pagar gás via smart account — e já tinha uma PoC loopback em
  `commands/truthid.rs::send_test_sign_request`), e só transporte **LAN** nesta fatia — dead-drop
  IPFS/IPNS fica pra depois (exigiria portar a derivação de nome IPNS — HKDF+Ed25519+CID/base36 —
  pro Rust do zero, risco de interop real demais pra empacotar junto). `/plan` rodado antes de
  codar.
- **Reaproveitamento pesado, pouco código novo do zero**: o decrypt ECIES em Rust já existia como
  teste (`dart_produced_blob_decrypts_correctly` em `desktop/src-tauri/src/lib.rs` do TruthID) —
  virou o novo `ecies.rs` do Practice Valuation quase sem alteração, com o mesmo vetor cruzado
  reaproveitado como teste. A varredura LAN (`lan_sweep.rs`, novo) é um port direto de
  `extension/src/session/lanDiscovery.ts` (mesma simplificação de /24 fixo, mesmo desenho de
  lotes paralelos) — só trocando `Promise.all` por `futures::future::join_all` e
  `chrome.system.network` pela crate `if-addrs`.
- **2 comandos novos em `commands/truthid.rs`** (mesmo arquivo da PoC loopback, não um módulo à
  parte): `create_cross_device_sign_request` (gera par efêmero + sessionId + JSON do QR, reusa as
  mesmas `TEST_DEST_ADDRESS`/`TEST_FUNCTION_SIGNATURE` da PoC loopback — mesma transferência de
  valor zero pro endereço de burn, mesma decisão da Sessão 103) e
  `await_cross_device_sign_request_response` (varre a LAN em laço a cada 2s até responder ou
  expirar, decifra e decodifica pro mesmo `TruthIdSignResult` já existente). Dois comandos
  stateless em vez de um esquema de evento Tauri — mesmo padrão já estabelecido no arquivo, sem
  introduzir arquitetura nova.
- **Achado incidental, corrigido no caminho**: `TruthIdSignResult` nunca tinha
  `#[serde(rename_all = "camelCase")]`, mas tanto o `SignRequestResponse` do TruthID Desktop
  quanto o resultado que o Mobile entrega via LAN mandam `userOpHash`/`transactionHash` em
  camelCase — os campos (sendo `Option<T>`, opcionais-quando-ausentes por padrão do serde) nunca
  davam erro, só ficavam `None` em silêncio mesmo com um hash real na resposta. Bug pré-existente
  desde a Sessão 103, nunca pego porque só o caminho de Reject foi validado com clique real na
  Sessão 105 (que não tem hash pra mostrar). Corrigido com uma linha; sem isso, a nova fatia
  cross-device herdaria o mesmo problema.
- **Frontend**: `qrcode`/`@types/qrcode` adicionados (mesma lib que a extensão já usa), novo
  `renderQr.ts` (mirror de 5 linhas), nova seção em `TruthIdPanel.tsx` — "Start cross-device
  request" gera a sessão, renderiza o QR num canvas e já dispara a varredura automaticamente (sem
  esperar clique — mesma filosofia de "já começa a servir assim que aprovar" do lado Mobile).
- **Testes**: `cargo test` 59/59 (7 novos: vetor cruzado ECIES + round-trip de par efêmero gerado
  em `ecies.rs`; `subnet_hosts` puro + 3 casos de `fetch_session_blob` contra um `TcpListener` de
  teste real, mesmo espírito "I/O real, nunca mock de rede" que `remote_signer_lan_server_test.dart`
  já segue do lado Mobile, em `lan_sweep.rs`). `cargo check`/`cargo clippy` limpos (mesmos avisos
  pré-existentes, não relacionados). `tsc --noEmit` limpo.
- **Validado nesta sessão com clique real** (mesmo espírito da Sessão 105): Practice Valuation
  subido via `./dev.sh` real (Docker, `network_mode: host`), janela capturada e clicada de verdade
  (`xdotool`/`spectacle`, sem precisar do fix `GDK_BACKEND=x11` da Sessão 105 — só necessário pro
  Tauri nativo do TruthID, o Docker da Practice Valuation já era X11 puro). Clique em "Start
  cross-device request" → `create_cross_device_sign_request` respondeu, QR renderizado de verdade
  no `<canvas>`, `await_cross_device_sign_request_response` disparou sozinho e a tela foi pra
  "Waiting for your phone..." sem nenhum erro/panic nos logs do container — confirma que a
  integração IPC (nomes de parâmetro camelCase, schema do QR, encadeamento das duas mutations)
  funciona de ponta a ponta no lado do requisitante.
- **Não validado nesta sessão** (não há celular físico disponível neste ambiente pra escanear):
  a troca real com o Mobile — QR escaneado, aprovação, UserOp executada, resposta decifrada de
  volta no Practice Valuation. É o único passo que falta pra fechar completamente a pendência
  "nenhuma troca ponta a ponta real foi observada", aberta desde a Sessão 108.
- **Próximo passo**: dono do projeto rodar `./dev.sh` no Practice Valuation com o celular físico
  pareado por perto, clicar "Start cross-device request" e escanear o QR de verdade — fecha a
  última pendência real desta frente inteira (LAN + dead-drop nos dois canais, requisitante de
  referência). Depois: fatia 2 (dead-drop IPFS/IPNS) pro `/sign-request` levar o mesmo padrão até
  o Practice Valuation (hoje só o Mobile publica; o requisitante ainda só sabe consumir LAN), e
  `/pin` continua como pendência separada, não atacada.

---

### Sessão 113 — 2026-07-16: dead-drop IPFS/IPNS pro app requisitante (Practice Valuation)

- **Objetivo**: dono do projeto pediu pra fazer a fatia 2 (dead-drop IPFS/IPNS) do lado
  requisitante antes de testar com o celular físico, pra rodar **um único teste de hardware
  cobrindo os dois transportes de uma vez** em vez de dois separados. `/plan` rodado antes de
  codar. Lado que publica (Mobile) não muda — só o lado que consome (Practice Valuation) precisa
  recalcular o mesmo nome IPNS a partir do `sessionId` e tentar buscar.
- **Risco principal mitigado com um vetor cruzado já existente**: a derivação do nome IPNS
  (HKDF-SHA256 → seed Ed25519 → protobuf libp2p → multihash identity → CIDv1 → base36) nunca
  tinha sido implementada em Rust neste projeto — mas já tinha um vetor validado contra um Kubo
  real, reaproveitado como teste (`sessionIdHex = "000102030405060708090a0b0c0d0e0f"` →
  `k51qzi5uqu5diyq5i3xkj8knjqw2jewheim4x3ghwm0a8bh7t6ty3zv9x5f3oh"`, o mesmo par usado em
  `mobile/test/services/ipns_key_service_test.dart` e `extension/src/session/ipnsKey.test.ts`).
  **Bateu de primeira** — o port manual (protobuf/multihash/CID montados à mão, sem crate, mesma
  decisão consciente que o Dart já tinha tomado; só `ed25519-dalek` novo como dependência de
  verdade) ficou byte-a-byte compatível com Kubo/Dart/TS.
- **Novo `src/ipns_key.rs`**: `compute_ipns_name(session_id_hex)`, port direto de
  `computeIpnsName` (`ipnsKey.ts`)/`ipns_key_service.dart`, só a metade pública da derivação (o
  Practice Valuation nunca precisa da chave privada nem importa nada num Kubo, isso é trabalho só
  do Mobile). Base36 "estilo base58" implementado à mão (algoritmo clássico de multiply-add sobre
  um vetor de dígitos, evita depender de crate de bignum pra um valor usado uma vez só).
- **Novo `src/dead_drop.rs`**: `try_fetch_dead_drop(session_id_hex, client)`, port de
  `tryFetchDeadDrop` (`extension/src/session/deadDropPolling.ts`) — gateway público `ipfs.io`,
  query `cachebust`, timeout 10s, qualquer status não-200 ou erro de rede vira `None`, nunca
  lança (o gateway responde `500`, não `404`, quando o nome ainda não propagou).
- **`commands/truthid.rs`**: `await_cross_device_sign_request_response` ganhou um segundo
  transporte em paralelo com cadências diferentes — LAN a cada 2s (como já era), dead-drop a
  cada ~20s (propagação de IPNS leva até 1-2min, bater num gateway público a cada 2s seria
  agressivo demais; mesma ordem de grandeza do `chrome.alarms` da extensão, 1/min). O primeiro
  transporte que achar um blob decide; os dois entregam exatamente o mesmo formato de blob ECIES,
  mesmo `ecies::decrypt`/`TruthIdSignResult` de sempre.
- **Frontend**: só cosmético — "Waiting for your phone..." virou "Waiting for your phone (LAN +
  IPFS backup)...", deixando claro pro usuário que os dois transportes estão ativos.
- **Testes**: `cargo test` 64/64 (5 novos, todos em `ipns_key.rs`, incluindo o vetor cruzado).
  `cargo check`/`cargo clippy` limpos (mesmos avisos pré-existentes). `tsc --noEmit` limpo.
- **Validado nesta sessão com clique real** (mesmo padrão da Sessão 112): `./dev.sh` subido de
  novo, QR renderizado, texto novo "LAN + IPFS backup" confirmado na tela, e a varredura seguiu
  rodando establemente por 15s+ sem nenhum erro/panic nos logs — confirma que a primeira
  tentativa de dead-drop (que falha graciosamente, já que não existe sessão publicada de
  verdade) não quebra o laço nem trava a UI.
- **Achado no caminho**: a edição anterior (Sessão 112) tinha derrubado sem querer o cabeçalho
  "## Como Usar Este Arquivo" no fim deste arquivo — corrigido nesta sessão.
- **Não validado nesta sessão** (mesma pendência, sem mudança): troca real com celular físico —
  agora cobrindo os dois transportes de uma vez, é o único passo que falta pra fechar de vez a
  pendência de ponta a ponta aberta desde a Sessão 108.
- **Próximo passo**: dono do projeto rodar `./dev.sh` com o celular físico por perto e escanear o
  QR de verdade — testa LAN e dead-drop no mesmo teste de hardware. `/pin` continua como
  pendência separada, não atacada.

---

### Sessão 114 — 2026-07-16: primeira troca real ponta a ponta com celular físico — fecha a
pendência aberta desde a Sessão 108

- **Objetivo**: dono do projeto pediu pra rodar o teste de hardware combinado (LAN+dead-drop)
  guiado passo a passo, incluindo emparelhar o celular via adb (depuração sem fio) pra reinstalar
  o Mobile atualizado. Achado logo de cara: o APK instalado no celular era de **2026-07-07**,
  anterior a toda a Fase de `/sign-request` cross-device (Sessões 108-113) — precisou de
  `./dev.sh build` + `adb pair`/`adb connect`/`adb install -r` antes de qualquer teste real.
- **Achado paralelo, registrado por transparência**: a tela de configurar provedor de pinning no
  Mobile (`pinning_providers_screen.dart`) existe no código mas **não está conectada a nenhuma
  navegação no app** — não tem como abrir ela hoje pela UI. Não bloqueou o teste desta sessão
  (LAN venceu antes do dead-drop ter chance de importar), mas é uma lacuna real a fechar numa
  sessão futura se dead-drop precisar ser validado especificamente.
- **Primeira troca real ponta a ponta confirmada**: Practice Valuation gerou o QR real, o celular
  físico (Samsung SM_S731B, app recém-instalado) escaneou, aprovou, e o resultado voltou via LAN
  — primeiro teste mostrou `Status: executed`.
- **Bug real achado e corrigido só porque testamos com hardware de verdade**: o `userOpHash`/
  `transactionHash` não apareciam na tela, só "Status: executed". Causa: o `#[serde(rename_all =
  "camelCase")]` que a Sessão 112 adicionou em `TruthIdSignResult` corrige a desserialização do
  JSON que chega de fora (Mobile/Desktop, sempre camelCase) mas **também** muda a serialização de
  volta pro Tauri/JS — e o frontend (`TruthIdPanel.tsx`) lê os campos em snake_case
  (`user_op_hash`/`transaction_hash`), mesmo padrão que `TruthIdHandshakeResult` já usa em todo o
  resto do arquivo. Os dois lados (desserializar o JSON alheio vs serializar de volta pro Tauri)
  precisam de convenções de nome diferentes. Corrigido separando em dois tipos:
  `TruthIdWireResult` (só `Deserialize`, `rename_all = "camelCase"`, usado internamente pra
  parsear a resposta do loopback e do blob decifrado) e `TruthIdSignResult` (só `Serialize`, sem
  `rename_all`, o que volta pro Tauri) com um `impl From<TruthIdWireResult> for TruthIdSignResult`
  no meio. **Nem `cargo test`/`tsc` nem a Sessão 112 pegaram isso** — os campos são `Option<T>`,
  então uma chave ausente nunca gera erro de parse, só vira `None`/`undefined` em silêncio; só
  apareceu testando com um celular físico de verdade e prestando atenção ao que a tela mostrava.
  `cargo test` continua 64/64, `cargo check`/`clippy` limpos.
- **Segundo teste, após a correção**: `Status: failed`, com a mensagem de erro completa
  (`UserOperation reverted with reason: AA26 over verificationGasLimit, code: -32500`) aparecendo
  corretamente na tela — confirma que a correção funcionou (o campo `error` decodifica certo) e,
  de brinde, valida o caminho de falha (mesma decisão da Sessão 110: erro de execução ainda assim
  vira uma resposta entregue, não um erro local silencioso).
- **AA26 é uma pendência separada, não um bug do transporte**: erro padrão ERC-4337 — a etapa de
  verificação da smart account (`validateUserOp`) consumiu mais gás do que o bundler (Pimlico)
  reservou pra essa etapa. Não tem relação com QR/LAN/dead-drop/decriptação, que é exatamente o
  que esta sessão validou. Mesma classe da pendência já registrada em
  `project_delegated_signing.md` ("Validação real em Mainnet nunca confirmada").
- **Fecha a pendência aberta desde a Sessão 108**: "nenhuma troca ponta a ponta real foi
  observada" — agora foi, duas vezes, com hardware físico real, cobrindo tanto o caminho de
  sucesso quanto o de falha.
- **Próximo passo**: investigar o AA26 (parâmetros de gas do `SessionCreator.executeArbitraryCall`
  no Mobile, ou config do bundler) se o dono do projeto quiser seguir essa frente; conectar
  `pinning_providers_screen.dart` a alguma navegação real se dead-drop precisar ser validado
  especificamente; `/pin` continua como pendência separada, não atacada.

---

## Como Usar Este Arquivo

1. **Ao começar uma sessão**: Diga ao Claude Code "leia o PROJECT_STATE.md e me ajude a continuar"
2. **Ao terminar uma sessão**: O Claude atualiza o Log de Sessões e marca etapas concluídas
3. **Ao tomar uma decisão**: Registrar em "Decisões de Arquitetura em Aberto"
4. **Ao mudar de máquina**: Sincronizar via git (recomendado: `git init` neste diretório)
