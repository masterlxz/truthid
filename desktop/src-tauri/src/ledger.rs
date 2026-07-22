use hidapi::{HidApi, HidDevice};

/// Vendor ID USB atribuído à Ledger SAS pela USB-IF — o mesmo em todos os
/// modelos (Nano S, Nano S Plus, Nano X).
const LEDGER_VENDOR_ID: u16 = 0x2c97;

/// Verifica se há uma Ledger plugada via USB, sem abrir o dispositivo.
/// Só enumera o que o sistema operacional já vê — não conversa com o app
/// Ethereum ainda (isso é o protocolo APDU, etapa 10.2).
#[tauri::command]
pub fn is_ledger_connected() -> Result<bool, String> {
    let api = HidApi::new().map_err(|e| e.to_string())?;

    let found = api
        .device_list()
        .any(|device| device.vendor_id() == LEDGER_VENDOR_ID);

    Ok(found)
}

// --- Protocolo de transporte HID da Ledger ---
//
// Um relatório USB HID tem tamanho fixo (64 bytes de payload). Um APDU pode
// ser maior, então a Ledger fatia o APDU em vários pacotes de 64 bytes e
// remonta do outro lado. Formato de cada pacote: canal (2 bytes) | tag
// (1 byte) | sequência (2 bytes) | [só no 1º pacote: tamanho total dos dados,
// 2 bytes] | pedaço dos dados. Protocolo documentado publicamente (ex.:
// `@ledgerhq/hw-transport-node-hid`), não é específico deste projeto.

const HID_PACKET_SIZE: usize = 64;
const CHANNEL: u16 = 0x0101;
const TAG_APDU: u8 = 0x05;

/// Abre o primeiro dispositivo HID encontrado com o vendor_id da Ledger.
/// Distingue "não encontrada" (device não aparece na lista) de "não conseguiu
/// abrir" (device existe mas outro processo — ex. Ledger Live — está com acesso
/// exclusivo, mais comum no Windows).
fn open_ledger_device(api: &HidApi) -> Result<HidDevice, String> {
    let device_info = api
        .device_list()
        .find(|d| d.vendor_id() == LEDGER_VENDOR_ID)
        .ok_or_else(|| "not_connected".to_string())?;

    api.open_path(device_info.path()).map_err(|e| {
        let msg = e.to_string().to_lowercase();
        // No Windows, acesso exclusivo recusado quando outro app (ex. Ledger Live)
        // já tem o device aberto. No Linux pode indicar falta de regra udev.
        if msg.contains("access") || msg.contains("permission") || msg.contains("denied") {
            "access_denied".to_string()
        } else {
            e.to_string()
        }
    })
}

/// Envia um APDU completo (fatiado em pacotes HID) e devolve a resposta
/// crua (dados + 2 bytes de status word no final).
/// `timeout_ms`: quanto tempo esperar pela resposta da Ledger.
///   - Polling (get_ledger_address): 5_000 ms — curto, chamado a cada ~1s.
///   - Assinatura (sign_ledger_transaction): 120_000 ms — o usuário precisa
///     ler a transação na tela pequena da Ledger e pressionar os botões físicos.
fn send_apdu(device: &HidDevice, apdu: &[u8], timeout_ms: i32) -> Result<Vec<u8>, String> {
    write_apdu(device, apdu)?;
    read_apdu_response(device, timeout_ms)
}

fn write_apdu(device: &HidDevice, apdu: &[u8]) -> Result<(), String> {
    let mut sequence: u16 = 0;
    let mut offset = 0;

    while offset < apdu.len() || sequence == 0 {
        // +1 porque o hidapi exige um byte de "report ID" antes do payload
        // (a Ledger não usa relatórios numerados, então esse byte é sempre 0).
        let mut packet = vec![0u8; HID_PACKET_SIZE + 1];
        packet[1] = (CHANNEL >> 8) as u8;
        packet[2] = (CHANNEL & 0xff) as u8;
        packet[3] = TAG_APDU;
        packet[4] = (sequence >> 8) as u8;
        packet[5] = (sequence & 0xff) as u8;

        let header_len = if sequence == 0 {
            packet[6] = (apdu.len() >> 8) as u8;
            packet[7] = (apdu.len() & 0xff) as u8;
            8
        } else {
            6
        };

        let space = packet.len() - header_len;
        let chunk_len = space.min(apdu.len() - offset);
        packet[header_len..header_len + chunk_len]
            .copy_from_slice(&apdu[offset..offset + chunk_len]);

        device.write(&packet).map_err(|e| e.to_string())?;

        offset += chunk_len;
        sequence += 1;
    }

    Ok(())
}

