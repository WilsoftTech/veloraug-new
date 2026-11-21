import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';

/// Settings: the admins, and the languages editions can be in. Plans and
/// prices are under Subscriptions.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  List<AdminEntry>? _admins;
  List<AdminLanguage>? _languages;
  AdminException? _failure;
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _languageName = TextEditingController();
  final _adminForm = GlobalKey<FormState>();
  final _languageForm = GlobalKey<FormState>();
  bool _started = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _languageName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final admins = await api.admins();
      final languages = await api.languages();
      if (!mounted) return;
      setState(() {
        _admins = admins;
        _languages = languages;
        _failure = null;
      });
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _run(
    Future<void> Function(AdminApi api) action,
    String done,
  ) async {
    setState(() => _busy = true);
    final ok = await runAdmin(context, (api) async {
      await action(api);
      return true;
    }, done: done);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) await _load();
  }

  Future<void> _addAdmin() async {
    if (!(_adminForm.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    final email = _email.text.trim();
    await _run((api) => api.addAdmin(email), l.adminAdded(email));
    if (mounted) _email.clear();
  }

  Future<void> _removeAdmin(AdminEntry admin) async {
    final l = context.l10n;
    final who = admin.email ?? admin.userId;
    if (!await confirm(
      context,
      title: l.removeAdminTitle,
      message: l.removeAdminMessage(who),
      action: l.remove,
    )) {
      return;
    }
    if (!mounted) return;
    await _run((api) => api.removeAdmin(admin.userId), l.adminRemoved(who));
  }

  Future<void> _addLanguage() async {
    if (!(_languageForm.currentState?.validate() ?? false)) return;
    final l = context.l10n;
    final name = _languageName.text.trim();
    await _run(
      (api) => api.addLanguage(_code.text.trim().toLowerCase(), name),
      l.languageAdded(name),
    );
    if (mounted) {
      _code.clear();
      _languageName.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final failure = _failure;
    final admins = _admins;
    final languages = _languages;
    final dates = MaterialLocalizations.of(context);
    return ScreenBody(
      heading: l.adminSettings,
      children: [
        if (failure != null)
          ErrorState(
            title: l.adminLoadFailed,
            message: adminFailureMessage(l, failure),
            onRetry: _load,
          )
        else if (admins == null || languages == null)
          Center(
            child: VeloraLoadingRegion(
              label: l.loading,
              child: const VeloraSpinner(size: 32),
            ),
          )
        else ...[
          AdminSection(
            title: l.admins,
            children: [
              Text(l.adminsIntro),
              for (final admin in admins)
                Card.outlined(
                  key: ValueKey(admin.userId),
                  child: ListTile(
                    title: Text(admin.email ?? admin.userId),
                    subtitle: Text(
                      admin.addedByEmail == null
                          ? l.addedOn(
                              dates.formatMediumDate(admin.addedAt.toLocal()),
                            )
                          : l.addedByOn(
                              admin.addedByEmail!,
                              dates.formatMediumDate(admin.addedAt.toLocal()),
                            ),
                    ),
                    trailing: admins.length > 1
                        ? TextButton(
                            onPressed: _busy ? null : () => _removeAdmin(admin),
                            child: Text(l.remove),
                          )
                        : Text(l.lastAdmin),
                  ),
                ),
              Form(
                key: _adminForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: VeloraSpacing.sm,
                  children: [
                    VeloraTextField(
                      label: l.adminEmail,
                      helperText: l.adminEmailHelp,
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) =>
                          (v ?? '').contains('@') ? null : l.enterEmail,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: VeloraButton(
                        label: l.addAdmin,
                        icon: Icons.person_add_alt,
                        isLoading: _busy,
                        onPressed: _addAdmin,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          AdminSection(
            title: l.languages,
            children: [
              Text(l.languagesIntro),
              for (final language in languages)
                Text('${language.name} (${language.code})'),
              Form(
                key: _languageForm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: VeloraSpacing.sm,
                  children: [
                    VeloraTextField(
                      label: l.languageCode,
                      helperText: l.languageCodeHelp,
                      controller: _code,
                      validator: (v) =>
                          RegExp(r'^[a-zA-Z]{2,3}$').hasMatch((v ?? '').trim())
                          ? null
                          : l.languageCodeInvalid,
                    ),
                    VeloraTextField(
                      label: l.languageName,
                      controller: _languageName,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? l.required : null,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: VeloraButton(
                        label: l.addLanguage,
                        icon: Icons.translate,
                        variant: VeloraButtonVariant.secondary,
                        isLoading: _busy,
                        onPressed: _addLanguage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
