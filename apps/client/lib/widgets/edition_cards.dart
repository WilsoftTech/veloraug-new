import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../screens/edition_screen.dart';
import '../theme/tokens.dart';
import 'loading_placeholder.dart';
import 'movie_card.dart';
import 'movie_poster.dart';

/// "2023 · Series", or just "Series".
String editionSubtitle(AppLocalizations l, EditionCard edition) => [
  if (edition.year != null) '${edition.year}',
  if (edition.kind == EditionKind.series) l.seriesBadge,
].join(' · ');

/// One edition's poster card, with only the VJ's name on the poster.
class EditionTile extends StatelessWidget {
  const EditionTile({super.key, required this.edition});

  final EditionCard edition;

  @override
  Widget build(BuildContext context) {
    final subtitle = editionSubtitle(context.l10n, edition);
    return MovieCard(
      title: edition.title,
      cornerLabel: edition.vjName,
      subtitle: subtitle.isEmpty ? null : subtitle,
      artwork: MoviePoster(url: edition.posterUrl),
      onTap: () => openEdition(context, edition),
    );
  }
}

/// Edition cards in a grid.
class EditionGrid extends StatelessWidget {
  const EditionGrid({super.key, required this.editions});

  final List<EditionCard> editions;

  @override
  Widget build(BuildContext context) {
    return MovieCardGrid(
      children: [
        for (final edition in editions)
          EditionTile(key: ValueKey(edition.id), edition: edition),
      ],
    );
  }
}

/// A titled row of edition cards that scrolls sideways, with See all.
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

  static const double cardWidth = 150;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final seeAll = onSeeAll;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.sm,
      children: [
        // A Wrap, so See all moves below the title at large text sizes.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: VeloraSpacing.sm,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: VeloraSpacing.sm,
              children: [
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
                child: Text(
                  context.l10n.seeAll,
                  semanticsLabel: context.l10n.seeAllOf(title),
                ),
              ),
          ],
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: VeloraSpacing.md,
              children: [
                for (final edition in editions)
                  SizedBox(
                    key: ValueKey(edition.id),
                    width: cardWidth,
                    child: EditionTile(edition: edition),
                  ),
              ],
            ),
          ),
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
      child: MovieCardGrid(
        children: [for (var i = 0; i < count; i++) const MovieCardSkeleton()],
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
