import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/movie_poster.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';

enum _Phase { loading, ready, failed }

/// The catalogue: published movies, newest first, a page at a time.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CatalogueApi? _api;
  _Phase _phase = _Phase.loading;
  CatalogueFailure? _failure;
  final List<MovieSummary> _movies = [];
  int? _nextOffset;
  bool _loadingMore = false;
  CatalogueFailure? _moreFailure;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = CatalogueScope.of(context);
    if (!identical(api, _api)) {
      _api = api;
      // No setState here: the build that follows shows the change.
      _reset();
      _fetchFirst();
    }
  }

  void _reset() {
    _phase = _api == null ? _Phase.failed : _Phase.loading;
    _failure = null;
    _moreFailure = null;
  }

  void _retry() {
    setState(_reset);
    _fetchFirst();
  }

  Future<void> _fetchFirst() async {
    final api = _api;
    if (api == null) return;
    try {
      final page = await api.list();
      if (!mounted || !identical(api, _api)) return;
      setState(() {
        _movies
          ..clear()
          ..addAll(page.movies);
        _nextOffset = page.nextOffset;
        _phase = _Phase.ready;
      });
    } on CatalogueException catch (error) {
      if (!mounted || !identical(api, _api)) return;
      setState(() {
        _failure = error.failure;
        _phase = _Phase.failed;
      });
    }
  }

  Future<void> _loadMore() async {
    final api = _api;
    final offset = _nextOffset;
    if (api == null || offset == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailure = null;
    });
    try {
      final page = await api.list(offset: offset);
      if (!mounted) return;
      setState(() {
        final seen = {for (final movie in _movies) movie.id};
        _movies.addAll(page.movies.where((movie) => !seen.contains(movie.id)));
        _nextOffset = page.nextOffset;
      });
    } on CatalogueException catch (error) {
      if (!mounted) return;
      setState(() => _moreFailure = error.failure);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      heading: 'Welcome to VeloraUG',
      intro: 'Movies to watch on the web and on Android.',
      hero: true,
      maxWidth: VeloraLayout.browseWidth,
      children: switch (_phase) {
        _Phase.loading => [const MovieGridSkeleton()],
        _Phase.failed when _api == null => [
          const EmptyState(
            icon: Icons.cloud_off_outlined,
            title: "The catalogue isn't set up",
            message:
                "This version of the app has no address for VeloraUG's "
                'service, so it has no movies to show.',
          ),
        ],
        _Phase.failed => [
          ErrorState(
            title: "Couldn't load movies",
            message: catalogueFailureMessage(_failure!),
            onRetry: _retry,
          ),
        ],
        _Phase.ready when _movies.isEmpty => [
          const EmptyState(
            icon: Icons.movie_outlined,
            title: 'No movies yet',
            message: 'New movies will appear here as soon as they are added.',
          ),
        ],
        _Phase.ready => [
          MovieGrid(movies: _movies),
          if (_moreFailure case final failure?)
            Text(catalogueFailureMessage(failure), textAlign: TextAlign.center),
          if (_nextOffset != null)
            Center(
              child: VeloraButton(
                label: 'Show more',
                icon: Icons.expand_more,
                variant: VeloraButtonVariant.secondary,
                isLoading: _loadingMore,
                loadingLabel: 'Loading more…',
                onPressed: _loadMore,
              ),
            ),
        ],
      },
    );
  }
}
