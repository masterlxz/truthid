// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TruthIDAccount, PackedUserOperation} from "../src/TruthIDAccount.sol";

// Contrato-alvo mínimo para os testes de `execute`/`executeBatch` — só
// registra que foi chamado (e com qual calldata) e aceita ETH, para não
// precisar de nenhum contrato real de produção como alvo dos testes de
// execução (diferente dos testes de VALIDAÇÃO, que usam os endereços reais
// bloqueados via `blockedForDevices`).
contract MockTarget {
    uint256 public callCount;
    bytes public lastCallData;

    function ping() external {
        callCount++;
        lastCallData = msg.data;
    }

    receive() external payable {}
}

// Suíte geral da TruthIDAccount (Fase 14, etapa 14.5). Cobre:
//   B1 — constructor e seeding do blockedForDevices
//   B2 — addDevice / removeDevice
//   B3 — blockDestinationForDevices / unblockDestinationForDevices
//   B4 — validateUserOp, tier owner
//   B5 — validateUserOp, tier device (restrições de calldata)
//   B6 — emergencyWithdraw
//   B7 — execute / executeBatch (camada de execução, não validação)
//   B8 — receive()
//
// Os 3 testes originais do débito #18 (Sessão 55) continuam aqui, na
// seção B5, como regressão.
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

    uint256 internal constant SIG_VALIDATION_SUCCESS = 0;
    uint256 internal constant SIG_VALIDATION_FAILED = 1;

    TruthIDAccount public account;

    // owner agora precisa de chave privada (makeAddrAndKey) — os testes de
    // validateUserOp no tier owner (B4) assinam UserOps como o Ledger faria.
    address public owner;
    uint256 public ownerKey;

    address public entryPoint = makeAddr("entryPoint");
    address public deviceRegistry = makeAddr("deviceRegistry");
    address public identityRegistry = makeAddr("identityRegistry");
    address public recoveryManager = makeAddr("recoveryManager");

    // Precisamos da chave PRIVADA do device (não só do endereço) pra
    // assinar os userOpHash nos testes — makeAddrAndKey devolve os dois.
    address public device;
    uint256 public deviceKey;

    MockTarget public target;

    function setUp() public {
        (owner, ownerKey) = makeAddrAndKey("owner");

        account = new TruthIDAccount(
            entryPoint, deviceRegistry, identityRegistry, recoveryManager, owner
        );

        (device, deviceKey) = makeAddrAndKey("device");
        vm.prank(owner);
        account.addDevice(device);

        target = new MockTarget();
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

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

    // Variante que NÃO canonicaliza — usada só pra construir de propósito
    // uma assinatura non-canônica (high-s) no teste B4 que confirma que o
    // contrato rejeita esse formato mesmo para o owner.
    function _signNonCanonical(uint256 privateKey, bytes32 userOpHash)
        internal
        returns (bytes memory)
    {
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", userOpHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ethSignedHash);

        // Força high-s: se já veio low-s (caso comum), inverte pra high-s.
        if (uint256(s) <= _SECP256K1N_DIV_2) {
            s = bytes32(_SECP256K1N - uint256(s));
            v = v == 27 ? 28 : 27;
        }

        return abi.encodePacked(r, s, v);
    }

    // -------------------------------------------------------------------------
    // B1 — Constructor e seeding do blockedForDevices
    // -------------------------------------------------------------------------

    function test_Revert_Constructor_ZeroAddress_EntryPoint() public {
        vm.expectRevert(TruthIDAccount.InvalidConstructorArgs.selector);
        new TruthIDAccount(address(0), deviceRegistry, identityRegistry, recoveryManager, owner);
    }

    function test_Revert_Constructor_ZeroAddress_DeviceRegistry() public {
        vm.expectRevert(TruthIDAccount.InvalidConstructorArgs.selector);
        new TruthIDAccount(entryPoint, address(0), identityRegistry, recoveryManager, owner);
    }

    function test_Revert_Constructor_ZeroAddress_IdentityRegistry() public {
        vm.expectRevert(TruthIDAccount.InvalidConstructorArgs.selector);
        new TruthIDAccount(entryPoint, deviceRegistry, address(0), recoveryManager, owner);
    }

    function test_Revert_Constructor_ZeroAddress_RecoveryManager() public {
        vm.expectRevert(TruthIDAccount.InvalidConstructorArgs.selector);
        new TruthIDAccount(entryPoint, deviceRegistry, identityRegistry, address(0), owner);
    }

    function test_Revert_Constructor_ZeroAddress_Owner() public {
        vm.expectRevert(TruthIDAccount.InvalidConstructorArgs.selector);
        new TruthIDAccount(
            entryPoint, deviceRegistry, identityRegistry, recoveryManager, address(0)
        );
    }

    // Confirma que os 3 contratos privilegiados já nascem bloqueados para
    // signers de tier device — trava a correção de segurança da Sessão 53
    // (achado #1 do /code-review: device sequestrando identidade).
    function test_Constructor_SeedsBlockedForDevices() public {
        assertTrue(account.blockedForDevices(deviceRegistry));
        assertTrue(account.blockedForDevices(identityRegistry));
        assertTrue(account.blockedForDevices(recoveryManager));
        // Um endereço qualquer, não semeado, começa desbloqueado.
        assertFalse(account.blockedForDevices(makeAddr("randomContract")));
    }

    // -------------------------------------------------------------------------
    // B2 — addDevice / removeDevice
    // -------------------------------------------------------------------------

    function test_AddDevice_Success_EmitsEvent() public {
        address newDevice = makeAddr("newDevice");

        vm.expectEmit(true, false, false, false);
        emit TruthIDAccount.DeviceAdded(newDevice);

        vm.prank(owner);
        account.addDevice(newDevice);

        assertTrue(account.authorizedDevices(newDevice));
    }

    function test_Revert_AddDevice_NotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(TruthIDAccount.NotAuthorized.selector);
        account.addDevice(makeAddr("newDevice"));
    }

    function test_Revert_AddDevice_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(TruthIDAccount.InvalidDevice.selector);
        account.addDevice(address(0));
    }

    function test_Revert_AddDevice_EqualsOwner() public {
        vm.prank(owner);
        vm.expectRevert(TruthIDAccount.InvalidDevice.selector);
        account.addDevice(owner);
    }

    function test_Revert_AddDevice_AlreadyAuthorized() public {
        // `device` já foi adicionado no setUp.
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(TruthIDAccount.DeviceAlreadyAuthorized.selector, device)
        );
        account.addDevice(device);
    }

    function test_RemoveDevice_Success_EmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit TruthIDAccount.DeviceRemoved(device);

        vm.prank(owner);
        account.removeDevice(device);

        assertFalse(account.authorizedDevices(device));
    }

    function test_Revert_RemoveDevice_NotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(TruthIDAccount.NotAuthorized.selector);
        account.removeDevice(device);
    }

    function test_Revert_RemoveDevice_NotAuthorizedMapping() public {
        address neverAdded = makeAddr("neverAdded");
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(TruthIDAccount.DeviceNotAuthorized.selector, neverAdded)
        );
        account.removeDevice(neverAdded);
    }

    // -------------------------------------------------------------------------
    // B3 — blockDestinationForDevices / unblockDestinationForDevices
    // -------------------------------------------------------------------------

    function test_BlockDestination_EmitsEvent_AndBansDeviceCalls() public {
        address newContract = makeAddr("newPrivilegedContract");

        vm.expectEmit(true, false, false, false);
        emit TruthIDAccount.DestinationBlockedForDevices(newContract);

        vm.prank(owner);
        account.blockDestinationForDevices(newContract);

        assertTrue(account.blockedForDevices(newContract));

        // Device autorizado não consegue mais validar execute() pra esse destino.
        bytes memory callData = abi.encodeCall(TruthIDAccount.execute, (newContract, 0, ""));
        bytes32 userOpHash = keccak256("op-block-test");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    function test_UnblockDestination_EmitsEvent_AndReallows() public {
        address newContract = makeAddr("newPrivilegedContract");

        vm.prank(owner);
        account.blockDestinationForDevices(newContract);

        vm.expectEmit(true, false, false, false);
        emit TruthIDAccount.DestinationUnblockedForDevices(newContract);

        vm.prank(owner);
        account.unblockDestinationForDevices(newContract);

        assertFalse(account.blockedForDevices(newContract));
    }

    function test_Revert_BlockDestination_NotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(TruthIDAccount.NotAuthorized.selector);
        account.blockDestinationForDevices(makeAddr("whatever"));
    }

    function test_Revert_UnblockDestination_NotOwner() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(TruthIDAccount.NotAuthorized.selector);
        account.unblockDestinationForDevices(makeAddr("whatever"));
    }

    // -------------------------------------------------------------------------
    // B4 — validateUserOp, tier owner
    // -------------------------------------------------------------------------

    // O ponto central deste teste: o owner NÃO tem a restrição de destino
    // que os devices têm. Uma UserOp assinada pelo owner mirando um
    // contrato bloqueado (identityRegistry) deve validar com sucesso.
    function test_ValidateUserOp_Owner_AnyCallData_ReturnsSuccess() public {
        bytes memory callData = abi.encodeCall(TruthIDAccount.execute, (identityRegistry, 0, ""));
        bytes32 userOpHash = keccak256("owner-op-any-dest");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(ownerKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_SUCCESS);
    }

    // Assinatura non-canônica (high-s) deve ser rejeitada mesmo vindo do
    // owner — regressão do débito #20 (Sessão 55): a checagem de low-s
    // roda ANTES de identificar quem assinou.
    function test_ValidateUserOp_Owner_SigNonCanonical_Rejected() public {
        bytes32 userOpHash = keccak256("owner-op-non-canonical");
        PackedUserOperation memory userOp = _buildUserOp("");
        userOp.signature = _signNonCanonical(ownerKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // Assinatura válida, mas de uma chave que não é owner nem device
    // autorizado.
    function test_ValidateUserOp_Owner_WrongSigner_Rejected() public {
        (, uint256 randomKey) = makeAddrAndKey("randomSigner");
        bytes32 userOpHash = keccak256("owner-op-wrong-signer");
        PackedUserOperation memory userOp = _buildUserOp("");
        userOp.signature = _sign(randomKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // validateUserOp só pode ser chamado pelo EntryPoint — nem o owner
    // pode chamar diretamente.
    function test_Revert_ValidateUserOp_NotFromEntryPoint() public {
        bytes32 userOpHash = keccak256("op-not-entrypoint");
        PackedUserOperation memory userOp = _buildUserOp("");
        userOp.signature = _sign(ownerKey, userOpHash);

        vm.prank(owner);
        vm.expectRevert(TruthIDAccount.NotEntryPoint.selector);
        account.validateUserOp(userOp, userOpHash, 0);
    }

    // -------------------------------------------------------------------------
    // B5 — validateUserOp, tier device (restrições de calldata)
    // -------------------------------------------------------------------------

    function test_ValidateUserOp_Device_Execute_AllowedDest_Success() public {
        address allowedDest = makeAddr("allowedDest");
        bytes memory callData = abi.encodeCall(TruthIDAccount.execute, (allowedDest, 0, ""));
        bytes32 userOpHash = keccak256("device-op-allowed");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_SUCCESS);
    }

    // Os 3 destinos bloqueados por padrão desde o constructor.
    function test_ValidateUserOp_Device_Execute_BlockedDest_DeviceRegistry_Failed() public {
        _assertDeviceExecuteBlocked(deviceRegistry);
    }

    function test_ValidateUserOp_Device_Execute_BlockedDest_IdentityRegistry_Failed() public {
        _assertDeviceExecuteBlocked(identityRegistry);
    }

    function test_ValidateUserOp_Device_Execute_BlockedDest_RecoveryManager_Failed() public {
        _assertDeviceExecuteBlocked(recoveryManager);
    }

    function _assertDeviceExecuteBlocked(address blockedDest) internal {
        bytes memory callData = abi.encodeCall(TruthIDAccount.execute, (blockedDest, 0, ""));
        bytes32 userOpHash = keccak256(abi.encode("device-op-blocked", blockedDest));
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // Auto-chamada: device tentando execute(address(this), ...) — o
    // próprio achado crítico #1 do /code-review da Sessão 53.
    function test_ValidateUserOp_Device_Execute_AddressThis_Failed() public {
        bytes memory callData = abi.encodeCall(TruthIDAccount.execute, (address(account), 0, ""));
        bytes32 userOpHash = keccak256("device-op-self-call");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // Comportamento atual: se QUALQUER destino do batch está bloqueado, a
    // validação inteira falha (fail-closed) — mesmo que outros destinos no
    // mesmo batch sejam permitidos. Este teste documenta essa decisão de
    // design existente; não é uma mudança de comportamento.
    function test_ValidateUserOp_Device_ExecuteBatch_OneBlockedDest_FailsWholeBatch() public {
        address[] memory dest = new address[](2);
        dest[0] = makeAddr("allowedDest");
        dest[1] = identityRegistry; // bloqueado
        uint256[] memory value = new uint256[](2);
        bytes[] memory func = new bytes[](2);
        func[0] = "";
        func[1] = "";

        bytes memory callData = abi.encodeCall(TruthIDAccount.executeBatch, (dest, value, func));
        bytes32 userOpHash = keccak256("device-op-batch-mixed");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // Device tentando chamar uma função que não é execute/executeBatch
    // diretamente como topo da UserOp (ex: addDevice) — só esses dois
    // seletores são aceitos no tier restrito.
    function test_ValidateUserOp_Device_NonExecuteSelector_Failed() public {
        bytes memory callData = abi.encodeCall(TruthIDAccount.addDevice, (makeAddr("attacker")));
        bytes32 userOpHash = keccak256("device-op-non-execute-selector");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // Calldata menor que 4 bytes — não dá nem pra ler um seletor.
    function test_ValidateUserOp_Device_Execute_ShortCalldata_Failed() public {
        bytes memory callData = abi.encodePacked(bytes3(0xAABBCC));
        bytes32 userOpHash = keccak256("device-op-short-calldata");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(deviceKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // Assinatura criptograficamente válida, mas de uma chave que nunca foi
    // adicionada em `authorizedDevices` — não é owner nem device conhecido.
    function test_ValidateUserOp_Device_NotAuthorizedMapping_Failed() public {
        (, uint256 strangerKey) = makeAddrAndKey("strangerDevice");
        bytes memory callData =
            abi.encodeCall(TruthIDAccount.execute, (makeAddr("allowedDest"), 0, ""));
        bytes32 userOpHash = keccak256("device-op-unknown-signer");
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = _sign(strangerKey, userOpHash);

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, userOpHash, 0);

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

    // --- Regressão do débito #18 (Sessão 55) ---

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

        assertEq(validationData, SIG_VALIDATION_FAILED);
    }

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

        assertEq(validationData, SIG_VALIDATION_SUCCESS);
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

        assertEq(validationData, SIG_VALIDATION_FAILED); // SIG_VALIDATION_FAILED
    }

    // -------------------------------------------------------------------------
    // B9 — vetor conhecido, cruzado com o pipeline mobile (etapa 14.9.4)
    // -------------------------------------------------------------------------

    // Fecha o ciclo da 14.9.4: prova que uma assinatura gerada fora deste
    // contrato — pelo mesmo par (chave, hash) usado nos testes
    // `mobile/test/services/device_key_signature_vector_test.dart` (Dart,
    // `EthPrivateKey.signPersonalMessageToUint8List`) e no script Node com
    // `viem/accounts` `signMessage` — é aceita de verdade por
    // `validateUserOp`. Não é só "parece compatível por inspeção": é a
    // mesma chave (conta #0 padrão do Anvil/Hardhat, pública, sem fundos
    // reais), o mesmo hash e a mesma assinatura, coladas aqui como literais.
    function test_ValidateUserOp_KnownVector_MatchesMobilePipeline() public {
        uint256 knownPrivateKey =
            0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        address knownAddress = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        assertEq(vm.addr(knownPrivateKey), knownAddress, "sanity: chave conhecida");

        bytes32 knownHash = 0x4c0edff4da8c663198f35c78ab485687133310c50c343920b0e24510b2581b37;
        bytes memory knownSignature =
            hex"c957aeb33d6e8289d733442cf9b44fbafc6c1c07fbb71eef974c724cc087deae"
            hex"0a4be53c6a97b8f41e53559d6327017adcf62341fc176583751ab61f1020f855"
            hex"1c";
        assertEq(knownSignature.length, 65);

        vm.prank(owner);
        account.addDevice(knownAddress);

        address allowedDest = makeAddr("allowedDest");
        bytes memory callData = abi.encodeCall(TruthIDAccount.execute, (allowedDest, 0, ""));
        PackedUserOperation memory userOp = _buildUserOp(callData);
        userOp.signature = knownSignature;

        vm.prank(entryPoint);
        uint256 validationData = account.validateUserOp(userOp, knownHash, 0);

        assertEq(validationData, SIG_VALIDATION_SUCCESS);
    }

    // -------------------------------------------------------------------------
    // B6 — emergencyWithdraw
    // -------------------------------------------------------------------------

    function test_EmergencyWithdraw_ByRecoveryManager_TransfersFullBalance() public {
        vm.deal(address(account), 3 ether);
        address recipient = makeAddr("rescueRecipient");

        vm.expectEmit(true, false, false, true);
        emit TruthIDAccount.EmergencyWithdraw(recipient, 3 ether);

        vm.prank(recoveryManager);
        account.emergencyWithdraw(recipient);

        assertEq(address(account).balance, 0);
        assertEq(recipient.balance, 3 ether);
    }

    // Decisão de design deliberada: nem o owner pode chamar essa função —
    // ela existe justamente pro caso em que o owner já perdeu acesso (o
    // próprio motivo do recovery), então a autorização não pode depender
    // dele.
    function test_Revert_EmergencyWithdraw_ByOwner() public {
        vm.deal(address(account), 1 ether);
        vm.prank(owner);
        vm.expectRevert(TruthIDAccount.NotRecoveryManager.selector);
        account.emergencyWithdraw(makeAddr("recipient"));
    }

    function test_Revert_EmergencyWithdraw_ByRandom() public {
        vm.deal(address(account), 1 ether);
        vm.prank(makeAddr("random"));
        vm.expectRevert(TruthIDAccount.NotRecoveryManager.selector);
        account.emergencyWithdraw(makeAddr("recipient"));
    }

    function test_Revert_EmergencyWithdraw_ZeroRecipient() public {
        vm.deal(address(account), 1 ether);
        vm.prank(recoveryManager);
        vm.expectRevert(TruthIDAccount.InvalidRecipient.selector);
        account.emergencyWithdraw(address(0));
    }

    // -------------------------------------------------------------------------
    // B7 — execute / executeBatch (camada de execução, não validação)
    // -------------------------------------------------------------------------

    // Nota importante: a restrição de tier (owner vs device) vive só em
    // `validateUserOp` — quem chama `execute` diretamente (owner, EntryPoint
    // ou a própria conta) não passa por essa checagem de novo. É o
    // EntryPoint quem garante, no fluxo real, que só chama `execute` depois
    // de `validateUserOp` já ter aprovado a UserOp.
    function test_Execute_ByOwner_CallsTarget() public {
        vm.prank(owner);
        account.execute(address(target), 0, abi.encodeCall(MockTarget.ping, ()));

        assertEq(target.callCount(), 1);
    }

    function test_Execute_ByEntryPoint_CallsTarget() public {
        vm.prank(entryPoint);
        account.execute(address(target), 0, abi.encodeCall(MockTarget.ping, ()));

        assertEq(target.callCount(), 1);
    }

    function test_Revert_Execute_ByRandom() public {
        vm.prank(makeAddr("random"));
        vm.expectRevert(TruthIDAccount.NotAuthorized.selector);
        account.execute(address(target), 0, abi.encodeCall(MockTarget.ping, ()));
    }

    function test_Revert_ExecuteBatch_LengthMismatch() public {
        address[] memory dest = new address[](2);
        dest[0] = address(target);
        dest[1] = address(target);
        uint256[] memory value = new uint256[](1); // tamanho diferente de propósito
        value[0] = 0;
        bytes[] memory func = new bytes[](2);
        func[0] = "";
        func[1] = "";

        vm.prank(owner);
        vm.expectRevert(TruthIDAccount.ArrayLengthMismatch.selector);
        account.executeBatch(dest, value, func);
    }

    function test_ExecuteBatch_ByOwner_AllCallsExecuted() public {
        address[] memory dest = new address[](2);
        dest[0] = address(target);
        dest[1] = address(target);
        uint256[] memory value = new uint256[](2);
        bytes[] memory func = new bytes[](2);
        func[0] = abi.encodeCall(MockTarget.ping, ());
        func[1] = abi.encodeCall(MockTarget.ping, ());

        vm.prank(owner);
        account.executeBatch(dest, value, func);

        assertEq(target.callCount(), 2);
    }

    // -------------------------------------------------------------------------
    // B8 — receive()
    // -------------------------------------------------------------------------

    function test_Receive_AcceptsEth() public {
        (bool success,) = payable(address(account)).call{value: 1 ether}("");
        assertTrue(success);
        assertEq(address(account).balance, 1 ether);
    }
}
