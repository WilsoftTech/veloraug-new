import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../api/api_config.dart';
import '../api/profile_api.dart';
import '../auth/auth_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'loading_placeholder.dart';
import 'status_badge.dart';
import 'velora_button.dart';
import 'velora_text_field.dart';

const int displayNameMaxLength = 80;

enum _Phase { loading, ready, failed }

/// The signed-in person's profile: their display name, which they can change.
///
/// Build it only while signed in. It loads the profile when it first
/// appears, and the API creates the profile on first use.
class ProfileSection extends StatefulWidget {
  const ProfileSection({
    super.key,
    required this.auth,
    this.baseUrl = apiBaseUrlSetting,
    this.httpClient,
  });

  final AuthController auth;
  final String baseUrl;

  /// Replaces the real HTTP client in tests. The widget does not close it.
  final http.Client? httpClient;

  @override
  State<ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<ProfileSection> {
  late final http.Client _httpClient = widget.httpClient ?? http.Client();
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  ProfileApi? _api;
  _Phase _phase = _Phase.loading;
  String? _loadError;
  String? _saveMessage;
  bool _saveFailed = false;
  bool _saving = false;
  String? _savedName;

  @override
  void initState() {
    super.initState();
    try {
      _api = ProfileApi(
        baseUrl: parseApiBaseUrl(widget.baseUrl),
        httpClient: _httpClient,
        accessToken: widget.auth.accessToken,
      );
    } on FormatException {
      _phase = _Phase.failed;
      _loadError = "This version of the app can't reach VeloraUG.";
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    if (widget.httpClient == null) _httpClient.close();
    super.dispose();
  }

  Future<void> _load() async {
    final api = _api;
    if (api == null) return;
    if (_phase != _Phase.loading) {
      setState(() {
        _phase = _Phase.loading;
        _loadError = null;
      });
    }
    try {
      final profile = await api.fetch();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.ready;
        _savedName = profile.displayName;
        _name.text = profile.displayName ?? '';
      });
    } on ProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failed;
        _loadError = profileFailureMessage(error.failure);
      });
    }
  }

  Future<void> _save() async {
    final api = _api;
    if (api == null || _saving) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final trimmed = _name.text.trim();
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    try {
      final profile = await api.updateDisplayName(
        trimmed.isEmpty ? null : trimmed,
      );
      if (!mounted) return;
      setState(() {
        _savedName = profile.displayName;
        _name.text = profile.displayName ?? '';
        _saveMessage = profile.displayName == null
            ? 'Your name was removed.'
            : 'Saved.';
        _saveFailed = false;
      });
    } on ProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _saveMessage = profileFailureMessage(error.failure);
        _saveFailed = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validate(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.characters.length > displayNameMaxLength) {
      return 'Use $displayNameMaxLength characters or fewer.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('Your profile', style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: VeloraSpacing.sm),
            switch (_phase) {
              _Phase.loading => const Row(
                children: [
                  VeloraSpinner(),
                  SizedBox(width: VeloraSpacing.sm),
                  Expanded(child: Text('Loading your profile…')),
                ],
              ),
              _Phase.failed => _LoadFailed(
                message: _loadError ?? 'Something went wrong.',
                onRetry: _load,
              ),
              _Phase.ready => _buildForm(theme),
            },
          ],
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme) {
    final message = _saveMessage;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _savedName == null
                ? "You haven't set a display name yet."
                : 'Your display name is $_savedName.',
          ),
          const SizedBox(height: VeloraSpacing.sm),
          VeloraTextField(
            label: 'Display name',
            controller: _name,
            helperText:
                'Up to $displayNameMaxLength characters. Leave it empty to '
                'remove it.',
            validator: _validate,
            enabled: !_saving,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.nickname],
            onFieldSubmitted: (_) => _save(),
          ),
          const SizedBox(height: VeloraSpacing.sm),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: VeloraSpacing.sm),
              child: Semantics(
                liveRegion: true,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: StatusBadge(
                    label: message,
                    tone: _saveFailed ? StatusTone.danger : StatusTone.success,
                  ),
                ),
              ),
            ),
          VeloraButton(
            label: 'Save name',
            icon: Icons.save_outlined,
            isLoading: _saving,
            loadingLabel: 'Saving…',
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = VeloraPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: palette.danger),
              const SizedBox(width: VeloraSpacing.xs),
              Expanded(child: Text(message)),
            ],
          ),
        ),
        const SizedBox(height: VeloraSpacing.sm),
        VeloraButton(
          label: 'Try again',
          icon: Icons.refresh,
          variant: VeloraButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
