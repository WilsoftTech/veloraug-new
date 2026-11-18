import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../auth/oauth_client.dart';
import '../l10n/app_localizations.dart';
import 'catalogue_api.dart' show EditionKind;
import 'safe_urls.dart';

/// An upload key for one item, as listed. The key itself is never listed.
class UploadKeyInfo {
  const UploadKeyInfo({
    required this.id,
    required this.label,
    required this.expiresAt,
    required this.used,
    required this.revoked,
  });

  final String id;
  final String label;
  final DateTime expiresAt;
  final bool used;
  final bool revoked;
}

/// A movie's one video, or one episode, with its newest upload's state.
class AdminItem {
  const AdminItem({
    required this.id,
    this.season,
    this.episode,
    this.episodeTitle,
    this.approved = false,
    this.video,
    this.videoReason,
    this.previewable = false,
    this.filename,
    this.creditHints,
    this.keys = const [],
  });

  final String id;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final bool approved;

  /// The newest original's state: `uploading`, `processing`, `ready`,
  /// `failed`… or null before any upload.
  final String? video;
  final String? videoReason;
  final bool previewable;
  final String? filename;
  final String? creditHints;
  final List<UploadKeyInfo> keys;
}

/// A TMDB title the admin can choose.
class TmdbMatch {
  const TmdbMatch({
    required this.tmdbId,
    required this.title,
    this.originalTitle,
    this.year,
    this.overview,
    this.posterUrl,
  });

  final int tmdbId;
  final String title;
  final String? originalTitle;
  final int? year;
  final String? overview;
  final String? posterUrl;
}

/// An edition as the admin screens see it, published or not.
class AdminEdition {
  const AdminEdition({
    required this.id,
    required this.kind,
    required this.displayTitle,
    required this.language,
    required this.status,
    this.submittedYear,
    this.test = false,
    this.tmdbLookup,
    this.sourceTmdbId,
    this.sourceTitle,
    this.sourceYear,
    this.sourceOverview,
    this.detailsFrom,
    this.posterPath,
    this.posterUrl,
    this.vjId,
    this.vjName,
    this.items = const [],
    this.missing = const [],
    this.matches = const [],
  });

  final String id;
  final EditionKind kind;
  final String displayTitle;
  final int? submittedYear;
  final String language;

  /// `draft`, `published` or `hidden`.
  final String status;
  final bool test;

  /// `clear`, `choose`, `none`, `failed`, `chosen`, `manual`, or null
  /// before TMDB has been asked.
  final String? tmdbLookup;
  final int? sourceTmdbId;
  final String? sourceTitle;
  final int? sourceYear;
  final String? sourceOverview;

  /// `tmdb` or `manual`, once details are chosen.
  final String? detailsFrom;
  final String? posterPath;
  final String? posterUrl;
  final String? vjId;
  final String? vjName;
  final List<AdminItem> items;

  /// What publishing still needs, in the API's words.
  final List<String> missing;
  final List<TmdbMatch> matches;

  bool get published => status == 'published';
}

class PosterOption {
  const PosterOption({required this.path, required this.url});

  final String path;
  final String url;
}

class PosterOptions {
  const PosterOptions({this.chosen, this.options = const []});

  final String? chosen;
  final List<PosterOption> options;
}

class CreditSuggestion {
  const CreditSuggestion({
    required this.name,
    required this.foundIn,
    this.vjId,
  });

  /// Null when the name matches no known VJ.
  final String? vjId;
  final String name;

  /// Where it was found: the file's name or one of its tags.
  final String foundIn;
}

class Credit {
  const Credit({this.vjId, this.vjName, this.suggestions = const []});

  final String? vjId;
  final String? vjName;
  final List<CreditSuggestion> suggestions;
}

class AdminVj {
  const AdminVj({
    required this.id,
    required this.name,
    required this.slug,
    this.matchNames = const [],
    this.photoUrl,
    this.bio,
    this.editions = 0,
  });

  final String id;
  final String name;
  final String slug;

