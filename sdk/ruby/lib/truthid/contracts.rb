module TruthID
  module Contracts
    DEVICE_REGISTRY_ADDRESSES = {
      "base-sepolia" => "0x867EA636FDF324B0Cc4a631C70421580e2Bbe91c",
      "base-mainnet" => "0x4Fd53d70553df00D42c015EB35E2626cB80b1614"
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
      "base-sepolia" => "0xFE49Cec3a927136f7F18E521BF1547f00b09B17f",
      "base-mainnet" => "0x66F10F8c38b3F35551e90ACa3c675F5E3432C6Df"
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
