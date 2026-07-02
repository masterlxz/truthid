# TruthID — Estado do Projeto

> Este arquivo é o centro de controle do projeto. Atualizado a cada sessão de trabalho.
> Pode ser lido por qualquer instância do Claude Code em qualquer máquina para retomar o contexto.
> Última atualização: 2026-07-02 (Sessão 59 — Fase 14.6: utilitário off-chain computeSmartAccountAddress concluído, 21 testes desktop passando)

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
Fase 13 — TruthID Vault (gerenciador de senhas) [~] Em andamento (13.1–13.7 ✓, 13.8–13.9 pendentes)
Fase 14 — Smart Account (ERC-4337, Self-Funded)  [~] Em andamento (14.1–14.5 ✓, 14.6–14.12 pendentes)
```

---

## Checklist antes do próximo release oficial

**Rodar `/code-review` (considerar `ultra`) sobre `contracts/` inteiro** antes de publicar
qualquer versão que inclua a Fase 13 (Vault) ou a Fase 14 (Smart Account) em produção —
não só revisar arquivo por arquivo conforme escrito, mas uma passada final olhando os
contratos como um todo (interações entre `IdentityRegistry`/`DeviceRegistry`/
`RecoveryManager`/`TruthIDAccount`/`VaultRegistry`).

**Por quê**: motivado pela Sessão 53 — o `/code-review` rodado sobre um único contrato
recém-escrito (`TruthIDAccount.sol`) já achou uma falha crítica (device sequestrando a
identidade via `IdentityRegistry`/`RecoveryManager`, ver débito resolvido na Sessão 53) e,
durante a própria correção, uma tentativa de otimização introduziu um bug novo (bits não
mascarados numa extração via assembly) que só foi pego numa releitura cuidadosa antes do
commit. Contratos on-chain não têm "hotfix" depois de deployados na mainnet — o custo de
revisar demais é só tempo; o custo de revisar de menos pode ser fundos ou identidades
perdidos permanentemente. Ver também o débito #17 (aberto, não bloqueia o
progresso mas deve ser resolvido ou conscientemente aceito antes do release) — #18 e o
#20 (achado na mesma correção) já foram resolvidos na Sessão 55.

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
| 17 | `contracts/src/IdentityRegistry.sol:80` | `createIdentity(username, controller)` não verifica se `msg.sender` tem qualquer autorização sobre o `controller` informado. Achado (CONFIRMED) no `/code-review` da Sessão 53, rodado sobre o diff da 14.1+14.2. Permite squatting/griefing: qualquer um pode "ocupar" um endereço alheio (inclusive o CREATE2 pré-computado de uma smart account que ainda vai ser deployada) chamando `createIdentity` primeiro, bloqueando o dono legítimo com `AddressAlreadyHasIdentity`. Recuperável (o dono, uma vez com controle do endereço, pode chamar `transferController` pra liberar e tentar de novo), mas é uma DoS/griefing gratuita para o atacante. | Decisão de design pendente do dono do projeto — opções: (a) exigir uma assinatura do `controller` provando consentimento (mais forte, mas complica o fluxo de smart account pré-deploy, que ainda não existe pra assinar nada); (b) esquema commit-reveal como o `registerDevice` já usa; (c) aceitar o risco como está (griefing é recuperável, não é perda permanente de fundos/identidade). Nenhuma teve endosso ainda. |
| ~~18~~ | ~~`contracts/src/TruthIDAccount.sol`~~ | ~~`_isDeviceCallAllowed` retorna via `abi.decode`, que pode reverter (em vez de retornar `SIG_VALIDATION_FAILED` de forma limpa) se um signer de tier device mandar `callData` com o seletor certo mas payload truncado/malformado. Achado (PLAUSIBLE) no `/code-review` da Sessão 53.~~ | **RESOLVIDO — Sessão 55**. Decode movido pra função nova `_decodeExecuteBatchDest` (`external pure`), chamada via `try/catch` em vez de `abi.decode` direto — qualquer revert/panic do decode vira `false` (→ `SIG_VALIDATION_FAILED`) em vez de propagar. Evitou reintroduzir assembly manual na área que já causou o bug do débito relacionado à máscara (item 4 do review da Sessão 53). Testes novos em `contracts/test/TruthIDAccount.t.sol` (não existia antes). |
| 19 | `contracts/src/RecoveryManager.sol` | Etapa 14.3 (Sessão 54) adicionou `emergencyWithdraw(address recipient)` na `TruthIDAccount`, chamável só pelo `RecoveryManager` — mas nada no `RecoveryManager.sol` de fato chama essa função (`executeRecovery` só invoca `IdentityRegistry.recoverController`, não rastreia endereço de smart account nenhum). A função fica funcional mas inalcançável até essa conexão ser feita. | Decisão de design pendente: como o `RecoveryManager` vai descobrir o endereço da smart account antiga (hoje só disponível via evento `ControllerTransferred` do `IdentityRegistry`, não em storage) e como/quando invocar `emergencyWithdraw` (dentro do próprio `executeRecovery`, ou uma função separada chamada depois). Nenhuma das etapas 14.4–14.12 do roadmap cobre isso explicitamente — vale decidir se é uma etapa nova ou parte da 14.8 (sync de devices/smart account). |
| ~~20~~ | ~~`contracts/src/TruthIDAccount.sol:69`~~ | ~~A constante `_SECP256K1N_DIV_2` (limiar low-s, EIP-2) tinha 1 dígito hex a menos (`...681B20A` em vez de `...681B20A0`), fazendo o valor real ser `n/32` em vez de `n/2` — rejeitava ~97% das assinaturas canônicas válidas como `SIG_VALIDATION_FAILED`, afetando owner e devices igualmente (checagem roda antes de identificar quem assinou). Introduzido junto com a 14.2 (Sessão 53), nunca pego porque não havia teste de caminho feliz pra `TruthIDAccount` até agora.~~ | **RESOLVIDO — Sessão 55**. Achado ao escrever o teste de regressão do débito #18 (caminho feliz de `executeBatch` falhava mesmo com assinatura correta). Corrigido adicionando o `0` faltante; valor conferido matematicamente (`== n // 2`) antes de commitar. |
| 21 | `contracts/src/TruthIDAccountFactory.sol:54,65` | `createAccount` sempre recomputa o hash completo do init code (via `getAddress`, que copia o creation bytecode inteiro da `TruthIDAccount` pra memória e faz `keccak256`) antes de checar `extcodesize` — desperdiça gas no caminho idempotente (conta já existe). Além disso `_salt(owner_)` é calculado duas vezes por chamada de deploy (uma dentro de `getAddress`, outra inline no `new{salt:...}`). Achado (CONFIRMED) no `/code-review` da Sessão 57, sobre o diff da 14.4. | Cachear o salt calculado uma vez e reusar; considerar uma mapping `owner => account` checada antes de tocar em `getAddress`/creationCode, pra curto-circuitar o caminho idempotente sem custo. Baixo impacto (gas, não correção). |
| 22 | `contracts/src/TruthIDAccountFactory.sol:56`, `contracts/test/TruthIDAccountFactory.t.sol:74` | Checagem de `extcodesize` via assembly manual, duplicada literalmente entre produção e teste. Achado (CONFIRMED) no `/code-review` da Sessão 57. | Trocar por `predicted.code.length > 0` (builtin, mesmo opcode, sem assembly) nos dois lugares. |
| 23 | `contracts/script/Deploy.s.sol:13`, `contracts/test/TruthIDAccountFactory.t.sol:18` | Endereço `ENTRY_POINT_V07` hardcoded de forma independente em dois arquivos — se o EntryPoint mudar de versão, dá pra atualizar um e esquecer o outro. Achado (CONFIRMED) no `/code-review` da Sessão 57. | Extrair pra uma constante compartilhada (ex: arquivo de constantes em `contracts/src/` ou `contracts/script/`) importada nos dois lugares. |
| 24 | `contracts/src/TruthIDAccountFactory.sol:40` | Constructor valida os 4 endereços com 4 erros customizados separados, estilo diferente do `TruthIDAccount.sol` (1 erro combinado) pros mesmos 4 parâmetros — os dois contratos são acoplados (factory só existe pra deployar `TruthIDAccount`) mas usam idiomas diferentes de validação. Achado (CONFIRMED) no `/code-review` da Sessão 57. | Decidir um padrão único pros dois contratos (o estilo de 4 erros dá asserts de teste mais precisos; o estilo combinado é mais enxuto) — não é bug, é decisão de consistência. |
| 25 | `contracts/src/TruthIDAccountFactory.sol:97` | `_salt(owner_)` depende só do endereço do owner — um Ledger só pode ter UMA `TruthIDAccount` nessa factory pra sempre. Se um dia precisar de múltiplas contas por owner (ex: reset após comprometimento suspeito), é breaking change em `createAccount`/`getAddress` e em todo consumidor off-chain do CREATE2 (mobile, desktop, futuro utilitário `computeSmartAccountAddress` da 14.6). Achado (CONFIRMED) no `/code-review` da Sessão 57. | Decisão de design pendente: manter 1 conta por owner (mais simples, alinhado ao modelo atual) ou já adicionar um parâmetro de índice/salt extra em `createAccount(owner, index)` antes de qualquer coisa depender do formato atual. |
| 26 | `contracts/test/TruthIDAccountFactory.t.sol:40` | Helper `_predictAndCreate` definido mas usado em só 1 dos 3 testes que repetem a mesma sequência prever→criar→assert; os outros 2 duplicam a lógica inline. Achado (CONFIRMED) no `/code-review` da Sessão 57. | Usar o helper nos 3 testes, ou removê-lo e manter tudo inline — escolher um padrão. |

