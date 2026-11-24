import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';
import 'catalogue_api.dart';
import 'playback_api.dart';

/// One movie or episode the viewer watched.
class HistoryEntry {
  const HistoryEntry({
    required this.itemId,
    required this.edition,
    required this.lastWatchedAt,
    this.season,
    this.episode,
    this.episodeTitle,
    this.resumeAt,
  });

  final String itemId;
  final EditionCard edition;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final DateTime lastWatchedAt;

  /// Where to carry on from, only when the API saved a reliable position.
  final Duration? resumeAt;

  bool get isEpisode => season != null && episode != null;
}

enum NotificationKind {
  paymentCompleted,
  paymentRefunded,
  passEnding,
  passEnded,
  deviceRemoved,
}

/// One notification in the inbox, built by the API from a real event.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.at,
    required this.read,
    this.planName,
    this.deviceLabel,
  });

  final String id;
  final NotificationKind kind;
  final DateTime at;
  final bool read;
  final String? planName;
  final String? deviceLabel;
}

class NotificationInbox {
  const NotificationInbox({required this.notifications, required this.unread});

  final List<AppNotification> notifications;
  final int unread;
}

enum DeletionState { none, pending, completed }

class DeletionStatus {
  const DeletionStatus({
    required this.available,
    required this.state,
    this.requestedAt,
  });

  /// Whether this server can delete an account from the app now.
  final bool available;
  final DeletionState state;
  final DateTime? requestedAt;
}

enum AccountFailure {
  /// No session on this device.
  signedOut,

  /// The API refused the sign-in: 401.
  refused,

  /// Deleting needs a sign-in within the last few minutes.
  reauthRequired,

  /// Not available on this server: 503 with a code saying so.
  unavailable,

  /// A deletion stopped part way and can be tried again: 502.
  incomplete,

  /// 404.
  notFound,

  /// 429.
  tooMany,

  /// 503: busy.
  busy,

  /// No answer.
  unreachable,

  /// Anything else.
  unexpected,
}

class AccountException implements Exception {
  const AccountException(this.failure);

  final AccountFailure failure;

  @override
  String toString() => 'AccountException(${failure.name})';
}

/// The account hub's routes: history, notifications and deletion. Signed in
/// through [playback], which holds the token and the device credential.
class AccountApi {
  const AccountApi({required this.playback, required this.catalogue});

  final PlaybackApi playback;

  /// Checks the edition cards in history as the catalogue checks its own.
  final CatalogueApi catalogue;

  Future<List<HistoryEntry>> history() async {
    final answer = await _send('GET', '/api/v1/me/history');
    final rows = answer.json;
    if (rows is! List<Object?>) _bad();
    final entries = <HistoryEntry>[];
    for (final row in rows) {
      if (row case {
        'item_id': final String itemId,
        'edition': final Object edition,
        'last_watched_at': final String at,
      }) {
        final when = DateTime.tryParse(at);
        if (when == null) _bad();
        final EditionCard card;
        try {
          card = catalogue.cardFrom(edition);
        } on CatalogueException {
          _bad();
        }
        final resume = row['resume_seconds'];
        entries.add(
          HistoryEntry(
            itemId: itemId,
            edition: card,
            lastWatchedAt: when.toUtc(),
            season: row['season'] is int ? row['season'] as int : null,
            episode: row['episode'] is int ? row['episode'] as int : null,
            episodeTitle: row['episode_title'] is String
                ? row['episode_title'] as String
                : null,
            resumeAt: resume is int && resume > 0
                ? Duration(seconds: resume)
                : null,
          ),
        );
      } else {
        _bad();
      }
    }
    return entries;
  }

  /// Saves where the player got to. Quiet: a failure is ignored, and the
  /// next save or the next grant carries on.
  Future<void> savePosition(
    String itemId,
    Duration position, {
    bool finished = false,
  }) async {
    try {
      await playback.send(
        'PUT',
        '/api/v1/me/history/${Uri.encodeComponent(itemId)}/position',
        body: {
          'position_seconds': position.inSeconds.clamp(0, 86400),
          'finished': finished,
        },
      );
    } on Object {
      // Not worth bothering the viewer about.
    }
  }

