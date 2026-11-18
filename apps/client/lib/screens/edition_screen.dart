import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/catalogue_api.dart';
import '../api/playback_api.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/movie_card.dart';
import '../widgets/movie_poster.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import 'player_screen.dart';
import 'vj_screen.dart';

/// "2 h 49 min", "45 min" or "2 h".
String formatRuntime(AppLocalizations l, int minutes) {
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (hours == 0) return l.runtimeMinutes(rest);
  if (rest == 0) return l.runtimeHours(hours);
  return l.runtimeHoursMinutes(hours, rest);
}

enum _Phase { loading, ready, failed }

/// One VJ's edition: its artwork, label, details and trailer, and Watch, or
/// for a series its seasons and episodes.
class EditionScreen extends StatefulWidget {
  const EditionScreen({
    super.key,
    required this.editionId,
    required this.title,
  });

  final String editionId;

  /// Shown in the bar while the details load.
  final String title;

  @override
  State<EditionScreen> createState() => _EditionScreenState();
}

class _EditionScreenState extends State<EditionScreen> {
  _Phase _phase = _Phase.loading;
  EditionDetail? _edition;
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
      final edition = await api.edition(widget.editionId);
      if (!mounted) return;
      setState(() {
        _edition = edition;
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
    final edition = _edition;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          edition?.title ?? widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.loading => Center(
            child: VeloraLoadingRegion(
              label: context.l10n.loadingEdition,
              child: const VeloraSpinner(size: 32),
            ),
          ),
          _Phase.failed => _Failed(failure: _failure!, onRetry: _retry),
          _Phase.ready => _Details(edition: edition!),
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
    final l = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
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
          child: failure == CatalogueFailure.notFound
              ? EmptyState(
                  icon: Icons.movie_filter_outlined,
                  title: l.editionNotFoundTitle,
                  message: l.editionNotFoundMessage,
                  action: VeloraButton(
                    label: l.back,
                    icon: Icons.arrow_back,
                    variant: VeloraButtonVariant.secondary,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                )
              : ErrorState(
                  title: l.editionLoadFailed,
                  message: catalogueFailureMessage(l, failure),
                  onRetry: onRetry,
                ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.edition});

  final EditionDetail edition;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= VeloraLayout.mediumBreakpoint;
    final runtime = edition.runtimeMinutes;
    final card = edition.card;
    final facts = [
      if (card.year != null) '${card.year}',
      if (edition.kind == EditionKind.series) l.seriesBadge,
      if (runtime != null) formatRuntime(l, runtime),
    ];
    final overview = edition.overview;
    final trailer = edition.trailerUrl;
    final vjSlug = card.vjSlug;
    final vjName = card.vjName;

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: VeloraSpacing.sm,
      children: [
        Semantics(
          header: true,
          child: Text(edition.title, style: theme.textTheme.headlineMedium),
        ),
        if (vjSlug != null && vjName != null)
          // The full label, such as "Luganda · VJ Junior". It opens the VJ.
          Semantics(
            link: true,
            label: l.editionLabelLink(card.label),
            excludeSemantics: true,
            child: InkWell(
              borderRadius: BorderRadius.circular(VeloraRadii.sm),
              onTap: () => openVj(context, vjSlug, vjName),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: VeloraSpacing.xxs,
                ),
                child: Text(
                  card.label,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ),
          )
        else
          Text(card.label, style: theme.textTheme.titleMedium),
        if (edition.sourceTitle != edition.title)
          Text(
            l.alsoKnownAs(edition.sourceTitle),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (facts.isNotEmpty)
          Text(
            facts.join(' · '),
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (edition.genres.isNotEmpty)
          Wrap(
            spacing: VeloraSpacing.xs,
            runSpacing: VeloraSpacing.xs,
            children: [
              for (final genre in edition.genres)
                StatusBadge(label: genre, tone: StatusTone.neutral),
            ],
          ),
        const SizedBox(height: VeloraSpacing.xs),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (edition.kind == EditionKind.movie)
              _WatchButton(edition: edition),
            if (trailer != null)
              VeloraButton(
                label: l.trailer,
                icon: Icons.open_in_new,
                variant: VeloraButtonVariant.secondary,
                onPressed: () =>
                    launchUrl(trailer, mode: LaunchMode.externalApplication),
              ),
          ],
        ),
        if (overview != null) ...[
          const SizedBox(height: VeloraSpacing.xs),
          Text(overview, style: theme.textTheme.bodyLarge),
        ],
      ],
    );

    final poster = ClipRRect(
      borderRadius: BorderRadius.circular(VeloraRadii.md),
      child: Stack(
        children: [
          MoviePoster(url: card.posterUrl),
          if (vjName != null)
            Positioned(
              top: VeloraSpacing.xs,
              left: VeloraSpacing.xs,
              child: ExcludeSemantics(child: CornerLabel(vjName)),
            ),
        ],
      ),
    );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (edition.backdropUrl != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: MoviePoster(url: edition.backdropUrl, aspectRatio: 16 / 9),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: VeloraSpacing.lg,
                  children: [
                    if (wide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: VeloraSpacing.lg,
                        children: [
                          SizedBox(width: 220, child: poster),
                          Expanded(child: info),
                        ],
                      )
                    else ...[
                      Center(child: SizedBox(width: 180, child: poster)),
                      info,
                    ],
                    if (edition.kind == EditionKind.series)
                      _Seasons(edition: edition),
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

/// What a viewer can do about watching: watch, sign in first, or nothing
/// in this build.
enum _CanWatch { yes, signInFirst, notHere }

_CanWatch _canWatch(BuildContext context) {
  final auth = AuthScope.of(context);
  final playback = PlaybackScope.of(context);
  if (auth == null || playback == null) return _CanWatch.notHere;
  if (auth.status != AuthStatus.signedIn) return _CanWatch.signInFirst;
  return _CanWatch.yes;
}

/// Plays an item, with the series' episodes for Next Episode.
void openPlayer(
  BuildContext context, {
  required String itemId,
  required String title,
  List<Episode> episodes = const [],
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          PlayerScreen(itemId: itemId, title: title, episodes: episodes),
    ),
  );
}

/// Watch, for a movie, when there is something to watch. Signed out, it
/// starts sign-in first. Any signed-in viewer may watch, until passes in
/// Milestone 10.
class _WatchButton extends StatelessWidget {
  const _WatchButton({required this.edition});

  final EditionDetail edition;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final itemId = edition.itemId;
    final can = _canWatch(context);
    if (!edition.playable || itemId == null || can == _CanWatch.notHere) {
      return Wrap(
        spacing: VeloraSpacing.sm,
        runSpacing: VeloraSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          VeloraButton(label: l.watch, icon: Icons.play_arrow, onPressed: null),
          StatusBadge(
            label: edition.playable ? l.notAvailableHere : l.comingSoon,
            tone: StatusTone.info,
          ),
        ],
      );
    }
    if (can == _CanWatch.signInFirst) return const _SignInToWatch();
    return VeloraButton(
      label: l.watch,
      icon: Icons.play_arrow,
      onPressed: () =>
          openPlayer(context, itemId: itemId, title: edition.title),
    );
  }
}

class _SignInToWatch extends StatelessWidget {
  const _SignInToWatch();

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context)!;
    return VeloraButton(
      label: context.l10n.signInToWatchButton,
      icon: Icons.login,
      onPressed: auth.isBusy ? null : auth.signIn,
    );
  }
}

