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
import '../l10n/l10n.dart';

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

  /// Null with no API address in this build.
  ProfileFailure? _loadFailure;

  /// After saving: the failure, or null for success.
  ProfileFailure? _saveFailure;
  bool _saved = false;
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
        _loadFailure = null;
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
        _loadFailure = error.failure;
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
      _saved = false;
      _saveFailure = null;
    });
    try {
      final profile = await api.updateDisplayName(
        trimmed.isEmpty ? null : trimmed,
      );
      if (!mounted) return;
      setState(() {
        _savedName = profile.displayName;
        _name.text = profile.displayName ?? '';
        _saved = true;
      });
    } on ProfileException catch (error) {
      if (!mounted) return;
      setState(() {
        _saveFailure = error.failure;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _validate(String? value) {
    final trimmed = (value ?? '').trim();
    if (trimmed.characters.length > displayNameMaxLength) {
      return context.l10n.nameTooLong(displayNameMaxLength);
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l.yourProfile, style: theme.textTheme.titleMedium),
            ),
            const SizedBox(height: VeloraSpacing.sm),
            switch (_phase) {
              _Phase.loading => Row(
                children: [
                  const VeloraSpinner(),
                  const SizedBox(width: VeloraSpacing.sm),
                  Expanded(child: Text(l.loadingProfile)),
                ],
              ),
              _Phase.failed => _LoadFailed(
                message: switch (_loadFailure) {
                  final failure? => profileFailureMessage(l, failure),
                  null => l.noApiAddress,
                },
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
    final l = context.l10n;
    final failure = _saveFailure;
    final message = failure != null
        ? profileFailureMessage(l, failure)
        : _saved
        ? (_savedName == null ? l.nameRemoved : l.saved)
        : null;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(switch (_savedName) {
            final name? => l.displayNameIs(name),
            null => l.noDisplayName,
          }),
          const SizedBox(height: VeloraSpacing.sm),
          VeloraTextField(
            label: l.displayName,
            controller: _name,
            helperText: l.displayNameHelp(displayNameMaxLength),
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
                    tone: failure != null
                        ? StatusTone.danger
                        : StatusTone.success,
                  ),
                ),
              ),
            ),
          VeloraButton(
            label: l.saveName,
            icon: Icons.save_outlined,
            isLoading: _saving,
            loadingLabel: l.saving,
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
          label: context.l10n.tryAgain,
          icon: Icons.refresh,
          variant: VeloraButtonVariant.secondary,
          onPressed: onRetry,
        ),
      ],
    );
  }
}
