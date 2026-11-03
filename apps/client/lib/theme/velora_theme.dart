import 'package:flutter/material.dart';

import 'palette.dart';
import 'tokens.dart';

const _focusSide = BorderSide(
  color: VeloraColors.focusRing,
  width: VeloraStroke.focus,
);
const _minimumButtonSize = Size(
  VeloraLayout.minTouchTarget,
  VeloraLayout.minTouchTarget,
);
final _buttonShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(VeloraRadii.md),
);
const _buttonPadding = EdgeInsets.symmetric(
  horizontal: VeloraSpacing.lg,
  vertical: VeloraSpacing.sm,
);

BorderSide? _focusOnly(Set<WidgetState> states) =>
    states.contains(WidgetState.focused) ? _focusSide : null;

/// The background of a button with no fill of its own.
Color _quietBackground(Set<WidgetState> states) {
  if (states.contains(WidgetState.disabled)) return Colors.transparent;
  if (states.contains(WidgetState.pressed)) return VeloraColors.surfaceOverlay;
  if (states.contains(WidgetState.hovered)) return VeloraColors.surfaceRaised;
  return Colors.transparent;
}

/// The app's only theme: dark, built entirely from the tokens.
ThemeData buildVeloraTheme() {
  const colorScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: VeloraColors.accent,
    onPrimary: VeloraColors.onAccent,
    primaryContainer: VeloraColors.infoContainer,
    onPrimaryContainer: VeloraColors.textPrimary,
    secondary: VeloraColors.accentText,
    onSecondary: VeloraColors.canvas,
    secondaryContainer: VeloraColors.infoContainer,
    onSecondaryContainer: VeloraColors.textPrimary,
    tertiary: VeloraColors.accentText,
    onTertiary: VeloraColors.canvas,
    error: VeloraColors.danger,
    onError: VeloraColors.canvas,
    errorContainer: VeloraColors.dangerContainer,
    onErrorContainer: VeloraColors.textPrimary,
    surface: VeloraColors.canvas,
    onSurface: VeloraColors.textPrimary,
    onSurfaceVariant: VeloraColors.textSecondary,
    surfaceContainerLowest: VeloraColors.canvas,
    surfaceContainerLow: VeloraColors.surface,
    surfaceContainer: VeloraColors.surface,
    surfaceContainerHigh: VeloraColors.surfaceRaised,
    surfaceContainerHighest: VeloraColors.surfaceOverlay,
    outline: VeloraColors.outline,
    outlineVariant: VeloraColors.outlineSubtle,
    inverseSurface: VeloraColors.textPrimary,
    onInverseSurface: VeloraColors.canvas,
    inversePrimary: VeloraColors.accent,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );
  final textTheme = _buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: VeloraColors.canvas,
    canvasColor: VeloraColors.canvas,
    textTheme: textTheme,
    fontFamilyFallback: VeloraFonts.fallback,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
    splashFactory: InkRipple.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: VeloraColors.textPrimary.withValues(alpha: 0.06),
    // Built-in controls with no focus border, such as navigation items, show
    // focus with this fill, so it is much stronger than the Material default.
    focusColor: VeloraColors.focusRing.withValues(alpha: 0.32),
    extensions: const [VeloraPalette.dark],
    appBarTheme: AppBarTheme(
      backgroundColor: VeloraColors.canvas,
      foregroundColor: VeloraColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: VeloraColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: VeloraColors.infoContainer,
      elevation: 0,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? VeloraColors.accentText
              : VeloraColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => textTheme.labelMedium?.copyWith(
          color: states.contains(WidgetState.selected)
              ? VeloraColors.textPrimary
              : VeloraColors.textSecondary,
        ),
      ),
      overlayColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? VeloraColors.focusRing.withValues(alpha: 0.32)
            : null,
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: VeloraColors.canvas,
      indicatorColor: VeloraColors.infoContainer,
      elevation: 0,
      selectedIconTheme: const IconThemeData(color: VeloraColors.accentText),
      unselectedIconTheme: const IconThemeData(
        color: VeloraColors.textSecondary,
      ),
      selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: VeloraColors.textPrimary,
      ),
      unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
        color: VeloraColors.textSecondary,
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: VeloraColors.textPrimary,
      unselectedLabelColor: VeloraColors.textSecondary,
      labelStyle: textTheme.labelLarge,
      unselectedLabelStyle: textTheme.labelLarge,
      indicatorColor: VeloraColors.accentText,
      dividerColor: VeloraColors.outlineSubtle,
      tabAlignment: TabAlignment.start,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        animationDuration: VeloraMotion.fast,
        minimumSize: const WidgetStatePropertyAll(_minimumButtonSize),
        padding: const WidgetStatePropertyAll(_buttonPadding),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(_buttonShape),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return VeloraColors.surfaceOverlay;
          }
          if (states.contains(WidgetState.pressed)) {
            return VeloraColors.accentPressed;
          }
          if (states.contains(WidgetState.hovered)) {
            return VeloraColors.accentHover;
          }
          return VeloraColors.accent;
        }),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? VeloraColors.textDisabled
              : VeloraColors.onAccent,
        ),
        // The fill changes colour itself, so the state overlay stays off.
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(_focusOnly),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        animationDuration: VeloraMotion.fast,
        minimumSize: const WidgetStatePropertyAll(_minimumButtonSize),
        padding: const WidgetStatePropertyAll(_buttonPadding),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(_buttonShape),
        backgroundColor: WidgetStateProperty.resolveWith(_quietBackground),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? VeloraColors.textDisabled
              : VeloraColors.textPrimary,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) return _focusSide;
          return BorderSide(
            color: states.contains(WidgetState.disabled)
                ? VeloraColors.outlineSubtle
                : VeloraColors.outline,
            width: VeloraStroke.hairline,
          );
        }),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        animationDuration: VeloraMotion.fast,
        minimumSize: const WidgetStatePropertyAll(_minimumButtonSize),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: VeloraSpacing.md,
            vertical: VeloraSpacing.sm,
          ),
        ),
        textStyle: WidgetStatePropertyAll(textTheme.labelLarge),
        shape: WidgetStatePropertyAll(_buttonShape),
        backgroundColor: WidgetStateProperty.resolveWith(_quietBackground),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? VeloraColors.textDisabled
              : VeloraColors.accentText,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith(_focusOnly),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(_minimumButtonSize),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? VeloraColors.textDisabled
              : VeloraColors.textSecondary,
        ),
        side: WidgetStateProperty.resolveWith(_focusOnly),
      ),
    ),
    inputDecorationTheme: _buildInputTheme(textTheme),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: VeloraColors.accentText,
      selectionColor: VeloraColors.accent.withValues(alpha: 0.5),
      selectionHandleColor: VeloraColors.accentText,
    ),
    cardTheme: CardThemeData(
      color: VeloraColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VeloraRadii.lg),
        side: const BorderSide(color: VeloraColors.outlineSubtle),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: VeloraColors.surfaceRaised,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VeloraRadii.lg),
      ),
      titleTextStyle: textTheme.headlineSmall,
      contentTextStyle: textTheme.bodyMedium?.copyWith(
        color: VeloraColors.textSecondary,
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: VeloraColors.surfaceOverlay,
      contentTextStyle: textTheme.bodyMedium,
      actionTextColor: VeloraColors.accentText,
      closeIconColor: VeloraColors.textPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VeloraRadii.md),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      textStyle: textTheme.bodySmall,
      decoration: BoxDecoration(
        color: VeloraColors.surfaceOverlay,
        borderRadius: BorderRadius.circular(VeloraRadii.sm),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: VeloraColors.outlineSubtle,
      thickness: VeloraStroke.hairline,
      space: VeloraSpacing.lg,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: VeloraColors.accentText,
    ),
  );
}

