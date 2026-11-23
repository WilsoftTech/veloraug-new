import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../l10n/l10n.dart';

/// The VeloraUG name beside its film-ribbon V mark.
class VeloraWordmark extends StatelessWidget {
  const VeloraWordmark({super.key, this.markSize = 28});

  final double markSize;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge
        ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.25);
    return Semantics(
      label: context.l10n.appName,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          VeloraMark(size: markSize),
          const SizedBox(width: VeloraSpacing.xs),
          Flexible(
            child: Text.rich(
              const TextSpan(
                children: [
                  TextSpan(text: 'Velora'),
                  TextSpan(
                    text: 'UG',
                    style: TextStyle(color: VeloraColors.accentText),
                  ),
                ],
              ),
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// The V mark on a transparent background.
///
/// The artwork is blue. It takes the hue of the theme's primary colour, so a
/// change of accent recolours the logo with it; light and shade are kept.
class VeloraMark extends StatelessWidget {
  const VeloraMark({super.key, this.size = 28, this.color});

  static const String asset = 'assets/brand/velora_mark.png';

  /// The hue of the artwork as drawn, in degrees.
  static const double _artworkHue = 217.7;

  final double size;

  /// The colour whose hue the mark takes; the theme's primary by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final target = color ?? Theme.of(context).colorScheme.primary;
    final image = Image.asset(
      asset,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
    );
    final shift = HSVColor.fromColor(target).hue - _artworkHue;
    // Close enough to the artwork's own blue: show it untouched.
    if (shift.abs() < 3) return image;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_hueRotation(shift)),
      child: image,
    );
  }
}

/// A colour matrix that turns hues by [degrees] and keeps luminance.
List<double> _hueRotation(double degrees) {
  final a = degrees * math.pi / 180;
  final c = math.cos(a);
  final s = math.sin(a);
  return [
    0.213 + c * 0.787 - s * 0.213,
    0.715 - c * 0.715 - s * 0.715,
    0.072 - c * 0.072 + s * 0.928,
    0, 0, //
    0.213 - c * 0.213 + s * 0.143,
    0.715 + c * 0.285 + s * 0.140,
    0.072 - c * 0.072 - s * 0.283,
    0, 0, //
    0.213 - c * 0.213 - s * 0.787,
    0.715 - c * 0.715 + s * 0.715,
    0.072 + c * 0.928 + s * 0.072,
    0, 0, //
    0, 0, 0, 1, 0,
  ];
}
