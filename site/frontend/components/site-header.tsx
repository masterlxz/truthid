"use client";

import {
  LanguageSelect,
  LanguageSelectText,
} from "fumadocs-ui/layouts/shared/slots/language-select";
import { ThemeSwitch } from "fumadocs-ui/layouts/shared/slots/theme-switch";
import { Link } from "@/i18n/navigation";
import { Logo } from "@/components/logo";

// /signin and /dashboard have no shared chrome of their own (unlike /docs,
// which gets a language switcher and theme toggle for free from DocsLayout's
// own nav — see lib/layout.shared.tsx, and unlike the landing page, which
// has its own equivalent in landing-header.tsx). This is the version for
// those two pages.
export function SiteHeader() {
  return (
    <header className="flex items-center justify-between p-4">
      <Link href="/" className="flex items-center gap-2 text-sm font-medium">
        <Logo className="size-5 text-fd-primary" />
        TruthID
      </Link>
      <div className="flex items-center gap-2">
        <ThemeSwitch />
        <LanguageSelect>
          <LanguageSelectText />
        </LanguageSelect>
      </div>
    </header>
  );
}
