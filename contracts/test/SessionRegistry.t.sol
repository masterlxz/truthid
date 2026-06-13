// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {SessionRegistry} from "../src/SessionRegistry.sol";

contract SessionRegistryTest is Test {
    IdentityRegistry public identityRegistry;
    SessionRegistry public sessionRegistry;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie"); // nunca cria identidade

    address public aliceDevice = makeAddr("alice-device");
    address public bobDevice = makeAddr("bob-device");

    // Hashes simulando sessões reais (keccak256 de dados de autenticação)
    bytes32 public sessionA = keccak256(abi.encodePacked("alice", "loja.com", uint256(1)));
    bytes32 public sessionB = keccak256(abi.encodePacked("alice", "banco.com", uint256(2)));
    bytes32 public sessionC = keccak256(abi.encodePacked("bob", "loja.com", uint256(3)));

    function setUp() public {
        identityRegistry = new IdentityRegistry();
        sessionRegistry = new SessionRegistry(address(identityRegistry));

        vm.prank(alice);
        identityRegistry.createIdentity("alice.id"); // identityId = 1

        vm.prank(bob);
        identityRegistry.createIdentity("bob.id"); // identityId = 2
    }

    // -------------------------------------------------------------------------
    // createSession — caminho feliz
    // -------------------------------------------------------------------------

    function test_CreateSession_Success() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        SessionRegistry.Session memory s = sessionRegistry.getSession(sessionA);
        assertEq(s.identityId, 1);
        assertEq(s.devicePubKey, aliceDevice);
        assertEq(s.createdAt, block.timestamp);
        assertFalse(s.revoked);
        assertTrue(s.exists);
    }

    function test_CreateSession_QualquerUmPodeCriar() public {
        // O SDK do website (não o usuário) chama createSession
        vm.prank(charlie);
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        assertFalse(sessionRegistry.isSessionRevoked(sessionA));
    }

    function test_CreateSession_EmiteEvento() public {
        vm.expectEmit(true, true, true, false);
        emit SessionRegistry.SessionCreated(1, sessionA, aliceDevice);

        sessionRegistry.createSession(sessionA, 1, aliceDevice);
    }

    // -------------------------------------------------------------------------
    // createSession — erros
    // -------------------------------------------------------------------------

    function test_CreateSession_HashDuplicado_Reverte() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.expectRevert(abi.encodeWithSelector(SessionRegistry.SessionAlreadyExists.selector, sessionA));
        sessionRegistry.createSession(sessionA, 1, aliceDevice);
    }

    // -------------------------------------------------------------------------
    // isSessionRevoked
    // -------------------------------------------------------------------------

    function test_IsSessionRevoked_HashDesconhecido_RetornaTrue() public view {
        bytes32 hashDesconhecido = keccak256("nao existe");
        assertTrue(sessionRegistry.isSessionRevoked(hashDesconhecido));
    }

    function test_IsSessionRevoked_SessaoAtiva_RetornaFalse() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);
        assertFalse(sessionRegistry.isSessionRevoked(sessionA));
    }

    // -------------------------------------------------------------------------
    // revokeSession — caminho feliz
    // -------------------------------------------------------------------------

    function test_RevokeSession_Success() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
    }

    function test_RevokeSession_EmiteEvento() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.expectEmit(true, true, false, false);
        emit SessionRegistry.SessionRevoked(1, sessionA);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_NaoAfetaOutrasSessoes() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);
        sessionRegistry.createSession(sessionB, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
        assertFalse(sessionRegistry.isSessionRevoked(sessionB));
    }

    // -------------------------------------------------------------------------
    // revokeSession — erros
    // -------------------------------------------------------------------------

    function test_RevokeSession_NaoEncontrada_Reverte() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SessionRegistry.SessionNotFound.selector, sessionA));
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_JaRevogada_Reverte() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SessionRegistry.SessionAlreadyRevoked.selector, sessionA));
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_ControllerErrado_Reverte() public {
        // sessionA pertence à identidade 1 (alice), bob não pode revogar
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.prank(bob);
        vm.expectRevert(SessionRegistry.NotIdentityController.selector);
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_SemIdentidade_Reverte() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.prank(charlie);
        vm.expectRevert(SessionRegistry.NotIdentityController.selector);
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_JaRevogadaPorRevokeAll_Reverte() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        // sessionA já está revogada pelo revokeAllSessions
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(SessionRegistry.SessionAlreadyRevoked.selector, sessionA));
        sessionRegistry.revokeSession(sessionA);
    }

    // -------------------------------------------------------------------------
    // revokeAllSessions
    // -------------------------------------------------------------------------

    function test_RevokeAllSessions_RevogaSessoesExistentes() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);
        sessionRegistry.createSession(sessionB, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
        assertTrue(sessionRegistry.isSessionRevoked(sessionB));
    }

    function test_RevokeAllSessions_NaoAfetaOutrasIdentidades() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);
        sessionRegistry.createSession(sessionC, 2, bobDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
        assertFalse(sessionRegistry.isSessionRevoked(sessionC));
    }

    function test_RevokeAllSessions_SessoesNovasDepoisFicamAtivas() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        // sessionB criada DEPOIS do revokeAllSessions → deve ficar ativa
        bytes32 sessionNova = keccak256(abi.encodePacked("alice", "novo.com", uint256(99)));
        vm.warp(block.timestamp + 1); // avança o tempo 1 segundo
        sessionRegistry.createSession(sessionNova, 1, aliceDevice);

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
        assertFalse(sessionRegistry.isSessionRevoked(sessionNova));
    }

    function test_RevokeAllSessions_EmiteEvento() public {
        vm.prank(alice);
        vm.expectEmit(true, false, false, false);
        emit SessionRegistry.AllSessionsRevoked(1, block.timestamp);

        sessionRegistry.revokeAllSessions();
    }

    function test_RevokeAllSessions_SemIdentidade_Reverte() public {
        vm.prank(charlie);
        vm.expectRevert(SessionRegistry.NotIdentityController.selector);
        sessionRegistry.revokeAllSessions();
    }

    // -------------------------------------------------------------------------
    // getSessionsByIdentity
    // -------------------------------------------------------------------------

    function test_GetSessionsByIdentity_RetornaHashsCorretos() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);
        sessionRegistry.createSession(sessionB, 1, aliceDevice);
        sessionRegistry.createSession(sessionC, 2, bobDevice);

        bytes32[] memory aliceSessions = sessionRegistry.getSessionsByIdentity(1);
        assertEq(aliceSessions.length, 2);
        assertEq(aliceSessions[0], sessionA);
        assertEq(aliceSessions[1], sessionB);

        bytes32[] memory bobSessions = sessionRegistry.getSessionsByIdentity(2);
        assertEq(bobSessions.length, 1);
        assertEq(bobSessions[0], sessionC);
    }

    function test_GetSessionsByIdentity_IncluiRevogadas() public {
        sessionRegistry.createSession(sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);

        // Lista inclui revogadas — use isSessionRevoked para filtrar
        bytes32[] memory sessions = sessionRegistry.getSessionsByIdentity(1);
        assertEq(sessions.length, 1);
        assertEq(sessions[0], sessionA);
    }

    // -------------------------------------------------------------------------
    // getRevokedBefore
    // -------------------------------------------------------------------------

    function test_GetRevokedBefore_InicialmenteZero() public view {
        assertEq(sessionRegistry.getRevokedBefore(1), 0);
    }

    function test_GetRevokedBefore_AtualizaAposRevokeAll() public {
        uint256 antes = block.timestamp;

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        assertEq(sessionRegistry.getRevokedBefore(1), antes);
    }
}
