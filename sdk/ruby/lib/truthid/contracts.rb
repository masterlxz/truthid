module TruthID
  module Contracts
    DEVICE_REGISTRY_ADDRESSES = {
      "base-sepolia" => "0xC61b82C29D80098558D7Ca73CC47D907B62f9e3F",
      "base-mainnet" => "0xea61a59810Ee981B5FB7C1d42FE348Cbe8aE5344"
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
      "base-sepolia" => "0x80878CC2B339D187051EEd905699613a0ed84B12",
      "base-mainnet" => "0x1F34F33f1061E44028e28a4e17E43d4eaE92f7FA"
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
