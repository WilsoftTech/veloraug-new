import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'loading_placeholder.dart';

enum VeloraButtonVariant { primary, secondary, tertiary, danger }

/// A labelled action. It adds the loading state and the danger variant to the
/// themed Material buttons.
class VeloraButton extends StatelessWidget {
  const VeloraButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = VeloraButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.loadingLabel = 'Loading…',
    this.expand = false,
    this.statesController,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final VeloraButtonVariant variant;
  final IconData? icon;

  /// Disables the button and replaces its label with [loadingLabel], so
  /// waiting isn't shown by the spinner alone.
  final bool isLoading;
  final String loadingLabel;

  /// Fills the available width.
  final bool expand;

  /// Forces a visual state. Only the showcase needs this.
  final WidgetStatesController? statesController;

  @override
  Widget build(BuildContext context) {
    final action = isLoading ? null : onPressed;
    final content = _ButtonContent(
      label: isLoading ? loadingLabel : label,
      icon: icon,
      isLoading: isLoading,
    );
    final Widget button = switch (variant) {
      VeloraButtonVariant.primary => FilledButton(
        onPressed: action,
        statesController: statesController,
        child: content,
      ),
      VeloraButtonVariant.secondary => OutlinedButton(
        onPressed: action,
        statesController: statesController,
        child: content,
      ),
      VeloraButtonVariant.tertiary => TextButton(
        onPressed: action,
        statesController: statesController,
        child: content,
      ),
      VeloraButtonVariant.danger => OutlinedButton(
        onPressed: action,
        statesController: statesController,
        style: _dangerStyle(VeloraPalette.of(context)),
        child: content,
      ),
    };
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }

  ButtonStyle _dangerStyle(VeloraPalette palette) {
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? palette.textDisabled
            : palette.danger,
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) return Colors.transparent;
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.hovered)) {
          return palette.dangerContainer;
        }
        return Colors.transparent;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.focused)) {
          return BorderSide(
            color: palette.focusRing,
            width: VeloraStroke.focus,
          );
        }
        return BorderSide(
          color: states.contains(WidgetState.disabled)
              ? VeloraColors.outlineSubtle
              : palette.danger,
        );
      }),
    );
  }
}

class _ButtonContent extends StatelessWidget {
  const _ButtonContent({
    required this.label,
    required this.icon,
    required this.isLoading,
  });

  final String label;
  final IconData? icon;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final leading = isLoading
        ? const VeloraSpinner(size: 18)
        : (icon == null ? null : ExcludeSemantics(child: Icon(icon, size: 18)));
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading,
          const SizedBox(width: VeloraSpacing.xs),
        ],
        Flexible(child: Text(label, textAlign: TextAlign.center)),
      ],
    );
  }
}
