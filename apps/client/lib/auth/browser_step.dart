import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';

/// Allows time to read an email and enter its code during sign-up. The sign-in
/// request itself expires after about 10 minutes.
const int _browserTimeoutSeconds = 600;

/// Opens the sign-in pages in a popup on the web, or in Chrome's Auth Tab on
/// Android, and returns the address they finished on.
Future<String> openBrowserStep(Uri url, Uri redirectUri) {
  return FlutterWebAuth2.authenticate(
    url: url.toString(),
    callbackUrlScheme: redirectUri.scheme,
    options: FlutterWebAuth2Options(
      timeout: _browserTimeoutSeconds,
      windowName: '_blank',
      httpsHost: redirectUri.host,
      httpsPath: redirectUri.path,
    ),
  );
}
