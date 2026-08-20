import { browser } from 'wxt/browser';

import { DICTIONARIES, type RawMessage } from './dictionaries';

export interface Language {
  code: string;
  label: string;
}

// Nomes dos idiomas nunca são traduzidos — cada um aparece sempre no
// próprio idioma, mesma convenção do seletor do Desktop/Mobile.
export const LANGUAGES: Language[] = [
  { code: 'en', label: 'English' },
  { code: 'pt-BR', label: 'Português (Brasil)' },
  { code: 'es', label: 'Español' },
  { code: 'zh-CN', label: '中文' },
];

export const DEFAULT_LANGUAGE_CODE = 'en';

function isSupported(code: string): boolean {
  return code in DICTIONARIES;
}

// Mapeia o idioma do navegador (`browser.i18n.getUILanguage()`, ex.
// "pt-BR", "es-MX", "fr") pro código suportado mais próximo — é o que
// resolve o idioma de quem nunca abriu o seletor manual, preservando o
// comportamento de auto-detecção de antes deste seletor existir (quando
// isso era feito pelo `chrome.i18n` nativo).
export function detectDefaultLanguage(): string {
  const uiLanguage = browser.i18n.getUILanguage();
  if (isSupported(uiLanguage)) return uiLanguage;
  const base = uiLanguage.split('-')[0].toLowerCase();
  const byBase = LANGUAGES.find((lang) => lang.code.split('-')[0].toLowerCase() === base);
  return byBase?.code ?? DEFAULT_LANGUAGE_CODE;
}

let activeCode = DEFAULT_LANGUAGE_CODE;
let activeDictionary: Record<string, RawMessage> = DICTIONARIES[DEFAULT_LANGUAGE_CODE];

export function getCurrentLanguageCode(): string {
  return activeCode;
}

// Síncrono de propósito — os dicionários já estão bundlados (ver
// `dictionaries.ts`), então trocar de idioma nunca depende de rede.
export function setLanguage(code: string): void {
  activeCode = isSupported(code) ? code : DEFAULT_LANGUAGE_CODE;
  activeDictionary = DICTIONARIES[activeCode];
}

// Replica o algoritmo de substituição do `chrome.i18n.getMessage`: troca
// cada `$NOME$` do texto pelo valor de `placeholders.nome.content`
// (tipicamente `$1`/`$2`, resolvido contra `substitutions`).
function applySubstitutions(
  message: string,
  placeholders: Record<string, { content: string }> | undefined,
  substitutions: string | string[] | undefined,
): string {
  if (!placeholders) return message;
  const subs = Array.isArray(substitutions)
    ? substitutions
    : substitutions !== undefined
      ? [substitutions]
      : [];
  let result = message;
  for (const [name, def] of Object.entries(placeholders)) {
    const positional = /^\$(\d+)$/.exec(def.content);
    const value = positional ? (subs[Number(positional[1]) - 1] ?? '') : def.content;
    result = result.split(`$${name.toUpperCase()}$`).join(value);
  }
  return result;
}

// Substitui `browser.i18n.getMessage` em todo o popup — lê do dicionário
// ativo (`activeDictionary`), trocado por `setLanguage()`. Mesma
// assinatura do `chrome.i18n.getMessage` de propósito, pra minimizar o
// diff nos call sites existentes.
export function t(key: string, substitutions?: string | string[]): string {
  const entry = activeDictionary[key];
  if (!entry) return '';
  return applySubstitutions(entry.message, entry.placeholders, substitutions);
}
