import 'package:flutter/material.dart';

/// The VeloraUG design tokens: the one place raw colours, sizes and timings
/// are written. docs/design-system.md is the specification, and
/// apps/auth_pages/src/tokens.css mirrors these values. A test fails if the
/// two drift apart.
abstract final class VeloraColors {
  // Surfaces, darkest to lightest.
  static const Color canvas = Color(0xFF0E1014);
  static const Color surface = Color(0xFF171A1F);
  static const Color surfaceRaised = Color(0xFF1F2329);
  static const Color surfaceOverlay = Color(0xFF2A2F37);

  // Text.
  static const Color textPrimary = Color(0xFFF4F2EC);
  static const Color textSecondary = Color(0xFFBCC1CA);
  static const Color textMuted = Color(0xFF9AA1AD);
  static const Color textDisabled = Color(0xFF7F8691);

  // Electric blue. `accent` is a fill, always with `onAccent` on top. Use
  // `accentText` for blue text and icons, because `accent` is too dark to read
  // on charcoal.
  static const Color accent = Color(0xFF1A66F5);
  static const Color accentHover = Color(0xFF1E69F5);
  static const Color accentPressed = Color(0xFF1557D6);
  static const Color onAccent = Color(0xFFFFFFFF);
  static const Color accentText = Color(0xFF7DB2FF);
  static const Color focusRing = Color(0xFFB8D4FF);

  // Lines. `outline` marks the edge of a control, `outlineSubtle` is decoration.
  static const Color outline = Color(0xFF7C8491);
  static const Color outlineSubtle = Color(0xFF343A43);

  // Status. Always shown with an icon and words, never by colour alone.
  static const Color success = Color(0xFF5FD39A);
  static const Color successContainer = Color(0xFF12291F);
  static const Color warning = Color(0xFFF5BE5B);
  static const Color warningContainer = Color(0xFF2C2312);
  static const Color danger = Color(0xFFFF8A80);
  static const Color dangerContainer = Color(0xFF301A1A);
  static const Color infoContainer = Color(0xFF14233D);
}

abstract final class VeloraSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;
}

abstract final class VeloraRadii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
}

abstract final class VeloraStroke {
  static const double hairline = 1;
  static const double focus = 2;
}

/// On charcoal, depth comes mainly from a lighter surface. These shadows are
/// plain black, with no coloured glow.
abstract final class VeloraShadows {
  static const List<BoxShadow> raised = [
    BoxShadow(color: Color(0x52000000), blurRadius: 16, offset: Offset(0, 6)),
  ];
}

/// Font stacks only: no font file is bundled in this first version. Setting
/// [displayFamily] changes the headings everywhere.
abstract final class VeloraFonts {
  static const String? displayFamily = null;
  static const List<String> fallback = [
    'Roboto',
    'Segoe UI',
    'Helvetica Neue',
    'Noto Sans',
    'Arial',
    'sans-serif',
  ];
}

abstract final class VeloraLayout {
  /// At least this wide is a medium layout, with a side rail and not a bottom
  /// bar.
  static const double mediumBreakpoint = 600;

  /// At least this wide is an expanded layout.
  static const double expandedBreakpoint = 1024;

  static const double formWidth = 420;
  static const double readingWidth = 720;
  static const double browseWidth = 1280;

  static const double minTouchTarget = 48;

  /// Width over height of a movie poster.
  static const double posterAspectRatio = 2 / 3;
  static const double minPosterWidthCompact = 136;
  static const double minPosterWidthWide = 176;

  /// The space on each side of a screen's content.
  static double gutterFor(double screenWidth) {
    if (screenWidth >= expandedBreakpoint) return VeloraSpacing.xxl;
    if (screenWidth >= mediumBreakpoint) return VeloraSpacing.xl;
    return VeloraSpacing.md;
  }
}

abstract final class VeloraMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 320);

  /// One full fade out and back of a loading placeholder, slow enough not to
  /// read as a flash.
  static const Duration pulse = Duration(milliseconds: 1400);

  static const Curve curve = Curves.easeOutCubic;

  /// [duration], or nothing when the person asked for reduced motion.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
