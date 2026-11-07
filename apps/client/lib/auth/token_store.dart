import 'dart:convert';

import 'platform_token_store.dart'
    if (dart.library.js_interop) 'platform_token_store_web.dart'
    as platform;

/// What the app keeps between launches. Don't log or display the tokens.
class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.email,
  });

  final String accessToken;
  final String? refreshToken;

  /// When the access token stops working, by this device's clock.
  final DateTime expiresAt;

  /// For display only.
  final String? email;

  String encode() => jsonEncode({
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.toUtc().toIso8601String(),
    'email': email,
  });

  /// Returns null for anything unreadable, so a damaged entry means signed out.
  static StoredSession? decode(String text) {
    try {
      final value = jsonDecode(text);
      if (value is! Map<String, dynamic>) return null;
      final accessToken = value['access_token'];
      final refreshToken = value['refresh_token'];
      final expiresAt = DateTime.tryParse('${value['expires_at']}');
      final email = value['email'];
      if (accessToken is! String || accessToken.isEmpty || expiresAt == null) {
        return null;
      }
      return StoredSession(
        accessToken: accessToken,
        refreshToken: refreshToken is String ? refreshToken : null,
        expiresAt: expiresAt,
        email: email is String ? email : null,
      );
    } on FormatException {
      return null;
    }
  }
}

/// Keeps the session on this device.
abstract interface class TokenStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

/// Android Keystore-backed storage on Android, and the tab's `sessionStorage`
/// on the web, which survives a reload but not a closed tab.
TokenStore createPlatformTokenStore() => platform.createTokenStore();

/// Keeps nothing between launches. For tests.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this.session]);

  StoredSession? session;

  @override
  Future<StoredSession?> read() async => session;

  @override
  Future<void> write(StoredSession session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}
