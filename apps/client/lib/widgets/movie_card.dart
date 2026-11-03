import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'loading_placeholder.dart';

/// Neutral local artwork for a movie with no poster. It loads nothing from the
/// network and implies no real title.
class PosterPlaceholder extends StatelessWidget {
  const PosterPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: VeloraLayout.posterAspectRatio,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [VeloraColors.surfaceOverlay, VeloraColors.surface],
            ),
          ),
          child: Center(
            child: Icon(
              Icons.movie_outlined,
              size: 40,
              color: VeloraPalette.of(context).textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A movie's poster and details. Its height follows its content, so larger
/// text makes the card taller instead of clipping it.
class MovieCard extends StatefulWidget {
  const MovieCard({
    super.key,
    required this.title,
    this.subtitle,
    this.status,
    this.artwork,
    this.onTap,
  });

  final String title;
  final String? subtitle;

  /// Usually a StatusBadge, shown below the details.
  final Widget? status;

  /// Defaults to [PosterPlaceholder].
  final Widget? artwork;

  /// Null shows the card with no action.
  final VoidCallback? onTap;

  @override
  State<MovieCard> createState() => _MovieCardState();
}

class _MovieCardState extends State<MovieCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = VeloraPalette.of(context);
    final duration = VeloraMotion.of(context, VeloraMotion.fast);
    final enabled = widget.onTap != null;
    final subtitle = widget.subtitle;
    final status = widget.status;

    final BorderSide border;
    if (_focused) {
      border = BorderSide(color: palette.focusRing, width: VeloraStroke.focus);
    } else if (_hovered && enabled) {
      border = const BorderSide(color: VeloraColors.outline);
    } else {
      border = const BorderSide(color: VeloraColors.outlineSubtle);
    }

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: duration,
      curve: VeloraMotion.curve,
      child: AnimatedContainer(
        duration: duration,
        curve: VeloraMotion.curve,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: VeloraColors.surface,
          borderRadius: BorderRadius.circular(VeloraRadii.md),
          boxShadow: _hovered && enabled ? VeloraShadows.raised : null,
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(VeloraRadii.md),
          border: Border.fromBorderSide(border),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Semantics(
            container: true,
            button: enabled,
            enabled: enabled,
            excludeSemantics: true,
            onTap: widget.onTap,
            label: [widget.title, ?subtitle].join(', '),
            child: InkWell(
              onTap: widget.onTap,
              onHover: (value) => setState(() => _hovered = value),
              onFocusChange: (value) => setState(() => _focused = value),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  widget.artwork ?? const PosterPlaceholder(),
                  Padding(
                    padding: const EdgeInsets.all(VeloraSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: VeloraSpacing.xxs),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (status != null) ...[
                          const SizedBox(height: VeloraSpacing.xs),
                          status,
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A placeholder with a [MovieCard]'s shape.
class MovieCardSkeleton extends StatelessWidget {
  const MovieCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VeloraSkeleton(
          aspectRatio: VeloraLayout.posterAspectRatio,
          radius: VeloraRadii.md,
        ),
        SizedBox(height: VeloraSpacing.sm),
        VeloraSkeleton(height: 14),
        SizedBox(height: VeloraSpacing.xs),
        FractionallySizedBox(
          widthFactor: 0.5,
          alignment: Alignment.centerLeft,
          child: VeloraSkeleton(height: 12),
        ),
      ],
    );
  }
}

/// Lays out movie cards in as many equal columns as fit, at least two. Each
/// row is as tall as its tallest card and all its cards match that height, so
/// nothing overflows at large text sizes.
///
/// This builds every card, so it suits short lists. A long catalogue will need
/// a lazy grid.
class MovieCardGrid extends StatelessWidget {
  const MovieCardGrid({super.key, required this.children});

  final List<Widget> children;

  /// How many columns fit in [width] on a screen [screenWidth] wide.
  static int columnsFor(double width, double screenWidth) {
    final minWidth = screenWidth >= VeloraLayout.mediumBreakpoint
        ? VeloraLayout.minPosterWidthWide
        : VeloraLayout.minPosterWidthCompact;
    final columns = ((width + VeloraSpacing.md) / (minWidth + VeloraSpacing.md))
        .floor();
    return columns < 2 ? 2 : columns;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = columnsFor(constraints.maxWidth, screenWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.md,
          children: [
            for (var start = 0; start < children.length; start += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: VeloraSpacing.md,
                  children: [
                    for (var i = start; i < start + columns; i++)
                      Expanded(
                        child: i < children.length
                            ? children[i]
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
