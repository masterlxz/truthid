use trezor_client::client::{Signature, Trezor};
use trezor_client::protos::failure::FailureType;
use trezor_client::{find_devices, Error as TrezorError, Model};

/// Caminho de derivação `m/44'/60'/account_index'/0/0` — mesma conta usada pela
/// Ledger (`ledger.rs::encode_derivation_path`), mas aqui já é um `Vec<u32>` direto
/// (o campo protobuf `address_n` que a `trezor-client` espera), sem precisar
/// serializar como bytes de APDU.
fn derivation_path(account_index: u32) -> Vec<u32> {
    const HARDENED: u32 = 0x8000_0000;
    vec![44 | HARDENED, 60 | HARDENED, account_index | HARDENED, 0, 0]
}

/// Abre o primeiro dispositivo Trezor encontrado (ignora um device preso em modo
/// bootloader, que não conversa a interface Ethereum). Diferente da Ledger (vendor
/// ID único), a Trezor tem vários pares vendor:product dependendo do modelo/estado
/// — `find_devices` já sabe disso internamente, não hardcodamos IDs aqui.
fn open_trezor_device() -> Result<Trezor, String> {
    let device = find_devices(false)
        .into_iter()
        .find(|d| d.model != Model::TrezorBootloader)
        .ok_or_else(|| "not_connected".to_string())?;

    let mut trezor = device.connect().map_err(|e| classify_error(&e))?;
    trezor.init_device(None).map_err(|e| classify_error(&e))?;
    Ok(trezor)
}

/// Equivalente ao `classify_error` de `ledger.rs`, mas sobre o enum tipado
/// `trezor_client::Error` em vez de status words APDU — o protocolo da Trezor não
/// tem status words, usa mensagens `Failure` com um `FailureType`. `"wrong_app"`
/// não existe aqui (a Trezor não tem um "app Ethereum" separado pra abrir, um único
/// firmware cobre todas as moedas); em troca ganhamos `"not_initialized"` (device
/// novo/resetado, sem seed configurada ainda).
fn classify_error(e: &TrezorError) -> String {
    match e {
        TrezorError::NoDeviceFound | TrezorError::DeviceNotUnique => "not_connected".to_string(),
        // `UnsupportedNetwork` é reaproveitado pelo `handle_interaction()` interno
        // da própria crate pra sinalizar um `PinMatrixRequest` (PIN via matriz
        // renderizada no host) — não implementado por esta versão da crate. Na
        // prática só afeta o Trezor One legado; os modelos com PIN direto na tela
        // (Model T, Safe 3/5) não emitem esse request.
        TrezorError::UnsupportedNetwork => "locked".to_string(),
        TrezorError::FailureResponse(f) => match f.code() {
            FailureType::Failure_ActionCancelled => "rejected_by_user".to_string(),
            FailureType::Failure_PinInvalid
            | FailureType::Failure_PinExpected
            | FailureType::Failure_PinCancelled => "locked".to_string(),
            FailureType::Failure_NotInitialized => "not_initialized".to_string(),
            other => format!("failure {other:?}: {}", f.message()),
        },
        TrezorError::TransportConnect(inner) => {
            let msg = inner.to_string().to_lowercase();
            if msg.contains("access") || msg.contains("permission") || msg.contains("denied") {
                "access_denied".to_string()
            } else {
                "not_connected".to_string()
            }
        }
        other => other.to_string(),
    }
}

/// Verifica se há uma Trezor plugada via USB, sem abrir o dispositivo.
#[tauri::command]
pub fn is_trezor_connected() -> Result<bool, String> {
    Ok(find_devices(false)
        .into_iter()
        .any(|d| d.model != Model::TrezorBootloader))
}

/// Pede o endereço Ethereum (conta `account_index`) pra Trezor conectada. Erro vem
/// como uma destas strings: "not_connected", "access_denied", "locked",
/// "not_initialized", "rejected_by_user", ou uma mensagem genérica.
#[tauri::command]
pub fn get_trezor_address(account_index: u32) -> Result<String, String> {
    let mut trezor = open_trezor_device()?;
    trezor
        .ethereum_get_address(derivation_path(account_index))
        .map_err(|e| classify_error(&e))
}

