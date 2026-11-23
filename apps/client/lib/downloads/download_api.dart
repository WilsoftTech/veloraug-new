import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../api/playback_api.dart';

/// What the API said when asked to renew the downloads' offline licences.
sealed class LicenceAnswer {
  const LicenceAnswer();
}

/// Each item asked about: until when it may play offline, or null when it
/// may no longer be kept (taken down, or no video any more).
class LicencesRenewed extends LicenceAnswer {
  const LicencesRenewed(this.until);

  final Map<String, DateTime?> until;
}

/// This device may keep none: no pass running (402), the device removed
/// or not registered (403), or more devices than the plan allows (409).
class LicencesRefused extends LicenceAnswer {
  const LicencesRefused(this.reason);

  final LicenceRefusal reason;
}

enum LicenceRefusal {
  /// 402: no pass running. Downloads wait for the next pass.
  noPass,

  /// 403: this device was removed, and couldn't register again.
  deviceRemoved,

  /// 409: more devices than the plan allows.
  deviceLimit,
}

/// No answer, or one that says nothing: try again later. Nothing changes.
class LicencesUnknown extends LicenceAnswer {
  const LicencesUnknown();
}

/// A file the media gateway refused or couldn't give.
class MediaFetchException implements Exception {
  const MediaFetchException(this.status);

  /// The HTTP status, or null when nothing came back.
  final int? status;

  /// The grant ran out, or is no longer honoured: ask for a new one.
  bool get refused => status == 403;

  @override
  String toString() => 'MediaFetchException($status)';
}

/// The API most offline licences are renewed with at once.
const int maxLicencesPerRequest = 200;

extension DownloadRequests on PlaybackApi {
  /// Renews the offline licences of up to [maxLicencesPerRequest] items.
  /// A device the API doesn't know registers itself once, as playback does.
  Future<LicenceAnswer> renewLicences(List<String> itemIds) async {
    Future<ApiAnswer> ask() => send(
      'POST',
      '/api/v1/me/offline-licences',
      body: {'items': itemIds.take(maxLicencesPerRequest).toList()},
    );
    try {
      var answer = await ask();
      if (answer.status == 403 && answer.code == 'device_required') {
        try {
          await registerDevice();
        } on PlaybackException {
          return const LicencesRefused(LicenceRefusal.deviceRemoved);
        }
        answer = await ask();
      }
      switch (answer.status) {
        case 200:
          final rows = switch (answer.json) {
            {'licences': final List<Object?> rows} => rows,
            _ => null,
          };
          if (rows == null) return const LicencesUnknown();
          return LicencesRenewed({
            for (final row in rows)
              if (row case {'item_id': final String id})
                id: switch (row['offline_until']) {
                  final String text => DateTime.tryParse(text)?.toUtc(),
                  _ => null,
                },
          });
        case 402:
          return const LicencesRefused(LicenceRefusal.noPass);
        case 403:
          return const LicencesRefused(LicenceRefusal.deviceRemoved);
        case 409:
          return const LicencesRefused(LicenceRefusal.deviceLimit);
        default:
          return const LicencesUnknown();
      }
    } on Exception {
      return const LicencesUnknown();
    }
  }

  /// One file from the media gateway, whole. Throws [MediaFetchException].
  Future<Uint8List> fetchMedia(Uri url, {Duration? within}) async {
    final http.Response response;
    try {
      response = await httpClient
          .get(url)
          .timeout(within ?? const Duration(seconds: 60));
    } on Exception {
      throw const MediaFetchException(null);
    }
    if (response.statusCode != 200) {
      throw MediaFetchException(response.statusCode);
    }
    return response.bodyBytes;
  }
}
