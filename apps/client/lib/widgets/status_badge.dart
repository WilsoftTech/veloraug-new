import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';

enum StatusTone { neutral, info, success, warning, danger }

/// A short status. It always has an icon and words, so it still reads without
/// colour.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
    this.icon,
  });

  final String label;
  final StatusTone tone;

  /// Replaces the tone's usual icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = VeloraPalette.of(context);
    final (foreground, background, defaultIcon) = switch (tone) {
      StatusTone.neutral => (
        VeloraColors.textSecondary,
        VeloraColors.surfaceRaised,
        Icons.circle_outlined,
      ),
      StatusTone.info => (
        palette.accentText,
        palette.infoContainer,
        Icons.info_outline,
      ),
      StatusTone.success => (
        palette.success,
        palette.successContainer,
        Icons.check_circle_outline,
      ),
      StatusTone.warning => (
        palette.warning,
        palette.warningContainer,
        Icons.warning_amber_outlined,
      ),
      StatusTone.danger => (
        palette.danger,
        palette.dangerContainer,
        Icons.error_outline,
      ),
    };

    return Semantics(
      container: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(VeloraRadii.sm),
          border: Border.all(color: foreground.withValues(alpha: 0.4)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VeloraSpacing.xs,
            vertical: VeloraSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(icon ?? defaultIcon, size: 14, color: foreground),
              ),
              const SizedBox(width: VeloraSpacing.xxs),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
