import type { Metadata } from "next";
import { Inter, Space_Grotesk, Geist_Mono } from "next/font/google";
import { NextIntlClientProvider, hasLocale } from "next-intl";
import { getTranslations, setRequestLocale } from "next-intl/server";
import { notFound } from "next/navigation";
import { routing } from "@/i18n/routing";
import { LocaleAwareRootProvider } from "@/components/locale-aware-root-provider";
import "@/app/globals.css";

// Independent root layout (own <html>/<body>), sibling to app/docs/ — see
// lib/i18n.ts / components/locale-aware-root-provider.tsx for why English
// docs live on a separate, unprefixed root instead of here. This tree
// covers: landing (/ and /pt-BR, /es, /zh-CN), /dashboard, and the
// non-English docs (/pt-BR/docs, /es/docs, /zh-CN/docs).
const inter = Inter({ variable: "--font-sans", subsets: ["latin"] });
const spaceGrotesk = Space_Grotesk({
  variable: "--font-heading",
  subsets: ["latin"],
  weight: ["500", "600", "700"],
});
const geistMono = Geist_Mono({ variable: "--font-mono", subsets: ["latin"] });

export function generateStaticParams() {
  return routing.locales.map((locale) => ({ locale }));
}

export async function generateMetadata({
  params,
}: {
  params: Promise<{ locale: string }>;
}): Promise<Metadata> {
  const { locale } = await params;
  const t = await getTranslations({ locale, namespace: "metadata" });
  return { title: t("title"), description: t("description") };
}

export default async function LocaleLayout({
  children,
  params,
}: LayoutProps<"/[locale]">) {
  const { locale } = await params;
  if (!hasLocale(routing.locales, locale)) notFound();

  // Required for static rendering (generateStaticParams) — tells next-intl
  // which locale the current render is for without waiting on middleware.
  setRequestLocale(locale);

  return (
    <html
      lang={locale}
      className={`${inter.variable} ${spaceGrotesk.variable} ${geistMono.variable} h-full antialiased`}
      suppressHydrationWarning
    >
      <body className="min-h-full flex flex-col">
        <NextIntlClientProvider>
          <LocaleAwareRootProvider locale={locale}>
            {children}
          </LocaleAwareRootProvider>
        </NextIntlClientProvider>
      </body>
    </html>
  );
}
