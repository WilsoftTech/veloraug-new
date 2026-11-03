import 'package:flutter/material.dart';

import 'tokens.dart';

/// Colours with no place in [ColorScheme]: status tones and the extra text
/// levels. Read it with [VeloraPalette.of].
@immutable
class VeloraPalette extends ThemeExtension<VeloraPalette> {
  const VeloraPalette({
    required this.textMuted,
    required this.textDisabled,
    required this.accentText,
    required this.focusRing,
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.infoContainer,
  });

  static const VeloraPalette dark = VeloraPalette(
    textMuted: VeloraColors.textMuted,
    textDisabled: VeloraColors.textDisabled,
    accentText: VeloraColors.accentText,
    focusRing: VeloraColors.focusRing,
    success: VeloraColors.success,
    successContainer: VeloraColors.successContainer,
    warning: VeloraColors.warning,
    warningContainer: VeloraColors.warningContainer,
    danger: VeloraColors.danger,
    dangerContainer: VeloraColors.dangerContainer,
    infoContainer: VeloraColors.infoContainer,
  );

  final Color textMuted;
  final Color textDisabled;
  final Color accentText;
  final Color focusRing;
  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color infoContainer;

  /// Falls back to [dark], so a component also works under a plain theme.
  static VeloraPalette of(BuildContext context) =>
      Theme.of(context).extension<VeloraPalette>() ?? dark;

  @override
  VeloraPalette copyWith({
    Color? textMuted,
    Color? textDisabled,
    Color? accentText,
    Color? focusRing,
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? infoContainer,
  }) {
    return VeloraPalette(
      textMuted: textMuted ?? this.textMuted,
      textDisabled: textDisabled ?? this.textDisabled,
      accentText: accentText ?? this.accentText,
      focusRing: focusRing ?? this.focusRing,
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      infoContainer: infoContainer ?? this.infoContainer,
    );
  }

  @override
  VeloraPalette lerp(ThemeExtension<VeloraPalette>? other, double t) {
    if (other is! VeloraPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return VeloraPalette(
      textMuted: mix(textMuted, other.textMuted),
      textDisabled: mix(textDisabled, other.textDisabled),
      accentText: mix(accentText, other.accentText),
      focusRing: mix(focusRing, other.focusRing),
      success: mix(success, other.success),
      successContainer: mix(successContainer, other.successContainer),
      warning: mix(warning, other.warning),
      warningContainer: mix(warningContainer, other.warningContainer),
      danger: mix(danger, other.danger),
      dangerContainer: mix(dangerContainer, other.dangerContainer),
      infoContainer: mix(infoContainer, other.infoContainer),
    );
  }
}
