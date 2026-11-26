import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/edition_cards.dart';
import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';

/// Which published editions a list shows.
class BrowseFilter {
  const BrowseFilter({
    this.kind,
    this.vj,
    this.language,
    this.genre,
    this.category,
  });

  final EditionKind? kind;

  /// A VJ's slug.
  final String? vj;
  final String? language;
  final String? genre;

  /// A category's slug.
  final String? category;
}

enum _Phase { loading, ready, failed }

/// Every edition that matches a filter, newest first, a page at a time.
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key, required this.title, required this.filter});

  final String title;
  final BrowseFilter filter;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  _Phase _phase = _Phase.loading;
  CatalogueFailure? _failure;
  final List<EditionCard> _editions = [];
  int? _nextOffset;
  bool _loadingMore = false;
  CatalogueFailure? _moreFailure;
  bool _started = false;

  /// Starting again from the first page gets a new number, so a page asked
  /// for before can't land in the new list.
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _fetch(0);
    }
  }

  Future<void> _fetch(int offset) async {
    final api = CatalogueScope.of(context);
    final filter = widget.filter;
    if (offset == 0) {
      _generation++;
      _editions.clear();
      _nextOffset = null;
      _moreFailure = null;
    }
    final generation = _generation;
    if (api == null) {
      setState(() {
        _failure = CatalogueFailure.unreachable;
        _phase = _Phase.failed;
      });
      return;
    }
    if (offset > 0) {
      setState(() {
        _loadingMore = true;
        _moreFailure = null;
      });
    }
    try {
      final page = await api.editions(
        offset: offset,
        kind: filter.kind,
        vj: filter.vj,
        language: filter.language,
        genre: filter.genre,
        category: filter.category,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final seen = {for (final edition in _editions) edition.id};
        _editions.addAll(page.editions.where((e) => !seen.contains(e.id)));
        _nextOffset = page.nextOffset;
        _phase = _Phase.ready;
      });
    } on CatalogueException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        if (offset > 0) {
          _moreFailure = error.failure;
        } else {
          _failure = error.failure;
          _phase = _Phase.failed;
        }
      });
    } finally {
      if (mounted && _loadingMore) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: ScreenBody(
          heading: widget.title,
          maxWidth: VeloraLayout.browseWidth,
          children: switch (_phase) {
            _Phase.loading => [const EditionGridSkeleton()],
            _Phase.failed => [
              ErrorState(
                title: l.listLoadFailed,
                message: catalogueFailureMessage(l, _failure!),
                onRetry: () {
                  setState(() => _phase = _Phase.loading);
                  _fetch(0);
                },
              ),
            ],
            _Phase.ready when _editions.isEmpty => [
              EmptyState(
                icon: Icons.movie_outlined,
                title: l.nothingHereTitle,
                message: l.nothingYetMessage,
              ),
            ],
            _Phase.ready => [
              EditionGrid(editions: _editions),
              if (_moreFailure case final failure?)
                Text(
                  catalogueFailureMessage(l, failure),
                  textAlign: TextAlign.center,
                ),
              if (_nextOffset case final next?)
                Center(
                  child: VeloraButton(
                    label: l.showMore,
                    icon: Icons.expand_more,
                    variant: VeloraButtonVariant.secondary,
                    isLoading: _loadingMore,
                    loadingLabel: l.loadingMore,
                    onPressed: () => _fetch(next),
                  ),
                ),
            ],
          },
        ),
      ),
    );
  }
}
