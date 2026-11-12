/// Address of the API, set at build time with --dart-define=API_BASE_URL=...
///
/// This is public configuration. Anyone can read it from a built app, so never
/// put a secret in it.
const String apiBaseUrlSetting = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

/// Address of the media gateway, the Cloudflare Worker that serves video,
/// set with --dart-define=MEDIA_BASE_URL=... The app plays video only from
/// here. Public configuration, like the API's address.
const String mediaBaseUrlSetting = String.fromEnvironment(
  'MEDIA_BASE_URL',
  defaultValue: 'http://127.0.0.1:8787',
);

const Set<String> _loopbackHosts = {'127.0.0.1', 'localhost'};

/// Checks a configured API address, throwing a [FormatException] if it is not
/// of the form scheme://host[:port]. Plain HTTP is only accepted for this
/// computer's or this phone's own loopback address.
Uri parseApiBaseUrl(String value) => _parseServiceUrl('API_BASE_URL', value);

/// The same rules, for the media gateway's address.
Uri parseMediaBaseUrl(String value) =>
    _parseServiceUrl('MEDIA_BASE_URL', value);

Uri _parseServiceUrl(String name, String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('$name is not a valid address: "$value"');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw FormatException('$name must use http or https: "$value"');
  }
  if (uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw FormatException(
      '$name must contain only a scheme, host and port: "$value"',
    );
  }
  if (uri.scheme == 'http' && !_loopbackHosts.contains(uri.host)) {
    throw FormatException(
      '$name must use https unless the host is 127.0.0.1 or localhost: '
      '"$value"',
    );
  }
  return uri;
}
