/**
 * Codifica sessionId + expiresAt no próprio nome do alarme do
 * `chrome.alarms` usado pelo polling de dead-drop do autofill (Fase 15.4,
 * fatia 2 — endereço e cartão). Diferente do polling de vault-session
 * (`DEAD_DROP_POLL_ALARM` em `background.ts`), que guarda 1 sessão só em
 * `chrome.storage.session`, o autofill pode ter várias sessões pendentes ao
 * mesmo tempo (endereço e cartão no mesmo checkout, várias abas) — em vez de
 * um storage novo só pra rastrear isso, o nome do alarme já carrega o que
 * `background.ts` precisa pra cada tick, e `chrome.alarms` sobrevive ao
 * service worker sendo suspenso/reiniciado entre ticks (uma `Map` em memória
 * não sobreviveria).
 */
const ALARM_PREFIX = 'truthid-autofill-dead-drop-poll:';

export function encodeAlarmName(sessionId: string, expiresAtMs: number): string {
  return `${ALARM_PREFIX}${sessionId}:${expiresAtMs}`;
}

export interface DecodedAutofillDeadDropAlarm {
  sessionId: string;
  expiresAtMs: number;
}

/**
 * `null` pra qualquer nome que não seja um alarme de dead-drop do autofill
 * (`background.ts` usa isso pra decidir se o alarme é seu antes de agir) ou
 * que esteja malformado (defensivo — nunca deveria acontecer, já que só
 * `encodeAlarmName` gera esses nomes).
 */
export function decodeAlarmName(name: string): DecodedAutofillDeadDropAlarm | null {
  if (!name.startsWith(ALARM_PREFIX)) return null;
  const rest = name.slice(ALARM_PREFIX.length);
  const separatorIndex = rest.lastIndexOf(':');
  if (separatorIndex === -1) return null;

  const sessionId = rest.slice(0, separatorIndex);
  const expiresAtMs = Number(rest.slice(separatorIndex + 1));
  if (!sessionId || !Number.isFinite(expiresAtMs)) return null;

  return { sessionId, expiresAtMs };
}
