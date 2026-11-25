import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'movie_card.dart';
import 'tmdb_attribution.dart';

/// TMDB's rating on an edition's page: a star, the score to one decimal,
/// how many votes it is from, and TMDB's logo. Shows nothing without a
/// rating, so a title TMDB hasn't rated has no empty or zero badge.
class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.rating, this.voteCount});

  final double? rating;
  final int? voteCount;

  @override
  Widget build(BuildContext context) {
    final rating = this.rating;
    if (rating == null) return const SizedBox.shrink();
    final l = context.l10n;
    final theme = Theme.of(context);
    final votes = voteCount;
    return Semantics(
      container: true,
      label: votes == null
          ? l.ratingSemantics(rating)
          : l.ratingSemanticsWithVotes(rating, votes),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: VeloraColors.surfaceRaised,
          borderRadius: BorderRadius.circular(VeloraRadii.sm),
          border: Border.all(color: VeloraColors.outlineSubtle),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VeloraSpacing.xs,
            vertical: VeloraSpacing.xxs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: VeloraSpacing.xxs,
            children: [
              const Icon(
                Icons.star_rounded,
                size: 16,
                color: VeloraColors.rating,
              ),
              Text(
                l.ratingValue(rating),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: VeloraColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (votes != null)
                Flexible(
                  child: Text(
                    l.ratingVotes(votes),
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: VeloraColors.textSecondary,
                    ),
                  ),
                ),
              const SizedBox(width: VeloraSpacing.xxs),
              const TmdbLogo(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// TMDB's rating in a poster's bottom-right corner: a star and the score, on
/// the same dark chip as the VJ's name. The card reads it out with its
/// title, so this adds nothing to the semantics tree.
class PosterRating extends StatelessWidget {
  const PosterRating(this.rating, {super.key});

  final double rating;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: PosterChip(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: VeloraSpacing.xxs,
          children: [
            const Icon(
              Icons.star_rounded,
              size: 14,
              color: VeloraColors.rating,
            ),
            Text(
              context.l10n.ratingValue(rating),
              maxLines: 1,
              style: PosterChip.textStyle(context),
            ),
          ],
        ),
      ),
    );
  }
}
