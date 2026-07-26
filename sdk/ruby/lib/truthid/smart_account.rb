require "eth"

require_relative "contracts"
require_relative "truthid_account_bytecode"

module TruthID
  # Predicts a TruthIDAccount's address via CREATE2 before it's deployed —
  # pure local computation, no RPC call needed. Same algorithm as
  # desktop/src/utils/computeSmartAccountAddress.ts and the TypeScript/Python
  # SDKs' compute_smart_account_address, ported here so integrators don't
  # need a TruthID server (or the desktop app) to know a user's smart account
  # address ahead of time.
  def self.compute_smart_account_address(ledger_address, network: "base-mainnet", index: 0)
    factory_address = Contracts::SMART_ACCOUNT_FACTORY_ADDRESSES.fetch(network)
    ledger_checksummed = Eth::Address.new(ledger_address).checksummed

    # Must be packed (Eth::Abi.encode(..., true)), not the default ABI
    # encoding — the contract uses abi.encodePacked(owner_, index) (address
    # with no left-pad, 20 bytes), not abi.encode (address left-padded to 32
    # bytes). Using the wrong encoding here produces a different salt than
    # the factory computes on-chain, yielding a controller address that
    # never matches reality.
    salt = Eth::Util.keccak256(
      Eth::Abi.encode(["address", "uint256"], [ledger_checksummed, index], true)
    )

    constructor_args = Eth::Abi.encode(
      ["address", "address", "address", "address", "address"],
      [
        Contracts::ENTRY_POINT_V07_ADDRESS,
        Contracts::DEVICE_REGISTRY_ADDRESSES.fetch(network),
        Contracts::IDENTITY_REGISTRY_ADDRESSES.fetch(network),
        Contracts::RECOVERY_MANAGER_ADDRESSES.fetch(network),
        ledger_checksummed,
      ]
    )

    creation_code_bytes = Eth::Util.hex_to_bin(TRUTHID_ACCOUNT_CREATION_CODE)
    init_code_hash = Eth::Util.keccak256(creation_code_bytes + constructor_args)

    factory_bytes = Eth::Util.hex_to_bin(Eth::Address.new(factory_address).checksummed)
    create2_input = "\xff".b + factory_bytes + salt + init_code_hash
    address_hash = Eth::Util.keccak256(create2_input)

    Eth::Address.new("0x" + address_hash[-20..].unpack1("H*")).checksummed
  end
end
