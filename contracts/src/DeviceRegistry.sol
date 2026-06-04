// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "./IdentityRegistry.sol";

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

contract DeviceRegistry {
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

    // `immutable`: calculado no constructor e gravado diretamente no bytecode.
    // Não ocupa um slot de storage — leituras são mais baratas.
    IdentityRegistry private immutable _identityRegistry;

    // pubKey (address) → Device
    mapping(address => Device) private _devices;

    // identityId → lista de pubKeys registradas para essa identidade (inclui revogados)
    mapping(uint256 => address[]) private _devicesByIdentity;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event DeviceRegistered(uint256 indexed identityId, address indexed pubKey, string label);
    event DeviceRevoked(uint256 indexed identityId, address indexed pubKey);

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error DeviceAlreadyRegistered(address pubKey);
    error DeviceNotFound(address pubKey);
    error DeviceAlreadyRevoked(address pubKey);
    error NotIdentityController();
    error InvalidPubKey();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address identityRegistry) {
        _identityRegistry = IdentityRegistry(identityRegistry);
    }

    // -------------------------------------------------------------------------
    // Funções de escrita
    // -------------------------------------------------------------------------

    /// Registra um novo device para a identidade do chamador.
    /// O chamador precisa ter uma identidade no IdentityRegistry.
    function registerDevice(address devicePubKey, string calldata label) external {
        if (devicePubKey == address(0)) revert InvalidPubKey();
        if (_devices[devicePubKey].exists) revert DeviceAlreadyRegistered(devicePubKey);

        uint256 identityId = _getCallerIdentityId();

        _devices[devicePubKey] = Device({
            identityId: identityId,
            pubKey: devicePubKey,
            label: label,
            addedAt: block.timestamp,
            revoked: false,
            exists: true
        });

        _devicesByIdentity[identityId].push(devicePubKey);

        emit DeviceRegistered(identityId, devicePubKey, label);
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

    // -------------------------------------------------------------------------
    // Funções internas
    // -------------------------------------------------------------------------

    // Obtém o identityId da identidade controlada por msg.sender.
    // Reverte se msg.sender não for controller de nenhuma identidade.
    function _getCallerIdentityId() internal view returns (uint256) {
        // Lookup reverso: carteira → username
        string memory username = _identityRegistry.getUsernameByController(msg.sender);

        // String vazia significa que esse endereço não controla nenhuma identidade
        if (bytes(username).length == 0) revert NotIdentityController();

        // Com o username em mãos, buscamos a identidade completa
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        return identity.id;
    }
}
