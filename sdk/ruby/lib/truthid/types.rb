require "json"

module TruthID
  # AuthChallenge precisa de to_h com camelCase — por isso classe manual, não Struct
  class AuthChallenge
    attr_reader :type, :nonce, :issued_at, :origin

    def initialize(type:, nonce:, issued_at:, origin:)
      @type      = type
      @nonce     = nonce
      @issued_at = issued_at
      @origin    = origin
    end

    # JSON.generate(challenge.to_h) → formato exato que o mobile assina
    def to_h
      { "type" => @type, "nonce" => @nonce, "issuedAt" => @issued_at, "origin" => @origin }
    end

    def to_json(*args)
      JSON.generate(to_h)
    end
  end

  # AuthResponse é o que chega do mobile (chaves camelCase do JSON mapeadas manualmente)
  class AuthResponse
    attr_reader :approved, :nonce, :signature, :device_address

    def initialize(approved:, nonce:, signature:, device_address:)
      @approved       = approved
      @nonce          = nonce
      @signature      = signature
      @device_address = device_address
    end

    def self.from_hash(h)
      new(
        approved:       h["approved"],
        nonce:          h["nonce"],
        signature:      h["signature"],
        device_address: h["deviceAddress"]
      )
    end
  end

  # Tipos de resultado: snake_case, sem necessidade de conversão JSON
  VerifyAuthResult = Struct.new(:valid, :identity_id, :device_address, :reason, keyword_init: true)
  SessionInfo      = Struct.new(:exists, :revoked, :identity_id, :device_pub_key, :created_at, keyword_init: true)
  DeviceStatus     = Struct.new(:exists, :active, :label, :identity_id, :added_at, keyword_init: true)
end
