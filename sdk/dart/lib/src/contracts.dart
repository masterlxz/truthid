import 'types.dart';

const Map<Network, String> identityRegistryAddresses = {
  Network.baseSepolia: '0xb56DbCB7580c097d3f64808064C2d5609dD6B243',
  Network.baseMainnet: '0x97787D6EE3EfD76962dc7E3Bf143E659D9961962',
};

// Immutables of the TruthIDAccountFactory (ERC-4337 smart account), used to
// predict a controller address via CREATE2 before it's ever deployed — see
// smart_account.dart. Same source as desktop/src/config/truthidAccount.ts.
const Map<Network, String> smartAccountFactoryAddresses = {
  Network.baseSepolia: '0xc4Ca3A79BAb993C4B7cFD312C80c20b2182F8c1e',
  Network.baseMainnet: '0xc2C86cB7d8694EcA8BaAdD95B14842E8643aB262',
};

const Map<Network, String> recoveryManagerAddresses = {
  Network.baseSepolia: '0x97787D6EE3EfD76962dc7E3Bf143E659D9961962',
  Network.baseMainnet: '0x42Ca394c23aB027e877B9900B384f59E2Af23470',
};

// ERC-4337 EntryPoint v0.7 — same canonical singleton address on every chain.
const String entryPointV07Address = '0x0000000071727De22E5E9d8BAf0edAc6f37da032';

const Map<Network, String> deviceRegistryAddresses = {
  Network.baseSepolia: '0xe40e10627D307B0994f1856584bcc5DC323a4330',
  Network.baseMainnet: '0x937702CBABDab0EEBD1A29f0a7A658FeF4582543',
};

const String deviceRegistryAbi = '''
[
  {
    "type": "function",
    "name": "isDeviceActive",
    "inputs": [{ "name": "devicePubKey", "type": "address" }],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getDevice",
    "inputs": [{ "name": "devicePubKey", "type": "address" }],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "components": [
          { "name": "identityId", "type": "uint256" },
          { "name": "pubKey", "type": "address" },
          { "name": "label", "type": "string" },
          { "name": "addedAt", "type": "uint256" },
          { "name": "revoked", "type": "bool" },
          { "name": "exists", "type": "bool" }
        ]
      }
    ],
    "stateMutability": "view"
  }
]
''';

const Map<Network, String> sessionRegistryAddresses = {
  Network.baseSepolia: '0xc2C86cB7d8694EcA8BaAdD95B14842E8643aB262',
  Network.baseMainnet: '0x8C65527eDA3ce7754Bf87B34aC4ec8ce74D647e2',
};

const String sessionRegistryAbi = '''
[
  {
    "type": "function",
    "name": "isSessionRevoked",
    "inputs": [{ "name": "hash", "type": "bytes32" }],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getSession",
    "inputs": [{ "name": "hash", "type": "bytes32" }],
    "outputs": [
      {
        "name": "",
        "type": "tuple",
        "components": [
          { "name": "identityId", "type": "uint256" },
          { "name": "devicePubKey", "type": "address" },
          { "name": "createdAt", "type": "uint256" },
          { "name": "revoked", "type": "bool" },
          { "name": "exists", "type": "bool" }
        ]
      }
    ],
    "stateMutability": "view"
  }
]
''';
