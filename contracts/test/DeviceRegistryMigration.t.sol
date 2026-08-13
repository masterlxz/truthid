// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";
import {IdentityResolver} from "../src/IdentityResolver.sol";
import {IdentityConsentHelper} from "./IdentityConsentHelper.sol";

// Débito #52 — testa `DeviceRegistry.migrateDevices`, a função que porta o
// histórico de devices de uma cascata de redeploy anterior sem exigir
// re-pareamento físico de cada device. Par "legado" simulado no próprio
// teste: um segundo `IdentityRegistry`/`DeviceRegistry`, criado e populado
// ANTES do par "novo" (o que está sob teste) — reproduz o cenário real de
// uma cascata, inclusive o controller mudando de endereço entre os dois
// (a smart account muda porque o CREATE2 depende do endereço da factory).
contract DeviceRegistryMigrationTest is Test, IdentityConsentHelper {
    IdentityRegistry legacyIdentityRegistry;
    DeviceRegistry legacyDeviceRegistry;

    IdentityRegistry newIdentityRegistry;
    DeviceRegistry newDeviceRegistry;

    uint256 legacyControllerKey;
    address legacyController;
    uint256 newControllerKey;
    address newController;

    address device1 = makeAddr("device-1"); // ativo, com vault key
    address device2 = makeAddr("device-2"); // revogado
    address device3 = makeAddr("device-3"); // ativo, sem vault key

    bytes32 constant SALT = keccak256("migration-test-salt");

    function setUp() public {
        (legacyController, legacyControllerKey) = makeAddrAndKey("legacy-controller");
        (newController, newControllerKey) = makeAddrAndKey("new-controller");

        // --- Par legado, já populado com 3 devices ---
        legacyIdentityRegistry = new IdentityRegistry();
        legacyDeviceRegistry =
            new DeviceRegistry(address(legacyIdentityRegistry), address(0), address(0));

        _createIdentity(legacyIdentityRegistry, legacyControllerKey, "alice.id");

        _registerLegacyDevice(device1, "iPhone 15 Pro", hex"aabbccdd");
        vm.warp(block.timestamp + 1 days);
        _registerLegacyDevice(device2, "MacBook antigo", "");
        vm.prank(legacyController);
        legacyDeviceRegistry.revokeDevice(device2);
        vm.warp(block.timestamp + 1 days);
        _registerLegacyDevice(device3, "iPad", "");

        // --- Par novo, com o mesmo username mas controller diferente ---
        newIdentityRegistry = new IdentityRegistry();
        newDeviceRegistry = new DeviceRegistry(
            address(newIdentityRegistry),
            address(legacyDeviceRegistry),
            address(legacyIdentityRegistry)
        );
        _createIdentity(newIdentityRegistry, newControllerKey, "alice.id");
    }

    function _registerLegacyDevice(address devicePubKey, string memory label, bytes memory vaultKey)
        internal
    {
        bytes32 commitment = keccak256(abi.encodePacked(devicePubKey, SALT, legacyController));
        vm.prank(legacyController);
        legacyDeviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);
        vm.prank(legacyController);
        legacyDeviceRegistry.registerDevice(devicePubKey, label, SALT, vaultKey);
    }

    // -----------------------------------------------------------------
    // migrateDevices — caminho feliz
    // -----------------------------------------------------------------

    function test_MigrateDevices_CopiesAllDevices() public {
        vm.prank(newController);
        newDeviceRegistry.migrateDevices();

        assertEq(newDeviceRegistry.deviceCount(1), 3);
        address[] memory devices = newDeviceRegistry.getDevicesByIdentity(1);
        assertEq(devices[0], device1);
        assertEq(devices[1], device2);
        assertEq(devices[2], device3);
    }

    function test_MigrateDevices_PreservesLabelAddedAtAndRevokedStatus() public {
        DeviceRegistry.Device memory legacy1 = legacyDeviceRegistry.getDevice(device1);
        DeviceRegistry.Device memory legacy2 = legacyDeviceRegistry.getDevice(device2);

        vm.prank(newController);
        newDeviceRegistry.migrateDevices();

        DeviceRegistry.Device memory migrated1 = newDeviceRegistry.getDevice(device1);
        assertEq(migrated1.identityId, 1); // identityId do registry NOVO, não do legado
        assertEq(migrated1.label, "iPhone 15 Pro");
        assertEq(migrated1.addedAt, legacy1.addedAt);
        assertFalse(migrated1.revoked);

        DeviceRegistry.Device memory migrated2 = newDeviceRegistry.getDevice(device2);
        assertEq(migrated2.addedAt, legacy2.addedAt);
        assertTrue(migrated2.revoked);
        assertFalse(newDeviceRegistry.isDeviceActive(device2));
    }

    function test_MigrateDevices_PreservesVaultKeys() public {
        vm.prank(newController);
        newDeviceRegistry.migrateDevices();

        assertEq(newDeviceRegistry.deviceVaultKeys(device1), hex"aabbccdd");
        assertEq(newDeviceRegistry.deviceVaultKeys(device3).length, 0);
    }

    function test_MigrateDevices_EmitsEvents() public {
        // vm.expectEmit checa cada expectativa contra o próximo log emitido,
        // em ordem estrita — precisa cobrir os 4 eventos na sequência exata
        // em que migrateDevices() os emite (1 DeviceRegistered por device,
        // na ordem do array legado, seguido de 1 DevicesMigrated).
        vm.prank(newController);

        vm.expectEmit(true, true, false, true);
        emit DeviceRegistry.DeviceRegistered(1, device1, "iPhone 15 Pro", hex"aabbccdd");
        vm.expectEmit(true, true, false, true);
        emit DeviceRegistry.DeviceRegistered(1, device2, "MacBook antigo", "");
        vm.expectEmit(true, true, false, true);
        emit DeviceRegistry.DeviceRegistered(1, device3, "iPad", "");
        vm.expectEmit(true, false, false, true);
        emit DeviceRegistry.DevicesMigrated(1, 3);

        newDeviceRegistry.migrateDevices();
    }

    // -----------------------------------------------------------------
    // migrateDevices — reexecução e guardas
    // -----------------------------------------------------------------

    function test_Revert_MigrateDevices_AlreadyMigrated() public {
        vm.prank(newController);
        newDeviceRegistry.migrateDevices();

        vm.prank(newController);
        vm.expectRevert(abi.encodeWithSelector(DeviceRegistry.AlreadyMigrated.selector, uint256(1)));
        newDeviceRegistry.migrateDevices();
    }

    function test_Revert_MigrateDevices_NoIdentityOnNewRegistry() public {
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(IdentityResolver.NotIdentityController.selector);
        newDeviceRegistry.migrateDevices();
    }

    function test_Revert_MigrateDevices_NoMatchingLegacyIdentity() public {
        (uint256 bobKey, address bob) = _makeBob();
        _createIdentity(newIdentityRegistry, bobKey, "bob.id"); // nunca existiu no legado

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IdentityRegistry.IdentityNotFound.selector, "bob.id")
        );
        newDeviceRegistry.migrateDevices();
    }

    function test_Revert_MigrateDevices_DisabledWhenLegacyAddressesZero() public {
        DeviceRegistry freshDeviceRegistry =
            new DeviceRegistry(address(newIdentityRegistry), address(0), address(0));

        vm.prank(newController);
        vm.expectRevert(DeviceRegistry.MigrationDisabled.selector);
        freshDeviceRegistry.migrateDevices();
    }

    function test_MigrateDevices_SkipsDeviceAlreadyRegisteredOnNewRegistry() public {
        // device3 já foi re-pareado organicamente no registry novo ANTES da
        // migração rodar — não deve ser sobrescrito nem duplicado.
        bytes32 commitment = keccak256(abi.encodePacked(device3, SALT, newController));
        vm.prank(newController);
        newDeviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);
        vm.prank(newController);
        newDeviceRegistry.registerDevice(device3, "iPad (repareado)", SALT, "");

        vm.prank(newController);
        newDeviceRegistry.migrateDevices();

        // device1 e device2 vieram da migração, device3 permanece como foi
        // re-pareado — 3 no total, sem duplicata.
        assertEq(newDeviceRegistry.deviceCount(1), 3);
        DeviceRegistry.Device memory device = newDeviceRegistry.getDevice(device3);
        assertEq(device.label, "iPad (repareado)");
    }

    function _makeBob() internal returns (uint256 bobKey, address bob) {
        (bob, bobKey) = makeAddrAndKey("bob");
    }
}
