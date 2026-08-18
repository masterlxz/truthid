import type { BaseLayoutProps } from "fumadocs-ui/layouts/shared";
import { uiTranslations } from "fumadocs-ui/i18n";
import { zhCN } from "@fumadocs/language/zh-cn";
import { i18n } from "@/lib/i18n";
import { ptBRUiTranslations } from "@/lib/i18n/ui-translations.pt-BR";
import { esUiTranslations } from "@/lib/i18n/ui-translations.es";
import { Logo } from "@/components/logo";

export const translations = i18n
  .translations()
  .extend(uiTranslations())
  .preset("zh-CN", zhCN())
  .preset("pt-BR", ptBRUiTranslations())
  .preset("es", esUiTranslations());

export function baseOptions(locale: string): BaseLayoutProps {
  return {
    nav: {
      title: (
        <>
          <Logo className="size-5 text-fd-primary" />
          TruthID
        </>
      ),
      url: locale === "en" ? "/" : `/${locale}`,
    },
    githubUrl: "https://github.com/masterlxz/truthid",
  };
}
