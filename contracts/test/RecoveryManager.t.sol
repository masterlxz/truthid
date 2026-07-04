// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {RecoveryManager} from "../src/RecoveryManager.sol";
import {TruthIDAccountFactory} from "../src/TruthIDAccountFactory.sol";
import {TruthIDAccount} from "../src/TruthIDAccount.sol";
import {IdentityConsentHelper} from "./IdentityConsentHelper.sol";

contract RecoveryManagerTest is Test, IdentityConsentHelper {
    IdentityRegistry public identityRegistry;
    RecoveryManager public recoveryManager;

    // Donos de identidades
    address public alice;
    uint256 aliceKey;
    address public bob;
    uint256 bobKey;

    // Guardians da identidade da alice (3-de-5)
    address public guardian1 = makeAddr("guardian1");
    address public guardian2 = makeAddr("guardian2");
    address public guardian3 = makeAddr("guardian3");
    address public guardian4 = makeAddr("guardian4");
    address public guardian5 = makeAddr("guardian5");

    // Nova wallet para onde alice quer transferir o controle
    address public aliceNewWallet = makeAddr("alice-new-wallet");

    address public stranger = makeAddr("stranger"); // sem identidade, sem papel

    // Fixtures para o teste de emergencyWithdraw (debito #19):
    // charlie tem uma identidade cujo controller eh uma TruthIDAccount
    // (smart account), nao um EOA direto.
    address public charlie;
    uint256 charlieKey;
    address public charlieTA;
    TruthIDAccountFactory public taFactory;

    // Guardians pra identidade do charlie (2-de-3 pra cobrir threshold diferente)
    address public charlieG1 = makeAddr("charlie-g1");
    address public charlieG2 = makeAddr("charlie-g2");
    address public charlieG3 = makeAddr("charlie-g3");
    address public charlieNewWallet = makeAddr("charlie-new-wallet");

    // setUp() roda antes de cada teste — estado completamente isolado
    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");
        (charlie, charlieKey) = makeAddrAndKey("charlie");

        identityRegistry = new IdentityRegistry();
        recoveryManager = new RecoveryManager(address(identityRegistry));

        // Liga os dois contratos (só pode ser feito uma vez)
        identityRegistry.setRecoveryManager(address(recoveryManager));

        vm.prank(alice);
        _createIdentity(identityRegistry, aliceKey, "alice.id"); // identityId = 1

        vm.prank(bob);
        _createIdentity(identityRegistry, bobKey, "bob.id"); // identityId = 2
    }

    // Atalho: configura guardians 3-de-5 para alice
    function _configureAliceGuardians() internal {
        address[] memory guardians = new address[](5);
        guardians[0] = guardian1;
        guardians[1] = guardian2;
        guardians[2] = guardian3;
        guardians[3] = guardian4;
        guardians[4] = guardian5;

        vm.prank(alice);
        recoveryManager.configureGuardians("alice.id", guardians, 3);
    }

    // Atalho: propõe recovery (requer guardians configurados)
    function _propose() internal {
        vm.prank(guardian1);
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);
    }

    // Atalho: coleta 3 aprovações (threshold)
    function _collectThreeApprovals() internal {
        vm.prank(guardian1);
        recoveryManager.approveRecovery("alice.id");
        vm.prank(guardian2);
        recoveryManager.approveRecovery("alice.id");
        vm.prank(guardian3);
        recoveryManager.approveRecovery("alice.id");
    }

    // -----------------------------------------------------------------
    // setRecoveryManager (no IdentityRegistry)
    // -----------------------------------------------------------------

    function test_SetRecoveryManager_BlocksSecondCall() public {
        // Já foi chamado no setUp — segunda chamada deve reverter
        vm.expectRevert(IdentityRegistry.RecoveryManagerAlreadySet.selector);
        identityRegistry.setRecoveryManager(address(recoveryManager));
    }

    function test_RecoverController_RevertsIfCalledDirectly() public {
        // Nenhum usuário pode chamar recoverController diretamente
        vm.prank(alice);
        vm.expectRevert(IdentityRegistry.NotRecoveryManager.selector);
        identityRegistry.recoverController("alice.id", aliceNewWallet);
    }

    function test_Revert_RecoverController_ToZeroAddress() public {
        // Defesa em profundidade: mesmo o RecoveryManager (único autorizado) não
        // consegue setar o controller para address(0) — checagem dentro do IdentityRegistry
        vm.prank(address(recoveryManager));
        vm.expectRevert(IdentityRegistry.InvalidNewController.selector);
        identityRegistry.recoverController("alice.id", address(0));
    }

    // -----------------------------------------------------------------
    // configureGuardians — caminho feliz
    // -----------------------------------------------------------------

    function test_ConfigureGuardians_Success() public {
        _configureAliceGuardians();

        (address[] memory guardians, uint256 threshold) =
            recoveryManager.getGuardianConfig("alice.id");
        assertEq(guardians.length, 5);
        assertEq(threshold, 3);
    }

    function test_ConfigureGuardians_EmitsEvent() public {
        address[] memory guardians = new address[](2);
        guardians[0] = guardian1;
        guardians[1] = guardian2;

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit RecoveryManager.GuardiansConfigured(1, guardians, 2);
        recoveryManager.configureGuardians("alice.id", guardians, 2);
    }

    function test_ConfigureGuardians_CanReconfigureAfterProposalExecuted() public {
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();
        vm.warp(block.timestamp + 7 days + 1);
        recoveryManager.executeRecovery("alice.id");

        // Proposta executada — pode reconfigurar com nova wallet como controller
        address[] memory newGuardians = new address[](1);
        newGuardians[0] = guardian1;

        vm.prank(aliceNewWallet); // nova wallet é a nova controller
        recoveryManager.configureGuardians("alice.id", newGuardians, 1);

        (, uint256 threshold) = recoveryManager.getGuardianConfig("alice.id");
        assertEq(threshold, 1);
    }

    // -----------------------------------------------------------------
    // configureGuardians — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_ConfigureGuardians_NotController() public {
        address[] memory guardians = new address[](1);
        guardians[0] = guardian1;

        vm.prank(bob); // bob tenta configurar guardians para alice.id
        vm.expectRevert(RecoveryManager.NotIdentityController.selector);
        recoveryManager.configureGuardians("alice.id", guardians, 1);
    }

    function test_Revert_ConfigureGuardians_ThresholdHigherThanGuardians() public {
        address[] memory guardians = new address[](2);
        guardians[0] = guardian1;
        guardians[1] = guardian2;

        vm.prank(alice);
        vm.expectRevert(RecoveryManager.InvalidThreshold.selector);
        recoveryManager.configureGuardians("alice.id", guardians, 3); // 3 > 2
    }

    function test_Revert_ConfigureGuardians_ThresholdZero() public {
        address[] memory guardians = new address[](2);
        guardians[0] = guardian1;
        guardians[1] = guardian2;

        vm.prank(alice);
        vm.expectRevert(RecoveryManager.InvalidThreshold.selector);
        recoveryManager.configureGuardians("alice.id", guardians, 0);
    }

    function test_Revert_ConfigureGuardians_TooManyGuardians() public {
        address[] memory guardians = new address[](21); // MAX_GUARDIANS = 20
        for (uint256 i = 0; i < guardians.length; i++) {
            guardians[i] = address(uint160(i + 1));
        }

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.TooManyGuardians.selector, 21, 20));
        recoveryManager.configureGuardians("alice.id", guardians, 1);
    }

    function test_ConfigureGuardians_ExactlyMaxGuardians() public {
        address[] memory guardians = new address[](20); // exatamente o limite
        for (uint256 i = 0; i < guardians.length; i++) {
            guardians[i] = address(uint160(i + 1));
        }

        vm.prank(alice);
        recoveryManager.configureGuardians("alice.id", guardians, 1);

        (address[] memory stored,) = recoveryManager.getGuardianConfig("alice.id");
        assertEq(stored.length, 20);
    }

    function test_Revert_ConfigureGuardians_EmptyGuardians() public {
        address[] memory guardians = new address[](0);

        vm.prank(alice);
        vm.expectRevert(RecoveryManager.InvalidThreshold.selector);
        recoveryManager.configureGuardians("alice.id", guardians, 1);
    }

    function test_Revert_ConfigureGuardians_ActiveProposalExists() public {
        _configureAliceGuardians();
        _propose();

        address[] memory newGuardians = new address[](1);
        newGuardians[0] = guardian1;

        vm.prank(alice);
        vm.expectRevert(RecoveryManager.ActiveProposalExists.selector);
        recoveryManager.configureGuardians("alice.id", newGuardians, 1);
    }

    // -----------------------------------------------------------------
    // proposeRecovery — caminho feliz
    // -----------------------------------------------------------------

    function test_ProposeRecovery_Success() public {
        _configureAliceGuardians();
        _propose();

        RecoveryManager.RecoveryProposal memory proposal = recoveryManager.getProposal("alice.id");
        assertEq(proposal.proposedBy, guardian1);
        assertEq(proposal.newController, aliceNewWallet);
        assertEq(proposal.proposedAt, block.timestamp);
        assertEq(proposal.approvalCount, 0);
        assertFalse(proposal.executed);
        assertFalse(proposal.cancelled);
        assertTrue(proposal.exists);
    }

    function test_ProposeRecovery_EmitsEvent() public {
        _configureAliceGuardians();

        vm.prank(guardian1);
        vm.expectEmit(true, true, true, false);
        emit RecoveryManager.RecoveryProposed(1, guardian1, aliceNewWallet);
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);
    }

    function test_ProposeRecovery_CanReproposeAfterCancellation() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(alice);
        recoveryManager.cancelRecovery("alice.id");

        // Pode propor novamente após cancelamento
        vm.prank(guardian2);
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);

        RecoveryManager.RecoveryProposal memory proposal = recoveryManager.getProposal("alice.id");
        assertEq(proposal.proposedBy, guardian2);
        assertFalse(proposal.cancelled);
    }

    // -----------------------------------------------------------------
    // proposeRecovery — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_ProposeRecovery_NotGuardian() public {
        _configureAliceGuardians();

        vm.prank(stranger);
        vm.expectRevert(RecoveryManager.NotGuardian.selector);
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);
    }

    function test_Revert_ProposeRecovery_GuardiansNotConfigured() public {
        // Alice não configurou guardians ainda
        vm.prank(guardian1);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.GuardiansNotConfigured.selector, 1));
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);
    }

    function test_Revert_ProposeRecovery_AlreadyExists() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(guardian2);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.ProposalAlreadyExists.selector, 1));
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);
    }

    function test_Revert_ProposeRecovery_NewControllerIsZeroAddress() public {
        _configureAliceGuardians();

        vm.prank(guardian1);
        vm.expectRevert(RecoveryManager.InvalidNewController.selector);
        recoveryManager.proposeRecovery("alice.id", address(0));
    }

    // -----------------------------------------------------------------
    // approveRecovery — caminho feliz
    // -----------------------------------------------------------------

    function test_ApproveRecovery_Success() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(guardian1);
        recoveryManager.approveRecovery("alice.id");

        RecoveryManager.RecoveryProposal memory proposal = recoveryManager.getProposal("alice.id");
        assertEq(proposal.approvalCount, 1);
        assertTrue(recoveryManager.hasGuardianApproved("alice.id", guardian1));
    }

    function test_ApproveRecovery_EmitsEvent() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(guardian1);
        vm.expectEmit(true, true, false, true);
        emit RecoveryManager.RecoveryApproved(1, guardian1, 1);
        recoveryManager.approveRecovery("alice.id");
    }

    function test_ApproveRecovery_CountIncreasesPerGuardian() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(guardian1);
        recoveryManager.approveRecovery("alice.id");
        vm.prank(guardian2);
        recoveryManager.approveRecovery("alice.id");

        RecoveryManager.RecoveryProposal memory proposal = recoveryManager.getProposal("alice.id");
        assertEq(proposal.approvalCount, 2);
    }

    // -----------------------------------------------------------------
    // approveRecovery — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_ApproveRecovery_NotGuardian() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(stranger);
        vm.expectRevert(RecoveryManager.NotGuardian.selector);
        recoveryManager.approveRecovery("alice.id");
    }

    function test_Revert_ApproveRecovery_NoActiveProposal() public {
        _configureAliceGuardians();

        vm.prank(guardian1);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.NoActiveProposal.selector, 1));
        recoveryManager.approveRecovery("alice.id");
    }

    function test_Revert_ApproveRecovery_AlreadyApproved() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(guardian1);
        recoveryManager.approveRecovery("alice.id");

        vm.prank(guardian1);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.AlreadyApproved.selector, guardian1));
        recoveryManager.approveRecovery("alice.id");
    }

    // -----------------------------------------------------------------
    // executeRecovery — caminho feliz
    // -----------------------------------------------------------------

    function test_ExecuteRecovery_ChangesControllerInIdentityRegistry() public {
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();

        vm.warp(block.timestamp + 7 days + 1);
        recoveryManager.executeRecovery("alice.id");

        // Verifica que o controller mudou no IdentityRegistry
        IdentityRegistry.Identity memory identity = identityRegistry.getIdentity("alice.id");
        assertEq(identity.controller, aliceNewWallet);

        // Verifica o lookup reverso: nova wallet aponta para alice.id
        assertEq(identityRegistry.getUsernameByController(aliceNewWallet), "alice.id");

        // Verifica que a wallet antiga não tem mais vínculo
        assertEq(identityRegistry.getUsernameByController(alice), "");
    }

    function test_ExecuteRecovery_EmitsEvent() public {
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();
        vm.warp(block.timestamp + 7 days + 1);

        vm.expectEmit(true, true, false, false);
        emit RecoveryManager.RecoveryExecuted(1, aliceNewWallet);
        recoveryManager.executeRecovery("alice.id");
    }

    function test_ExecuteRecovery_MarksProposalAsExecuted() public {
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();
        vm.warp(block.timestamp + 7 days + 1);
        recoveryManager.executeRecovery("alice.id");

        RecoveryManager.RecoveryProposal memory proposal = recoveryManager.getProposal("alice.id");
        assertTrue(proposal.executed);
    }

    function test_ExecuteRecovery_ClearsOldGuardianConfig() public {
        // Achado da auditoria: guardians antigos não devem reter poder sobre o
        // novo controller após a recovery ser executada.
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();
        vm.warp(block.timestamp + 7 days + 1);
        recoveryManager.executeRecovery("alice.id");

        // A configuração de guardians foi zerada
        (address[] memory guardians, uint256 threshold) =
            recoveryManager.getGuardianConfig("alice.id");
        assertEq(guardians.length, 0);
        assertEq(threshold, 0);

        // guardian1 (que era guardian da alice) não consegue mais propor —
        // identidade agora não tem guardians configurados
        vm.prank(guardian1);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.GuardiansNotConfigured.selector, 1));
        recoveryManager.proposeRecovery("alice.id", stranger);
    }

    // -----------------------------------------------------------------
    // executeRecovery — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_ExecuteRecovery_ThresholdNotReached() public {
        _configureAliceGuardians();
        _propose();

        // Só 2 aprovações, threshold é 3
        vm.prank(guardian1);
        recoveryManager.approveRecovery("alice.id");
        vm.prank(guardian2);
        recoveryManager.approveRecovery("alice.id");

        vm.warp(block.timestamp + 7 days + 1);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.ThresholdNotReached.selector, 2, 3));
        recoveryManager.executeRecovery("alice.id");
    }

    function test_Revert_ExecuteRecovery_TimelockNotExpired() public {
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();

        // Avança 6 dias — ainda falta 1 dia
        vm.warp(block.timestamp + 6 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                RecoveryManager.TimelockNotExpired.selector,
                block.timestamp - 6 days, // proposedAt (antes do warp)
                block.timestamp - 6 days + 7 days // executeAfter
            )
        );
        recoveryManager.executeRecovery("alice.id");
    }

    function test_Revert_ExecuteRecovery_NoActiveProposal() public {
        _configureAliceGuardians();

        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.NoActiveProposal.selector, 1));
        recoveryManager.executeRecovery("alice.id");
    }

    // -----------------------------------------------------------------
    // cancelRecovery — caminho feliz
    // -----------------------------------------------------------------

    function test_CancelRecovery_Success() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(alice);
        recoveryManager.cancelRecovery("alice.id");

        RecoveryManager.RecoveryProposal memory proposal = recoveryManager.getProposal("alice.id");
        assertTrue(proposal.cancelled);
        assertFalse(proposal.executed);
    }

    function test_CancelRecovery_EmitsEvent() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit RecoveryManager.RecoveryCancelled(1);
        recoveryManager.cancelRecovery("alice.id");
    }

    function test_CancelRecovery_ApprovalsResetOnNextProposal() public {
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();

        vm.prank(alice);
        recoveryManager.cancelRecovery("alice.id");

        // Nova proposta — aprovações antigas devem estar zeradas
        vm.prank(guardian1);
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);

        assertFalse(recoveryManager.hasGuardianApproved("alice.id", guardian1));
        assertFalse(recoveryManager.hasGuardianApproved("alice.id", guardian2));
        assertFalse(recoveryManager.hasGuardianApproved("alice.id", guardian3));

        RecoveryManager.RecoveryProposal memory proposal = recoveryManager.getProposal("alice.id");
        assertEq(proposal.approvalCount, 0);
    }

    // -----------------------------------------------------------------
    // cancelRecovery — casos de erro
    // -----------------------------------------------------------------

    function test_Revert_CancelRecovery_NotController() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(bob); // bob não é controller de alice.id
        vm.expectRevert(RecoveryManager.NotIdentityController.selector);
        recoveryManager.cancelRecovery("alice.id");
    }

    function test_Revert_CancelRecovery_NoActiveProposal() public {
        _configureAliceGuardians();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RecoveryManager.NoActiveProposal.selector, 1));
        recoveryManager.cancelRecovery("alice.id");
    }

    function test_Revert_CancelRecovery_AlreadyExecuted() public {
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();
        vm.warp(block.timestamp + 7 days + 1);
        recoveryManager.executeRecovery("alice.id");

        vm.prank(aliceNewWallet); // nova controller tenta cancelar proposta já executada
        vm.expectRevert(RecoveryManager.ProposalAlreadyExecuted.selector);
        recoveryManager.cancelRecovery("alice.id");
    }

    // -----------------------------------------------------------------
    // configureGuardians — remoção de guardians antigos
    // -----------------------------------------------------------------

    function test_Revert_OldGuardian_CannotProposeAfterReconfiguration() public {
        _configureAliceGuardians(); // guardian1..5 são guardians

        // Alice reconfigura: agora só guardian1 é guardian
        address[] memory newGuardians = new address[](1);
        newGuardians[0] = guardian1;

        vm.prank(alice);
        recoveryManager.configureGuardians("alice.id", newGuardians, 1);

        // guardian2 era guardian antes, mas agora foi removido
        vm.prank(guardian2);
        vm.expectRevert(RecoveryManager.NotGuardian.selector);
        recoveryManager.proposeRecovery("alice.id", aliceNewWallet);
    }

    // -----------------------------------------------------------------
    // approveRecovery / cancelRecovery — proposta cancelada
    // -----------------------------------------------------------------

    function test_Revert_ApproveRecovery_ProposalAlreadyCancelled() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(alice);
        recoveryManager.cancelRecovery("alice.id");

        vm.prank(guardian1);
        vm.expectRevert(RecoveryManager.ProposalAlreadyCancelled.selector);
        recoveryManager.approveRecovery("alice.id");
    }

    function test_Revert_CancelRecovery_AlreadyCancelled() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(alice);
        recoveryManager.cancelRecovery("alice.id");

        vm.prank(alice);
        vm.expectRevert(RecoveryManager.ProposalAlreadyCancelled.selector);
        recoveryManager.cancelRecovery("alice.id");
    }

    // -----------------------------------------------------------------
    // configureGuardians — pode reconfigurar após cancelamento
    // -----------------------------------------------------------------

    function test_ConfigureGuardians_CanReconfigureAfterCancellation() public {
        _configureAliceGuardians();
        _propose();

        vm.prank(alice);
        recoveryManager.cancelRecovery("alice.id");

        // Proposta cancelada — alice pode reconfigurar guardians
        address[] memory newGuardians = new address[](1);
        newGuardians[0] = guardian1;

        vm.prank(alice);
        recoveryManager.configureGuardians("alice.id", newGuardians, 1);

        (, uint256 threshold) = recoveryManager.getGuardianConfig("alice.id");
        assertEq(threshold, 1);
    }

    // -----------------------------------------------------------------
    // emergencyWithdraw — débito #19: RecoveryManager transfere ETH
    // da TruthIDAccount antiga para o novo controller durante recovery.
    // -----------------------------------------------------------------

    // Deploy da factory + cria identidade do charlie com TruthIDAccount
    // como controller. Soh chamado pelos testes de emergencyWithdraw
    // (custa deploy de 2 contratos — mantido fora do setUp compartilhado).
    function _setupCharlieWithTA() internal {
        // Dummy addresses pra entryPoint e deviceRegistry — a TA soh precisa
        // que nao sejam address(0); nunca chamamos o EntryPoint ou DeviceRegistry
        // nesses testes especificos de recovery.
        taFactory = new TruthIDAccountFactory(
            address(0x1234), // entryPoint (nao usado neste teste)
            address(0x5678), // deviceRegistry (nao usado neste teste)
            address(identityRegistry),
            address(recoveryManager)
        );

        // O IdentityRegistry precisa saber da factory pra validar a assinatura
        // de consentimento quando o controller eh uma smart account (debito #17).
        identityRegistry.setFactory(address(taFactory));

        // Pre-computa o endereco da TA de charlie antes de deployar.
        address predictedAccount = taFactory.getAddress(charlie, 0);

        // Cria identidade apontando pro endereco pre-computado da TA.
        // Consentimento: charlie (dono da chave) assina confirmando que quer
        // a smart account como controller da sua identidade.
        {
            (uint8 v, bytes32 r, bytes32 s) = _signConsent(
                identityRegistry,
                charlieKey,
                "charlie.id",
                predictedAccount
            );
            vm.prank(charlie);
            identityRegistry.createIdentity("charlie.id", predictedAccount, v, r, s);
        }

        // Agora deploya a TA de fato — cai no mesmo endereco previsto.
        vm.prank(charlie);
        charlieTA = address(taFactory.createAccount(charlie, 0));

        // Financia a TA com 2 ETH pra ter algo pra transferir.
        vm.deal(charlieTA, 2 ether);

        // Configura guardians 2-de-3 para charlie.
        address[] memory guardians = new address[](3);
        guardians[0] = charlieG1;
        guardians[1] = charlieG2;
        guardians[2] = charlieG3;

        vm.prank(charlieTA);
        recoveryManager.configureGuardians("charlie.id", guardians, 2);
    }

    function test_ExecuteRecovery_EmergencyWithdraw_TransfersEthFromTA() public {
        _setupCharlieWithTA();

        uint256 taBalanceBefore = charlieTA.balance;
        assertEq(taBalanceBefore, 2 ether, "TA should have 2 ETH before recovery");

        // Propoe recovery pelo guardian 1
        vm.prank(charlieG1);
        recoveryManager.proposeRecovery("charlie.id", charlieNewWallet);

        // Aprova pelos guardians 1 e 2 (threshold = 2)
        vm.prank(charlieG1);
        recoveryManager.approveRecovery("charlie.id");
        vm.prank(charlieG2);
        recoveryManager.approveRecovery("charlie.id");

        // Avanca o timelock
        vm.warp(block.timestamp + 7 days + 1);

        // Executa recovery — deve transferir os 2 ETH da TA para o novo wallet
        recoveryManager.executeRecovery("charlie.id");

        // Verifica: TA ficou sem ETH
        assertEq(charlieTA.balance, 0, "TA balance should be 0 after emergencyWithdraw");
        // Verifica: novo controller recebeu os 2 ETH
        assertEq(charlieNewWallet.balance, 2 ether, "new wallet should have 2 ETH");
    }

    function test_ExecuteRecovery_EOAController_DoesNotRevert() public {
        // Caso normal: alice tem um EOA simples como controller.
        // O try/catch em executeRecovery deve capturar o revert de
        // emergencyWithdraw (EOA nao tem essa funcao) e a recovery continua.
        _configureAliceGuardians();
        _propose();
        _collectThreeApprovals();
        vm.warp(block.timestamp + 7 days + 1);

        // Nao deve reverter — emergencyWithdraw falha silenciosamente no try/catch.
        recoveryManager.executeRecovery("alice.id");

        // Confirma que o controller mudou de fato.
        IdentityRegistry.Identity memory recovered = identityRegistry.getIdentity("alice.id");
        assertEq(recovered.controller, aliceNewWallet);
    }
}
