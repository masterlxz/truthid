// Desktop installers and the browser extension package, hosted as GitHub
// Release assets (v1.0.0). Filenames embed the app version — when a newer
// tag is cut with a different version, these need updating by hand (Tauri's
// bundler names installers after desktop/package.json's version, so there's
// no stable "latest" filename to link against).
const REPO = "masterlxz/truthid";
const TAG = "v1.0.0";

function assetUrl(filename: string): string {
  return `https://github.com/${REPO}/releases/download/${TAG}/${filename}`;
}

export const desktopDownloads = {
  linux: {
    deb: assetUrl("tauri-app_1.0.0_amd64.deb"),
    appImage: assetUrl("tauri-app_1.0.0_amd64.AppImage"),
    rpm: assetUrl("tauri-app-1.0.0-1.x86_64.rpm"),
  },
  windows: {
    exe: assetUrl("tauri-app_1.0.0_x64-setup.exe"),
    msi: assetUrl("tauri-app_1.0.0_x64_en-US.msi"),
  },
  macos: {
    // Apple Silicon only — the macos-latest CI runner doesn't produce an
    // Intel build.
    dmg: assetUrl("tauri-app_1.0.0_aarch64.dmg"),
  },
  android: {
    apk: assetUrl("app-release.apk"),
  },
};

// Extension version is tracked independently from the desktop app
// (extension/package.json, currently 0.1.0) — the zip filename reflects
// that, not the v1.0.0 tag.
export const extensionDownloadUrl = assetUrl(
  "truthid-vault-extension-0.1.0-chrome.zip",
);

export const releasePageUrl = `https://github.com/${REPO}/releases/tag/${TAG}`;
