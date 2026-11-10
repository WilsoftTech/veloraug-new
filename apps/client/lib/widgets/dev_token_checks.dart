import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../api/profile_api.dart';
import '../auth/auth_controller.dart';
import '../auth/oauth_client.dart';
import '../theme/tokens.dart';
import 'status_badge.dart';

/// Development tool for the Step 5G token checks with a real token.
///
/// Show it only behind kDebugMode. It sends GET /api/v1/me with no token, a
/// changed token, or a token kept from earlier, and shows only the status
/// code and whether it was expected. The kept token stays in memory, is
/// never shown, logged or copied, and is gone when the app closes.
class DevTokenChecks extends StatefulWidget {
  const DevTokenChecks({
    super.key,
    required this.auth,
    this.baseUrl = apiBaseUrlSetting,
    this.httpClient,
    this.clock,
  });

  final AuthController? auth;
  final String baseUrl;
  final http.Client? httpClient;
  final DateTime Function()? clock;

  @override
  State<DevTokenChecks> createState() => _DevTokenChecksState();
}

class _Result {
  const _Result(this.text, {required this.asExpected});

  final String text;
  final bool asExpected;
}

class _DevTokenChecksState extends State<DevTokenChecks> {
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  ProfileApi? _api;
  String? _kept;
  DateTime? _keptAt;
  DateTime? _keptExpires;
  final List<_Result> _results = [];
  bool _busy = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final auth = widget.auth;
    if (auth == null) return;
    try {
      _api = ProfileApi(
        baseUrl: parseApiBaseUrl(widget.baseUrl),
        httpClient: _httpClient,
        accessToken: auth.accessToken,
      );
    } on FormatException {
      _api = null;
    }
  }

  @override
  void dispose() {
    _kept = null;
    if (widget.httpClient == null) _httpClient.close();
    super.dispose();
  }

  void _add(_Result result) {
    setState(() {
      _results.insert(0, result);
      if (_results.length > 6) _results.removeLast();
    });
  }

  Future<void> _run(Future<void> Function(ProfileApi api) check) async {
    final api = _api;
    if (api == null || _busy) return;
    setState(() => _busy = true);
    try {
      await check(api);
    } on ProfileException catch (error) {
      _add(_Result(profileFailureMessage(error.failure), asExpected: false));
    } on OAuthException {
      _add(const _Result("Couldn't renew the token.", asExpected: false));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _currentToken() async {
    final token = await widget.auth!.accessToken();
    if (token == null) {
      _add(
        const _Result(
          'Signed out: the app has no token, so it sends none.',
          asExpected: true,
        ),
      );
    }
    return token;
  }

  Future<void> _sendNoToken(ProfileApi api) async {
    final status = await api.statusFor();
    _add(_expect('No token', status, 401));
  }

  Future<void> _sendChangedToken(ProfileApi api) async {
    final token = await _currentToken();
    if (token == null) return;
    final status = await api.statusFor(
      authorization: 'Bearer ${_changed(token)}',
    );
    _add(_expect('Token with one changed character', status, 401));
  }

  Future<void> _keep(ProfileApi api) async {
    final token = await _currentToken();
    if (token == null) return;
    final exp = readJwtPayload(token)?['exp'];
    setState(() {
      _kept = token;
      _keptAt = _now();
      _keptExpires = exp is int
          ? DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          : null;
    });
    _add(
      _Result(
        'Kept a token at ${_time(_keptAt!)}. '
        '${_keptExpires == null ? "Its expiry couldn't be read." : "It expires at ${_time(_keptExpires!)}."}',
        asExpected: true,
      ),
    );
  }

  Future<void> _sendKept(ProfileApi api) async {
    final kept = _kept;
    if (kept == null) return;
    final status = await api.statusFor(authorization: 'Bearer $kept');
    final now = _now();
    final minutes = now.difference(_keptAt!).inMinutes;
    final expired = _keptExpires != null && !now.isBefore(_keptExpires!);
    final signedOut = widget.auth!.status == AuthStatus.signedOut;
    final label =
        'Kept token, $minutes min old, '
        '${expired ? 'past its expiry' : 'before its expiry'}'
        '${signedOut ? ', after sign-out' : ''}';
    _add(_expect(label, status, expired ? 401 : 200));
  }

  _Result _expect(String label, int status, int expected) {
    final ok = status == expected;
    return _Result(
      '$label: the API answered $status. '
      '${ok ? 'As expected.' : 'Expected $expected.'}',
      asExpected: ok,
    );
  }

  /// One character of the signature changed, so only the signature check
  /// can catch it.
  static String _changed(String token) {
    final parts = token.split('.');
    if (parts.length != 3 || parts[2].length < 4) return '${token}x';
    final signature = parts[2];
    final middle = signature.length ~/ 2;
    final replacement = signature[middle] == 'A' ? 'B' : 'A';
    parts[2] =
        signature.substring(0, middle) +
        replacement +
        signature.substring(middle + 1);
    return parts.join('.');
  }

  static String _time(DateTime time) {
    final local = time.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final enabled = _api != null && !_busy;

    Widget button(String label, Future<void> Function(ProfileApi) check) =>
        OutlinedButton(
          onPressed: enabled ? () => _run(check) : null,
          child: Text(label),
        );

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Development only: token checks',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: VeloraSpacing.xs),
            Text(
              'Sends /api/v1/me with no token, a changed token, or a token '
              'kept from earlier, and shows only the answer. The kept token '
              'stays in memory and is never shown.',
              style: muted,
            ),
            const SizedBox(height: VeloraSpacing.sm),
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.xs,
              children: [
                button('Send no token', _sendNoToken),
                button('Send a changed token', _sendChangedToken),
                button('Keep the current token', _keep),
                if (_kept != null) button('Send the kept token', _sendKept),
              ],
            ),
            if (_results.isNotEmpty) const SizedBox(height: VeloraSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final result in _results)
                    Padding(
                      padding: const EdgeInsets.only(top: VeloraSpacing.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StatusBadge(
                            label: result.asExpected ? 'OK' : 'Check',
                            tone: result.asExpected
                                ? StatusTone.success
                                : StatusTone.danger,
                          ),
                          const SizedBox(width: VeloraSpacing.xs),
                          Expanded(child: Text(result.text)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
