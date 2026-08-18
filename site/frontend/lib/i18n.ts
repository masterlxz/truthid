import { defineI18n } from "fumadocs-core/i18n";

// English stays on the physically unprefixed `/docs/...` route (a separate,
// independent root layout — see app/docs/layout.tsx) rather than relying on
// hideLocale's runtime rewrite, because that rewrite needs a proxy and the
// GitHub Pages docs build is a pure static export (no proxy at all). This
// config is still shared with app/[locale]/docs/ (pt-BR/es/zh-CN) so both
// trees agree on the same locale list and on how page.url is computed —
// hideLocale keeps internally-generated links (sidebar, breadcrumbs,
// pagination) for the default language pointing at the unprefixed URL that
// actually exists.
export const i18n = defineI18n({
  languages: ["en", "pt-BR", "es", "zh-CN"],
  defaultLanguage: "en",
  hideLocale: "default-locale",
});
