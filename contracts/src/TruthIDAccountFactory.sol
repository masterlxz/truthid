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
contract TruthIDAccountFactory {
    // Enderecos dos contratos privilegiados injetados no constructor da
    // factory. Toda conta criada herda esses mesmos enderecos.
    address public immutable entryPoint;
    address public immutable deviceRegistry;
    address public immutable identityRegistry;
    address public immutable recoveryManager;

    // Registro das contas ja deployadas por (owner, index). Curto-circuita
    // o caminho idempotente de createAccount/getAddress sem precisar
    // recalcular o initCodeHash.
    mapping(address => mapping(uint256 => address)) public accounts;

    event AccountCreated(address indexed account, address indexed owner, uint256 indexed index);

    error InvalidConstructorArgs();

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
        deviceRegistry = deviceRegistry_;
        identityRegistry = identityRegistry_;
        recoveryManager = recoveryManager_;
    }

    /// Cria uma TruthIDAccount para o owner + indice fornecidos. Se ja
    /// existir uma conta nesse endereco, retorna-a sem tentar recriar.
    function createAccount(address owner_, uint256 index) external returns (TruthIDAccount ret) {
        address existing = accounts[owner_][index];
        if (existing != address(0)) {
            return TruthIDAccount(payable(existing));
        }

        bytes32 salt = _salt(owner_, index);
        address predicted = _computeAddress(salt, owner_);

        ret = new TruthIDAccount{salt: salt}(
            entryPoint, deviceRegistry, identityRegistry, recoveryManager, owner_
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
        bytes memory initCode = abi.encodePacked(
            type(TruthIDAccount).creationCode,
            abi.encode(entryPoint, deviceRegistry, identityRegistry, recoveryManager, owner_)
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
}