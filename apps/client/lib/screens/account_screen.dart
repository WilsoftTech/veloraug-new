import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../widgets/dev_connection_check.dart';
import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return ScreenBody(
      heading: 'Account',
      children: [
        if (auth == null) const _NotConfigured() else _AccountPanel(auth),
        // kDebugMode is a constant, so release builds leave this code out.
        if (kDebugMode) const _DevToolsHeading(),
        if (kDebugMode) const DevConnectionCheck(),
      ],
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.person_off_outlined,
      title: "You're signed out",
      message: "Sign-in isn't set up in this version of the app.",
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel(this.auth);

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final notice = auth.notice;
    final panel = switch (auth.status) {
      AuthStatus.restoring => const EmptyState(
        icon: Icons.hourglass_empty,
        title: 'Checking your sign-in',
        message: 'This takes a moment.',
      ),
      AuthStatus.signedOut || AuthStatus.signingIn => EmptyState(
        icon: Icons.person_outline,
        title: "You're signed out",
        message:
            'Sign in, or create an account, on the VeloraUG sign-in page. '
            'It opens in your browser.',
        action: VeloraButton(
          label: 'Sign in',
          icon: Icons.login,
          isLoading: auth.status == AuthStatus.signingIn,
          loadingLabel: 'Waiting for the sign-in page…',
          onPressed: auth.signIn,
        ),
      ),
      AuthStatus.signedIn || AuthStatus.signingOut => EmptyState(
        icon: Icons.person,
        title: "You're signed in",
        message: switch (auth.email) {
          final email? => 'Signed in as $email.',
          null => 'Your account is signed in on this device.',
        },
        action: VeloraButton(
          label: 'Sign out',
          icon: Icons.logout,
          variant: VeloraButtonVariant.secondary,
          isLoading: auth.status == AuthStatus.signingOut,
          loadingLabel: 'Signing out…',
          onPressed: auth.signOut,
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) _Notice(notice, isError: auth.noticeIsError),
        panel,
      ],
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
    return Padding(
      padding: const EdgeInsets.only(bottom: VeloraSpacing.md),
      child: Semantics(
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
