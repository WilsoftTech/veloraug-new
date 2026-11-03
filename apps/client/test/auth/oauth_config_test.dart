import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/auth/oauth_config.dart';

const _issuer = 'https://ep-x.neonauth.aws.neon.tech/neondb/auth';
const _resource = 'https://api-dev.veloraug.invalid';
const _pages = 'https://veloraug-auth-dev.pages.dev';

OAuthConfig? _config({
  bool isWeb = false,
  String issuer = _issuer,
  String pages = _pages,
}) => OAuthConfig.fromSettings(
  issuer: issuer,
  webClientId: 'web',
  androidClientId: 'android',
  resource: _resource,
  authPagesUrl: pages,
  isWeb: isWeb,
  webOrigin: 'http://localhost:8765',
);

void main() {
  test('Android uses its client and the registered HTTPS callback', () {
    final config = _config()!;
    expect(config.clientId, 'android');
    expect(config.redirectUri.toString(), '$_pages/auth/callback/android');
  });

  test('web uses its client and the callback page on its own origin', () {
    final config = _config(isWeb: true)!;
    expect(config.clientId, 'web');
    expect(config.redirectUri.toString(), 'http://localhost:8765/auth.html');
  });

  test('the sign-out page returns to that platform\'s callback', () {
    final config = _config()!;
    expect(config.signOutPage.path, '/sign-out');
    expect(
      config.signOutPage.queryParameters['return'],
      '$_pages/auth/callback/android',
    );
  });

  test('missing settings mean not configured, not a crash', () {
    expect(_config(issuer: ''), isNull);
  });

  test('plain HTTP is refused for Neon and the pages', () {
    expect(
      () => _config(issuer: 'http://ep-x.aws.neon.tech/neondb/auth'),
      throwsFormatException,
    );
    expect(
      () => _config(pages: 'http://veloraug-auth-dev.pages.dev'),
      throwsFormatException,
    );
  });
}