fn read_apdu_response(device: &HidDevice, timeout_ms: i32) -> Result<Vec<u8>, String> {
    let mut sequence: u16 = 0;
    let mut expected_len: usize = 0;
    let mut data = Vec::new();

    loop {
        let mut buf = [0u8; HID_PACKET_SIZE];
        let read = device
            .read_timeout(&mut buf, timeout_ms)
            .map_err(|e| e.to_string())?;
        if read == 0 {
            return Err("Timeout waiting for Ledger response".to_string());
        }

        // bytes 0-1 canal, 2 tag, 3-4 sequência — não validados aqui ainda.
        let header_len = if sequence == 0 {
            expected_len = ((buf[5] as usize) << 8) | buf[6] as usize;
            7
        } else {
            5
        };

        let remaining = expected_len - data.len();
        let chunk_len = (HID_PACKET_SIZE - header_len).min(remaining);
        data.extend_from_slice(&buf[header_len..header_len + chunk_len]);

        sequence += 1;
        if data.len() >= expected_len {
            break;
        }
    }

    Ok(data)
}

/// Separa o status word (2 últimos bytes da resposta) dos dados. Em sucesso
/// (`0x9000`) devolve os dados; em erro devolve o status word crú, pra quem
/// chamar decidir o que ele significa (`classify_error`, abaixo).
fn check_status(response: Vec<u8>) -> Result<Vec<u8>, u16> {
    if response.len() < 2 {
        return Err(0); // resposta malformada — não deveria acontecer na prática
    }

    let (data, status) = response.split_at(response.len() - 2);
    let status_word = ((status[0] as u16) << 8) | status[1] as u16;

    if status_word == 0x9000 {
        Ok(data.to_vec())
    } else {
        Err(status_word)
    }
}

// --- Comando "pedir endereço" do app Ethereum da Ledger ---

const ETH_CLA: u8 = 0xe0;
const INS_GET_ADDRESS: u8 = 0x02;
const NO_DISPLAY_CONFIRMATION: u8 = 0x00; // P1: não pede confirmação na tela da Ledger (necessário pro polling)
const NO_CHAIN_CODE: u8 = 0x00; // P2: não inclui chain code na resposta, não precisamos dele

/// Codifica o caminho de derivação `m/44'/60'/account_index'/0/0` no formato
/// esperado pelas APDUs do app Ethereum: 1 byte de profundidade + 4 bytes
/// big-endian por componente. Os 3 primeiros componentes são "hardened".
fn encode_derivation_path(account_index: u32) -> Vec<u8> {
    let path = [0x8000_002c, 0x8000_003c, 0x8000_0000 | account_index, 0, 0];
    let mut data = vec![path.len() as u8];
    for component in path {
        data.extend_from_slice(&component.to_be_bytes());
    }
    data
}

fn build_get_address_apdu(account_index: u32) -> Vec<u8> {
    let data = encode_derivation_path(account_index);

    let mut apdu = vec![
        ETH_CLA,
        INS_GET_ADDRESS,
        NO_DISPLAY_CONFIRMATION,
        NO_CHAIN_CODE,
        data.len() as u8,
    ];
    apdu.extend_from_slice(&data);
    apdu
}

/// Resposta do GET_ADDRESS (sem chain code): 1 byte com o tamanho da chave
/// pública + a chave pública + 1 byte com o tamanho do endereço + o endereço
/// em ASCII (40 caracteres hex, sem "0x" — a Ledger não manda o prefixo).
fn parse_get_address_response(data: &[u8]) -> Result<String, String> {
    let pubkey_len = *data.first().ok_or("resposta vazia da Ledger")? as usize;
    let address_len_offset = 1 + pubkey_len;
    let address_len = *data
        .get(address_len_offset)
        .ok_or("resposta incompleta da Ledger")? as usize;
    let address_start = address_len_offset + 1;
    let address_bytes = data
        .get(address_start..address_start + address_len)
        .ok_or("resposta incompleta da Ledger")?;

    let address = String::from_utf8(address_bytes.to_vec()).map_err(|e| e.to_string())?;
    Ok(format!("0x{address}"))
}

