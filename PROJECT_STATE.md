# TruthID — Estado do Projeto

> Este arquivo é o centro de controle do projeto. Atualizado a cada sessão de trabalho.
> Pode ser lido por qualquer instância do Claude Code em qualquer máquina para retomar o contexto.
> Última atualização: 2026-06-04 (Sessão 4)

---

## Diretriz de ensino (IMPORTANTE — ler antes de cada sessão)

O usuário é iniciante em blockchain e Solidity. O objetivo do projeto é aprender enquanto constrói.

**Regras para o Claude:**
- Explicar o conceito ANTES de escrever o código
- Introduzir um conceito novo de cada vez — nunca vários ao mesmo tempo
- Usar analogias do mundo real antes de termos técnicos
- Perguntar se o usuário entendeu antes de avançar
- Não assumir conhecimento prévio de blockchain, Solidity, criptografia, Foundry ou qualquer ferramenta
- Ritmo lento e deliberado é melhor que velocidade

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
Fase 1 — Smart Contracts        [~] Em andamento (3/7 etapas)
Fase 2 — Relay Service          [ ] Não iniciada
Fase 3 — Desktop App            [ ] Não iniciada
Fase 4 — Mobile App             [ ] Não iniciada
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
- [ ] 1.4 — `RecoveryManager`: propor recovery, coletar aprovações, executar com timelock (7 dias)
- [ ] 1.5 — Testes unitários completos
- [ ] 1.6 — Deploy em testnet (Base Sepolia)
- [ ] 1.7 — Verificar contratos no Basescan

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
- **Sinalização**: canal para os dois lados se acharem antes de conectar — decisão pendente

**Etapas**:
- [ ] 2.1 — Decidir canal de sinalização
- [ ] 2.2 — Implementar sinalização
- [ ] 2.3 — Conexão WebRTC: website cria oferta → celular responde
- [ ] 2.4 — Challenge trafega P2P: website → celular
- [ ] 2.5 — Resposta assinada trafega P2P: celular → website
- [ ] 2.6 — TTL de challenges (expiração, não-replay)
- [ ] 2.7 — TURN self-hostável (coturn) como fallback
- [ ] 2.8 — Testes de integração

**Decisões pendentes**:
- Canal de sinalização: on-chain via eventos, DHT/P2P efêmero, ou servidor leve?

---

### Fase 3 — Desktop App (Tauri)

**Objetivo de aprendizado**: Construir uma aplicação desktop com Rust no backend e React no frontend, integrando wallet e blockchain.

**Responsabilidades**:
- Criar e gerenciar identidade
- Gerenciar dispositivos (adicionar/revogar)
- Gerenciar sessões ativas
- Conectar wallet (MetaMask, Rabby, Ledger, Trezor, WalletConnect)

**Etapas**:
- [ ] 3.1 — Setup Tauri + React + TypeScript
- [ ] 3.2 — Integração com wallet (wagmi + viem)
- [ ] 3.3 — Tela: Criar identidade (conectar wallet → escolher username → registrar)
- [ ] 3.4 — Tela: Gerenciar dispositivos (adicionar via QR, revogar)
- [ ] 3.5 — Tela: Sessões ativas (listar, revogar selecionadas, revogar todas)
- [ ] 3.6 — Geração de QR code para pareamento de novo dispositivo
- [ ] 3.7 — Armazenamento seguro de chaves (Windows TPM / Linux Keyring)
- [ ] 3.8 — Build para Linux, Windows, macOS

---

### Fase 4 — Mobile App (Flutter)

**Objetivo de aprendizado**: Construir o componente mais crítico do fluxo de autenticação — o aprovador que fica na mão do usuário.

**Responsabilidades**:
- Escanear QR code do website
- Exibir request de login ao usuário
- Assinar o challenge com chave privada do dispositivo
- Gerenciar dispositivos e sessões

**Etapas**:
- [ ] 4.1 — Setup Flutter
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
| Canal de sinalização WebRTC | On-chain / DHT / servidor leve | Pendente |
| Padrão de upgrade dos contratos | Proxy (upgradeable) vs Imutável | Pendente |
| Formato do challenge de autenticação | JWT vs custom JSON | Pendente |

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
