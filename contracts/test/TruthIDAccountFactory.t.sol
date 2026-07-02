// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {TruthIDAccountFactory} from "../src/TruthIDAccountFactory.sol";
import {TruthIDAccount, PackedUserOperation} from "../src/TruthIDAccount.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";

// Cobertura da factory deterministica (CREATE2) da Fase 14.4.
//
// Escopo:
//   - endereco previsto == endereco deployado
//   - idempotencia do createAccount
//   - parametros da conta criada
//   - dinamica "ovo-e-galinha" com IdentityRegistry
contract TruthIDAccountFactoryTest is Test {
    address internal constant ENTRY_POINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    TruthIDAccountFactory internal factory;
    IdentityRegistry internal identityRegistry;

    address internal deviceRegistry = makeAddr("deviceRegistry");
    address internal recoveryManager = makeAddr("recoveryManager");
    address internal owner = makeAddr("owner");
    address internal owner2 = makeAddr("owner2");

    function setUp() public {
        identityRegistry = new IdentityRegistry();

        factory = new TruthIDAccountFactory(
            ENTRY_POINT_V07, deviceRegistry, address(identityRegistry), recoveryManager
        );
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _predictAndCreate(address owner_) internal returns (TruthIDAccount account) {
        address predicted = factory.getAddress(owner_);
        account = factory.createAccount(owner_);
        assertEq(address(account), predicted);
    }

    // -------------------------------------------------------------------------
    // CREATE2 deterministico
    // -------------------------------------------------------------------------

    function test_GetAddress_EqualsDeployedAddress() public {
        address predicted = factory.getAddress(owner);
        TruthIDAccount account = factory.createAccount(owner);

        assertEq(address(account), predicted);
        assertTrue(address(account) != address(0));
    }

    function test_CreateAccount_DeploysWithCorrectParameters() public {
        TruthIDAccount account = _predictAndCreate(owner);

        assertEq(account.owner(), owner);
        assertEq(account.entryPoint(), ENTRY_POINT_V07);
        assertEq(account.deviceRegistry(), deviceRegistry);
        assertEq(account.identityRegistry(), address(identityRegistry));
        assertEq(account.recoveryManager(), recoveryManager);
    }

    // -------------------------------------------------------------------------
    // Idempotencia
    // -------------------------------------------------------------------------

    function test_CreateAccount_SecondCall_ReturnsExistingAccount() public {
        TruthIDAccount first = factory.createAccount(owner);
        uint256 firstCodeSize;
        assembly {
            firstCodeSize := extcodesize(first)
        }

        TruthIDAccount second = factory.createAccount(owner);

        assertEq(address(first), address(second));
        assertGt(firstCodeSize, 0);
    }

    function test_CreateAccount_SecondCall_DoesNotEmitAgain() public {
        factory.createAccount(owner);

        vm.recordLogs();
        factory.createAccount(owner);

        // Nenhum AccountCreated deve ser emitido na segunda chamada, pois
        // a conta ja existe (idempotente).
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 accountCreatedSig = keccak256("AccountCreated(address,address)");
        for (uint256 i = 0; i < entries.length; i++) {
            assertTrue(entries[i].topics[0] != accountCreatedSig);
        }
    }

    // -------------------------------------------------------------------------
    // Isolamento entre owners
    // -------------------------------------------------------------------------

    function test_DifferentOwners_DifferentAddresses() public {
        address predicted1 = factory.getAddress(owner);
        address predicted2 = factory.getAddress(owner2);

        assertTrue(predicted1 != predicted2);

        TruthIDAccount account1 = factory.createAccount(owner);
        TruthIDAccount account2 = factory.createAccount(owner2);

        assertEq(address(account1), predicted1);
        assertEq(address(account2), predicted2);
        assertTrue(address(account1) != address(account2));
    }

    // -------------------------------------------------------------------------
    // Validacao de constructor
    // -------------------------------------------------------------------------

    function test_Revert_Constructor_ZeroAddress_EntryPoint() public {
        vm.expectRevert(TruthIDAccountFactory.InvalidEntryPoint.selector);
        new TruthIDAccountFactory(
            address(0), deviceRegistry, address(identityRegistry), recoveryManager
        );
    }

    function test_Revert_Constructor_ZeroAddress_DeviceRegistry() public {
        vm.expectRevert(TruthIDAccountFactory.InvalidDeviceRegistry.selector);
        new TruthIDAccountFactory(
            ENTRY_POINT_V07, address(0), address(identityRegistry), recoveryManager
        );
    }

    function test_Revert_Constructor_ZeroAddress_IdentityRegistry() public {
        vm.expectRevert(TruthIDAccountFactory.InvalidIdentityRegistry.selector);
        new TruthIDAccountFactory(ENTRY_POINT_V07, deviceRegistry, address(0), recoveryManager);
    }

    function test_Revert_Constructor_ZeroAddress_RecoveryManager() public {
        vm.expectRevert(TruthIDAccountFactory.InvalidRecoveryManager.selector);
        new TruthIDAccountFactory(
            ENTRY_POINT_V07, deviceRegistry, address(identityRegistry), address(0)
        );
    }

    // -------------------------------------------------------------------------
    // Ovo-e-galinha: prever endereco -> criar identidade -> deployar conta
    // -------------------------------------------------------------------------

    function test_IdentityCreationBeforeDeploy_MatchesPredictedAddress() public {
        address predictedAccount = factory.getAddress(owner);

        // 1. Ledger (owner) paga a identidade apontando para o endereco previsto.
        vm.prank(owner);
        uint256 identityId = identityRegistry.createIdentity("masterlxz.id", predictedAccount);

        // sanity: controller registrado e realmente o endereco previsto.
        IdentityRegistry.Identity memory identity = identityRegistry.getIdentity("masterlxz.id");

        assertTrue(identity.exists);
        assertEq(identity.id, identityId);
        assertEq(identity.username, "masterlxz.id");
        assertEq(identity.controller, predictedAccount);

        // 2. So depois a factory deploya a conta.
        TruthIDAccount account = factory.createAccount(owner);
        assertEq(address(account), predictedAccount);

        // A conta sabe quem e o owner.
        assertEq(account.owner(), owner);
    }

    // -------------------------------------------------------------------------
    // Endereco previsto deve ser nao-zero ANTES de qualquer deploy —
    // pre-requisito do caso de uso real da factory: prever o endereco pra
    // registrar no IdentityRegistry antes de deployar a conta.
    // -------------------------------------------------------------------------

    function test_GetAddress_BeforeDeploy_NonZeroAddress() public {
        address predicted = factory.getAddress(owner);

        assertTrue(predicted != address(0), "predicted address must be non-zero");
        // Ainda nao deployada — extcodesize deve ser zero.
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(predicted)
        }
        assertEq(codeSize, 0, "no code should exist before deploy");
    }

    // -------------------------------------------------------------------------
    // createAccount(address(0)) deve propagar o revert de InvalidDevice do
    // constructor da TruthIDAccount (owner == 0).
    // -------------------------------------------------------------------------

    function test_Revert_CreateAccount_ZeroOwner() public {
        // O revert vem de dentro do CREATE2: o constructor da account
        // rejeita qualquer arg zero com InvalidConstructorArgs (check
        // generico no topo do constructor, antes de qualquer outra logica).
        vm.expectRevert(TruthIDAccount.InvalidConstructorArgs.selector);
        factory.createAccount(address(0));
    }

    // -------------------------------------------------------------------------
    // Determinismo temporal: chamar getAddress 2x retorna o mesmo valor.
    // (Trivial, mas trava o contrato de CREATE2 — o endereco depende so de
    //  salt + initCodeHash + factory, nao de estado mutavel.)
    // -------------------------------------------------------------------------

    function test_GetAddress_SameOwner_SameAddress_AcrossTime() public {
        address predicted1 = factory.getAddress(owner);

        // Acao intermediaria que NAO afeta o endereco previsto (deploy de
        // outro owner). Se o endereco do primeiro owner mudasse apos essa
        // acao, estariamos em frente a um bug grave de CREATE2.
        factory.createAccount(owner2);

        address predicted2 = factory.getAddress(owner);
        assertEq(predicted1, predicted2);
    }
}
