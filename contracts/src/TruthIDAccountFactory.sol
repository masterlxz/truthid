// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TruthIDAccount} from "./TruthIDAccount.sol";

// Factory deterministica que cria contas TruthIDAccount via CREATE2.
//
// A factory resolve o problema "ovo-e-galinha" da Fase 14: a identidade
// on-chain precisa apontar para uma smart account ANTES de ela existir.
// CREATE2 permite prever o endereco da conta com base no endereco do
// Ledger (owner) + um indice, antes de qualquer transacao de deploy.
//
// Caracteristicas:
//   - salt = keccak256(abi.encodePacked(owner_, index))
//   - index=0: conta principal. index>0: reset / contas adicionais.
//   - createAccount(owner_, index) e idempotente: se a conta ja existe,
//     retorna a instancia existente em vez de reverter.
//   - getAddress(owner_, index) pode ser chamado off-chain para prever o
//     endereco antes de deployar.
//   - Debito #25: adiciona suporte a multiplas contas por owner via indice.
//
// C8: os endereços dos registries são mutáveis (não immutable) — se um
// destes contratos precisar ser redeployado, o deployer pode chamar
// `updateRegistries` para que novas contas já apontem para as novas
// instâncias. Contas já existentes continuam apontando para as instâncias
// antigas até que o owner de cada uma chame `updateRegistries` na própria
// TruthIDAccount. O getter `getAddress` retorna endereços diferentes após
// uma atualização — mesma ressalva do IdentityRegistry._factory (que é
// mutável pelo mesmo motivo, ver comentário em IdentityRegistry.sol).
contract TruthIDAccountFactory {
    // Enderecos dos contratos privilegiados injetados no constructor da
    // factory. Toda conta criada herda esses mesmos enderecos.
    // NÃO são immutable (C8): podem ser atualizados pelo deployer.
    address public immutable entryPoint;
    address private _deviceRegistry;
    address private _identityRegistry;
    address private _recoveryManager;

    // Quem fez o deploy deste contrato. Único endereço autorizado a
    // chamar updateRegistries.
    address public immutable owner;

    // Registro das contas ja deployadas por (owner, index). Curto-circuita
    // o caminho idempotente de createAccount/getAddress sem precisar
    // recalcular o initCodeHash.
    mapping(address => mapping(uint256 => address)) public accounts;

    event AccountCreated(address indexed account, address indexed owner, uint256 indexed index);
    event FactoryRegistriesUpdated(
        address indexed deviceRegistry, address indexed identityRegistry, address indexed recoveryManager
    );

    error InvalidConstructorArgs();
    error NotOwner();
    error InvalidRegistryAddress();

    constructor(
        address entryPoint_,
        address deviceRegistry_,
        address identityRegistry_,
        address recoveryManager_
    ) {
        if (
            entryPoint_ == address(0) || deviceRegistry_ == address(0)
                || identityRegistry_ == address(0) || recoveryManager_ == address(0)
        ) {
            revert InvalidConstructorArgs();
        }

        entryPoint = entryPoint_;
        _deviceRegistry = deviceRegistry_;
        _identityRegistry = identityRegistry_;
        _recoveryManager = recoveryManager_;
        owner = msg.sender;
    }

    /// Cria uma TruthIDAccount para o owner + indice fornecidos. Se ja
    /// existir uma conta nesse endereco, retorna-a sem tentar recriar.
    /// C8: usa os valores CORRENTES de _deviceRegistry/_identityRegistry/
    /// _recoveryManager (que podem ter sido atualizados via updateRegistries).
    function createAccount(address owner_, uint256 index) external returns (TruthIDAccount ret) {
        address existing = accounts[owner_][index];
        if (existing != address(0)) {
            return TruthIDAccount(payable(existing));
        }

        bytes32 salt = _salt(owner_, index);
        address predicted = _computeAddress(salt, owner_);

        ret = new TruthIDAccount{salt: salt}(
            entryPoint, _deviceRegistry, _identityRegistry, _recoveryManager, owner_
        );

        // Sanity check: CREATE2 deve nos dar exatamente o endereco previsto.
        assert(address(ret) == predicted);

        accounts[owner_][index] = address(ret);

        emit AccountCreated(address(ret), owner_, index);
    }

    /// Calcula o endereco futuro da conta para um owner + indice, antes de deployar.
    function getAddress(address owner_, uint256 index) public view returns (address) {
        address existing = accounts[owner_][index];
        if (existing != address(0)) {
            return existing;
        }

        return _computeAddress(_salt(owner_, index), owner_);
    }

    function _computeAddress(bytes32 salt, address owner_) internal view returns (address) {
        // init code = creationCode do contrato concatenado com os argumentos
        // do constructor ABI-encoded. Esse e o hash usado pelo CREATE2.
        // C8: usa os valores CORRENTES dos registries (que podem ter
        // sido atualizados via updateRegistries).
        bytes memory initCode = abi.encodePacked(
            type(TruthIDAccount).creationCode,
            abi.encode(entryPoint, _deviceRegistry, _identityRegistry, _recoveryManager, owner_)
        );

        bytes32 initCodeHash = keccak256(initCode);

        return address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xFF), address(this), salt, initCodeHash))
                )
            )
        );
    }

    function _salt(address owner_, uint256 index) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner_, index));
    }

    // -------------------------------------------------------------------------
    // Getters (C8: retornam valores mutáveis)
    // -------------------------------------------------------------------------

    function deviceRegistry() external view returns (address) {
        return _deviceRegistry;
    }

    function identityRegistry() external view returns (address) {
        return _identityRegistry;
    }

    function recoveryManager() external view returns (address) {
        return _recoveryManager;
    }

    // -------------------------------------------------------------------------
    // Atualização de registries (C8)
    // -------------------------------------------------------------------------

    /// Atualiza os endereços dos três registries para novas instâncias
    /// (ex: após um redeploy para correção de bugs). Só o deployer (owner)
    /// pode chamar. Nenhum endereço pode ser zero.
    ///
    /// ATENÇÃO: após a atualização, `getAddress` retorna endereços
    /// DIFERENTES para o mesmo par (owner, index) — o init code do CREATE2
    /// muda porque os argumentos do constructor mudaram. Contas já criadas
    /// antes da atualização não são afetadas (continuam com os endereços
    /// antigos). O owner de cada conta existente deve chamar
    /// `updateRegistries` na própria TruthIDAccount para redirecioná-la.
    function updateRegistries(
        address deviceRegistry_,
        address identityRegistry_,
        address recoveryManager_
    ) external {
        if (msg.sender != owner) revert NotOwner();
        if (
            deviceRegistry_ == address(0) || identityRegistry_ == address(0)
                || recoveryManager_ == address(0)
        ) {
            revert InvalidRegistryAddress();
        }
        _deviceRegistry = deviceRegistry_;
        _identityRegistry = identityRegistry_;
        _recoveryManager = recoveryManager_;
        emit FactoryRegistriesUpdated(deviceRegistry_, identityRegistry_, recoveryManager_);
    }
}