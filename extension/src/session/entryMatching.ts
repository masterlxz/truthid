import type { VaultEntry } from './sessionState';

/**
 * `entry.site` costuma ser só o domínio (ex: "github.com"), mas às vezes é
 * digitado com protocolo/path por engano — tenta como URL primeiro (mesmo
 * parser usado pra `entry.url`) e cai pro texto cru se não for uma URL
 * válida.
 */
function extractHostname(value: string): string | null {
  if (!value) return null;
  try {
    return new URL(value).hostname.toLowerCase();
  } catch {
    return value.toLowerCase();
  }
}

/**
 * Uma entrada "bate" com o hostname da página atual se o hostname de
 * `entry.url` (preferencial, mais confiável) ou de `entry.site` (fallback)
 * for igual, ou se um for subdomínio do outro (ex: entrada para
 * "example.com" bate em "www.example.com" e vice-versa) — cobre o caso
 * comum de o usuário ter cadastrado só o domínio-base.
 */
export function matchesOrigin(entry: Pick<VaultEntry, 'site' | 'url'>, hostname: string): boolean {
  const target = hostname.toLowerCase();
  const candidates = [extractHostname(entry.url), extractHostname(entry.site)].filter(
    (h): h is string => h !== null && h.length > 0,
  );

  return candidates.some(
    (candidate) =>
      candidate === target ||
      target.endsWith(`.${candidate}`) ||
      candidate.endsWith(`.${target}`),
  );
}

/**
 * Mesma tolerância a subdomínio de `matchesOrigin`, mas pra `passkey.rp_id`
 * (Sessão 132) — um `rp_id` é sempre só um hostname (nunca uma URL com
 * protocolo/path), então reaproveita `matchesOrigin` passando o mesmo valor
 * como `site` e `url` vazia, sem duplicar a lógica de comparação.
 */
export function matchesRpId(rpId: string, hostname: string): boolean {
  return matchesOrigin({ site: rpId, url: '' }, hostname);
}
