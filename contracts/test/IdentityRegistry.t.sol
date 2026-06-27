// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistry public registry;

    // Endereços fictícios para simular usuários nos testes
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    // setUp() roda antes de CADA teste — garante que cada teste começa limpo
    function setUp() public {
        registry = new IdentityRegistry();
    }

    // -----------------------------------------------------------------
    // Criação de identidade
    // -----------------------------------------------------------------

    function test_CreateIdentity_Success() public {
        // vm.prank: "finge" que a próxima chamada vem do endereço alice
        vm.prank(alice);
        uint256 id = registry.createIdentity("alice.id");

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
        registry.createIdentity("alice.id");
    }

    function test_CreateIdentity_IncrementsId() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        vm.prank(bob);
        uint256 bobId = registry.createIdentity("bob.id");

        assertEq(bobId, 2);
        assertEq(registry.totalIdentities(), 2);
    }

    function test_CreateIdentity_MapsControllerToUsername() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        string memory found = registry.getUsernameByController(alice);
        assertEq(found, "alice.id");
    }

    // -----------------------------------------------------------------
    // Validação de username
    // -----------------------------------------------------------------

    function test_Revert_EmptyUsername() public {
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity("");
    }

    function test_Revert_UsernameTooLong() public {
        // 65 caracteres — acima do limite de 64
        string memory long = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity(long);
    }

    function test_Revert_UsernameWithUppercase() public {
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity("Alice.id");
    }

    function test_Revert_UsernameWithSpace() public {
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.InvalidUsername.selector);
        registry.createIdentity("alice id");
    }

    function test_ValidUsername_WithDotAndHyphen() public {
        vm.prank(alice);
        uint256 id = registry.createIdentity("alice-123.id");
        assertEq(id, 1);
    }

    // -----------------------------------------------------------------
    // Regras de negócio
    // -----------------------------------------------------------------

    function test_Revert_UsernameTaken() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.UsernameTaken.selector, "alice.id"));
        registry.createIdentity("alice.id");
    }

    function test_Revert_AddressAlreadyHasIdentity() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.AddressAlreadyHasIdentity.selector, alice));
        registry.createIdentity("alice2.id");
    }

    function test_Revert_GetNonexistentIdentity() public {
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.IdentityNotFound.selector, "nobody.id"));
        registry.getIdentity("nobody.id");
    }

    // -----------------------------------------------------------------
    // Transferência de controller
    // -----------------------------------------------------------------

    function test_TransferController_Success() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        vm.prank(alice);
        registry.transferController("alice.id", bob);

        IdentityRegistry.Identity memory identity = registry.getIdentity("alice.id");
        assertEq(identity.controller, bob);
        assertEq(registry.getUsernameByController(bob), "alice.id");
        assertEq(registry.getUsernameByController(alice), ""); // alice não tem mais username
    }

    function test_TransferController_EmitsEvent() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        vm.prank(alice);
        vm.expectEmit(false, true, true, true);
        emit IdentityRegistry.ControllerTransferred("alice.id", alice, bob);
        registry.transferController("alice.id", bob);
    }

    function test_Revert_TransferController_NotController() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        vm.prank(bob); // bob tenta transferir, mas não é o controller
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.NotController.selector, bob, "alice.id"));
        registry.transferController("alice.id", bob);
    }

    function test_Revert_TransferController_NewControllerAlreadyHasIdentity() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

        vm.prank(bob);
        registry.createIdentity("bob.id");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IdentityRegistry.AddressAlreadyHasIdentity.selector, bob));
        registry.transferController("alice.id", bob);
    }

    function test_Revert_TransferController_ToZeroAddress() public {
        vm.prank(alice);
        registry.createIdentity("alice.id");

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
        registry.createIdentity("alice.id");

        assertTrue(registry.isUsernameTaken("alice.id"));
    }
}