  /// Other spellings found in file names, for suggesting credits.
  final List<String> matchNames;
  final String? photoUrl;
  final String? bio;
  final int editions;
}

/// A series edition, for adding a dropped episode to it.
class AdminSeries {
  const AdminSeries({
    required this.id,
    required this.title,
    required this.language,
    required this.status,
    this.vjId,
    this.vjName,
    this.episodes = const [],
  });

  final String id;
  final String title;
  final String language;
  final String status;
  final String? vjId;
  final String? vjName;

  /// (season, episode) of each episode it has.
  final List<(int?, int?)> episodes;

  bool hasEpisode(int season, int episode) =>
      episodes.any((e) => e.$1 == season && e.$2 == episode);
}

class AdminLanguage {
  const AdminLanguage({required this.code, required this.name});

  final String code;
  final String name;
}

class AdminEntry {
  const AdminEntry({
    required this.userId,
    required this.addedAt,
    this.email,
    this.addedByEmail,
  });

  final String userId;
  final String? email;
  final String? addedByEmail;
  final DateTime addedAt;
}

/// A new upload key. [uploadKey] is shown once and never kept.
class KeyMade {
  const KeyMade({
    required this.keyId,
    required this.uploadKey,
    required this.expiresAt,
    this.editionId,
    this.itemId,
  });

  final String keyId;
  final String uploadKey;
  final DateTime expiresAt;

  /// Set when the key came with a new draft.
  final String? editionId;
  final String? itemId;
}

/// Typed-in details, when TMDB has nothing.
class ManualDetails {
  const ManualDetails({
    required this.title,
    this.overview,
    this.year,
    this.genres = const [],
    this.runtimeMinutes,
  });

  final String title;
  final String? overview;
  final int? year;
  final List<String> genres;
  final int? runtimeMinutes;

  Map<String, Object?> toJson() => {
    'title': title,
    'overview': overview,
    'year': year,
    'genres': genres,
    'runtime_minutes': runtimeMinutes,
  };
}

/// What a TMDB search found: `clear`, `choose`, `none` or `failed`.
class LookupResult {
  const LookupResult({required this.outcome, required this.edition});

  final String outcome;
  final AdminEdition edition;
}

enum AdminFailure {
  /// The app has no session, so it sent nothing.
  signedOut,

  /// The API refused the token: 401.
  refused,

  /// 403: this account isn't an admin.
  notAdmin,

  /// 404: it no longer exists.
  notFound,

  /// 409: publishing refused, with what is missing, or another conflict.
  conflict,

  /// 400 or 422: the API refused what was sent, and says why.
  invalid,

  /// 413 or 415: the image is too big, or isn't the image it says.
  badImage,

  /// 503: the API, its database, TMDB or playback isn't available.
  busy,

  /// No answer: no network, the API stopped, a timeout, or CORS.
  unreachable,

  /// Any other answer.
  unexpected,
}

class AdminException implements Exception {
  const AdminException(this.failure, {this.detail, this.missing = const []});

  final AdminFailure failure;

  /// The API's own explanation, for a refused change. Only admins see it.
  final String? detail;

  /// For a refused publish: what is still needed.
  final List<String> missing;

  @override
  String toString() => 'AdminException(${failure.name})';
}

Never _bad() => throw const AdminException(AdminFailure.unexpected);

T _need<T>(Object? value) => value is T ? value : _bad();

T? _maybe<T>(Object? value) => value == null ? null : _need<T>(value);

DateTime _time(Object? value) =>
    DateTime.tryParse(_need<String>(value)) ?? _bad();

List<Map<String, Object?>> _rows(Object? value) => [
  for (final row in _need<List<Object?>>(value))
    _need<Map<String, Object?>>(row),
];

/// The admin routes, /api/v1/admin/…, with the signed-in admin's token.
///
/// The token is sent only in the Authorization header, and never logged or
/// kept. Upload keys in answers are returned to the screen once, never kept.
class AdminApi {
  AdminApi({
    required this.baseUrl,
    required this.mediaBaseUrl,
    required this.httpClient,
    required this.accessToken,
    this.timeout = const Duration(seconds: 30),
  });

