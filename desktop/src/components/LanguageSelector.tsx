import { useTranslation } from "react-i18next";

// Nomes dos idiomas nunca são traduzidos — cada um aparece sempre no
// próprio idioma, convenção padrão de seletor de idioma.
const LANGUAGES: { code: string; label: string }[] = [
  { code: "en", label: "English" },
  { code: "pt-BR", label: "Português (Brasil)" },
  { code: "es", label: "Español" },
  { code: "zh-CN", label: "中文" },
];

export function LanguageSelector() {
  const { t, i18n } = useTranslation();

  return (
    <select
      className="topbar-btn"
      value={i18n.language}
      onChange={(e) => i18n.changeLanguage(e.target.value)}
      title={t("app.topbar.language")}
      aria-label={t("app.topbar.language")}
    >
      {LANGUAGES.map(({ code, label }) => (
        <option key={code} value={code}>
          {label}
        </option>
      ))}
    </select>
  );
}
