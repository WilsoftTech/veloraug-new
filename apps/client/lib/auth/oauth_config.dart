import 'package:flutter/foundation.dart';

// Public configuration, set at build time. Anyone can read these from a built
// app, so never put a secret in them. Public OAuth clients have no secret.
const String neonAuthUrlSetting = String.fromEnvironment('NEON_AUTH_URL');
const String neonAuthWebClientIdSetting = String.fromEnvironment(
  'NEON_AUTH_WEB_CLIENT_ID',
);
const String neonAuthAndroidClientIdSetting = String.fromEnvironment(
  'NEON_AUTH_ANDROID_CLIENT_ID',
);
const String apiResourceSetting = String.fromEnvironment('API_RESOURCE');
const String authPagesUrlSetting = String.fromEnvironment('AUTH_PAGES_URL');

const String _androidCallbackPath = '/auth/callback/android';
const String _webCallbackPath = '/auth.html';

/// Settings for one OAuth client on one platform.
class OAuthConfig {
  const OAuthConfig({
    required this.issuer,
    required this.clientId,
    required this.resource,
    required this.redirectUri,
    required this.signOutPage,
  });

  /// The exact Neon Auth URL of the branch.
  final String issuer;
  final String clientId;

  /// The API identifier, which becomes the token's audience.
  final String resource;

  /// Must match the address registered on the client, character for character.
  final Uri redirectUri;

  final Uri signOutPage;

  /// The settings for this build, or null if they are not all set.
  ///
  /// [webOrigin] is the address the web app is running from.
  static OAuthConfig? fromSettings({
    String issuer = neonAuthUrlSetting,
    String webClientId = neonAuthWebClientIdSetting,
    String androidClientId = neonAuthAndroidClientIdSetting,
    String resource = apiResourceSetting,
    String authPagesUrl = authPagesUrlSetting,
    bool isWeb = kIsWeb,
    String? webOrigin,
  }) {
    final clientId = isWeb ? webClientId : androidClientId;
    if ([issuer, clientId, resource, authPagesUrl].any((v) => v.isEmpty)) {
      return null;
    }
    final pages = _parseHttps(authPagesUrl, 'AUTH_PAGES_URL');
    _parseHttps(issuer, 'NEON_AUTH_URL');
    _parseHttps(resource, 'API_RESOURCE');

    final redirectUri = isWeb
        ? Uri.parse('${webOrigin ?? Uri.base.origin}$_webCallbackPath')
        : pages.replace(path: _androidCallbackPath);
    return OAuthConfig(
      issuer: issuer,
      clientId: clientId,
      resource: resource,
      redirectUri: redirectUri,
      signOutPage: pages.replace(
        path: '/sign-out',
        queryParameters: {'return': redirectUri.toString()},
      ),
    );
  }
}

Uri _parseHttps(String value, String name) {
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException('$name must be an https address.');
  }
  return uri;
}
