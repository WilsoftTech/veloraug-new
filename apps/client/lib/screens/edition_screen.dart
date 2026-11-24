import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/account_api.dart';
import '../api/catalogue_api.dart';
import '../api/playback_api.dart';
import '../auth/auth_controller.dart';
import '../downloads/downloads.dart';
import '../downloads/download_ui.dart';
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
          _Phase.ready => _Details(
            key: ValueKey((edition!.id, AuthScope.of(context)?.accountKey)),
            edition: edition,
          ),
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

class _Details extends StatefulWidget {
  const _Details({super.key, required this.edition});

  final EditionDetail edition;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  EditionDetail get edition => widget.edition;
  Set<String>? _saved;
  final _saving = <String>{};
  bool _loadingSaved = false;
  bool _requestedSaved = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requestedSaved && _canWatch(context) == _CanWatch.yes) {
      _requestedSaved = true;
      _loadSaved();
    }
  }

  Future<void> _loadSaved() async {
    final api = accountApiOf(context);
    if (api == null) return;
    setState(() => _loadingSaved = true);
    try {
      final saved = await api.savedItemsFor(edition.id);
      if (mounted) setState(() => _saved = saved);
    } on AccountException {
      // The buttons offer a retry if status could not be fetched.
    } finally {
      if (mounted) setState(() => _loadingSaved = false);
    }
  }

  Future<void> _toggleSaved(String id) async {
    final api = accountApiOf(context);
    final auth = AuthScope.of(context);
    if (api == null || auth?.status != AuthStatus.signedIn) return;
    final saved = _saved;
    if (saved == null) {
      await _loadSaved();
      return;
    }
    if (_saving.contains(id)) return;
    final add = !saved.contains(id);
    setState(() => _saving.add(id));
    try {
      await api.setWatchListItem(id, saved: add);
      if (!mounted) return;
      setState(() {
        if (add) {
          saved.add(id);
        } else {
          saved.remove(id);
        }
      });
    } on AccountException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(accountFailureMessage(context.l10n, error.failure)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving.remove(id));
    }
  }

  Widget _watchListButton(String id, {bool compact = false}) {
    final l = context.l10n;
    final saved = _saved;
    final selected = saved?.contains(id) ?? false;
    final busy = _loadingSaved || _saving.contains(id);
    final label = busy
        ? l.loading
        : saved == null
        ? l.watchListRetry
        : selected
        ? l.watchListRemove
        : l.watchListAdd;
    final icon = selected ? Icons.bookmark : Icons.bookmark_add_outlined;
    void toggle() => _toggleSaved(id);
    return compact
        ? IconButton(
            tooltip: label,
            icon: Icon(icon),
            onPressed: busy ? null : toggle,
          )
        : VeloraButton(
            label: label,
            icon: icon,
            variant: VeloraButtonVariant.secondary,
            onPressed: busy ? null : toggle,
          );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= VeloraLayout.mediumBreakpoint;
    final gutter = VeloraLayout.gutterFor(width);
    final runtime = edition.runtimeMinutes;
    final overview = edition.overview;
    final trailer = edition.trailerUrl;
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final canWatchMovie =
        edition.kind == EditionKind.movie &&
        edition.playable &&
        edition.itemId != null &&
        _canWatch(context) == _CanWatch.yes;

    final badges = Wrap(
      spacing: VeloraSpacing.xs,
      runSpacing: VeloraSpacing.xs,
      children: [
        StatusBadge(
          label: edition.kind == EditionKind.series
              ? l.seriesBadge
              : l.movieBadge,
          tone: StatusTone.neutral,
        ),
        if (runtime != null)
          StatusBadge(
            label: formatRuntime(l, runtime),
            tone: StatusTone.neutral,
            icon: Icons.schedule,
          ),
        for (final genre in edition.genres)
          StatusBadge(label: genre, tone: StatusTone.neutral),
      ],
    );

    final secondary = [
      if (canWatchMovie)
        DownloadButton(itemId: edition.itemId!, info: downloadInfo(edition)),
      if (trailer != null)
        VeloraButton(
          label: l.trailer,
          icon: Icons.open_in_new,
          variant: VeloraButtonVariant.secondary,
          onPressed: () =>
              launchUrl(trailer, mode: LaunchMode.externalApplication),
        ),
    ];

    final listItemId = canWatchMovie ? edition.itemId : null;
    final Widget? actions;
    if (edition.kind == EditionKind.movie) {
      actions = wide
          ? Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _WatchButton(edition: edition),
                if (listItemId != null) _watchListButton(listItemId),
                ...secondary,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: VeloraSpacing.sm,
              children: [
                if (listItemId == null)
                  _WatchButton(edition: edition, expand: true)
                else
                  Wrap(
                    spacing: VeloraSpacing.sm,
                    runSpacing: VeloraSpacing.sm,
                    children: [
                      _WatchButton(edition: edition),
                      _watchListButton(listItemId),
                    ],
                  ),
                if (secondary.isNotEmpty)
                  Wrap(
                    spacing: VeloraSpacing.sm,
                    runSpacing: VeloraSpacing.sm,
                    children: secondary,
                  ),
              ],
            );
    } else {
      actions = secondary.isEmpty
          ? null
          : Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.sm,
              children: secondary,
            );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(edition: edition, wide: wide, gutter: gutter),
          Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              VeloraSpacing.md,
              gutter,
              VeloraSpacing.xl,
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
                    badges,
                    ?actions,
                    if (edition.sourceTitle != edition.title)
                      Text(l.alsoKnownAs(edition.sourceTitle), style: muted),
                    if (overview != null && overview.trim().isNotEmpty)
                      _Storyline(text: overview),
                    if (edition.kind == EditionKind.series)
                      _Seasons(
                        edition: edition,
                        watchListButton: (id) =>
                            _watchListButton(id, compact: true),
                      ),
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

