import { clearSession } from '../src/storage/sessionStore';

// Único job do service worker: garantir que a sessão some do
// `chrome.storage.session` quando o TTL expira, mesmo que a popup nunca
// tenha sido reaberta pra checar `expiresAt` sozinha (belt-and-suspenders —
// a popup também checa expiração toda vez que renderiza).
export const SESSION_EXPIRY_ALARM = 'truthid-vault-session-expiry';

export default defineBackground(() => {
  chrome.alarms.onAlarm.addListener((alarm) => {
    if (alarm.name !== SESSION_EXPIRY_ALARM) return;
    void clearSession();
  });
});
