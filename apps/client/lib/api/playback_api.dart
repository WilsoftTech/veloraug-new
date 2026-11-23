import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../auth/oauth_client.dart';
import '../l10n/app_localizations.dart';
import 'device_store.dart';

/// The header that carries this device's credential, Milestone 10.
const String deviceHeader = 'X-Velora-Device';

/// Permission to watch one item, a movie's video or one episode: the master playlist's address on the
/// media gateway, with the grant in its path. It works until [expiresAt].
///
/// With passes required, it is bound to a playback session, which the
/// player keeps alive every [heartbeat]. Removing the device, stopping the
/// session elsewhere, or the pass ending stops the video within a minute.
class PlaybackGrant {
  const PlaybackGrant({
    required this.playlistUrl,
    required this.expiresAt,
    this.sessionId,
    this.heartbeat,
  });

  final Uri playlistUrl;
  final DateTime expiresAt;
  final String? sessionId;
  final Duration? heartbeat;

  /// One quality's own playlist, beside the master playlist, under the same
  /// grant.
  Uri qualityUrl(VideoQuality quality) => playlistUrl.resolve(quality.path);
}

/// Permission to download one item, Android only: a grant with no playback
/// session, so the download takes no stream, and until when the download
/// may be played offline. The app checks in again before then.
class DownloadGrant {
  const DownloadGrant({required this.grant, required this.offlineUntil});

  final PlaybackGrant grant;
  final DateTime offlineUntil;
}

/// Something playing on one of the viewer's devices.
class LiveSession {
  const LiveSession({
    required this.id,
    required this.deviceLabel,
    required this.startedAt,
    this.currentDevice = false,
  });

  final String id;
  final String deviceLabel;
  final DateTime startedAt;
  final bool currentDevice;
}

/// One quality of a video, from its master playlist: "720p" and so on.
class VideoQuality {
  const VideoQuality({
    required this.label,
    required this.height,
    required this.path,
  });

  /// Shown in the quality menu, such as "720p".
  final String label;

  /// The picture's height, for sorting.
  final int height;

  /// Its playlist, beside the master playlist, such as "720p/index.m3u8".
  final String path;

  @override
  bool operator ==(Object other) => other is VideoQuality && other.path == path;

  @override
  int get hashCode => path.hashCode;
}

/// A quality's playlist: one folder down, nothing else. Anything else in a
/// master playlist is ignored, so it can't point the player elsewhere.
final RegExp _qualityPath = RegExp(r'^[A-Za-z0-9_-]{1,32}/index\.m3u8$');

/// The qualities a master playlist offers, highest first. Each is named by
/// its folder when that is like "720p", as the media worker names them.
List<VideoQuality> parseMasterPlaylist(String text) {
  final found = <String, VideoQuality>{};
  int? height;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final size = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
      height = size == null ? null : int.parse(size[2]!);
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    if (_qualityPath.hasMatch(line)) {
      final folder = line.split('/').first;
      final named = RegExp(r'^(\d{3,4})p$').firstMatch(folder);
      final lines = named == null ? height : int.parse(named[1]!);
      if (lines != null) {
        found[line] = VideoQuality(
          label: named == null ? '${lines}p' : folder,
          height: lines,
          path: line,
        );
      }
    }
    height = null;
  }
  return found.values.toList()..sort((a, b) => b.height.compareTo(a.height));
}

enum PlaybackFailure {
  /// The app has no session, so it sent nothing.
  signedOut,

  /// The API refused the token: 401.
  refused,

  /// 402: passes are required, and this viewer has none running.
  needsPass,

  /// 403: an admin preview, asked for by someone who isn't an admin.
  notAdmin,

  /// 404: the item doesn't exist, or isn't published and approved.
  notFound,

  /// 409: the item has nothing ready to watch.
  notReady,

  /// 409 `device_limit`: every device the plan allows is registered, or
  /// more than it allows after a change to a smaller plan.
  deviceLimit,

  /// 409 `stream_limit`: every stream the plan allows is in use elsewhere.
  streamLimit,

