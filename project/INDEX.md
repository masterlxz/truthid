# TruthID — Estado do Projeto

> Última atualização: 2026-07-24 (Sessão 150 — C4 e C6 corrigidos no código; 269 testes)
> ⚠️ **REMANESCENTES**: **Desktop** — 52/52 bugs do `/code-review max` corrigidos (0 pendentes). **Contratos** — 9 achados da review da Sessão 140 (C1-C9): **todos corrigidos no código** (C4 low-s check + C6 limites de arrays finalizados na Sessão 150). **Deploy em cascata pendente** — há identidade real na Mainnet (Sessão 116), avaliar migração antes de redeployar.

---

## Como Usar Este Arquivo

O estado do projeto foi dividido em arquivos menores dentro desta pasta (`project/`).
Leia o arquivo relevante para o que você precisa:

| Para saber sobre | Leia |
|---|---|
| Diretrizes de código e ensino | `GUIDELINES.md` |
| Visão geral, stack, status das fases | `OVERVIEW.md` |
| PRD (Product Requirements Document) | `CONTEXT.md` |
| Fases 1-11 (Smart Contracts a Testes E2E) | `PHASES_1_11.md` |
| Fase 12 (Publicação & Release) | `PHASE_12_RELEASE.md` |
| Fase 13 (TruthID Vault — senhas) | `PHASE_13_VAULT.md` |
| Fase 14 (Smart Account ERC-4337) | `PHASE_14_SMART_ACCOUNT.md` |
| Fase 15 (Digital Identity Vault — docs, endereços, cartões) | `PHASE_15_IDENTITY_VAULT.md` |
| Decisões de arquitetura, débitos técnicos, deploy pendente | `ARCHITECTURE.md` |
| Roadmap, evoluções planejadas, monetização, backlog | `ROADMAP.md` |
| Diagrama do fluxo de autenticação | `AUTH_FLOW.md` |
| Log completo de sessões de trabalho (14-150) | `SESSIONS.md` |

**Ao começar uma sessão**: Diga ao Claude "leia os arquivos em `project/` e me ajude a continuar"
**Ao terminar uma sessão**: Atualize o Log de Sessões em `SESSIONS.md` e marque etapas concluídas
**Ao tomar uma decisão**: Registre em `ARCHITECTURE.md`
**Ao mudar de máquina**: Sincronize via git