// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";
import {VaultRegistry} from "../src/VaultRegistry.sol";
import {IdentityConsentHelper} from "./IdentityConsentHelper.sol";

contract VaultRegistryTest is Test, IdentityConsentHelper {
    IdentityRegistry public identityRegistry;
    DeviceRegistry public deviceRegistry;
    VaultRegistry public vaultRegistry;

    address public alice;
    uint256 aliceKey;
    address public bob;
    uint256 bobKey;
    address public charlie = makeAddr("charlie"); // nunca cria identidade

    bytes32 constant SALT = keccak256("test-salt");

    string constant CID_V1 = "bafybeigdyrzt5sfp7udm7hu76uh7y26nf3efuylqabf3oclgtqy55fbzdi";
    string constant CID_V2 = "bafybeidmur3iutbzsbapbfm3rvqk7bvz3uqydxsqhsgfk2rq3vbmkagmq";

    bytes32 constant HASH_V1 = keccak256("vault-content-v1");
    bytes32 constant HASH_V2 = keccak256("vault-content-v2");

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");

        identityRegistry = new IdentityRegistry();
        deviceRegistry = new DeviceRegistry(address(identityRegistry));
        vaultRegistry = new VaultRegistry(address(identityRegistry), address(deviceRegistry));

        vm.prank(alice);
        _createIdentity(identityRegistry, aliceKey, "alice.id"); // identityId = 1

        vm.prank(bob);
        _createIdentity(identityRegistry, bobKey, "bob.id"); // identityId = 2
    }

    // -------------------------------------------------------------------------
    // updateVault — caminho feliz
    // -------------------------------------------------------------------------

    function test_UpdateVault_Success() public {
        vm.prank(alice);
        vaultRegistry.updateVault(CID_V1, HASH_V1);

        VaultRegistry.VaultRef memory ref = vaultRegistry.getVault(1);
        assertEq(ref.cid, CID_V1);
        assertEq(ref.contentHash, HASH_V1);
        assertEq(ref.version, 1);
        assertEq(ref.updatedAt, block.timestamp);
        assertTrue(ref.exists);
    }

    function test_UpdateVault_EmiteEvento() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit VaultRegistry.VaultUpdated(1, CID_V1, HASH_V1, 1);

        vaultRegistry.updateVault(CID_V1, HASH_V1);
    }

    function test_UpdateVault_SegundaAtualizacaoIncrementa_Versao() public {
        vm.prank(alice);
        vaultRegistry.updateVault(CID_V1, HASH_V1);

        vm.warp(block.timestamp + 60);

        vm.prank(alice);
        vaultRegistry.updateVault(CID_V2, HASH_V2);

        VaultRegistry.VaultRef memory ref = vaultRegistry.getVault(1);
        assertEq(ref.cid, CID_V2);
        assertEq(ref.contentHash, HASH_V2);
        assertEq(ref.version, 2);
    }

    function test_UpdateVault_NaoAfetaOutrasIdentidades() public {
        vm.prank(alice);
        vaultRegistry.updateVault(CID_V1, HASH_V1);

        assertFalse(vaultRegistry.hasVault(2));
    }

    // -------------------------------------------------------------------------
    // updateVault — erros
    // -------------------------------------------------------------------------

    function test_Revert_UpdateVault_SemIdentidade() public {
        vm.prank(charlie);
        vm.expectRevert(VaultRegistry.NotIdentityController.selector);
        vaultRegistry.updateVault(CID_V1, HASH_V1);
    }

    function test_Revert_UpdateVault_CidVazio() public {
        vm.prank(alice);
        vm.expectRevert(VaultRegistry.EmptyCid.selector);
        vaultRegistry.updateVault("", HASH_V1);
    }

    function test_Revert_UpdateVault_ContentHashVazio() public {
        vm.prank(alice);
        vm.expectRevert(VaultRegistry.EmptyContentHash.selector);
        vaultRegistry.updateVault(CID_V1, bytes32(0));
    }

    // -------------------------------------------------------------------------
    // getVault
    // -------------------------------------------------------------------------

    function test_Revert_GetVault_NaoEncontrado() public {
        vm.expectRevert(abi.encodeWithSelector(VaultRegistry.VaultNotFound.selector, 99));
        vaultRegistry.getVault(99);
    }

    // -------------------------------------------------------------------------
    // getVaultHistory
    // -------------------------------------------------------------------------

    function test_GetVaultHistory_RegistraTodasVersoes() public {
        vm.prank(alice);
        vaultRegistry.updateVault(CID_V1, HASH_V1);

        vm.prank(alice);
        vaultRegistry.updateVault(CID_V2, HASH_V2);

        string[] memory history = vaultRegistry.getVaultHistory(1);
        assertEq(history.length, 2);
        assertEq(history[0], CID_V1);
        assertEq(history[1], CID_V2);
    }

    function test_GetVaultHistory_Vazio_RetornaArrayVazio() public view {
        string[] memory history = vaultRegistry.getVaultHistory(99);
        assertEq(history.length, 0);
    }

    // -------------------------------------------------------------------------
    // hasVault
    // -------------------------------------------------------------------------

    function test_HasVault_FalseAntesDeAtualizar() public view {
        assertFalse(vaultRegistry.hasVault(1));
    }

    function test_HasVault_TrueAposAtualizar() public {
        vm.prank(alice);
        vaultRegistry.updateVault(CID_V1, HASH_V1);

        assertTrue(vaultRegistry.hasVault(1));
    }

    // -------------------------------------------------------------------------
    // Isolamento entre identidades
    // -------------------------------------------------------------------------

    function test_DuasIdentidades_VaultsSeparados() public {
        vm.prank(alice);
        vaultRegistry.updateVault(CID_V1, HASH_V1);

        vm.prank(bob);
        vaultRegistry.updateVault(CID_V2, HASH_V2);

        VaultRegistry.VaultRef memory aliceRef = vaultRegistry.getVault(1);
        VaultRegistry.VaultRef memory bobRef = vaultRegistry.getVault(2);

        assertEq(aliceRef.cid, CID_V1);
        assertEq(bobRef.cid, CID_V2);
        assertEq(aliceRef.version, 1);
        assertEq(bobRef.version, 1);
    }
}
