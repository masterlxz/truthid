import type { Metadata } from "next";
import { Inter, Space_Grotesk, Geist_Mono } from "next/font/google";
import { DocsLayout } from "fumadocs-ui/layouts/docs";
import { source } from "@/lib/source";
import { baseOptions } from "@/lib/layout.shared";
import { LocaleAwareRootProvider } from "@/components/locale-aware-root-provider";
import "@/app/globals.css";

// This is an independent root layout (its own <html>/<body>), sibling to
// app/[locale]/ — see lib/i18n.ts for why: English docs stay on this
// physically unprefixed /docs route rather than living under app/[locale],
// because the mechanism that would hide a locale prefix at runtime
// (hideLocale/proxy rewrite) can't run under the GitHub Pages static export.
const inter = Inter({ variable: "--font-sans", subsets: ["latin"] });
const spaceGrotesk = Space_Grotesk({
  variable: "--font-heading",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
});
const geistMono = Geist_Mono({ variable: "--font-mono", subsets: ["latin"] });

export const metadata: Metadata = {
  title: "TruthID",
  description: "TruthID — self-sovereign identity",
};

export default function Layout({ children }: LayoutProps<"/docs">) {
  return (
    <html
      lang="en"
      className={`${inter.variable} ${spaceGrotesk.variable} ${geistMono.variable} h-full antialiased`}
      suppressHydrationWarning
    >
      <body className="min-h-full flex flex-col">
        <LocaleAwareRootProvider locale="en">
          <DocsLayout tree={source.getPageTree("en")} {...baseOptions("en")}>
            {children}
          </DocsLayout>
        </LocaleAwareRootProvider>
      </body>
    </html>
  );
}
