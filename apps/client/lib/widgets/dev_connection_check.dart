import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/api_config.dart';
import '../theme/tokens.dart';
import 'loading_placeholder.dart';
import 'status_badge.dart';

enum _Phase { idle, loading, success, failure }

/// Development tool that checks whether the local API is answering.
///
/// Show it only behind kDebugMode. It starts only when asked, because the
/// navigation shell builds every screen when the app opens.
class DevConnectionCheck extends StatefulWidget {
  const DevConnectionCheck({
    super.key,
    this.baseUrl = apiBaseUrlSetting,
    this.httpClient,
  });

  final String baseUrl;

  /// Replaces the real HTTP client in tests. The widget does not close it.
  final http.Client? httpClient;

  @override
  State<DevConnectionCheck> createState() => _DevConnectionCheckState();
}

class _DevConnectionCheckState extends State<DevConnectionCheck> {
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  ApiClient? _apiClient;
  String? _configError;

  _Phase _phase = _Phase.idle;
  ServiceInfo? _serviceInfo;
  String? _failureMessage;

  @override
  void initState() {
    super.initState();
    try {
      _apiClient = ApiClient(
        baseUrl: parseApiBaseUrl(widget.baseUrl),
        httpClient: _httpClient,
      );
    } on FormatException catch (error) {
      _configError = error.message;
    }
  }

  @override
  void dispose() {
    if (widget.httpClient == null) {
      _httpClient.close();
    }
    super.dispose();
  }

  Future<void> _runCheck() async {
    if (_phase == _Phase.loading) {
      return;
    }
    final apiClient = _apiClient;
    if (apiClient == null) {
      setState(() {
        _phase = _Phase.failure;
        _failureMessage = _configError;
      });
      return;
    }

    setState(() {
      _phase = _Phase.loading;
      _serviceInfo = null;
      _failureMessage = null;
    });

    try {
      await apiClient.fetchHealth();
      if (!mounted) {
        return;
      }
      final serviceInfo = await apiClient.fetchServiceInfo();
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.success;
        _serviceInfo = serviceInfo;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _phase = _Phase.failure;
        _failureMessage = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Development only: API connection check',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: VeloraSpacing.xs),
            Text(
              'Asks the local API whether it is answering. This check is left '
              'out of release builds.',
              style: mutedStyle,
            ),
            const SizedBox(height: VeloraSpacing.xs),
            Text('API address: ${widget.baseUrl}', style: mutedStyle),
            const SizedBox(height: VeloraSpacing.md),
            Semantics(liveRegion: true, child: _buildStatus(theme, mutedStyle)),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(VeloraLayout.minTouchTarget),
              ),
              onPressed: _phase == _Phase.loading ? null : _runCheck,
              child: Text(switch (_phase) {
                _Phase.idle => 'Check connection',
                _Phase.loading => 'Checking…',
                _Phase.success => 'Check again',
                _Phase.failure => 'Try again',
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme, TextStyle? mutedStyle) {
    final serviceInfo = _serviceInfo;
    switch (_phase) {
      case _Phase.idle:
        return const SizedBox.shrink();
      case _Phase.loading:
        return const Padding(
          padding: EdgeInsets.only(bottom: VeloraSpacing.md),
          child: Row(
            children: [
              VeloraSpinner(),
              SizedBox(width: VeloraSpacing.sm),
              Expanded(child: Text('Checking the API…')),
            ],
          ),
        );
      case _Phase.success:
        return Padding(
          padding: const EdgeInsets.only(bottom: VeloraSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(
                  label: 'The API answered',
                  tone: StatusTone.success,
                ),
              ),
              const SizedBox(height: VeloraSpacing.xs),
              if (serviceInfo != null)
                Text(
                  'Service: ${serviceInfo.service}\n'
                  'API version: ${serviceInfo.apiVersion}\n'
                  'Environment: ${serviceInfo.environment}',
                ),
              const SizedBox(height: VeloraSpacing.xs),
              Text(
                'This only shows that the API process responded. It does not '
                'check sign-in, payments, a database or production readiness.',
                style: mutedStyle,
              ),
            ],
          ),
        );
      case _Phase.failure:
        return Padding(
          padding: const EdgeInsets.only(bottom: VeloraSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: StatusBadge(
                  label: 'The check failed',
                  tone: StatusTone.danger,
                ),
              ),
              const SizedBox(height: VeloraSpacing.xs),
              Text(_failureMessage ?? 'Something went wrong.'),
              if (_configError == null) ...[
                const SizedBox(height: VeloraSpacing.xs),
                Text(
                  'Check that the API is running. On a phone connected by USB, '
                  'also run: adb reverse tcp:8000 tcp:8000',
                  style: mutedStyle,
                ),
              ],
            ],
          ),
        );
    }
  }
}
