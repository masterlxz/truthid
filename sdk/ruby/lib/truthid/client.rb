require "json"
require "securerandom"
require "eth"

require_relative "contracts"
require_relative "types"

module TruthID
  class Client
    RPC_URLS = {
      "base-sepolia" => "https://sepolia.base.org",
      "base-mainnet" => "https://mainnet.base.org"
    }.freeze

    def initialize(network: "base-sepolia", rpc_url: nil)
      url = rpc_url || RPC_URLS.fetch(network)
      @rpc = Eth::Client.create(url)
      @devices = Eth::Contract.from_abi(
        name: "DeviceRegistry",
        address: Contracts::DEVICE_REGISTRY_ADDRESS,
        abi: Contracts::DEVICE_REGISTRY_ABI
      )
      @sessions = Eth::Contract.from_abi(
        name: "SessionRegistry",
        address: Contracts::SESSION_REGISTRY_ADDRESS,
        abi: Contracts::SESSION_REGISTRY_ABI
      )
    end

    def create_challenge(origin)
      AuthChallenge.new(
        type:      "challenge",
        nonce:     SecureRandom.uuid,
        issued_at: (Time.now.to_f * 1000).to_i,
        origin:    origin
      )
    end

    def verify_auth_response(challenge, response, ttl_ms: 30_000)
      # 1. Usuário recusou
      unless response.approved
        return VerifyAuthResult.new(valid: false, reason: "User rejected the login request")
      end

      # 2. TTL expirado
      now_ms = (Time.now.to_f * 1000).to_i
      if now_ms - challenge.issued_at > ttl_ms
        return VerifyAuthResult.new(valid: false, reason: "Challenge expired")
      end

      # 3. Nonce bate com o challenge original
      if challenge.nonce != response.nonce
        return VerifyAuthResult.new(valid: false, reason: "Nonce mismatch")
      end

      # 4. Verificar assinatura
      # JSON.generate já produz JSON compacto (sem espaços) — compatível com Dart e JS
      message = JSON.generate(challenge.to_h)
      begin
        signer = Eth::Signature.personal_recover(message, response.signature)
      rescue => e
        return VerifyAuthResult.new(valid: false, reason: "Invalid signature format")
      end

      if signer.downcase != response.device_address.downcase
        return VerifyAuthResult.new(valid: false, reason: "Signature does not match device address")
      end

      # 5. Device ativo na blockchain
      is_active = @rpc.call(@devices, "isDeviceActive", response.device_address)
      unless is_active
        return VerifyAuthResult.new(valid: false, reason: "Device is not active or has been revoked")
      end

      # 6. Buscar identityId do device
      device = @rpc.call(@devices, "getDevice", response.device_address)

      VerifyAuthResult.new(
        valid:          true,
        identity_id:    device[0],
        device_address: response.device_address
      )
    end

    def verify_session(session_hash)
      # bytes32: converte hex string → 32 bytes binários
      hash_bytes = [session_hash.delete_prefix("0x")].pack("H*")

      session = @rpc.call(@sessions, "getSession", hash_bytes)
      return SessionInfo.new(exists: false, revoked: false) unless session[4] # exists

      revoked = @rpc.call(@sessions, "isSessionRevoked", hash_bytes)

      SessionInfo.new(
        exists:       true,
        revoked:      revoked,
        identity_id:  session[0],
        device_pub_key: session[1],
        created_at:   Time.at(session[2]).utc
      )
    end

    def check_device_status(device_pub_key)
      device = @rpc.call(@devices, "getDevice", device_pub_key)
      return DeviceStatus.new(exists: false, active: false) unless device[5] # exists

      DeviceStatus.new(
        exists:      true,
        active:      !device[4], # revoked → active é o inverso
        label:       device[2],
        identity_id: device[0],
        added_at:    Time.at(device[3]).utc
      )
    end
  end
end
