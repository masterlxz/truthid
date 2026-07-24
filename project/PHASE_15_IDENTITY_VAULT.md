### Fase 15 — Digital Identity Vault (documentos, endereços, cartões)

**O que é**: expansão do TruthID Vault (Fase 13) de um gerenciador de senhas para um **cofre de identidade digital completo**. Além de senhas, o usuário pode armazenar e preencher automaticamente:

- **Documentos** (PDFs, imagens de RG/CNH/passaporte, contratos, qualquer arquivo — cifrado, com limite de tamanho a definir)
- **Endereços** (residencial, comercial, entrega, cobrança — com autofill em formulários)
- **Cartões de crédito** (número, titular, validade, CVV — cifrados, autofill em checkout)

**Visão maior**: uma **Identidade Digital portátil** que o usuário carrega entre dispositivos, sem depender de Google/Apple/Microsoft — tudo cifrado, armazenado no mesmo IPFS vault que as senhas, acessível pelos mesmos dispositivos confiáveis.

**Status**: :hourglass: Não iniciada — registrada na Sessão 151 (2026-07-24), aguardando `/plan`.

---

#### Princípios de arquitetura (decididos com o dono do projeto)

| Princípio | Decisão |
|---|---|
| **Onde ficam os dados** | Mesmo blob IPFS criptografado do Vault (Fase 13). Tudo junto: senhas, documentos, endereços, cartões — um único vault cifrado por identidade. |
| **Criptografia** | AES-256-GCM, mesma chave derivada da wallet (HKDF via `personal_sign("TruthID Vault Key v1")`). Nenhum dado em claro jamais sai do dispositivo. |
| **Autofill — browser** | Via extensão já existente (`extension/`, Fase 13.9). A extensão não acessa o vault diretamente — o **device** (Mobile/Desktop) envia P2P apenas as informações que o usuário aprovar, no mesmo padrão do fluxo de senhas já implementado. |
| **Autofill — SO** | Android Autofill Framework + iOS ASCredentialProviderViewController. O vault local no celular preenche formulários de sistema (checkout, cadastro) diretamente. |
| **Documentos** | Genéricos (qualquer tipo de arquivo). Limite de tamanho a ser decidido na implementação (sugestão inicial: 10MB por documento, ajustável). |
| **Sync entre devices** | Mesmo mecanismo da Fase 13: edição local → botão "Enviar" → IPFS multi-pin → `VaultRegistry.updateVault` on-chain. |
| **Relação com a extensão** | A extensão funciona como "agente de requisição": detecta campos de formulário, pede ao device os dados específicos via QR/LAN/dead-drop (mesmo padrão 13.9), o device mostra o que está sendo pedido e o usuário aprova/rejeita. |

---

#### O que vai on-chain vs. o que não vai

| Dado | Vai on-chain? | Onde fica |
|---|---|---|
| Conteúdo do vault (senhas, documentos, endereços, cartões) | **Nunca** | IPFS cifrado (blob único) |
| CID do blob | Sim | `VaultRegistry` (já existe) |
| Chave de decriptação | **Nunca** | Derivada localmente (wallet signature) |
| Metadados de cartão (nome do banco, apelido) | **Nunca** | Apenas no blob cifrado |

---

#### Fluxo de autofill (browser — extensão)

```
Usuário está num site de checkout (formulário de endereço + cartão)

    ┌─ Extensão (browser) ─────────────────────────────────┐
    │ 1. Detecta campos de endereço/cartão no DOM          │
    │ 2. Gera pedido: { type: "address" | "creditCard",    │
    │                   fields: [...], sessionId,           │
    │                   ephemeralPubKey }                   │
    │ 3. Exibe QR code (ou LAN discovery)                  │
    └──────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─ Mobile / Desktop (device confiável) ────────────────┐
    │ 4. Escaneia QR / descobre na LAN                     │
    │ 5. Decifra o vault localmente                        │
    │ 6. Mostra ao usuário: "O site X pede endereço        │
    │    residencial. Permitir?"                            │
    │ 7. Usuário aprova (ou escolhe qual endereço/cartão)  │
    │ 8. Cifra só os dados aprovados via ECIES             │
    │ 9. Envia de volta (LAN / dead-drop IPFS)             │
    └──────────────────────────────────────────────────────┘
                            │
                            ▼
    ┌─ Extensão (browser) ─────────────────────────────────┐
    │ 10. Decifra resposta com chave efêmera               │
    │ 11. Preenche campos do formulário                    │
    │ 12. Dados descartados ao fechar aba                  │
    └──────────────────────────────────────────────────────┘
```