/// Traduz um status word de erro num dos 3 estados que o frontend vai exibir
/// durante o polling. Valores documentados publicamente (transporte Ledger),
/// ainda não confirmados com hardware real desta máquina (etapa 10.8).
fn classify_error(status_word: u16) -> String {
    match status_word {
        0x5515 | 0x6982 | 0x6985 => "locked".to_string(),
        0x6e00 | 0x6d00 => "wrong_app".to_string(),
        _ => format!("status 0x{status_word:04x}"),
    }
}

/// Pede o endereço Ethereum (conta padrão) pra Ledger conectada. Erro vem
/// como uma destas strings: "not_connected", "access_denied", "locked",
/// "wrong_app", ou uma mensagem genérica pra qualquer outra falha inesperada.
#[tauri::command]
pub fn get_ledger_address(account_index: u32) -> Result<String, String> {
    let api = HidApi::new().map_err(|e| e.to_string())?;
    let device = open_ledger_device(&api)?;

    let apdu = build_get_address_apdu(account_index);
    let response = send_apdu(&device, &apdu, 5_000)?;
    let data = check_status(response).map_err(classify_error)?;

    parse_get_address_response(&data)
}

// --- Comando "assinar transação" do app Ethereum da Ledger ---

const INS_SIGN: u8 = 0x04;
const P1_FIRST_CHUNK: u8 = 0x00;
const P1_FOLLOWING_CHUNK: u8 = 0x80;
const NO_P2: u8 = 0x00;

/// Tamanho máximo de dados por APDU de assinatura (mesmo limite usado
/// publicamente pelo `@ledgerhq/hw-app-eth`) — diferente do tamanho do
/// pacote HID (etapa 10.2): aqui é o protocolo do app Ethereum que decide
/// fatiar uma transação grande em várias trocas de APDU, cada uma já
/// fatiada de novo em pacotes HID por `write_apdu`/`read_apdu_response`.
const SIGN_CHUNK_SIZE: usize = 150;

/// Núcleo genérico de fatiamento em APDUs de assinatura (compartilhado por
/// `build_sign_tx_apdus` e `build_sign_personal_message_apdus`). Cada APDU
/// leva no máximo `SIGN_CHUNK_SIZE` bytes de dado; o 1º carrega o caminho de
/// derivação + um prefixo extra específico da instrução (vazio pra
/// transação, 4 bytes big-endian de tamanho da mensagem pra personal_sign)
/// + o início do payload; os seguintes (`P1 = P1_FOLLOWING_CHUNK`) só levam
/// o restante dos bytes.
fn build_sign_apdus(
    payload: &[u8],
    ins_byte: u8,
    account_index: u32,
    extra_prefix: &[u8],
) -> Vec<Vec<u8>> {
    let path = encode_derivation_path(account_index);
    let mut apdus = Vec::new();
    let mut offset = 0;
    let mut first = true;

    while first || offset < payload.len() {
        let header_len = if first { path.len() + extra_prefix.len() } else { 0 };
        let chunk_len = (SIGN_CHUNK_SIZE - header_len).min(payload.len() - offset);

        let mut data = Vec::with_capacity(header_len + chunk_len);
        if first {
            data.extend_from_slice(&path);
            data.extend_from_slice(extra_prefix);
        }
        data.extend_from_slice(&payload[offset..offset + chunk_len]);

        let p1 = if first { P1_FIRST_CHUNK } else { P1_FOLLOWING_CHUNK };
        let mut apdu = vec![ETH_CLA, ins_byte, p1, NO_P2, data.len() as u8];
        apdu.extend_from_slice(&data);
        apdus.push(apdu);

        offset += chunk_len;
        first = false;
    }

    apdus
}

/// Monta a sequência de APDUs SIGN_TX para uma transação já serializada
/// (RLP, com o byte de tipo na frente para EIP-1559/2930).
fn build_sign_tx_apdus(unsigned_tx: &[u8], account_index: u32) -> Vec<Vec<u8>> {
    build_sign_apdus(unsigned_tx, INS_SIGN, account_index, &[])
}

