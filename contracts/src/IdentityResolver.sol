// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IdentityRegistry} from "./IdentityRegistry.sol";

// Débito #42: `_getCallerIdentityId()` era uma cópia byte-a-byte em
// DeviceRegistry, SessionRegistry e VaultRegistry (mesmo campo
// `_identityRegistry`, mesmo erro `NotIdentityController`, mesma lógica).
// Extraído aqui como base compartilhada — primeiro uso de herança em
// contracts/src/ (até então todo contrato era `contract X { }` isolado).
//
// `abstract`: nunca deve ser deployado sozinho — só serve de base pra
// registries que precisam responder "quem é o msg.sender, em identityId".
abstract contract IdentityResolver {
    // -------------------------------------------------------------------------
    // Estado
    // -------------------------------------------------------------------------

    // `private`: nenhum contrato derivado toca em `_identityRegistry`
    // diretamente hoje — todos passam por `_getCallerIdentityId()`, que já
    // vive aqui. Promover pra `internal` se um derivado precisar do endereço
    // bruto no futuro.
    IdentityRegistry private immutable _identityRegistry;

    // -------------------------------------------------------------------------
    // Erros customizados
    // -------------------------------------------------------------------------

    error NotIdentityController();

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address identityRegistry) {
        _identityRegistry = IdentityRegistry(identityRegistry);
    }

    // -------------------------------------------------------------------------
    // Funções internas
    // -------------------------------------------------------------------------

    // Obtém o identityId da identidade controlada por msg.sender.
    // Reverte se msg.sender não for controller de nenhuma identidade.
    //
    // Débito #42: antes, resolver isso custava 2 chamadas externas
    // (getUsernameByController + getIdentity) e copiava o struct Identity
    // inteiro (com a string `username` dinâmica) só pra extrair o `id`.
    // `getIdentityIdByController` encadeia as duas mappings dentro do
    // próprio IdentityRegistry: 1 chamada externa, sem copiar string nenhuma.
    function _getCallerIdentityId() internal view returns (uint256) {
        uint256 identityId = _identityRegistry.getIdentityIdByController(msg.sender);
        if (identityId == 0) revert NotIdentityController();
        return identityId;
    }
}
