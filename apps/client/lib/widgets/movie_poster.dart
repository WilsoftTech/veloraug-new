import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'movie_card.dart';

/// A poster from TMDB's image server or the media gateway, at the poster's
/// shape. The placeholder shows while it loads, when it fails, and when there
/// is none, so a broken image never appears. Artwork that arrives after the
/// first frame fades in briefly over the placeholder, and appears at once
/// with reduced motion.
class MoviePoster extends StatelessWidget {
  const MoviePoster({super.key, required this.url, this.aspectRatio});

  final String? url;

  /// Defaults to a poster's 2:3.
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    final ratio = aspectRatio ?? VeloraLayout.posterAspectRatio;
    if (url == null) return _placeholder(ratio);
    final fade = VeloraMotion.of(context, VeloraMotion.standard);
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: ratio,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, synchronous) {
            // Already in memory: shown at once, with nothing behind it.
            if (synchronous) return child;
            return Stack(
              fit: StackFit.expand,
              children: [
                _placeholder(ratio),
                AnimatedOpacity(
                  opacity: frame == null ? 0 : 1,
                  duration: fade,
                  curve: VeloraMotion.curve,
                  child: child,
                ),
              ],
            );
          },
          errorBuilder: (context, error, stack) => _placeholder(ratio),
        ),
      ),
    );
  }

  Widget _placeholder(double ratio) => ratio == VeloraLayout.posterAspectRatio
      ? const PosterPlaceholder()
      : AspectRatio(
          aspectRatio: ratio,
          child: const ColoredBox(color: VeloraColors.surfaceOverlay),
        );
}