---

## Pendências de Deploy (constantes placeholder no código)

Endereços de contrato que estão com placeholder `0x0` no código e precisam ser atualizados após o deploy em mainnet. **A fonte da verdade dessas pendências é esta seção, NÃO comentários no código.**

| # | Constante | Arquivo | Valor atual | Deploy previsto | Etapa |
|---|---|---|---|---|---|
| 1 | `TRUTHID_ACCOUNT_FACTORY_ADDRESS` | `desktop/src/config/truthidAccount.ts` | `0x00...00` | Deploy do `TruthIDAccountFactory` | 14.11 |
| 2 | `VAULT_REGISTRY_ADDRESS` | `desktop/src/config/contracts.ts` | `0x00...00` | Deploy do `VaultRegistry` | 13.x (ainda não deployado) |

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

**Perfis (Trabalho / Casa / outros)**: metadado local de cada entrada do vault (tag), não algo on-chain. O Mobile decide, no momento do scan do QR da extensão, qual perfil está ativo e filtra o payload antes de enviar. v1 usa perfis fixos pré-definidos.

**Revogação em cascata**: revogar um Device (ex: Mobile perdido) via Desktop precisa invalidar em cascata qualquer sessão de extensão que aquele Device tenha aberto. O Desktop precisa manter localmente o registro de qual Device originou qual sessão ativa, para conseguir notificar/expirar essas sessões no momento da revogação.

