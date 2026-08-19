"use client";

import Link from "next/link";
import {
  LanguageSelect,
  LanguageSelectText,
} from "fumadocs-ui/layouts/shared/slots/language-select";
import { Logo } from "@/components/logo";

// Header for the landing page (/ and /pt-BR, /es, /zh-CN). Deliberately
// plain next/link with a manually-computed href instead of next-intl's Link
// (@/i18n/navigation) — this component is also rendered from the unprefixed
// app/page.tsx root, which has no NextIntlClientProvider (see
// app/layout.tsx), and next-intl's Link needs that context to resolve the
// current locale. next/link doesn't have that problem (no provider needed)
// and still respects next.config's basePath, unlike a raw <a href>.
// LanguageSelect is unaffected either way — it reads from fumadocs' own
// RootProvider i18n context, wired up by LocaleAwareRootProvider in every
// root layout.
export function LandingHeader({ locale }: { locale: string }) {
  const homeHref = locale === "en" ? "/" : `/${locale}`;

  return (
    <header className="flex items-center justify-between p-4">
      <Link href={homeHref} className="flex items-center gap-2 text-sm font-medium">
        <Logo className="size-5 text-fd-primary" />
        TruthID
      </Link>
      <LanguageSelect>
        <LanguageSelectText />
      </LanguageSelect>
    </header>
  );
}
