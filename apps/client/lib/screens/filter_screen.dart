import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';
import 'browse_screen.dart';

/// One list of choices for the filter, loaded from the catalogue.
class _Options<T> {
  List<T>? items;
  CatalogueFailure? failure;

  bool get loading => items == null && failure == null;
}

/// Narrows the catalogue by type, genre, VJ and language, then shows the
/// matching titles with the server doing the filtering, a page at a time.
/// Every choice comes from the catalogue itself, so only filters that can
/// match something are offered. The choices stay when the person comes back.
class FilterScreen extends StatefulWidget {
  const FilterScreen({super.key});

  @override
  State<FilterScreen> createState() => _FilterScreenState();
}

class _FilterScreenState extends State<FilterScreen> {
  CatalogueApi? _api;

  /// Each load gets a number; an answer for an older one is ignored.
  int _generation = 0;

  final _genres = _Options<Genre>();
  final _vjs = _Options<VjCard>();
  final _languages = _Options<Language>();

  EditionKind? _kind;
  String? _genre;
  String? _vj;
  String? _language;

  bool get _anyChosen =>
      _kind != null || _genre != null || _vj != null || _language != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = CatalogueScope.of(context);
    if (!identical(api, _api)) {
      _api = api;
      _loadAll();
    }
  }

  void _loadAll() {
    final generation = ++_generation;
    _load(_genres, generation, (api) => api.genres());
    _load(_vjs, generation, (api) => api.vjs());
    _load(_languages, generation, (api) => api.languages());
  }

  Future<void> _load<T>(
    _Options<T> options,
    int generation,
    Future<List<T>> Function(CatalogueApi api) fetch,
  ) async {
    final api = _api;
    void update(VoidCallback change) {
      if (!mounted || generation != _generation) return;
      setState(change);
    }

    update(() {
      options.items = null;
      options.failure = api == null ? CatalogueFailure.unreachable : null;
    });
    if (api == null) return;
    try {
      final items = await fetch(api);
      update(() {
        options.items = items;
        _dropMissingChoices();
      });
    } on CatalogueException catch (error) {
      update(() => options.failure = error.failure);
    }
  }

  /// A choice that is no longer in the catalogue is cleared, so a filter
  /// never asks for something that can't match.
  void _dropMissingChoices() {
    if (_genres.items case final genres?
        when !genres.any((g) => g.name == _genre)) {
      _genre = null;
    }
    if (_vjs.items case final vjs? when !vjs.any((v) => v.slug == _vj)) {
      _vj = null;
    }
    if (_languages.items case final languages?
        when !languages.any((l) => l.code == _language)) {
      _language = null;
    }
  }

  void _clear() => setState(() {
    _kind = null;
    _genre = null;
    _vj = null;
    _language = null;
  });

  String _resultsTitle(AppLocalizations l) {
    final parts = [
      switch (_kind) {
        EditionKind.movie => l.movies,
        EditionKind.series => l.series,
        null => null,
      },
      ?_genre,
      if (_vj case final slug?)
        _vjs.items?.where((v) => v.slug == slug).firstOrNull?.name,
      if (_language case final code?)
        _languages.items?.where((x) => x.code == code).firstOrNull?.name,
    ].nonNulls;
    return parts.isEmpty ? l.filterAllTitles : parts.join(' · ');
  }

  void _showResults() {
    final l = context.l10n;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BrowseScreen(
          title: _resultsTitle(l),
          filter: BrowseFilter(
            kind: _kind,
            genre: _genre,
            vj: _vj,
            language: _language,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (_api == null) {
      return ScreenBody(
        heading: l.filterHeading,
        children: [
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: l.catalogueNotSetUpTitle,
            message: l.catalogueNotSetUpMessage,
          ),
        ],
      );
    }
    final languages = _languages.items;
    return ScreenBody(
      heading: l.filterHeading,
      intro: l.filterIntro,
      children: [
        _Section(
          title: l.filterType,
          child: SegmentedButton<EditionKind?>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: null, label: Text(l.filterAll)),
              ButtonSegment(value: EditionKind.movie, label: Text(l.movies)),
              ButtonSegment(value: EditionKind.series, label: Text(l.series)),
            ],
            selected: {_kind},
            onSelectionChanged: (chosen) =>
                setState(() => _kind = chosen.first),
          ),
        ),
        _Section(
          title: l.filterGenre,
          child: _OptionsView(
            options: _genres,
            label: l.filterGenre,
            onRetry: () => _load(_genres, _generation, (api) => api.genres()),
            builder: (genres) => _Chips(
              anyLabel: l.filterAnyGenre,
              selected: _genre,
              choices: [for (final g in genres) (g.name, g.name)],
              onSelected: (value) => setState(() => _genre = value),
            ),
          ),
        ),
        _Section(
          title: l.filterVj,
          child: _OptionsView(
            options: _vjs,
            label: l.filterVj,
            onRetry: () => _load(_vjs, _generation, (api) => api.vjs()),
            builder: (vjs) => _Chips(
              anyLabel: l.filterAnyVj,
              selected: _vj,
              choices: [for (final vj in vjs) (vj.slug, vj.name)],
              onSelected: (value) => setState(() => _vj = value),
            ),
          ),
        ),
        // Only when there is more than one language to choose between.
        if (_languages.loading ||
            _languages.failure != null ||
            (languages != null && languages.length > 1))
          _Section(
            title: l.filterLanguage,
            child: _OptionsView(
              options: _languages,
              label: l.filterLanguage,
              onRetry: () =>
                  _load(_languages, _generation, (api) => api.languages()),
              builder: (languages) => _Chips(
                anyLabel: l.filterAnyLanguage,
                selected: _language,
                choices: [for (final x in languages) (x.code, x.name)],
                onSelected: (value) => setState(() => _language = value),
              ),
            ),
          ),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.sm,
          alignment: WrapAlignment.end,
          children: [
            VeloraButton(
              label: l.filterClear,
              icon: Icons.clear_all,
              variant: VeloraButtonVariant.secondary,
              onPressed: _anyChosen ? _clear : null,
            ),
            VeloraButton(
              label: l.filterShowResults,
              icon: Icons.grid_view,
              onPressed: _showResults,
            ),
          ],
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: VeloraSpacing.sm,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        child,
      ],
    );
  }
}

