import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';

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

/// "Ratings from" and TMDB's logo: one line at the foot of a screen that
/// shows ratings on its posters, as TMDB's terms ask, rather than a logo on
/// every card. Shows nothing when [editions] has no rating.
class TmdbAttribution extends StatelessWidget {
  const TmdbAttribution({super.key, required this.editions});

  final Iterable<EditionCard> editions;

  @override
  Widget build(BuildContext context) {
    if (!editions.any((edition) => edition.rating != null)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final l = context.l10n;
    return Semantics(
      container: true,
      label: l.ratingsFromTmdbSemantics,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: VeloraSpacing.xs,
        children: [
          // Wraps rather than overflow on a narrow phone at large text.
          Flexible(
            child: Text(
              l.ratingsFromTmdb,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const TmdbLogo(),
        ],
      ),
    );
  }
}
