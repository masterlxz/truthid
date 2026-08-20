// Bundlados via import estático (não `fetch` em runtime) — trocar de
// idioma fica sempre síncrono e instantâneo, sem flash de texto errado
// enquanto um arquivo carrega. Mesmos `_locales/<pasta>/messages.json`
// que o manifest já usa pro nome/descrição da extensão na loja via
// `chrome.i18n` nativo (esse continua intacto, fora do nosso controle).
import en from '../../public/_locales/en/messages.json';
import es from '../../public/_locales/es/messages.json';
import pt from '../../public/_locales/pt/messages.json';
import zhCN from '../../public/_locales/zh_CN/messages.json';

export interface RawMessage {
  message: string;
  placeholders?: Record<string, { content: string }>;
}

type Dictionary = Record<string, RawMessage>;

// Chaveado pelo código exposto ao usuário (en/pt-BR/es/zh-CN, mesma
// convenção do seletor no Desktop/Mobile) — não bate 1:1 com o nome da
// pasta em `_locales` (`pt`, não `pt-BR`; `zh_CN`, não `zh-CN`).
export const DICTIONARIES: Record<string, Dictionary> = {
  en: en as Dictionary,
  'pt-BR': pt as Dictionary,
  es: es as Dictionary,
  'zh-CN': zhCN as Dictionary,
};
