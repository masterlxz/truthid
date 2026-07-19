import { base64UrlDecode, createPasskey } from '../src/webauthn';

// Canal de enfileiramento de propostas (Sessão 134, item 6 do roadmap) —
// separado do canal de login (CHANNEL abaixo) de propósito: é fire-and-
// forget (a página não espera resposta, só o resultado normal do
// create()), então não precisa do protocolo request/response com
// requestId/timeout que o login exige.
const VAULT_EDIT_CHANNEL = '__truthid_vault_edit__';

// Intercepta `navigator.credentials.get()` de verdade na página (Sessão
// 132) — precisa rodar no main-world (o mesmo contexto JS da página, não o
// isolated world padrão de content script) porque só assim consegue
// sobrescrever o método antes de qualquer script da própria página chamá-lo.
// Primeiro uso de `world: 'MAIN'` no projeto. Não tem acesso a `chrome.*`
// aqui (restrição do main-world) — tudo que precisa de uma API de extensão
// passa por `window.postMessage` até `webauthn-bridge.content.ts` (isolated
// world, mesma aba), que fala com o background pelos canais normais.
const CHANNEL = '__truthid_webauthn__';
// Tempo suficiente pro usuário ver o prompt de confirmação e clicar — não
// trava pra sempre se o bridge nunca responder (ex: service worker morto).
const RESPONSE_TIMEOUT_MS = 20000;

interface BridgeResponse {
  channel: typeof CHANNEL;
  direction: 'response';
  requestId: string;
  result: 'signed' | 'no-match' | 'declined' | 'error' | 'timeout';
  credentialIdB64?: string;
  userHandleB64?: string;
  authenticatorData?: Uint8Array;
  clientDataJSON?: string;
  signatureDer?: Uint8Array;
}

function toUint8Array(source: BufferSource): Uint8Array {
  return source instanceof ArrayBuffer
    ? new Uint8Array(source)
    : new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
}

function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
}

function askBridge(rpId: string, challenge: Uint8Array): Promise<BridgeResponse> {
  const requestId = crypto.randomUUID();

  return new Promise((resolve) => {
    const timeout = setTimeout(() => {
      window.removeEventListener('message', onMessage);
      resolve({ channel: CHANNEL, direction: 'response', requestId, result: 'timeout' });
    }, RESPONSE_TIMEOUT_MS);

    function onMessage(event: MessageEvent): void {
      // Só a própria página (webauthn-bridge.content.ts, mesmo frame) fala
      // nesse canal — nunca confia em mensagem vinda de iframe/outra origem.
      if (event.source !== window) return;
      const data = event.data as Partial<BridgeResponse> | undefined;
      if (data?.channel !== CHANNEL || data.direction !== 'response' || data.requestId !== requestId) return;
      clearTimeout(timeout);
      window.removeEventListener('message', onMessage);
      resolve(data as BridgeResponse);
    }
    window.addEventListener('message', onMessage);

    window.postMessage(
      { channel: CHANNEL, direction: 'request', requestId, rpId, origin: location.origin, challenge },
      location.origin,
    );
  });
}

export default defineContentScript({
  matches: ['http://*/*', 'https://*/*'],
  world: 'MAIN',
  runAt: 'document_start',
  main() {
    const originalGet = navigator.credentials.get.bind(navigator.credentials);
    const originalCreate = navigator.credentials.create.bind(navigator.credentials);

    navigator.credentials.create = (async (options?: CredentialCreationOptions) => {
      const publicKey = options?.publicKey;
      if (!publicKey) return originalCreate(options);

      // Gera a passkey localmente — não precisa de aprovação do Device pra
      // *gerar* (só pra *persistir*), então nenhum round-trip pro bridge
      // aqui: o site nunca fica esperando o usuário aprovar em outro
      // dispositivo só pra terminar o próprio fluxo de cadastro.
      const rpId = publicKey.rp?.id ?? location.hostname;
      const challenge = toUint8Array(publicKey.challenge as BufferSource);
      const passkey = createPasskey({ rpId, challenge, origin: location.origin });

      // Fire-and-forget pro bridge — a proposta fica pendente até o
      // usuário mandar pra aprovação (popup da extensão), sem bloquear o
      // resultado que a página está esperando.
      window.postMessage(
        {
          channel: VAULT_EDIT_CHANNEL,
          site: rpId,
          url: location.origin,
          username: publicKey.user?.name ?? '',
          password: '',
          notes: '',
          passkey: {
            rp_id: rpId,
            credential_id_b64: passkey.credentialIdB64,
            user_handle_b64: passkey.userHandleB64,
            private_key_hex: passkey.privateKeyHex,
            sign_count: passkey.signCount,
            created_at: passkey.createdAt,
          },
        },
        location.origin,
      );

      return {
        id: passkey.credentialIdB64,
        type: 'public-key',
        rawId: toArrayBuffer(base64UrlDecode(passkey.credentialIdB64)),
        response: {
          clientDataJSON: toArrayBuffer(new TextEncoder().encode(passkey.clientDataJSON)),
          attestationObject: toArrayBuffer(passkey.attestationObject),
        },
        getClientExtensionResults: () => ({}),
      };
    }) as typeof navigator.credentials.create;

    navigator.credentials.get = (async (options?: CredentialRequestOptions) => {
      const publicKey = options?.publicKey;
      if (!publicKey) return originalGet(options);

      const rpId = publicKey.rpId ?? location.hostname;
      const challenge = toUint8Array(publicKey.challenge as BufferSource);
      const response = await askBridge(rpId, challenge);

      if (
        response.result !== 'signed' ||
        !response.credentialIdB64 ||
        !response.userHandleB64 ||
        !response.authenticatorData ||
        !response.clientDataJSON ||
        !response.signatureDer
      ) {
        // Sem passkey TruthID pro site, usuário cancelou, erro, ou timeout
        // — cai pro `get` nativo do navegador. Nunca quebra sites que usam
        // passkeys de verdade/chaves de segurança físicas.
        return originalGet(options);
      }

      // Objeto no formato de PublicKeyCredential/AuthenticatorAssertionResponse
      // — best-effort, não é uma instância nativa de verdade (não passa em
      // `instanceof PublicKeyCredential`), mas expõe os mesmos campos que a
      // maioria das bibliotecas cliente de WebAuthn lê diretamente.
      return {
        id: response.credentialIdB64,
        type: 'public-key',
        rawId: toArrayBuffer(base64UrlDecode(response.credentialIdB64)),
        response: {
          authenticatorData: toArrayBuffer(response.authenticatorData),
          clientDataJSON: toArrayBuffer(new TextEncoder().encode(response.clientDataJSON)),
          signature: toArrayBuffer(response.signatureDer),
          userHandle: toArrayBuffer(base64UrlDecode(response.userHandleB64)),
        },
        getClientExtensionResults: () => ({}),
      };
    }) as typeof navigator.credentials.get;
  },
});
