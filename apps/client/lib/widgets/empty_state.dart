import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'velora_button.dart';

/// Explains why a screen has nothing to show yet.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;

  /// An optional next step, such as a [VeloraButton].
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _StatePanel(
      icon: icon,
      iconColor: Theme.of(context).colorScheme.onSurfaceVariant,
      iconBackground: VeloraColors.surfaceRaised,
      title: title,
      message: message,
      action: action,
    );
  }
}

/// Explains that something failed and, when it can be retried, offers that.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Try again',
    this.icon = Icons.error_outline,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = VeloraPalette.of(context);
    final retry = onRetry;
    return Semantics(
      container: true,
      liveRegion: true,
      child: _StatePanel(
        icon: icon,
        iconColor: palette.danger,
        iconBackground: palette.dangerContainer,
        title: title,
        message: message,
        action: retry == null
            ? null
            : VeloraButton(
                label: retryLabel,
                onPressed: retry,
                variant: VeloraButtonVariant.secondary,
                icon: Icons.refresh,
              ),
      ),
    );
  }
}

class _StatePanel extends StatelessWidget {
  const _StatePanel({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.message,
    required this.action,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final action = this.action;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VeloraColors.surface,
        borderRadius: BorderRadius.circular(VeloraRadii.lg),
        border: Border.all(color: VeloraColors.outlineSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VeloraSpacing.lg,
          vertical: VeloraSpacing.xl,
        ),
        child: Column(
          children: [
            MergeSemantics(
              child: Column(
                children: [
                  ExcludeSemantics(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: iconBackground,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(VeloraSpacing.md),
                        child: Icon(icon, size: 32, color: iconColor),
                      ),
                    ),
                  ),
                  const SizedBox(height: VeloraSpacing.md),
                  Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: VeloraSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Text(
                      message,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: VeloraSpacing.lg),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
