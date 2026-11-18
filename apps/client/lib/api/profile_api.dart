import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/oauth_client.dart';
import '../l10n/app_localizations.dart';

/// The signed-in person's profile, from /api/v1/me.
class Profile {
  const Profile({required this.userId, required this.displayName});

  final String userId;
  final String? displayName;
}

enum ProfileFailure {
  /// The app has no session, so it sent nothing.
  signedOut,

  /// The API refused the token: 401.
  refused,

  /// The API, or its database or sign-in check, is unavailable: 503.
  busy,

  /// No answer: no network, the API stopped, a timeout, or CORS.
  unreachable,

  /// The API refused the display name: 422.
  invalidName,

  /// Any other answer.
  unexpected,
}

class ProfileException implements Exception {
  const ProfileException(this.failure);

  final ProfileFailure failure;

  @override
  String toString() => 'ProfileException(${failure.name})';
}

/// Calls /api/v1/me with the person's access token.
///
/// The token comes from [accessToken] for each call, so it is renewed when
/// it is about to expire. It is sent only in the Authorization header, and
/// never logged or kept here.
class ProfileApi {
  ProfileApi({
    required this.baseUrl,
    required this.httpClient,
    required this.accessToken,
    this.timeout = const Duration(seconds: 15),
  });

  final Uri baseUrl;
  final http.Client httpClient;
  final Future<String?> Function() accessToken;

  /// Long enough for a database that has scaled to zero to wake.
  final Duration timeout;

  Uri get _me => baseUrl.replace(path: '/api/v1/me');

  Future<Profile> fetch() async {
    final token = await _token();
    return _profileFrom(
      await _send(() => httpClient.get(_me, headers: _headers(token))),
    );
  }

  /// Sets the display name, or clears it with null.
  Future<Profile> updateDisplayName(String? displayName) async {
    final token = await _token();
    return _profileFrom(
      await _send(
        () => httpClient.patch(
          _me,
          headers: {..._headers(token), 'Content-Type': 'application/json'},
          body: jsonEncode({'display_name': displayName}),
        ),
      ),
    );
  }

  /// Sends GET /api/v1/me with exactly this Authorization value, or none,
  /// and returns only the status code. For the debug-only token checks.
  Future<int> statusFor({String? authorization}) async {
    final response = await _send(
      () => httpClient.get(_me, headers: {'Authorization': ?authorization}),
      checkStatus: false,
    );
    return response.statusCode;
  }

  Future<String> _token() async {
    final String? token;
    try {
      token = await accessToken();
    } on OAuthException {
      // Renewing the token needed the network.
      throw const ProfileException(ProfileFailure.unreachable);
    }
    if (token == null) throw const ProfileException(ProfileFailure.signedOut);
    return token;
  }

  Map<String, String> _headers(String token) => {
    'Authorization': 'Bearer $token',
  };

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    bool checkStatus = true,
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw const ProfileException(ProfileFailure.unreachable);
    } on Exception {
      // Includes a browser blocking the reply, which looks the same.
      throw const ProfileException(ProfileFailure.unreachable);
    }
    if (!checkStatus) return response;
    switch (response.statusCode) {
      case 200:
        return response;
      case 401:
        throw const ProfileException(ProfileFailure.refused);
      case 422:
        throw const ProfileException(ProfileFailure.invalidName);
      case 503:
        throw const ProfileException(ProfileFailure.busy);
      default:
        throw const ProfileException(ProfileFailure.unexpected);
    }
  }

  Profile _profileFrom(http.Response response) {
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const ProfileException(ProfileFailure.unexpected);
    }
    if (json is! Map<String, Object?>) {
      throw const ProfileException(ProfileFailure.unexpected);
    }
    final userId = json['user_id'];
    final displayName = json['display_name'];
    if (userId is! String || (displayName != null && displayName is! String)) {
      throw const ProfileException(ProfileFailure.unexpected);
    }
    return Profile(userId: userId, displayName: displayName as String?);
  }
}

/// Words for each failure. They never repeat a token or the server's text.
String profileFailureMessage(AppLocalizations l, ProfileFailure failure) =>
    switch (failure) {
      ProfileFailure.signedOut => l.profileSignedOut,
      ProfileFailure.refused => l.signInNotAccepted,
      ProfileFailure.busy => l.busy,
      ProfileFailure.unreachable => l.unreachable,
      ProfileFailure.invalidName => l.profileInvalidName,
      ProfileFailure.unexpected => l.somethingWentWrong,
    };
