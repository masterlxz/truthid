// Same idea as desktop/src/hooks/useUpdateCheck.ts and the checker in
// mobile/lib/main.dart: poll GitHub's "latest release" and compare semver.
// Unlike those two, there's no real auto-update path here — an extension
// loaded via "Load unpacked" never gets Chrome's built-in update mechanism
// (that only works for Chrome Web Store / enterprise policy installs) — so
// the caller is expected to point the user at manual reinstall instructions
// instead of a direct download link.
const RELEASES_URL =
  'https://api.github.com/repos/masterlxz/truthid/releases/latest';

export function isNewer(latest: string, current: string): boolean {
  const l = latest.split('.').map(Number);
  const c = current.split('.').map(Number);
  for (let i = 0; i < 3; i++) {
    const lv = l[i] ?? 0;
    const cv = c[i] ?? 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

// currentVersion is a parameter (not read from browser.runtime.getManifest()
// here) so this stays pure and easy to test without mocking the browser API.
export async function checkForUpdate(currentVersion: string): Promise<string | null> {
  try {
    const res = await fetch(RELEASES_URL, {
      headers: { 'User-Agent': 'TruthID-Extension' },
    });
    const data = await res.json();
    const tag: string = (data.tag_name ?? '').replace(/^v/, '');
    if (tag && isNewer(tag, currentVersion)) {
      return tag;
    }
    return null;
  } catch {
    return null;
  }
}
