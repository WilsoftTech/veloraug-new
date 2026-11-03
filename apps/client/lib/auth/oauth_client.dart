import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'oauth_config.dart';
import 'pkce.dart';

/// Opens the browser step and returns the address it ended on.
typedef BrowserStep = Future<String> Function(Uri url, Uri redirectUri);

/// A failure that is safe to show. It never contains a code or token.
class OAuthException implements Exception {
  const OAuthException(this.message);

  final String message;

  @override
  String toString() => 'OAuthException: $message';
}

/// Tokens from Neon Auth. Don't log or display these.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
    required this.idTokenNonceMatched,
  });

  final String accessToken;
  final String? refreshToken;
  final int? expiresIn;

  /// Null when the reply had no ID token. An ID token with the wrong nonce is
  /// refused, so this is never false.
  final bool? idTokenNonceMatched;
}

class _Endpoints {
  const _Endpoints(this.authorization, this.token, this.revocation);

  final Uri authorization;
  final Uri token;
  final Uri? revocation;
}

/// Authorization code flow with PKCE S256, as a public client with no secret.
class OAuthClient {
  OAuthClient({
    required this.config,
    required http.Client httpClient,
    required this._browserStep,
  }) : _http = httpClient;

  static const Duration _timeout = Duration(seconds: 20);
  static const String _scope = 'openid email offline_access';

  final OAuthConfig config;
  final http.Client _http;
  final BrowserStep _browserStep;

  _Endpoints? _endpoints;
  Future<OAuthTokens>? _refreshInFlight;

  Future<_Endpoints> _discover() async {
    final known = _endpoints;
    if (known != null) return known;

    final response = await _send(
      () => _http.get(
        Uri.parse('${config.issuer}/.well-known/oauth-authorization-server'),
      ),
      'discovery',
    );
    final body = _decodeObject(response, 'discovery');
    if (response.statusCode != 200) {
      throw OAuthException('Discovery failed with ${response.statusCode}.');
    }
    if (body['issuer'] != config.issuer) {
      throw const OAuthException('The issuer does not match this app.');
    }
    final authorization = body['authorization_endpoint'];
    final token = body['token_endpoint'];
    if (authorization is! String || token is! String) {
      throw const OAuthException('Discovery did not list the endpoints.');
    }
    final revocation = body['revocation_endpoint'];
    return _endpoints = _Endpoints(
      Uri.parse(authorization),
      Uri.parse(token),
      revocation is String ? Uri.parse(revocation) : null,
    );
  }

  Future<OAuthTokens> signIn() async {
    final endpoints = await _discover();
    final verifier = randomUrlSafe();
    final state = randomUrlSafe();
    final nonce = randomUrlSafe();

    final authorizeUrl = endpoints.authorization.replace(
      queryParameters: {
        ...endpoints.authorization.queryParameters,
        'response_type': 'code',
        'client_id': config.clientId,
        'redirect_uri': config.redirectUri.toString(),
        'scope': _scope,
        'state': state,
        'nonce': nonce,
        'code_challenge': pkceS256Challenge(verifier),
        'code_challenge_method': 'S256',
        'resource': config.resource,
      },
    );

    final result = await _browserStep(authorizeUrl, config.redirectUri);
    final code = _readCode(result, expectedState: state);

    return _requestTokens(
      endpoints.token,
      {
        'grant_type': 'authorization_code',
        'code': code,
        'code_verifier': verifier,
        'redirect_uri': config.redirectUri.toString(),
        'client_id': config.clientId,
        'resource': config.resource,
      },
      'exchange',
      expectedNonce: nonce,
    );
  }

  String _readCode(String result, {required String expectedState}) {
    final uri = Uri.tryParse(result);
    final expected = config.redirectUri;
    if (uri == null ||
        uri.scheme != expected.scheme ||
        uri.authority != expected.authority ||
        uri.path != expected.path) {
      throw const OAuthException('The sign-in returned to the wrong address.');
    }
    final parameters = uri.queryParameters;
    // Checked first, so that an error reply from another request is ignored.
    if (parameters['state'] != expectedState) {
      throw const OAuthException('The sign-in state did not match.');
    }
    final issuer = parameters['iss'];
    if (issuer != null && issuer != config.issuer) {
      throw const OAuthException('The sign-in came from the wrong issuer.');
    }
    final error = parameters['error'];
    if (error != null) {
      throw OAuthException('The sign-in was refused: ${_safeCode(error)}.');
    }
    final code = parameters['code'];
    if (code == null || code.isEmpty) {
      throw const OAuthException('The sign-in returned no code.');
    }
    return code;
  }

