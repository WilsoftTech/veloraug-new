import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/edition_cards.dart';
import '../widgets/tmdb_attribution.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';

/// Opens a VJ's page.
void openVj(BuildContext context, String slug, String name) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VjScreen(slug: slug, name: name),
    ),
  );
}

enum _Phase { loading, ready, failed }

/// A VJ's photo, name and bio, then their movies and series.
class VjScreen extends StatefulWidget {
  const VjScreen({super.key, required this.slug, required this.name});

  final String slug;

  /// Shown in the bar while the page loads.
  final String name;

  @override
  State<VjScreen> createState() => _VjScreenState();
}

class _VjScreenState extends State<VjScreen> {
  _Phase _phase = _Phase.loading;
  CatalogueFailure? _failure;
  VjPage? _page;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _fetch();
    }
  }

  Future<void> _fetch() async {
    final api = CatalogueScope.of(context);
    if (api == null) {
      setState(() {
        _failure = CatalogueFailure.unreachable;
        _phase = _Phase.failed;
      });
      return;
    }
    try {
      final page = await api.vj(widget.slug);
      if (!mounted) return;
      setState(() {
        _page = page;
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
    final l = context.l10n;
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: Text(page?.vj.name ?? widget.name)),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => Center(
            child: VeloraLoadingRegion(
              label: l.loadingVj,
              child: const VeloraSpinner(size: VeloraIconSizes.large),
            ),
          ),
          _Phase.failed => ScreenBody(
            heading: widget.name,
            children: [
              if (_failure == CatalogueFailure.notFound)
                EmptyState(
                  icon: Icons.person_off_outlined,
                  title: l.vjNotFoundTitle,
                  message: l.vjNotFoundMessage,
                )
              else
                ErrorState(
                  title: l.vjLoadFailed,
                  message: catalogueFailureMessage(l, _failure!),
                  onRetry: () {
                    setState(() => _phase = _Phase.loading);
                    _fetch();
                  },
                ),
            ],
          ),
          _Phase.ready => _VjBody(page: page!),
        },
      ),
    );
  }
}

class _VjBody extends StatelessWidget {
  const _VjBody({required this.page});

  final VjPage page;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final bio = page.bio;
    Widget section(String title, List<EditionCard> editions) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.sm,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.titleLarge),
        ),
        EditionGrid(editions: editions),
      ],
    );
    return ScreenBody(
      heading: page.vj.name,
      maxWidth: VeloraLayout.browseWidth,
      status: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: VeloraSpacing.md,
        children: [
          VjAvatar(name: page.vj.name, photoUrl: page.vj.photoUrl, size: 96),
          Expanded(
            child: Text(
              bio == null || bio.isEmpty ? l.vjNoBio : bio,
              style: theme.textTheme.bodyLarge,
            ),
          ),
        ],
      ),
      children: [
        if (page.movies.isEmpty && page.series.isEmpty)
          EmptyState(
            icon: Icons.movie_outlined,
            title: l.nothingHereTitle,
            message: l.nothingYetMessage,
          ),
        if (page.movies.isNotEmpty) section(l.movies, page.movies),
        if (page.series.isNotEmpty) section(l.series, page.series),
        TmdbAttribution(editions: [...page.movies, ...page.series]),
      ],
    );
  }
}
