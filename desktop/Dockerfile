FROM node:20-bookworm-slim

# Bibliotecas do Linux que o Tauri precisa:
# - libwebkit2gtk: motor HTML que renderiza o React dentro da janela
# - libgtk-3-dev: toolkit de janelas do Linux
# - libssl-dev: criptografia (HTTPS, WebSocket seguro)
# - build-essential: compilador C (dependências do Rust precisam)
# - as demais: ícones, indicadores de sistema, imagens SVG
RUN apt-get update && apt-get install -y \
    build-essential \
    curl \
    file \
    libssl-dev \
    libgtk-3-dev \
    libwebkit2gtk-4.1-dev \
    libayatana-appindicator3-dev \
    librsvg2-dev \
    patchelf \
    && rm -rf /var/lib/apt/lists/*

# Instala Rust dentro do container
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

# Instala o Tauri CLI (ferramenta de linha de comando do Tauri)
RUN cargo install tauri-cli --version "^2" --locked

# libudev-dev + pkg-config: crate `hidapi` (Fase 10, Ledger via USB) usa libudev pra
# enumerar dispositivos HID no Linux. Numa camada própria, depois do Rust/tauri-cli
# (que são caros pra rebuildar), pra não invalidar o cache dessas camadas anteriores.
RUN apt-get update && apt-get install -y \
    libudev-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
