// ABI fragments used by the mobile app.
// Only the functions actually called are listed — no need for the full ABI.
// Source: contracts/src/SessionRegistry.sol and DeviceRegistry.sol
// Update here when the contract interface changes.

const String sessionRegistryAbi = '''[
  {
    "type": "function",
    "name": "getSessionsByIdentity",
    "inputs": [{"name": "identityId", "type": "uint256"}],
    "outputs": [{"name": "", "type": "bytes32[]"}],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getSession",
    "inputs": [{"name": "hash", "type": "bytes32"}],
    "outputs": [{
      "name": "",
      "type": "tuple",
      "components": [
        {"name": "identityId", "type": "uint256"},
        {"name": "devicePubKey", "type": "address"},
        {"name": "createdAt", "type": "uint256"},
        {"name": "revoked", "type": "bool"},
        {"name": "exists", "type": "bool"}
      ]
    }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "isSessionRevoked",
    "inputs": [{"name": "hash", "type": "bytes32"}],
    "outputs": [{"name": "", "type": "bool"}],
    "stateMutability": "view"
  }
]''';

const String deviceRegistryAbi = '''[
  {
    "type": "function",
    "name": "getDevice",
    "inputs": [{"name": "devicePubKey", "type": "address"}],
    "outputs": [{
      "name": "",
      "type": "tuple",
      "components": [
        {"name": "identityId", "type": "uint256"},
        {"name": "pubKey", "type": "address"},
        {"name": "label", "type": "string"},
        {"name": "addedAt", "type": "uint256"},
        {"name": "revoked", "type": "bool"},
        {"name": "exists", "type": "bool"}
      ]
    }],
    "stateMutability": "view"
  }
]''';
