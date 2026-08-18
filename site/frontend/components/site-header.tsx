"use client";

import {
  LanguageSelect,
  LanguageSelectText,
} from "fumadocs-ui/layouts/shared/slots/language-select";
import { Link } from "@/i18n/navigation";
import { Logo } from "@/components/logo";

// Landing (/) and /dashboard have no shared chrome of their own (unlike
// /docs, which gets a language switcher for free from DocsLayout's own nav
// — see lib/layout.shared.tsx). This is the equivalent for those two pages.
export function SiteHeader() {
  return (
    <header className="flex items-center justify-between p-4">
      <Link href="/" className="flex items-center gap-2 text-sm font-medium">
        <Logo className="size-5 text-fd-primary" />
        TruthID
      </Link>
      <LanguageSelect>
        <LanguageSelectText />
      </LanguageSelect>
    </header>
  );
}
