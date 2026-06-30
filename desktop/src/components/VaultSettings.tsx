import { useEffect, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import type { PinningProvider } from "../types";

type HealthStatus = "idle" | "checking" | "ok" | "error";

const DEFAULT_KUBO: PinningProvider = {
  name: "Kubo local",
  kind: "kubo",
  endpoint_url: "http://localhost:5001",
  api_key: "",
};

async function checkHealth(p: PinningProvider): Promise<"ok" | "error"> {
  try {
    const url =
      p.kind === "kubo"
        ? `${p.endpoint_url.replace(/\/$/, "")}/api/v0/version`
        : `${p.endpoint_url.replace(/\/$/, "")}/pins?limit=1`;
    const headers: Record<string, string> = p.api_key
      ? { Authorization: `Bearer ${p.api_key}` }
      : {};
    // Kubo HTTP RPC usa POST; PSA usa GET
    const res = await fetch(url, {
      method: p.kind === "kubo" ? "POST" : "GET",
      headers,
    });
    return res.ok ? "ok" : "error";
  } catch {
    return "error";
  }
}

export function VaultSettings() {
  const [providers, setProviders] = useState<PinningProvider[]>([]);
  const [loading, setLoading] = useState(true);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [healthStatus, setHealthStatus] = useState<Record<number, HealthStatus>>({});

  // Formulário de adição
  const [addOpen, setAddOpen] = useState(false);
  const [form, setForm] = useState<PinningProvider>({
    name: "",
    kind: "kubo",
    endpoint_url: "",
    api_key: "",
  });
  const [showKey, setShowKey] = useState(false);
  const [guideOpen, setGuideOpen] = useState(false);

  useEffect(() => {
    invoke<PinningProvider[]>("vault_get_providers")
      .then(setProviders)
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  async function save(updated: PinningProvider[]) {
    setSaveError(null);
    try {
      await invoke<void>("vault_set_providers", { providers: updated });
      setProviders(updated);
    } catch (e) {
      setSaveError(String(e));
    }
  }

  function handleRemove(index: number) {
    const updated = providers.filter((_, i) => i !== index);
    save(updated);
    setHealthStatus((prev) => {
      const next = { ...prev };
      delete next[index];
      return next;
    });
  }

  async function handleCheck(index: number) {
    setHealthStatus((prev) => ({ ...prev, [index]: "checking" }));
    const result = await checkHealth(providers[index]);
    setHealthStatus((prev) => ({ ...prev, [index]: result }));
  }

  function handleAddKuboDefault() {
    const updated = [...providers, DEFAULT_KUBO];
    save(updated);
  }

  function handleFormAdd() {
    if (!form.name.trim() || !form.endpoint_url.trim()) return;
    const updated = [...providers, { ...form }];
    save(updated);
    setForm({ name: "", kind: "kubo", endpoint_url: "", api_key: "" });
    setAddOpen(false);
    setShowKey(false);
  }

  if (loading) return <p className="muted">Carregando providers...</p>;

  return (
    <div>
      <h2>Pinning Providers</h2>
      <p className="muted" style={{ marginBottom: "1.25rem" }}>
        O vault cifrado é enviado para todos os providers configurados ao clicar
        "Enviar". Recomendado: ao menos um provider <strong>kubo</strong> (nó
        local, sem custo) e um <strong>psa</strong> (cloud, para redundância).
      </p>

      {saveError && <p className="error-text">{saveError}</p>}

      {/* Lista de providers */}
      {providers.length === 0 ? (
        <div className="card" style={{ marginBottom: "1rem" }}>
          <p className="muted">Nenhum provider configurado.</p>
          <div className="actions-row">
            <button onClick={handleAddKuboDefault}>+ Adicionar Kubo local</button>
          </div>
        </div>
      ) : (
        <div style={{ display: "flex", flexDirection: "column", gap: "0.75rem", marginBottom: "1rem" }}>
          {providers.map((p, i) => {
            const status = healthStatus[i] ?? "idle";
            return (
              <div
                key={i}
                className="card"
                style={{ display: "flex", alignItems: "center", gap: "0.75rem", padding: "0.85rem 1.1rem" }}
              >
                <span
                  className="status-badge"
                  style={{
                    background: p.kind === "kubo" ? "rgba(77,208,225,0.15)" : "rgba(159,177,194,0.1)",
                    color: p.kind === "kubo" ? "var(--color-accent)" : "var(--color-text-muted)",
                    fontSize: "0.75em",
                    padding: "0.2em 0.6em",
                    borderRadius: "4px",
                    flexShrink: 0,
                  }}
                >
                  {p.kind}
                </span>
                <span style={{ fontWeight: 600, flexShrink: 0 }}>{p.name}</span>
                <span
                  className="address muted"
                  style={{ fontSize: "0.82em", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", flex: 1 }}
                >
                  {p.endpoint_url}
                </span>

                {/* Health indicator */}
                {status === "ok" && <span style={{ color: "#4caf50", flexShrink: 0 }}>✓</span>}
                {status === "error" && <span style={{ color: "var(--color-danger)", flexShrink: 0 }}>✗</span>}
                {status === "checking" && <span className="muted" style={{ flexShrink: 0, fontSize: "0.85em" }}>...</span>}

                <button
                  onClick={() => handleCheck(i)}
                  disabled={status === "checking"}
                  style={{ padding: "0.3em 0.75em", fontSize: "0.85em", flexShrink: 0 }}
                >
                  Testar
                </button>
                <button
                  onClick={() => handleRemove(i)}
                  style={{
                    padding: "0.3em 0.65em",
                    fontSize: "0.85em",
                    borderColor: "var(--color-danger)",
                    color: "var(--color-danger)",
                    flexShrink: 0,
                  }}
                >
                  ✕
                </button>
              </div>
            );
          })}
        </div>
      )}

      {/* Formulário de adição */}
      {!addOpen ? (
        <button onClick={() => setAddOpen(true)} style={{ marginBottom: "1.5rem" }}>
          + Adicionar provider
        </button>
      ) : (
        <div className="card" style={{ marginBottom: "1.5rem" }}>
          <h3 style={{ marginTop: 0 }}>Novo provider</h3>
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: "0.75rem" }}>
            <div className="field">
              <label>Nome</label>
              <input
                placeholder="ex: Pinata"
                value={form.name}
                onChange={(e) => setForm((f) => ({ ...f, name: e.target.value }))}
              />
            </div>
            <div className="field">
              <label>Tipo</label>
              <select
                value={form.kind}
                onChange={(e) => setForm((f) => ({ ...f, kind: e.target.value as "kubo" | "psa" }))}
                style={{
                  background: "var(--color-surface)",
                  border: "1px solid var(--color-border)",
                  color: "var(--color-text)",
                  borderRadius: "8px",
                  padding: "0.6em 1em",
                  fontSize: "1em",
                  fontFamily: "inherit",
                  width: "100%",
                }}
              >
                <option value="kubo">kubo — nó IPFS (upload de conteúdo)</option>
                <option value="psa">psa — Pinning Service API (pin por CID)</option>
              </select>
            </div>
          </div>
          <div className="field" style={{ marginTop: "0.5rem" }}>
            <label>Endpoint URL</label>
            <input
              placeholder={form.kind === "kubo" ? "http://localhost:5001" : "https://api.pinata.cloud/psa"}
              value={form.endpoint_url}
              onChange={(e) => setForm((f) => ({ ...f, endpoint_url: e.target.value }))}
              style={{ width: "100%", boxSizing: "border-box" }}
            />
          </div>
          <div className="field" style={{ marginTop: "0.5rem" }}>
            <label>API key {form.kind === "kubo" && <span className="muted">(opcional para nós locais)</span>}</label>
            <div style={{ display: "flex", gap: "0.5rem" }}>
              <input
                type={showKey ? "text" : "password"}
                placeholder={form.kind === "kubo" ? "deixe vazio para Kubo local" : "Bearer token do provider"}
                value={form.api_key}
                onChange={(e) => setForm((f) => ({ ...f, api_key: e.target.value }))}
                style={{ flex: 1 }}
              />
              <button
                onClick={() => setShowKey((v) => !v)}
                style={{ padding: "0.4em 0.8em", fontSize: "0.9em" }}
                title={showKey ? "Ocultar" : "Mostrar"}
              >
                {showKey ? "🙈" : "👁"}
              </button>
            </div>
          </div>
          <div className="actions-row">
            <button
              onClick={handleFormAdd}
              disabled={!form.name.trim() || !form.endpoint_url.trim()}
            >
              Adicionar
            </button>
            <button
              onClick={() => { setAddOpen(false); setShowKey(false); }}
              style={{ borderColor: "var(--color-border)", color: "var(--color-text-muted)" }}
            >
              Cancelar
            </button>
          </div>
        </div>
      )}

      {/* Guia do Kubo */}
      <div style={{ marginTop: "0.5rem" }}>
        <button
          onClick={() => setGuideOpen((v) => !v)}
          style={{
            borderColor: "var(--color-border)",
            color: "var(--color-text-muted)",
            fontSize: "0.9em",
            padding: "0.45em 1em",
          }}
        >
          {guideOpen ? "▼" : "▶"} Como configurar o Kubo local (self-hosted, gratuito)
        </button>
        {guideOpen && (
          <div className="card" style={{ marginTop: "0.75rem" }}>
            <p className="muted" style={{ marginTop: 0 }}>
              O Kubo é o nó de referência do IPFS. Instalado localmente, nenhum
              dado do vault sai do seu computador.
            </p>

            <h4 style={{ marginBottom: "0.4rem" }}>1. Instalar</h4>
            <pre style={{
              background: "var(--color-bg)",
              border: "1px solid var(--color-border)",
              borderRadius: "8px",
              padding: "0.85rem 1rem",
              fontSize: "0.82em",
              overflowX: "auto",
              margin: "0 0 1rem",
            }}>
              <code>{`# Arch Linux
yay -S kubo

# ou via script oficial (qualquer distro)
curl -sSL https://dist.ipfs.tech/kubo/v0.29.0/kubo_v0.29.0_linux-amd64.tar.gz | tar xz
sudo bash kubo/install.sh`}</code>
            </pre>

            <h4 style={{ marginBottom: "0.4rem" }}>2. Inicializar e iniciar</h4>
            <pre style={{
              background: "var(--color-bg)",
              border: "1px solid var(--color-border)",
              borderRadius: "8px",
              padding: "0.85rem 1rem",
              fontSize: "0.82em",
              overflowX: "auto",
              margin: "0 0 1rem",
            }}>
              <code>{`ipfs init
ipfs daemon`}</code>
            </pre>

            <h4 style={{ marginBottom: "0.4rem" }}>3. Configurar no TruthID</h4>
            <p className="muted" style={{ marginBottom: "0.75rem" }}>
              Com o daemon rodando, clique em <strong>+ Adicionar Kubo local</strong>{" "}
              acima. O endpoint padrão é <code>http://localhost:5001</code> e nenhuma
              API key é necessária.
            </p>

            <p className="muted" style={{ marginBottom: 0 }}>
              O daemon precisa estar rodando toda vez que você clicar "Enviar" no
              vault. Você pode iniciá-lo automaticamente com{" "}
              <code>systemctl --user enable --now ipfs</code> (requer o serviço do
              pacote kubo).
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
