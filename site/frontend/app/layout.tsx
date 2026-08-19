import type { Metadata } from "next";
import { Inter, Space_Grotesk, Geist_Mono } from "next/font/google";
import { LocaleAwareRootProvider } from "@/components/locale-aware-root-provider";
import "@/app/globals.css";

// Independent root layout (own <html>/<body>), sibling to app/docs/ and
// app/[locale]/ — see app/docs/layout.tsx for why: the English landing
// stays on this physically unprefixed root ("/") instead of living under
// app/[locale], because the mechanism that would hide a locale prefix at
// runtime (hideLocale/proxy rewrite) can't run under the GitHub Pages
// static export.
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

export default function Layout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${inter.variable} ${spaceGrotesk.variable} ${geistMono.variable} h-full antialiased`}
      suppressHydrationWarning
    >
      <body className="min-h-full flex flex-col">
        <LocaleAwareRootProvider locale="en">{children}</LocaleAwareRootProvider>
      </body>
    </html>
  );
}
