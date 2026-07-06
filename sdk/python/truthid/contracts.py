IDENTITY_REGISTRY_ADDRESSES = {
    "base-sepolia": "0x7582E1c55fAFF19619A6c0a8b6575855d4e933d0",
    "base-mainnet": "0xC11426fd1cB103bC56dD3263325b34f2AcEe9903",
}

DEVICE_REGISTRY_ADDRESSES = {
    "base-sepolia": "0x867EA636FDF324B0Cc4a631C70421580e2Bbe91c",
    "base-mainnet": "0x4Fd53d70553df00D42c015EB35E2626cB80b1614",
}
DEVICE_REGISTRY_ABI = [
    {
        "type": "function",
        "name": "isDeviceActive",
        "inputs": [{"name": "devicePubKey", "type": "address"}],
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "getDevice",
        "inputs": [{"name": "devicePubKey", "type": "address"}],
        "outputs": [
            {
                "name": "",
                "type": "tuple",
                "components": [
                    {"name": "identityId", "type": "uint256"},
                    {"name": "pubKey", "type": "address"},
                    {"name": "label", "type": "string"},
                    {"name": "addedAt", "type": "uint256"},
                    {"name": "revoked", "type": "bool"},
                    {"name": "exists", "type": "bool"},
                ],
            }
        ],
        "stateMutability": "view",
    },
]

SESSION_REGISTRY_ADDRESSES = {
    "base-sepolia": "0xFE49Cec3a927136f7F18E521BF1547f00b09B17f",
    "base-mainnet": "0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df",
}
SESSION_REGISTRY_ABI = [
    {
        "type": "function",
        "name": "isSessionRevoked",
        "inputs": [{"name": "hash", "type": "bytes32"}],
        "outputs": [{"name": "", "type": "bool"}],
        "stateMutability": "view",
    },
    {
        "type": "function",
        "name": "getSession",
        "inputs": [{"name": "hash", "type": "bytes32"}],
        "outputs": [
            {
                "name": "",
                "type": "tuple",
                "components": [
                    {"name": "identityId", "type": "uint256"},
                    {"name": "devicePubKey", "type": "address"},
                    {"name": "createdAt", "type": "uint256"},
                    {"name": "revoked", "type": "bool"},
                    {"name": "exists", "type": "bool"},
                ],
            }
        ],
        "stateMutability": "view",
    },
]
