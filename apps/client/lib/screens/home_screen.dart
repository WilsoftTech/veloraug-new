import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../shell/app_shell.dart';
import '../theme/tokens.dart';
import '../widgets/edition_cards.dart';
import '../widgets/tmdb_attribution.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import 'browse_screen.dart';
import 'filter_screen.dart'
    show IndianMoviesChip, hasIndianMovies, openIndianMovies;
import 'vj_screen.dart';

enum _Phase { loading, ready, failed }

/// How many cards a row on Home shows before See all.
const int rowSize = 12;

/// At most this many VJs get their own row on Home. The rest are on their
/// own pages, through search.
const int maxVjRows = 12;

/// Genre shelves Home offers, in this order, when the catalogue has titles
/// in them. The names are TMDB's, exactly as the catalogue stores them.
const List<String> homeGenres = [
  'Action',
  'Comedy',
  'Adventure',
  'Horror',
  'Science Fiction',
  'Drama',
  'Thriller',
  'Romance',
  'Animation',
];

/// At most this many category shelves: Indian first, then the most used.
const int maxCategoryRows = 6;

/// At most this many genre shelves.
const int maxGenreRows = 5;

/// Secondary shelves are fetched this many at a time, so Home never sends
/// a burst of requests.
const int shelfFetchesAtOnce = 4;

/// A shelf after the first three: a category's, a genre's, a VJ's or a
/// language's.
class _Shelf {
  const _Shelf({
    required this.key,
    required this.title,
    required this.load,
    required this.seeAll,
    this.vj,
  });

  final String key;
  final String title;
  final Future<EditionPage> Function(CatalogueApi api) load;

  /// Opens the shelf's full, paginated list.
  final void Function(BuildContext context) seeAll;
  final VjCard? vj;
}

