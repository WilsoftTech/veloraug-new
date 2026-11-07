import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'auth_messages.dart';
import 'browser_failure.dart';
import 'oauth_client.dart';
import 'token_store.dart';

enum AuthStatus { restoring, signedOut, signingIn, signedIn, signingOut }

/// Owns the signed-in session for the whole app.
///
/// Tokens never leave this class except through [accessToken], and are never
/// logged. Debug builds log only the kind of failure.
class AuthController extends ChangeNotifier {
  AuthController({
    required this._client,
    required this._store,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  /// Access tokens are renewed this long before they expire, so a request
  /// doesn't start with a token that ends on the way.
  static const Duration refreshMargin = Duration(seconds: 60);

  /// Used when the token reply has no `expires_in`.
  static const Duration _fallbackLifetime = Duration(minutes: 5);

  final OAuthClient _client;
  final TokenStore _store;
  final DateTime Function() _now;

  StoredSession? _session;
  Future<String?>? _refreshing;

  AuthStatus _status = AuthStatus.restoring;
  AuthStatus get status => _status;

  String? _notice;
  bool _noticeIsError = false;

  /// The last outcome worth telling the person about, or null.
  String? get notice => _notice;
  bool get noticeIsError => _noticeIsError;

  /// For display only.
  String? get email => _session?.email;

  bool get isBusy =>
      _status == AuthStatus.restoring ||
      _status == AuthStatus.signingIn ||
      _status == AuthStatus.signingOut;

  /// Loads a saved session. If its access token has expired, it's renewed
  /// now, so a session ended elsewhere shows as signed out straight away.
  Future<void> restore() async {
    StoredSession? saved;
    try {
      saved = await _store.read();
    } on Object catch (error) {
      _log('restore', 'storage could not be read (${error.runtimeType})');
      await _clearStore();
    }
    _session = saved;
    if (saved != null && _expiresSoon(saved)) {
      try {
        await accessToken();
      } on OAuthException {
        // Offline at launch: stay signed in, and renew on the next request.
      }
    }
    _setStatus(_session == null ? AuthStatus.signedOut : AuthStatus.signedIn);
  }

  Future<void> signIn() async {
    if (isBusy) return;
    _notice = null;
    _setStatus(AuthStatus.signingIn);
    try {
      final tokens = await _client.signIn();
      final session = _sessionFrom(tokens, previous: null);
      _session = session;
      await _save(session);
      _setStatus(AuthStatus.signedIn);
    } on Exception catch (error) {
      _logFailure('sign-in', error);
      _setNotice(signInFailureMessage(error), isError: true);
      _setStatus(AuthStatus.signedOut);
    }
  }

  /// A usable access token, renewed first if it is about to expire, or null
  /// when signed out. Calls made during a renewal share it. A refused renewal
  /// signs the person out. A network failure throws [OAuthException] and
  /// keeps the session, so the caller can try again later.
  Future<String?> accessToken() async {
    final session = _session;
    if (session == null) return null;
    if (!_expiresSoon(session)) return session.accessToken;
    return _refreshing ??= _refresh(session).whenComplete(() {
      _refreshing = null;
    });
  }

  Future<String?> _refresh(StoredSession session) async {
    final refreshToken = session.refreshToken;
    if (refreshToken == null) {
      await _endLocally();
      return null;
    }
    try {
      final tokens = await _client.refresh(refreshToken);
      // Signed out, or signed in again, while this was running.
      if (!identical(_session, session)) return _session?.accessToken;
      final renewed = _sessionFrom(tokens, previous: session);
      _session = renewed;
      await _save(renewed);
      notifyListeners();
      return renewed.accessToken;
    } on OAuthException catch (error) {
      _logFailure('refresh', error);
      if (error.kind != OAuthFailure.grantRefused) rethrow;
      if (identical(_session, session)) await _endLocally();
      return null;
    }
  }

  /// Revokes the refresh token, clears the device, and ends the browser's
  /// sign-in session. The device is cleared first, so it is cleared even
  /// with no network or if the app closes part way.
  Future<void> signOut() async {
    if (isBusy) return;
    final refreshToken = _session?.refreshToken;
    _session = null;
    _notice = null;
    _setStatus(AuthStatus.signingOut);
    await _clearStore();

    var online = true;
    if (refreshToken != null) {
      try {
        await _client.revoke(refreshToken);
      } on OAuthException catch (error) {
        _logFailure('revoke', error);
        online = error.kind != OAuthFailure.network;
      }
    }

    String message;
    if (!online) {
      // The sign-out page wouldn't load, and would leave a tab to close.
      message = signedOutOfflineMessage;
    } else {
      try {
        await _client.endBrowserSession();
        message = signedOutMessage;
      } on Exception catch (error) {
        _logFailure('browser sign-out', error);
        message = signedOutBrowserKeptMessage;
      }
    }
    _setNotice(message, isError: message != signedOutMessage);
    _setStatus(AuthStatus.signedOut);
  }

  Future<void> _endLocally() async {
    _session = null;
    await _clearStore();
    _setNotice(sessionEndedMessage, isError: false);
    _setStatus(AuthStatus.signedOut);
  }

  bool _expiresSoon(StoredSession session) =>
      !_now().isBefore(session.expiresAt.subtract(refreshMargin));

  StoredSession _sessionFrom(
    OAuthTokens tokens, {
    required StoredSession? previous,
  }) {
    final lifetime = tokens.expiresIn;
    return StoredSession(
      accessToken: tokens.accessToken,
      // Neon rotates refresh tokens, but keep the old one if none came back.
      refreshToken: tokens.refreshToken ?? previous?.refreshToken,
      expiresAt: _now().add(
        lifetime == null ? _fallbackLifetime : Duration(seconds: lifetime),
      ),
      email: tokens.email ?? previous?.email,
    );
  }

  Future<void> _save(StoredSession session) async {
    try {
      await _store.write(session);
    } on Object catch (error) {
      // Still signed in for now, but the next launch will ask again.
      _log('save', 'storage could not be written (${error.runtimeType})');
    }
  }

  Future<void> _clearStore() async {
    try {
      await _store.clear();
    } on Object catch (error) {
      _log('clear', 'storage could not be cleared (${error.runtimeType})');
    }
  }

  void _setStatus(AuthStatus status) {
    _status = status;
    notifyListeners();
  }

  void _setNotice(String message, {required bool isError}) {
    _notice = message;
    _noticeIsError = isError;
  }

  void _logFailure(String step, Exception error) {
    final String detail;
    if (error is OAuthException) {
      detail = '${error.kind.name}: ${error.message}';
    } else if (error is PlatformException) {
      detail = describeBrowserFailure(error).join(', ');
    } else {
      // Only the type: a message could quote a callback address.
      detail = '${error.runtimeType}';
    }
    _log(step, detail);
  }

  // OAuthException messages and describeBrowserFailure never hold a code,
  // token or address, so this is safe to write to the device log.
  void _log(String step, String detail) {
    if (kDebugMode) debugPrint('auth $step: $detail');
  }
}

/// Makes the [AuthController] available below it. It is null in builds
/// without sign-in settings.
class AuthScope extends InheritedNotifier<AuthController> {
  const AuthScope({
    super.key,
    required AuthController? controller,
    required super.child,
  }) : super(notifier: controller);

  static AuthController? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AuthScope>()?.notifier;
}