  /// 429 `device_switch_limit`: too many devices added in 30 days.
  deviceSwitchLimit,

  /// 429: too many requests at once.
  tooMany,

  /// 503: the API, its database, or playback isn't available.
  busy,

  /// No answer: no network, the API stopped, a timeout, or CORS.
  unreachable,

  /// Any other answer, including an address on another server.
  unexpected,
}

class PlaybackException implements Exception {
  const PlaybackException(this.failure, {this.limit, this.sessions = const []});

  final PlaybackFailure failure;

  /// For a device or stream limit: how many the plan allows.
  final int? limit;

  /// For a stream limit: what is playing on the other devices.
  final List<LiveSession> sessions;

  @override
  String toString() => 'PlaybackException(${failure.name})';
}

/// What the API said when the player said it's still watching.
enum HeartbeatResult {
  /// Carry on.
  live,

  /// 402: the pass it was playing under is over.
  passEnded,

  /// 410: stopped from another device, replaced, or idle too long.
  ended,

  /// 403: this device was removed.
  deviceRemoved,

  /// No answer, or an answer that says nothing: try again next time. The
  /// media gateway decides in the end.
  unknown,
}

/// A device or account answer: its status and its decoded JSON.
class ApiAnswer {
  const ApiAnswer(this.status, this.json);

  final int status;
  final Object? json;

  /// The `code` in a structured `detail`, such as `device_limit`.
  String? get code => switch (json) {
    {'detail': {'code': final String code}} => code,
    _ => null,
  };

  int? get limit => switch (json) {
    {'detail': {'limit': final int limit}} => limit,
    _ => null,
  };
}

/// Asks the API for permission to watch an item.
///
/// The token is sent only in the Authorization header, and never logged or
/// kept. The grant is never logged either: anyone holding it can watch. The
/// device credential is sent only in [deviceHeader], and kept only in
/// [deviceStore].
class PlaybackApi {
  PlaybackApi({
    required this.baseUrl,
    required this.mediaBaseUrl,
    required this.httpClient,
    required this.accessToken,
    DeviceStore? deviceStore,
    this.deviceLabel = defaultDeviceLabel,
    this.timeout = const Duration(seconds: 15),
  }) : deviceStore = deviceStore ?? MemoryDeviceStore();

  final Uri baseUrl;

  /// The only server the app will play video from.
  final Uri mediaBaseUrl;
  final http.Client httpClient;
  final Future<String?> Function() accessToken;

  /// This installation's device credential.
  final DeviceStore deviceStore;

  /// The name a new device registers with. The viewer can rename it.
  final String Function() deviceLabel;

  /// Long enough for a database that has scaled to zero to wake.
  final Duration timeout;

  /// The qualities [grant]'s video comes in, read from its master playlist
  /// on the media gateway. Empty when they can't be read: the player then
  /// offers only the automatic choice.
  Future<List<VideoQuality>> qualities(PlaybackGrant grant) async {
    if (!_onGateway(grant.playlistUrl)) return const [];
    try {
      final response = await httpClient.get(grant.playlistUrl).timeout(timeout);
      if (response.statusCode != 200) return const [];
      return parseMasterPlaylist(utf8.decode(response.bodyBytes));
    } on Exception {
      return const [];
    }
  }

  /// A viewer's grant for a published item. With [preview], an admin's
  /// grant for any item with a ready video, published or not.
  ///
  /// When the API asks for a registered device, this one registers itself
  /// once, and asks again.
  Future<PlaybackGrant> grant(String itemId, {bool preview = false}) async {
    final id = Uri.encodeComponent(itemId);
    final answer = await _askRegistering(
      preview
          ? '/api/v1/admin/items/$id/preview'
          : '/api/v1/items/$id/playback',
      register: !preview,
    );
    return _grantIn(answer);
  }

