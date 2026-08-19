import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/logo";
import {
  desktopDownloads,
  extensionDownloadUrl,
} from "@/lib/releases";

// Shared between app/page.tsx (English, unprefixed root — see
// app/layout.tsx for why) and app/[locale]/page.tsx (pt-BR/es/zh-CN).
// Fetches its own translations by explicit locale so it works from both
// roots without depending on NextIntlClientProvider/middleware context.
export async function LandingContent({ locale }: { locale: string }) {
  const t = await getTranslations({ locale, namespace: "download" });
  const docsHref = locale === "en" ? "/docs" : `/${locale}/docs`;

  return (
    <main className="flex flex-1 flex-col items-center">
      <section className="flex w-full max-w-2xl flex-col items-center gap-6 px-8 py-20 text-center">
        <Logo className="size-10 text-fd-primary" />
        <h1 className="text-4xl font-semibold">{t("heading")}</h1>
        <p className="max-w-md text-base text-fd-muted-foreground">
          {t("subtitle")}
        </p>
        <div className="flex flex-wrap items-center justify-center gap-3">
          <a
            href="#desktop"
            className="rounded-full bg-fd-primary px-6 py-3 text-sm font-medium text-fd-primary-foreground transition hover:opacity-90"
          >
            {t("desktopCta")}
          </a>
          <a
            href="#extension"
            className="rounded-full border border-fd-border px-6 py-3 text-sm font-medium transition hover:bg-fd-accent"
          >
            {t("extensionCta")}
          </a>
        </div>
      </section>

      <section
        id="desktop"
        className="w-full max-w-3xl scroll-mt-8 border-t border-fd-border px-8 py-16"
      >
        <h2 className="text-2xl font-semibold">{t("desktopHeading")}</h2>
        <p className="mt-2 max-w-xl text-sm text-fd-muted-foreground">
          {t("desktopSubtitle")}
        </p>

        <div className="mt-8 grid gap-4 sm:grid-cols-3">
          <div className="rounded-xl border border-fd-border bg-fd-card p-5">
            <h3 className="text-sm font-medium">{t("linuxLabel")}</h3>
            <div className="mt-3 flex flex-col gap-2">
              <DownloadLink href={desktopDownloads.linux.deb} label=".deb" />
              <DownloadLink
                href={desktopDownloads.linux.appImage}
                label=".AppImage"
              />
              <DownloadLink href={desktopDownloads.linux.rpm} label=".rpm" />
            </div>
          </div>

          <div className="rounded-xl border border-fd-border bg-fd-card p-5">
            <h3 className="text-sm font-medium">{t("windowsLabel")}</h3>
            <div className="mt-3 flex flex-col gap-2">
              <DownloadLink
                href={desktopDownloads.windows.exe}
                label=".exe"
              />
              <DownloadLink
                href={desktopDownloads.windows.msi}
                label=".msi"
              />
            </div>
          </div>

          <div className="rounded-xl border border-fd-border bg-fd-card p-5">
            <h3 className="text-sm font-medium">{t("macosLabel")}</h3>
            <div className="mt-3 flex flex-col gap-2">
              <DownloadLink href={desktopDownloads.macos.dmg} label=".dmg" />
            </div>
            <p className="mt-3 text-xs text-fd-muted-foreground">
              {t("macosNote")}
            </p>
          </div>
        </div>

        <div className="mt-4 rounded-xl border border-fd-border bg-fd-card p-5 sm:max-w-xs">
          <h3 className="text-sm font-medium">{t("androidLabel")}</h3>
          <div className="mt-3 flex flex-col gap-2">
            <DownloadLink href={desktopDownloads.android.apk} label=".apk" />
          </div>
          <p className="mt-3 text-xs text-fd-muted-foreground">
            {t("androidNote")}
          </p>
        </div>
      </section>

      <section
        id="extension"
        className="w-full max-w-3xl scroll-mt-8 border-t border-fd-border px-8 py-16"
      >
        <h2 className="text-2xl font-semibold">{t("extensionHeading")}</h2>
        <p className="mt-2 max-w-xl text-sm text-fd-muted-foreground">
          {t("extensionSubtitle")}
        </p>

        <DownloadLink
          href={extensionDownloadUrl}
          label={t("extensionDownload")}
          className="mt-6 inline-flex rounded-full bg-fd-primary px-6 py-3 text-sm font-medium text-fd-primary-foreground no-underline transition hover:opacity-90"
        />

        <ol className="mt-8 flex max-w-lg flex-col gap-3 text-left text-sm">
          <Step n={1} text={t("extensionStep1")} />
          <Step n={2} text={t("extensionStep2")} />
          <Step n={3} text={t("extensionStep3")} />
          <Step n={4} text={t("extensionStep4")} />
        </ol>
      </section>

      <footer className="w-full max-w-3xl border-t border-fd-border px-8 py-10 text-center">
        <Link href={docsHref} className="text-sm text-fd-primary underline">
          {t("docsCta")}
        </Link>
      </footer>
    </main>
  );
}

function DownloadLink({
  href,
  label,
  className,
}: {
  href: string;
  label: string;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={
        className ??
        "text-sm text-fd-primary underline underline-offset-2 hover:opacity-80"
      }
    >
      {label}
    </a>
  );
}

function Step({ n, text }: { n: number; text: string }) {
  return (
    <li className="flex gap-3">
      <span className="flex size-6 shrink-0 items-center justify-center rounded-full bg-fd-accent text-xs font-medium text-fd-accent-foreground">
        {n}
      </span>
      <span className="pt-0.5">{text}</span>
    </li>
  );
}