fn hex_bytes(s: &str) -> Result<Vec<u8>, String> {
    hex::decode(s.trim_start_matches("0x")).map_err(|e| e.to_string())
}

/// Campos numéricos do protobuf Ethereum da Trezor (nonce, gas, value) esperam
/// big-endian sem byte zero à esquerda — mesma codificação mínima que RLP usa.
/// Diferente de `data` (calldata), que não passa por aqui — é decodificado com
/// `hex_bytes` puro, sem remover zeros.
fn minimal_be_bytes(hex_str: &str) -> Result<Vec<u8>, String> {
    let bytes = hex_bytes(hex_str)?;
    Ok(bytes.into_iter().skip_while(|&b| b == 0).collect())
}

fn minimal_be_u64(n: u64) -> Vec<u8> {
    n.to_be_bytes().into_iter().skip_while(|&b| b == 0).collect()
}

/// `ethereum_sign_eip1559_tx` da `trezor-client` aplica a fórmula EIP-155 legada
/// (`v = yParity + 2*chain_id + 35`) mesmo numa transação tipo 2, que na verdade só
/// precisa de `yParity` (0/1). Como sempre passamos `chain_id`, dá pra reverter
/// deterministicamente e reformatar no mesmo formato `"0x" + r + s + v(27/28)"` que
/// `sign_ledger_transaction` já usa — nada rio abaixo (TS/`derive_vault_key_from_wallet`)
/// precisa saber que isso aconteceu.
fn format_tx_signature(sig: Signature, chain_id: u64) -> Result<String, String> {
    let offset = 35 + 2 * chain_id;
    let y_parity = sig
        .v
        .checked_sub(offset)
        .filter(|&v| v <= 1)
        .ok_or_else(|| format!("unexpected v from Trezor: {}", sig.v))? as u8;
    Ok(format!(
        "0x{}{}{:02x}",
        hex::encode(sig.r),
        hex::encode(sig.s),
        27 + y_parity
    ))
}

/// `ethereum_sign_message` (personal_sign) não tem o quirk EIP-155 acima — o `v`
/// que a Trezor devolve já vem cru (0/1), só precisa normalizar pra convenção 27/28.
fn format_message_signature(sig: Signature) -> String {
    let mut v = sig.v as u8;
    if v < 27 {
        v += 27;
    }
    format!("0x{}{}{:02x}", hex::encode(sig.r), hex::encode(sig.s), v)
}

/// Assina uma transação EIP-1559 (type 2) com a chave da Trezor (mesma
/// conta/caminho do `get_trezor_address`). Diferente da Ledger (que recebe RLP já
/// serializado e não decodifica nada), a Trezor exige os campos decompostos — o
/// lado TypeScript já tem esses campos em mãos (o objeto `TransactionSerializable`
/// da viem, antes de `serializeTransaction`), então não precisamos decodificar RLP
/// aqui. Escopo v1: só EIP-1559 (único tipo usado nesta app, chain configurada é
/// Base), sem access list.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub fn sign_trezor_transaction(
    account_index: u32,
    chain_id: u64,
    nonce: u64,
    to: String,
    value_hex: String,
    data_hex: String,
    gas_limit_hex: String,
    max_fee_per_gas_hex: String,
    max_priority_fee_per_gas_hex: String,
) -> Result<String, String> {
    let mut trezor = open_trezor_device()?;

    let signature = trezor
        .ethereum_sign_eip1559_tx(
            derivation_path(account_index),
            minimal_be_u64(nonce),
            minimal_be_bytes(&gas_limit_hex)?,
            to,
            minimal_be_bytes(&value_hex)?,
            hex_bytes(&data_hex)?,
            Some(chain_id),
            minimal_be_bytes(&max_fee_per_gas_hex)?,
            minimal_be_bytes(&max_priority_fee_per_gas_hex)?,
            vec![],
        )
        .map_err(|e| classify_error(&e))?;

    format_tx_signature(signature, chain_id)
}

