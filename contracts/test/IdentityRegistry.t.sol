// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {TruthIDAccountFactory} from "../src/TruthIDAccountFactory.sol";
import {ENTRY_POINT_V07} from "../src/ERC4337Constants.sol";
import {IdentityConsentHelper} from "./IdentityConsentHelper.sol";

contract IdentityRegistryTest is Test, IdentityConsentHelper {
    IdentityRegistry public registry;

    // Endereços fictícios para simular usuários nos testes. Precisam de chave
    // privada (makeAddrAndKey, não makeAddr) desde o débito #17: createIdentity
    // agora exige uma assinatura de consentimento do controller.
    address alice;
    uint256 aliceKey;
    address bob;
    uint256 bobKey;

    // setUp() roda antes de CADA teste — garante que cada teste começa limpo
    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        registry = new IdentityRegistry();
    }

    // -----------------------------------------------------------------
    // Criação de identidade
    // -----------------------------------------------------------------

    function test_CreateIdentity_Success() public {
        // vm.prank: "finge" que a próxima chamada vem do endereço alice
        vm.prank(alice);
        uint256 id = _createIdentity(registry, aliceKey, "alice.id");

        assertEq(id, 1); // primeiro ID deve ser 1

        IdentityRegistry.Identity memory identity = registry.getIdentity("alice.id");
        assertEq(identity.id, 1);
        assertEq(identity.username, "alice.id");
        assertEq(identity.controller, alice);
    }

    function test_CreateIdentity_EmitsEvent() public {
        // vm.expectEmit: verifica que o evento foi emitido com os valores certos
        vm.expectEmit(true, true, false, true);
        emit IdentityRegistry.IdentityCreated(1, "alice.id", alice);

        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");
    }

    function test_CreateIdentity_IncrementsId() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(bob);
        uint256 bobId = _createIdentity(registry, bobKey, "bob.id");

        assertEq(bobId, 2);
        assertEq(registry.totalIdentities(), 2);
    }

    function test_CreateIdentity_MapsControllerToUsername() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        string memory found = registry.getUsernameByController(alice);
        assertEq(found, "alice.id");
    }

    // O controller pode ser qualquer endereço que consinta — não precisa ser
    // quem paga o gas. Aqui alice paga a transação, mas quem assina o
    // consentimento (e vira controller) é um terceiro endereço.
    function test_CreateIdentity_ControllerCanDifferFromCaller() public {
        (address controllerAddr, uint256 controllerKey) = makeAddrAndKey("controllerNotCaller");

        vm.prank(alice); // alice paga o gas; controllerAddr assina e vira controller
        _createIdentity(registry, controllerKey, "alice.id");

        IdentityRegistry.Identity memory identity = registry.getIdentity("alice.id");
        assertEq(identity.controller, controllerAddr);
        assertEq(registry.getUsernameByController(controllerAddr), "alice.id");
        assertEq(registry.getUsernameByController(alice), ""); // alice NÃO é o controller
    }

    // -----------------------------------------------------------------
    // Validação de username
    // -----------------------------------------------------------------
    // _validateUsername roda ANTES da checagem de assinatura em createIdentity,
    // então esses testes não precisam de uma assinatura válida — qualquer
    // v/r/s serve, o revert acontece antes de a assinatura ser sequer olhada.

    function test_Revert_EmptyUsername() public {
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity("", alice, 0, bytes32(0), bytes32(0));
    }

    function test_Revert_UsernameTooLong() public {
        // 65 caracteres — acima do limite de 64
        string memory long = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity(long, alice, 0, bytes32(0), bytes32(0));
    }

    function test_Revert_UsernameWithUppercase() public {
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity("Alice.id", alice, 0, bytes32(0), bytes32(0));
    }

    function test_Revert_UsernameWithSpace() public {
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity("alice id", alice, 0, bytes32(0), bytes32(0));
    }

    function test_ValidUsername_WithDotAndHyphen() public {
        vm.prank(alice);
        uint256 id = _createIdentity(registry, aliceKey, "alice-123.id");
        assertEq(id, 1);
    }

    // -----------------------------------------------------------------
    // Regras de negócio
    // -----------------------------------------------------------------

    function test_Revert_UsernameTaken() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.UsernameTaken.selector, "alice.id"));
        _createIdentity(registry, bobKey, "alice.id");
    }

    function test_Revert_AddressAlreadyHasIdentity() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.AddressAlreadyHasIdentity.selector, alice)
        );
        _createIdentity(registry, aliceKey, "alice2.id"); // mesmo controller → falha
    }

    function test_Revert_CreateIdentity_ZeroController() public {
        vm.expectRevert(IdentityRegistry.InvalidNewController.selector);
        registry.createIdentity("alice.id", address(0), 0, bytes32(0), bytes32(0));
    }

    function test_Revert_GetNonexistentIdentity() public {
        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.IdentityNotFound.selector, "nobody.id")
        );
        registry.getIdentity("nobody.id");
    }

    // -----------------------------------------------------------------
    // Consentimento (débito #17) — controller EOA assina por si mesmo
    // -----------------------------------------------------------------

    function test_Revert_CreateIdentity_WrongSigner() public {
        // attacker tenta registrar o endereço de alice como controller, mas
        // assina com a PRÓPRIA chave — nem bate com o controller (alice),
        // nem existe factory configurada pra checar via CREATE2.
        (, uint256 attackerKey) = makeAddrAndKey("attacker");
        (uint8 v, bytes32 r, bytes32 s) = _signConsent(registry, attackerKey, "alice.id", alice);

        vm.expectRevert(IdentityRegistry.InvalidConsentSignature.selector);
        registry.createIdentity("alice.id", alice, v, r, s);
    }

    function test_Revert_CreateIdentity_InvalidV() public {
        (, bytes32 r, bytes32 s) = _signConsent(registry, aliceKey, "alice.id", alice);
        vm.expectRevert(IdentityRegistry.InvalidConsentSignature.selector);
        registry.createIdentity("alice.id", alice, 26, r, s);
    }

    function test_Revert_CreateIdentity_SignatureForDifferentUsername() public {
        // Assinatura válida para "alice.id", usada para tentar registrar "eve.id".
        (uint8 v, bytes32 r, bytes32 s) = _signConsent(registry, aliceKey, "alice.id", alice);

        vm.expectRevert(IdentityRegistry.InvalidConsentSignature.selector);
        registry.createIdentity("eve.id", alice, v, r, s);
    }

    function test_Revert_CreateIdentity_SignatureForDifferentController() public {
        // Assinatura de alice válida para (alice.id, alice), usada com um
        // controller diferente do assinado.
        (uint8 v, bytes32 r, bytes32 s) = _signConsent(registry, aliceKey, "alice.id", alice);

        vm.expectRevert(IdentityRegistry.InvalidConsentSignature.selector);
        registry.createIdentity("alice.id", bob, v, r, s);
    }

    // -----------------------------------------------------------------
    // Consentimento (débito #17) — controller é smart account pré-deploy,
    // verificado via factory (integração real com TruthIDAccountFactory)
    // -----------------------------------------------------------------

    function _deployFactory() internal returns (TruthIDAccountFactory) {
        address deviceRegistry = makeAddr("deviceRegistry");
        address recoveryManager = makeAddr("recoveryManager");
        return new TruthIDAccountFactory(
            ENTRY_POINT_V07, deviceRegistry, address(registry), recoveryManager
        );
    }

    function test_CreateIdentity_Consent_SmartAccountViaFactory() public {
        TruthIDAccountFactory factory = _deployFactory();
        registry.setFactory(address(factory));

        address predictedAccount = factory.getAddress(alice, 0);
        (uint8 v, bytes32 r, bytes32 s) =
            _signConsent(registry, aliceKey, "alice.id", predictedAccount);

        uint256 id = registry.createIdentity("alice.id", predictedAccount, v, r, s);

        IdentityRegistry.Identity memory identity = registry.getIdentity("alice.id");
        assertEq(id, 1);
        assertEq(identity.controller, predictedAccount);
        assertEq(registry.getUsernameByController(predictedAccount), "alice.id");
    }

    function test_Revert_CreateIdentity_SmartAccount_WithoutFactoryConfigured() public {
        // Mesma assinatura que seria válida SE a factory estivesse configurada
        // — mas _factory ainda é address(0) (padrão fail-closed).
        TruthIDAccountFactory factory = _deployFactory();
        address predictedAccount = factory.getAddress(alice, 0);
        (uint8 v, bytes32 r, bytes32 s) =
            _signConsent(registry, aliceKey, "alice.id", predictedAccount);

        vm.expectRevert(IdentityRegistry.InvalidConsentSignature.selector);
        registry.createIdentity("alice.id", predictedAccount, v, r, s);
    }

    // -----------------------------------------------------------------
    // setFactory
    // -----------------------------------------------------------------

    function test_Revert_SetFactory_NotOwner() public {
        vm.prank(alice); // alice não é quem fez o deploy do registry
        vm.expectRevert(IdentityRegistry.NotOwner.selector);
        registry.setFactory(makeAddr("factory"));
    }

    function test_SetFactory_OwnerCanCall() public {
        address factoryAddr = makeAddr("factory");
        registry.setFactory(factoryAddr);
    }

    function test_SetFactory_NotOneShot() public {
        // Diferente de setRecoveryManager, setFactory pode ser chamada mais
        // de uma vez — a factory já foi redeployada 2x no histórico real do
        // projeto por motivos de gas/limpeza, sem relação com identidade.
        registry.setFactory(makeAddr("factoryV1"));
        registry.setFactory(makeAddr("factoryV2")); // não deve reverter
    }

    function test_SetFactory_EmitsEvent() public {
        address factoryAddr = makeAddr("factory");
        vm.expectEmit(true, false, false, true);
        emit IdentityRegistry.FactorySet(factoryAddr);
        registry.setFactory(factoryAddr);
    }

    // -----------------------------------------------------------------
    // Transferência de controller
    // -----------------------------------------------------------------

    function test_TransferController_Success() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(alice);
        registry.transferController("alice.id", bob);

        IdentityRegistry.Identity memory identity = registry.getIdentity("alice.id");
        assertEq(identity.controller, bob);
        assertEq(registry.getUsernameByController(bob), "alice.id");
        assertEq(registry.getUsernameByController(alice), ""); // alice não tem mais username
    }

    function test_TransferController_EmitsEvent() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(alice);
        vm.expectEmit(false, true, true, true);
        emit IdentityRegistry.ControllerTransferred("alice.id", alice, bob);
        registry.transferController("alice.id", bob);
    }

    function test_Revert_TransferController_NotController() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(bob); // bob tenta transferir, mas não é o controller
        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.NotController.selector, bob, "alice.id")
        );
        registry.transferController("alice.id", bob);
    }

    function test_Revert_TransferController_NewControllerAlreadyHasIdentity() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(bob);
        _createIdentity(registry, bobKey, "bob.id");

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.AddressAlreadyHasIdentity.selector, bob)
        );
        registry.transferController("alice.id", bob);
    }

    function test_Revert_TransferController_ToZeroAddress() public {
        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidNewController.selector);
        registry.transferController("alice.id", address(0));
    }

    // -----------------------------------------------------------------
    // setRecoveryManager — controle de acesso (achado crítico da auditoria)
    // -----------------------------------------------------------------

    function test_Revert_SetRecoveryManager_NotOwner() public {
        // registry foi deployado pelo contrato de teste (setUp) — owner é address(this)
        vm.prank(alice); // alice não é quem fez o deploy
        vm.expectRevert(IdentityRegistry.NotOwner.selector);
        registry.setRecoveryManager(bob);
    }

    function test_SetRecoveryManager_OwnerCanCall() public {
        // address(this) é o owner, pois foi quem chamou `new IdentityRegistry()` no setUp
        registry.setRecoveryManager(bob);
        // segunda chamada (mesmo pelo owner) deve reverter — já foi setado
        vm.expectRevert(IdentityRegistry.RecoveryManagerAlreadySet.selector);
        registry.setRecoveryManager(bob);
    }

    function test_Owner_IsDeployer() public view {
        assertEq(registry.owner(), address(this));
    }

    // -----------------------------------------------------------------
    // isUsernameTaken
    // -----------------------------------------------------------------

    function test_IsUsernameTaken() public {
        assertFalse(registry.isUsernameTaken("alice.id"));

        vm.prank(alice);
        _createIdentity(registry, aliceKey, "alice.id");

        assertTrue(registry.isUsernameTaken("alice.id"));
    }

    // -----------------------------------------------------------------
    // getIdentityIdByController
    // -----------------------------------------------------------------

    function test_GetIdentityIdByController_Success() public {
        vm.prank(alice);
        uint256 id = _createIdentity(registry, aliceKey, "alice.id");

        assertEq(registry.getIdentityIdByController(alice), id);
    }

    function test_GetIdentityIdByController_ReturnsZeroWhenNotFound() public {
        assertEq(registry.getIdentityIdByController(alice), 0);
    }
}
