import createMiddleware from "next-intl/middleware";
import { routing } from "@/i18n/routing";

export default createMiddleware(routing);

export const config = {
  // /docs is served by its own unprefixed root (app/docs/) for English and by
  // app/[locale]/docs/ for the other 3 locales — neither depends on this proxy
  // for locale resolution (the docs-only static export can't run a proxy at
  // all), so it's excluded here to avoid the proxy rewriting docs URLs.
  matcher: ["/((?!api|docs|_next|_vercel|favicon.ico|icon.svg|.*\\..*).*)"],
};
