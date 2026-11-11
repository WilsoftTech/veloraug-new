import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/movie_poster.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';

/// "2 h 49 min", "45 min" or "2 h".
String formatRuntime(int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return '$rest min';
  if (rest == 0) return '$hours h';
  return '$hours h $rest min';
}

enum _Phase { loading, ready, failed }

/// One movie: its artwork, details and description. Watching comes in a
/// later milestone, so the button is shown disabled.
class MovieDetailScreen extends StatefulWidget {
  const MovieDetailScreen({
    super.key,
    required this.movieId,
    required this.title,
  });

  final String movieId;

  /// Shown in the bar while the details load.
  final String title;

  @override
  State<MovieDetailScreen> createState() => _MovieDetailScreenState();
}

class _MovieDetailScreenState extends State<MovieDetailScreen> {
  _Phase _phase = _Phase.loading;
  MovieDetail? _movie;
  CatalogueFailure? _failure;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      // No setState here: the first build shows the loading state.
      _fetch();
    }
  }

  void _retry() {
    setState(() => _phase = _Phase.loading);
    _fetch();
  }

  Future<void> _fetch() async {
    final api = CatalogueScope.of(context);
    if (api == null) {
      _phase = _Phase.failed;
      _failure = CatalogueFailure.unreachable;
      if (mounted) setState(() {});
      return;
    }
    try {
      final movie = await api.movie(widget.movieId);
      if (!mounted) return;
      setState(() {
        _movie = movie;
        _phase = _Phase.ready;
      });
    } on CatalogueException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.failure;
        _phase = _Phase.failed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final movie = _movie;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          movie?.title ?? widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => const Center(
            child: VeloraLoadingRegion(
              label: 'Loading the movie',
              child: VeloraSpinner(size: 32),
            ),
          ),
          _Phase.failed => _Failed(failure: _failure!, onRetry: _retry),
          _Phase.ready => _Details(movie: movie!),
        },
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.failure, required this.onRetry});

  final CatalogueFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final notFound = failure == CatalogueFailure.notFound;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(
        horizontal: VeloraLayout.gutterFor(width),
        vertical: VeloraSpacing.lg,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: VeloraLayout.readingWidth,
          ),
          child: notFound
              ? EmptyState(
                  icon: Icons.movie_filter_outlined,
                  title: "This movie isn't available",
                  message:
                      'It may have been removed from VeloraUG. Go back to '
                      'find something else to watch.',
                  action: VeloraButton(
                    label: 'Back',
                    icon: Icons.arrow_back,
                    variant: VeloraButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                )
              : ErrorState(
                  title: "Couldn't load this movie",
                  message: catalogueFailureMessage(failure),
                  onRetry: onRetry,
                ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.movie});

  final MovieDetail movie;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= VeloraLayout.mediumBreakpoint;
    final runtime = movie.runtimeMinutes;
    final facts = [
      if (movie.year != null) '${movie.year}',
      if (runtime != null) formatRuntime(runtime),
    ];
    final overview = movie.overview;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: VeloraSpacing.sm,
      children: [
        Semantics(
          header: true,
          child: Text(movie.title, style: theme.textTheme.headlineMedium),
        ),
        if (facts.isNotEmpty)
          Text(
            facts.join(' · '),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (movie.genres.isNotEmpty)
          Wrap(
            spacing: VeloraSpacing.xs,
            runSpacing: VeloraSpacing.xs,
            children: [
              for (final genre in movie.genres)
                StatusBadge(label: genre, tone: StatusTone.neutral),
            ],
          ),
        const SizedBox(height: VeloraSpacing.xs),
        const _WatchButton(),
        if (overview != null) ...[
          const SizedBox(height: VeloraSpacing.xs),
          Text(overview, style: theme.textTheme.bodyLarge),
        ],
      ],
    );

    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(VeloraRadii.md),
      child: MoviePoster(url: movie.posterUrl),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (movie.backdropUrl != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: MoviePoster(url: movie.backdropUrl, aspectRatio: 16 / 9),
            ),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: VeloraLayout.gutterFor(width),
              vertical: VeloraSpacing.lg,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: VeloraLayout.readingWidth + 240,
                ),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: VeloraSpacing.lg,
                        children: [
                          SizedBox(width: 220, child: poster),
                          Expanded(child: info),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: VeloraSpacing.lg,
                        children: [
                          Center(child: SizedBox(width: 180, child: poster)),
                          info,
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Watching needs protected playback, from Milestone 8.
class _WatchButton extends StatelessWidget {
  const _WatchButton();

  @override
  Widget build(BuildContext context) {
    return const Wrap(
      spacing: VeloraSpacing.sm,
      runSpacing: VeloraSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        VeloraButton(label: 'Watch', icon: Icons.play_arrow, onPressed: null),
        StatusBadge(label: 'Coming soon', tone: StatusTone.info),
      ],
    );
  }
}