  final Uri baseUrl;

  /// The only server images are uploaded to.
  final Uri mediaBaseUrl;
  final http.Client httpClient;
  final Future<String?> Function() accessToken;

  /// TMDB lookups happen while the API answers, so allow longer.
  final Duration timeout;

  /// True for an admin, false for anyone else signed in. Throws when it
  /// can't tell.
  Future<bool> isAdmin() async {
    try {
      await _send('GET', '/me');
      return true;
    } on AdminException catch (error) {
      if (error.failure == AdminFailure.notAdmin) return false;
      rethrow;
    }
  }

  Future<List<AdminEdition>> drafts() async {
    final json = _need<Map<String, Object?>>(await _send('GET', '/drafts'));
    return [for (final row in _rows(json['editions'])) _edition(row)];
  }

  /// Starts a draft, or with [seriesEditionId] adds an episode to a series.
  Future<KeyMade> createDraft({
    required EditionKind kind,
    String? title,
    int? year,
    String? language,
    String? seriesEditionId,
    int? season,
    int? episode,
    String? episodeTitle,
  }) async {
    final json = _need<Map<String, Object?>>(
      await _send('POST', '/drafts', {
        'kind': kind.name,
        'title': ?title,
        'year': ?year,
        'language': ?language,
        'series_edition_id': ?seriesEditionId,
        'season': ?season,
        'episode': ?episode,
        'episode_title': ?episodeTitle,
      }),
    );
    return _key(json);
  }

  Future<AdminEdition> edition(String id) async =>
      _edition(await _send('GET', '/editions/${_id(id)}'));

  Future<AdminEdition> rename(String id, String title) async => _edition(
    await _send('PATCH', '/editions/${_id(id)}', {'display_title': title}),
  );

  Future<LookupResult> searchTmdb(String id, {String? title, int? year}) async {
    final json = _need<Map<String, Object?>>(
      await _send('POST', '/editions/${_id(id)}/tmdb/search', {
        'title': ?title,
        'year': ?year,
      }),
    );
    return LookupResult(
      outcome: _need<String>(json['outcome']),
      edition: _edition(json['edition']),
    );
  }

  Future<AdminEdition> chooseTmdb(String id, int tmdbId) async => _edition(
    await _send('PUT', '/editions/${_id(id)}/source', {'tmdb_id': tmdbId}),
  );

  Future<AdminEdition> typeDetails(String id, ManualDetails details) async =>
      _edition(
        await _send('PUT', '/editions/${_id(id)}/source', {
          'manual': details.toJson(),
        }),
      );

  Future<PosterOptions> posters(String id) async {
    final json = _need<Map<String, Object?>>(
      await _send('GET', '/editions/${_id(id)}/posters'),
    );
    return PosterOptions(
      chosen: _maybe<String>(json['chosen']),
      options: [
        for (final row in _rows(json['options']))
          if (safeImageUrl(row['url'], gateway: mediaBaseUrl) case final url?)
            PosterOption(path: _need<String>(row['path']), url: url),
      ],
    );
  }

  Future<AdminEdition> choosePoster(String id, String path) async => _edition(
    await _send('PUT', '/editions/${_id(id)}/poster', {'path': path}),
  );

  Future<Credit> credit(String id) async {
    final json = _need<Map<String, Object?>>(
      await _send('GET', '/editions/${_id(id)}/credit'),
    );
    return Credit(
      vjId: _maybe<String>(json['vj_id']),
      vjName: _maybe<String>(json['vj_name']),
      suggestions: [
        for (final row in _rows(json['suggestions']))
          CreditSuggestion(
            vjId: _maybe<String>(row['vj_id']),
            name: _need<String>(row['name']),
            foundIn: _need<String>(row['found_in']),
          ),
      ],
    );
  }