/// Assina uma mensagem pessoal (EIP-191 `personal_sign`) com a chave da Trezor —
/// usado pelo consentimento de `createIdentity` (mesmo papel de
/// `sign_ledger_personal_message`).
#[tauri::command]
pub fn sign_trezor_personal_message(message_hex: String, account_index: u32) -> Result<String, String> {
    let message = hex_bytes(&message_hex)?;
    let mut trezor = open_trezor_device()?;
    let signature = trezor
        .ethereum_sign_message(message, derivation_path(account_index))
        .map_err(|e| classify_error(&e))?;
    Ok(format_message_signature(signature))
}

#[cfg(test)]
mod tests {
    use super::*;
    use trezor_client::protos::Failure;

    #[test]
    fn derivation_path_matches_bip44_ethereum() {
        assert_eq!(
            derivation_path(0),
            vec![0x8000_002c, 0x8000_003c, 0x8000_0000, 0, 0]
        );
        assert_eq!(derivation_path(3)[2], 0x8000_0003);
    }

    #[test]
    fn minimal_be_bytes_strips_leading_zeros() {
        assert_eq!(minimal_be_bytes("0x0000002a").unwrap(), vec![0x2a]);
        assert_eq!(minimal_be_bytes("0x00000000").unwrap(), Vec::<u8>::new());
        assert_eq!(minimal_be_bytes("2a").unwrap(), vec![0x2a]);
    }

    #[test]
    fn minimal_be_bytes_rejects_invalid_hex() {
        assert!(minimal_be_bytes("not_hex").is_err());
    }

    #[test]
    fn minimal_be_u64_strips_leading_zeros() {
        assert_eq!(minimal_be_u64(0), Vec::<u8>::new());
        assert_eq!(minimal_be_u64(42), vec![42]);
    }

    #[test]
    fn format_tx_signature_reverses_eip155_offset() {
        let chain_id = 8453u64; // Base
        let sig = Signature {
            r: [1u8; 32],
            s: [2u8; 32],
            v: 35 + 2 * chain_id + 1,
        };
        let out = format_tx_signature(sig, chain_id).unwrap();
        assert!(out.ends_with("1c")); // 27 + yParity(1) = 28 = 0x1c
        assert_eq!(out.len(), 2 + 64 + 64 + 2);
    }

    #[test]
    fn format_tx_signature_rejects_unexpected_v() {
        let sig = Signature {
            r: [0u8; 32],
            s: [0u8; 32],
            v: 999,
        };
        assert!(format_tx_signature(sig, 8453).is_err());
    }

    #[test]
    fn format_message_signature_normalizes_v() {
        let sig = Signature {
            r: [0u8; 32],
            s: [0u8; 32],
            v: 0,
        };
        assert!(format_message_signature(sig).ends_with("1b")); // 27

        let sig_already_normalized = Signature {
            r: [0u8; 32],
            s: [0u8; 32],
            v: 28,
        };
        assert!(format_message_signature(sig_already_normalized).ends_with("1c"));
    }

    #[test]
    fn classify_error_maps_action_cancelled_to_rejected_by_user() {
        let mut f = Failure::new();
        f.set_code(FailureType::Failure_ActionCancelled);
        assert_eq!(
            classify_error(&TrezorError::FailureResponse(f)),
            "rejected_by_user"
        );
    }

    #[test]
    fn classify_error_maps_pin_failures_to_locked() {
        for code in [
            FailureType::Failure_PinInvalid,
            FailureType::Failure_PinExpected,
            FailureType::Failure_PinCancelled,
        ] {
            let mut f = Failure::new();
            f.set_code(code);
            assert_eq!(classify_error(&TrezorError::FailureResponse(f)), "locked");
        }
    }

    #[test]
    fn classify_error_maps_not_initialized() {
        let mut f = Failure::new();
        f.set_code(FailureType::Failure_NotInitialized);
        assert_eq!(
            classify_error(&TrezorError::FailureResponse(f)),
            "not_initialized"
        );
    }

    #[test]
    fn classify_error_maps_unsupported_network_to_locked() {
        assert_eq!(classify_error(&TrezorError::UnsupportedNetwork), "locked");
    }

    #[test]
    fn classify_error_maps_no_device_to_not_connected() {
        assert_eq!(classify_error(&TrezorError::NoDeviceFound), "not_connected");
        assert_eq!(
            classify_error(&TrezorError::DeviceNotUnique),
            "not_connected"
        );
    }
}
