import { defineConfig } from 'wxt';

// TruthID Vault — extensão de navegador (13.9, fatia 1: só transporte LAN).
//
// `system.network` só existe em Chrome/Edge (Firefox não implementa essa
// API) — por isso não entra no manifest base, e sim condicionalmente via
// hook, só pra esses browsers. Firefox sempre cai no fallback manual de IP
// (campo de texto na popup), que funciona em qualquer browser.
//
// `http://*/*` é pedido em runtime (optional_host_permissions +
// chrome.permissions.request()), não declarado como host_permissions fixo —
// evita o aviso amplo de instalação ("ler e alterar todos os seus dados em
// todos os sites") para algo que só é usado sob demanda, quando o usuário
// clica em "procurar meu celular".
export default defineConfig({
  srcDir: '.',
  // MV3 explícito também no Firefox (WXT usa MV2 por padrão lá) — no MV2 o
  // `optional_host_permissions` não é gerado no manifest, o que quebraria
  // tanto a descoberta automática quanto o fallback manual de IP (os dois
  // dependem de `fetch()` para um IP de LAN, que precisa da permissão de
  // host concedida em runtime). Firefox 109+ já suporta MV3.
  manifestVersion: 3,
  manifest: {
    name: 'TruthID Vault',
    description:
      'Recebe um subconjunto do seu vault de senhas do app TruthID Mobile via LAN.',
    permissions: ['storage', 'alarms'],
    optional_host_permissions: ['http://*/*'],
  },
  hooks: {
    'build:manifestGenerated': (wxt, manifest) => {
      const browser = wxt.config.browser;
      if (browser === 'chrome' || browser === 'edge') {
        manifest.permissions ??= [];
        // "system.network" é uma permissão real (Chrome/Edge), mas ausente
        // do union type `ManifestPermission` do WXT.
        manifest.permissions.push('system.network' as never);
      }
    },
  },
});