**Fluxo da sessão de extensão**:
1. Usuário abre a extensão no browser → ela exibe um QR code (challenge efêmero, mesmo padrão do QR de login do TruthID core).
2. Mobile escaneia, usuário escolhe/confirma o perfil ativo.
3. Mobile filtra o vault local pelo perfil escolhido e envia o subconjunto direto pra extensão via canal P2P efêmero (ex: WebRTC).
4. Extensão guarda esse subconjunto **em memória apenas**, pelo tempo da sessão do browser. Faz autofill nos campos da página.
5. Fechar a aba/browser, ou expirar um timeout configurável, destrói a sessão. Reabrir exige novo scan.

**Confirmado**: o canal P2P efêmero (Mobile→Extensão) é mantido — entrega um payload já filtrado, não sincroniza estado de vault entre devices. É o mesmo padrão do canal P2P de login via QR já em produção. A remoção de P2P aplica-se **apenas** ao mecanismo de sincronizar o conteúdo do vault inteiro entre Desktop e Mobile (esse passou a ser via pin).

**Nota de implementação**: como não há mais P2P nem handshake direto entre devices para sincronizar o conteúdo do vault, a complexidade de implementação cai bastante — não é preciso WebRTC, descoberta de peer, nem re-criptografia por device de destino para o fluxo Desktop/Mobile de sync. Isso é diferente do canal P2P efêmero do login via QR (já em produção) e do fluxo Mobile→Extensão (ambos mantidos, entregam payload já pronto/filtrado).

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

#### Não-escopo explícito (por agora)

- Autofill nativo via Credential Provider Extension (iOS) / Autofill Framework (Android).
- Native messaging host entre extensão e app desktop.
- Import/export de outros password managers.
- Compartilhamento de credenciais entre identidades diferentes (multi-usuário/empresa).
- Qualquer flow que exija o usuário digitar uma senha mestre.
- Perfis ad-hoc por site (v1 usa perfis fixos pré-definidos).

