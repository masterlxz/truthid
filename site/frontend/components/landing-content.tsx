import type { ReactNode } from "react";
import Link from "next/link";
import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/logo";
import {
  DownloadIcon,
  KeyShieldIcon,
  LockIcon,
  MonitorIcon,
  PuzzleIcon,
  ScanIcon,
} from "@/components/icons";
import {
  aptKeyringUrl,
  aptSourceLine,
  desktopDownloads,
  extensionDownloadUrl,
} from "@/lib/releases";

// Shared between app/page.tsx (English, unprefixed root — see
// app/layout.tsx for why) and app/[locale]/page.tsx (pt-BR/es/zh-CN).
// Fetches its own translations by explicit locale so it works from both
// roots without depending on NextIntlClientProvider/middleware context.
export async function LandingContent({ locale }: { locale: string }) {
  const t = await getTranslations({ locale, namespace: "download" });
  // Bare "/docs" (no slug) 404s — the fumadocs source has no page mapped to
  // an empty slug, only explicit ones like intro/quickstart/etc.
  const docsHref =
    locale === "en" ? "/docs/intro" : `/${locale}/docs/intro`;

  return (
    <main className="relative flex flex-1 flex-col items-center overflow-hidden">
      {/* Decorative background across the whole page — a faint dot grid plus
          a few large blurred color blobs at different scroll depths. Without
          this, wide viewports read as a narrow content column floating in a
          lot of empty margin. */}
      <div
        aria-hidden="true"
        className="pointer-events-none absolute inset-0 -z-20 opacity-[0.6] [background-image:radial-gradient(var(--color-fd-border)_1px,transparent_1px)] [background-size:28px_28px]"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -right-32 top-[2%] -z-10 size-[760px] rounded-full bg-fd-primary/20 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -left-40 top-[28%] -z-10 size-[640px] rounded-full bg-fd-accent blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -right-32 top-[58%] -z-10 size-[680px] rounded-full bg-fd-primary/15 blur-3xl"
      />
      <div
        aria-hidden="true"
        className="pointer-events-none absolute -left-40 top-[88%] -z-10 size-[600px] rounded-full bg-fd-accent blur-3xl"
      />

      {/* Hero */}
      <section className="relative w-full overflow-hidden">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute inset-x-0 top-0 -z-10 h-[560px] bg-[radial-gradient(60%_60%_at_50%_0%,var(--color-fd-accent)_0%,transparent_70%)]"
        />
        <div className="mx-auto flex max-w-2xl flex-col items-center gap-6 px-8 pb-20 pt-24 text-center">
          <Logo className="size-10 text-fd-primary" />
          <p className="text-sm font-medium uppercase tracking-wide text-fd-primary">
            {t("eyebrow")}
          </p>
          <h1 className="text-4xl font-semibold text-balance sm:text-5xl">
            {t("headline")}
          </h1>
          <p className="max-w-lg text-base text-fd-muted-foreground">
            {t("subtitle")}
          </p>
          <div className="mt-2 flex flex-wrap items-center justify-center gap-3">
            <a
              href="#desktop"
              className="inline-flex items-center gap-2 rounded-full bg-fd-primary px-6 py-3 text-sm font-medium text-fd-primary-foreground transition hover:opacity-90"
            >
              <MonitorIcon className="size-4" />
              {t("desktopCta")}
            </a>
            <a
              href="#extension"
              className="inline-flex items-center gap-2 rounded-full border border-fd-border px-6 py-3 text-sm font-medium transition hover:bg-fd-accent"
            >
              <PuzzleIcon className="size-4" />
              {t("extensionCta")}
            </a>
          </div>
        </div>
      </section>

      {/* Why TruthID */}
      <section className="w-full border-t border-fd-border bg-fd-card/40 px-8 py-16">
        <div className="mx-auto max-w-6xl">
          <h2 className="text-center text-2xl font-semibold">
            {t("featuresHeading")}
          </h2>
          <div className="mt-10 grid gap-6 sm:grid-cols-3">
            <FeatureCard
              icon={<KeyShieldIcon className="size-5" />}
              title={t("feature1Title")}
              body={t("feature1Body")}
            />
            <FeatureCard
              icon={<LockIcon className="size-5" />}
              title={t("feature2Title")}
              body={t("feature2Body")}
            />
            <FeatureCard
              icon={<ScanIcon className="size-5" />}
              title={t("feature3Title")}
              body={t("feature3Body")}
            />
          </div>
        </div>
      </section>

      {/* Desktop app */}
      <section id="desktop" className="w-full scroll-mt-8 px-8 py-16">
        <div className="mx-auto max-w-6xl">
          <SectionHeading
            icon={<MonitorIcon className="size-5" />}
            heading={t("desktopHeading")}
            subtitle={t("desktopSubtitle")}
          />

          <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <OsCard
              label={t("linuxLabel")}
              primaryHref={desktopDownloads.linux.deb}
              primaryLabel={t("linuxPrimaryCta")}
              otherFormatsLabel={t("otherFormats")}
              otherFormats={[
                { href: desktopDownloads.linux.appImage, label: ".AppImage" },
                { href: desktopDownloads.linux.rpm, label: ".rpm" },
              ]}
              extra={<AptInstallBlock label={t("linuxAptLabel")} />}
            />
            <OsCard
              label={t("windowsLabel")}
              primaryHref={desktopDownloads.windows.exe}
              primaryLabel={t("windowsPrimaryCta")}
              otherFormatsLabel={t("otherFormats")}
              otherFormats={[
                { href: desktopDownloads.windows.msi, label: ".msi" },
              ]}
            />
            <OsCard
              label={t("macosLabel")}
              primaryHref={desktopDownloads.macos.dmg}
              primaryLabel={t("macosPrimaryCta")}
              note={t("macosNote")}
            />
            <OsCard
              label={t("androidLabel")}
              primaryHref={desktopDownloads.android.apk}
              primaryLabel={t("androidPrimaryCta")}
              note={t("androidNote")}
            />
          </div>
        </div>
      </section>

      {/* Browser extension */}
      <section
        id="extension"
        className="w-full scroll-mt-8 border-t border-fd-border bg-fd-card/40 px-8 py-16"
      >
        <div className="mx-auto max-w-4xl">
          <SectionHeading
            icon={<PuzzleIcon className="size-5" />}
            heading={t("extensionHeading")}
            subtitle={t("extensionSubtitle")}
          />

          <a
            href={extensionDownloadUrl}
            className="mt-6 inline-flex items-center gap-2 rounded-full bg-fd-primary px-6 py-3 text-sm font-medium text-fd-primary-foreground transition hover:opacity-90"
          >
            <DownloadIcon className="size-4" />
            {t("extensionDownload")}
          </a>

          <ol className="mt-8 flex max-w-lg flex-col gap-3 text-left text-sm">
            <Step n={1} text={t("extensionStep1")} />
            <Step n={2} text={t("extensionStep2")} />
            <Step n={3} text={t("extensionStep3")} />
            <Step n={4} text={t("extensionStep4")} />
          </ol>
        </div>
      </section>

      <footer className="w-full border-t border-fd-border px-8 py-10 text-center">
        <Link href={docsHref} className="text-sm text-fd-primary underline">
          {t("docsCta")}
        </Link>
      </footer>
    </main>
  );
}