/// A series' seasons, and each season's episodes with a play button.
class _Seasons extends StatefulWidget {
  const _Seasons({required this.edition});

  final EditionDetail edition;

  @override
  State<_Seasons> createState() => _SeasonsState();
}

class _SeasonsState extends State<_Seasons> {
  int _shown = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final seasons = widget.edition.seasons;
    if (seasons.isEmpty) {
      return EmptyState(
        icon: Icons.video_library_outlined,
        title: l.noEpisodesTitle,
        message: l.noEpisodesMessage,
      );
    }
    final season = seasons[_shown.clamp(0, seasons.length - 1)];
    final can = _canWatch(context);
    final episodes = widget.edition.episodes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.sm,
      children: [
        Semantics(
          header: true,
          child: Text(l.episodes, style: theme.textTheme.titleLarge),
        ),
        if (seasons.length > 1)
          Wrap(
            spacing: VeloraSpacing.xs,
            runSpacing: VeloraSpacing.xs,
            children: [
              for (final (i, s) in seasons.indexed)
                ChoiceChip(
                  label: Text(l.seasonNumber(s.season)),
                  selected: i == _shown,
                  onSelected: (_) => setState(() => _shown = i),
                ),
            ],
          )
        else
          Text(
            l.seasonNumber(season.season),
            style: theme.textTheme.titleMedium,
          ),
        if (can == _CanWatch.signInFirst) const _SignInToWatch(),
        for (final episode in season.episodes)
          Card.outlined(
            key: ValueKey(episode.itemId),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: VeloraSpacing.md,
                vertical: VeloraSpacing.xs,
              ),
              // A Wrap, so the status moves below at large text sizes.
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: VeloraSpacing.sm,
                runSpacing: VeloraSpacing.xs,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        l.episodeNumber(episode.episode),
                        style: theme.textTheme.titleMedium,
                      ),
                      if (episode.title case final name?)
                        Text(
                          name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                  episode.playable && can == _CanWatch.yes
                      ? IconButton(
                          tooltip: l.playEpisode(
                            season.season,
                            episode.episode,
                          ),
                          icon: const Icon(Icons.play_circle_outline),
                          onPressed: () => openPlayer(
                            context,
                            itemId: episode.itemId,
                            title: widget.edition.title,
                            episodes: episodes,
                          ),
                        )
                      : StatusBadge(
                          label: episode.playable
                              ? (can == _CanWatch.notHere
                                    ? l.notAvailableHere
                                    : l.signInFirst)
                              : l.comingSoon,
                          tone: StatusTone.info,
                        ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
