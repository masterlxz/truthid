// Idioma do i18next não bate 1:1 com tag de locale do Intl (ex. nosso "es"
// genérico vira "es-ES" pro Intl escolher convenções regionais consistentes)
// — mapeia explicitamente em vez de passar `language` direto pro Intl.
const LOCALE_MAP: Record<string, string> = {
  en: "en-US",
  "pt-BR": "pt-BR",
  es: "es-ES",
  "zh-CN": "zh-CN",
};

function resolveLocale(language: string): string {
  return LOCALE_MAP[language] ?? language;
}

// `language` sempre vem explícito do `i18n.language` de quem chama (via
// `useTranslation()` no componente) — nunca de um singleton importado
// direto, senão o componente não re-renderiza quando o usuário troca de
// idioma no seletor (useTranslation() assina o evento `languageChanged`,
// um import solto do módulo `i18n` não).
export function formatDate(
  secs: number,
  language: string,
  options: Intl.DateTimeFormatOptions = { day: "2-digit", month: "2-digit", year: "numeric" },
): string {
  return new Date(secs * 1000).toLocaleDateString(resolveLocale(language), options);
}

export function formatDateTime(
  secs: number,
  language: string,
  options?: Intl.DateTimeFormatOptions,
): string {
  return new Date(secs * 1000).toLocaleString(resolveLocale(language), options);
}
