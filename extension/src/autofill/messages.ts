// Só constantes de mensagem — sem código de DOM — pra background.ts poder
// importar sem puxar junto a lógica de UI de overlay.ts (que só faz
// sentido no contexto de content script).
export const GET_MATCHING_ENTRIES_MESSAGE = 'truthid-get-matching-entries';
