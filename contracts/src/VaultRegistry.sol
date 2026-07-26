// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityResolver} from "./IdentityResolver.sol";
import {DeviceRegistry} from "./DeviceRegistry.sol";

// O VaultRegistry guarda apenas uma referência ao vault cifrado — nunca o
// conteúdo. O CID aponta para um blob AES-256-GCM no IPFS; a chave de
// decriptação é derivada localmente (HKDF) e nunca sai do device.
contract VaultRegistry is IdentityResolver {
    // -------------------------------------------------------------------------
    // Constantes
    // -------------------------------------------------------------------------

    // Limite máximo de versões do vault no histórico. Evita DoS de gas nos
    // getters (C6 do /code-review). Cada atualização do vault cria uma
    // entrada — 1000 é folgado para anos de uso frequente.
    uint256 public constant MAX_HISTORY = 1000;

    // -------------------------------------------------------------------------
    // Tipos de dados
    // -------------------------------------------------------------------------

    struct VaultRef {
        string cid; // IPFS CID do blob cifrado atual
        bytes32 contentHash; // keccak256 do blob (verificação de integridade)
        uint256 updatedAt; // block.timestamp da última atualização
        uint256 version; // contador monotônico — ordena atualizações
        bool exists;
    }

    // -------------------------------------------------------------------------
    // Estado
    // -------------------------------------------------------------------------

    DeviceRegistry private immutable _deviceRegistry;

    // identityId → referência atual do vault
    mapping(uint256 => VaultRef) private _vaults;

    // identityId → histórico de CIDs (todas as versões, da mais antiga à mais recente)
    mapping(uint256 => string[]) private _vaultHistory;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event VaultUpdated(uint256 indexed identityId, string cid, bytes32 indexed contentHash, uint256 version);

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error VaultNotFound(uint256 identityId);
    error EmptyCid();
    error EmptyContentHash();
    error MaxHistoryExceeded(uint256 identityId);

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address identityRegistry, address deviceRegistry) IdentityResolver(identityRegistry) {
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
        if (contentHash == bytes32(0)) revert EmptyContentHash();

        uint256 identityId = _getCallerIdentityId();

        uint256 newVersion = _vaults[identityId].exists ? _vaults[identityId].version + 1 : 1;

        _vaults[identityId] = VaultRef({
            cid: cid, contentHash: contentHash, updatedAt: block.timestamp, version: newVersion, exists: true
        });

        if (_vaultHistory[identityId].length >= MAX_HISTORY) {
            revert MaxHistoryExceeded(identityId);
        }
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
    /// C6: pode reverter se o histórico for muito grande (estouro de gas em
    /// eth_call). Use `getVaultHistoryPaginated` para arrays grandes.
    function getVaultHistory(uint256 identityId) external view returns (string[] memory) {
        return _vaultHistory[identityId];
    }

    /// Retorna uma página do histórico de CIDs. `offset` é a posição inicial
    /// (0-indexed), `limit` é o número máximo de entries. Se `offset >= length`,
    /// retorna array vazio. Se `offset + limit > length`, trunca ao final.
    /// C6: previne estouro de gas ao limitar o número de entries retornadas.
    function getVaultHistoryPaginated(uint256 identityId, uint256 offset, uint256 limit)
        external
        view
        returns (string[] memory cids)
    {
        string[] storage history = _vaultHistory[identityId];
        uint256 length = history.length;
        if (offset >= length) return new string[](0);
        uint256 end = offset + limit;
        if (end > length) end = length;
        uint256 resultLen = end - offset;
        cids = new string[](resultLen);
        for (uint256 i = 0; i < resultLen; i++) {
            cids[i] = history[offset + i];
        }
    }

    /// Retorna true se a identidade já tem um vault registrado.
    function hasVault(uint256 identityId) external view returns (bool) {
        return _vaults[identityId].exists;
    }
}
