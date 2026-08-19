"use client";

import { usePathname } from "next/navigation";
import { RootProvider } from "fumadocs-ui/provider/next";
import { i18nProvider } from "fumadocs-ui/i18n";
import type { ReactNode } from "react";
import { translations } from "@/lib/layout.shared";

const NON_DEFAULT_LOCALES = ["pt-BR", "es", "zh-CN"];

function stripLocalePrefix(pathname: string): string {
  const [, first] = pathname.split("/");
  if (NON_DEFAULT_LOCALES.includes(first)) {
    return pathname.slice(first.length + 1) || "/";
  }
  return pathname;
}

function withLocalePrefix(pathname: string, locale: string): string {
  if (locale === "en") return pathname;
  return `/${locale}${pathname === "/" ? "" : pathname}`;
}

// Fumadocs' default language-switcher onChange assumes every locale
// (including the default) has a URL prefix — switching from /pt-BR/docs/intro
// back to English would try to navigate to /en/docs/intro, which doesn't
// exist here (English lives on the unprefixed /docs root, a separate root
// layout from app/[locale]/docs — see lib/i18n.ts). onLocaleChange overrides
// that with plain next/navigation hooks instead of next-intl's, since this
// component is rendered from BOTH root layouts (app/docs/layout.tsx has no
// NextIntlClientProvider, so next-intl's useLocale()-dependent navigation
// hooks would throw there). The prefix logic below is deliberately kept in
// sync with i18n/routing.ts's localePrefix: "as-needed" behavior by hand.
//
// Switching locale always crosses into a *different* root layout (this repo
// has 3: app/, app/docs/, app/[locale]/ — see app/docs/layout.tsx) — a
// full-document reload, not a soft client transition. Confirmed by testing
// live: a router.push() across root layouts here does swap the page, but
// next-themes' dark/light class gets silently dropped on the new tree —
// resolvedTheme still reads the right value from localStorage, but nothing
// re-applies it to <html> outside of next-themes' anti-flash inline script,
// which only runs on a genuine page load. window.location.href forces that
// real load, so the persisted theme survives a locale switch.
export function LocaleAwareRootProvider({
  locale,
  children,
}: {
  locale: string;
  children: ReactNode;
}) {
  const pathname = usePathname() ?? "/";

  return (
    <RootProvider
      search={{ options: { type: "static" } }}
      i18n={{
        ...i18nProvider(translations, locale),
        onLocaleChange: (newLocale) => {
          window.location.href = withLocalePrefix(
            stripLocalePrefix(pathname),
            newLocale,
          );
        },
      }}
    >
      {children}
    </RootProvider>
  );
}