  /// Credits a known VJ by [vjId], or adds one named [newVj] and credits
  /// them.
  Future<AdminEdition> setCredit(
    String id, {
    String? vjId,
    String? newVj,
  }) async => _edition(
    await _send('PUT', '/editions/${_id(id)}/credit', {
      'vj_id': ?vjId,
      'new_vj': ?newVj,
    }),
  );

  /// Publishes, or throws [AdminFailure.conflict] with what is missing.
  Future<AdminEdition> publish(String id) async =>
      _edition(await _send('POST', '/editions/${_id(id)}/publish'));

  Future<AdminEdition> hide(String id) async =>
      _edition(await _send('POST', '/editions/${_id(id)}/hide'));

  Future<void> approve(String itemId) async {
    await _send('POST', '/items/${_id(itemId)}/approve');
  }

  Future<KeyMade> newKey(String itemId, {required String label}) async => _key(
    _need<Map<String, Object?>>(
      await _send('POST', '/items/${_id(itemId)}/keys', {'label': label}),
    ),
  );

  Future<void> revokeKey(String keyId) async {
    await _send('POST', '/keys/${_id(keyId)}/revoke');
  }

  /// Every series edition, in any state, for the upload screen.
  Future<List<AdminSeries>> series() async => [
    for (final row in _rows(await _send('GET', '/series')))
      AdminSeries(
        id: _need<String>(row['id']),
        title: _need<String>(row['display_title']),
        language: _need<String>(row['language']),
        status: _need<String>(row['status']),
        vjId: _maybe<String>(row['vj_id']),
        vjName: _maybe<String>(row['vj_name']),
        episodes: [
          for (final pair in _need<List<Object?>>(row['episodes'] ?? const []))
            switch (_need<List<Object?>>(pair)) {
              [final season, final episode] => (
                _maybe<int>(season),
                _maybe<int>(episode),
              ),
              _ => _bad(),
            },
        ],
      ),
  ];

  Future<List<AdminVj>> vjs() async => [
    for (final row in _rows(await _send('GET', '/vjs'))) _vj(row),
  ];

  Future<AdminVj> addVj({
    required String name,
    List<String> matchNames = const [],
    String? bio,
  }) async => _vj(
    await _send('POST', '/vjs', {
      'name': name,
      'match_names': matchNames,
      'bio': ?bio,
    }),
  );

  /// Changes what is given. [photoPath] is an uploaded image's path, or ""
  /// to remove the photo.
  Future<AdminVj> changeVj(
    String id, {
    String? name,
    List<String>? matchNames,
    String? bio,
    String? photoPath,
  }) async => _vj(
    await _send('PATCH', '/vjs/${_id(id)}', {
      'name': ?name,
      'match_names': ?matchNames,
      'bio': ?bio,
      'photo_path': ?photoPath,
    }),
  );

  Future<List<AdminLanguage>> languages() async => [
    for (final row in _rows(await _send('GET', '/languages')))
      AdminLanguage(
        code: _need<String>(row['code']),
        name: _need<String>(row['name']),
      ),
  ];

  Future<void> addLanguage(String code, String name) async {
    await _send('POST', '/languages', {'code': code, 'name': name});
  }

  Future<List<AdminEntry>> admins() async => [
    for (final row in _rows(await _send('GET', '/admins')))
      AdminEntry(
        userId: _need<String>(row['user_id']),
        email: _maybe<String>(row['email']),
        addedByEmail: _maybe<String>(row['added_by_email']),
        addedAt: _time(row['added_at']),
      ),
  ];

  /// Adds an admin by email. They must have signed in to VeloraUG once,
  /// and confirmed that email.
  Future<void> addAdmin(String email) async {
    await _send('POST', '/admins', {'email': email});
  }

  /// The last admin can't be removed: that is a [AdminFailure.conflict].
  Future<void> removeAdmin(String userId) async {
    await _send('DELETE', '/admins/${_id(userId)}');
  }

