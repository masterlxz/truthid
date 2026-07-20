import type { PasswordGeneratorOptions } from "../utils/passwordGenerator";

const CATEGORY_LABELS = [
  ["uppercase", "Maiúsculas"],
  ["lowercase", "Minúsculas"],
  ["numbers", "Números"],
  ["symbols", "Símbolos"],
] as const;

// Popup do gerador de senha (pedido explícito do dono do projeto — antes
// era um painel inline dentro do formulário de entrada; Mobile já usava
// bottom sheet, o Desktop ficou de fora dessa paridade). Mesmo padrão de
// modal já usado por TotpQrScanner (modal-overlay/modal-box).
export function PasswordGeneratorModal({
  options,
  preview,
  error,
  onToggleCategory,
  onLengthChange,
  onRegenerate,
  onUse,
  onClose,
}: {
  options: PasswordGeneratorOptions;
  preview: string;
  error: string | null;
  onToggleCategory: (field: keyof Omit<PasswordGeneratorOptions, "length">) => void;
  onLengthChange: (length: number) => void;
  onRegenerate: () => void;
  onUse: () => void;
  onClose: () => void;
}) {
  return (
    <div className="modal-overlay" onClick={onClose}>
      <div className="modal-box" onClick={(e) => e.stopPropagation()}>
        <div className="modal-header">
          <h2 className="modal-title">Gerar senha</h2>
          <button className="modal-close" onClick={onClose}>
            ✕
          </button>
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "0.6rem", flexWrap: "wrap" }}>
          <label style={{ fontSize: "0.82em" }}>
            Tamanho:{" "}
            <input
              type="number"
              min={1}
              value={options.length}
              onChange={(e) => onLengthChange(Math.max(1, Number(e.target.value)))}
              style={{ width: "4.5rem" }}
            />
          </label>
          {CATEGORY_LABELS.map(([field, label]) => (
            <button
              key={field}
              type="button"
              onClick={() => onToggleCategory(field)}
              style={{
                padding: "0.25em 0.75em",
                fontSize: "0.82em",
                borderColor: options[field] ? "var(--color-accent)" : "var(--color-border)",
                color: options[field] ? "var(--color-accent)" : "var(--color-text-muted)",
                background: options[field] ? "rgba(77,208,225,0.1)" : "transparent",
              }}
            >
              {options[field] ? "✓ " : ""}{label}
            </button>
          ))}
        </div>
        <div style={{ display: "flex", alignItems: "center", gap: "0.5rem", marginTop: "0.75rem" }}>
          <code style={{ flex: 1, fontSize: "1em", wordBreak: "break-all" }}>
            {preview || "—"}
          </code>
          <button type="button" onClick={onRegenerate} style={{ padding: "0.2em 0.6em", fontSize: "0.8em" }}>
            🔄 Gerar
          </button>
        </div>
        {error && <p className="error-text" style={{ margin: "0.4em 0 0", fontSize: "0.82em" }}>{error}</p>}
        <div className="actions-row" style={{ marginTop: "0.75rem" }}>
          <button type="button" onClick={onUse} disabled={!preview}>
            Usar esta senha
          </button>
        </div>
      </div>
    </div>
  );
}
