from eth_abi import encode as abi_encode
from web3 import Web3

from .contracts import (
    DEVICE_REGISTRY_ADDRESSES,
    ENTRY_POINT_V07_ADDRESS,
    IDENTITY_REGISTRY_ADDRESSES,
    RECOVERY_MANAGER_ADDRESSES,
    SMART_ACCOUNT_FACTORY_ADDRESSES,
)
from .truthid_account_bytecode import TRUTHID_ACCOUNT_CREATION_CODE


def compute_smart_account_address(
    ledger_address: str,
    network: str = "base-mainnet",
    index: int = 0,
) -> str:
    """Predicts a TruthIDAccount's address via CREATE2 before it's deployed —
    pure local computation, no RPC call needed. Same algorithm as
    desktop/src/utils/computeSmartAccountAddress.ts and the TypeScript SDK's
    computeSmartAccountAddress, ported here so integrators don't need a
    TruthID server (or the desktop app) to know a user's smart account
    address ahead of time.
    """
    factory_address = SMART_ACCOUNT_FACTORY_ADDRESSES[network]
    ledger_checksum = Web3.to_checksum_address(ledger_address)

    # Must be solidity_keccak (packed), not abi_encode — the contract uses
    # abi.encodePacked(owner_, index) (address with no left-pad, 20 bytes),
    # not abi.encode (address left-padded to 32 bytes). Using the wrong
    # encoding here produces a different salt than the factory computes
    # on-chain, yielding a controller address that never matches reality.
    salt = Web3.solidity_keccak(["address", "uint256"], [ledger_checksum, index])

    constructor_args = abi_encode(
        ["address", "address", "address", "address", "address"],
        [
            ENTRY_POINT_V07_ADDRESS,
            DEVICE_REGISTRY_ADDRESSES[network],
            IDENTITY_REGISTRY_ADDRESSES[network],
            RECOVERY_MANAGER_ADDRESSES[network],
            ledger_checksum,
        ],
    )

    creation_code_bytes = bytes.fromhex(TRUTHID_ACCOUNT_CREATION_CODE.removeprefix("0x"))
    init_code_hash = Web3.keccak(creation_code_bytes + constructor_args)

    factory_bytes = bytes.fromhex(Web3.to_checksum_address(factory_address).removeprefix("0x"))
    create2_input = b"\xff" + factory_bytes + salt + init_code_hash
    address_hash = Web3.keccak(create2_input)

    return Web3.to_checksum_address(address_hash[-20:])
