import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/account_api.dart';
import '../api/pass_api.dart';
import '../api/playback_api.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_messages.dart';
import '../downloads/downloads.dart';
import '../l10n/l10n.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../widgets/dev_connection_check.dart';
import '../widgets/dev_token_checks.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/startup_gate.dart';
import '../widgets/velora_button.dart';
import 'account/account_pages.dart';
import 'account/danger_zone_screen.dart';
import 'account/history_screen.dart';
import 'account/notifications_screen.dart';
import 'account/settings_screen.dart';
import 'account/watch_list_screen.dart';
import 'downloads_screen.dart';
import 'pass_screen.dart' show timeLeft;

/// The account hub: who is signed in, then grouped rows that open a page
/// each, with the plan and unread notifications at a glance. Signed out,
/// only what needs no account shows, with a way to sign in. Sign out is at
/// the foot.
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  /// Whose glance this is: a different account starts again.
  String? _loadedFor;
  PassStatus? _pass;
  int? _unread;
  String? _displayName;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AuthScope.of(context);
    final key = auth?.status == AuthStatus.signedIn ? auth?.accountKey : null;
    if (key != _loadedFor) {
      _loadedFor = key;
      _pass = null;
      _unread = null;
      _displayName = null;
      if (key != null) _glance(key);
    }
  }

  /// The plan, unread notifications and display name. Each is only a
  /// glance: one that fails is left out, and the rows say what they always
  /// said.
  Future<void> _glance(String key) async {
    final playback = PlaybackScope.of(context);
    final account = accountApiOf(context);
    bool current() => mounted && _loadedFor == key;
    await Future.wait([
      if (playback != null)
        playback.myPass().then((pass) {
          if (current()) setState(() => _pass = pass);
        }, onError: (Object _) {}),
      if (account != null) ...[
        account.notifications().then((inbox) {
          if (current()) setState(() => _unread = inbox.unread);
        }, onError: (Object _) {}),
        account.displayName().then((name) {
          if (current()) setState(() => _displayName = name);
        }, onError: (Object _) {}),
      ],
    ]);
  }

  /// Opens a page, then refreshes the glance: the viewer may have bought a
  /// plan or read their notifications there.
  Future<void> _open(AccountPage Function(BuildContext) page) async {
    await AccountPage.open(context, page(context));
    if (!mounted) return;
    if (_loadedFor case final key?) await _glance(key);
  }

  /// "Velora Prime · 24 days left", "No plan · Choose a plan", or the usual
  /// help while it loads or if it failed.
  String _planLine(AppLocalizations l) {
    final pass = _pass;
    final current = pass?.current;
    if (pass == null) return l.plansRowHelp;
    if (!pass.active || current == null) return l.hubNoPlan;
    final left = current.endsAt.difference(DateTime.now().toUtc());
    return '${current.planName} · '
        '${timeLeft(l, left.isNegative ? Duration.zero : left)}';
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final auth = AuthScope.of(context);
    final signedIn = auth?.status == AuthStatus.signedIn;
    final hasPlayback = PlaybackScope.of(context) != null;
    final downloads = DownloadsScope.of(context);
    final hasDownloads = downloads != null && downloads.followed;
    final unread = _unread ?? 0;

    return ScreenBody(
      heading: l.account,
      children: [
        _Identity(auth: auth, displayName: _displayName),
        if (signedIn && hasPlayback)
          AccountGroup(
            title: l.membershipGroup,
            rows: [
              AccountRow(
                key: const ValueKey('row-plans'),
                icon: Icons.workspace_premium_outlined,
                title: l.plansTitle,
                subtitle: _planLine(l),
                onTap: () => _open(plansPage),
              ),
              AccountRow(
                icon: Icons.receipt_long_outlined,
                title: l.payments,
                onTap: () => _open(paymentsPage),
              ),
              AccountRow(
                icon: Icons.devices_outlined,
                title: l.myDevices,
                subtitle: l.myDevicesRowHelp,
                onTap: () => _open(devicesPage),
              ),
            ],
          ),
        if (hasDownloads || (signedIn && hasPlayback))
          AccountGroup(
            title: l.libraryGroup,
            rows: [
              if (hasDownloads)
                AccountRow(
                  icon: Icons.download_for_offline_outlined,
                  title: l.downloads,
                  subtitle: l.downloadsRowHelp,
                  onTap: () => DownloadsScreen.open(context),
                ),
              if (signedIn && hasPlayback) ...[
                AccountRow(
                  icon: Icons.bookmark_border,
                  title: l.watchListTitle,
                  onTap: () => _open(watchListPage),
                ),
                AccountRow(
                  icon: Icons.history,
                  title: l.historyTitle,
                  onTap: () => _open(historyPage),
                ),
                AccountRow(
                  key: const ValueKey('row-notifications'),
                  icon: Icons.notifications_none,
                  title: l.notificationsTitle,
                  badge: unread > 0 ? l.notificationsNew(unread) : null,
                  onTap: () => _open(notificationsPage),
                ),
              ],
            ],
          ),
        AccountGroup(
          title: l.accountGroup,
          rows: [
            if (signedIn)
              AccountRow(
                icon: Icons.badge_outlined,
                title: l.profileTitle,
                onTap: () => _open(profilePage),
              ),
            AccountRow(
              icon: Icons.settings_outlined,
              title: l.settingsTitle,
              onTap: () => _open(settingsPage),
            ),
            if (signedIn && hasPlayback)
              AccountRow(
                icon: Icons.delete_forever_outlined,
                title: l.dangerZoneTitle,
                danger: true,
                onTap: () => _open(dangerZonePage),
              ),
          ],
        ),
        if (auth != null &&
            (auth.status == AuthStatus.signedIn ||
                auth.status == AuthStatus.signingOut))
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: VeloraButton(
              label: l.signOut,
              icon: Icons.logout,
              variant: VeloraButtonVariant.secondary,
              isLoading: auth.status == AuthStatus.signingOut,
              loadingLabel: l.signingOut,
              onPressed: auth.signOut,
            ),
          ),
        // kDebugMode is a constant, so release builds leave this code out.
        if (kDebugMode) const _DevToolsHeading(),
        if (kDebugMode) const DevConnectionCheck(),
        if (kDebugMode) DevTokenChecks(auth: auth),
      ],
    );
  }
}

