// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IdentityRegistry} from "../src/IdentityRegistry.sol";
import {DeviceRegistry} from "../src/DeviceRegistry.sol";
import {SessionRegistry} from "../src/SessionRegistry.sol";
import {IdentityConsentHelper} from "./IdentityConsentHelper.sol";

contract SessionRegistryTest is Test, IdentityConsentHelper {
    IdentityRegistry public identityRegistry;
    DeviceRegistry public deviceRegistry;
    SessionRegistry public sessionRegistry;

    address public alice;
    uint256 aliceKey;
    address public bob;
    uint256 bobKey;
    address public charlie = makeAddr("charlie"); // nunca cria identidade

    // Precisamos da chave PRIVADA dos devices (não só do endereço) para
    // assinar os hashes de sessão nos testes — makeAddrAndKey devolve os dois.
    address public aliceDevice;
    uint256 public aliceDeviceKey;
    address public bobDevice;
    uint256 public bobDeviceKey;

    // Hashes simulando sessões reais (keccak256 de dados de autenticação)
    bytes32 public sessionA = keccak256(abi.encodePacked("alice", "loja.com", uint256(1)));
    bytes32 public sessionB = keccak256(abi.encodePacked("alice", "banco.com", uint256(2)));
    bytes32 public sessionC = keccak256(abi.encodePacked("bob", "loja.com", uint256(3)));

    bytes32 constant SALT = keccak256("test-salt");

    function setUp() public {
        (alice, aliceKey) = makeAddrAndKey("alice");
        (bob, bobKey) = makeAddrAndKey("bob");

        identityRegistry = new IdentityRegistry();
        deviceRegistry = new DeviceRegistry(address(identityRegistry));
        sessionRegistry = new SessionRegistry(address(identityRegistry), address(deviceRegistry));

        vm.prank(alice);
        _createIdentity(identityRegistry, aliceKey, "alice.id"); // identityId = 1

        vm.prank(bob);
        _createIdentity(identityRegistry, bobKey, "bob.id"); // identityId = 2

        (aliceDevice, aliceDeviceKey) = makeAddrAndKey("alice-device");
        (bobDevice, bobDeviceKey) = makeAddrAndKey("bob-device");

        _registerDevice(alice, aliceDevice, "Alice's phone");
        _registerDevice(bob, bobDevice, "Bob's phone");
    }

    // Atalho: registra um device via commit-reveal (igual DeviceRegistry.t.sol)
    function _registerDevice(address controller, address devicePubKey, string memory label)
        internal
    {
        bytes32 commitment = keccak256(abi.encodePacked(devicePubKey, SALT, controller));

        vm.prank(controller);
        deviceRegistry.commitDevice(commitment);

        vm.roll(block.number + 1);

        vm.prank(controller);
        deviceRegistry.registerDevice(devicePubKey, label, SALT, "");
    }

    // Atalho: assina `hash` com a chave do device (mesmo formato que o
    // contrato espera — prefixo "\x19Ethereum Signed Message:\n32") e chama
    // createSession. Quem efetivamente SUBMETE a transação é quem estiver
    // sob `vm.prank` no momento da chamada — fica a critério de cada teste.
    function _createSession(
        uint256 devicePrivateKey,
        bytes32 hash,
        uint256 identityId,
        address devicePubKey
    ) internal {
        bytes32 ethSignedHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", hash)
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(devicePrivateKey, ethSignedHash);
        sessionRegistry.createSession(hash, identityId, devicePubKey, r, s, v);
    }

    // -------------------------------------------------------------------------
    // createSession — caminho feliz
    // -------------------------------------------------------------------------

    function test_CreateSession_Success() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        SessionRegistry.Session memory s = sessionRegistry.getSession(sessionA);
        assertEq(s.identityId, 1);
        assertEq(s.devicePubKey, aliceDevice);
        assertEq(s.createdAt, block.timestamp);
        assertFalse(s.revoked);
        assertTrue(s.exists);
    }

    function test_CreateSession_QualquerUmPodeSubmeter() public {
        // O SDK do website (aqui simulado por "charlie") é quem costuma
        // enviar a transação — mas só funciona se ele tiver a assinatura
        // real do device, que ele não tem como forjar sem a chave privada.
        vm.prank(charlie);
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        assertFalse(sessionRegistry.isSessionRevoked(sessionA));
    }

    function test_CreateSession_EmiteEvento() public {
        vm.expectEmit(true, true, true, false);
        emit SessionRegistry.SessionCreated(1, sessionA, aliceDevice);

        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
    }

    // -------------------------------------------------------------------------
    // createSession — erros
    // -------------------------------------------------------------------------

    function test_CreateSession_HashDuplicado_Reverte() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.expectRevert(
            abi.encodeWithSelector(SessionRegistry.SessionAlreadyExists.selector, sessionA)
        );
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
    }

    function test_Revert_CreateSession_InvalidSignature() public {
        // Assinado pela chave do BOB, mas alegando ser o device da alice —
        // sem a chave privada certa, ecrecover nunca devolve aliceDevice.
        bytes32 ethSignedHash =
            keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", sessionA));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobDeviceKey, ethSignedHash);

        vm.expectRevert(SessionRegistry.InvalidSessionSignature.selector);
        sessionRegistry.createSession(sessionA, 1, aliceDevice, r, s, v);
    }

    function test_Revert_CreateSession_DeviceClaimingWrongIdentity() public {
        // aliceDevice assina de verdade (prova de posse ok), mas a sessão
        // alega pertencer à identidade do bob (2) — aliceDevice não é device
        // do bob no DeviceRegistry, então deve reverter.
        vm.expectRevert(SessionRegistry.DeviceNotOwnedByIdentity.selector);
        _createSession(aliceDeviceKey, sessionA, 2, aliceDevice);
    }

    function test_Revert_CreateSession_RevokedDevice() public {
        vm.prank(alice);
        deviceRegistry.revokeDevice(aliceDevice);

        vm.expectRevert(SessionRegistry.DeviceNotOwnedByIdentity.selector);
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
    }

    function test_Revert_CreateSession_UnknownDevice() public {
        (address ghostDevice, uint256 ghostKey) = makeAddrAndKey("ghost-device");

        vm.expectRevert(abi.encodeWithSelector(DeviceRegistry.DeviceNotFound.selector, ghostDevice));
        _createSession(ghostKey, sessionA, 1, ghostDevice);
    }

    // -------------------------------------------------------------------------
    // isSessionRevoked
    // -------------------------------------------------------------------------

    function test_IsSessionRevoked_HashDesconhecido_RetornaTrue() public view {
        bytes32 hashDesconhecido = keccak256("nao existe");
        assertTrue(sessionRegistry.isSessionRevoked(hashDesconhecido));
    }

    function test_IsSessionRevoked_SessaoAtiva_RetornaFalse() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
        assertFalse(sessionRegistry.isSessionRevoked(sessionA));
    }

    // -------------------------------------------------------------------------
    // revokeSession — caminho feliz
    // -------------------------------------------------------------------------

    function test_RevokeSession_Success() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
    }

    function test_RevokeSession_EmiteEvento() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.expectEmit(true, true, false, false);
        emit SessionRegistry.SessionRevoked(1, sessionA);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_NaoAfetaOutrasSessoes() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
        _createSession(aliceDeviceKey, sessionB, 1, aliceDevice);

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
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeSession(sessionA);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(SessionRegistry.SessionAlreadyRevoked.selector, sessionA)
        );
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_ControllerErrado_Reverte() public {
        // sessionA pertence à identidade 1 (alice), bob não pode revogar
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.prank(bob);
        vm.expectRevert(SessionRegistry.NotIdentityController.selector);
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_SemIdentidade_Reverte() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.prank(charlie);
        vm.expectRevert(SessionRegistry.NotIdentityController.selector);
        sessionRegistry.revokeSession(sessionA);
    }

    function test_RevokeSession_JaRevogadaPorRevokeAll_Reverte() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        // sessionA já está revogada pelo revokeAllSessions
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(SessionRegistry.SessionAlreadyRevoked.selector, sessionA)
        );
        sessionRegistry.revokeSession(sessionA);
    }

    // -------------------------------------------------------------------------
    // revokeAllSessions
    // -------------------------------------------------------------------------

    function test_RevokeAllSessions_RevogaSessoesExistentes() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
        _createSession(aliceDeviceKey, sessionB, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
        assertTrue(sessionRegistry.isSessionRevoked(sessionB));
    }

    function test_RevokeAllSessions_NaoAfetaOutrasIdentidades() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
        _createSession(bobDeviceKey, sessionC, 2, bobDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        assertTrue(sessionRegistry.isSessionRevoked(sessionA));
        assertFalse(sessionRegistry.isSessionRevoked(sessionC));
    }

    function test_RevokeAllSessions_SessoesNovasDepoisFicamAtivas() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

        vm.prank(alice);
        sessionRegistry.revokeAllSessions();

        // sessionB criada DEPOIS do revokeAllSessions → deve ficar ativa
        bytes32 sessionNova = keccak256(abi.encodePacked("alice", "novo.com", uint256(99)));
        vm.warp(block.timestamp + 1); // avança o tempo 1 segundo
        _createSession(aliceDeviceKey, sessionNova, 1, aliceDevice);

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
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);
        _createSession(aliceDeviceKey, sessionB, 1, aliceDevice);
        _createSession(bobDeviceKey, sessionC, 2, bobDevice);

        bytes32[] memory aliceSessions = sessionRegistry.getSessionsByIdentity(1);
        assertEq(aliceSessions.length, 2);
        assertEq(aliceSessions[0], sessionA);
        assertEq(aliceSessions[1], sessionB);

        bytes32[] memory bobSessions = sessionRegistry.getSessionsByIdentity(2);
        assertEq(bobSessions.length, 1);
        assertEq(bobSessions[0], sessionC);
    }

    function test_GetSessionsByIdentity_IncluiRevogadas() public {
        _createSession(aliceDeviceKey, sessionA, 1, aliceDevice);

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
