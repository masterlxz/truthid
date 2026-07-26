require "spec_helper"
require "json"

RSpec.describe TruthID::Client do
  let(:client) { described_class.new(network: "base-sepolia") }
  let(:signer_key) { Eth::Key.new }
  let(:device_address) { signer_key.address.to_s }

  def make_challenge(overrides = {})
    fields = {
      type: "challenge",
      nonce: "nonce-1",
      issued_at: (Time.now.to_f * 1000).to_i,
      origin: "https://example.com",
    }.merge(overrides)
    TruthID::AuthChallenge.new(**fields)
  end

  def sign_challenge(challenge, key = signer_key)
    key.personal_sign(JSON.generate(challenge.to_h))
  end

  describe "#create_challenge" do
    it "returns the expected shape" do
      challenge = client.create_challenge("https://example.com")
      expect(challenge.type).to eq("challenge")
      expect(challenge.origin).to eq("https://example.com")
      expect(challenge.nonce).to be_a(String)
      expect(challenge.issued_at).to be_a(Integer)
    end

    it "generates a different nonce every call" do
      a = client.create_challenge("https://example.com")
      b = client.create_challenge("https://example.com")
      expect(a.nonce).not_to eq(b.nonce)
    end
  end

  describe "#verify_auth_response" do
    it "rejects when the user declined" do
      challenge = make_challenge
      response = TruthID::AuthResponse.new(
        approved: false, nonce: challenge.nonce, signature: "0x", device_address: device_address
      )
      result = client.verify_auth_response(challenge, response)
      expect(result.valid).to be(false)
      expect(result.reason).to eq("User rejected the login request")
    end

    it "rejects an expired challenge" do
      challenge = make_challenge(issued_at: (Time.now.to_f * 1000).to_i - 60_000)
      response = TruthID::AuthResponse.new(
        approved: true, nonce: challenge.nonce, signature: "0x", device_address: device_address
      )
      result = client.verify_auth_response(challenge, response, ttl_ms: 30_000)
      expect(result.valid).to be(false)
      expect(result.reason).to eq("Challenge expired")
    end

    it "rejects a nonce mismatch" do
      challenge = make_challenge
      response = TruthID::AuthResponse.new(
        approved: true, nonce: "different-nonce", signature: "0x", device_address: device_address
      )
      result = client.verify_auth_response(challenge, response)
      expect(result.valid).to be(false)
      expect(result.reason).to eq("Nonce mismatch")
    end

    it "rejects a malformed signature" do
      challenge = make_challenge
      response = TruthID::AuthResponse.new(
        approved: true, nonce: challenge.nonce, signature: "0xnotasignature", device_address: device_address
      )
      result = client.verify_auth_response(challenge, response)
      expect(result.valid).to be(false)
      expect(result.reason).to eq("Invalid signature format")
    end

    it "rejects a signature recovered from a different key than the claimed device_address" do
      challenge = make_challenge
      other_key = Eth::Key.new
      response = TruthID::AuthResponse.new(
        approved: true,
        nonce: challenge.nonce,
        signature: sign_challenge(challenge, other_key),
        device_address: device_address, # claims to be signer_key, but signed with other_key
      )
      result = client.verify_auth_response(challenge, response)
      expect(result.valid).to be(false)
      expect(result.reason).to eq("Signature does not match device address")
    end

    it "rejects an inactive device" do
      challenge = make_challenge
      response = TruthID::AuthResponse.new(
        approved: true, nonce: challenge.nonce, signature: sign_challenge(challenge), device_address: device_address
      )
      rpc = client.instance_variable_get(:@rpc)
      allow(rpc).to receive(:call).with(anything, "isDeviceActive", device_address).and_return(false)

      result = client.verify_auth_response(challenge, response)
      expect(result.valid).to be(false)
      expect(result.reason).to eq("Device is not active or has been revoked")
    end

    it "succeeds and returns the identity_id for a valid, active device" do
      challenge = make_challenge
      response = TruthID::AuthResponse.new(
        approved: true, nonce: challenge.nonce, signature: sign_challenge(challenge), device_address: device_address
      )
      rpc = client.instance_variable_get(:@rpc)
      allow(rpc).to receive(:call).with(anything, "isDeviceActive", device_address).and_return(true)
      allow(rpc).to receive(:call).with(anything, "getDevice", device_address)
        .and_return([42, device_address, "", 0, false, true])

      result = client.verify_auth_response(challenge, response)
      expect(result.valid).to be(true)
      expect(result.identity_id).to eq(42)
      expect(result.device_address).to eq(device_address)
    end
  end

  it "no longer responds to register_session — the mobile registers sessions on-chain itself" do
    expect(client).not_to respond_to(:register_session)
  end
end