/// Resposta do SIGN_TX (só o último chunk importa): 1 byte de `v`
/// (recovery id) + 32 bytes de `r` + 32 bytes de `s`. Devolve no mesmo
/// formato que `sign_challenge` já usa (0x + r + s + v, v na convenção
/// 27/28) pra quem chamar não precisar tratar dois formatos de assinatura
/// diferentes no resto do app.
fn parse_sign_tx_response(data: &[u8]) -> Result<String, String> {
    if data.len() < 65 {
        return Err("resposta de assinatura incompleta da Ledger".to_string());
    }

    let mut v = data[0];
    if v < 27 {
        v += 27;
    }
    let r = &data[1..33];
    let s = &data[33..65];

    Ok(format!("0x{}{}{:02x}", hex::encode(r), hex::encode(s), v))
}

/// Assina uma transação Ethereum já serializada (RLP) com a chave da
/// Ledger (mesma conta/caminho do `get_ledger_address`). `unsigned_tx_hex`
/// vem do lado TypeScript (serializado com `viem`), com ou sem prefixo
/// "0x" — aqui só tratamos como bytes opacos, não decodificamos o RLP.
/// Erro vem nos mesmos rótulos do `get_ledger_address`.
#[tauri::command]
pub fn sign_ledger_transaction(unsigned_tx_hex: String, account_index: u32) -> Result<String, String> {
    let unsigned_tx = hex::decode(unsigned_tx_hex.trim_start_matches("0x"))
        .map_err(|e| e.to_string())?;

    let api = HidApi::new().map_err(|e| e.to_string())?;
    let device = open_ledger_device(&api)?;

    let mut last_response = Vec::new();
    for apdu in build_sign_tx_apdus(&unsigned_tx, account_index) {
        let response = send_apdu(&device, &apdu, 120_000)?;
        last_response = check_status(response).map_err(|sw| match sw {
            // 0x6985 = "Conditions of use not satisfied" — durante assinatura
            // significa que o usuário rejeitou na tela da Ledger.
            0x6985 | 0x6750 => "rejected_by_user".to_string(),
            _ => classify_error(sw),
        })?;
    }

    parse_sign_tx_response(&last_response)
}

// --- Comando "assinar mensagem pessoal" do app Ethereum da Ledger ---
//
// SIGN_PERSONAL_MESSAGE (INS 0x08) — usado pelo consentimento de
// createIdentity (débito #17 do IdentityRegistry). A Ledger recebe os bytes
// crus da mensagem (no nosso caso, um hash de 32 bytes calculado no
// frontend, não texto UTF-8), aplica o prefixo
// "\x19Ethereum Signed Message:\n{len}" por conta própria e assina o
// resultado — exatamente o formato que `IdentityRegistry.createIdentity`
// espera do lado on-chain, então não há risco de descompasso entre o que a
// Ledger assina e o que o contrato verifica.

const INS_SIGN_PERSONAL_MESSAGE: u8 = 0x08;

/// O 1º APDU leva também 4 bytes big-endian com o tamanho total da
/// mensagem — o app Ethereum exige isso porque uma mensagem pessoal
/// arbitrária não tem como "saber" o próprio tamanho sozinha.
fn build_sign_personal_message_apdus(message: &[u8], account_index: u32) -> Vec<Vec<u8>> {
    build_sign_apdus(
        message,
        INS_SIGN_PERSONAL_MESSAGE,
        account_index,
        &(message.len() as u32).to_be_bytes(),
    )
}

/// Assina uma mensagem pessoal (EIP-191 `personal_sign`) com a chave da
/// Ledger (mesma conta/caminho do `get_ledger_address`). `message_hex` vem
/// do lado TypeScript como bytes crus em hex (no nosso caso, o hash de 32
/// bytes do consentimento de `createIdentity` — não uma string UTF-8), com
/// ou sem prefixo "0x". Resposta e rótulos de erro no mesmo formato de
/// `sign_ledger_transaction`.
#[tauri::command]
pub fn sign_ledger_personal_message(message_hex: String, account_index: u32) -> Result<String, String> {
    let message =
        hex::decode(message_hex.trim_start_matches("0x")).map_err(|e| e.to_string())?;

    let api = HidApi::new().map_err(|e| e.to_string())?;
    let device = open_ledger_device(&api)?;

    let mut last_response = Vec::new();
    for apdu in build_sign_personal_message_apdus(&message, account_index) {
        let response = send_apdu(&device, &apdu, 120_000)?;
        last_response = check_status(response).map_err(|sw| match sw {
            0x6985 | 0x6750 => "rejected_by_user".to_string(),
            _ => classify_error(sw),
        })?;
    }

    parse_sign_tx_response(&last_response)
}
