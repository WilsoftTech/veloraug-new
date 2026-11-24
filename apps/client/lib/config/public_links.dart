import '../auth/oauth_config.dart';

// Public addresses set at build time, as in dart_defines.prod.json. Each is
// optional: without one, Settings shows that row as not available yet
// rather than linking somewhere unapproved.

/// The address to share VeloraUG by, such as https://app.veloraug.com.
const String publicAppUrlSetting = String.fromEnvironment('PUBLIC_APP_URL');

/// VeloraUG's Google Play listing, once it is published.
const String playStoreUrlSetting = String.fromEnvironment('PLAY_STORE_URL');

/// VeloraUG's approved privacy policy.
const String privacyPolicyUrlSetting = String.fromEnvironment(
  'PRIVACY_POLICY_URL',
);

/// [value] as an https address, or null if it is empty or anything else.
Uri? httpsLink(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  if (uri.userInfo.isNotEmpty) return null;
  return uri;
}

/// A Google Play listing: https://play.google.com/store/apps/details?id=...
Uri? playListing(String value) {
  final uri = httpsLink(value);
  if (uri == null ||
      uri.host != 'play.google.com' ||
      uri.path != '/store/apps/details' ||
      (uri.queryParameters['id'] ?? '').isEmpty) {
    return null;
  }
  return uri;
}

/// The links this build has, checked.
class PublicLinks {
  const PublicLinks({this.app, this.playStore, this.privacyPolicy, this.reset});

  /// From this build's settings.
  factory PublicLinks.fromSettings() {
    final pages = httpsLink(authPagesUrlSetting);
    return PublicLinks(
      app: httpsLink(publicAppUrlSetting),
      playStore: playListing(playStoreUrlSetting),
      privacyPolicy: httpsLink(privacyPolicyUrlSetting),
      reset: pages == null
          ? null
          : Uri(
              scheme: pages.scheme,
              host: pages.host,
              port: pages.hasPort ? pages.port : null,
              path: '/reset',
            ),
    );
  }

  final Uri? app;
  final Uri? playStore;
  final Uri? privacyPolicy;

  /// The sign-in pages' password reset, which emails a code and says the
  /// same whether or not the address has an account.
  final Uri? reset;
}