/// Loading, a failure with Try again, or the choices.
class _OptionsView<T> extends StatelessWidget {
  const _OptionsView({
    required this.options,
    required this.label,
    required this.onRetry,
    required this.builder,
  });

  final _Options<T> options;
  final String label;
  final VoidCallback onRetry;
  final Widget Function(List<T> items) builder;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    if (options.failure case final failure?) {
      return ErrorState(
        title: l.filterOptionsFailed(label),
        message: catalogueFailureMessage(l, failure),
        onRetry: onRetry,
      );
    }
    final items = options.items;
    if (items == null) {
      return VeloraLoadingRegion(
        label: l.filterOptionsLoading(label),
        child: const Wrap(
          spacing: VeloraSpacing.xs,
          runSpacing: VeloraSpacing.xs,
          children: [
            VeloraSkeleton(width: 72, height: 32),
            VeloraSkeleton(width: 96, height: 32),
            VeloraSkeleton(width: 64, height: 32),
          ],
        ),
      );
    }
    return builder(items);
  }
}

/// One choice at a time, with "any" first.
class _Chips extends StatelessWidget {
  const _Chips({
    required this.anyLabel,
    required this.selected,
    required this.choices,
    required this.onSelected,
  });

  final String anyLabel;
  final String? selected;

  /// Each choice's value and label.
  final List<(String, String)> choices;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: VeloraSpacing.xs,
      runSpacing: VeloraSpacing.xs,
      children: [
        ChoiceChip(
          label: Text(anyLabel),
          selected: selected == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final (value, label) in choices)
          ChoiceChip(
            key: ValueKey('choice-$value'),
            label: Text(label),
            selected: selected == value,
            onSelected: (on) => onSelected(on ? value : null),
          ),
      ],
    );
  }
}
