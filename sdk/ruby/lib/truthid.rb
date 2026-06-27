require_relative "truthid/contracts"
require_relative "truthid/types"
require_relative "truthid/client"

module TruthID
  # Alias para manter a API consistente com os outros SDKs
  # TypeScript: new TruthIDClient(...)
  # Python:     TruthIDClient(...)
  # Ruby:       TruthID::Client.new(...)  ou  TruthID.new_client(...)
  def self.new_client(network: "base-sepolia", rpc_url: nil)
    Client.new(network: network, rpc_url: rpc_url)
  end
end