function SectionHeading({
  icon,
  heading,
  subtitle,
}: {
  icon: ReactNode;
  heading: string;
  subtitle: string;
}) {
  return (
    <div className="flex flex-col items-start gap-3">
      <span className="flex size-10 items-center justify-center rounded-full bg-fd-accent text-fd-accent-foreground">
        {icon}
      </span>
      <h2 className="text-2xl font-semibold">{heading}</h2>
      <p className="max-w-xl text-sm text-fd-muted-foreground">{subtitle}</p>
    </div>
  );
}

function FeatureCard({
  icon,
  title,
  body,
}: {
  icon: ReactNode;
  title: string;
  body: string;
}) {
  return (
    <div className="rounded-xl border border-fd-border bg-fd-card p-6">
      <span className="flex size-9 items-center justify-center rounded-full bg-fd-accent text-fd-accent-foreground">
        {icon}
      </span>
      <h3 className="mt-4 text-base font-medium">{title}</h3>
      <p className="mt-2 text-sm text-fd-muted-foreground">{body}</p>
    </div>
  );
}

function OsCard({
  label,
  primaryHref,
  primaryLabel,
  otherFormatsLabel,
  otherFormats,
  note,
  extra,
}: {
  label: string;
  primaryHref: string;
  primaryLabel: string;
  otherFormatsLabel?: string;
  otherFormats?: { href: string; label: string }[];
  note?: string;
  extra?: ReactNode;
}) {
  return (
    <div className="flex flex-col rounded-xl border border-fd-border bg-fd-card p-5">
      <h3 className="text-sm font-medium text-fd-muted-foreground">{label}</h3>
      <a
        href={primaryHref}
        className="mt-3 inline-flex items-center justify-center gap-2 rounded-full border border-fd-border px-4 py-2.5 text-sm font-medium transition hover:bg-fd-accent"
      >
        <DownloadIcon className="size-4" />
        {primaryLabel}
      </a>
      {otherFormats && otherFormats.length > 0 && (
        <p className="mt-3 text-xs text-fd-muted-foreground">
          {otherFormatsLabel}{" "}
          {otherFormats.map((f, i) => (
            <span key={f.href}>
              {i > 0 && " · "}
              <a href={f.href} className="underline underline-offset-2 hover:opacity-80">
                {f.label}
              </a>
            </span>
          ))}
        </p>
      )}
      {note && <p className="mt-3 text-xs text-fd-muted-foreground">{note}</p>}
      {extra}
    </div>
  );
}

// Commands themselves aren't translated (shell syntax, same everywhere) —
// only the label above them is, via the `download.linuxAptLabel` key.
function AptInstallBlock({ label }: { label: string }) {
  const commands = [
    `curl -fsSL ${aptKeyringUrl} -o /usr/share/keyrings/truthid-archive-keyring.gpg`,
    `echo "${aptSourceLine}" | sudo tee /etc/apt/sources.list.d/truthid.list`,
    "sudo apt update && sudo apt install truth-id",
  ];
  return (
    <div className="mt-4 border-t border-fd-border pt-3">
      <p className="text-xs text-fd-muted-foreground">{label}</p>
      <pre className="mt-2 overflow-x-auto rounded-lg bg-fd-secondary p-3 text-[11px] leading-relaxed">
        <code>
          {commands.map((line) => (
            <div key={line}>{line}</div>
          ))}
        </code>
      </pre>
    </div>
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
