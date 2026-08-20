// Desktop installers and the browser extension package, hosted as GitHub
// Release assets (v2.0.0). Filenames embed the app version — when a newer
// tag is cut with a different version, these need updating by hand (Tauri's
// bundler names installers after tauri.conf.json's productName + version,
// so there's no stable "latest" filename to link against). Confirmed on the
// v2.0.0 release: productName changed from the old "tauri-app" default to
// "TruthID" sometime after v1.0.0 was built, which is why the v1.0.0 assets
// were named "tauri-app_1.0.0_..." — not because of package.json's `name`
// field, as originally assumed when this file was written for P57.
const REPO = "masterlxz/truthid";
const TAG = "v2.0.0";

function assetUrl(filename: string): string {
  return `https://github.com/${REPO}/releases/download/${TAG}/${filename}`;
}

export const desktopDownloads = {
  linux: {
    deb: assetUrl("TruthID_2.0.0_amd64.deb"),
    appImage: assetUrl("TruthID_2.0.0_amd64.AppImage"),
    rpm: assetUrl("TruthID-2.0.0-1.x86_64.rpm"),
  },
  windows: {
    exe: assetUrl("TruthID_2.0.0_x64-setup.exe"),
    msi: assetUrl("TruthID_2.0.0_x64_en-US.msi"),
  },
  macos: {
    // Apple Silicon only — the macos-latest CI runner doesn't produce an
    // Intel build.
    dmg: assetUrl("TruthID_2.0.0_aarch64.dmg"),
  },
  android: {
    apk: assetUrl("app-release.apk"),
  },
};

// Extension version is now unified with the other 2 apps (v2.0.0) — see
// project/PENDING.md, "versão unificada" (Sessão 213).
export const extensionDownloadUrl = assetUrl(
  "truthid-vault-extension-2.0.0-chrome.zip",
);

export const releasePageUrl = `https://github.com/${REPO}/releases/tag/${TAG}`;
