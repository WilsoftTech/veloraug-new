import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:http/http.dart' as http;

import '../auth/oauth_client.dart';
import '../auth/oauth_config.dart';

/// Allows time to read an email and enter its code during sign-up.
const int _browserTimeoutSeconds = 600;

Future<String> _openBrowserStep(Uri url, Uri redirectUri) {
  return FlutterWebAuth2.authenticate(
    url: url.toString(),
    callbackUrlScheme: redirectUri.scheme,
    options: FlutterWebAuth2Options(
      timeout: _browserTimeoutSeconds,
      windowName: '_blank',
      httpsHost: redirectUri.host,
      httpsPath: redirectUri.path,
    ),
  );
}

/// Development tool for testing the Step 5B gates. Show it only behind
/// kDebugMode. Tokens stay in memory, and only non-secret facts are displayed.
class DevAuthProof extends StatefulWidget {
  const DevAuthProof({
    super.key,
    this.config,
    this.httpClient,
    this.browserStep,
  });

  /// Replaces the build-time settings in tests.
  final OAuthConfig? config;

  /// Replaces the real HTTP client in tests. The widget does not close it.
  final http.Client? httpClient;

  /// Replaces the browser in tests.
  final BrowserStep? browserStep;

  @override
  State<DevAuthProof> createState() => _DevAuthProofState();
}

class _DevAuthProofState extends State<DevAuthProof> {
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  OAuthClient? _client;
  String? _configProblem;

  OAuthTokens? _tokens;
  String? _previousRefreshToken;
  bool _busy = false;
  final List<String> _results = [];

  @override
  void initState() {
    super.initState();
    try {
      final config = widget.config ?? OAuthConfig.fromSettings();
      if (config == null) {
        _configProblem = 'The sign-in proof is not configured.';
      } else {
        _client = OAuthClient(
          config: config,
          httpClient: _httpClient,
          browserStep: widget.browserStep ?? _openBrowserStep,
        );
      }
    } on FormatException catch (error) {
      _configProblem = error.message;
    }
  }

  @override
  void dispose() {
    if (widget.httpClient == null) _httpClient.close();
    super.dispose();
  }

  Future<void> _run(String name, Future<List<String>> Function() action) async {
    setState(() {
      _busy = true;
      _results.add('$name: running');
    });
    List<String> lines;
    try {
      lines = await action();
    } on OAuthException catch (error) {
      lines = ['failed: ${error.message}'];
    } on Exception catch (error) {
      // Only the type: a platform message could quote a callback address.
      lines = ['failed: ${error.runtimeType}'];
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _results
        ..removeLast()
        ..add('$name:')
        ..addAll(lines.map((line) => '  $line'));
    });
  }

  Future<List<String>> _signIn() async {
    final tokens = await _client!.signIn();
    _tokens = tokens;
    _previousRefreshToken = null;
    return [
      'code exchanged',
      'refresh token returned: ${tokens.refreshToken != null}',
      'expires_in: ${tokens.expiresIn}',
      'ID token nonce matched: ${tokens.idTokenNonceMatched}',
      ...describeAccessToken(tokens.accessToken),
    ];
  }

  Future<List<String>> _refresh() async {
    final current = _tokens?.refreshToken;
    if (current == null) return ['no refresh token held'];
    final renewed = await _client!.refresh(current);
    _previousRefreshToken = current;
    _tokens = renewed;
    return [
      'refreshed',
      'refresh token rotated: ${renewed.refreshToken != current}',
      ...describeAccessToken(renewed.accessToken),
    ];
  }

  Future<List<String>> _reuseOldRefreshToken() async {
    final old = _previousRefreshToken;
    if (old == null) return ['refresh once first'];
    try {
      await _client!.refresh(old);
      return ['the rotated token was accepted'];
    } on OAuthException catch (error) {
      return ['refused: ${error.message}'];
    }
  }

  Future<List<String>> _revoke() async {
    final current = _tokens?.refreshToken;
    if (current == null) return ['no refresh token held'];
    final status = await _client!.revoke(current);
    return ['revocation status: $status'];
  }

  Future<List<String>> _endBrowserSession() async {
    await _client!.endBrowserSession();
    _tokens = null;
    _previousRefreshToken = null;
    return ['browser session ended, device tokens cleared'];
  }

  @override
  Widget build(BuildContext context) {
    final problem = _configProblem;
    final actions = <String, Future<List<String>> Function()>{
      'Sign in': _signIn,
      'Refresh': _refresh,
      'Reuse old refresh token': _reuseOldRefreshToken,
      'Revoke refresh token': _revoke,
      'End browser session': _endBrowserSession,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sign-in proof (Step 5B, development only)',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (problem != null)
          Text(problem)
        else ...[
          Text('Running on: ${kIsWeb ? 'web' : 'Android'}'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final MapEntry(key: name, value: action) in actions.entries)
                OutlinedButton(
                  onPressed: _busy ? null : () => _run(name, action),
                  child: Text(name),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(_results.join('\n')),
        ],
      ],
    );
  }
}
