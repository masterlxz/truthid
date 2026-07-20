import { deriveDeadDropKey } from './deadDropIpnsKey';
import { loadPinningProviderConfig } from './pinningProviderConfig';

const DEFAULT_TIMEOUT_MS = 15_000;

function trimSlash(url: string): string {
  return url.endsWith('/') ? url.slice(0, -1) : url;
}

async function postMultipart(
  url: string,
  fieldName: string,
  filename: string,
  body: Uint8Array,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const form = new FormData();
    form.set(fieldName, new Blob([body as unknown as BlobPart]), filename);
    return await fetch(url, { method: 'POST', body: form, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

// POST `{endpoint}/api/v0/add` — mirror de `IpfsPinClient._kuboAdd`. Devolve
// o CID (campo `Hash` da resposta JSON do Kubo).
async function kuboAdd(endpointUrl: string, content: Uint8Array): Promise<string> {
  const response = await postMultipart(
    `${trimSlash(endpointUrl)}/api/v0/add`,
    'file',
    'vault-edit.enc',
    content,
    DEFAULT_TIMEOUT_MS,
  );
  if (!response.ok) {
    throw new Error(`kubo add retornou ${response.status}`);
  }
  const text = await response.text();
  const lines = text.split('\n').map((l) => l.trim()).filter((l) => l.length > 0);
  if (lines.length === 0) {
    throw new Error('resposta vazia do kubo');
  }
  const json = JSON.parse(lines[lines.length - 1]) as { Hash?: string };
  if (!json.Hash) {
    throw new Error(`campo Hash ausente: ${lines[lines.length - 1]}`);
  }
  return json.Hash;
}

// POST `{endpoint}/api/v0/key/import` — mirror de `IpfsPinClient.kuboImportKey`.
// Chave determinística (mesmo sessionId → mesmos bytes): trata "already
// exists" como sucesso, não como erro (ex: retry depois de um publish que
// falhou antes do key/rm rodar).
async function kuboImportKey(
  endpointUrl: string,
  keyName: string,
  privateKeyProtobuf: Uint8Array,
): Promise<void> {
  const url =
    `${trimSlash(endpointUrl)}/api/v0/key/import` +
    `?arg=${encodeURIComponent(keyName)}&format=libp2p-protobuf-cleartext`;
  const response = await postMultipart(url, 'file', 'key.bin', privateKeyProtobuf, DEFAULT_TIMEOUT_MS);
  if (!response.ok) {
    const text = await response.text();
    if (!text.includes('already exists')) {
      throw new Error(`kubo key/import retornou ${response.status}: ${text}`);
    }
  }
}

// POST `{endpoint}/api/v0/name/publish` — mirror de `IpfsPinClient.kuboPublishName`.
// `lifetime=5m` cobre o TTL de sessão (3min) com margem pra propagação de IPNS.
async function kuboPublishName(endpointUrl: string, keyName: string, cid: string): Promise<void> {
  const url =
    `${trimSlash(endpointUrl)}/api/v0/name/publish` +
    `?arg=${encodeURIComponent(`/ipfs/${cid}`)}&key=${encodeURIComponent(keyName)}` +
    `&lifetime=5m&ipns-base=base36`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const response = await fetch(url, { method: 'POST', signal: controller.signal });
    if (!response.ok) {
      const text = await response.text();
      throw new Error(`kubo name/publish retornou ${response.status}: ${text}`);
    }
  } finally {
    clearTimeout(timer);
  }
}

// POST `{endpoint}/api/v0/key/rm` — mirror de `IpfsPinClient.kuboRemoveKey`,
// limpeza best-effort depois do publish (chamada de dentro de um `finally`
// pelo call site, falha aqui não invalida o publish que já aconteceu).
async function kuboRemoveKey(endpointUrl: string, keyName: string): Promise<void> {
  const url = `${trimSlash(endpointUrl)}/api/v0/key/rm?arg=${encodeURIComponent(keyName)}&ipns-base=base36`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), DEFAULT_TIMEOUT_MS);
  try {
    const response = await fetch(url, { method: 'POST', signal: controller.signal });
    if (!response.ok) {
      throw new Error(`kubo key/rm retornou ${response.status}`);
    }
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Publica `content` (já cifrado) num nome IPNS derivado deterministicamente
 * de `sessionId` — dead-drop cross-network do vault-edit (item 6 do
 * backlog, mirror de `IpfsPinClient.publishDeadDrop`). Best-effort: devolve
 * `null` sem lançar se não houver provider Kubo configurado
 * (`pinningProviderConfig.ts`) ou se qualquer passo falhar — uma falha
 * aqui não pode derrubar a varredura LAN que roda em paralelo
 * (`mobileDelivery.ts::startMobileDelivery`).
 */
export async function publishDeadDrop(
  sessionIdHex: string,
  content: Uint8Array,
): Promise<string | null> {
  const config = await loadPinningProviderConfig();
  if (!config?.kuboEndpointUrl) return null;

  try {
    const key = deriveDeadDropKey(sessionIdHex);
    const keyName = `truthid-vault-edit-dead-drop-${sessionIdHex}`;

    const cid = await kuboAdd(config.kuboEndpointUrl, content);
    await kuboImportKey(config.kuboEndpointUrl, keyName, key.privateKeyProtobuf);
    try {
      await kuboPublishName(config.kuboEndpointUrl, keyName, cid);
    } finally {
      try {
        await kuboRemoveKey(config.kuboEndpointUrl, keyName);
      } catch {
        // best-effort, ver comentário acima de kuboRemoveKey
      }
    }

    return key.ipnsName;
  } catch {
    return null;
  }
}
