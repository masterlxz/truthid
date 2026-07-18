import { defineConfig } from 'wxt';

// TruthID Vault — extensão de navegador.
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
      'Recebe um subconjunto do seu vault de senhas do app TruthID Mobile via LAN ou IPFS/IPNS.',
    permissions: ['storage', 'alarms'],
    optional_host_permissions: ['http://*/*'],
    icons: {
      16: 'icon/16.png',
      32: 'icon/32.png',
      48: 'icon/48.png',
      128: 'icon/128.png',
    },
    // O ícone do overlay de autofill (content script) é um <img> injetado
    // na página visitada — sem isso, o navegador bloqueia o carregamento
    // do recurso da extensão a partir do contexto da página.
    web_accessible_resources: [
      {
        resources: ['icon/32.png'],
        matches: ['http://*/*', 'https://*/*'],
      },
    ],
  },
  // Não declara mais `system.network` no manifest — achado real na Sessão
  // 126: versões atuais do Chromium (confirmado no Brave) rejeitam essa
  // permissão ("only allowed for packaged apps"), gerando um erro visível
  // no card da extensão. Já se sabia que o Brave zera `chrome.system.*`
  // por anti-fingerprinting mesmo com a permissão concedida (Sessão 115) —
  // agora nem a declaração é aceita. `isNetworkDiscoverySupported()` em
  // lanDiscovery.ts já detecta a ausência da API graciosamente (sem essa
  // permissão, `chrome.system.network` fica `undefined`) e mostra o
  // fallback manual de IP, que já cobre o caso em qualquer navegador.
});
