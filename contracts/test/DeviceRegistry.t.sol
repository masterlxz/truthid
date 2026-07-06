// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";
import {IdentityResolver} from "../src/IdentityResolver.sol";
import {IdentityConsentHelper} from "./IdentityConsentHelper.sol";

contract DeviceRegistryTest is Test, IdentityConsentHelper {
    IdentityRegistry public identityRegistry;
    DeviceRegistry public deviceRegistry;

    address public alice;
    uint256 aliceKey;
    address public bob;
    uint256 bobKey;
    address public charlie = makeAddr("charlie"); // nunca cria identidade

    // Endereços simulando chaves públicas de devices
    address public aliceDevice1 = makeAddr("alice-device-1");
    address public aliceDevice2 = makeAddr("alice-device-2");
    address public bobDevice1 = makeAddr("bob-device-1");

    // Salt fixo para os testes — o que importa é que cada commitment seja
    // único por (devicePubKey, salt, msg.sender), não que o salt seja secreto.
    bytes32 constant SALT = keccak256("test-salt");

    // setUp() roda antes de cada teste — estado isolado por teste
    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");

        identityRegistry = new IdentityRegistry();
        deviceRegistry = new DeviceRegistry(address(identityRegistry));

        vm.prank(alice);
        _createIdentity(identityRegistry, aliceKey, "alice.id"); // identityId = 1

        vm.prank(bob);
        _createIdentity(identityRegistry, bobKey, "bob.id"); // identityId = 2
    }

    // Atalho: faz o fluxo completo commit → (1 bloco depois) → registerDevice
    function _registerDevice(address controller, address devicePubKey, string memory label)
        internal
    {
        bytes32 commitment = keccak256(abi.encodePacked(devicePubKey, SALT, controller));

        vm.prank(controller);
        deviceRegistry.commitDevice(commitment);

        vm.roll(block.number + 1); // precisa de pelo menos 1 bloco entre commit e reveal

        vm.prank(controller);
        deviceRegistry.registerDevice(devicePubKey, label, SALT, "");
    }

    // -----------------------------------------------------------------
    // registerDevice — caminho feliz
    // -----------------------------------------------------------------

    function test_RegisterDevice_Success() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        assertTrue(deviceRegistry.isDeviceActive(aliceDevice1));

        DeviceRegistry.Device memory device = deviceRegistry.getDevice(aliceDevice1);
        assertEq(device.identityId, 1);
        assertEq(device.pubKey, aliceDevice1);
        assertEq(device.label, "iPhone 15 Pro");
        assertFalse(device.revoked);
        assertTrue(device.exists);
    }

    function test_RegisterDevice_MultipleDevicesForSameIdentity() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");
        _registerDevice(alice, aliceDevice2, "MacBook Pro");

        assertEq(deviceRegistry.deviceCount(1), 2);
        assertTrue(deviceRegistry.isDeviceActive(aliceDevice1));
        assertTrue(deviceRegistry.isDeviceActive(aliceDevice2));
    }

    function test_RegisterDevice_DifferentIdentitiesIndependent() public {
        _registerDevice(alice, aliceDevice1, "Alice's phone");
        _registerDevice(bob, bobDevice1, "Bob's phone");

        assertEq(deviceRegistry.deviceCount(1), 1); // alice: 1 device
        assertEq(deviceRegistry.deviceCount(2), 1); // bob: 1 device
    }

    function test_RegisterDevice_EmitsEvent() public {
        bytes32 commitment = keccak256(abi.encodePacked(aliceDevice1, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit DeviceRegistry.DeviceRegistered(1, aliceDevice1, "iPhone 15 Pro", "");
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro", SALT, "");
    }

    // -----------------------------------------------------------------
    // commitDevice / registerDevice — proteção contra front-running
    // -----------------------------------------------------------------

    function test_Revert_RegisterDevice_NoCommitment() public {
        // Nunca commitou — não pode revelar direto
        vm.prank(alice);
        vm.expectRevert(DeviceRegistry.NoCommitmentFound.selector);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro", SALT, "");
    }

    function test_Revert_RegisterDevice_RevealTooEarly() public {
        bytes32 commitment = keccak256(abi.encodePacked(aliceDevice1, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment);

        // Tenta revelar no MESMO bloco do commit — deve reverter
        vm.prank(alice);
        vm.expectRevert(DeviceRegistry.RevealTooEarly.selector);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro", SALT, "");
    }

    function test_Revert_RegisterDevice_WrongSalt() public {
        bytes32 commitment = keccak256(abi.encodePacked(aliceDevice1, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);

        // Salt errado → commitment recalculado não bate com o que foi salvo
        vm.prank(alice);
        vm.expectRevert(DeviceRegistry.NoCommitmentFound.selector);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro", keccak256("salt-errado"), "");
    }

    function test_Revert_RegisterDevice_CannotStealAnothersCommitment() public {
        // Alice commita normalmente
        bytes32 commitment = keccak256(abi.encodePacked(aliceDevice1, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);

        // Bob vê o devicePubKey + salt no momento em que Alice revela (mempool)
        // e tenta registrar o MESMO device pra identidade dele — mas o
        // commitment dele seria diferente (inclui o próprio endereço), então
        // nunca foi commitado por ele.
        vm.prank(bob);
        vm.expectRevert(DeviceRegistry.NoCommitmentFound.selector);
        deviceRegistry.registerDevice(aliceDevice1, "device roubado", SALT, "");
    }

    // -----------------------------------------------------------------
    // registerDevice — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_RegisterDevice_NoIdentity() public {
        address charlieDevice = makeAddr("charlie-device");
        bytes32 commitment = keccak256(abi.encodePacked(charlieDevice, SALT, charlie));
        vm.prank(charlie);
        deviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);

        vm.prank(charlie);
        vm.expectRevert(IdentityResolver.NotIdentityController.selector);
        deviceRegistry.registerDevice(charlieDevice, "iPad", SALT, "");
    }

    function test_Revert_RegisterDevice_AlreadyRegistered() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        bytes32 commitment = keccak256(abi.encodePacked(aliceDevice1, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DeviceRegistry.DeviceAlreadyRegistered.selector, aliceDevice1)
        );
        deviceRegistry.registerDevice(aliceDevice1, "Duplicado", SALT, "");
    }

    function test_Revert_RegisterDevice_InvalidPubKey() public {
        bytes32 commitment = keccak256(abi.encodePacked(address(0), SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);

        vm.prank(alice);
        vm.expectRevert(DeviceRegistry.InvalidPubKey.selector);
        deviceRegistry.registerDevice(address(0), "Device invalido", SALT, "");
    }

    // -----------------------------------------------------------------
    // revokeDevice — caminho feliz
    // -----------------------------------------------------------------

    function test_RevokeDevice_Success() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

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
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        vm.expectEmit(true, true, false, false);
        emit DeviceRegistry.DeviceRevoked(1, aliceDevice1);
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    function test_RevokeDevice_DoesNotAffectOtherDevices() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");
        _registerDevice(alice, aliceDevice2, "MacBook Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

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
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DeviceRegistry.DeviceAlreadyRevoked.selector, aliceDevice1)
        );
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    function test_Revert_RevokeDevice_NotController() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        // Bob tenta revogar o device da Alice — não é o controller da identidade dona do device
        vm.prank(bob);
        vm.expectRevert(IdentityResolver.NotIdentityController.selector);
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    function test_Revert_RevokeDevice_NoIdentity() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        // Charlie não tem identidade
        vm.prank(charlie);
        vm.expectRevert(IdentityResolver.NotIdentityController.selector);
        deviceRegistry.revokeDevice(aliceDevice1);
    }

    // -----------------------------------------------------------------
    // isDeviceActive
    // -----------------------------------------------------------------

    function test_IsDeviceActive_ReturnsFalseForNonExistent() public view {
        assertFalse(deviceRegistry.isDeviceActive(aliceDevice1));
    }

    function test_IsDeviceActive_ReturnsTrueForActive() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");
        assertTrue(deviceRegistry.isDeviceActive(aliceDevice1));
    }

    function test_IsDeviceActive_ReturnsFalseForRevoked() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

        assertFalse(deviceRegistry.isDeviceActive(aliceDevice1));
    }

    // -----------------------------------------------------------------
    // getDevice
    // -----------------------------------------------------------------

    function test_GetDevice_Success() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

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
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");
        _registerDevice(alice, aliceDevice2, "MacBook Pro");

        address[] memory devices = deviceRegistry.getDevicesByIdentity(1);
        assertEq(devices.length, 2);
        assertEq(devices[0], aliceDevice1);
        assertEq(devices[1], aliceDevice2);
    }

    function test_GetDevicesByIdentity_IncludesRevoked() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");
        _registerDevice(alice, aliceDevice2, "MacBook Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

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
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");
        assertEq(deviceRegistry.deviceCount(1), 1);

        _registerDevice(alice, aliceDevice2, "MacBook Pro");
        assertEq(deviceRegistry.deviceCount(1), 2);
    }

    function test_DeviceCount_DoesNotDecrementOnRevoke() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice1);

        // Revogação não remove da lista, só marca como revogado
        assertEq(deviceRegistry.deviceCount(1), 1);
    }

    // -----------------------------------------------------------------
    // encryptedVaultKey — compartilhamento da chave do vault no pareamento
    // -----------------------------------------------------------------

    function test_RegisterDevice_WithEncryptedVaultKey() public {
        bytes memory vaultKey = hex"aabbccdd";
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro", vaultKey);

        bytes memory stored = deviceRegistry.deviceVaultKeys(aliceDevice1);
        assertEq(stored, vaultKey);
    }

    function test_RegisterDevice_EmptyEncryptedVaultKey() public {
        _registerDevice(alice, aliceDevice1, "iPhone 15 Pro");

        bytes memory stored = deviceRegistry.deviceVaultKeys(aliceDevice1);
        assertEq(stored.length, 0);
    }

    function test_RegisterDevice_EmitsEventWithVaultKey() public {
        bytes memory vaultKey = hex"deadbeef";

        bytes32 commitment = keccak256(abi.encodePacked(aliceDevice1, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment);
        vm.roll(block.number + 1);

        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit DeviceRegistry.DeviceRegistered(1, aliceDevice1, "iPhone 15 Pro", vaultKey);
        deviceRegistry.registerDevice(aliceDevice1, "iPhone 15 Pro", SALT, vaultKey);
    }

    function test_RegisterDevice_TwoDevices_DifferentVaultKeys() public {
        bytes memory vaultKey1 = hex"aabb";
        bytes memory vaultKey2 = hex"ccdd";

        bytes32 commitment1 = keccak256(abi.encodePacked(aliceDevice1, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment1);
        vm.roll(block.number + 1);
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice1, "Phone", SALT, vaultKey1);

        bytes32 commitment2 = keccak256(abi.encodePacked(aliceDevice2, SALT, alice));
        vm.prank(alice);
        deviceRegistry.commitDevice(commitment2);
        vm.roll(block.number + 1);
        vm.prank(alice);
        deviceRegistry.registerDevice(aliceDevice2, "Laptop", SALT, vaultKey2);

        assertEq(deviceRegistry.deviceVaultKeys(aliceDevice1), vaultKey1);
        assertEq(deviceRegistry.deviceVaultKeys(aliceDevice2), vaultKey2);
    }

    // Sobrecarga do helper que aceita encryptedVaultKey
    function _registerDevice(
        address controller,
        address devicePubKey,
        string memory label,
        bytes memory encryptedVaultKey
    ) internal {
        bytes32 commitment = keccak256(abi.encodePacked(devicePubKey, SALT, controller));

        vm.prank(controller);
        deviceRegistry.commitDevice(commitment);

        vm.roll(block.number + 1);

        vm.prank(controller);
        deviceRegistry.registerDevice(devicePubKey, label, SALT, encryptedVaultKey);
    }
}