/// The hero's newest titles, Latest editions, Movies and Series, then
/// shelves for categories, genres, VJs and languages as they load. A shelf that fails or is empty is left out, and
/// never holds up the others.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CatalogueApi? _api;
  _Phase _phase = _Phase.failed;
  CatalogueFailure? _failure;

  /// Each load gets a number, and answers for an older one are dropped.
  int _generation = 0;

  /// Home's hero. Null while it loads; empty when there is nothing to
  /// feature or it failed, and then the welcome panel shows instead.
  List<FeaturedTitle>? _featured = const [];

  /// Categories with titles: they decide the Indian Movies chip and the
  /// category shelves. Empty until they load, or if they fail.
  List<Category> _categories = const [];
  Future<List<Category>> _categoriesLoading = Future.value(const []);

  List<EditionCard> _latest = const [];
  List<EditionCard> _movies = const [];
  List<EditionCard> _series = const [];

  /// Secondary shelves in Home's order. One shows once [_loaded] has its
  /// titles.
  List<_Shelf> _shelves = const [];
  final Map<String, List<EditionCard>> _loaded = {};
  bool _secondaryPending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = CatalogueScope.of(context);
    if (!identical(api, _api)) {
      _api = api;
      // No setState here: the build that follows shows the change.
      _phase = api == null ? _Phase.failed : _Phase.loading;
      _fetch();
    }
  }

  void _retry() {
    setState(() => _phase = _Phase.loading);
    _fetch();
  }

  Future<void> _fetch() async {
    final api = _api;
    if (api == null) return;
    final generation = ++_generation;
    final l = context.l10n;
    bool current() => mounted && generation == _generation;
    _shelves = const [];
    _loaded.clear();
    _latest = _movies = _series = const [];
    _failure = null;
    _featured = null;
    _categories = const [];
    // On its own, like the hero: Indian Movies shows as soon as it's known.
    _categoriesLoading = api.categories().then((categories) {
      if (current()) setState(() => _categories = categories);
      return categories;
    }, onError: (Object _) => <Category>[]);
    // On its own: a failure here leaves the welcome panel, and never holds
    // up the shelves.
    api.featured().then(
      (titles) {
        if (current()) setState(() => _featured = titles);
      },
      onError: (Object _) {
        if (current()) setState(() => _featured = const []);
      },
    );
    Future<void> loadPrimary(EditionKind? kind) async {
      try {
        final page = await api.editions(limit: rowSize, kind: kind);
        if (!current()) return;
        setState(() {
          switch (kind) {
            case null:
              _latest = page.editions;
            case EditionKind.movie:
              _movies = page.editions;
            case EditionKind.series:
              _series = page.editions;
          }
          if (page.editions.isNotEmpty) _phase = _Phase.ready;
        });
      } on CatalogueException catch (error) {
        if (current()) _failure = error.failure;
      }
    }

    await Future.wait([
      loadPrimary(null),
      loadPrimary(EditionKind.movie),
      loadPrimary(EditionKind.series),
    ]);
    if (!current()) return;
    setState(() {
      _secondaryPending = _hasTitles;
      _phase = !_hasTitles && _failure != null ? _Phase.failed : _Phase.ready;
    });
    if (_hasTitles) await _fetchShelves(api, l, current);
  }

  bool get _hasTitles =>
      _latest.isNotEmpty || _movies.isNotEmpty || _series.isNotEmpty;

  /// The lists behind the secondary shelves, then each shelf, a few at a
  /// time. Each list and shelf may fail on its own.
  Future<void> _fetchShelves(
    CatalogueApi api,
    AppLocalizations l,
    bool Function() current,
  ) async {
    Future<List<T>> orNothing<T>(Future<List<T>> list) =>
        list.then((v) => v, onError: (Object _) => <T>[]);
    final genresLoading = orNothing<Genre>(api.genres());
    final vjsLoading = orNothing<VjCard>(api.vjs());
    final languagesLoading = orNothing<Language>(api.languages());
    final categories = await _categoriesLoading;
    final genres = await genresLoading;
    final vjs = await vjsLoading;
    final languages = await languagesLoading;
    if (!current()) return;
    final present = {
      for (final genre in genres)
        if (genre.editions > 0) genre.name,
    };
    final byUse = [
      ...categories.where((c) => c.slug == Category.indianSlug),
      ...categories.where((c) => c.slug != Category.indianSlug),
    ];
    final shelves = <_Shelf>[
      for (final category
          in byUse.where((c) => c.editions > 0).take(maxCategoryRows))
        _Shelf(
          key: 'category:${category.slug}',
          title: category.name,
          load: (api) => api.editions(limit: rowSize, category: category.slug),
          seeAll: (context) => _browse(
            context,
            category.name,
            BrowseFilter(category: category.slug),
          ),
        ),
      for (final name in homeGenres.where(present.contains).take(maxGenreRows))
        _Shelf(
          key: 'genre:$name',
          title: name,
          load: (api) => api.editions(limit: rowSize, genre: name),
          seeAll: (context) =>
              _browse(context, name, BrowseFilter(genre: name)),
        ),
      for (final vj in vjs.take(maxVjRows))
        _Shelf(
          key: 'vj:${vj.slug}',
          title: vj.name,
          vj: vj,
          load: (api) => api.editions(limit: rowSize, vj: vj.slug),
          seeAll: (context) => openVj(context, vj.slug, vj.name),
        ),
      // A row per language once more than one has published editions.
      if (languages.length > 1)
        for (final language in languages)
          _Shelf(
            key: 'language:${language.code}',
            title: l.inLanguage(language.name),
            load: (api) =>
                api.editions(limit: rowSize, language: language.code),
            seeAll: (context) => _browse(
              context,
              l.inLanguage(language.name),
              BrowseFilter(language: language.code),
            ),
          ),
    ];
    setState(() => _shelves = shelves);
    for (var start = 0; start < shelves.length; start += shelfFetchesAtOnce) {
      final batch = shelves.skip(start).take(shelfFetchesAtOnce);
      await Future.wait([
        for (final shelf in batch)
          shelf
              .load(api)
              .then(
                (page) {
                  if (current()) {
                    setState(() => _loaded[shelf.key] = page.editions);
                  }
                },
                onError: (Object _) {
                  if (current()) setState(() => _loaded[shelf.key] = const []);
                },
              ),
      ]);
      if (!current()) return;
    }
    setState(() => _secondaryPending = false);
  }

  static void _browse(BuildContext context, String title, BrowseFilter filter) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(title: title, filter: filter),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final featured = _featured;
    return ScreenBody(
      heading: l.homeHeading,
      intro: l.homeIntro,
      hero: true,
      banner: switch (featured) {
        null => const HeroCarouselSkeleton(),
        [] => null,
        _ => HeroCarousel(titles: featured),
      },
      maxWidth: VeloraLayout.browseWidth,
      children: [
        _Shortcuts(indianMovies: hasIndianMovies(_categories)),
        ...switch (_phase) {
          _Phase.loading => [const EditionGridSkeleton()],
          _Phase.failed when _api == null => [
            EmptyState(
              icon: Icons.cloud_off_outlined,
              title: l.catalogueNotSetUpTitle,
              message: l.catalogueNotSetUpMessage,
            ),
          ],
          _Phase.failed => [
            ErrorState(
              title: l.homeLoadFailed,
              message: catalogueFailureMessage(l, _failure!),
              onRetry: _retry,
            ),
          ],
          _Phase.ready when !_hasTitles => [
            EmptyState(
              icon: Icons.movie_outlined,
              title: l.nothingYetTitle,
              message: l.nothingYetMessage,
            ),
          ],
          _Phase.ready => _ready(context),
        },
      ],
    );
  }

  List<Widget> _ready(BuildContext context) {
    final l = context.l10n;
    return [
      if (_latest.isNotEmpty)
        EditionRow(
          key: const ValueKey('row-latest'),
          title: l.latest,
          editions: _latest,
          onSeeAll: () => _browse(context, l.latest, const BrowseFilter()),
        ),
      if (_movies.isNotEmpty)
        EditionRow(
          key: const ValueKey('row-movies'),
          title: l.movies,
          editions: _movies,
          onSeeAll: () => _browse(
            context,
            l.movies,
            const BrowseFilter(kind: EditionKind.movie),
          ),
        ),
      if (_series.isNotEmpty)
        EditionRow(
          key: const ValueKey('row-series'),
          title: l.series,
          editions: _series,
          onSeeAll: () => _browse(
            context,
            l.series,
            const BrowseFilter(kind: EditionKind.series),
          ),
        ),
      for (final shelf in _shelves)
        if (_loaded[shelf.key] case final editions? when editions.isNotEmpty)
          EditionRow(
            key: ValueKey('row-${shelf.key}'),
            title: shelf.title,
            leading: switch (shelf.vj) {
              final vj? => VjAvatar(name: vj.name, photoUrl: vj.photoUrl),
              null => null,
            },
            editions: editions,
            onSeeAll: () => shelf.seeAll(context),
          ),
      if (_secondaryPending)
        VeloraLoadingRegion(
          label: l.loadingMoreShelves,
          child: const Align(
            alignment: Alignment.centerLeft,
            child: VeloraSkeleton(width: 160, height: 20),
          ),
        ),
      TmdbAttribution(
        editions: [
          ...?_featured?.map((title) => title.card),
          ..._latest,
          ..._movies,
          ..._series,
          ..._loaded.values.expand((e) => e),
        ],
      ),
    ];
  }
}

/// Indian Movies, when there are some, and quick ways to Search and, on
/// Android, Downloads, through the menu's own
/// destinations.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts({required this.indianMovies});

  /// Indian Movies comes first, when there are some.
  final bool indianMovies;

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.maybeOf(context);
    if (shell == null) return const SizedBox.shrink();
    final l = context.l10n;
    return Wrap(
      spacing: VeloraSpacing.xs,
      runSpacing: VeloraSpacing.xs,
      children: [
        if (indianMovies)
          IndianMoviesChip(onPressed: () => openIndianMovies(context)),
        ActionChip(
          avatar: const Icon(Icons.search, size: 18),
          label: Text(l.searchShortcut),
          onPressed: () => shell.select(AppDestination.search),
        ),
        ActionChip(
          avatar: const Icon(Icons.tune, size: 18),
          label: Text(l.filter),
          onPressed: () => shell.select(AppDestination.filter),
        ),
        if (shell.available.contains(AppDestination.downloads))
          ActionChip(
            avatar: const Icon(Icons.download_for_offline_outlined, size: 18),
            label: Text(l.downloads),
            onPressed: () => shell.select(AppDestination.downloads),
          ),
      ],
    );
  }
}
