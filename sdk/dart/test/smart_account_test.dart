import 'package:test/test.dart';
import 'package:truthid_sdk/src/smart_account.dart';
import 'package:truthid_sdk/src/types.dart';

void main() {
  // Fixed cross-language parity vector — the exact same (ledgerAddress,
  // network, index) is reused verbatim in
  // sdk/typescript/src/__tests__/smartAccount.test.ts,
  // sdk/python/tests/test_smart_account.py and
  // sdk/ruby/spec/smart_account_spec.rb. All four MUST compute the same
  // address; a mismatch means one of the ports has an encoding bug
  // (abi.encodePacked vs abi.encode is an easy one to get wrong — it already
  // caused a real bug once, see desktop's own test file).
  const parityLedger = '0x00000000000000000000000000000000000000ab';
  const parityNetwork = Network.baseSepolia;
  final parityIndex = BigInt.zero;

  const ledger1 = '0x111111111111111111111111111111111111111a';
  const ledger2 = '0x222222222222222222222222222222222222222b';

  test('returns a valid, checksummed, non-zero address', () {
    final addr = computeSmartAccountAddress(ledger1, Network.baseSepolia);
    expect(addr, matches(RegExp(r'^0x[0-9a-fA-F]{40}$')));
    expect(addr, isNot('0x0000000000000000000000000000000000000000'));
  });

  test('is deterministic — same inputs always produce the same address', () {
    expect(
      computeSmartAccountAddress(ledger1, Network.baseSepolia),
      computeSmartAccountAddress(ledger1, Network.baseSepolia),
    );
  });

  test('different owners produce different addresses', () {
    expect(
      computeSmartAccountAddress(ledger1, Network.baseSepolia),
      isNot(computeSmartAccountAddress(ledger2, Network.baseSepolia)),
    );
  });

  test('different networks produce different addresses', () {
    expect(
      computeSmartAccountAddress(ledger1, Network.baseSepolia),
      isNot(computeSmartAccountAddress(ledger1, Network.baseMainnet)),
    );
  });

  test('different index for the same owner produces a different address', () {
    final addr0 = computeSmartAccountAddress(ledger1, Network.baseSepolia, index: BigInt.zero);
    final addr1 = computeSmartAccountAddress(ledger1, Network.baseSepolia, index: BigInt.one);
    expect(addr0, isNot(addr1));
  });

  test('is reproducible across repeated calls — no hidden side effects', () {
    final results = List.generate(
      5,
      (_) => computeSmartAccountAddress(ledger1, Network.baseSepolia),
    );
    expect(results.toSet(), hasLength(1));
  });

  test('matches the fixed cross-language parity vector', () {
    final addr = computeSmartAccountAddress(parityLedger, parityNetwork, index: parityIndex);
    expect(addr, '0x83E364261871F2eC815dD7a63bD7455B69e2d9B9');
  });
}
