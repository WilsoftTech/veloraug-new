import 'dart:js_interop';

import 'token_store.dart';

TokenStore createTokenStore() => _SessionStorageTokenStore();

@JS('sessionStorage')
external _Storage get _sessionStorage;

extension type _Storage(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

/// Per tab, so two tabs never share, and so race, one refresh token. Scripts on
/// the page can read it, which is why the web app loads no third-party scripts.
class _SessionStorageTokenStore implements TokenStore {
  static const String _key = 'veloraug.session';

  @override
  Future<StoredSession?> read() async {
    final text = _sessionStorage.getItem(_key);
    return text == null ? null : StoredSession.decode(text);
  }

  @override
  Future<void> write(StoredSession session) async =>
      _sessionStorage.setItem(_key, session.encode());

  @override
  Future<void> clear() async => _sessionStorage.removeItem(_key);
}
