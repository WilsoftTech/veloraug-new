import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../screens/edition_screen.dart';
import '../theme/tokens.dart';
import 'loading_placeholder.dart';
import 'movie_card.dart';
import 'movie_poster.dart';
import 'poster_grid.dart';

/// "2023 · Series", or just "Series".
String editionSubtitle(AppLocalizations l, EditionCard edition) => [
  if (edition.year != null) '${edition.year}',
  if (edition.kind == EditionKind.series) l.seriesBadge,
].join(' · ');

/// One edition's poster card, with only the VJ's name on the poster.
class EditionTile extends StatelessWidget {
  const EditionTile({super.key, required this.edition, this.dense = false});

  final EditionCard edition;

  /// Phone grids and shelves: see [MovieCard.dense].
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final subtitle = editionSubtitle(context.l10n, edition);
    return MovieCard(
      title: edition.title,
      cornerLabel: edition.vjName,
      subtitle: subtitle.isEmpty ? null : subtitle,
      artwork: MoviePoster(url: edition.posterUrl),
      dense: dense,
      onTap: () => openEdition(context, edition),
    );
  }
}

/// Edition cards in the shared poster grid: three columns on a phone.
class EditionGrid extends StatelessWidget {
  const EditionGrid({super.key, required this.editions});

  final List<EditionCard> editions;

  @override
  Widget build(BuildContext context) {
    return PosterGrid(
      itemCount: editions.length,
      itemBuilder: (context, i, dense) => EditionTile(
        key: ValueKey(editions[i].id),
        edition: editions[i],
        dense: dense,
      ),
    );
  }
}

/// A shelf's heading: an accent bar, the title, and See all. See all moves
/// below the title at large text sizes rather than squeezing it.
class ShelfHeader extends StatelessWidget {
  const ShelfHeader({
    super.key,
    required this.title,
    this.onSeeAll,
    this.leading,
  });

  final String title;
  final VoidCallback? onSeeAll;

  /// Shown before the title, such as a VJ's photo.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final seeAll = onSeeAll;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: VeloraSpacing.sm,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: VeloraSpacing.sm,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: VeloraColors.accentText,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            ?leading,
            Flexible(
              child: Semantics(
                header: true,
                child: Text(title, style: theme.textTheme.titleLarge),
              ),
            ),
          ],
        ),
        if (seeAll != null)
          TextButton(
            onPressed: seeAll,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: VeloraSpacing.xs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l.seeAll, semanticsLabel: l.seeAllOf(title)),
                const Icon(Icons.chevron_right, size: 20),
              ],
            ),
          ),
      ],
    );
  }
}

/// A titled shelf of edition cards that scrolls sideways, with See all.
/// On a phone about three posters fit across, with the next one peeking.
class EditionRow extends StatelessWidget {
  const EditionRow({
    super.key,
    required this.title,
    required this.editions,
    this.onSeeAll,
    this.leading,
  });

  final String title;
  final List<EditionCard> editions;
  final VoidCallback? onSeeAll;

  /// Shown before the title, such as a VJ's photo.
  final Widget? leading;

  /// A card's width on wider screens.
  static const double cardWidth = 150;

  /// The width of one card in a shelf [width] wide: on phones, about three
  /// across with a little of the fourth showing, so the shelf reads as one
  /// that scrolls.
  static double cardWidthFor(double width, double screenWidth) {
    if (screenWidth >= VeloraLayout.mediumBreakpoint) return cardWidth;
    const gap = VeloraSpacing.xs;
    return ((width + gap) / 3.2 - gap).clamp(88, cardWidth).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compact = screenWidth < VeloraLayout.mediumBreakpoint;
    final gap = compact ? VeloraSpacing.xs : VeloraSpacing.md;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.sm,
      children: [
        ShelfHeader(title: title, onSeeAll: onSeeAll, leading: leading),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = cardWidthFor(constraints.maxWidth, screenWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    for (final edition in editions)
                      SizedBox(
                        key: ValueKey(edition.id),
                        width: width,
                        child: EditionTile(edition: edition, dense: compact),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

/// Opens an edition's page.
void openEdition(BuildContext context, EditionCard edition) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          EditionScreen(editionId: edition.id, title: edition.title),
    ),
  );
}

/// Placeholder cards while a page loads.
class EditionGridSkeleton extends StatelessWidget {
  const EditionGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return VeloraLoadingRegion(
      label: context.l10n.loadingTitles,
      child: PosterGrid(
        itemCount: count,
        itemBuilder: (context, i, dense) => const MovieCardSkeleton(),
      ),
    );
  }
}

/// A VJ's photo in a circle, or their initial without one.
class VjAvatar extends StatelessWidget {
  const VjAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 40,
  });

  final String name;
  final String? photoUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    final initial = name.replaceFirst(
      RegExp(r'^VJ\s+', caseSensitive: false),
      '',
    );
    final fallback = Center(
      child: Text(
        initial.isEmpty ? '?' : initial.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: VeloraColors.textPrimary,
        ),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: ClipOval(
          child: ColoredBox(
            color: VeloraColors.surfaceRaised,
            child: url == null
                ? fallback
                : Image.network(
                    url,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
