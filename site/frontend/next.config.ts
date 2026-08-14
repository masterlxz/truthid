import type { NextConfig } from "next";
import { createMDX } from "fumadocs-mdx/next";

const withMDX = createMDX();

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
};

export default withMDX(nextConfig);
