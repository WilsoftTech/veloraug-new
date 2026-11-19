import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_messages.dart';
import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../widgets/dev_connection_check.dart';
import '../widgets/dev_token_checks.dart';
import '../widgets/empty_state.dart';
import '../widgets/profile_section.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../l10n/l10n.dart';
import 'pass_screen.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context);
    return ScreenBody(
      heading: context.l10n.account,
      children: [
        if (auth == null) const _NotConfigured() else _AccountPanel(auth),
        const AboutSection(),
        // kDebugMode is a constant, so release builds leave this code out.
        if (kDebugMode) const _DevToolsHeading(),
        if (kDebugMode) const DevConnectionCheck(),
        if (kDebugMode) DevTokenChecks(auth: auth),
      ],
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.person_off_outlined,
      title: context.l10n.signedOutTitle,
      message: context.l10n.signInNotSetUp,
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel(this.auth);

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final notice = auth.notice;
    final panel = switch (auth.status) {
      AuthStatus.restoring => EmptyState(
        icon: Icons.hourglass_empty,
        title: l.checkingSignIn,
        message: l.takesAMoment,
      ),
      AuthStatus.signedOut || AuthStatus.signingIn => EmptyState(
        icon: Icons.person_outline,
        title: l.signedOutTitle,
        message: l.signInExplained,
        action: VeloraButton(
          label: l.signIn,
          icon: Icons.login,
          isLoading: auth.status == AuthStatus.signingIn,
          loadingLabel: l.waitingForSignIn,
          onPressed: auth.signIn,
        ),
      ),
      AuthStatus.signedIn || AuthStatus.signingOut => EmptyState(
        icon: Icons.person,
        title: l.signedInTitle,
        message: switch (auth.email) {
          final email? => l.signedInAs(email),
          null => l.signedInOnDevice,
        },
        action: VeloraButton(
          label: l.signOut,
          icon: Icons.logout,
          variant: VeloraButtonVariant.secondary,
          isLoading: auth.status == AuthStatus.signingOut,
          loadingLabel: l.signingOut,
          onPressed: auth.signOut,
        ),
      ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null)
          _Notice(authNoticeMessage(l, notice), isError: notice.isError),
        panel,
        if (auth.status == AuthStatus.signedIn) ...[
          const SizedBox(height: VeloraSpacing.md),
          // Step 10C. A new person gets a fresh section, which loads theirs.
          PassSection(key: ValueKey('pass-${auth.email}')),
          const SizedBox(height: VeloraSpacing.md),
          // A new person gets a fresh section, which loads their profile.
          ProfileSection(key: ValueKey(auth.email), auth: auth),
        ],
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

/// TMDB's approved short logo, from themoviedb.org/about/logos-attribution,
/// drawn from its SVG to a PNG at 820 × 107 so no SVG package is needed.
const String tmdbLogoAsset = 'assets/brand/tmdb_logo.png';

/// Credits. TMDB's terms ask for its notice in an "About" or "Credits"
/// section, less prominent than VeloraUG's own brand, in every build.
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(top: VeloraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: VeloraSpacing.xs,
        children: [
          Semantics(
            header: true,
            child: Text(l.about, style: theme.textTheme.titleLarge),
          ),
          Text(l.aboutTmdb, style: theme.textTheme.bodyMedium),
          // Small, so it stays less prominent than VeloraUG's own brand.
          Image.asset(tmdbLogoAsset, height: 16, semanticLabel: l.tmdbLogo),
          Text(
            // The wording TMDB's terms and FAQ ask for, word for word.
            l.tmdbNotice,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
