import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../auth/auth_controller.dart';
import '../../l10n/l10n.dart';
import '../../theme/palette.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/profile_section.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/velora_button.dart';
import '../devices_screen.dart';
import '../pass_screen.dart';

/// Who may open an account page.
enum AccountAccess {
  /// Anyone, signed in or not.
  anyone,

  /// Only someone signed in: the page shows their own data.
  signedIn,
}

/// A page of the account hub, with its own bar. It checks who may see it
/// every time it builds, so opening it directly, signing out or switching
/// account never shows one person's data to another: the body is rebuilt
/// from scratch for each account, and hidden while nobody is signed in.
class AccountPage extends StatelessWidget {
  const AccountPage({
    super.key,
    required this.title,
    required this.builder,
    this.access = AccountAccess.signedIn,
    this.androidOnly = false,
  });

  final String title;
  final AccountAccess access;

  /// For pages that exist only in the Android app, such as Downloads.
  final bool androidOnly;
  final WidgetBuilder builder;

  /// Opens a page on top of the current one.
  static Future<void> open(BuildContext context, AccountPage page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final auth = AuthScope.of(context);
    final Widget body;
    if (androidOnly && !isAndroidApp) {
      body = ScreenBody(
        heading: title,
        children: [
          EmptyState(
            icon: Icons.phone_android,
            title: l.androidOnlyTitle,
            message: l.androidOnlyMessage,
          ),
        ],
      );
    } else if (access == AccountAccess.signedIn) {
      body = switch (auth?.status) {
        null => ScreenBody(
          heading: title,
          children: [
            EmptyState(
              icon: Icons.person_off_outlined,
              title: l.signedOutTitle,
              message: l.signInNotSetUp,
            ),
          ],
        ),
        AuthStatus.restoring => ScreenBody(
          heading: title,
          children: [
            EmptyState(
              icon: Icons.hourglass_empty,
              title: l.checkingSignIn,
              message: l.takesAMoment,
            ),
          ],
        ),
        AuthStatus.signedIn => KeyedSubtree(
          // A different person gets a fresh page, which loads their data.
          key: ValueKey('account-${auth!.accountKey}'),
          child: Builder(builder: builder),
        ),
        _ => ScreenBody(
          heading: title,
          children: [SignInPrompt(message: l.signInToSeeThis)],
        ),
      };
    } else {
      body = Builder(builder: builder);
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(child: body),
    );
  }
}

/// True in the Android app. Tests can pretend otherwise.
bool get isAndroidApp =>
    debugAndroidAppOverride ??
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// Set in tests to choose which platform the account pages act as.
@visibleForTesting
bool? debugAndroidAppOverride;

/// Asks the person to sign in, with the button.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final auth = AuthScope.of(context);
    return EmptyState(
      icon: Icons.person_outline,
      title: l.signedOutTitle,
      message: message,
      action: auth == null
          ? null
          : VeloraButton(
              label: l.signIn,
              icon: Icons.login,
              isLoading: auth.status == AuthStatus.signingIn,
              loadingLabel: l.waitingForSignIn,
              onPressed: auth.isBusy ? null : auth.signIn,
            ),
    );
  }
}

/// A titled group of rows, such as "Membership".
class AccountGroup extends StatelessWidget {
  const AccountGroup({super.key, required this.title, required this.rows});

  final String title;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.xs,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: VeloraSpacing.xxs),
          child: Semantics(
            header: true,
            child: Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        Card.outlined(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0) const Divider(height: 1, indent: 56),
                row,
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// One row: an icon, a label, an optional line under it, and a chevron.
/// A row with no [onTap] shows as unavailable, with [subtitle] saying why.
class AccountRow extends StatelessWidget {
  const AccountRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.danger = false,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final palette = VeloraPalette.of(context);
    final color = danger ? palette.danger : null;
    final subtitle = this.subtitle;
    return ListTile(
      enabled: onTap != null || trailing != null,
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: color)),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing:
          trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
      onTap: onTap,
      minTileHeight: VeloraLayout.minTouchTarget + VeloraSpacing.xs,
    );
  }
}

// --- Pages built from the existing sections ----------------------------------

AccountPage profilePage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.profileTitle,
    builder: (context) {
      final auth = AuthScope.of(context)!;
      final email = auth.email;
      return ScreenBody(
        heading: l.profileTitle,
        children: [
          if (email != null)
            AccountCard(
              title: l.signInEmail,
              child: Text(email, style: Theme.of(context).textTheme.bodyLarge),
            ),
          ProfileSection(auth: auth),
        ],
      );
    },
  );
}

AccountPage plansPage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.plansTitle,
    builder: (context) => ScreenBody(
      heading: l.plansTitle,
      children: const [MembershipSection()],
    ),
  );
}

AccountPage paymentsPage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.payments,
    builder: (context) =>
        ScreenBody(heading: l.payments, children: const [PaymentsSection()]),
  );
}

AccountPage devicesPage(BuildContext context) {
  final l = context.l10n;
  return AccountPage(
    title: l.myDevices,
    builder: (context) =>
        ScreenBody(heading: l.myDevices, children: const [DevicesSection()]),
  );
}
