// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "./IdentityRegistry.sol";
import {DeviceRegistry} from "./DeviceRegistry.sol";

// O VaultRegistry guarda apenas uma referência ao vault cifrado — nunca o
// conteúdo. O CID aponta para um blob AES-256-GCM no IPFS; a chave de
// decriptação é derivada localmente (HKDF) e nunca sai do device.
contract VaultRegistry {
    // -------------------------------------------------------------------------
    // Tipos de dados
    // -------------------------------------------------------------------------

    struct VaultRef {
        string cid;          // IPFS CID do blob cifrado atual
        bytes32 contentHash; // keccak256 do blob (verificação de integridade)
        uint256 updatedAt;   // block.timestamp da última atualização
        uint256 version;     // contador monotônico — ordena atualizações
        bool exists;
    }

    // -------------------------------------------------------------------------
    // Estado
    // -------------------------------------------------------------------------

    IdentityRegistry private immutable _identityRegistry;
    DeviceRegistry private immutable _deviceRegistry;

    // identityId → referência atual do vault
    mapping(uint256 => VaultRef) private _vaults;

    // identityId → histórico de CIDs (todas as versões, da mais antiga à mais recente)
    mapping(uint256 => string[]) private _vaultHistory;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event VaultUpdated(
        uint256 indexed identityId,
        string cid,
        bytes32 indexed contentHash,
        uint256 version
    );

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error NotIdentityController();
    error VaultNotFound(uint256 identityId);
    error EmptyCid();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address identityRegistry, address deviceRegistry) {
        _identityRegistry = IdentityRegistry(identityRegistry);
        _deviceRegistry = DeviceRegistry(deviceRegistry);
    }

    // -------------------------------------------------------------------------
    // Funções de escrita
    // -------------------------------------------------------------------------

    /// Atualiza a referência do vault. Só o controller da identidade pode chamar.
    /// `canWriteVault` por device é estado local no Desktop — não há terceiros
    /// desconfiados que precisem ser restritos on-chain neste fluxo.
    function updateVault(string calldata cid, bytes32 contentHash) external {
        if (bytes(cid).length == 0) revert EmptyCid();

        uint256 identityId = _getCallerIdentityId();

        uint256 newVersion = _vaults[identityId].exists
            ? _vaults[identityId].version + 1
            : 1;

        _vaults[identityId] = VaultRef({
            cid: cid,
            contentHash: contentHash,
            updatedAt: block.timestamp,
            version: newVersion,
            exists: true
        });

        _vaultHistory[identityId].push(cid);

        emit VaultUpdated(identityId, cid, contentHash, newVersion);
    }

    // -------------------------------------------------------------------------
    // Funções de leitura
    // -------------------------------------------------------------------------

    /// Retorna a referência atual do vault de uma identidade.
    function getVault(uint256 identityId) external view returns (VaultRef memory) {
        if (!_vaults[identityId].exists) revert VaultNotFound(identityId);
        return _vaults[identityId];
    }

    /// Retorna o histórico completo de CIDs (da versão mais antiga à mais recente).
    function getVaultHistory(uint256 identityId) external view returns (string[] memory) {
        return _vaultHistory[identityId];
    }

    /// Retorna true se a identidade já tem um vault registrado.
    function hasVault(uint256 identityId) external view returns (bool) {
        return _vaults[identityId].exists;
    }

    // -------------------------------------------------------------------------
    // Funções internas
    // -------------------------------------------------------------------------

    function _getCallerIdentityId() internal view returns (uint256) {
        string memory username = _identityRegistry.getUsernameByController(msg.sender);
        if (bytes(username).length == 0) revert NotIdentityController();
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        return identity.id;
    }
}
