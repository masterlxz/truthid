from dataclasses import dataclass
from datetime import datetime
from typing import Optional


# Campos em camelCase: mapeiam diretamente para o protocolo JSON do mobile
@dataclass
class AuthChallenge:
    type: str
    nonce: str
    issuedAt: int  # timestamp Unix em ms
    origin: str


@dataclass
class AuthResponse:
    approved: bool
    nonce: str
    signature: str      # assinatura secp256k1 em hex ("0x...")
    deviceAddress: str  # endereço Ethereum da chave do device


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
