from web3 import Web3

from truthid.smart_account import compute_smart_account_address

# Fixed cross-language parity vector — the exact same (ledger_address, network,
# index) is reused verbatim in sdk/typescript/src/__tests__/smartAccount.test.ts
# and sdk/ruby/spec/smart_account_spec.rb. All three MUST compute the same
# address; a mismatch means one of the three ports has an encoding bug
# (abi.encodePacked vs abi.encode is an easy one to get wrong — it already
# caused a real bug once, see desktop's own test file).
PARITY_LEDGER = "0x00000000000000000000000000000000000000ab"
PARITY_NETWORK = "base-sepolia"
PARITY_INDEX = 0

LEDGER_1 = "0x111111111111111111111111111111111111111a"
LEDGER_2 = "0x222222222222222222222222222222222222222b"


def test_returns_a_valid_checksummed_nonzero_address():
    addr = compute_smart_account_address(LEDGER_1, "base-sepolia")
    assert addr == Web3.to_checksum_address(addr)
    assert addr != "0x0000000000000000000000000000000000000000"


def test_deterministic_same_inputs_produce_same_address():
    assert compute_smart_account_address(
        LEDGER_1, "base-sepolia"
    ) == compute_smart_account_address(LEDGER_1, "base-sepolia")


def test_different_owners_produce_different_addresses():
    assert compute_smart_account_address(
        LEDGER_1, "base-sepolia"
    ) != compute_smart_account_address(LEDGER_2, "base-sepolia")


def test_different_networks_produce_different_addresses():
    assert compute_smart_account_address(
        LEDGER_1, "base-sepolia"
    ) != compute_smart_account_address(LEDGER_1, "base-mainnet")


def test_different_index_produces_different_address():
    addr0 = compute_smart_account_address(LEDGER_1, "base-sepolia", 0)
    addr1 = compute_smart_account_address(LEDGER_1, "base-sepolia", 1)
    assert addr0 != addr1


def test_reproducible_across_repeated_calls():
    results = [compute_smart_account_address(LEDGER_1, "base-sepolia") for _ in range(5)]
    assert all(r == results[0] for r in results)


def test_matches_fixed_cross_language_parity_vector():
    addr = compute_smart_account_address(PARITY_LEDGER, PARITY_NETWORK, PARITY_INDEX)
    assert addr == "0x83E364261871F2eC815dD7a63bD7455B69e2d9B9"
