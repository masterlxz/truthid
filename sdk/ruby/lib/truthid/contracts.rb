module TruthID
  module Contracts
    IDENTITY_REGISTRY_ADDRESSES = {
      "base-sepolia" => "0xb56DbCB7580c097d3f64808064C2d5609dD6B243",
      "base-mainnet" => "0x97787D6EE3EfD76962dc7E3Bf143E659D9961962"
    }.freeze

    # Immutables of the TruthIDAccountFactory (ERC-4337 smart account), used
    # to predict a controller address via CREATE2 before it's ever deployed —
    # see smart_account.rb. Same source as
    # desktop/src/config/truthidAccount.ts.
    SMART_ACCOUNT_FACTORY_ADDRESSES = {
      "base-sepolia" => "0xc4Ca3A79BAb993C4B7cFD312C80c20b2182F8c1e",
      "base-mainnet" => "0xc2C86cB7d8694EcA8BaAdD95B14842E8643aB262"
    }.freeze

    RECOVERY_MANAGER_ADDRESSES = {
      "base-sepolia" => "0x97787D6EE3EfD76962dc7E3Bf143E659D9961962",
      "base-mainnet" => "0x42Ca394c23aB027e877B9900B384f59E2Af23470"
    }.freeze

    # ERC-4337 EntryPoint v0.7 — same canonical singleton address on every chain.
    ENTRY_POINT_V07_ADDRESS = "0x0000000071727De22E5E9d8BAf0edAc6f37da032".freeze

    DEVICE_REGISTRY_ADDRESSES = {
      "base-sepolia" => "0xe40e10627D307B0994f1856584bcc5DC323a4330",
      "base-mainnet" => "0x937702CBABDab0EEBD1A29f0a7A658FeF4582543"
    }.freeze
    DEVICE_REGISTRY_ABI = [
      {
        "type" => "function",
        "name" => "isDeviceActive",
        "inputs" => [{ "name" => "devicePubKey", "type" => "address" }],
        "outputs" => [{ "name" => "", "type" => "bool" }],
        "stateMutability" => "view"
      },
      {
        "type" => "function",
        "name" => "getDevice",
        "inputs" => [{ "name" => "devicePubKey", "type" => "address" }],
        "outputs" => [
          {
            "name" => "",
            "type" => "tuple",
            "components" => [
              { "name" => "identityId", "type" => "uint256" },
              { "name" => "pubKey",     "type" => "address" },
              { "name" => "label",      "type" => "string"  },
              { "name" => "addedAt",    "type" => "uint256" },
              { "name" => "revoked",    "type" => "bool"    },
              { "name" => "exists",     "type" => "bool"    }
            ]
          }
        ],
        "stateMutability" => "view"
      }
    ].freeze

    SESSION_REGISTRY_ADDRESSES = {
      "base-sepolia" => "0xc2C86cB7d8694EcA8BaAdD95B14842E8643aB262",
      "base-mainnet" => "0x8C65527eDA3ce7754Bf87B34aC4ec8ce74D647e2"
    }.freeze
    SESSION_REGISTRY_ABI = [
      {
        "type" => "function",
        "name" => "isSessionRevoked",
        "inputs" => [{ "name" => "hash", "type" => "bytes32" }],
        "outputs" => [{ "name" => "", "type" => "bool" }],
        "stateMutability" => "view"
      },
      {
        "type" => "function",
        "name" => "getSession",
        "inputs" => [{ "name" => "hash", "type" => "bytes32" }],
        "outputs" => [
          {
            "name" => "",
            "type" => "tuple",
            "components" => [
              { "name" => "identityId",  "type" => "uint256" },
              { "name" => "devicePubKey","type" => "address" },
              { "name" => "createdAt",   "type" => "uint256" },
              { "name" => "revoked",     "type" => "bool"    },
              { "name" => "exists",      "type" => "bool"    }
            ]
          }
        ],
        "stateMutability" => "view"
      }
    ].freeze
  end
end
