// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "./IdentityRegistry.sol";

// Como funciona o recovery social?
// ------------------------------------------------------------------
// O usuário define "guardians" — pessoas de confiança (endereços).
// Se perder acesso à wallet, os guardians propõem e aprovam a troca
// de controller para uma nova wallet. Dois mecanismos de segurança:
//
//   1. Threshold M-de-N: requer M aprovações de N guardians
//      (ex: 3-de-5), evitando que um único guardian comprometa a conta.
//
//   2. Timelock de 7 dias: mesmo após aprovações suficientes, a
//      mudança só executa depois de 7 dias — janela para o owner
//      legítimo perceber e cancelar se foi um ataque.
//
// Ciclo de vida de uma proposta:
//   proposeRecovery() → approveRecovery() → executeRecovery()
//                                        ↘ cancelRecovery() (pelo controller)

contract RecoveryManager {
    // -------------------------------------------------------------------------
    // Constantes
    // -------------------------------------------------------------------------

    uint256 public constant TIMELOCK = 7 days;

    // -------------------------------------------------------------------------
    // Tipos de dados
    // -------------------------------------------------------------------------

    struct GuardianConfig {
        address[] guardians; // lista de guardians (ordem não importa)
        uint256 threshold;   // quantos precisam aprovar (M de N)
        bool configured;     // false = nunca configurado
    }

    struct RecoveryProposal {
        address proposedBy;    // guardian que iniciou
        address newController; // nova wallet que assumirá o controle
        uint256 proposedAt;    // timestamp da proposta (base do timelock)
        uint256 approvalCount; // quantos guardians aprovaram até agora
        bool executed;         // true se a recovery já foi executada
        bool cancelled;        // true se o controller cancelou
        bool exists;           // false = nunca houve proposta para esta identidade
    }

    // -------------------------------------------------------------------------
    // Estado
    // -------------------------------------------------------------------------

    IdentityRegistry private immutable _identityRegistry;

    // identityId → configuração de guardians
    mapping(uint256 => GuardianConfig) private _guardianConfigs;

    // identityId → guardian → é guardian? (lookup O(1), evita loop na validação)
    mapping(uint256 => mapping(address => bool)) private _isGuardian;

    // identityId → proposta ativa (só uma por identidade por vez)
    mapping(uint256 => RecoveryProposal) private _proposals;

    // identityId → guardian → já aprovou a proposta atual?
    mapping(uint256 => mapping(address => bool)) private _approvals;

    // -------------------------------------------------------------------------
    // Eventos
    // -------------------------------------------------------------------------

    event GuardiansConfigured(uint256 indexed identityId, address[] guardians, uint256 threshold);
    event RecoveryProposed(uint256 indexed identityId, address indexed proposedBy, address indexed newController);
    event RecoveryApproved(uint256 indexed identityId, address indexed guardian, uint256 approvalCount);
    event RecoveryExecuted(uint256 indexed identityId, address indexed newController);
    event RecoveryCancelled(uint256 indexed identityId);

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error NotIdentityController();
    error NotGuardian();
    error InvalidThreshold();
    error GuardiansNotConfigured(uint256 identityId);
    error ProposalAlreadyExists(uint256 identityId);
    error NoActiveProposal(uint256 identityId);
    error ProposalAlreadyExecuted();
    error ProposalAlreadyCancelled();
    error AlreadyApproved(address guardian);
    error ThresholdNotReached(uint256 current, uint256 required);
    error TimelockNotExpired(uint256 proposedAt, uint256 executeAfter);
    error ActiveProposalExists();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address identityRegistry) {
        _identityRegistry = IdentityRegistry(identityRegistry);
    }

    // -------------------------------------------------------------------------
    // Configuração de guardians
    // -------------------------------------------------------------------------

    /// Define (ou redefine) os guardians de uma identidade.
    /// Só o controller pode configurar. Não pode ter proposta ativa.
    function configureGuardians(
        string calldata username,
        address[] calldata guardians,
        uint256 threshold
    ) external {
        uint256 identityId = _requireController(username);

        if (guardians.length == 0 || threshold == 0 || threshold > guardians.length) {
            revert InvalidThreshold();
        }

        // Bloqueia reconfiguração com proposta em andamento — evita invalidar votos já coletados
        RecoveryProposal storage proposal = _proposals[identityId];
        if (proposal.exists && !proposal.executed && !proposal.cancelled) {
            revert ActiveProposalExists();
        }

        // Remove guardians antigos do mapa de lookup antes de sobrescrever
        GuardianConfig storage config = _guardianConfigs[identityId];
        for (uint256 i = 0; i < config.guardians.length; i++) {
            _isGuardian[identityId][config.guardians[i]] = false;
        }

        config.guardians = guardians;
        config.threshold = threshold;
        config.configured = true;

        for (uint256 i = 0; i < guardians.length; i++) {
            _isGuardian[identityId][guardians[i]] = true;
        }

        emit GuardiansConfigured(identityId, guardians, threshold);
    }

    // -------------------------------------------------------------------------
    // Ciclo de vida da proposta
    // -------------------------------------------------------------------------

    /// Propõe a troca de controller. Só um guardian pode iniciar.
    /// Substitui qualquer proposta anterior (executada ou cancelada).
    function proposeRecovery(string calldata username, address newController) external {
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        uint256 identityId = identity.id;

        // Checa configuração antes de autorização: erro mais descritivo para guardians
        // que tentam propor antes de o controller ter configurado os guardians.
        GuardianConfig storage config = _guardianConfigs[identityId];
        if (!config.configured) revert GuardiansNotConfigured(identityId);

        if (!_isGuardian[identityId][msg.sender]) revert NotGuardian();

        RecoveryProposal storage proposal = _proposals[identityId];
        if (proposal.exists && !proposal.executed && !proposal.cancelled) {
            revert ProposalAlreadyExists(identityId);
        }

        _clearApprovals(identityId, config.guardians);

        _proposals[identityId] = RecoveryProposal({
            proposedBy: msg.sender,
            newController: newController,
            proposedAt: block.timestamp,
            approvalCount: 0,
            executed: false,
            cancelled: false,
            exists: true
        });

        emit RecoveryProposed(identityId, msg.sender, newController);
    }

    /// Aprova a proposta ativa. Cada guardian pode aprovar uma única vez.
    function approveRecovery(string calldata username) external {
        uint256 identityId = _requireGuardian(username);

        RecoveryProposal storage proposal = _activeProposal(identityId);

        if (_approvals[identityId][msg.sender]) revert AlreadyApproved(msg.sender);

        _approvals[identityId][msg.sender] = true;
        proposal.approvalCount++;

        emit RecoveryApproved(identityId, msg.sender, proposal.approvalCount);
    }

    /// Executa a recovery. Qualquer um pode chamar após threshold atingido + 7 dias.
    /// Separar "aprovar" de "executar" é intencional: o beneficiado pode não
    /// estar online no exato momento em que o último guardian aprova.
    function executeRecovery(string calldata username) external {
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        uint256 identityId = identity.id;

        RecoveryProposal storage proposal = _activeProposal(identityId);

        GuardianConfig storage config = _guardianConfigs[identityId];
        if (proposal.approvalCount < config.threshold) {
            revert ThresholdNotReached(proposal.approvalCount, config.threshold);
        }

        uint256 executeAfter = proposal.proposedAt + TIMELOCK;
        if (block.timestamp < executeAfter) {
            revert TimelockNotExpired(proposal.proposedAt, executeAfter);
        }

        proposal.executed = true;

        _identityRegistry.recoverController(username, proposal.newController);

        emit RecoveryExecuted(identityId, proposal.newController);
    }

    /// Cancela a proposta ativa. Só o controller atual pode cancelar.
    /// Esta é a "janela de defesa" durante os 7 dias de timelock.
    function cancelRecovery(string calldata username) external {
        uint256 identityId = _requireController(username);

        RecoveryProposal storage proposal = _activeProposal(identityId);

        proposal.cancelled = true;

        emit RecoveryCancelled(identityId);
    }

    // -------------------------------------------------------------------------
    // Funções de leitura
    // -------------------------------------------------------------------------

    function getGuardianConfig(string calldata username)
        external
        view
        returns (address[] memory guardians, uint256 threshold)
    {
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        GuardianConfig storage config = _guardianConfigs[identity.id];
        return (config.guardians, config.threshold);
    }

    function getProposal(string calldata username)
        external
        view
        returns (RecoveryProposal memory)
    {
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        return _proposals[identity.id];
    }

    function hasGuardianApproved(string calldata username, address guardian)
        external
        view
        returns (bool)
    {
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        return _approvals[identity.id][guardian];
    }

    // -------------------------------------------------------------------------
    // Funções internas
    // -------------------------------------------------------------------------

    function _requireController(string calldata username) internal view returns (uint256) {
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        if (identity.controller != msg.sender) revert NotIdentityController();
        return identity.id;
    }

    function _requireGuardian(string calldata username) internal view returns (uint256) {
        IdentityRegistry.Identity memory identity = _identityRegistry.getIdentity(username);
        if (!_isGuardian[identity.id][msg.sender]) revert NotGuardian();
        return identity.id;
    }

    // Retorna a proposta ativa ou reverte se não existir / já finalizada
    function _activeProposal(uint256 identityId) internal view returns (RecoveryProposal storage) {
        RecoveryProposal storage proposal = _proposals[identityId];
        if (!proposal.exists) revert NoActiveProposal(identityId);
        if (proposal.executed) revert ProposalAlreadyExecuted();
        if (proposal.cancelled) revert ProposalAlreadyCancelled();
        return proposal;
    }

    // Zera os flags de aprovação para todos os guardians atuais
    function _clearApprovals(uint256 identityId, address[] storage guardians) internal {
        for (uint256 i = 0; i < guardians.length; i++) {
            _approvals[identityId][guardians[i]] = false;
        }
    }
}
