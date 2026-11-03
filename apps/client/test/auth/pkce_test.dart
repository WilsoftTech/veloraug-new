import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/auth/pkce.dart';

void main() {
  test('matches the RFC 7636 S256 example', () {
    expect(
      pkceS256Challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
  });

  test('random values are long enough for PKCE, URL-safe and differ', () {
    final first = randomUrlSafe();
    expect(first.length, greaterThanOrEqualTo(43));
    expect(first, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
    expect(randomUrlSafe(), isNot(first));
  });
}