/// The artwork, with the poster, title, VJ and year grouped over the
/// bottom of the backdrop, where a gradient keeps the text readable.
class _Header extends StatelessWidget {
  const _Header({
    required this.edition,
    required this.wide,
    required this.gutter,
  });

  final EditionDetail edition;
  final bool wide;
  final double gutter;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final card = edition.card;
    final vjSlug = card.vjSlug;
    final vjName = card.vjName;
    final backdrop = edition.backdropUrl ?? card.posterUrl;
    final posterWidth = wide ? 180.0 : 112.0;

    final Widget label;
    if (vjSlug != null && vjName != null) {
      // The full label, such as "Luganda · VJ Junior". It opens the VJ.
      label = Semantics(
        link: true,
        label: l.editionLabelLink(card.label),
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(VeloraRadii.sm),
          onTap: () => openVj(context, vjSlug, vjName),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: VeloraSpacing.xxs),
            child: Text(
              card.label,
              style: theme.textTheme.titleMedium?.copyWith(
                color: VeloraColors.accentText,
              ),
            ),
          ),
        ),
      );
    } else {
      label = Text(card.label, style: theme.textTheme.titleMedium);
    }

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: VeloraSpacing.xxs,
      children: [
        Semantics(
          header: true,
          child: Text(
            edition.title,
            style: wide
                ? theme.textTheme.headlineMedium
                : theme.textTheme.headlineSmall,
          ),
        ),
        label,
        if (card.year != null)
          Text(
            '${card.year}',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
              right: VeloraSpacing.xs,
              child: Align(
                alignment: Alignment.topLeft,
                child: ExcludeSemantics(child: CornerLabel(vjName)),
              ),
            ),
        ],
      ),
    );

    return Stack(
      children: [
        // The backdrop fills the header's top and fades into the canvas.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: wide ? 340 : 240,
          child: ExcludeSemantics(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backdrop != null)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: 1600,
                      height: 900,
                      child: MoviePoster(url: backdrop, aspectRatio: 16 / 9),
                    ),
                  )
                else
                  const ColoredBox(color: VeloraColors.surface),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.55, 1],
                      colors: [
                        Color(0x660E1014),
                        Color(0xB30E1014),
                        VeloraColors.canvas,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(gutter, wide ? 160 : 112, gutter, 0),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: VeloraLayout.readingWidth + 240,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: VeloraSpacing.md,
                children: [
                  SizedBox(width: posterWidth, child: poster),
                  Expanded(child: info),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The storyline, cut to a few lines with Read more when it is long. The
/// whole text is always read out; Read more only changes what is drawn.
class _Storyline extends StatefulWidget {
  const _Storyline({required this.text});

  final String text;

  static const int collapsedLines = 4;

  @override
  State<_Storyline> createState() => _StorylineState();
}

class _StorylineState extends State<_Storyline> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: VeloraSpacing.xs,
      children: [
        Semantics(
          header: true,
          child: Text(
            l.storyline,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              text: TextSpan(text: widget.text, style: style),
              maxLines: _Storyline.collapsedLines,
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: constraints.maxWidth);
            final long = painter.didExceedMaxLines;
            painter.dispose();
            final cut = long && !_expanded;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedSize(
                  duration: VeloraMotion.of(context, VeloraMotion.standard),
                  curve: VeloraMotion.curve,
                  alignment: Alignment.topCenter,
                  child: Semantics(
                    label: widget.text,
                    excludeSemantics: true,
                    child: Text(
                      widget.text,
                      style: style,
                      maxLines: cut ? _Storyline.collapsedLines : null,
                      overflow: cut ? TextOverflow.ellipsis : null,
                    ),
                  ),
                ),
                if (long)
                  Semantics(
                    expanded: _expanded,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: VeloraSpacing.xs,
                        ),
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                      child: Text(_expanded ? l.readLess : l.readMore),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
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

/// What a download of this edition, or one of its episodes, keeps with it.
DownloadInfo downloadInfo(EditionDetail edition, [Episode? episode]) =>
    DownloadInfo(
      editionId: edition.card.id,
      title: edition.title,
      label: edition.card.label,
      posterUrl: edition.card.posterUrl,
      season: episode?.season,
      episode: episode?.episode,
      episodeTitle: episode?.title,
    );

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
  const _WatchButton({required this.edition, this.expand = false});

  final EditionDetail edition;

  /// Fills the width, as the main action on a phone.
  final bool expand;

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
    if (can == _CanWatch.signInFirst) return _SignInToWatch(expand: expand);
    return VeloraButton(
      label: l.watch,
      icon: Icons.play_arrow,
      expand: expand,
      onPressed: () =>
          openPlayer(context, itemId: itemId, title: edition.title),
    );
  }
}

class _SignInToWatch extends StatelessWidget {
  const _SignInToWatch({this.expand = false});

  final bool expand;

  @override
  Widget build(BuildContext context) {
    final auth = AuthScope.of(context)!;
    return VeloraButton(
      label: context.l10n.signInToWatchButton,
      icon: Icons.login,
      expand: expand,
      onPressed: auth.isBusy ? null : auth.signIn,
    );
  }
}

/// A series' seasons, and each season's episodes with a play button.
class _Seasons extends StatefulWidget {
  const _Seasons({required this.edition, required this.watchListButton});

  final EditionDetail edition;
  final Widget Function(String) watchListButton;

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
        AnimatedSwitcher(
          duration: VeloraMotion.of(context, VeloraMotion.standard),
          switchInCurve: VeloraMotion.curve,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          child: Column(
            key: ValueKey('season-${season.season}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: VeloraSpacing.sm,
            children: [
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
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  EpisodeDownloadButton(
                                    itemId: episode.itemId,
                                    info: downloadInfo(widget.edition, episode),
                                  ),
                                  IconButton(
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
                                  ),
                                  widget.watchListButton(episode.itemId),
                                ],
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
          ),
        ),
      ],
    );
  }
}
