from dataclasses import dataclass
from datetime import datetime
from typing import Optional


# camelCase fields: map directly to the mobile's JSON protocol
@dataclass
class AuthChallenge:
    type: str
    nonce: str
    issuedAt: int  # Unix timestamp in ms
    origin: str


@dataclass
class AuthResponse:
    approved: bool
    nonce: str
    signature: str              # secp256k1 signature in hex ("0x...")
    deviceAddress: str          # Ethereum address derived from the device key
    sessionSignature: Optional[str] = None  # personal_sign over keccak256(nonce), present when approved


@dataclass
class VerifyAuthResult:
    valid: bool
    identity_id: Optional[int] = None
    device_address: Optional[str] = None
    reason: Optional[str] = None


@dataclass
class SessionInfo:
    exists: bool
    revoked: bool
    identity_id: Optional[int] = None
    device_pub_key: Optional[str] = None
    created_at: Optional[datetime] = None


@dataclass
class DeviceStatus:
    exists: bool
    active: bool
    label: Optional[str] = None
    identity_id: Optional[int] = None
    added_at: Optional[datetime] = None


@dataclass
class RegisterSessionResult:
    tx_hash: str      # "0x..." — the transaction submitted to the network
    session_hash: str # "0x..." — keccak256(nonce), the on-chain session identifier
