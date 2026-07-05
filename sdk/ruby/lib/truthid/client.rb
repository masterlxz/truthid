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

    def initialize(network: "base-mainnet", rpc_url: nil)
      url = rpc_url || RPC_URLS.fetch(network)
      @rpc = Eth::Client.create(url)
      @devices = Eth::Contract.from_abi(
        name: "DeviceRegistry",
        address: Contracts::DEVICE_REGISTRY_ADDRESSES.fetch(network),
        abi: Contracts::DEVICE_REGISTRY_ABI
      )
      @sessions = Eth::Contract.from_abi(
        name: "SessionRegistry",
        address: Contracts::SESSION_REGISTRY_ADDRESSES.fetch(network),
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

    # getSession reverte on-chain quando o hash é desconhecido — a única forma dessa
    # chamada falhar contra um RPC funcionando, então qualquer erro aqui é tratado
    # como "ainda não existe" em vez de propagado.
    def read_session(hash_bytes)
      session = @rpc.call(@sessions, "getSession", hash_bytes)
      session[4] ? session : nil # session[4] == exists
    rescue StandardError
      nil
    end
    private :read_session

    def verify_session(session_hash)
      # bytes32: converte hex string → 32 bytes binários
      hash_bytes = [session_hash.delete_prefix("0x")].pack("H*")

      session = read_session(hash_bytes)
      return SessionInfo.new(exists: false, revoked: false) if session.nil?

      revoked = @rpc.call(@sessions, "isSessionRevoked", hash_bytes)

      SessionInfo.new(
        exists:       true,
        revoked:      revoked,
        identity_id:  session[0],
        device_pub_key: session[1],
        created_at:   Time.at(session[2]).utc
      )
    end

    def register_session(nonce:, identity_id:, device_pub_key:, session_signature:, relayer_private_key:)
      # Deriva o mesmo session hash que o mobile calculou: keccak256(utf8(nonce))
      session_hash_bytes = Eth::Util.keccak256(nonce)

      # O app mobile TruthID (v14.9.5+) já cria a sessão on-chain sozinho via
      # UserOperation antes de chamar o callback do integrador — então isso é
      # idempotente: se a sessão já existe, pula a transação (evita um revert
      # garantido e gás desperdiçado do relayer).
      if read_session(session_hash_bytes)
        return RegisterSessionResult.new(
          tx_hash:             nil,
          session_hash:        "0x#{session_hash_bytes.unpack1("H*")}",
          already_registered:  true
        )
      end

      # Separa a assinatura compacta de 65 bytes em (r, s, v) que o contrato espera
      sig     = session_signature.delete_prefix("0x")
      r_bytes = [sig[0, 64]].pack("H*")    # bytes32
      s_bytes = [sig[64, 64]].pack("H*")   # bytes32
      v_int   = sig[128, 2].to_i(16)       # uint8

      key = Eth::Key.new(priv: relayer_private_key.delete_prefix("0x"))
      tx_hash = @rpc.transact(@sessions, "createSession",
        session_hash_bytes, identity_id, device_pub_key, r_bytes, s_bytes, v_int,
        sender_key: key)

      RegisterSessionResult.new(
        tx_hash:            tx_hash.start_with?("0x") ? tx_hash : "0x#{tx_hash}",
        session_hash:       "0x#{session_hash_bytes.unpack1("H*")}",
        already_registered: false
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