  /// Uploads a poster for an edition, or a VJ's photo, through the media
  /// gateway, and returns its path to choose.
  Future<String> uploadImage({
    required bool poster,
    required String ownerId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final json = _need<Map<String, Object?>>(
      await _send('POST', '/images', {
        'folder': poster ? 'posters' : 'vjs',
        'owner_id': ownerId,
        'content_type': contentType,
      }),
    );
    final path = _need<String>(json['path']);
    final upload = Uri.tryParse(_need<String>(json['upload_url'])) ?? _bad();
    if (upload.scheme != mediaBaseUrl.scheme ||
        upload.host != mediaBaseUrl.host ||
        upload.port != mediaBaseUrl.port ||
        upload.userInfo.isNotEmpty ||
        !upload.path.startsWith('/i/') ||
        upload.hasQuery) {
      _bad();
    }
    final http.Response response;
    try {
      response = await httpClient
          .put(upload, headers: {'Content-Type': contentType}, body: bytes)
          .timeout(timeout);
    } on Exception {
      throw const AdminException(AdminFailure.unreachable);
    }
    switch (response.statusCode) {
      case 200 || 201:
        return path;
      case 413 || 415:
        throw const AdminException(AdminFailure.badImage);
      case 403:
        // The upload's ten minutes ran out.
        throw const AdminException(AdminFailure.conflict);
      default:
        _bad();
    }
  }

  String _id(String id) => Uri.encodeComponent(id);

  Future<Object?> _send(
    String method,
    String path, [
    Map<String, Object?>? body,
  ]) async {
    final String? token;
    try {
      token = await accessToken();
    } on OAuthException {
      throw const AdminException(AdminFailure.unreachable);
    }
    if (token == null) throw const AdminException(AdminFailure.signedOut);
    final request = http.Request(
      method,
      baseUrl.replace(path: '/api/v1/admin$path'),
    )..headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await httpClient.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const AdminException(AdminFailure.unreachable);
    } on Exception {
      throw const AdminException(AdminFailure.unreachable);
    }
    Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      json = null;
    }
    final status = response.statusCode;
    if (status == 200 || status == 201) return json;
    throw _failure(status, json);
  }

  AdminException _failure(int status, Object? json) {
    final detail = json is Map<String, Object?> ? json['detail'] : null;
    String? text;
    var missing = const <String>[];
    if (detail is String) {
      text = detail;
    } else if (detail is Map<String, Object?>) {
      text = detail['message'] is String ? detail['message'] as String : null;
      final listed = detail['missing'];
      if (listed is List) missing = [...listed.whereType<String>()];
    } else if (detail is List && status == 422) {
      text = null;
    }
    final failure = switch (status) {
      400 || 422 => AdminFailure.invalid,
      401 => AdminFailure.refused,
      403 => AdminFailure.notAdmin,
      404 => AdminFailure.notFound,
      409 => AdminFailure.conflict,
      503 => AdminFailure.busy,
      _ => AdminFailure.unexpected,
    };
    return AdminException(failure, detail: text, missing: missing);
  }

  AdminEdition _edition(Object? value) {
    final json = _need<Map<String, Object?>>(value);
    return AdminEdition(
      id: _need<String>(json['id']),
      kind: json['kind'] == 'series' ? EditionKind.series : EditionKind.movie,
      displayTitle: _need<String>(json['display_title']),
      submittedYear: _maybe<int>(json['submitted_year']),
      language: _need<String>(json['language']),
      status: _need<String>(json['status']),
      test: _need<bool>(json['test'] ?? false),
      tmdbLookup: _maybe<String>(json['tmdb_lookup']),
      sourceTmdbId: _maybe<int>(json['source_tmdb_id']),
      sourceTitle: _maybe<String>(json['source_title']),
      sourceYear: _maybe<int>(json['source_year']),
      sourceOverview: _maybe<String>(json['source_overview']),
      detailsFrom: _maybe<String>(json['details_from']),
      posterPath: _maybe<String>(json['poster_path']),
      posterUrl: safeImageUrl(json['poster_url'], gateway: mediaBaseUrl),
      vjId: _maybe<String>(json['vj_id']),
      vjName: _maybe<String>(json['vj_name']),
      items: [for (final row in _rows(json['items'] ?? const [])) _item(row)],
      missing: [
        for (final text in _need<List<Object?>>(json['missing'] ?? const []))
          _need<String>(text),
      ],
      matches: [
        for (final row in _rows(json['matches'] ?? const []))
          TmdbMatch(
            tmdbId: _need<int>(row['tmdb_id']),
            title: _need<String>(row['title']),
            originalTitle: _maybe<String>(row['original_title']),
            year: _maybe<int>(row['year']),
            overview: _maybe<String>(row['overview']),
            posterUrl: safeImageUrl(row['poster_url'], gateway: mediaBaseUrl),
          ),
      ],
    );
  }

  AdminItem _item(Map<String, Object?> json) => AdminItem(
    id: _need<String>(json['id']),
    season: _maybe<int>(json['season']),
    episode: _maybe<int>(json['episode']),
    episodeTitle: _maybe<String>(json['episode_title']),
    approved: _need<bool>(json['approved'] ?? false),
    video: _maybe<String>(json['video']),
    videoReason: _maybe<String>(json['video_reason']),
    previewable: _need<bool>(json['previewable'] ?? false),
    filename: _maybe<String>(json['filename']),
    creditHints: _maybe<String>(json['credit_hints']),
    keys: [
      for (final key in _rows(json['keys'] ?? const []))
        UploadKeyInfo(
          id: _need<String>(key['id']),
          label: _need<String>(key['label']),
          expiresAt: _time(key['expires_at']),
          used: _need<bool>(key['used'] ?? false),
          revoked: _need<bool>(key['revoked'] ?? false),
        ),
    ],
  );

  AdminVj _vj(Object? value) {
    final json = _need<Map<String, Object?>>(value);
    return AdminVj(
      id: _need<String>(json['id']),
      name: _need<String>(json['name']),
      slug: _need<String>(json['slug']),
      matchNames: [
        for (final name in _need<List<Object?>>(
          json['match_names'] ?? const [],
        ))
          _need<String>(name),
      ],
      photoUrl: safeImageUrl(json['photo_url'], gateway: mediaBaseUrl),
      bio: _maybe<String>(json['bio']),
      editions: _need<int>(json['editions'] ?? 0),
    );
  }

  KeyMade _key(Map<String, Object?> json) => KeyMade(
    keyId: _need<String>(json['key_id']),
    uploadKey: _need<String>(json['upload_key']),
    expiresAt: _time(json['expires_at']),
    editionId: _maybe<String>(json['edition_id']),
    itemId: _maybe<String>(json['item_id']),
  );
}

/// Words for a failure. A refused change also shows the API's reason,
/// since only admins see these screens.
String adminFailureMessage(AppLocalizations l, AdminException error) {
  final base = switch (error.failure) {
    AdminFailure.signedOut => l.adminSignedOut,
    AdminFailure.refused => l.signInNotAccepted,
    AdminFailure.notAdmin => l.adminOnly,
    AdminFailure.notFound => l.adminNotFound,
    AdminFailure.conflict => l.adminConflict,
    AdminFailure.invalid => l.adminInvalid,
    AdminFailure.badImage => l.adminBadImage,
    AdminFailure.busy => l.busy,
    AdminFailure.unreachable => l.unreachable,
    AdminFailure.unexpected => l.somethingWentWrong,
  };
  final detail = error.detail;
  return detail == null || detail.isEmpty ? base : '$base $detail';
}

/// Gives the screens below it the admin routes. Null when this build has
/// no API or media address, or no sign-in.
class AdminScope extends InheritedWidget {
  const AdminScope({super.key, required this.api, required super.child});

  final AdminApi? api;

  static AdminApi? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminScope>()?.api;

  @override
  bool updateShouldNotify(AdminScope oldWidget) => api != oldWidget.api;
}
