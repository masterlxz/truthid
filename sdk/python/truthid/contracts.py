IDENTITY_REGISTRY_ADDRESSES = {
    "base-sepolia": "0x35D21c65980cBd2dAE7576e1bf6b8e46C9e180BF",
    "base-mainnet": "0xbf097EC74d0Cc9b16D3d94EaCa62060d89A63b17",
}

DEVICE_REGISTRY_ADDRESSES = {
    "base-sepolia": "0x225c67a98c9D675fE595ae05a2F9249C34d9C60a",
    "base-mainnet": "0x4A7a307cb6872bde24BAf3E9de2BeC3Ddd03e144",
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
    "base-sepolia": "0xdeD2Ad865069CA6546172926540D3A3Aa73C1CA6",
    "base-mainnet": "0x24074587a2aFB3aa5491361BB0a5eBee90797D1B",
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
