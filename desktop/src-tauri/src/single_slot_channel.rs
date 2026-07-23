use std::time::{SystemTime, UNIX_EPOCH};

use rand::RngCore;
use tokio::sync::{oneshot, Mutex};

/// Slot interno — guarda o payload pendente + o canal de resposta.
struct Slot<P, D> {
    payload: P,
    responder: oneshot::Sender<D>,
}

/// Máquina de estados genérica de "single pending request".
///
/// Cada canal do local signer server precisa de: um `Mutex<Option<PendingX>>`
/// pra segurar no máximo 1 pedido por vez, um `oneshot` pro frontend
/// responder, e funções `current`/`resolve`/`clear` + helpers `random_id`/
/// `now_ms`. Antes este padrão era copiado manualmente nos 4 canais
/// (sign_request, sign_message, pin, vault_edit), ~150 linhas cada.
///
/// `P` = Payload (o que o frontend vê, Serialize + Clone).
/// `D` = Decision (o que o frontend responde, Deserialize).
pub struct SingleSlotChannel<P, D>(Mutex<Option<Slot<P, D>>>);

impl<P, D> Default for SingleSlotChannel<P, D> {
    fn default() -> Self {
        Self(Mutex::new(None))
    }
}

impl<P, D> SingleSlotChannel<P, D>
where
    P: Clone,
{
    /// Tenta parquear um novo payload. Se já houver um pendente, retorna
    /// `Err(())` (o chamador mapeia pra "Busy"). Se ok, devolve o payload
    /// (clone) + o receiver do oneshot — o chamador usa `tokio::time::timeout`
    /// pra esperar a decisão.
    pub async fn try_park(
        &self,
        payload: P,
    ) -> Result<(P, oneshot::Receiver<D>), ()> {
        let mut guard = self.0.lock().await;
        if guard.is_some() {
            return Err(());
        }
        let (tx, rx) = oneshot::channel();
        *guard = Some(Slot {
            payload: payload.clone(),
            responder: tx,
        });
        Ok((payload, rx))
    }

    /// Retorna o payload do pedido pendente, se houver.
    pub async fn current(&self) -> Option<P> {
        self.0
            .lock()
            .await
            .as_ref()
            .map(|s| s.payload.clone())
    }

    /// Limpa o slot (usado no timeout, quando o tokio::time::timeout estoura).
    pub async fn clear(&self) {
        self.0.lock().await.take();
    }
}

impl<P, D> SingleSlotChannel<P, D>
where
    P: Clone + PayloadId,
{
    /// Resolve o pedido pendente com uma decisão. Confere que o `id` bate
    /// antes de consumir, pra não resolver o pedido errado numa race rara
    /// (ex: um pedido expirou e outro já parqueou no lugar dele).
    pub async fn resolve(&self, id: &str, decision: D) -> Result<(), String> {
        let mut guard = self.0.lock().await;
        match guard.take() {
            Some(slot) if slot.payload_id_matches(id) => {
                let _ = slot.responder.send(decision);
                Ok(())
            }
            Some(slot) => {
                *guard = Some(slot);
                Err("id does not match the currently pending request".to_string())
            }
            None => Err("no pending request (it may have already expired)".to_string()),
        }
    }

    /// Retorna `true` se existe um pedido pendente com o `id` informado.
    pub async fn is_valid(&self, id: &str) -> bool {
        self.0
            .lock()
            .await
            .as_ref()
            .map_or(false, |s| s.payload_id_matches(id))
    }
}

// O trait precisa de acesso ao `id` do payload. Como não podemos exigir
// `HasId` de todos os tipos P, implementamos o matching por reflection
// via uma helper trait interna.
pub(crate) trait PayloadId {
    fn payload_id(&self) -> &str;
}

impl<P: PayloadId, D> Slot<P, D> {
    fn payload_id_matches(&self, id: &str) -> bool {
        self.payload.payload_id() == id
    }
}

// Implementação concreta: extrai o campo `id` de cada payload.
// Cada tipo de payload precisa implementar PayloadId.
// As implementações ficam nos respectivos módulos.

macro_rules! impl_payload_id {
    ($ty:ty) => {
        impl $crate::single_slot_channel::PayloadId for $ty {
            fn payload_id(&self) -> &str {
                &self.id
            }
        }
    };
}

pub(crate) use impl_payload_id;

/// Gera um id aleatório de 16 bytes hex. Usado por todos os canais.
pub fn random_id() -> String {
    let mut bytes = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Timestamp atual em ms desde UNIX_EPOCH. Usado por todos os canais.
pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}