"use client";

import { useState } from "react";
import { CheckIcon, CopyIcon, TerminalIcon } from "@/components/icons";
import { aptKeyringUrl, aptSourceLine } from "@/lib/releases";

const COMMANDS = [
  `curl -fsSL ${aptKeyringUrl} -o /usr/share/keyrings/truthid-archive-keyring.gpg`,
  `echo "${aptSourceLine}" | sudo tee /etc/apt/sources.list.d/truthid.list`,
  "sudo apt update && sudo apt install truth-id",
];

export function AptInstallCard({
  heading,
  subtitle,
  copyLabel,
  copiedLabel,
}: {
  heading: string;
  subtitle: string;
  copyLabel: string;
  copiedLabel: string;
}) {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    await navigator.clipboard.writeText(COMMANDS.join("\n"));
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  return (
    <div className="flex flex-col gap-6 rounded-xl border border-fd-border bg-fd-card p-6 sm:p-7 lg:flex-row lg:items-center lg:gap-10">
      <div className="flex items-start gap-3 lg:w-72 lg:shrink-0">
        <span className="flex size-9 shrink-0 items-center justify-center rounded-full bg-fd-accent text-fd-accent-foreground">
          <TerminalIcon className="size-4" />
        </span>
        <div>
          <h3 className="text-base font-medium">{heading}</h3>
          <p className="mt-1 text-sm text-fd-muted-foreground">{subtitle}</p>
        </div>
      </div>

      <div className="relative flex-1">
        <pre className="overflow-x-auto rounded-lg border border-fd-border bg-fd-secondary p-4 pr-14 font-mono text-sm leading-loose text-fd-secondary-foreground">
          <code>
            {COMMANDS.map((line) => (
              <div key={line} className="whitespace-pre-wrap break-all">
                {line}
              </div>
            ))}
          </code>
        </pre>
        <button
          type="button"
          onClick={handleCopy}
          aria-label={copied ? copiedLabel : copyLabel}
          title={copied ? copiedLabel : copyLabel}
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
