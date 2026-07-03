IDENTITY_REGISTRY_ADDRESSES = {
    "base-sepolia": "0xA93123C1ca438D9F56E4E599363F4d973d61A307",
    "base-mainnet": "0x056b826e8E31F1dCD95886571e92CA206cFB6337",
}

DEVICE_REGISTRY_ADDRESSES = {
    "base-sepolia": "0x7339aB41d3E16577311A6B2e468224b4aAdB88A7",
    "base-mainnet": "0xa42dfF462D90a11f2fbd53aD2fA4E4dd3dDBECeC",
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
    "base-sepolia": "0x3DcCF11435C8c22217e27a629b4173Bc9e7c1781",
    "base-mainnet": "0x2d4a25324B5e3E93fa4d3201396Cf1E15cC2A221",
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
