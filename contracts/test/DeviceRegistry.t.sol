// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";

contract DeviceRegistryTest is Test {
    IdentityRegistry public identityRegistry;
    DeviceRegistry public deviceRegistry;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie"); // nunca cria identidade

    // Endereços simulando chaves públicas de devices
    address public aliceDevice1 = makeAddr("alice-device-1");
    address public aliceDevice2 = makeAddr("alice-device-2");
    address public bobDevice1 = makeAddr("bob-device-1");

    // setUp() roda antes de cada teste — estado isolado por teste
    function setUp() public {
        identityRegistry = new IdentityRegistry();
        deviceRegistry = new DeviceRegistry(address(identityRegistry));

        vm.prank(alice);
        identityRegistry.createIdentity("alice.id"); // identityId = 1

        vm.prank(bob);
        identityRegistry.createIdentity("bob.id"); // identityId = 2
    }

    // -----------------------------------------------------------------
    // registerDevice — caminho feliz
    // -----------------------------------------------------------------

    function test_RegisterDevice_Success() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        assertTrue(deviceRegistry.isDeviceActive(aliceDevice1));

        DeviceRegistry.Device memory device = deviceRegistry.getDevice(aliceDevice1);
        assertEq(device.identityId, 1);
        assertEq(device.pubKey, aliceDevice1);
        assertEq(device.label, "iPhone 15 Pro");
        assertFalse(device.revoked);
        assertTrue(device.exists);
    }

    function test_RegisterDevice_MultipleDevicesForSameIdentity() public {
        vm.startPrank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");
        deviceRegistry.registerDevice(aliceDevice2, "MacBook Pro");
        vm.stopPrank();

        assertEq(deviceRegistry.deviceCount(1), 2);
        assertTrue(deviceRegistry.isDeviceActive(aliceDevice1));
        assertTrue(deviceRegistry.isDeviceActive(aliceDevice2));
    }

    function test_RegisterDevice_DifferentIdentitiesIndependent() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "Alice's phone");

        vm.prank(bob);
        deviceRegistry.registerDevice(bobDevice1, "Bob's phone");

        assertEq(deviceRegistry.deviceCount(1), 1); // alice: 1 device
        assertEq(deviceRegistry.deviceCount(2), 1); // bob: 1 device
    }

    function test_RegisterDevice_EmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit DeviceRegistry.DeviceRegistered(1, aliceDevice1, "iPhone 15 Pro");
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");
    }

    // -----------------------------------------------------------------
    // registerDevice — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_RegisterDevice_NoIdentity() public {
        vm.prank(charlie);
        vm.expectRevert(DeviceRegistry.NotIdentityController.selector);
        deviceRegistry.registerDevice(makeAddr("charlie-device"), "iPad");
    }

    function test_Revert_RegisterDevice_AlreadyRegistered() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DeviceRegistry.DeviceAlreadyRegistered.selector, aliceDevice1)
        );
        deviceRegistry.registerDevice(aliceDevice1, "Duplicado");
    }

    function test_Revert_RegisterDevice_InvalidPubKey() public {
        vm.prank(alice);
        vm.expectRevert(DeviceRegistry.InvalidPubKey.selector);
        deviceRegistry.registerDevice(address(0), "Device invalido");
    }

    // -----------------------------------------------------------------
    // revokeDevice — caminho feliz
    // -----------------------------------------------------------------

    function test_RevokeDevice_Success() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        assertTrue(deviceRegistry.isDeviceActive(aliceDevice1));

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

        assertFalse(deviceRegistry.isDeviceActive(aliceDevice1));

        // Device ainda existe no storage, só está marcado como revogado
        DeviceRegistry.Device memory device = deviceRegistry.getDevice(aliceDevice1);
        assertTrue(device.revoked);
        assertTrue(device.exists);
    }

    function test_RevokeDevice_EmitsEvent() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit DeviceRegistry.DeviceRevoked(1, aliceDevice1);
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    function test_RevokeDevice_DoesNotAffectOtherDevices() public {
        vm.startPrank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");
        deviceRegistry.registerDevice(aliceDevice2, "MacBook Pro");
        deviceRegistry.revokeDevice(aliceDevice1);
        vm.stopPrank();

        assertFalse(deviceRegistry.isDeviceActive(aliceDevice1));
        assertTrue(deviceRegistry.isDeviceActive(aliceDevice2));
    }

    // -----------------------------------------------------------------
    // revokeDevice — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_RevokeDevice_NotFound() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DeviceRegistry.DeviceNotFound.selector, aliceDevice1)
        );
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    function test_Revert_RevokeDevice_AlreadyRevoked() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DeviceRegistry.DeviceAlreadyRevoked.selector, aliceDevice1)
        );
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    function test_Revert_RevokeDevice_NotController() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        // Bob tenta revogar o device da Alice — não é o controller da identidade dona do device
        vm.prank(bob);
        vm.expectRevert(DeviceRegistry.NotIdentityController.selector);
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    function test_Revert_RevokeDevice_NoIdentity() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        // Charlie não tem identidade
        vm.prank(charlie);
        vm.expectRevert(DeviceRegistry.NotIdentityController.selector);
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    // -----------------------------------------------------------------
    // isDeviceActive
    // -----------------------------------------------------------------

    function test_IsDeviceActive_ReturnsFalseForNonExistent() public view {
        assertFalse(deviceRegistry.isDeviceActive(aliceDevice1));
    }

    function test_IsDeviceActive_ReturnsTrueForActive() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");
        assertTrue(deviceRegistry.isDeviceActive(aliceDevice1));
    }

    function test_IsDeviceActive_ReturnsFalseForRevoked() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

        assertFalse(deviceRegistry.isDeviceActive(aliceDevice1));
    }

    // -----------------------------------------------------------------
    // getDevice
    // -----------------------------------------------------------------

    function test_GetDevice_Success() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        DeviceRegistry.Device memory device = deviceRegistry.getDevice(aliceDevice1);
        assertEq(device.identityId, 1);
        assertEq(device.pubKey, aliceDevice1);
        assertEq(device.label, "iPhone 15 Pro");
        assertEq(device.addedAt, block.timestamp);
        assertFalse(device.revoked);
    }

    function test_Revert_GetDevice_NotFound() public {
        vm.expectRevert(
            abi.encodeWithSelector(DeviceRegistry.DeviceNotFound.selector, aliceDevice1)
        );
        deviceRegistry.getDevice(aliceDevice1);
    }

    // -----------------------------------------------------------------
    // getDevicesByIdentity
    // -----------------------------------------------------------------

    function test_GetDevicesByIdentity_ReturnsAllDevices() public {
        vm.startPrank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");
        deviceRegistry.registerDevice(aliceDevice2, "MacBook Pro");
        vm.stopPrank();

        address[] memory devices = deviceRegistry.getDevicesByIdentity(1);
        assertEq(devices.length, 2);
        assertEq(devices[0], aliceDevice1);
        assertEq(devices[1], aliceDevice2);
    }

    function test_GetDevicesByIdentity_IncludesRevoked() public {
        vm.startPrank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");
        deviceRegistry.registerDevice(aliceDevice2, "MacBook Pro");
        deviceRegistry.revokeDevice(aliceDevice1);
        vm.stopPrank();

        // Revogados continuam na lista — o caller usa isDeviceActive para filtrar
        address[] memory devices = deviceRegistry.getDevicesByIdentity(1);
        assertEq(devices.length, 2);
    }

    function test_GetDevicesByIdentity_EmptyForNoDevices() public view {
        address[] memory devices = deviceRegistry.getDevicesByIdentity(1);
        assertEq(devices.length, 0);
    }

    // -----------------------------------------------------------------
    // deviceCount
    // -----------------------------------------------------------------

    function test_DeviceCount_StartsAtZero() public view {
        assertEq(deviceRegistry.deviceCount(1), 0);
    }

    function test_DeviceCount_IncrementsOnRegister() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");
        assertEq(deviceRegistry.deviceCount(1), 1);

        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice2, "MacBook Pro");
        assertEq(deviceRegistry.deviceCount(1), 2);
    }

    function test_DeviceCount_DoesNotDecrementOnRevoke() public {
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

        // Revogação não remove da lista, só marca como revogado
        assertEq(deviceRegistry.deviceCount(1), 1);
    }
}