---

#### Fluxo de autofill (SO — Android/iOS)

```
Usuário está num app de e-commerce, campo de endereço focado

    ┌─ Android Autofill Framework / iOS ASCredentialProvider ─┐
    │ 1. SO dispara pedido de autofill                        │
    │ 2. TruthID Vault Service recebe a requisição            │
    │ 3. (Opcional) Biometria (fingerprint/face)              │
    │ 4. Decifra vault local                                  │
    │ 5. Filtra entradas compatíveis com o contexto           │
    │ 6. Preenche formulário diretamente                      │
    └─────────────────────────────────────────────────────────┘
```

---

#### Schema do vault (extensão do formato atual)

O schema JSON atual do vault (`VaultEntry`) será estendido com novos tipos de entrada:

```typescript
// Atual (Fase 13)
type VaultEntryCredential = {
  type: "credential";
  site: string;
  username: string;
  password: string;
  notes?: string;
  profiles: string[];
};

// Novos (Fase 15)
type VaultEntryDocument = {
  type: "document";
  name: string;           // apelido: "RG", "CNH", "Contrato XYZ"
  fileName: string;       // nome original do arquivo
  fileData: string;       // base64 do arquivo, cifrado dentro do blob
  fileSizeBytes: number;
  mimeType: string;       // "application/pdf", "image/png", etc.
  notes?: string;
  profiles: string[];
};

type VaultEntryAddress = {
  type: "address";
  label: string;          // "Casa", "Trabalho", "Entrega"
  fullName: string;
  street: string;
  number: string;
  complement?: string;
  neighborhood: string;
  city: string;
  state: string;
  zipCode: string;
  country: string;
  phone?: string;
  notes?: string;
  profiles: string[];
};

type VaultEntryCreditCard = {
  type: "creditCard";
  label: string;          // "Nubank", "Itaú Platinum"
  cardHolderName: string;
  cardNumber: string;     // cifrado individualmente dentro do blob
  expiryMonth: string;
  expiryYear: string;
  cvv: string;            // cifrado individualmente dentro do blob
  bank?: string;
  cardNetwork: "visa" | "mastercard" | "amex" | "elo" | "hipercard" | "other";
  notes?: string;
  profiles: string[];
};

// Union type do vault
type VaultEntry = VaultEntryCredential | VaultEntryDocument
                | VaultEntryAddress | VaultEntryCreditCard;
```

**Nota de segurança**: `cardNumber` e `cvv` são cifrados individualmente (camada extra além da cifra do blob inteiro), para que o autofill possa expor o número sem nunca decifrar o CVV a menos que explicitamente necessário (ex: checkout com CVV).

---

#### Etapas planejadas (ordem sugerida)

1. **15.1 — Schema**: estender o `VaultEntry` (Rust/Dart) para os 3 novos tipos. Migração automática de vaults existentes. Testes de compatibilidade reversa.
2. **15.2 — CRUD Desktop**: UI para criar/editar/deletar endereços e cartões no `VaultManagement.tsx`. Seção de documentos (upload de arquivo, listagem, visualização).
3. **15.3 — CRUD Mobile**: paridade no mobile (`vault_entry_form_screen.dart`). Upload de documento via câmera/galeria.
4. **15.4 — Autofill browser (extensão)**: extensão detecta campos de endereço/cartão e pede ao device os dados específicos (mesmo padrão P2P da 13.9). Aprovação no device mostra o que será preenchido.
5. **15.5 — Autofill SO Android**: implementar `AutofillService` (`android.app.service.AutofillService`). Lê vault local, filtra por tipo de campo, preenche.
6. **15.6 — Autofill SO iOS**: implementar `ASCredentialIdentityStore` / `ASCredentialProviderViewController`. Mesma lógica do Android.
7. **15.7 — Documentos**: upload/download/visualização de documentos genéricos. Limite de tamanho a definir. Chunking para arquivos grandes, se necessário.
8. **15.8 — Revisão de segurança**: auditoria focada nos cartões de crédito (cifra extra do CVV, exposição mínima no autofill, zero logging).

---

#### Dependências

- Fase 13 (Vault de senhas) — concluída, base para tudo
- Fase 13.9 (Extensão de navegador) — concluída, reusada para autofill de endereços/cartões
- Fase 14 (Smart Account) — concluída, usada para pagar gas do `updateVault` ao adicionar entradas novas
- Nenhum contrato novo necessário — `VaultRegistry` já serve

---
