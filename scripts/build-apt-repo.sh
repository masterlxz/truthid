#!/usr/bin/env bash
# Monta um repositório APT estático (dists/ + pool/) a partir de um .deb já
# buildado pelo build.yml — sem serviço terceiro (Cloudsmith/PackageCloud),
# hospedado como estático no mesmo GitHub Pages que já serve site/frontend
# (ver project/ROADMAP.md, seção "Instaladores nativos", Sessão 215/217).
#
# Uso: build-apt-repo.sh <deb-file> <output-dir>
#
# Requer: dpkg-scanpackages, apt-ftparchive (pacote dpkg-dev+apt-utils no
# Debian/Ubuntu), gpg. O runner ubuntu-22.04 do build.yml já tem os três.
#
# Variáveis de ambiente:
#   GPG_KEY_ID  - fingerprint/key ID da chave de assinatura (obrigatório)
# GNUPGHOME deve já apontar pro keyring com a chave privada importada.

set -euo pipefail

DEB_FILE="${1:?uso: build-apt-repo.sh <deb-file> <output-dir>}"
OUT_DIR="${2:?uso: build-apt-repo.sh <deb-file> <output-dir>}"
GPG_KEY_ID="${GPG_KEY_ID:?defina GPG_KEY_ID com o fingerprint da chave de assinatura}"

if [ ! -f "$DEB_FILE" ]; then
  echo "Arquivo .deb não encontrado: $DEB_FILE" >&2
  exit 1
fi

PACKAGE_NAME=$(dpkg-deb --field "$DEB_FILE" Package)
POOL_DIR="$OUT_DIR/pool/main/${PACKAGE_NAME:0:1}/$PACKAGE_NAME"
DIST_DIR="$OUT_DIR/dists/stable"
BINARY_DIR="$DIST_DIR/main/binary-amd64"

mkdir -p "$POOL_DIR" "$BINARY_DIR"
cp "$DEB_FILE" "$POOL_DIR/"

# dpkg-scanpackages precisa rodar com cwd em $OUT_DIR pra gerar os caminhos
# "Filename:" relativos certos (pool/main/...) dentro do Packages.
(
  cd "$OUT_DIR"
  dpkg-scanpackages --multiversion pool/ > "dists/stable/main/binary-amd64/Packages"
)
gzip -9c "$BINARY_DIR/Packages" > "$BINARY_DIR/Packages.gz"

# Release do apt-ftparchive precisa de um apt-ftparchive.conf mínimo
# apontando pra estrutura dists/stable já montada.
cat > "$DIST_DIR/apt-ftparchive.conf" <<EOF
APT::FTPArchive::Release::Origin "TruthID";
APT::FTPArchive::Release::Label "TruthID";
APT::FTPArchive::Release::Suite "stable";
APT::FTPArchive::Release::Codename "stable";
APT::FTPArchive::Release::Architectures "amd64";
APT::FTPArchive::Release::Components "main";
APT::FTPArchive::Release::Description "TruthID APT repository";
EOF

(
  cd "$DIST_DIR"
  apt-ftparchive -c apt-ftparchive.conf release . > Release
  rm apt-ftparchive.conf
)

# InRelease (assinatura inline, formato moderno) + Release.gpg (assinatura
# destacada, compat com clientes apt antigos) — os dois lado a lado é
# prática padrão de repositórios apt de terceiros.
gpg --default-key "$GPG_KEY_ID" --batch --yes --clearsign \
  -o "$DIST_DIR/InRelease" "$DIST_DIR/Release"
gpg --default-key "$GPG_KEY_ID" --batch --yes -abs \
  -o "$DIST_DIR/Release.gpg" "$DIST_DIR/Release"

# Chave pública em formato keyring binário (dearmored) — permite o usuário
# instalar com um curl+tee direto, sem precisar rodar `gpg --dearmor` na mão
# (esquema moderno `signed-by`, não o `apt-key add` descontinuado).
gpg --export "$GPG_KEY_ID" > "$OUT_DIR/truthid-archive-keyring.gpg"

echo "Repositório APT montado em $OUT_DIR (pacote: $PACKAGE_NAME)"
