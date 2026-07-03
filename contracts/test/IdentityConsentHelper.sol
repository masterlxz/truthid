// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";

// Helper compartilhado por todo teste que precisa chamar `createIdentity`
// depois do débito #17: a função passou a exigir uma assinatura de
// consentimento (v, r, s) em vez de aceitar qualquer `controller` de graça.
//
// Reproduz exatamente o hash que `IdentityRegistry.createIdentity` espera:
// keccak256(abi.encode(chainid, address(registry), username, controller)),
// com o prefixo manual do "Ethereum Signed Message" por cima (mesma
// convenção do `_sign` de TruthIDAccount.t.sol).
abstract contract IdentityConsentHelper is Test {
    function _signConsent(
        IdentityRegistry registry,
        uint256 signerKey,
        string memory username,
        address controller
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 hash = keccak256(abi.encode(block.chainid, address(registry), username, controller));
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        (v, r, s) = vm.sign(signerKey, ethSignedHash);
    }

    // Atalho para o caso mais comum nos outros testes: o controller É o
    // próprio EOA (não uma smart account pré-deploy), então quem assina o
    // consentimento é o dono da própria chave do controller.
    function _createIdentity(
        IdentityRegistry registry,
        uint256 controllerKey,
        string memory username
    ) internal returns (uint256 id) {
        address controller = vm.addr(controllerKey);
        (uint8 v, bytes32 r, bytes32 s) =
            _signConsent(registry, controllerKey, username, controller);
        id = registry.createIdentity(username, controller, v, r, s);
    }
}
