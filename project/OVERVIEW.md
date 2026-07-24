# O que é o TruthID

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

# Status Geral

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
Fase 13 — TruthID Vault (gerenciador de senhas) [x] Concluída (13.1–13.9 ✓, validada em hardware real na Sessão 116)
Fase 14 — Smart Account (ERC-4337, Self-Funded)  [x] Concluída
```

---

# Checklist antes do próximo release oficial

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