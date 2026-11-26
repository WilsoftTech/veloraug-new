import 'package:flutter/material.dart';

/// TMDB's approved short logo, from themoviedb.org/about/logos-attribution,
/// drawn from its SVG to a PNG at 820 × 107 so no SVG package is needed.
const String tmdbLogoAsset = 'assets/brand/tmdb_logo.png';

/// TMDB's logo, small, so it stays less prominent than VeloraUG's own brand.
class TmdbLogo extends StatelessWidget {
  const TmdbLogo({super.key, this.height = 12, this.semanticLabel});

  final double height;

  /// Null leaves the logo out of the semantics tree, for when the words
  /// beside it already name TMDB.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      tmdbLogoAsset,
      height: height,
      semanticLabel: semanticLabel,
      excludeFromSemantics: semanticLabel == null,
    );
    return image;
  }
}
