import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../auth/oauth_client.dart';
import '../l10n/app_localizations.dart';

/// Permission to watch one item, a movie's video or one episode: the master playlist's address on the
/// media gateway, with the grant in its path. It works until [expiresAt].
class PlaybackGrant {
  const PlaybackGrant({required this.playlistUrl, required this.expiresAt});

  final Uri playlistUrl;
  final DateTime expiresAt;
}

enum PlaybackFailure {
  /// The app has no session, so it sent nothing.
  signedOut,

  /// The API refused the token: 401.
  refused,

  /// 403: an admin preview, asked for by someone who isn't an admin.
  notAdmin,

  /// 404: the item doesn't exist, or isn't published and approved.
  notFound,

  /// 409: the item has nothing ready to watch.
  notReady,

  /// 503: the API, its database, or playback isn't available.
  busy,

  /// No answer: no network, the API stopped, a timeout, or CORS.
  unreachable,

  /// Any other answer, including an address on another server.
  unexpected,
}

class PlaybackException implements Exception {
  const PlaybackException(this.failure);

  final PlaybackFailure failure;

  @override
  String toString() => 'PlaybackException(${failure.name})';
}

/// Asks the API for permission to watch an item.
///
/// The token is sent only in the Authorization header, and never logged or
/// kept. The grant is never logged either: anyone holding it can watch.
class PlaybackApi {
  PlaybackApi({
    required this.baseUrl,
    required this.mediaBaseUrl,
    required this.httpClient,
    required this.accessToken,
    this.timeout = const Duration(seconds: 15),
  });

  final Uri baseUrl;

  /// The only server the app will play video from.
  final Uri mediaBaseUrl;
  final http.Client httpClient;
  final Future<String?> Function() accessToken;

  /// Long enough for a database that has scaled to zero to wake.
  final Duration timeout;

  /// A viewer's grant for a published item. With [preview], an admin's
  /// grant for any item with a ready video, published or not.
  Future<PlaybackGrant> grant(String itemId, {bool preview = false}) async {
    final String? token;
    try {
      token = await accessToken();
    } on OAuthException {
      // Renewing the token needed the network.
      throw const PlaybackException(PlaybackFailure.unreachable);
    }
    if (token == null) {
      throw const PlaybackException(PlaybackFailure.signedOut);
    }

    final http.Response response;
    try {
      response = await httpClient
          .post(
            baseUrl.replace(
              path: preview
                  ? '/api/v1/admin/items/${Uri.encodeComponent(itemId)}/preview'
                  : '/api/v1/items/${Uri.encodeComponent(itemId)}/playback',
            ),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const PlaybackException(PlaybackFailure.unreachable);
    } on Exception {
      throw const PlaybackException(PlaybackFailure.unreachable);
    }

    final failure = switch (response.statusCode) {
      200 => null,
      401 => PlaybackFailure.refused,
      403 => PlaybackFailure.notAdmin,
      404 => PlaybackFailure.notFound,
      409 => PlaybackFailure.notReady,
      503 => PlaybackFailure.busy,
      _ => PlaybackFailure.unexpected,
    };
    if (failure != null) throw PlaybackException(failure);

    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PlaybackException(PlaybackFailure.unexpected);
    }
    if (json is! Map<String, Object?>) {
      throw const PlaybackException(PlaybackFailure.unexpected);
    }
    final url = json['playlist_url'];
    final expires = json['expires_at'];
    final playlist = url is String ? Uri.tryParse(url) : null;
    final expiresAt = expires is String ? DateTime.tryParse(expires) : null;
    if (playlist == null || expiresAt == null || !_onGateway(playlist)) {
      throw const PlaybackException(PlaybackFailure.unexpected);
    }
    return PlaybackGrant(playlistUrl: playlist, expiresAt: expiresAt);
  }

  /// A bad answer can't make the app play video from anywhere else.
  bool _onGateway(Uri url) =>
      url.scheme == mediaBaseUrl.scheme &&
      url.host == mediaBaseUrl.host &&
      url.port == mediaBaseUrl.port &&
      url.userInfo.isEmpty &&
      url.path.startsWith('/v1/') &&
      url.path.endsWith('/master.m3u8') &&
      !url.hasQuery &&
      !url.hasFragment;
}

/// Words for each failure. They never repeat a token or the server's text.
String playbackFailureMessage(AppLocalizations l, PlaybackFailure failure) =>
    switch (failure) {
      PlaybackFailure.signedOut => l.signInToWatch,
      PlaybackFailure.refused => l.signInNotAccepted,
      PlaybackFailure.notAdmin => l.adminOnly,
      PlaybackFailure.notFound => l.notAvailable,
      PlaybackFailure.notReady => l.notReadyToWatch,
      PlaybackFailure.busy => l.busy,
      PlaybackFailure.unreachable => l.unreachable,
      PlaybackFailure.unexpected => l.somethingWentWrong,
    };

/// Gives the screens below it playback. [api] is null when this build has
/// no usable API or media address, or no sign-in.
class PlaybackScope extends InheritedWidget {
  const PlaybackScope({super.key, required this.api, required super.child});

  final PlaybackApi? api;

  static PlaybackApi? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackScope>()?.api;

  @override
  bool updateShouldNotify(PlaybackScope oldWidget) => api != oldWidget.api;
}
