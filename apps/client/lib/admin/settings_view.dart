import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/maintenance_banner.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';
import 'uploads/upload_platform.dart' as platform;

/// The admin tabs' places, for "Plans and pricing" to open Subscriptions.
const int subscriptionsTab = 4;

/// One part of Settings, and the settings it holds.
enum SettingsPart {
  support(['support_email', 'support_phone', 'support_whatsapp']),
  maintenance(['maintenance', 'maintenance_message']),
  payments(['payment_timeout_minutes']),
  viewers(['pass_reminder_days']),
  content(['default_language']),
  plans([]),
  admins([]),
  languages([]),
  about([]);

  const SettingsPart(this.keys);

  final List<String> keys;
}

/// Admin → Settings: support contacts, maintenance, payments, viewers'
/// reminders and content defaults, saved together; then plans, admins,
/// languages and what the server is set up with.
///
/// Edits are kept while the admin visits other tabs, a bar offers Save
/// while any is unsaved, and the browser asks before the page is closed.
/// Each part can undo its changes, or go back to its defaults.
class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView>
    with AutomaticKeepAliveClientMixin {
  AdminSettings? _saved;
  final Map<String, Object?> _draft = {};
  Map<String, String> _errors = const {};
  List<AdminEntry>? _admins;
  List<AdminLanguage>? _languages;
  AdminException? _failure;
  bool _started = false;
  bool _busy = false;
  bool _saving = false;
  bool _warning = false;

  /// Why the last Save didn't go through, shown in the save bar, where a
  /// snack bar would cover it.
  String? _saveProblem;

  final _text = {
    for (final key in [
      'support_email',
      'support_phone',
      'support_whatsapp',
      'maintenance_message',
      'payment_timeout_minutes',
      'pass_reminder_days',
    ])
      key: TextEditingController(),
  };
  final _parts = {for (final part in SettingsPart.values) part: GlobalKey()};

  final _email = TextEditingController();
  final _code = TextEditingController();
  final _languageName = TextEditingController();
  final _adminForm = GlobalKey<FormState>();
  final _languageForm = GlobalKey<FormState>();

  static const _numbers = {'payment_timeout_minutes', 'pass_reminder_days'};

  @override
  bool get wantKeepAlive => true;

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
    platform.warnBeforeLeaving(false, reason: 'settings');
    for (final c in [..._text.values, _email, _code, _languageName]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final settings = await api.settings();
      final admins = await api.admins();
      final languages = await api.languages();
      if (!mounted) return;
      setState(() {
        _saved = settings;
        _admins = admins;
        _languages = languages;
        _failure = null;
        _errors = const {};
        _draft
          ..clear()
          ..addAll(settings.values);
        _fillText();
      });
      _warn();
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  /// The text boxes show the draft's values.
  void _fillText() {
    for (final MapEntry(:key, value: controller) in _text.entries) {
      final value = _draft[key];
      controller.text = value == null ? '' : '$value';
    }
  }

  // --- Changes -----------------------------------------------------------

  /// What a text box's text means: an int for numbers, null when empty.
  Object? _parse(String key, String text) {
    final trimmed = text.trim();
    if (_numbers.contains(key)) {
      return trimmed.isEmpty ? null : (int.tryParse(trimmed) ?? trimmed);
    }
    return trimmed;
  }

  void _set(String key, Object? value) {
    setState(() {
      _draft[key] = value;
      _errors = {..._errors}..remove(key);
      if (_errors.isEmpty) _saveProblem = null;
    });
    _warn();
  }

  bool _changed(String key) => _draft[key] != _saved?.values[key];

  bool _partChanged(SettingsPart part) => part.keys.any(_changed);

  bool get _dirty => SettingsPart.values.any(_partChanged);

  /// The browser asks before the page closes while anything is unsaved.
  void _warn() {
    final dirty = _dirty;
    if (dirty == _warning) return;
    _warning = dirty;
    platform.warnBeforeLeaving(dirty, reason: 'settings');
  }

  void _undo(SettingsPart part) {
    final saved = _saved;
    if (saved == null) return;
    setState(() {
      for (final key in part.keys) {
        _draft[key] = saved.values[key];
        _errors = {..._errors}..remove(key);
      }
      _fillText();
    });
    _warn();
  }

  void _useDefaults(SettingsPart part) {
    final saved = _saved;
    if (saved == null) return;
    setState(() {
      for (final key in part.keys) {
        // The timeout's default is the server's: stored as no value.
        _draft[key] = key == 'payment_timeout_minutes'
            ? null
            : saved.defaults[key];
      }
      _fillText();
    });
    _warn();
  }

  bool _atDefaults(SettingsPart part) => part.keys.every(
    (key) =>
        _draft[key] ==
        (key == 'payment_timeout_minutes' ? null : _saved?.defaults[key]),
  );

  /// Checks what can be checked here. The server checks everything again.
  Map<String, String> _check(AppLocalizations l) {
    final errors = <String, String>{};
    final email = _draft['support_email'];
    if (email is String && email.isNotEmpty && !email.contains('@')) {
      errors['support_email'] = l.enterEmail;
    }
    for (final key in ['support_phone', 'support_whatsapp']) {
      final phone = _draft[key];
      if (phone is String &&
          phone.isNotEmpty &&
          !RegExp(r'^\+[0-9 -]{9,20}$').hasMatch(phone)) {
        errors[key] = l.settingPhoneInvalid;
      }
    }
    final message = _draft['maintenance_message'];
    if (message is String && message.length > 300) {
      errors['maintenance_message'] = l.tooLong(300);
    }
    for (final (key, low, high) in [
      ('payment_timeout_minutes', 5, 1440),
      ('pass_reminder_days', 1, 14),
    ]) {
      final value = _draft[key];
      if (value == null && key == 'payment_timeout_minutes') continue;
      if (value is! int || value < low || value > high) {
        errors[key] = l.numberBetween(low, high);
      }
    }
    return errors;
  }

  Future<void> _save() async {
    final l = context.l10n;
    final errors = _check(l);
    if (errors.isNotEmpty) {
      setState(() {
        _errors = errors;
        _saveProblem = l.settingsFixFirst;
      });
      return;
    }
    final api = AdminScope.of(context);
    if (api == null) return;
    final changes = {
      for (final part in SettingsPart.values)
        for (final key in part.keys)
          if (_changed(key)) key: _draft[key],
    };
    setState(() {
      _saving = true;
      _saveProblem = null;
    });
    try {
      final saved = await api.saveSettings(changes);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = saved;
        _errors = const {};
        _draft
          ..clear()
          ..addAll(saved.values);
        _fillText();
      });
      _warn();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.settingsSaved(changes.length))));
    } on AdminException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _errors = error.fieldErrors;
        _saveProblem = error.fieldErrors.isEmpty
            ? adminFailureMessage(l, error)
            : l.settingsFixFirst;
      });
    }
  }

  void _discard() {
    for (final part in SettingsPart.values) {
      _undo(part);
    }
  }

  void _jump(SettingsPart part) {
    final target = _parts[part]!.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        duration: VeloraMotion.of(context, VeloraMotion.standard),
      );
    }
  }

  // --- Admins and languages, saved at once as before ---------------------

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
    if (ok != true) return;
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final admins = await api.admins();
      final languages = await api.languages();
      if (mounted) {
        setState(() {
          _admins = admins;
          _languages = languages;
        });
      }
    } on AdminException {
      // Shown as they were; Refresh tries again.
    }
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
      danger: true,
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

  // --- The page -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l10n;
    final failure = _failure;
    final saved = _saved;
    final admins = _admins;
    final languages = _languages;
    if (failure != null) {
      return ScreenBody(
        heading: l.adminSettings,
        children: [
          ErrorState(
            title: l.adminLoadFailed,
            message: adminFailureMessage(l, failure),
            onRetry: _load,
          ),
        ],
      );
    }
    if (saved == null || admins == null || languages == null) {
      return ScreenBody(
        heading: l.adminSettings,
        children: [
          Center(
            child: VeloraLoadingRegion(
              label: l.loading,
              child: const VeloraSpinner(size: 32),
            ),
          ),
        ],
      );
    }
    final dirty = _dirty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ScreenBody(
            heading: l.adminSettings,
            intro: l.adminSettingsIntro,
            maxWidth: VeloraLayout.readingWidth,
            children: [
              Wrap(
                spacing: VeloraSpacing.xs,
                runSpacing: VeloraSpacing.xs,
                children: [
                  for (final part in SettingsPart.values)
                    ActionChip(
                      avatar: _partChanged(part)
                          ? const Icon(Icons.edit, size: 16)
                          : null,
                      label: Text(_title(l, part)),
                      onPressed: () => _jump(part),
                    ),
                ],
              ),
              _part(l, SettingsPart.support, [
                Text(l.settingsSupportIntro),
                _field(
                  l,
                  'support_email',
                  l.settingSupportEmail,
                  keyboard: TextInputType.emailAddress,
                ),
                _field(
                  l,
                  'support_phone',
                  l.settingSupportPhone,
                  keyboard: TextInputType.phone,
                  hint: '+256 7…',
                ),
                _field(
                  l,
                  'support_whatsapp',
                  l.settingSupportWhatsapp,
                  keyboard: TextInputType.phone,
                  hint: '+256 7…',
                ),
              ]),
              _part(l, SettingsPart.maintenance, [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.settingMaintenance),
                  subtitle: Text(l.settingMaintenanceHelp),
                  value: _draft['maintenance'] == true,
                  onChanged: (on) => _set('maintenance', on),
                ),
                _field(
                  l,
                  'maintenance_message',
                  l.settingMaintenanceMessage,
                  helper: l.settingMaintenanceMessageHelp,
                  lines: 3,
                ),
                if (_draft['maintenance'] == true)
                  _MaintenancePreview(
                    message: (_draft['maintenance_message'] as String?) ?? '',
                  ),
              ]),
              _part(l, SettingsPart.payments, [
                _Fact(
                  l.settingProvider,
                  saved.server.pesapalConfigured
                      ? l.settingPesapalMode(
                          saved.server.pesapalEnvironment == 'live'
                              ? l.settingLive
                              : l.settingSandbox,
                        )
                      : l.settingNotSetUp,
                  tone: saved.server.pesapalConfigured
                      ? (saved.server.pesapalEnvironment == 'live'
                            ? StatusTone.success
                            : StatusTone.warning)
                      : StatusTone.danger,
                ),
                Text(l.settingProviderHelp),
                _field(
                  l,
                  'payment_timeout_minutes',
                  l.settingTimeout,
                  helper: l.settingTimeoutHelp(
                    saved.server.serverTimeoutMinutes,
                  ),
                  keyboard: TextInputType.number,
                ),
              ]),
              _part(l, SettingsPart.viewers, [
                _field(
                  l,
                  'pass_reminder_days',
                  l.settingReminderDays,
                  helper: l.settingReminderDaysHelp,
                  keyboard: TextInputType.number,
                ),
              ]),
              _part(l, SettingsPart.content, [
                DropdownButtonFormField<String>(
                  initialValue:
                      languages.any((x) => x.code == _draft['default_language'])
                      ? _draft['default_language'] as String?
                      : null,
                  key: ValueKey('language-${_draft['default_language']}'),
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l.settingDefaultLanguage,
                    helperText: l.settingDefaultLanguageHelp,
                    helperMaxLines: 2,
                    errorText: _errors['default_language'],
                  ),
                  items: [
                    for (final language in languages)
                      DropdownMenuItem(
                        value: language.code,
                        child: Text(language.name),
                      ),
                  ],
                  onChanged: (code) => _set('default_language', code),
                ),
                _Fact(
                  l.settingVideoLimit,
                  l.settingVideoLimitValue(saved.server.videoLimitGb),
                ),
                _Fact(
                  l.settingImageLimit,
                  l.settingImageLimitValue(saved.server.imageLimitMb),
                ),
                _Fact(l.settingQualities, saved.server.qualities.join(', ')),
                Text(l.settingServerFixedHelp),
              ]),
              _part(l, SettingsPart.plans, [
                Text(l.settingPlansHelp),
                Align(
                  alignment: Alignment.centerLeft,
                  child: VeloraButton(
                    label: l.openSubscriptions,
                    icon: Icons.sell_outlined,
                    variant: VeloraButtonVariant.secondary,
                    onPressed: () =>
                        DefaultTabController.maybeOf(context)
                            ?.animateTo(subscriptionsTab),
                  ),
                ),
              ]),
              _part(l, SettingsPart.admins, [
                Text(l.adminsIntro),
                Text(l.adminRolesNote),
                for (final admin in admins) _adminTile(l, admin, admins),
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
              ]),
              _part(l, SettingsPart.languages, [
                Text(l.languagesIntro),
                Wrap(
                  spacing: VeloraSpacing.xs,
                  runSpacing: VeloraSpacing.xs,
                  children: [
                    for (final language in languages)
                      Chip(label: Text('${language.name} (${language.code})')),
                  ],
                ),
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
                            RegExp(r'^[a-zA-Z]{2,3}$')
                                .hasMatch((v ?? '').trim())
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
              ]),
              _part(l, SettingsPart.about, [
                _Fact(l.aboutEnvironment, saved.server.environment),
                _Fact(l.aboutApiVersion, saved.server.apiVersion),
                _Fact(
                  l.aboutSchemaVersion,
                  saved.server.schemaVersion ?? l.aboutUnknown,
                ),
                _Fact(
                  l.aboutTmdb2,
                  saved.server.tmdbConfigured ? l.aboutOn : l.aboutOff,
                  tone: saved.server.tmdbConfigured
                      ? StatusTone.success
                      : StatusTone.warning,
                ),
                _Fact(
                  l.aboutPlayback,
                  saved.server.playbackConfigured ? l.aboutOn : l.aboutOff,
                  tone: saved.server.playbackConfigured
                      ? StatusTone.success
                      : StatusTone.warning,
                ),
              ]),
            ],
          ),
        ),
        if (dirty)
          _SaveBar(
            problem: _saveProblem,
            saving: _saving,
            changedParts: SettingsPart.values.where(_partChanged).length,
            onSave: _save,
            onDiscard: _discard,
          ),
      ],
    );
  }

  String _title(AppLocalizations l, SettingsPart part) => switch (part) {
    SettingsPart.support => l.settingsSupport,
    SettingsPart.maintenance => l.settingsMaintenance,
    SettingsPart.payments => l.settingsPayments,
    SettingsPart.viewers => l.settingsViewers,
    SettingsPart.content => l.settingsContent,
    SettingsPart.plans => l.settingsPlans,
    SettingsPart.admins => l.admins,
    SettingsPart.languages => l.languages,
    SettingsPart.about => l.settingsAbout,
  };

  Widget _part(AppLocalizations l, SettingsPart part, List<Widget> children) {
    final changed = _partChanged(part);
    final editable = part.keys.isNotEmpty;
    return KeyedSubtree(
      key: _parts[part],
      child: AdminSection(
        title: _title(l, part),
        status: changed
            ? StatusBadge(label: l.settingsUnsaved, tone: StatusTone.warning)
            : null,
        children: [
          ...children,
          if (editable && (changed || !_atDefaults(part)))
            Wrap(
              spacing: VeloraSpacing.sm,
              children: [
                if (changed)
                  TextButton.icon(
                    icon: const Icon(Icons.undo),
                    label: Text(l.settingsUndo),
                    onPressed: () => _undo(part),
                  ),
                if (!_atDefaults(part))
                  TextButton.icon(
                    icon: const Icon(Icons.restart_alt),
                    label: Text(l.settingsUseDefaults),
                    onPressed: () => _useDefaults(part),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _field(
    AppLocalizations l,
    String key,
    String label, {
    String? helper,
    String? hint,
    TextInputType? keyboard,
    int lines = 1,
  }) {
    return TextField(
      controller: _text[key],
      keyboardType: keyboard,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        hintText: hint,
        errorText: _errors[key],
        errorMaxLines: 3,
      ),
      onChanged: (text) => _set(key, _parse(key, text)),
    );
  }

  Widget _adminTile(
    AppLocalizations l,
    AdminEntry admin,
    List<AdminEntry> admins,
  ) {
    final dates = MaterialLocalizations.of(context);
    return Card.outlined(
      key: ValueKey(admin.userId),
      margin: EdgeInsets.zero,
      // Remove sits under the details, so a narrow phone has room.
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.xxs,
          children: [
            Text(
              admin.email ?? admin.userId,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Text(
              admin.addedByEmail == null
                  ? l.addedOn(dates.formatMediumDate(admin.addedAt.toLocal()))
                  : l.addedByOn(
                      admin.addedByEmail!,
                      dates.formatMediumDate(admin.addedAt.toLocal()),
                    ),
            ),
            if (admins.length > 1)
              TextButton(
                onPressed: _busy ? null : () => _removeAdmin(admin),
                child: Text(l.remove),
              )
            else
              Text(l.lastAdmin, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// One thing the server is set up with, read only.
class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value, {this.tone});

  final String label;
  final String value;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = this.tone;
    return Wrap(
      spacing: VeloraSpacing.sm,
      runSpacing: VeloraSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(label, style: theme.textTheme.bodySmall),
        if (tone == null)
          Text(value, style: theme.textTheme.bodyLarge)
        else
          StatusBadge(label: value, tone: tone),
      ],
    );
  }
}

/// How the app will look to viewers while maintenance is on.
class _MaintenancePreview extends StatelessWidget {
  const _MaintenancePreview({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.xxs,
      children: [
        Text(
          l.settingMaintenancePreview,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        MaintenanceBanner(message: message),
      ],
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.problem,
    required this.saving,
    required this.changedParts,
    required this.onSave,
    required this.onDiscard,
  });

  final String? problem;
  final bool saving;
  final int changedParts;
  final VoidCallback onSave;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Material(
      color: VeloraColors.surfaceRaised,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VeloraSpacing.md,
            vertical: VeloraSpacing.sm,
          ),
          child: Wrap(
            spacing: VeloraSpacing.sm,
            runSpacing: VeloraSpacing.xs,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (problem case final text?)
                Text(
                  text,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                )
              else
                Text(l.settingsUnsavedParts(changedParts)),
              VeloraButton(
                label: l.settingsDiscard,
                variant: VeloraButtonVariant.tertiary,
                onPressed: saving ? null : onDiscard,
              ),
              VeloraButton(
                label: l.settingsSave,
                icon: Icons.check,
                isLoading: saving,
                onPressed: onSave,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