  /// A grant to download an item's video, on Android, and until when the
  /// download may play offline. Refused as [grant] is, except that a
  /// download takes no stream, so never [PlaybackFailure.streamLimit].
  Future<DownloadGrant> downloadGrant(String itemId) async {
    final answer = await _askRegistering(
      '/api/v1/items/${Uri.encodeComponent(itemId)}/download',
      register: true,
    );
    final grant = _grantIn(answer);
    final until = switch (answer.json) {
      {'offline_until': final String text} => DateTime.tryParse(text),
      _ => null,
    };
    if (until == null) {
      throw const PlaybackException(PlaybackFailure.unexpected);
    }
    return DownloadGrant(grant: grant, offlineUntil: until.toUtc());
  }

  /// Asks for a grant. When the API asks for a registered device, this one
  /// registers itself once, and asks again.
  Future<ApiAnswer> _askRegistering(
    String path, {
    required bool register,
  }) async {
    var answer = await _askForGrant(path);
    if (register && answer.status == 403 && answer.code == 'device_required') {
      await registerDevice();
      answer = await _askForGrant(path);
    }
    return answer;
  }

  /// The grant in an answer, or the refusal it means.
  PlaybackGrant _grantIn(ApiAnswer answer) {
    final failure = playbackFailureFor(answer);
    if (failure != null) {
      throw PlaybackException(
        failure,
        limit: answer.limit,
        sessions: _sessionsIn(answer.json),
      );
    }

    final json = answer.json;
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
    final session = json['session_id'];
    final every = json['heartbeat_seconds'];
    return PlaybackGrant(
      playlistUrl: playlist,
      expiresAt: expiresAt,
      sessionId: session is String ? session : null,
      heartbeat: every is int && every > 0 ? Duration(seconds: every) : null,
    );
  }

  Future<ApiAnswer> _askForGrant(String path) async {
    try {
      return await send('POST', path);
    } on _SignedOut {
      throw const PlaybackException(PlaybackFailure.signedOut);
    } on _NoAnswer {
      throw const PlaybackException(PlaybackFailure.unreachable);
    }
  }

  /// Registers this installation as one of the viewer's devices, keeping
  /// the credential the API makes. Already registered, it changes nothing.
  Future<void> registerDevice() async {
    final ApiAnswer answer;
    try {
      answer = await send(
        'POST',
        '/api/v1/me/devices',
        body: {'label': deviceLabel(), 'platform': devicePlatform()},
      );
    } on _SignedOut {
      throw const PlaybackException(PlaybackFailure.signedOut);
    } on _NoAnswer {
      throw const PlaybackException(PlaybackFailure.unreachable);
    }
    switch (answer.status) {
      case 200:
        return;
      case 201:
        final credential = switch (answer.json) {
          {'credential': final String credential} => credential,
          _ => null,
        };
        if (credential == null ||
            !deviceCredentialPattern.hasMatch(credential)) {
          throw const PlaybackException(PlaybackFailure.unexpected);
        }
        await deviceStore.write(credential);
      case 401:
        throw const PlaybackException(PlaybackFailure.refused);
      case 409:
        throw PlaybackException(
          PlaybackFailure.deviceLimit,
          limit: answer.limit,
        );
      case 429:
        throw PlaybackException(
          answer.code == 'device_switch_limit'
              ? PlaybackFailure.deviceSwitchLimit
              : PlaybackFailure.tooMany,
        );
      case 503:
        throw const PlaybackException(PlaybackFailure.busy);
      default:
        throw const PlaybackException(PlaybackFailure.unexpected);
    }
  }

  /// Says the player is still watching under [sessionId].
  Future<HeartbeatResult> heartbeat(String sessionId) async {
    try {
      final answer = await send(
        'POST',
        '/api/v1/me/playback-sessions/${Uri.encodeComponent(sessionId)}/heartbeat',
      );
      return switch (answer.status) {
        200 => HeartbeatResult.live,
        402 => HeartbeatResult.passEnded,
        403 => HeartbeatResult.deviceRemoved,
        410 => HeartbeatResult.ended,
        _ => HeartbeatResult.unknown,
      };
    } on Exception {
      return HeartbeatResult.unknown;
    }
  }

