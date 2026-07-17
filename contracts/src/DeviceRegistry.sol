// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityResolver} from "./IdentityResolver.sol";

// Por que a chave pública do device é um `address`?
// -------------------------------------------------------
// Dispositivos (mobile/desktop) geram um par de chaves secp256k1 — o mesmo
// algoritmo usado pelo Ethereum. De uma chave pública secp256k1 conseguimos
// derivar um endereço Ethereum: keccak256(pubKey)[12:].
//
// Armazenar o `address` (20 bytes) em vez da chave bruta (64 bytes) tem duas
// vantagens práticas:
//   1. Custa menos gas (menos storage).
//   2. Quando o device assina um challenge de autenticação, o SDK pode usar
//      `ecrecover(hash, v, r, s)` e comparar com o `address` registrado aqui.
//      Nenhuma biblioteca de criptografia extra é necessária — é tudo nativo.

contract DeviceRegistry is IdentityResolver {
    // -------------------------------------------------------------------------
    // Tipos de dados
    // -------------------------------------------------------------------------

    struct Device {
        uint256 identityId; // identidade à qual este device pertence
        address pubKey;     // endereço Ethereum derivado da chave pública do device
        string label;       // nome legível, ex: "iPhone 15 Pro"
        uint256 addedAt;    // block.timestamp quando o device foi registrado
        bool revoked;       // true se o device foi revogado
        bool exists;        // flag para distinguir "não existe" de "existe com valores zerados"
    }

    // -------------------------------------------------------------------------
    // Estado
    // -------------------------------------------------------------------------

    // pubKey (address) → Device
    mapping(address => Device) private _devices;

    // identityId → lista de pubKeys registradas para essa identidade (inclui revogados)
    mapping(uint256 => address[]) private _devicesByIdentity;

    // commitment (hash) → número do bloco em que foi commitado (0 = não existe)
    // Usado pelo esquema commit-reveal de registerDevice — ver nota abaixo.
    mapping(bytes32 => uint256) private _commitBlocks;

    // devicePubKey → vault key cifrada para este device (ECIES com a chave pública do device).
    // Vazio se nenhuma chave de vault foi compartilhada durante o pareamento.
    mapping(address => bytes) public deviceVaultKeys;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event DeviceRegistered(uint256 indexed identityId, address indexed pubKey, string label, bytes encryptedVaultKey);
    event DeviceRevoked(uint256 indexed identityId, address indexed pubKey);

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error DeviceAlreadyRegistered(address pubKey);
    error DeviceNotFound(address pubKey);
    error DeviceAlreadyRevoked(address pubKey);
    error DeviceBelongsToAnotherIdentity(address pubKey);
    error InvalidPubKey();
    error NoCommitmentFound();
    error RevealTooEarly();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address identityRegistry) IdentityResolver(identityRegistry) {}

    // -------------------------------------------------------------------------
    // Funções de escrita
    // -------------------------------------------------------------------------

    /// Passo 1 de 2 do registro: compromete um hash do devicePubKey sem
    /// revelá-lo. Protege contra front-running — sem isso, qualquer um
    /// observando a mempool poderia ver o devicePubKey de uma transação
    /// pendente e registrá-lo primeiro para a PRÓPRIA identidade, fazendo a
    /// transação legítima reverter (ver auditoria de segurança, achado #7).
    ///
    /// `commitment` deve ser `keccak256(abi.encodePacked(devicePubKey, salt, msg.sender))`.
    /// Incluir `msg.sender` no hash é essencial: impede que outra pessoa
    /// "roube" esse commitment copiando devicePubKey+salt quando eles forem
    /// revelados no passo 2 (só o endereço que commitou pode revelar).
    function commitDevice(bytes32 commitment) external {
        _commitBlocks[commitment] = block.number;
    }

    /// Passo 2 de 2: revela devicePubKey + salt, registra o device.
    /// Só funciona se `commitDevice` foi chamado antes (em um bloco anterior)
    /// com o commitment correspondente.
    ///
    /// `encryptedVaultKey` é opcional: bytes vazios se nenhuma chave de vault
    /// foi compartilhada. Quando preenchido, contém a chave AES do vault cifrada
    /// com a chave pública do device (ECIES secp256k1) — o device consegue
    /// decifrar com sua chave privada e assim acessar o vault sem precisar da
    /// wallet conectada.
    function registerDevice(
        address devicePubKey,
        string calldata label,
        bytes32 salt,
        bytes calldata encryptedVaultKey
    ) external {
        if (devicePubKey == address(0)) revert InvalidPubKey();

        Device storage existing = _devices[devicePubKey];
        // Um device revogado pode ser re-registrado (ex: revogado por engano,
        // ou o usuário quer reativar um device antigo) — mas só pela mesma
        // identidade que era dona dele antes. Um device nunca registrado
        // (!exists) segue liberado pra qualquer identidade, como sempre foi.
        if (existing.exists && !existing.revoked) revert DeviceAlreadyRegistered(devicePubKey);

        bytes32 commitment = keccak256(abi.encodePacked(devicePubKey, salt, msg.sender));
        uint256 commitBlock = _commitBlocks[commitment];
        if (commitBlock == 0) revert NoCommitmentFound();
        if (block.number <= commitBlock) revert RevealTooEarly();

        delete _commitBlocks[commitment];

        uint256 identityId = _getCallerIdentityId();

        if (existing.exists && existing.identityId != identityId) {
            revert DeviceBelongsToAnotherIdentity(devicePubKey);
        }

        _devices[devicePubKey] = Device({
            identityId: identityId,
            pubKey: devicePubKey,
            label: label,
            addedAt: block.timestamp,
            revoked: false,
            exists: true
        });

        _devicesByIdentity[identityId].push(devicePubKey);

        if (encryptedVaultKey.length > 0) {
            deviceVaultKeys[devicePubKey] = encryptedVaultKey;
        }

        emit DeviceRegistered(identityId, devicePubKey, label, encryptedVaultKey);
    }

    /// Revoga um device. O chamador precisa ser o controller da identidade dona do device.
    function revokeDevice(address devicePubKey) external {
        if (!_devices[devicePubKey].exists) revert DeviceNotFound(devicePubKey);
        if (_devices[devicePubKey].revoked) revert DeviceAlreadyRevoked(devicePubKey);

        uint256 callerIdentityId = _getCallerIdentityId();

        // Garante que o device pertence à identidade do chamador, não a outra
        if (_devices[devicePubKey].identityId != callerIdentityId) revert NotIdentityController();

        _devices[devicePubKey].revoked = true;

        emit DeviceRevoked(callerIdentityId, devicePubKey);
    }

    // -------------------------------------------------------------------------
    // Funções de leitura
    // -------------------------------------------------------------------------

    /// Retorna true se o device existe E não foi revogado.
    /// Esta é a função principal que os SDKs usam para verificar autenticação.
    function isDeviceActive(address devicePubKey) external view returns (bool) {
        Device storage d = _devices[devicePubKey];
        return d.exists && !d.revoked;
    }

    /// Retorna as informações completas de um device.
    function getDevice(address devicePubKey) external view returns (Device memory) {
        if (!_devices[devicePubKey].exists) revert DeviceNotFound(devicePubKey);
        return _devices[devicePubKey];
    }

    /// Retorna todas as pubKeys de devices de uma identidade (incluindo revogados).
    /// Use `isDeviceActive` para filtrar os ativos.
    function getDevicesByIdentity(uint256 identityId) external view returns (address[] memory) {
        return _devicesByIdentity[identityId];
    }

    /// Retorna quantos devices uma identidade tem (incluindo revogados).
    function deviceCount(uint256 identityId) external view returns (uint256) {
        return _devicesByIdentity[identityId].length;
    }
}
