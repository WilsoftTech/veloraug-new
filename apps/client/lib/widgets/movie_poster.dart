import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'movie_card.dart';

/// A poster from TMDB's image server or the media gateway, at the poster's
/// shape. The placeholder shows while it loads, when it fails, and when there
/// is none, so a broken image never appears.
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
    return ExcludeSemantics(
      child: AspectRatio(
        aspectRatio: ratio,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : _placeholder(ratio),
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
