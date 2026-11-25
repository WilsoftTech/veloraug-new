import 'package:flutter/material.dart';

import '../api/account_api.dart';
import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../screens/edition_screen.dart' show formatRuntime;
import '../theme/palette.dart';
import '../theme/tokens.dart';
import 'movie_card.dart';
import 'movie_poster.dart';

/// One episode of a series: a 16:9 thumbnail with its number, "3 · The
/// Crown", its running time or how much is left, a bar for how far the
/// viewer got, and its buttons.
///
/// The buttons sit at the end of a wide row, and under the text on a phone
/// or with large text, so they never squeeze the title. The thumbnail plays
/// the episode when [onPlay] is given; it's a shortcut for the pointer, so
/// keyboards and screen readers use the Play button instead.
class EpisodeRow extends StatelessWidget {
  const EpisodeRow({
    super.key,
    required this.episode,
    required this.actions,
    this.artworkUrl,
    this.progress,
    this.onPlay,
  });

  final Episode episode;

  /// The series' backdrop: there are no pictures of each episode yet.
  final String? artworkUrl;

  /// How far the viewer got, when signed in and they've played it.
  final WatchProgress? progress;

  /// Play, Download and Watch List, or a badge saying why it can't play.
  final List<Widget> actions;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final palette = VeloraPalette.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final runtime = episode.runtimeMinutes;
    final progress = this.progress;
    final fraction = progress?.fraction(runtime);
    final title = switch (episode.title) {
      final name? => l.episodeRowTitle(episode.episode, name),
      null => l.episodeNumber(episode.episode),
    };
    final String? meta = switch ((progress, runtime)) {
      (WatchProgress(finished: true), _) => l.episodeWatched,
      (WatchProgress(seconds: final seconds?), final minutes?) => l.minutesLeft(
        (minutes - seconds ~/ 60).clamp(1, minutes),
      ),
      (_, final minutes?) => formatRuntime(l, minutes),
      _ => null,
    };

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: VeloraSpacing.xxs,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        ?switch (meta) {
          final meta? => Text(meta, style: muted),
          null => null,
        },
        if (fraction != null)
          Padding(
            padding: const EdgeInsets.only(top: VeloraSpacing.xxs),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(VeloraRadii.sm),
              child: LinearProgressIndicator(
                key: ValueKey('progress-${episode.itemId}'),
                value: fraction,
                minHeight: VeloraLayout.progressBarHeight,
                color: palette.accentText,
                backgroundColor: VeloraColors.surfaceOverlay,
                semanticsLabel: l.percentWatched((fraction * 100).round()),
              ),
            ),
          ),
      ],
    );

    final buttons = Wrap(
      spacing: VeloraSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final wide =
                constraints.maxWidth >= VeloraLayout.mediumBreakpoint &&
                scale <= 1.3;
            // Narrower than a medium screen, or with large text, the buttons
            // go under the text. With less than a thumbnail's width left
            // beside the thumbnail, the text goes under it too.
            final stacked =
                constraints.maxWidth -
                    VeloraLayout.episodeThumbWidth -
                    VeloraSpacing.sm <
                VeloraLayout.episodeThumbWidth * scale;
            final thumb = _Thumbnail(
              number: episode.episode,
              url: artworkUrl,
              onPlay: onPlay,
            );
            if (wide) {
              return Row(
                spacing: VeloraSpacing.sm,
                children: [
                  thumb,
                  Expanded(child: info),
                  buttons,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: VeloraSpacing.xs,
              children: [
                if (stacked) ...[
                  thumb,
                  info,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: VeloraSpacing.sm,
                    children: [
                      thumb,
                      Expanded(child: info),
                    ],
                  ),
                buttons,
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The series' backdrop at 16:9 with the episode's number on it. With a
/// pointer over it, a play mark shows, and a click plays.
class _Thumbnail extends StatefulWidget {
  const _Thumbnail({required this.number, this.url, this.onPlay});

  final int number;
  final String? url;
  final VoidCallback? onPlay;

  @override
  State<_Thumbnail> createState() => _ThumbnailState();
}

class _ThumbnailState extends State<_Thumbnail> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final onPlay = widget.onPlay;
    final fade = VeloraMotion.of(context, VeloraMotion.fast);
    return SizedBox(
      width: VeloraLayout.episodeThumbWidth,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VeloraRadii.sm),
        child: Stack(
          children: [
            MoviePoster(
              url: widget.url,
              aspectRatio: VeloraLayout.backdropAspectRatio,
            ),
            Positioned(
              left: VeloraSpacing.xxs,
              bottom: VeloraSpacing.xxs,
              child: ExcludeSemantics(
                child: PosterChip(
                  child: Text(
                    l.episodeChip(widget.number),
                    style: PosterChip.textStyle(context),
                  ),
                ),
              ),
            ),
            if (onPlay != null)
              Positioned.fill(
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    // The Play button is the one keyboards and screen
                    // readers use.
                    canRequestFocus: false,
                    excludeFromSemantics: true,
                    onTap: onPlay,
                    onHover: (value) => setState(() => _hovered = value),
                    child: AnimatedOpacity(
                      opacity: _hovered ? 1 : 0,
                      duration: fade,
                      curve: VeloraMotion.curve,
                      child: const ColoredBox(
                        color: VeloraColors.scrimHeavy,
                        child: Center(
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: VeloraColors.onChip,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