#### Ordem sugerida de implementação

1. **Núcleo Desktop + Mobile**: `VaultRegistry`, derivação de chave (HKDF), cifra/decifra local, botão "Enviar" com batching.
2. **Multi-pin automático**: configuração inicial de API keys (2+ provedores externos), upload automático a cada "Enviar", health-check periódico, textos de aviso de risco. Self-host como opção avançada depois.
3. **Extensão de navegador**: QR de sessão, seleção de perfil no Mobile, canal P2P efêmero de entrega do payload filtrado (mesmo padrão do login via QR), revogação em cascata.

#### Status das etapas

- [x] 13.1 — Contrato `VaultRegistry` (hash/CID + timestamp, ligado ao `DeviceRegistry`) *(Sessão 49 — contrato em `contracts/src/VaultRegistry.sol`, 12 testes passando, script de deploy em `contracts/script/DeployVaultRegistry.s.sol`; ainda não deployado na mainnet)*
- [x] 13.2 — Derivação de chave HKDF no Desktop (Rust) e Mobile (Dart) *(Sessão 49 — `derive_vault_key()` interno em `desktop/src-tauri/src/lib.rs` usando `hkdf`+`sha2`; `VaultKeyService` em `mobile/lib/services/vault_key_service.dart` com HKDF-SHA256 puro; 5 testes Dart passando)*
- [x] 13.3 — Cifra/decifra local do vault (AES-256-GCM) *(Sessão 50 — `vault.rs` em `desktop/src-tauri/src/vault.rs` com `encrypt`/`decrypt` + 5 testes Rust; `VaultCipherService` em `mobile/lib/services/vault_cipher_service.dart` + 8 testes Dart; Tauri commands `vault_encrypt`/`vault_decrypt` via Base64; formato do blob: nonce(12) || ciphertext || tag(16))*
- [x] 13.4 — CRUD local de entradas do vault (site, usuário, senha, notas, perfil) *(Sessão 50 — structs `VaultEntry`+`Vault` + métodos `upsert`/`delete` + `load`/`save` em `desktop/src-tauri/src/vault.rs`; Tauri commands `vault_list_entries`/`vault_upsert_entry`/`vault_delete_entry`; 11 testes Rust passando. `VaultEntry`+`VaultRepository` em `mobile/lib/services/vault_repository.dart` com `path_provider`; 11 testes Dart passando. Formato JSON compartilhado: `{version, entries[]}`, blob cifrado em `$HOME/.truthid/vault.enc` no desktop e `{docs}/vault.enc` no mobile)*
- [x] 13.5 — Botão "Enviar" com batching + upload multi-pin (2+ provedores externos) *(Sessão 51 — novo módulo `desktop/src-tauri/src/ipfs.rs`: struct `PinningProvider { name, kind, endpoint_url, api_key }` onde `kind` é `"kubo"` (upload via `/api/v0/add`) ou `"psa"` (pin via IPFS Pinning Service API `/pins`); `pin_vault()` faz upload para todos os Kubo providers e pina o CID nos PSA providers; `load_providers`/`save_providers` persistem config em `~/.truthid/pinning_providers.json`. Em `vault.rs`: `mark_published(version)` salva `~/.truthid/vault.meta.json`; `pending_changes()` retorna vault.version - last_published_version. 4 novos Tauri commands: `vault_publish` (async, lê vault.enc, chama pin_vault, marca publicado, retorna `{cid, content_hash, providers_ok, providers_failed}`), `vault_pending_changes`, `vault_get_providers`, `vault_set_providers`. content_hash = keccak256(blob cifrado) com prefixo "0x", pronto para passar direto ao `VaultRegistry.updateVault`. 14 testes Rust passando)*
- [x] 13.6 — Configuração de provedores de pin: UI de adicionar/remover provedores (endpoint + API key), suporte à IPFS Pinning Service API como interface única (cobre terceiros como Pinata/Filebase/4EVERLAND e self-hosted via Kubo local), guia de setup do Kubo no app, health-check periódico por provedor + alerta na UI *(Sessão 51 — nova tab "Vault" em `App.tsx`; novo componente `desktop/src/components/VaultSettings.tsx`: lista de providers com badge kubo/psa + botão "Testar" (health-check via fetch GET/POST) + botão "✕" para remover; formulário de adição com campos nome/tipo/endpoint/api-key; botão "Adicionar Kubo local" quando lista vazia; guia collapsible de setup do Kubo com comandos exatos; tipo `PinningProvider` adicionado a `types.ts`)*
- [x] 13.7 — UI Desktop: tela de gerenciamento do vault, permissão `canWriteVault` por Device *(Sessão 51 — breaking change: `profile: String` → `profiles: Vec<String>` no Rust e `List<String>` no Dart, com migração automática de vaults antigos; novo `permissions.rs` + 2 commands (`vault_get_device_permissions`, `vault_set_device_permission`), permissões em `~/.truthid/vault_permissions.json`; `VAULT_REGISTRY_ADDRESS` + ABI adicionados a `contracts.ts` (endereço placeholder — aguardando deploy); novo componente `VaultManagement.tsx`: lista de entradas com filtro, formulário add/edit inline, delete com confirm, seletor de grupos multi-select (Trabalho/Casa/Pessoal), fluxo "Enviar" em 2 fases (vault_publish → updateVault on-chain), status on-chain (versão + data), botão "⚙ Providers" → VaultSettings, seção colapsável de permissões por device; tab "Vault" em App.tsx aponta agora para VaultManagement. 14 testes Rust + 13 testes Dart passando)*
- [ ] 13.8 — UI Mobile: leitura do vault, tela de perfil para scan da extensão
- [ ] 13.9 — Extensão de navegador: sessão efêmera, autofill, revogação em cascata

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
- [ ] 14.7 — Desktop: atualizar fluxo de criação de identidade
  - Pré-computar endereço da smart account via `TruthIDAccountFactory.getAddress`
  - Chamar `IdentityRegistry.createIdentity(username, smartAccountAddress)` — Ledger paga como EOA
  - Deployar smart account via factory — Ledger paga como EOA
  - Transferir ETH para a smart account — Ledger paga como EOA
  - Exibir instrução clara: "estas 3 transações são pagas pela Ledger uma única vez"
