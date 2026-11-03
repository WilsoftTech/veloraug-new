/// Address of the API, set at build time with --dart-define=API_BASE_URL=...
///
/// This is public configuration. Anyone can read it from a built app, so never
/// put a secret in it.
const String apiBaseUrlSetting = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

const Set<String> _loopbackHosts = {'127.0.0.1', 'localhost'};

/// Checks a configured API address, throwing a [FormatException] if it is not
/// of the form scheme://host[:port]. Plain HTTP is only accepted for this
/// computer's or this phone's own loopback address.
Uri parseApiBaseUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    throw FormatException('API_BASE_URL is not a valid address: "$value"');
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    throw FormatException('API_BASE_URL must use http or https: "$value"');
  }
  if (uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw FormatException(
      'API_BASE_URL must contain only a scheme, host and port: "$value"',
    );
  }
  if (uri.scheme == 'http' && !_loopbackHosts.contains(uri.host)) {
    throw FormatException(
      'API_BASE_URL must use https unless the host is 127.0.0.1 or localhost: '
      '"$value"',
    );
  }
  return uri;
}