  Future<NotificationInbox> notifications() async {
    final answer = await _send('GET', '/api/v1/me/notifications');
    final json = answer.json;
    if (json case {
      'notifications': final List<Object?> rows,
      'unread': final int unread,
    }) {
      return NotificationInbox(
        unread: unread,
        notifications: [
          for (final row in rows)
            if (row case {
              'id': final String id,
              'kind': final String kind,
              'at': final String at,
              'read': final bool read,
            })
              if (_kinds[kind] case final known?)
                if (DateTime.tryParse(at) case final time?)
                  AppNotification(
                    id: id,
                    kind: known,
                    at: time.toUtc(),
                    read: read,
                    planName: row['plan_name'] is String
                        ? row['plan_name'] as String
                        : null,
                    deviceLabel: row['device_label'] is String
                        ? row['device_label'] as String
                        : null,
                  ),
        ],
      );
    }
    _bad();
  }

  /// Marks [ids] read, or with none, everything in the inbox now.
  Future<void> markRead([List<String> ids = const []]) async {
    await _send(
      'POST',
      '/api/v1/me/notifications/read',
      body: ids.isEmpty ? {'all': true} : {'ids': ids},
    );
  }

  Future<DeletionStatus> deletionStatus() async {
    final answer = await _send('GET', '/api/v1/me/deletion');
    return _deletion(answer.json);
  }

  /// Deletes the signed-in account. Needs a sign-in within the last few
  /// minutes: see [AccountFailure.reauthRequired].
  Future<DeletionStatus> deleteAccount() async {
    final answer = await _send('POST', '/api/v1/me/deletion');
    return _deletion(answer.json);
  }

  DeletionStatus _deletion(Object? json) {
    if (json case {
      'available': final bool available,
      'state': final String state,
    }) {
      final at = json['requested_at'];
      return DeletionStatus(
        available: available,
        state: switch (state) {
          'pending' => DeletionState.pending,
          'completed' => DeletionState.completed,
          'none' => DeletionState.none,
          _ => _bad(),
        },
        requestedAt: at is String ? DateTime.tryParse(at)?.toUtc() : null,
      );
    }
    _bad();
  }

  Future<ApiAnswer> _send(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    final ApiAnswer answer;
    try {
      answer = await playback.send(method, path, body: body);
    } on Object catch (error) {
      if (isSignedOut(error)) {
        throw const AccountException(AccountFailure.signedOut);
      }
      if (isNoAnswer(error)) {
        throw const AccountException(AccountFailure.unreachable);
      }
      rethrow;
    }
    final failure = switch (answer.status) {
      200 || 204 => null,
      401 when answer.code == 'reauth_required' =>
        AccountFailure.reauthRequired,
      401 => AccountFailure.refused,
      404 => AccountFailure.notFound,
      429 => AccountFailure.tooMany,
      502 when answer.code == 'deletion_incomplete' =>
        AccountFailure.incomplete,
      503 when answer.code == 'deletion_unavailable' =>
        AccountFailure.unavailable,
      503 => AccountFailure.busy,
      _ => AccountFailure.unexpected,
    };
    if (failure != null) throw AccountException(failure);
    return answer;
  }

  static const _kinds = {
    'payment_completed': NotificationKind.paymentCompleted,
    'payment_refunded': NotificationKind.paymentRefunded,
    'pass_ending': NotificationKind.passEnding,
    'pass_ended': NotificationKind.passEnded,
    'device_removed': NotificationKind.deviceRemoved,
  };
}

Never _bad() => throw const AccountException(AccountFailure.unexpected);

/// The account routes for the screens below, or null in a build without
/// playback or a catalogue.
AccountApi? accountApiOf(BuildContext context) {
  final playback = PlaybackScope.of(context);
  final catalogue = CatalogueScope.of(context);
  if (playback == null || catalogue == null) return null;
  return AccountApi(playback: playback, catalogue: catalogue);
}

/// Words for each failure. They never repeat the server's text.
String accountFailureMessage(AppLocalizations l, AccountFailure failure) =>
    switch (failure) {
      AccountFailure.signedOut => l.signInFirst,
      AccountFailure.refused => l.signInNotAccepted,
      AccountFailure.reauthRequired => l.reauthNeeded,
      AccountFailure.unavailable => l.deletionUnavailableMessage,
      AccountFailure.incomplete => l.deletionIncompleteMessage,
      AccountFailure.notFound => l.notAvailable,
      AccountFailure.tooMany => l.tooManyAttempts,
      AccountFailure.busy => l.busy,
      AccountFailure.unreachable => l.unreachable,
      AccountFailure.unexpected => l.somethingWentWrong,
    };
