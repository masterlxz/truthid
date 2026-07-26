import json
import time
from dataclasses import asdict
from unittest.mock import MagicMock

import pytest
from eth_account import Account
from eth_account.messages import encode_defunct

from truthid import TruthIDClient
from truthid.types import AuthChallenge, AuthResponse

# Real keypair used to sign challenges in these tests — exercises the actual
# personal_sign recovery path end-to-end instead of mocking it away.
_SIGNER = Account.create()
DEVICE_ADDRESS = _SIGNER.address


@pytest.fixture
def client():
    c = TruthIDClient(network="base-sepolia")
    c._devices = MagicMock()
    return c


def make_challenge(**overrides):
    fields = dict(
        type="challenge",
        nonce="nonce-1",
        issuedAt=int(time.time() * 1000),
        origin="https://example.com",
    )
    fields.update(overrides)
    return AuthChallenge(**fields)


def sign_challenge(challenge: AuthChallenge) -> str:
    message = json.dumps(asdict(challenge), separators=(",", ":"))
    signed = Account.sign_message(encode_defunct(text=message), private_key=_SIGNER.key)
    return "0x" + signed.signature.hex().removeprefix("0x")


class TestCreateChallenge:
    def test_returns_the_expected_shape(self, client):
        challenge = client.create_challenge("https://example.com")
        assert challenge.type == "challenge"
        assert challenge.origin == "https://example.com"
        assert isinstance(challenge.nonce, str)
        assert isinstance(challenge.issuedAt, int)

    def test_generates_a_different_nonce_every_call(self, client):
        a = client.create_challenge("https://example.com")
        b = client.create_challenge("https://example.com")
        assert a.nonce != b.nonce


class TestVerifyAuthResponse:
    def test_rejects_when_the_user_declined(self, client):
        challenge = make_challenge()
        response = AuthResponse(
            approved=False,
            nonce=challenge.nonce,
            signature="0x",
            deviceAddress=DEVICE_ADDRESS,
        )
        result = client.verify_auth_response(challenge, response)
        assert result.valid is False
        assert result.reason == "User rejected the login request"

    def test_rejects_an_expired_challenge(self, client):
        challenge = make_challenge(issuedAt=int(time.time() * 1000) - 60_000)
        response = AuthResponse(
            approved=True,
            nonce=challenge.nonce,
            signature="0x",
            deviceAddress=DEVICE_ADDRESS,
        )
        result = client.verify_auth_response(challenge, response, ttl_ms=30_000)
        assert result.valid is False
        assert result.reason == "Challenge expired"

    def test_rejects_a_nonce_mismatch(self, client):
        challenge = make_challenge()
        response = AuthResponse(
            approved=True,
            nonce="different-nonce",
            signature="0x",
            deviceAddress=DEVICE_ADDRESS,
        )
        result = client.verify_auth_response(challenge, response)
        assert result.valid is False
        assert result.reason == "Nonce mismatch"

    def test_rejects_a_malformed_signature(self, client):
        challenge = make_challenge()
        response = AuthResponse(
            approved=True,
            nonce=challenge.nonce,
            signature="0xnotasignature",
            deviceAddress=DEVICE_ADDRESS,
        )
        result = client.verify_auth_response(challenge, response)
        assert result.valid is False
        assert result.reason == "Invalid signature format"

    def test_rejects_a_signature_from_a_different_key(self, client):
        challenge = make_challenge()
        other_signer = Account.create()
        message = json.dumps(asdict(challenge), separators=(",", ":"))
        signed = Account.sign_message(encode_defunct(text=message), private_key=other_signer.key)
        response = AuthResponse(
            approved=True,
            nonce=challenge.nonce,
            signature="0x" + signed.signature.hex().removeprefix("0x"),
            deviceAddress=DEVICE_ADDRESS,  # claims to be _SIGNER, but signed with other_signer
        )
        result = client.verify_auth_response(challenge, response)
        assert result.valid is False
        assert result.reason == "Signature does not match device address"

    def test_rejects_an_inactive_device(self, client):
        challenge = make_challenge()
        response = AuthResponse(
            approved=True,
            nonce=challenge.nonce,
            signature=sign_challenge(challenge),
            deviceAddress=DEVICE_ADDRESS,
        )
        client._devices.functions.isDeviceActive.return_value.call.return_value = False
        result = client.verify_auth_response(challenge, response)
        assert result.valid is False
        assert result.reason == "Device is not active or has been revoked"

    def test_succeeds_for_a_valid_active_device(self, client):
        challenge = make_challenge()
        response = AuthResponse(
            approved=True,
            nonce=challenge.nonce,
            signature=sign_challenge(challenge),
            deviceAddress=DEVICE_ADDRESS,
        )
        client._devices.functions.isDeviceActive.return_value.call.return_value = True
        client._devices.functions.getDevice.return_value.call.return_value = [42, DEVICE_ADDRESS, "", 0, False, True]
        result = client.verify_auth_response(challenge, response)
        assert result.valid is True
        assert result.identity_id == 42
        assert result.device_address == DEVICE_ADDRESS


def test_register_session_no_longer_exists(client):
    # The mobile app registers sessions on-chain itself now — see smart_account.py
    # for the replacement capability this SDK gained instead.
    assert not hasattr(client, "register_session")