final _inputIconColor = WidgetStateColor.resolveWith(
  (states) => states.contains(WidgetState.disabled)
      ? VeloraColors.textDisabled
      : VeloraColors.textSecondary,
);

InputDecorationThemeData _buildInputTheme(TextTheme textTheme) {
  OutlineInputBorder border(
    Color color, [
    double width = VeloraStroke.hairline,
  ]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(VeloraRadii.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecorationThemeData(
    filled: true,
    fillColor: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? VeloraColors.canvas
          : VeloraColors.surface,
    ),
    contentPadding: const EdgeInsets.all(VeloraSpacing.md),
    labelStyle: WidgetStateTextStyle.resolveWith((states) {
      return (textTheme.bodyLarge ?? const TextStyle()).copyWith(
        color: states.contains(WidgetState.disabled)
            ? VeloraColors.textDisabled
            : VeloraColors.textSecondary,
      );
    }),
    floatingLabelStyle: WidgetStateTextStyle.resolveWith((states) {
      final style = textTheme.bodyMedium ?? const TextStyle();
      if (states.contains(WidgetState.disabled)) {
        return style.copyWith(color: VeloraColors.textDisabled);
      }
      if (states.contains(WidgetState.error)) {
        return style.copyWith(color: VeloraColors.danger);
      }
      if (states.contains(WidgetState.focused)) {
        return style.copyWith(color: VeloraColors.accentText);
      }
      return style.copyWith(color: VeloraColors.textSecondary);
    }),
    hintStyle: textTheme.bodyLarge?.copyWith(color: VeloraColors.textMuted),
    helperStyle: textTheme.bodySmall?.copyWith(
      color: VeloraColors.textSecondary,
    ),
    helperMaxLines: 4,
    errorStyle: textTheme.bodySmall?.copyWith(color: VeloraColors.danger),
    errorMaxLines: 4,
    prefixIconColor: _inputIconColor,
    suffixIconColor: _inputIconColor,
    border: border(VeloraColors.outline),
    enabledBorder: border(VeloraColors.outline),
    disabledBorder: border(VeloraColors.outlineSubtle),
    focusedBorder: border(VeloraColors.accentText, VeloraStroke.focus),
    errorBorder: border(VeloraColors.danger),
    focusedErrorBorder: border(VeloraColors.danger, VeloraStroke.focus),
  );
}

TextTheme _buildTextTheme() {
  TextStyle heading(
    double size,
    double lineHeight,
    FontWeight weight, {
    double spacing = 0,
  }) {
    return TextStyle(
      fontFamily: VeloraFonts.displayFamily,
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: spacing,
      color: VeloraColors.textPrimary,
    );
  }

  TextStyle text(
    double size,
    double lineHeight,
    FontWeight weight, {
    double spacing = 0,
  }) {
    return TextStyle(
      fontSize: size,
      height: lineHeight / size,
      fontWeight: weight,
      letterSpacing: spacing,
      color: VeloraColors.textPrimary,
    );
  }

  return TextTheme(
    displayLarge: heading(56, 60, FontWeight.w800, spacing: -1.5),
    displayMedium: heading(48, 52, FontWeight.w800, spacing: -1),
    displaySmall: heading(36, 42, FontWeight.w800, spacing: -0.5),
    headlineLarge: heading(32, 38, FontWeight.w700, spacing: -0.5),
    headlineMedium: heading(28, 34, FontWeight.w700, spacing: -0.25),
    headlineSmall: heading(22, 28, FontWeight.w700),
    titleLarge: text(20, 26, FontWeight.w600),
    titleMedium: text(16, 22, FontWeight.w600),
    titleSmall: text(14, 20, FontWeight.w600),
    bodyLarge: text(16, 24, FontWeight.w400),
    bodyMedium: text(14, 20, FontWeight.w400),
    bodySmall: text(12, 16, FontWeight.w400),
    labelLarge: text(14, 20, FontWeight.w600, spacing: 0.1),
    labelMedium: text(12, 16, FontWeight.w600, spacing: 0.2),
    labelSmall: text(12, 16, FontWeight.w500, spacing: 0.2),
  );
}