- [ ] 14.8 — Desktop + Mobile: sincronizar lista de signers da smart account com o DeviceRegistry. Ao registrar device no DeviceRegistry → `TruthIDAccount.addDevice`. Ao revogar → `TruthIDAccount.removeDevice`. Ambas assinadas pelo Ledger (UserOp, gás da smart account).
- [ ] 14.9 — Mobile: atualizar fluxo de assinatura de transações (ex: `createSession`) para UserOps
  - Construir calldata para o contrato alvo
  - Montar UserOp (nonce via EntryPoint, gas limits estimados via bundler API)
  - Assinar UserOp hash com a device key (Secure Enclave)
  - Submeter ao bundler público (ex: `eth_sendUserOperation` via Alchemy/Pimlico)
  - Remove dependência do padrão relayer (Sessão 39) para o Mobile — sem `RELAYER_PRIVATE_KEY` necessário
- [ ] 14.10 — Dashboard da smart account no Desktop (tab dedicada):
  - Saldo atual de ETH
  - Histórico de operações com custo por tipo (sessão, registro de device, vault)
  - Botão "Depositar" (mostra endereço + QR)
  - Botão "Sacar" (transfere ETH para endereço informado, assinado pelo Ledger)
- [ ] 14.11 — Deploy em Base Mainnet: `TruthIDAccount` (implementation) + `TruthIDAccountFactory`. Atualizar endereços em `contracts.ts`, mobile e SDKs.
- [ ] 14.12 — Atualizar site de docs: nova página explicando o modelo de smart account, custo de setup, como financiar.

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
- **Próximo passo**: 14.7 — Desktop: atualizar fluxo de criação de identidade para usar smart account (pré-computar endereço → `createIdentity` com controller explícito → deployar factory → transferir ETH).

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

## Como Usar Este Arquivo

1. **Ao começar uma sessão**: Diga ao Claude Code "leia o PROJECT_STATE.md e me ajude a continuar"
2. **Ao terminar uma sessão**: O Claude atualiza o Log de Sessões e marca etapas concluídas
3. **Ao tomar uma decisão**: Registrar em "Decisões de Arquitetura em Aberto"
4. **Ao mudar de máquina**: Sincronizar via git (recomendado: `git init` neste diretório)
