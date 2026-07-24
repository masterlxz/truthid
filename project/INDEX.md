# TruthID — Estado do Projeto

> Última atualização: 2026-07-24 (Sessão 150 — C4 e C6 corrigidos no código; 269 testes)
> ⚠️ **REMANESCENTES**: **Desktop** — 52/52 bugs do `/code-review max` corrigidos (0 pendentes). **Contratos** — 9 achados da review da Sessão 140 (C1-C9): **todos corrigidos no código** (C4 low-s check + C6 limites de arrays finalizados na Sessão 150). **Deploy em cascata pendente** — há identidade real na Mainnet (Sessão 116), avaliar migração antes de redeployar. Ver `PENDING.md` para lista completa de pendências.

---

## Como Usar Este Arquivo

O estado do projeto foi dividido em arquivos menores dentro desta pasta (`project/`).
Leia o arquivo relevante para o que você precisa:

| Para saber sobre | Leia |
|---|---|
| Diretrizes de código e ensino | `GUIDELINES.md` |
| Visão geral, stack, status das fases | `OVERVIEW.md` |
| PRD (Product Requirements Document) | `CONTEXT.md` |
| **Todas as fases detalhadas (1 a 15)** | **`PHASE.md`** |
| Decisões de arquitetura | `ARCHITECTURE.md` |
| **Pendências (resolvidas e não resolvidas)** | **`PENDING.md`** |
| Roadmap, evoluções planejadas, monetização, backlog | `ROADMAP.md` |
| Diagrama do fluxo de autenticação | `AUTH_FLOW.md` |
| Log completo de sessões de trabalho (14-150) | `SESSIONS.md` |

**Ao começar uma sessão**: Diga ao Claude "leia os arquivos em `project/` e me ajude a continuar"
**Ao terminar uma sessão**: Atualize o Log de Sessões em `SESSIONS.md` e marque etapas concluídas. Se resolveu uma pendência, atualize `PENDING.md`.
**Ao tomar uma decisão**: Registre em `ARCHITECTURE.md`
**Ao encontrar um bug/pendência nova**: Adicione em `PENDING.md` com ID sequencial
**Ao mudar de máquina**: Sincronize via git