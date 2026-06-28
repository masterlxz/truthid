import { useEffect, useState } from "react";

const RELEASES_URL =
  "https://api.github.com/repos/masterlxz/truthid/releases/latest";

function isNewer(latest: string, current: string): boolean {
  const l = latest.split(".").map(Number);
  const c = current.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    const lv = l[i] ?? 0;
    const cv = c[i] ?? 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

export function useUpdateCheck() {
  const [updateVersion, setUpdateVersion] = useState<string | null>(null);
  const [updateUrl, setUpdateUrl] = useState<string>("");

  useEffect(() => {
    fetch(RELEASES_URL, { headers: { "User-Agent": "TruthID-Desktop" } })
      .then((r) => r.json())
      .then((data) => {
        const tag: string = (data.tag_name ?? "").replace(/^v/, "");
        const url: string = data.html_url ?? "";
        if (tag && isNewer(tag, __APP_VERSION__)) {
          setUpdateVersion(tag);
          setUpdateUrl(url);
        }
      })
      .catch(() => {});
  }, []);

  return { updateVersion, updateUrl };
}
