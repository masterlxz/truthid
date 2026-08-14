import { source } from "@/lib/source";
import { createFromSource } from "fumadocs-core/search/server";

// staticGET exports the whole index as one static file, searched client-side
// (via RootProvider's `search.options.type: "static"`) — no server needed,
// which keeps this route compatible with the GitHub Pages static export.
// force-static is required for `output: "export"` builds (see next.config.ts).
export const dynamic = "force-static";

export const { staticGET: GET } = createFromSource(source, {
  language: "english",
});