  /// One request to the API, signed in, with this device's credential if
  /// it has one. Throws only when nothing could be sent or nothing came
  /// back; every status is the caller's to judge.
  Future<ApiAnswer> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    bool signIn = true,
  }) async {
    final headers = <String, String>{};
    if (signIn) {
      final String? token;
      try {
        token = await accessToken();
      } on OAuthException {
        throw const _NoAnswer();
      }
      if (token == null) throw const _SignedOut();
      headers['Authorization'] = 'Bearer $token';
      String? credential;
      try {
        credential = await deviceStore.read().timeout(
          const Duration(seconds: 2),
        );
      } on Object {
        // Unreadable storage counts as not registered: the API says so,
        // and the device registers again.
        credential = null;
      }
      if (credential != null && deviceCredentialPattern.hasMatch(credential)) {
        headers[deviceHeader] = credential;
      }
    }
    final request = http.Request(method, baseUrl.replace(path: path))
      ..headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await httpClient.send(request).timeout(timeout),
      ).timeout(timeout);
    } on Exception {
      throw const _NoAnswer();
    }
    Object? json;
    try {
      json = response.bodyBytes.isEmpty
          ? null
          : jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    return ApiAnswer(response.statusCode, json);
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

/// The refusal an answer to a grant request means, or null for 200.
PlaybackFailure? playbackFailureFor(ApiAnswer answer) =>
    switch (answer.status) {
      200 => null,
      401 => PlaybackFailure.refused,
      402 => PlaybackFailure.needsPass,
      403 => PlaybackFailure.notAdmin,
      404 => PlaybackFailure.notFound,
      409 => switch (answer.code) {
        'device_limit' => PlaybackFailure.deviceLimit,
        'stream_limit' => PlaybackFailure.streamLimit,
        _ => PlaybackFailure.notReady,
      },
      429 =>
        answer.code == 'device_switch_limit'
            ? PlaybackFailure.deviceSwitchLimit
            : PlaybackFailure.tooMany,
      503 => PlaybackFailure.busy,
      _ => PlaybackFailure.unexpected,
    };

/// Nothing was sent: no session.
class _SignedOut implements Exception {
  const _SignedOut();
}

/// Nothing came back.
class _NoAnswer implements Exception {
  const _NoAnswer();
}

/// Whether [error] means signed out, or no answer, from [PlaybackApi.send].
bool isSignedOut(Object error) => error is _SignedOut;
bool isNoAnswer(Object error) => error is _NoAnswer;

List<LiveSession> _sessionsIn(Object? json) => [
  if (json case {'detail': {'sessions': final List<Object?> rows}})
    for (final row in rows)
      if (row case {
        'id': final String id,
        'device_label': final String label,
        'started_at': final String started,
      })
        LiveSession(
          id: id,
          deviceLabel: label,
          startedAt: DateTime.tryParse(started)?.toUtc() ?? DateTime.now(),
        ),
];

/// The platform a device registers as.
String devicePlatform() {
  if (kIsWeb) return 'web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => 'other',
  };
}

/// A plain first name for a device: "Web browser" or "Android phone". No
/// hardware identifier is read.
String defaultDeviceLabel() => switch (devicePlatform()) {
  'web' => 'Web browser',
  'android' => 'Android phone',
  'ios' => 'iPhone',
  _ => 'This device',
};

/// Words for each failure. They never repeat a token or the server's text.
String playbackFailureMessage(AppLocalizations l, PlaybackFailure failure) =>
    switch (failure) {
      PlaybackFailure.signedOut => l.signInToWatch,
      PlaybackFailure.refused => l.signInNotAccepted,
      PlaybackFailure.needsPass => l.passNeededMessage,
      PlaybackFailure.notAdmin => l.adminOnly,
      PlaybackFailure.notFound => l.notAvailable,
      PlaybackFailure.notReady => l.notReadyToWatch,
      PlaybackFailure.deviceLimit => l.deviceLimitMessage,
      PlaybackFailure.streamLimit => l.streamLimitMessage,
      PlaybackFailure.deviceSwitchLimit => l.deviceSwitchLimitMessage,
      PlaybackFailure.tooMany => l.tooManyAttempts,
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