/// Who is signed in, by display name with the email under it, or a way to
/// sign in, and the last sign-in outcome.
class _Identity extends StatelessWidget {
  const _Identity({required this.auth, this.displayName});

  final AuthController? auth;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final auth = this.auth;
    final notice = auth?.notice;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final Widget avatar;
    final String title;
    final String message;
    Widget? action;
    switch (auth?.status) {
      case null:
        avatar = const _Avatar(icon: Icons.person_off_outlined);
        title = l.signedOutTitle;
        message = l.signInNotSetUp;
      case AuthStatus.restoring:
        avatar = const SizedBox.square(
          dimension: VeloraLayout.avatarSize,
          child: BrandRing(strokeWidth: VeloraStroke.focus),
        );
        title = l.checkingSignIn;
        message = l.takesAMoment;
      case AuthStatus.signedOut || AuthStatus.signingIn:
        avatar = const _Avatar(icon: Icons.person_outline);
        title = l.signedOutTitle;
        message = l.signInExplained;
        action = VeloraButton(
          label: l.signIn,
          icon: Icons.login,
          isLoading: auth!.status == AuthStatus.signingIn,
          loadingLabel: l.waitingForSignIn,
          onPressed: auth.signIn,
        );
      case AuthStatus.signedIn || AuthStatus.signingOut:
        final email = auth!.email;
        final name = displayName;
        avatar = _Avatar(
          letter: (name ?? email)?.characters.first.toUpperCase(),
        );
        (title, message) = switch ((name, email)) {
          (final String name, final String email) => (name, email),
          (final String name, null) => (name, l.signedInOnDevice),
          (null, final String email) => (email, l.signedInTitle),
          (null, null) => (l.signedInTitle, l.signedInOnDevice),
        };
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.md,
      children: [
        if (notice != null)
          _Notice(authNoticeMessage(l, notice), isError: notice.isError),
        Card.outlined(
          child: Padding(
            padding: const EdgeInsets.all(VeloraSpacing.md),
            child: Wrap(
              spacing: VeloraSpacing.md,
              runSpacing: VeloraSpacing.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: VeloraSpacing.md,
                  children: [
                    avatar,
                    Flexible(
                      child: Semantics(
                        liveRegion: true,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: theme.textTheme.titleMedium),
                            Text(message, style: muted),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                ?action,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({this.letter, this.icon = Icons.person});

  final String? letter;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final letter = this.letter;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: VeloraLayout.avatarSize / 2,
        backgroundColor: VeloraColors.infoContainer,
        foregroundColor: VeloraColors.textPrimary,
        child: letter == null
            ? Icon(icon)
            : Text(letter, style: Theme.of(context).textTheme.titleLarge),
      ),
    );
  }
}

/// The last sign-in or sign-out outcome, announced to screen readers.
class _Notice extends StatelessWidget {
  const _Notice(this.message, {required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final palette = VeloraPalette.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isError ? palette.dangerContainer : palette.infoContainer,
          borderRadius: BorderRadius.circular(VeloraRadii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isError ? Icons.error_outline : Icons.info_outline,
                color: isError ? palette.danger : null,
              ),
              const SizedBox(width: VeloraSpacing.xs),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Separates the debug-only tools from what people will see in the product.
class _DevToolsHeading extends StatelessWidget {
  const _DevToolsHeading();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: VeloraSpacing.md),
      child: Wrap(
        spacing: VeloraSpacing.sm,
        runSpacing: VeloraSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            header: true,
            child: Text(
              // Debug builds only, so not translated.
              'Development tools',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const StatusBadge(
            label: 'Debug builds only',
            tone: StatusTone.warning,
          ),
        ],
      ),
    );
  }
}
