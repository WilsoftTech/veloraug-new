import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../screens/movie_detail_screen.dart';
import '../theme/tokens.dart';
import 'loading_placeholder.dart';
import 'movie_card.dart';

/// A poster from TMDB's image server, at the poster's shape. The placeholder
/// shows while it loads, when it fails, and when there is none, so a broken
/// image never appears.
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

/// Movie cards in a grid. Tapping one opens its detail screen.
class MovieGrid extends StatelessWidget {
  const MovieGrid({super.key, required this.movies});

  final List<MovieSummary> movies;

  @override
  Widget build(BuildContext context) {
    return MovieCardGrid(
      children: [
        for (final movie in movies)
          MovieCard(
            key: ValueKey(movie.id),
            title: movie.title,
            subtitle: movie.year?.toString(),
            artwork: MoviePoster(url: movie.posterUrl),
            onTap: () => openMovie(context, movie),
          ),
      ],
    );
  }
}

/// Opens a movie's detail screen.
void openMovie(BuildContext context, MovieSummary movie) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MovieDetailScreen(movieId: movie.id, title: movie.title),
    ),
  );
}

/// Placeholder cards while a page loads.
class MovieGridSkeleton extends StatelessWidget {
  const MovieGridSkeleton({super.key, this.count = 6});

  final int count;

  @override
  Widget build(BuildContext context) {
    return VeloraLoadingRegion(
      label: 'Loading movies',
      child: MovieCardGrid(
        children: [for (var i = 0; i < count; i++) const MovieCardSkeleton()],
      ),
    );
  }
}
