import i18n from "i18next";
import { initReactI18next } from "react-i18next";
import LanguageDetector from "i18next-browser-languagedetector";

// Cada componente tem seu próprio dicionário por idioma
// (`locales/<lang>/<componente>.json`) — o glob monta a árvore de recursos
// sozinho a partir do que existir em disco, então adicionar um dicionário
// novo nunca exige tocar neste arquivo (o limite de arquivo é o limite de
// posse de cada parte do app que mexe em i18n, sem colisão entre elas).
const modules = import.meta.glob<{ default: Record<string, unknown> }>(
  "./locales/*/*.json",
  { eager: true },
);

const resources: Record<string, { translation: Record<string, unknown> }> = {};
for (const [path, mod] of Object.entries(modules)) {
  const match = /\.\/locales\/([^/]+)\/([^/]+)\.json$/.exec(path);
  if (!match) continue;
  const [, lang, component] = match;
  (resources[lang] ??= { translation: {} }).translation[component] = mod.default;
}

i18n
  .use(LanguageDetector)
  .use(initReactI18next)
  .init({
    resources,
    fallbackLng: "en",
    supportedLngs: ["en", "pt-BR", "es", "zh-CN"],
    nonExplicitSupportedLngs: true,
    interpolation: { escapeValue: false },
    detection: {
      order: ["localStorage", "navigator"],
      caches: ["localStorage"],
      lookupLocalStorage: "truthid:language",
    },
  });

export default i18n;
