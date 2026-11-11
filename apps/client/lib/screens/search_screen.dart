import 'dart:async';

import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/movie_poster.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_search_field.dart';

/// The API searches titles from this many characters.
const int minSearchLength = 2;

/// How long typing must pause before a search is sent.
const Duration searchDelay = Duration(milliseconds: 300);

enum _Phase { idle, loading, ready, failed }

/// Searches VeloraUG's own catalogue by title, as the person types.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _timer;

  /// Each search gets a number, and only the latest one's answer is shown,
  /// so a slow early answer can't replace a newer one.
  int _searchNumber = 0;
  String _query = '';
  _Phase _phase = _Phase.idle;
  CatalogueFailure? _failure;
  List<MovieSummary> _movies = const [];
  int? _nextOffset;
  bool _loadingMore = false;

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String text) {
    _timer?.cancel();
    final query = text.trim();
    if (query.length < minSearchLength) {
      _searchNumber++;
      setState(() {
        _query = query;
        _phase = _Phase.idle;
        _movies = const [];
      });
      return;
    }
    _timer = Timer(searchDelay, () => _search(query));
  }

  void _submitted(String text) {
    _timer?.cancel();
    final query = text.trim();
    if (query.length >= minSearchLength) _search(query);
  }

  Future<void> _search(String query) async {
    final api = CatalogueScope.of(context);
    final number = ++_searchNumber;
    setState(() {
      _query = query;
      _phase = _Phase.loading;
    });
    if (api == null) {
      setState(() {
        _phase = _Phase.failed;
        _failure = CatalogueFailure.unreachable;
      });
      return;
    }
    try {
      final page = await api.list(query: query);
      if (!mounted || number != _searchNumber) return;
      setState(() {
        _movies = page.movies;
        _nextOffset = page.nextOffset;
        _phase = _Phase.ready;
      });
    } on CatalogueException catch (error) {
      if (!mounted || number != _searchNumber) return;
      setState(() {
        _failure = error.failure;
        _phase = _Phase.failed;
      });
    }
  }

  Future<void> _loadMore() async {
    final api = CatalogueScope.of(context);
    final offset = _nextOffset;
    final number = _searchNumber;
    if (api == null || offset == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await api.list(query: _query, offset: offset);
      if (!mounted || number != _searchNumber) return;
      setState(() {
        final seen = {for (final movie in _movies) movie.id};
        _movies = [
          ..._movies,
          ...page.movies.where((movie) => !seen.contains(movie.id)),
        ];
        _nextOffset = page.nextOffset;
      });
    } on CatalogueException {
      // The button stays, so the person can try again.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      heading: 'Search',
      maxWidth: VeloraLayout.browseWidth,
      children: [
        VeloraSearchField(
          controller: _controller,
          onChanged: _changed,
          onSubmitted: _submitted,
        ),
        ...switch (_phase) {
          _Phase.idle => [
            const EmptyState(
              icon: Icons.manage_search,
              title: 'Find a movie',
              message:
                  'Type at least $minSearchLength letters of a title to '
                  "search VeloraUG's movies.",
            ),
          ],
          _Phase.loading => [const MovieGridSkeleton(count: 4)],
          _Phase.failed => [
            ErrorState(
              title: "Couldn't search",
              message: catalogueFailureMessage(_failure!),
              onRetry: () => _search(_query),
            ),
          ],
          _Phase.ready when _movies.isEmpty => [
            EmptyState(
              icon: Icons.search_off,
              title: 'No movies match',
              message: 'Nothing in VeloraUG has "$_query" in its title.',
            ),
          ],
          _Phase.ready => [
            Semantics(
              liveRegion: true,
              child: Text(
                _nextOffset == null
                    ? '${_movies.length} '
                          '${_movies.length == 1 ? 'movie' : 'movies'} '
                          'for "$_query"'
                    : 'Movies for "$_query"',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            MovieGrid(movies: _movies),
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
      ],
    );
  }
}
