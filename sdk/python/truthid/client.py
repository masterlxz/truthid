import json
import time
import uuid
from dataclasses import asdict
from datetime import datetime, timezone
from typing import Optional

from eth_account import Account
from eth_account.messages import encode_defunct
from web3 import Web3

from .contracts import (
    DEVICE_REGISTRY_ADDRESSES,
    DEVICE_REGISTRY_ABI,
    SESSION_REGISTRY_ADDRESSES,
    SESSION_REGISTRY_ABI,
)
from .types import AuthChallenge, AuthResponse, DeviceStatus, RegisterSessionResult, SessionInfo, VerifyAuthResult

_RPC_URLS = {
    "base-sepolia": "https://sepolia.base.org",
    "base-mainnet": "https://mainnet.base.org",
}


class TruthIDClient:
    def __init__(self, network: str = "base-mainnet", rpc_url: Optional[str] = None):
        url = rpc_url or _RPC_URLS[network]
        self._w3 = Web3(Web3.HTTPProvider(url))
        self._devices = self._w3.eth.contract(
            address=Web3.to_checksum_address(DEVICE_REGISTRY_ADDRESSES[network]),
            abi=DEVICE_REGISTRY_ABI,
        )
        self._sessions = self._w3.eth.contract(
            address=Web3.to_checksum_address(SESSION_REGISTRY_ADDRESSES[network]),
            abi=SESSION_REGISTRY_ABI,
        )

    def create_challenge(self, origin: str) -> AuthChallenge:
        return AuthChallenge(
            type="challenge",
            nonce=str(uuid.uuid4()),
            issuedAt=int(time.time() * 1000),
            origin=origin,
        )

    def verify_auth_response(
        self,
        challenge: AuthChallenge,
        response: AuthResponse,
        ttl_ms: int = 30_000,
    ) -> VerifyAuthResult:
        # 1. User rejected
        if not response.approved:
            return VerifyAuthResult(valid=False, reason="User rejected the login request")

        # 2. TTL expired
        now_ms = int(time.time() * 1000)
        if now_ms - challenge.issuedAt > ttl_ms:
            return VerifyAuthResult(valid=False, reason="Challenge expired")

        # 3. Nonce must match the original challenge
        if challenge.nonce != response.nonce:
            return VerifyAuthResult(valid=False, reason="Nonce mismatch")

        # 4. Verify signature
        # separators=(',', ':') → compact JSON, matching jsonEncode() in Dart and JSON.stringify() in JS
        message = json.dumps(asdict(challenge), separators=(",", ":"))
        msg = encode_defunct(text=message)  # adds the Ethereum personal_sign prefix
        try:
            signer = Account.recover_message(msg, signature=response.signature)
        except Exception:
            return VerifyAuthResult(valid=False, reason="Invalid signature format")

        if signer.lower() != response.deviceAddress.lower():
            return VerifyAuthResult(valid=False, reason="Signature does not match device address")

        # 5. Device active on-chain
        checksum_addr = Web3.to_checksum_address(response.deviceAddress)
        is_active = self._devices.functions.isDeviceActive(checksum_addr).call()
        if not is_active:
            return VerifyAuthResult(valid=False, reason="Device is not active or has been revoked")

        # 6. Fetch the identityId associated with this device
        device = self._devices.functions.getDevice(checksum_addr).call()

        return VerifyAuthResult(
            valid=True,
            identity_id=device[0],          # identityId (uint256)
            device_address=response.deviceAddress,
        )

    def _read_session(self, hash_bytes: bytes) -> Optional[list]:
        # getSession() reverts on-chain (ContractLogicError) when the hash is unknown —
        # that's the only way this call can fail against a live RPC, so any error here
        # is treated as "doesn't exist yet" rather than propagated.
        try:
            session = self._sessions.functions.getSession(hash_bytes).call()
        except Exception:
            return None
        return session if session[4] else None  # session[4] == exists

    def verify_session(self, session_hash: str) -> SessionInfo:
        hash_bytes = bytes.fromhex(session_hash.removeprefix("0x"))

        session = self._read_session(hash_bytes)
        if session is None:
            return SessionInfo(exists=False, revoked=False)

        revoked = self._sessions.functions.isSessionRevoked(hash_bytes).call()
        created_at = datetime.fromtimestamp(session[2], tz=timezone.utc)  # createdAt (uint256 seconds)

        return SessionInfo(
            exists=True,
            revoked=revoked,
            identity_id=session[0],   # identityId
            device_pub_key=session[1], # devicePubKey
            created_at=created_at,
        )

    def register_session(
        self,
        nonce: str,
        identity_id: int,
        device_pub_key: str,
        session_signature: str,
        relayer_private_key: str,
    ) -> RegisterSessionResult:
        # Derives the same session hash the mobile computed: keccak256(utf8(nonce))
        session_hash = Web3.keccak(text=nonce)  # returns bytes

        # The TruthID mobile app (v14.9.5+) already creates the session on-chain itself
        # via UserOperation before it calls this integrator's callback — so this is
        # idempotent: if the session is already there, skip the transaction entirely
        # (avoids a guaranteed-revert and wasted relayer gas).
        if self._read_session(session_hash) is not None:
            return RegisterSessionResult(
                tx_hash=None,
                session_hash="0x" + session_hash.hex(),
                already_registered=True,
            )

        # Splits the compact 65-byte signature into the (r, s, v) the contract expects
        sig = session_signature.removeprefix("0x")
        r = bytes.fromhex(sig[0:64])    # bytes32
        s = bytes.fromhex(sig[64:128])  # bytes32
        v = int(sig[128:130], 16)       # uint8

        relayer_account = Account.from_key(relayer_private_key)
        checksum_dev = Web3.to_checksum_address(device_pub_key)

        tx = self._sessions.functions.createSession(
            session_hash, identity_id, checksum_dev, r, s, v
        ).build_transaction({
            "from": relayer_account.address,
            "nonce": self._w3.eth.get_transaction_count(relayer_account.address),
        })
        signed = relayer_account.sign_transaction(tx)
        tx_hash = self._w3.eth.send_raw_transaction(signed.raw_transaction)

        return RegisterSessionResult(
            tx_hash="0x" + tx_hash.hex(),
            session_hash="0x" + session_hash.hex(),
            already_registered=False,
        )

    def check_device_status(self, device_pub_key: str) -> DeviceStatus:
        checksum_addr = Web3.to_checksum_address(device_pub_key)
        device = self._devices.functions.getDevice(checksum_addr).call()

        if not device[5]:  # exists
            return DeviceStatus(exists=False, active=False)

        added_at = datetime.fromtimestamp(device[3], tz=timezone.utc)  # addedAt

        return DeviceStatus(
            exists=True,
            active=not device[4],  # revoked → active is the inverse
            label=device[2],
            identity_id=device[0],
            added_at=added_at,
        )
