// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "./IdentityRegistry.sol";
import {TruthIDAccount} from "./TruthIDAccount.sol";

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

    // Limite de guardians por identidade — sem isso, um controller hostil
    // poderia inflar o array a ponto de `proposeRecovery`/`configureGuardians`
    // custarem gas demais para qualquer guardian conseguir pagar (DoS).
    uint256 public constant MAX_GUARDIANS = 20;

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
    error InvalidNewController();
    error TooManyGuardians(uint256 count, uint256 max);

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
        if (guardians.length > MAX_GUARDIANS) {
            revert TooManyGuardians(guardians.length, MAX_GUARDIANS);
        }

        // Bloqueia reconfiguração com proposta em andamento — evita invalidar votos já coletados
        RecoveryProposal storage proposal = _proposals[identityId];
        if (proposal.exists && !proposal.executed && !proposal.cancelled) {
            revert ActiveProposalExists();
        }

        // Remove guardians antigos do mapa de lookup antes de sobrescrever
        GuardianConfig storage config = _guardianConfigs[identityId];
        _clearGuardianFlags(identityId, config.guardians);

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
        if (newController == address(0)) revert InvalidNewController();

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
    ///
    /// Defesa contra reentrância (achado C1, /code-review Sessão 140):
    /// O controller antigo (identity.controller) é quem recebe a chamada
    /// externa emergencyWithdraw — exatamente o endereço que, no cenário
    /// de recovery, pode estar comprometido por um atacante. Seguimos o
    /// padrão Checks-Effects-Interactions: (1) todas as checagens, (2)
    /// gravamos todo o estado final ANTES de qualquer chamada externa,
    /// (3) só então fazemos as interações — usando uma cópia `memory` do
    /// newController honesto, não o ponteiro storage (que um reentrante
    /// poderia tentar sobrescrever). Se o controller atacado reentrar
    /// proposeRecovery durante o emergencyWithdraw, ele reverte com
    /// GuardiansNotConfigured: os flags já foram limpos no passo 2.
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

        // --- EFFECTS: todo o estado final gravado antes de qualquer external call ---

        // Cópia memory do newController honesto. Daqui pra frente nunca mais
        // lemos proposal.newController do storage — um reentrante poderia
        // sobrescrever esse slot. Mesmo que conseguisse, o recoverController
        // abaixo usaria este valor memory, não o storage.
        address newController = proposal.newController;

        proposal.executed = true;

        // Limpa os guardians ANTES da chamada externa: se o controller
        // atacado reentrar proposeRecovery durante o emergencyWithdraw,
        // ele reverte aqui (GuardiansNotConfigured) — sem segunda proposta
        // fantasma pendurada por 7 dias.
        _clearGuardianFlags(identityId, config.guardians);
        delete _guardianConfigs[identityId];

        // --- INTERACTIONS: só agora, com o estado já finalizado ---

        // Tenta transferir o saldo da smart account antiga (TruthIDAccount)
        // para o novo controller. identity.controller eh uma copia memory —
        // ainda guarda o endereco antigo (antes de recoverController sobrescrever
        // no storage). Se o controller antigo for um EOA comum (nao uma
        // TruthIDAccount), a chamada eh pulada — Solidity 0.8 insere extcodesize
        // antes de high-level calls, entao nao da pra confiar soh no try/catch.
        if (identity.controller.code.length > 0) {
            try TruthIDAccount(payable(identity.controller)).emergencyWithdraw(newController) {
                // Fundos migrados da smart account antiga para o novo controller.
            } catch {
                // Nao eh uma TruthIDAccount valida — recovery segue sem migrar fundos.
            }
        }

        _identityRegistry.recoverController(username, newController);

        emit RecoveryExecuted(identityId, newController);
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

    // Zera o flag _isGuardian para uma lista de endereços (usado ao reconfigurar
    // guardians e ao limpar o conjunto antigo após uma recovery executada)
    function _clearGuardianFlags(uint256 identityId, address[] storage guardians) internal {
        for (uint256 i = 0; i < guardians.length; i++) {
            _isGuardian[identityId][guardians[i]] = false;
        }
    }
}
