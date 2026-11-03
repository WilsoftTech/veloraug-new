import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/dev_auth_proof.dart';
import '../widgets/dev_connection_check.dart';
import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenBody(
      heading: 'Account',
      children: [
        EmptyState(
          icon: Icons.person_off_outlined,
          title: "You're signed out",
          message:
              "Accounts aren't available yet, so there is no way to sign in. "
              'Sign-in will be added in a later step.',
        ),
        // kDebugMode is a constant, so release builds leave this code out.
        if (kDebugMode) _DevToolsHeading(),
        if (kDebugMode) DevConnectionCheck(),
        if (kDebugMode) DevAuthProof(),
      ],
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
