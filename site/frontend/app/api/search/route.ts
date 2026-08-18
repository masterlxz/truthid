import { source } from "@/lib/source";
import { createFromSource } from "fumadocs-core/search/server";

// staticGET exports the whole index as one static file, searched client-side
// (via RootProvider's `search.options.type: "static"`) — no server needed,
// which keeps this route compatible with the GitHub Pages static export.
// force-static is required for `output: "export"` builds (see next.config.ts).
export const dynamic = "force-static";

// No `language` option: the default `multilingual` tokenizer handles
// en/pt-BR/es/zh-CN out of the box (the per-locale `language`/`localeMap`
// option is deprecated as of the installed fumadocs-core version).
export const { staticGET: GET } = createFromSource(source);
