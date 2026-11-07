import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_store.dart';

TokenStore createTokenStore() => _SecureTokenStore();

/// Encrypted with a key held in the Android Keystore. The app's manifest turns
/// off backup, so the entry isn't copied to another device.
class _SecureTokenStore implements TokenStore {
  static const String _key = 'veloraug.session';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  @override
  Future<StoredSession?> read() async {
    final text = await _storage.read(key: _key);
    return text == null ? null : StoredSession.decode(text);
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: _key, value: session.encode());

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