  /// Renews tokens. Calls made while one is running share its result, because
  /// presenting a rotated refresh token can revoke the user's refresh tokens.
  Future<OAuthTokens> refresh(String refreshToken) {
    return _refreshInFlight ??= _refresh(refreshToken).whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<OAuthTokens> _refresh(String refreshToken) async {
    final endpoints = await _discover();
    return _requestTokens(endpoints.token, {
      'grant_type': 'refresh_token',
      'refresh_token': refreshToken,
      'client_id': config.clientId,
    }, 'refresh');
  }

  /// Revokes a refresh token. Returns the HTTP status for the proof to record.
  Future<int> revoke(String refreshToken) async {
    final endpoints = await _discover();
    final revocation = endpoints.revocation;
    if (revocation == null) {
      throw const OAuthException('Discovery did not list revocation.');
    }
    final response = await _send(
      () => _http.post(
        revocation,
        body: {
          'token': refreshToken,
          'token_type_hint': 'refresh_token',
          'client_id': config.clientId,
        },
      ),
      'revocation',
    );
    return response.statusCode;
  }

  /// Opens the sign-out page, which ends the browser's Neon session.
  Future<void> endBrowserSession() async {
    final result = await _browserStep(config.signOutPage, config.redirectUri);
    if (Uri.tryParse(result)?.queryParameters['signed_out'] != '1') {
      throw const OAuthException('The sign-out page did not confirm.');
    }
  }

  Future<OAuthTokens> _requestTokens(
    Uri tokenEndpoint,
    Map<String, String> form,
    String step, {
    String? expectedNonce,
  }) async {
    final response = await _send(
      () => _http.post(
        tokenEndpoint,
        headers: {'Accept': 'application/json'},
        body: form,
      ),
      step,
    );
    final body = _decodeObject(response, step);
    if (response.statusCode != 200) {
      final error = body['error'];
      final code = error is String ? ' (${_safeCode(error)})' : '';
      throw OAuthException('Token $step failed: ${response.statusCode}$code.');
    }
    final accessToken = body['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw OAuthException('Token $step returned no access token.');
    }

    bool? nonceMatched;
    final idToken = body['id_token'];
    if (expectedNonce != null && idToken is String) {
      if (readJwtPayload(idToken)?['nonce'] != expectedNonce) {
        throw const OAuthException('The ID token nonce did not match.');
      }
      nonceMatched = true;
    }

    final refreshToken = body['refresh_token'];
    final expiresIn = body['expires_in'];
    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: refreshToken is String ? refreshToken : null,
      expiresIn: expiresIn is int ? expiresIn : null,
      idTokenNonceMatched: nonceMatched,
    );
  }

  Future<http.Response> _send(
    Future<http.Response> Function() request,
    String step,
  ) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw OAuthException('The $step request timed out.');
    } on http.ClientException {
      // The message can include the address, so it isn't passed on. In a
      // browser this is also what a CORS refusal looks like.
      throw OAuthException('The $step request was blocked or failed.');
    }
  }

  Map<String, dynamic> _decodeObject(http.Response response, String step) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) return body;
    } on FormatException {
      // Reported below.
    }
    throw OAuthException(
      'The $step reply was not readable (${response.statusCode}).',
    );
  }

  /// Keeps only characters that an OAuth error code may contain.
  String _safeCode(String value) {
    final safe = value.replaceAll(RegExp(r'[^\w.-]'), '');
    return safe.length > 60 ? safe.substring(0, 60) : safe;
  }
}

/// Reads a JWT's payload without checking its signature, or returns null if it
/// isn't a JWT. This says nothing about whether the token is genuine.
Map<String, dynamic>? readJwtPayload(String token) {
  return _readJwtPart(token, 1);
}

/// Reads a JWT's header, on the same terms as [readJwtPayload].
Map<String, dynamic>? readJwtHeader(String token) {
  return _readJwtPart(token, 0);
}

Map<String, dynamic>? _readJwtPart(String token, int index) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final text = utf8.decode(
      base64Url.decode(base64Url.normalize(parts[index])),
    );
    final value = jsonDecode(text);
    return value is Map<String, dynamic> ? value : null;
  } on FormatException {
    return null;
  }
}

/// Facts about an access token that are safe to record for gate G7. It holds
/// claim names and shapes, and leaves out the token, its signature and `sub`.
List<String> describeAccessToken(String token) {
  final header = readJwtHeader(token);
  final payload = readJwtPayload(token);
  if (header == null || payload == null) {
    return ['Access token: opaque, not a JWT'];
  }
  final issuedAt = payload['iat'];
  final expiresAt = payload['exp'];
  final subject = payload['sub'];
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  return [
    'Access token: JWT, signature not checked here',
    'alg: ${header['alg']}, kid present: ${header['kid'] != null}',
    'iss: ${payload['iss']}',
    'aud: ${payload['aud']} (${payload['aud'].runtimeType})',
    'client_id: ${payload['client_id']}',
    'scope: ${payload['scope']}',
    'sub is a UUID: ${subject is String && uuid.hasMatch(subject)}',
    'iat present: ${issuedAt != null}',
    if (issuedAt is int && expiresAt is int)
      'lifetime: ${expiresAt - issuedAt} seconds',
    'claim names: ${(payload.keys.toList()..sort()).join(', ')}',
  ];
}
