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

