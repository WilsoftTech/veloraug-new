import 'package:flutter/material.dart';

import '../api/account_api.dart';
import '../api/catalogue_api.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import 'edition_cards.dart';
import 'empty_state.dart';
import 'loading_placeholder.dart';
import 'movie_card.dart';

/// A rail needs at least this many titles to show. The API checks too.
const int minRailTitles = 3;

/// The chips above the rails. Each shows some rails; All shows every one.
enum RailFilter { all, sameVj, sameGenre, topRated, newest }

const Map<RailFilter, Set<String>> _railsFor = {
  RailFilter.sameVj: {'vj'},
  RailFilter.sameGenre: {'recommended', 'because'},
  RailFilter.topRated: {'top_rated'},
  RailFilter.newest: {'recent', 'new_episodes'},
};

/// "More like this" on an edition's page: rails of titles from this
/// catalogue, loaded after the page shows, with chips to narrow them.
/// Signed in, Because you watched joins them. Shows nothing when no rail has
/// enough titles.
class DiscoveryRails extends StatefulWidget {
  const DiscoveryRails({super.key, required this.edition});

  final EditionDetail edition;

  @override
  State<DiscoveryRails> createState() => _DiscoveryRailsState();
}

enum _Phase { loading, ready, failed }

class _DiscoveryRailsState extends State<DiscoveryRails> {
  _Phase _phase = _Phase.loading;
  CatalogueFailure? _failure;
  List<EditionRail> _rails = const [];
  BecauseYouWatched? _because;
  RailFilter _filter = RailFilter.all;
  bool _requested = false;
  String? _becauseFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      _load();
    }
    _loadBecause();
  }

  Future<void> _load() async {
    final api = CatalogueScope.of(context);
    if (api == null) {
      setState(() => _phase = _Phase.ready);
      return;
    }
    if (_phase != _Phase.loading) setState(() => _phase = _Phase.loading);
    try {
      final rails = await api.rails(widget.edition.id);
      if (!mounted) return;
      setState(() {
        _rails = rails;
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

  /// Only signed in: the viewer's history is theirs alone. A failure just
  /// leaves the rail out.
  Future<void> _loadBecause() async {
    final auth = AuthScope.of(context);
    final user = auth?.status == AuthStatus.signedIn ? auth?.accountKey : null;
    if (user == _becauseFor) return;
    _becauseFor = user;
    final api = accountApiOf(context);
    if (user == null || api == null) {
      if (_because != null) setState(() => _because = null);
      return;
    }
    try {
      final because = await api.becauseYouWatched(widget.edition.id);
      if (mounted && _becauseFor == user) setState(() => _because = because);
    } on AccountException {
      // Left out.
    }
  }

  /// Every rail with enough titles, in page order: Because you watched
  /// follows Recommended.
  List<EditionRail> get _all {
    final because = _because;
    final rails = <EditionRail>[];
    for (final rail in _rails) {
      if (rail.editions.length >= minRailTitles) rails.add(rail);
      if (rail.key == 'recommended' && because != null) {
        rails.add(EditionRail(key: 'because', editions: because.editions));
      }
    }
    if (because != null && !rails.any((rail) => rail.key == 'because')) {
      rails.add(EditionRail(key: 'because', editions: because.editions));
    }
    return [
      for (final rail in rails)
        if (rail.editions.length >= minRailTitles) rail,
    ];
  }

  String _title(AppLocalizations l, EditionRail rail) {
    final series = widget.edition.kind == EditionKind.series;
    final vj = widget.edition.card.vjName;
    return switch (rail.key) {
      'vj' => vj == null ? l.railMoreFromThisVj : l.railMoreFromVj(vj),
      'recommended' => series ? l.railRecommendedSeries : l.railRecommended,
      'popular' => series ? l.railTrendingSeries : l.railMostPopular,
      'top_rated' => l.railTopRated,
      'recent' => l.railRecentlyAdded,
      'new_episodes' => l.railNewEpisodes,
      'because' => l.railBecauseYouWatched(_because?.watchedTitle ?? ''),
      _ => '',
    };
  }

  String _chipLabel(AppLocalizations l, RailFilter filter) => switch (filter) {
    RailFilter.all => l.railsAll,
    RailFilter.sameVj => l.railsSameVj,
    RailFilter.sameGenre => l.railsSameGenre,
    RailFilter.topRated => l.railsTopRated,
    RailFilter.newest => l.railsNew,
  };

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final heading = Semantics(
      header: true,
      child: Text(l.railsHeading, style: theme.textTheme.headlineSmall),
    );
    switch (_phase) {
      case _Phase.loading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.md,
          children: [heading, const RailSkeleton()],
        );
      case _Phase.failed:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.md,
          children: [
            heading,
            ErrorState(
              title: l.railsLoadFailed,
              message: catalogueFailureMessage(l, _failure!),
              onRetry: _load,
            ),
          ],
        );
      case _Phase.ready:
        break;
    }
    final all = _all;
    if (all.isEmpty) return const SizedBox.shrink();
    final present = {for (final rail in all) rail.key};
    final filters = [
      RailFilter.all,
      for (final filter in RailFilter.values.skip(1))
        if (_railsFor[filter]!.any(present.contains)) filter,
    ];
    // A filter whose rails have gone, such as after signing out, falls back.
    final filter = filters.contains(_filter) ? _filter : RailFilter.all;
    final shown = filter == RailFilter.all
        ? all
        : [
            for (final rail in all)
              if (_railsFor[filter]!.contains(rail.key)) rail,
          ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.lg,
      children: [
        heading,
        // Chips only help with more than one rail to choose from.
        if (all.length > 1)
          Semantics(
            label: l.railsFilters,
            container: true,
            child: Wrap(
              spacing: VeloraSpacing.xs,
              runSpacing: VeloraSpacing.xs,
              children: [
                for (final option in filters)
                  ChoiceChip(
                    key: ValueKey('rail-filter-${option.name}'),
                    label: Text(_chipLabel(l, option)),
                    selected: option == filter,
                    onSelected: (_) => setState(() => _filter = option),
                  ),
              ],
            ),
          ),
        for (final rail in shown)
          EditionRow(
            key: ValueKey('rail-${rail.key}'),
            title: _title(l, rail),
            editions: rail.editions,
          ),
      ],
    );
  }
}

/// A rail-shaped placeholder: a heading and a row of cards.
class RailSkeleton extends StatelessWidget {
  const RailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    return VeloraLoadingRegion(
      label: context.l10n.loadingTitles,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = EditionRow.cardWidthFor(
            constraints.maxWidth,
            screenWidth,
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.sm,
            children: [
              const VeloraSkeleton(width: 160, height: 20),
              ClipRect(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: VeloraSpacing.sm,
                    children: [
                      for (var i = 0; i < 5; i++)
                        SizedBox(
                          width: width,
                          child: const MovieCardSkeleton(),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
