import type { NextConfig } from "next";
import { createMDX } from "fumadocs-mdx/next";
import createNextIntlPlugin from "next-intl/plugin";

const withMDX = createMDX();
const withNextIntl = createNextIntlPlugin();

// Set by the "Deploy Docs" GitHub Actions workflow to produce a static
// export of just the /docs subtree for GitHub Pages — see
// .github/workflows/deploy-docs.yml. Unset (the default) for the real app,
// which runs via `next start`/Docker against the Rails backend and needs
// dynamic rendering for OAuth (/) and /dashboard.
const basePath = process.env.NEXT_BASE_PATH;

const nextConfig: NextConfig = {
  ...(basePath
    ? {
        output: "export",
        basePath,
        images: { unoptimized: true },
      }
    : {}),
  // Exposes NEXT_BASE_PATH (build-time only, not a NEXT_PUBLIC_ var) to the
  // client bundle too — locale-aware-root-provider.tsx needs it to build a
  // correct window.location.href for locale switches (a real navigation,
  // not router.push — see that file for why).
  env: {
    NEXT_PUBLIC_BASE_PATH: basePath ?? "",
  },
};

export default withNextIntl(withMDX(nextConfig));
