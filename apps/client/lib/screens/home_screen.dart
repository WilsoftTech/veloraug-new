import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/edition_cards.dart';
import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';
import 'browse_screen.dart';
import 'vj_screen.dart';

enum _Phase { loading, ready, failed }

/// How many cards a row on Home shows before See all.
const int rowSize = 12;

/// At most this many VJs get their own row on Home. The rest are on their
/// own pages, through search.
const int maxVjRows = 12;

class _VjRow {
  const _VjRow(this.vj, this.editions);

  final VjCard vj;
  final List<EditionCard> editions;
}

class _LanguageRow {
  const _LanguageRow(this.language, this.editions);

  final Language language;
  final List<EditionCard> editions;
}

class _Home {
  const _Home({
    required this.latest,
    required this.movies,
    required this.series,
    required this.vjs,
    required this.languages,
  });

  final List<EditionCard> latest;
  final List<EditionCard> movies;
  final List<EditionCard> series;
  final List<_VjRow> vjs;
  final List<_LanguageRow> languages;
}

/// Latest editions, Movies and Series, a row per VJ, and a row per language
/// once more than one language has published editions.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  CatalogueApi? _api;
  _Phase _phase = _Phase.loading;
  CatalogueFailure? _failure;
  _Home? _home;

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
    try {
      final first = await Future.wait([
        api.editions(limit: rowSize),
        api.editions(limit: rowSize, kind: EditionKind.movie),
        api.editions(limit: rowSize, kind: EditionKind.series),
      ]);
      final lists = await Future.wait<List<Object>>([
        api.vjs(),
        api.languages(),
      ]);
      final vjs = lists[0] as List<VjCard>;
      final languages = lists[1] as List<Language>;
      final shownVjs = vjs.take(maxVjRows).toList();
      final shownLanguages = languages.length > 1 ? languages : <Language>[];
      final rows = await Future.wait([
        for (final vj in shownVjs) api.editions(limit: rowSize, vj: vj.slug),
        for (final language in shownLanguages)
          api.editions(limit: rowSize, language: language.code),
      ]);
      if (!mounted || !identical(api, _api)) return;
      setState(() {
        _home = _Home(
          latest: first[0].editions,
          movies: first[1].editions,
          series: first[2].editions,
          vjs: [
            for (final (i, vj) in shownVjs.indexed)
              if (rows[i].editions.isNotEmpty) _VjRow(vj, rows[i].editions),
          ],
          languages: [
            for (final (i, language) in shownLanguages.indexed)
              if (rows[shownVjs.length + i].editions.isNotEmpty)
                _LanguageRow(language, rows[shownVjs.length + i].editions),
          ],
        );
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

  void _browse(String title, BrowseFilter filter) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(title: title, filter: filter),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final home = _home;
    return ScreenBody(
      heading: l.homeHeading,
      intro: l.homeIntro,
      hero: true,
      maxWidth: VeloraLayout.browseWidth,
      children: switch (_phase) {
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
        _Phase.ready when home!.latest.isEmpty => [
          EmptyState(
            icon: Icons.movie_outlined,
            title: l.nothingYetTitle,
            message: l.nothingYetMessage,
          ),
        ],
        _Phase.ready => [
          EditionRow(
            title: l.latest,
            editions: home!.latest,
            onSeeAll: () => _browse(l.latest, const BrowseFilter()),
          ),
          if (home.movies.isNotEmpty)
            EditionRow(
              title: l.movies,
              editions: home.movies,
              onSeeAll: () => _browse(
                l.movies,
                const BrowseFilter(kind: EditionKind.movie),
              ),
            ),
          if (home.series.isNotEmpty)
            EditionRow(
              title: l.series,
              editions: home.series,
              onSeeAll: () => _browse(
                l.series,
                const BrowseFilter(kind: EditionKind.series),
              ),
            ),
          for (final row in home.vjs)
            EditionRow(
              title: row.vj.name,
              leading: VjAvatar(name: row.vj.name, photoUrl: row.vj.photoUrl),
              editions: row.editions,
              onSeeAll: () => openVj(context, row.vj.slug, row.vj.name),
            ),
          for (final row in home.languages)
            EditionRow(
              title: l.inLanguage(row.language.name),
              editions: row.editions,
              onSeeAll: () => _browse(
                l.inLanguage(row.language.name),
                BrowseFilter(language: row.language.code),
              ),
            ),
        ],
      },
    );
  }
}
