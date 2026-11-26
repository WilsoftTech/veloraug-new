import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/catalogue_api.dart';
import '../../config/public_links.dart';
import '../../l10n/l10n.dart';
import '../../notifications/push_status.dart';
import '../../security/app_lock.dart';
import '../../widgets/screen_body.dart';
import 'account_pages.dart';

/// Settings for this viewer on this device. Separate from the admin
/// screens' settings, which only admins see.
AccountPage settingsPage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.settingsTitle,
    access: AccountAccess.anyone,
    builder: (context) => const SettingsBody(),
  );
}

class SettingsBody extends StatelessWidget {
  const SettingsBody({super.key, this.links});

  /// This build's public links. Tests pass their own.
  final PublicLinks? links;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final links = this.links ?? PublicLinks.fromSettings();
    final lock = AppLockScope.of(context);
    final reset = links.reset;
    final privacy = links.privacyPolicy;
    final play = links.playStore;

    return ScreenBody(
      heading: l.settingsTitle,
      children: [
        AccountGroup(
          title: l.securityGroup,
          rows: [
            if (lock != null && lock.loaded && lock.supported)
              _AppLockRow(lock: lock),
            const _PushRow(),
            AccountRow(
              icon: Icons.password,
              title: l.passwordResetTitle,
              subtitle: reset == null
                  ? l.passwordResetUnavailable
                  : l.passwordResetHelp,
              onTap: reset == null ? null : () => _openLink(context, reset),
            ),
          ],
        ),
        AccountGroup(
          title: l.aboutGroup,
          rows: [
            _ShareRow(link: links.app),
            AccountRow(
              icon: Icons.star_outline,
              title: l.rateOnPlay,
              subtitle: play == null ? l.rateOnPlayUnavailable : null,
              onTap: play == null ? null : () => _openLink(context, play),
            ),
            AccountRow(
              icon: Icons.privacy_tip_outlined,
              title: l.privacyPolicy,
              subtitle: privacy == null ? l.privacyPolicyUnavailable : null,
              onTap: privacy == null ? null : () => _openLink(context, privacy),
            ),
          ],
        ),
        const _SupportGroup(),
      ],
    );
  }
}

/// How to get help: the contacts admins set in Settings. Shown only once
/// there are some.
class _SupportGroup extends StatefulWidget {
  const _SupportGroup();

  @override
  State<_SupportGroup> createState() => _SupportGroupState();
}

class _SupportGroupState extends State<_SupportGroup> {
  AppStatus? _status;
  bool _asked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_asked) return;
    _asked = true;
    CatalogueScope.of(context)?.status().then((status) {
      if (mounted) setState(() => _status = status);
    }, onError: (Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = _status;
    if (status == null || !status.hasSupport) return const SizedBox.shrink();
    return AccountGroup(
      title: l.supportGroup,
      rows: [
        if (status.supportWhatsapp.isNotEmpty)
          AccountRow(
            icon: Icons.chat_outlined,
            title: l.supportWhatsapp,
            subtitle: status.supportWhatsapp,
            onTap: () => _openLink(
              context,
              Uri.parse(
                'https://wa.me/${status.supportWhatsapp.replaceAll('+', '')}',
              ),
            ),
          ),
        if (status.supportPhone.isNotEmpty)
          AccountRow(
            icon: Icons.call_outlined,
            title: l.supportCall,
            subtitle: status.supportPhone,
            onTap: () => _openLink(
              context,
              Uri(scheme: 'tel', path: status.supportPhone),
            ),
          ),
        if (status.supportEmail.isNotEmpty)
          AccountRow(
            icon: Icons.mail_outline,
            title: l.supportEmail,
            subtitle: status.supportEmail,
            onTap: () => _openLink(
              context,
              Uri(scheme: 'mailto', path: status.supportEmail),
            ),
          ),
      ],
    );
  }
}

Future<void> _openLink(BuildContext context, Uri link) async {
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  bool opened;
  try {
    opened = await launchUrl(link, mode: LaunchMode.externalApplication);
  } on Exception {
    opened = false;
  }
  if (!context.mounted) return;
  if (!opened) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.linkCouldNotOpen)));
  }
}

/// App lock's switch. Turning it either way asks for the phone's own
/// authentication first.
class _AppLockRow extends StatefulWidget {
  const _AppLockRow({required this.lock});

  final AppLockController lock;

  @override
  State<_AppLockRow> createState() => _AppLockRowState();
}

class _AppLockRowState extends State<_AppLockRow> {
  String? _message;

  Future<void> _toggle(bool on) async {
    final l = context.l10n;
    final result = await widget.lock.setEnabled(
      on,
      on ? l.appLockReasonTurnOn : l.appLockReasonTurnOff,
    );
    if (!mounted) return;
    setState(
      () => _message = switch (result) {
        LockCheck.passed => null,
        LockCheck.cancelled => l.appLockNotChanged,
        LockCheck.lockedOut => l.appLockLockedOut,
        LockCheck.unavailable => l.appLockUnavailable,
        LockCheck.failed => l.appLockFailed,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final lock = widget.lock;
    final subtitle = [
      lock.supported ? l.appLockHelp : l.appLockUnavailable,
      ?_message,
    ].join('\n');
    return Semantics(
      liveRegion: _message != null,
      child: SwitchListTile(
        secondary: const Icon(Icons.fingerprint),
        title: Text(l.appLockTitle),
        subtitle: Text(subtitle),
        value: lock.enabled,
        onChanged: !lock.supported || lock.checking ? null : _toggle,
      ),
    );
  }
}

/// Push notifications: what Android allows, and whether VeloraUG can send
/// them yet. Until a push service is set up the switch stays off and says
/// why, so it never seems to work when it can't.
class _PushRow extends StatefulWidget {
  const _PushRow();

  @override
  State<_PushRow> createState() => _PushRowState();
}

class _PushRowState extends State<_PushRow> with WidgetsBindingObserver {
  PushStatus? _status;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The person may have changed it in Android's settings meanwhile.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    final status = await readPushStatus();
    if (mounted) setState(() => _status = status);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = _status;
    // One line: push can't deliver anything yet, so what Android allows
    // doesn't matter today. The inbox works either way.
    final line = switch (status?.availability) {
      PushAvailability.notOnThisPlatform => l.pushNotOnWeb,
      PushAvailability.notSetUp || null => l.pushComingSoon,
    };
    return SwitchListTile(
      secondary: const Icon(Icons.notifications_active_outlined),
      title: Text(l.pushTitle),
      subtitle: Text(line),
      // Off and disabled: no push service can deliver anything yet.
      value: false,
      onChanged: null,
    );
  }
}

/// Shares the app's public address with the platform's share sheet, or
/// copies it where there is none.
class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.link});

  final Uri? link;

  Future<void> _share(BuildContext context, Uri link) async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final box = context.findRenderObject() as RenderBox?;
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          text: l.shareAppText(link.toString()),
          subject: l.appName,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
      if (result.status != ShareResultStatus.unavailable) return;
    } on Object {
      // No share sheet here: copy instead.
    }
    await Clipboard.setData(ClipboardData(text: link.toString()));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l.shareAppCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final link = this.link;
    return AccountRow(
      icon: Icons.share_outlined,
      title: l.shareApp,
      subtitle: link == null ? l.shareAppUnavailable : link.host,
      onTap: link == null ? null : () => _share(context, link),
      trailing: link == null
          ? null
          : IconButton(
              tooltip: l.copyLink,
              icon: const Icon(Icons.copy),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: link.toString()));
                messenger
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(l.shareAppCopied)));
              },
            ),
    );
  }
}
