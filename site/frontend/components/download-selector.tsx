"use client";

import { useState } from "react";
import { CheckIcon, CopyIcon, DownloadIcon } from "@/components/icons";
import { aptKeyringUrl, aptSourceLine } from "@/lib/releases";

type DirectMethod = {
  kind: "direct";
  primaryHref: string;
  primaryLabel: string;
  otherFormatsLabel?: string;
  otherFormats?: { href: string; label: string }[];
  note?: string;
};

type AptMethod = {
  kind: "apt";
  subtitle: string;
  copyLabel: string;
  copiedLabel: string;
};

type Method = DirectMethod | AptMethod;

export type OsEntry = {
  id: string;
  label: string;
  methods: { id: string; label: string; method: Method }[];
};

const APT_COMMANDS = [
  `curl -fsSL ${aptKeyringUrl} -o /usr/share/keyrings/truthid-archive-keyring.gpg`,
  `echo "${aptSourceLine}" | sudo tee /etc/apt/sources.list.d/truthid.list`,
  "sudo apt update && sudo apt install truth-id",
];

// One selector replaces what used to be 4 flat OS cards + a separate wide
// APT card: pick the OS first, then (only when an OS has more than one way
// to install) pick the method. Built to scale — AUR/Homebrew/winget/Flatpak
// (project/ROADMAP.md, "Instaladores nativos") each just add another entry
// to the relevant OS's methods list, instead of another card in a growing
// vertical stack.
export function DownloadSelector({ os }: { os: OsEntry[] }) {
  const [osId, setOsId] = useState(os[0].id);
  const activeOs = os.find((o) => o.id === osId) ?? os[0];
  const [methodId, setMethodId] = useState(activeOs.methods[0].id);
  const activeMethod =
    activeOs.methods.find((m) => m.id === methodId) ?? activeOs.methods[0];

  function selectOs(id: string) {
    setOsId(id);
    const next = os.find((o) => o.id === id);
    setMethodId(next ? next.methods[0].id : "");
  }

  return (
    <div className="rounded-xl border border-fd-border bg-fd-card p-6 sm:p-8">
      <div
        role="tablist"
        className="flex flex-wrap gap-2 border-b border-fd-border pb-5"
      >
        {os.map((o) => (
          <button
            key={o.id}
            type="button"
            role="tab"
            aria-selected={o.id === osId}
            onClick={() => selectOs(o.id)}
            className={
              "rounded-full px-4 py-2 text-sm font-medium transition " +
              (o.id === osId
                ? "bg-fd-primary text-fd-primary-foreground"
                : "text-fd-muted-foreground hover:bg-fd-accent hover:text-fd-accent-foreground")
            }
          >
            {o.label}
          </button>
        ))}
      </div>

      {activeOs.methods.length > 1 && (
        <div role="tablist" className="mt-5 flex gap-1">
          {activeOs.methods.map((m) => (
            <button
              key={m.id}
              type="button"
              role="tab"
              aria-selected={m.id === methodId}
              onClick={() => setMethodId(m.id)}
              className={
                "rounded-md px-3 py-1.5 text-sm font-medium transition " +
                (m.id === methodId
                  ? "bg-fd-accent text-fd-accent-foreground"
                  : "text-fd-muted-foreground hover:bg-fd-accent/60")
              }
            >
              {m.label}
            </button>
          ))}
        </div>
      )}

      <div className="mt-6">
        {activeMethod.method.kind === "direct" ? (
          <DirectPanel method={activeMethod.method} />
        ) : (
          <AptPanel method={activeMethod.method} />
        )}
      </div>
    </div>
  );
}

function DirectPanel({ method }: { method: DirectMethod }) {
  return (
    <div>
      <a
        href={method.primaryHref}
        className="inline-flex items-center gap-2 rounded-full bg-fd-primary px-6 py-3 text-sm font-medium text-fd-primary-foreground transition hover:opacity-90"
      >
        <DownloadIcon className="size-4" />
        {method.primaryLabel}
      </a>
      {method.otherFormats && method.otherFormats.length > 0 && (
        <p className="mt-4 text-sm text-fd-muted-foreground">
          {method.otherFormatsLabel}{" "}
          {method.otherFormats.map((f, i) => (
            <span key={f.href}>
              {i > 0 && " · "}
              <a
                href={f.href}
                className="underline underline-offset-2 hover:opacity-80"
              >
                {f.label}
              </a>
            </span>
          ))}
        </p>
      )}
      {method.note && (
        <p className="mt-4 text-sm text-fd-muted-foreground">{method.note}</p>
      )}
    </div>
  );
}

function AptPanel({ method }: { method: AptMethod }) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    await navigator.clipboard.writeText(APT_COMMANDS.join("\n"));
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div>
      <p className="text-sm text-fd-muted-foreground">{method.subtitle}</p>
      <div className="relative mt-4">
        <pre className="overflow-x-auto rounded-lg border border-fd-border bg-fd-secondary p-4 pr-14 font-mono text-sm leading-loose text-fd-secondary-foreground">
          <code>
            {APT_COMMANDS.map((line) => (
              <div key={line} className="whitespace-pre-wrap break-all">
                {line}
              </div>
            ))}
          </code>
        </pre>
        <button
          type="button"
          onClick={handleCopy}
          aria-label={copied ? method.copiedLabel : method.copyLabel}
          title={copied ? method.copiedLabel : method.copyLabel}
          className="absolute right-3 top-3 flex size-8 items-center justify-center rounded-md border border-fd-border bg-fd-card text-fd-muted-foreground transition hover:bg-fd-accent hover:text-fd-accent-foreground"
        >
          {copied ? (
            <CheckIcon className="size-4" />
          ) : (
            <CopyIcon className="size-4" />
          )}
        </button>
      </div>
    </div>
  );
}
