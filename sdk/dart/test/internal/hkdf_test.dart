import 'dart:convert';

import 'package:test/test.dart';
import 'package:truthid_sdk/src/internal/hkdf.dart';

void main() {
  test('is deterministic for the same inputs', () {
    final a = hkdfSha256(
      ikm: utf8.encode('secret'),
      salt: utf8.encode('salt'),
      info: utf8.encode('info'),
      length: 32,
    );
    final b = hkdfSha256(
      ikm: utf8.encode('secret'),
      salt: utf8.encode('salt'),
      info: utf8.encode('info'),
      length: 32,
    );
    expect(a, b);
  });

  test('different salt/info produce different keys (domain separation)', () {
    final a = hkdfSha256(
      ikm: utf8.encode('secret'),
      salt: utf8.encode('salt-a'),
      info: utf8.encode('info'),
      length: 32,
    );
    final b = hkdfSha256(
      ikm: utf8.encode('secret'),
      salt: utf8.encode('salt-b'),
      info: utf8.encode('info'),
      length: 32,
    );
    expect(a, isNot(b));
  });

  test('respects the requested length', () {
    final key = hkdfSha256(
      ikm: utf8.encode('secret'),
      salt: utf8.encode('salt'),
      info: utf8.encode('info'),
      length: 16,
    );
    expect(key.length, 16);
  });
}
