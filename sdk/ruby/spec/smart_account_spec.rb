require "spec_helper"

RSpec.describe "TruthID.compute_smart_account_address" do
  # Fixed cross-language parity vector — the exact same (ledger_address,
  # network, index) is reused verbatim in
  # sdk/typescript/src/__tests__/smartAccount.test.ts and
  # sdk/python/tests/test_smart_account.py. All three MUST compute the same
  # address; a mismatch means one of the three ports has an encoding bug
  # (abi.encodePacked vs abi.encode is an easy one to get wrong — it already
  # caused a real bug once, see desktop's own test file).
  let(:parity_ledger) { "0x00000000000000000000000000000000000000ab" }
  let(:parity_network) { "base-sepolia" }
  let(:parity_index) { 0 }

  let(:ledger1) { "0x111111111111111111111111111111111111111a" }
  let(:ledger2) { "0x222222222222222222222222222222222222222b" }

  def compute(ledger, network: "base-sepolia", index: 0)
    TruthID.compute_smart_account_address(ledger, network: network, index: index)
  end

  it "returns a valid, checksummed, non-zero address" do
    addr = compute(ledger1)
    expect(addr).to match(/\A0x[0-9a-fA-F]{40}\z/)
    expect(addr).not_to eq("0x0000000000000000000000000000000000000000")
    expect(Eth::Address.new(addr).checksummed).to eq(addr)
  end

  it "is deterministic — same inputs always produce the same address" do
    expect(compute(ledger1)).to eq(compute(ledger1))
  end

  it "different owners produce different addresses" do
    expect(compute(ledger1)).not_to eq(compute(ledger2))
  end

  it "different networks produce different addresses" do
    expect(compute(ledger1, network: "base-sepolia")).not_to eq(
      compute(ledger1, network: "base-mainnet")
    )
  end

  it "different index for the same owner produces a different address" do
    expect(compute(ledger1, index: 0)).not_to eq(compute(ledger1, index: 1))
  end

  it "is reproducible across repeated calls — no hidden side effects" do
    results = Array.new(5) { compute(ledger1) }
    expect(results.uniq.length).to eq(1)
  end

  it "matches the fixed cross-language parity vector" do
    addr = compute(parity_ledger, network: parity_network, index: parity_index)
    expect(addr).to eq("0x83E364261871F2eC815dD7a63bD7455B69e2d9B9")
  end
end
