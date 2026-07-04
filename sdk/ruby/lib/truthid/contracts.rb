module TruthID
  module Contracts
    DEVICE_REGISTRY_ADDRESSES = {
      "base-sepolia" => "0x5F92f95ABaACC85ADAde04F072d30b67eD8c896e",
      "base-mainnet" => "0x2be6a81B22823510c7F3Fa93E70B85aAd4fB488d"
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
      "base-sepolia" => "0x925a0bCE2EA3AcF25454354197565B799E786e97",
      "base-mainnet" => "0xbf8b940dDC3754D06ee5281209Bd3dD58852BF65"
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
