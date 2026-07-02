// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TruthIDAccount} from "./TruthIDAccount.sol";

// Factory deterministica que cria contas TruthIDAccount via CREATE2.
//
// A factory resolve o problema "ovo-e-galinha" da Fase 14: a identidade
// on-chain precisa apontar para uma smart account ANTES de ela existir.
// CREATE2 permite prever o endereço da conta com base no endereço do
// Ledger (owner) antes de qualquer transacao de deploy.
//
// Caracteristicas:
//   - salt = keccak256(abi.encodePacked(owner_))
//   - createAccount(owner_) e idempotente: se a conta ja existe, retorna
//     a instancia existente em vez de reverter.
//   - getAddress(owner_) pode ser chamado off-chain para prever o
//     endereco antes de deployar.
contract TruthIDAccountFactory {
    // Enderecos dos contratos privilegiados injetados no constructor da
    // factory. Toda conta criada herda esses mesmos enderecos.
    address public immutable entryPoint;
    address public immutable deviceRegistry;
    address public immutable identityRegistry;
    address public immutable recoveryManager;

    event AccountCreated(address indexed account, address indexed owner);

    error InvalidEntryPoint();
    error InvalidDeviceRegistry();
    error InvalidIdentityRegistry();
    error InvalidRecoveryManager();

    constructor(
        address entryPoint_,
        address deviceRegistry_,
        address identityRegistry_,
        address recoveryManager_
    ) {
        if (entryPoint_ == address(0)) revert InvalidEntryPoint();
        if (deviceRegistry_ == address(0)) revert InvalidDeviceRegistry();
        if (identityRegistry_ == address(0)) revert InvalidIdentityRegistry();
        if (recoveryManager_ == address(0)) revert InvalidRecoveryManager();

        entryPoint = entryPoint_;
        deviceRegistry = deviceRegistry_;
        identityRegistry = identityRegistry_;
        recoveryManager = recoveryManager_;
    }

    /// Cria uma TruthIDAccount para o owner fornecido. Se ja existir uma
    /// conta nesse endereco, retorna-a sem tentar recriar.
    function createAccount(address owner_) external returns (TruthIDAccount ret) {
        address predicted = getAddress(owner_);

        uint256 codeSize;
        assembly {
            codeSize := extcodesize(predicted)
        }

        if (codeSize > 0) {
            return TruthIDAccount(payable(predicted));
        }

        ret = new TruthIDAccount{salt: _salt(owner_)}(
            entryPoint, deviceRegistry, identityRegistry, recoveryManager, owner_
        );

        // Sanity check: CREATE2 deve nos dar exatamente o endereco previsto.
        assert(address(ret) == predicted);

        emit AccountCreated(address(ret), owner_);
    }

    /// Calcula o endereco futuro da conta para um owner, antes de deployar.
    function getAddress(address owner_) public view returns (address) {
        bytes32 salt = _salt(owner_);

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

    function _salt(address owner_) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner_));
    }
}
