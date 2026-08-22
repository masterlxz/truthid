// Small set of generic, geometric line icons (24x24, stroke-based — same
// visual language as components/logo.tsx). Deliberately not OS/brand logos:
// hand-approximated trademark silhouettes (Apple, Windows, Tux) risk looking
// wrong without a real reference asset. These are safe, consistent, and
// still make the download page feel designed instead of a list of <a> tags.

type IconProps = { className?: string };

export function DownloadIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path d="M12 3v11" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
      <path
        d="M7.5 10.5 12 15l4.5-4.5"
        stroke="currentColor"
        strokeWidth="1.75"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
      <path d="M4.5 19h15" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
    </svg>
  );
}

export function MonitorIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <rect x="3" y="4.5" width="18" height="12" rx="2" stroke="currentColor" strokeWidth="1.75" />
      <path d="M8.5 20h7M12 16.5V20" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" />
    </svg>
  );
}

export function PuzzleIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path
        d="M9 3.75c0-.97.9-1.75 2-1.75s2 .78 2 1.75V5.5h2.25c1.1 0 2 .84 2 1.88v2.12h1.75c.97 0 1.75.9 1.75 2s-.78 2-1.75 2H17.25v2.12c0 1.04-.9 1.88-2 1.88H13v1.75c0 .97-.9 1.75-2 1.75s-2-.78-2-1.75V17.5H6.75c-1.1 0-2-.84-2-1.88V13.5H3c-.97 0-1.75-.9-1.75-2s.78-2 1.75-2h1.75V7.38c0-1.04.9-1.88 2-1.88H9V3.75Z"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
    </svg>
  );
}

export function KeyShieldIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path
        d="M12 3 19 6v5.5c0 5-3.2 7.8-7 9-3.8-1.2-7-4-7-9V6l7-3Z"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinejoin="round"
      />
      <circle cx="12" cy="10.8" r="1.6" stroke="currentColor" strokeWidth="1.6" />
      <path d="M12 12.4V15" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

export function LockIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <rect x="5" y="10.5" width="14" height="9.5" rx="2" stroke="currentColor" strokeWidth="1.6" />
      <path d="M8 10.5V7.5a4 4 0 0 1 8 0v3" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <circle cx="12" cy="15" r="1.4" stroke="currentColor" strokeWidth="1.6" />
    </svg>
  );
}

export function ScanIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path d="M4 8.5V6a2 2 0 0 1 2-2h2.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M20 8.5V6a2 2 0 0 0-2-2h-2.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M4 15.5V18a2 2 0 0 0 2 2h2.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M20 15.5V18a2 2 0 0 1-2 2h-2.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
      <path d="M4 12h16" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

export function TerminalIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <rect x="3" y="4.5" width="18" height="15" rx="2" stroke="currentColor" strokeWidth="1.6" />
      <path d="M6.5 9.5 10 12.5 6.5 15.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M12 15.5h5.5" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

export function CopyIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <rect x="8.5" y="8.5" width="11" height="11" rx="1.75" stroke="currentColor" strokeWidth="1.6" />
      <path d="M5.5 15V6.25A1.75 1.75 0 0 1 7.25 4.5H15" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  );
}

export function CheckIcon({ className }: IconProps) {
  return (
    <svg viewBox="0 0 24 24" fill="none" className={className} aria-hidden="true">
      <path d="M5 12.5 10 17.5 19 7" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}
