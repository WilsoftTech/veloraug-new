import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veloraug/theme/palette.dart';
import 'package:veloraug/theme/tokens.dart';
import 'package:veloraug/theme/velora_theme.dart';

double _contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

const _surfaces = {
  'canvas': VeloraColors.canvas,
  'surface': VeloraColors.surface,
  'surfaceRaised': VeloraColors.surfaceRaised,
  'surfaceOverlay': VeloraColors.surfaceOverlay,
};

void main() {
  group('contrast', () {
    const readable = {
      'textPrimary': VeloraColors.textPrimary,
      'textSecondary': VeloraColors.textSecondary,
      'textMuted': VeloraColors.textMuted,
      'accentText': VeloraColors.accentText,
      'success': VeloraColors.success,
      'warning': VeloraColors.warning,
      'danger': VeloraColors.danger,
    };

    for (final MapEntry(key: name, value: color) in readable.entries) {
      test('$name reaches 4.5:1 on every surface', () {
        for (final MapEntry(key: surfaceName, value: surface)
            in _surfaces.entries) {
          expect(
            _contrast(color, surface),
            greaterThanOrEqualTo(4.5),
            reason: '$name on $surfaceName',
          );
        }
      });
    }

    test('button text reaches 4.5:1 in every button state', () {
      for (final fill in const [
        VeloraColors.accent,
        VeloraColors.accentHover,
        VeloraColors.accentPressed,
      ]) {
        expect(
          _contrast(VeloraColors.onAccent, fill),
          greaterThanOrEqualTo(4.5),
        );
      }
    });

    test('status text reaches 4.5:1 on its own container', () {
      for (final (text, container) in const [
        (VeloraColors.success, VeloraColors.successContainer),
        (VeloraColors.warning, VeloraColors.warningContainer),
        (VeloraColors.danger, VeloraColors.dangerContainer),
        (VeloraColors.accentText, VeloraColors.infoContainer),
      ]) {
        expect(_contrast(text, container), greaterThanOrEqualTo(4.5));
      }
    });

    test('the focus ring and control edges reach 3:1', () {
      for (final surface in _surfaces.values) {
        expect(
          _contrast(VeloraColors.focusRing, surface),
          greaterThanOrEqualTo(3),
        );
        expect(
          _contrast(VeloraColors.outline, surface),
          greaterThanOrEqualTo(3),
        );
      }
      expect(
        _contrast(VeloraColors.focusRing, VeloraColors.accent),
        greaterThanOrEqualTo(3),
      );
    });

    test('a filled button stands out from every surface but the top one', () {
      for (final surface in const [
        VeloraColors.canvas,
        VeloraColors.surface,
        VeloraColors.surfaceRaised,
      ]) {
        expect(
          _contrast(VeloraColors.accent, surface),
          greaterThanOrEqualTo(3),
        );
      }
    });
  });

  group('the sign-in pages mirror the tokens', () {
    // `flutter test` runs from apps/client.
    final css = File('../auth_pages/src/tokens.css').readAsStringSync();

    String? cssValue(String name) =>
        RegExp('--velora-$name:\\s*([^;]+);').firstMatch(css)?.group(1)?.trim();

    const colors = {
      'canvas': VeloraColors.canvas,
      'surface': VeloraColors.surface,
      'surface-raised': VeloraColors.surfaceRaised,
      'surface-overlay': VeloraColors.surfaceOverlay,
      'text-primary': VeloraColors.textPrimary,
      'text-secondary': VeloraColors.textSecondary,
      'text-muted': VeloraColors.textMuted,
      'text-disabled': VeloraColors.textDisabled,
      'accent': VeloraColors.accent,
      'accent-hover': VeloraColors.accentHover,
      'accent-pressed': VeloraColors.accentPressed,
      'on-accent': VeloraColors.onAccent,
      'accent-text': VeloraColors.accentText,
      'focus-ring': VeloraColors.focusRing,
      'outline': VeloraColors.outline,
      'outline-subtle': VeloraColors.outlineSubtle,
      'success': VeloraColors.success,
      'success-container': VeloraColors.successContainer,
      'warning': VeloraColors.warning,
      'warning-container': VeloraColors.warningContainer,
      'danger': VeloraColors.danger,
      'danger-container': VeloraColors.dangerContainer,
      'info-container': VeloraColors.infoContainer,
    };

    for (final MapEntry(key: name, value: color) in colors.entries) {
      test('colour $name', () {
        expect(cssValue('color-$name'), _hex(color));
      });
    }

    const sizes = {
      'space-xxs': VeloraSpacing.xxs,
      'space-xs': VeloraSpacing.xs,
      'space-sm': VeloraSpacing.sm,
      'space-md': VeloraSpacing.md,
      'space-lg': VeloraSpacing.lg,
      'space-xl': VeloraSpacing.xl,
      'space-xxl': VeloraSpacing.xxl,
      'space-xxxl': VeloraSpacing.xxxl,
      'radius-sm': VeloraRadii.sm,
      'radius-md': VeloraRadii.md,
      'radius-lg': VeloraRadii.lg,
      'stroke-hairline': VeloraStroke.hairline,
      'stroke-focus': VeloraStroke.focus,
      'width-form': VeloraLayout.formWidth,
      'touch-target': VeloraLayout.minTouchTarget,
    };

    for (final MapEntry(key: name, value: size) in sizes.entries) {
      test('size $name', () {
        expect(cssValue(name), '${size.toInt()}px');
      });
    }

    test('motion', () {
      expect(cssValue('motion-fast'), '${VeloraMotion.fast.inMilliseconds}ms');
      expect(
        cssValue('motion-standard'),
        '${VeloraMotion.standard.inMilliseconds}ms',
      );
      expect(cssValue('motion-slow'), '${VeloraMotion.slow.inMilliseconds}ms');
    });
  });

  group('theme', () {
    final theme = buildVeloraTheme();

    test('is dark, on the charcoal canvas, with the palette attached', () {
      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, VeloraColors.canvas);
      expect(theme.colorScheme.primary, VeloraColors.accent);
      expect(theme.colorScheme.onSurface, VeloraColors.textPrimary);
      expect(theme.extension<VeloraPalette>(), VeloraPalette.dark);
    });

    test('every button theme asks for a 48 pixel target', () {
      for (final style in [
        theme.filledButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
        theme.iconButtonTheme.style,
      ]) {
        final size = style!.minimumSize!.resolve({})!;
        expect(size.width, greaterThanOrEqualTo(48));
        expect(size.height, greaterThanOrEqualTo(48));
      }
    });

    test('every button theme shows the focus ring', () {
      for (final style in [
        theme.filledButtonTheme.style,
        theme.outlinedButtonTheme.style,
        theme.textButtonTheme.style,
        theme.iconButtonTheme.style,
      ]) {
        final side = style!.side!.resolve({WidgetState.focused})!;
        expect(side.color, VeloraColors.focusRing);
        expect(side.width, VeloraStroke.focus);
      }
    });

    test('the palette blends to its target', () {
      const other = VeloraPalette(
        textMuted: Colors.white,
        textDisabled: Colors.white,
        accentText: Colors.white,
        focusRing: Colors.white,
        success: Colors.white,
        successContainer: Colors.white,
        warning: Colors.white,
        warningContainer: Colors.white,
        danger: Colors.white,
        dangerContainer: Colors.white,
        infoContainer: Colors.white,
      );
      expect(VeloraPalette.dark.lerp(other, 1).danger, Colors.white);
      expect(VeloraPalette.dark.copyWith().danger, VeloraColors.danger);
    });
  });

  group('layout tokens', () {
    test('gutters widen with the screen', () {
      expect(VeloraLayout.gutterFor(360), VeloraSpacing.md);
      expect(VeloraLayout.gutterFor(600), VeloraSpacing.xl);
      expect(VeloraLayout.gutterFor(1024), VeloraSpacing.xxl);
    });

    test('posters are 2:3', () {
      expect(VeloraLayout.posterAspectRatio, closeTo(0.667, 0.001));
    });
  });
}
