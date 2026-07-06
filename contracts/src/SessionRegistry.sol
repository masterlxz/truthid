// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityResolver} from "./IdentityResolver.sol";
import {DeviceRegistry} from "./DeviceRegistry.sol";

contract SessionRegistry is IdentityResolver {
    // -------------------------------------------------------------------------
    // Tipos de dados
    // -------------------------------------------------------------------------

    struct Session {
        uint256 identityId; // identidade dona desta sessão
        address devicePubKey; // device que aprovou o login
        uint256 createdAt; // block.timestamp quando a sessão foi criada
        bool revoked; // true se foi revogada individualmente
        bool exists;
    }

    // -------------------------------------------------------------------------
    // Estado
    // -------------------------------------------------------------------------

    DeviceRegistry private immutable _deviceRegistry;

    // hash → Session
    mapping(bytes32 => Session) private _sessions;

    // identityId → lista de hashes (inclui revogadas)
    mapping(uint256 => bytes32[]) private _sessionsByIdentity;

    // identityId → timestamp: todas as sessões criadas ATÉ este momento estão revogadas
    // 0 significa que revokeAllSessions nunca foi chamado para esta identidade
    mapping(uint256 => uint256) private _revokedBefore;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event SessionCreated(uint256 indexed identityId, bytes32 indexed hash, address indexed devicePubKey);
    event SessionRevoked(uint256 indexed identityId, bytes32 indexed hash);
    event AllSessionsRevoked(uint256 indexed identityId, uint256 revokedBefore);

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error SessionAlreadyExists(bytes32 hash);
    error SessionNotFound(bytes32 hash);
    error SessionAlreadyRevoked(bytes32 hash);
    error InvalidSessionSignature();
    error DeviceNotOwnedByIdentity();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address identityRegistry, address deviceRegistry)
        IdentityResolver(identityRegistry)
    {
        _deviceRegistry = DeviceRegistry(deviceRegistry);
    }

    // -------------------------------------------------------------------------
    // Funções de escrita
    // -------------------------------------------------------------------------

    /// Registra uma sessão. Chamado pelo SDK do website após autenticação bem-sucedida.
    ///
    /// Qualquer endereço pode SUBMETER a transação (o hash em si é um
    /// compromisso cego — o conteúdo permanece privado), mas a sessão só é
    /// aceita se o próprio device assinou esse hash (prova de posse da chave
    /// privada) E se esse device realmente pertence à identidade informada,
    /// segundo o DeviceRegistry. Sem essas duas checagens, qualquer um
    /// poderia registrar uma sessão falsa em nome de qualquer identidade —
    /// ver auditoria de segurança, achado #2.
    ///
    /// `verifySession()` continua sendo apenas uma checagem de revogação —
    /// nunca deve ser usado como prova isolada de "este request está
    /// autenticado". A prova de login real acontece em `verifyAuthResponse`
    /// (fora da chain); esta função só registra/audita um login já aprovado.
    function createSession(
        bytes32 hash,
        uint256 identityId,
        address devicePubKey,
        bytes32 r,
        bytes32 s,
        uint8 v
    ) external {
        if (_sessions[hash].exists) revert SessionAlreadyExists(hash);

        // Prova de posse: só quem tem a chave privada de devicePubKey
        // consegue produzir essa assinatura sobre o hash exato da sessão.
        bytes32 ethSignedHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        if (ecrecover(ethSignedHash, v, r, s) != devicePubKey) revert InvalidSessionSignature();

        // Confirma que esse device de fato pertence à identidade alegada
        // (e está ativo) — sem isso, um atacante poderia usar seu PRÓPRIO
        // device (que ele realmente controla) para criar sessões falsas
        // atribuídas à identidade de uma vítima.
        DeviceRegistry.Device memory device = _deviceRegistry.getDevice(devicePubKey);
        if (device.identityId != identityId || device.revoked) revert DeviceNotOwnedByIdentity();

        _sessions[hash] = Session({
            identityId: identityId,
            devicePubKey: devicePubKey,
            createdAt: block.timestamp,
            revoked: false,
            exists: true
        });

        _sessionsByIdentity[identityId].push(hash);

        emit SessionCreated(identityId, hash, devicePubKey);
    }

    /// Revoga uma sessão específica. Só o controller da identidade dona da sessão pode fazer isso.
    function revokeSession(bytes32 hash) external {
        Session storage s = _sessions[hash];
        if (!s.exists) revert SessionNotFound(hash);
        if (isSessionRevoked(hash)) revert SessionAlreadyRevoked(hash);

        uint256 callerIdentityId = _getCallerIdentityId();
        if (s.identityId != callerIdentityId) revert NotIdentityController();

        s.revoked = true;

        emit SessionRevoked(s.identityId, hash);
    }

    /// Revoga todas as sessões da identidade do chamador criadas até agora.
    /// Truque: grava apenas um timestamp — O(1) em vez de iterar sobre todas as sessões.
    function revokeAllSessions() external {
        uint256 identityId = _getCallerIdentityId();
        _revokedBefore[identityId] = block.timestamp;
        emit AllSessionsRevoked(identityId, block.timestamp);
    }

    // -------------------------------------------------------------------------
    // Funções de leitura
    // -------------------------------------------------------------------------

    /// Verifica se uma sessão está revogada. Função principal usada pelos SDKs dos websites.
    function isSessionRevoked(bytes32 hash) public view returns (bool) {
        Session storage s = _sessions[hash];
        if (!s.exists) return true;
        return s.revoked || s.createdAt <= _revokedBefore[s.identityId];
    }

    /// Retorna os dados completos de uma sessão.
    function getSession(bytes32 hash) external view returns (Session memory) {
        if (!_sessions[hash].exists) revert SessionNotFound(hash);
        return _sessions[hash];
    }

    /// Retorna todos os hashes de sessão de uma identidade (incluindo revogadas).
    function getSessionsByIdentity(uint256 identityId) external view returns (bytes32[] memory) {
        return _sessionsByIdentity[identityId];
    }

    /// Retorna o timestamp de revogação em massa (0 se revokeAllSessions nunca foi chamado).
    function getRevokedBefore(uint256 identityId) external view returns (uint256) {
        return _revokedBefore[identityId];
    }
}
