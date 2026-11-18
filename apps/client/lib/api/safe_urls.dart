/// Addresses from the API are used only when they point where they should,
/// so a bad answer can't make the app load or open an address from
/// elsewhere.
library;

/// An image from TMDB's image server over HTTPS, or one an admin uploaded,
/// served by the media gateway under `/i/`. Anything else is ignored.
String? safeImageUrl(Object? value, {Uri? gateway}) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  if (uri.scheme == 'https' && uri.host == 'image.tmdb.org') return value;
  if (gateway != null &&
      uri.scheme == gateway.scheme &&
      uri.host == gateway.host &&
      uri.port == gateway.port &&
      uri.path.startsWith('/i/')) {
    return value;
  }
  return null;
}

final RegExp _youtubeId = RegExp(r'^[A-Za-z0-9_-]{6,20}$');

/// A YouTube watch page, as the API builds trailer links, and nothing else.
Uri? safeTrailerUrl(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host != 'www.youtube.com' ||
      uri.path != '/watch' ||
      uri.userInfo.isNotEmpty ||
      uri.hasFragment ||
      uri.queryParameters.length != 1 ||
      !_youtubeId.hasMatch(uri.queryParameters['v'] ?? '')) {
    return null;
  }
  return uri;
}
