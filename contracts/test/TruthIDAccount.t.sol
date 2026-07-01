// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TruthIDAccount, PackedUserOperation} from "../src/TruthIDAccount.sol";

// Cobertura NARROW: só o débito #18 (`_isDeviceCallAllowed` não deve
// reverter em `executeBatch` malformado — deve retornar SIG_VALIDATION_FAILED
// de forma limpa). Não é suíte geral do contrato.
contract TruthIDAccountTest is Test {
    // Ordem da curva secp256k1 e sua metade — usadas só pra canonicalizar
    // (low-s) as assinaturas de teste. `vm.sign` não normaliza s
    // automaticamente, e `TruthIDAccount` rejeita assinaturas non-canônicas
    // (proteção EIP-2 já existente no contrato); sem essa normalização,
    // os testes falhariam de forma intermitente dependendo do hash assinado.
    uint256 internal constant _SECP256K1N =
        0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    uint256 internal constant _SECP256K1N_DIV_2 =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    TruthIDAccount public account;

    address public owner = makeAddr("owner");
    address public entryPoint = makeAddr("entryPoint");
    address public deviceRegistry = makeAddr("deviceRegistry");
    address public identityRegistry = makeAddr("identityRegistry");
    address public recoveryManager = makeAddr("recoveryManager");

    // Precisamos da chave PRIVADA do device (não só do endereço) pra
    // assinar os userOpHash nos testes — makeAddrAndKey devolve os dois.
    address public device;
    uint256 public deviceKey;

    function setUp() public {
        account = new TruthIDAccount(
            entryPoint, deviceRegistry, identityRegistry, recoveryManager, owner
        );

        (device, deviceKey) = makeAddrAndKey("device");
        vm.prank(owner);
        account.addDevice(device);
    }

    // Monta uma PackedUserOperation mínima com o `callData` dado — os
    // demais campos não importam pro que `_validateSignature` verifica
    // (só olha `callData` e a assinatura contra `userOpHash`).
    function _buildUserOp(bytes memory callData)
        internal
        view
        returns (PackedUserOperation memory)
    {
        return PackedUserOperation({
            sender: address(account),
            nonce: 0,
            initCode: "",
            callData: callData,
            accountGasLimits: bytes32(0),
            preVerificationGas: 0,
            gasFees: bytes32(0),
            paymasterAndData: "",
            signature: ""
        });
    }

    // Assina `userOpHash` no mesmo formato que `_validateSignature` espera
    // (prefixo "\x19Ethereum Signed Message:\n32", igual SessionRegistry.t.sol),
    // canonicalizando pra low-s (ver comentário nas constantes acima).
    function _sign(uint256 privateKey, bytes32 userOpHash) internal returns (bytes memory) {
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);

        if (uint256(s) > _SECP256K1N_DIV_2) {
            s = bytes32(_SECP256K1N - uint256(s));
            v = v == 27 ? 28 : 27;
        }

        return abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // Débito #18 — executeBatch malformado não deve reverter
    // -------------------------------------------------------------------------

    function test_ValidateUserOp_ExecuteBatch_CalldataMalformado_RetornaFailedSemReverter() public {
        // Seletor certo de `executeBatch`, mas só 1 byte de payload depois —
        // não dá nem pra ler o primeiro word (offset) do array `dest[]`.
        // Antes da correção do débito #18, `abi.decode` revertia aqui, e o
        // revert propagava pra fora de `validateUserOp` inteiro.
        bytes memory callData = abi.encodePacked(account.executeBatch.selector, bytes1(0xAA));

        bytes32 userOpHash = keccak256("op-malformado");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        // 1 == SIG_VALIDATION_FAILED (constante interna de TruthIDAccount.sol)
        assertEq(validationData, 1);
    }

    // -------------------------------------------------------------------------
    // Regressão — caminho feliz e bloqueio de destino continuam funcionando
    // -------------------------------------------------------------------------

    function test_ValidateUserOp_ExecuteBatch_DestinoPermitido_Device_RetornaSuccess() public {
        address allowedDest = makeAddr("allowedDest");
        address[] memory dest = new address[](1);
        dest[0] = allowedDest;
        uint256[] memory value = new uint256[](1);
        value[0] = 0;
        bytes[] memory func = new bytes[](1);
        func[0] = "";

        bytes memory callData = abi.encodeCall(TruthIDAccount.executeBatch, (dest, value, func));

        bytes32 userOpHash = keccak256("op-feliz");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 0); // SIG_VALIDATION_SUCCESS
    }

    function test_ValidateUserOp_ExecuteBatch_DestinoBloqueado_Device_RetornaFailed() public {
        // identityRegistry vem bloqueado por padrão (constructor) — garante
        // que o refactor do try/catch não afrouxou o bloqueio de destino
        // quando o `abi.decode` em si tem sucesso.
        address[] memory dest = new address[](1);
        dest[0] = identityRegistry;
        uint256[] memory value = new uint256[](1);
        value[0] = 0;
        bytes[] memory func = new bytes[](1);
        func[0] = "";

        bytes memory callData = abi.encodeCall(TruthIDAccount.executeBatch, (dest, value, func));

        bytes32 userOpHash = keccak256("op-bloqueado");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, 1); // SIG_VALIDATION_FAILED
    }
}
