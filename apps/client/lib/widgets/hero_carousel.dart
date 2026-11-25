import 'dart:ui' show ImageFilter, PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/account_api.dart';
import '../api/catalogue_api.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../screens/edition_screen.dart';
import '../theme/tokens.dart';
import 'edition_cards.dart';
import 'loading_placeholder.dart';
import 'movie_poster.dart';
import 'velora_button.dart';

/// Home's hero: the newest titles, one at a time, over their artwork.
///
/// It moves on every [VeloraMotion.heroInterval] with a crossfade while the
/// artwork slowly zooms. It stops while hovered, touched or focused, while
/// the app is in the background or another screen covers it, and when the
/// viewer pauses it. With reduced motion it neither moves on nor zooms.
///
/// Watch now and the Watch List go through exactly what an edition's page
/// uses: [watchAccess], sign-in, [openPlayer] (which checks the pass and
/// the device) and the Watch List routes.
class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.titles});

  /// At least one.
  final List<FeaturedTitle> titles;

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel>
    with TickerProviderStateMixin {
  late final AnimationController _timer = AnimationController(
    vsync: this,
    duration: VeloraMotion.heroInterval,
  )..addStatusListener(_onTimer);
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onStateChange: (state) {
      _appActive = state == AppLifecycleState.resumed;
      _sync();
    },
  );

  /// Holds keyboard focus when a slide change removes the focused button,
  /// so the arrow keys keep working and the hero stays paused.
  final FocusNode _region = FocusNode(debugLabel: 'Hero', skipTraversal: true);

  int _index = 0;
  bool _hovered = false;
  bool _touching = false;
  bool _focused = false;
  bool _userPaused = false;
  bool _appActive = true;
  bool _visible = true;
  bool _reduced = false;

  /// Movies in the viewer's Watch List, once known. Null before, or signed
  /// out.
  Set<String>? _saved;
  String? _savedFor;
  final _saving = <String>{};

  int get _count => widget.titles.length;

  FeaturedTitle get _current => widget.titles[_index % _count];

  bool get _autoPlaying =>
      _count > 1 &&
      !_reduced &&
      !_hovered &&
      !_touching &&
      !_focused &&
      !_userPaused &&
      _appActive &&
      _visible;

  @override
  void initState() {
    super.initState();
    // Created now, so it hears the app leave the foreground from the start.
    _lifecycle;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = VeloraMotion.reduced(context);
    // False while another screen covers Home.
    _visible = TickerMode.valuesOf(context).enabled;
    _precache();
    _loadSaved();
    _sync();
  }

  @override
  void didUpdateWidget(HeroCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = 0;
    if (!identical(old.titles, widget.titles)) _precache();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _timer.dispose();
    _region.dispose();
    super.dispose();
  }

  /// Starts or stops the timer to match what the viewer is doing.
  void _sync() {
    if (_autoPlaying) {
      if (!_timer.isAnimating) _timer.forward();
    } else if (_timer.isAnimating) {
      _timer.stop();
    }
  }

  void _onTimer(AnimationStatus status) {
    if (status == AnimationStatus.completed) _go(_index + 1);
  }

  void _go(int index) {
    if (!mounted) return;
    final hadFocus = _region.hasFocus;
    setState(() => _index = (index % _count + _count) % _count);
    _timer.value = 0;
    _sync();
    if (hadFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_region.hasFocus) _region.requestFocus();
      });
    }
  }

  void _setPause({bool? hovered, bool? touching, bool? focused}) {
    _hovered = hovered ?? _hovered;
    _touching = touching ?? _touching;
    _focused = focused ?? _focused;
    // Rebuilt so the artwork's zoom stops and starts with the timer.
    setState(_sync);
  }

  void _precache() {
    for (final title in widget.titles) {
      for (final url in [title.backdropUrl, title.card.posterUrl]) {
        if (url != null) {
          precacheImage(NetworkImage(url), context, onError: (_, _) {});
        }
      }
    }
  }

  Future<void> _loadSaved() async {
    final auth = AuthScope.of(context);
    final user = auth?.status == AuthStatus.signedIn ? auth?.accountKey : null;
    if (user == _savedFor) return;
    _savedFor = user;
    _saved = null;
    final api = accountApiOf(context);
    if (user == null || api == null) return;
    try {
      final items = await api.watchList();
      if (mounted && _savedFor == user) {
        setState(() => _saved = {for (final item in items) item.itemId});
      }
    } on AccountException {
      // The button still works: it asks again when pressed.
    }
  }

  /// Adds or removes a movie at once, and puts it back if the API refuses.
  Future<void> _toggleSaved(String itemId) async {
    final api = accountApiOf(context);
    if (api == null || _saving.contains(itemId)) return;
    final saved = _saved ?? <String>{};
    final add = !saved.contains(itemId);
    setState(() {
      _saving.add(itemId);
      _saved = add ? {...saved, itemId} : ({...saved}..remove(itemId));
    });
    try {
      await api.setWatchListItem(itemId, saved: add);
    } on AccountException catch (error) {
      if (!mounted) return;
      setState(() {
        final now = {...?_saved};
        add ? now.remove(itemId) : now.add(itemId);
        _saved = now;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(accountFailureMessage(context.l10n, error.failure)),
          ),
        );
    } finally {
      if (mounted) setState(() => _saving.remove(itemId));
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _count < 2) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _go(_index + 1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _go(_index - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _onSwipe(DragEndDetails details) {
    final speed = details.primaryVelocity ?? 0;
    if (_count < 2 || speed.abs() < 200) return;
    _go(speed < 0 ? _index + 1 : _index - 1);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < VeloraLayout.mediumBreakpoint;
    final fade = _reduced ? Duration.zero : VeloraMotion.heroCrossfade;
    final title = _current;
    final pad = compact ? VeloraSpacing.md : VeloraSpacing.xl;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final minHeight = compact
            ? width / VeloraLayout.heroAspectCompact
            : (width / VeloraLayout.heroAspectWide).clamp(
                VeloraLayout.heroMinHeight,
                VeloraLayout.heroMaxHeight,
              );
        return Semantics(
          container: true,
          label: l.heroRegion,
          child: Focus(
            focusNode: _region,
            onFocusChange: (focused) => _setPause(focused: focused),
            onKeyEvent: _onKey,
            child: MouseRegion(
              onEnter: (_) => _setPause(hovered: true),
              onExit: (_) => _setPause(hovered: false),
              child: Listener(
                onPointerDown: (event) {
                  if (event.kind == PointerDeviceKind.touch) {
                    _setPause(touching: true);
                  }
                },
                onPointerUp: (_) {
                  if (_touching) _setPause(touching: false);
                },
                onPointerCancel: (_) {
                  if (_touching) _setPause(touching: false);
                },
                child: GestureDetector(
                  onHorizontalDragEnd: _onSwipe,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      compact ? 0 : VeloraRadii.lg,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: width,
                        minHeight: minHeight,
                      ),
                      child: Stack(
                        alignment: AlignmentDirectional.bottomStart,
                        children: [
                          Positioned.fill(
                            child: AnimatedSwitcher(
                              duration: fade,
                              child: _Artwork(
                                key: ValueKey('art-${title.id}'),
                                title: title,
                                zoom: _autoPlaying,
                              ),
                            ),
                          ),
                          Positioned.fill(child: _Scrim(compact: compact)),
                          Padding(
                            padding: EdgeInsets.fromLTRB(
                              pad,
                              pad + VeloraSpacing.xl,
                              pad,
                              compact ? VeloraSpacing.xs : VeloraSpacing.sm,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Its own node, so it is read as a heading
                                // and not merged into the region's label.
                                Semantics(
                                  container: true,
                                  header: true,
                                  child: Text(
                                    l.heroEyebrow.toUpperCase(),
                                    semanticsLabel: l.heroEyebrow,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      color: VeloraColors.accentText,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: VeloraSpacing.sm),
                                AnimatedSwitcher(
                                  duration: fade,
                                  layoutBuilder: (current, previous) => Stack(
                                    alignment: AlignmentDirectional.bottomStart,
                                    children: [...previous, ?current],
                                  ),
                                  child: _Slide(
                                    key: ValueKey('slide-${title.id}'),
                                    title: title,
                                    compact: compact,
                                    animate: !_reduced,
                                    saved: switch (title.itemId) {
                                      final id? => _saved?.contains(id),
                                      null => null,
                                    },
                                    onToggleSaved: _toggleSaved,
                                  ),
                                ),
                                const SizedBox(height: VeloraSpacing.xs),
                                _Controls(
                                  count: _count,
                                  index: _index,
                                  progress: _timer,
                                  showProgress: !_reduced,
                                  canPause: _count > 1 && !_reduced,
                                  paused: _userPaused,
                                  onSelect: _go,
                                  onPause: () => setState(() {
                                    _userPaused = !_userPaused;
                                    _sync();
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The title's backdrop, or its poster blurred when it has none, slowly
/// zooming while [zoom] is true.
class _Artwork extends StatefulWidget {
  const _Artwork({super.key, required this.title, required this.zoom});

  final FeaturedTitle title;
  final bool zoom;

  @override
  State<_Artwork> createState() => _ArtworkState();
}

class _ArtworkState extends State<_Artwork>
    with SingleTickerProviderStateMixin {
  late final AnimationController _zoom = AnimationController(
    vsync: this,
    duration: VeloraMotion.heroInterval,
  );

  @override
  void initState() {
    super.initState();
    if (widget.zoom) _zoom.forward();
  }

  @override
  void didUpdateWidget(_Artwork old) {
    super.didUpdateWidget(old);
    if (widget.zoom && !_zoom.isAnimating && !_zoom.isCompleted) {
      _zoom.forward();
    } else if (!widget.zoom) {
      _zoom.stop();
    }
  }

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backdrop = widget.title.backdropUrl;
    final poster = widget.title.card.posterUrl;
    const empty = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [VeloraColors.surfaceOverlay, VeloraColors.canvas],
        ),
      ),
    );
    Widget image(String url) => Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => empty,
    );
    final Widget art;
    if (backdrop != null) {
      art = image(backdrop);
    } else if (poster != null) {
      art = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: image(poster),
      );
    } else {
      art = empty;
    }
    return ExcludeSemantics(
      child: ColoredBox(
        color: VeloraColors.canvas,
        child: AnimatedBuilder(
          animation: _zoom,
          builder: (context, child) => Transform.scale(
            scale:
                1 +
                (VeloraMotion.heroZoom - 1) *
                    VeloraMotion.curve.transform(_zoom.value),
            child: child,
          ),
          child: SizedBox.expand(child: art),
        ),
      ),
    );
  }
}

/// Darkens the artwork where the words are, so they read over any image.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bottom = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: const [0, 0.35, 1],
          colors: [
            VeloraColors.canvas.withValues(alpha: 0.35),
            VeloraColors.canvas.withValues(alpha: 0.15),
            VeloraColors.canvas.withValues(alpha: 0.96),
          ],
        ),
      ),
    );
    if (compact) return bottom;
    return Stack(
      fit: StackFit.expand,
      children: [
        bottom,
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              stops: const [0, 0.65],
              colors: [
                VeloraColors.canvas.withValues(alpha: 0.88),
                VeloraColors.canvas.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One title: its poster, name, VJ, rating, genres and actions.
class _Slide extends StatelessWidget {
  const _Slide({
    super.key,
    required this.title,
    required this.compact,
    required this.animate,
    required this.saved,
    required this.onToggleSaved,
  });

  final FeaturedTitle title;
  final bool compact;
  final bool animate;

  /// For a movie: in the Watch List or not, or null when not known.
  final bool? saved;
  final void Function(String itemId) onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final card = title.card;
    final rating = card.rating;
    final posterWidth = compact ? 92.0 : 176.0;
    final poster = _PosterEntrance(
      animate: animate,
      child: Semantics(
        button: true,
        label: l.heroDetails,
        excludeSemantics: true,
        child: GestureDetector(
          onTap: () => openEdition(context, card),
          child: SizedBox(
            width: posterWidth,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(VeloraRadii.md),
                boxShadow: VeloraShadows.raised,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VeloraRadii.md),
                child: MoviePoster(url: card.posterUrl),
              ),
            ),
          ),
        ),
      ),
    );
    final meta = [
      if (card.vjName != null) card.vjName!,
      if (card.year != null) '${card.year}',
      if (card.kind == EditionKind.series) l.seriesBadge,
    ];
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: VeloraSpacing.xs,
      children: [
        Text(
          card.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              (compact
                      ? theme.textTheme.headlineMedium
                      : theme.textTheme.displaySmall)
                  ?.copyWith(
                    color: VeloraColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
        ),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.xxs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (meta.isNotEmpty)
              Text(
                meta.join(' · '),
                style: theme.textTheme.titleSmall?.copyWith(
                  color: VeloraColors.textSecondary,
                ),
              ),
            if (rating != null)
              Semantics(
                container: true,
                label: l.ratingSemantics(rating),
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: VeloraSpacing.xxs,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: VeloraIconSizes.button,
                      color: VeloraColors.rating,
                    ),
                    Text(
                      l.ratingValue(rating),
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: VeloraColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
    final genres = title.genres.take(3).toList();
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: VeloraSpacing.sm,
      children: [
        if (!compact) heading,
        if (genres.isNotEmpty)
          Wrap(
            spacing: VeloraSpacing.xs,
            runSpacing: VeloraSpacing.xs,
            children: [for (final genre in genres) _GenreChip(genre)],
          ),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.sm,
          children: [
            _WatchNow(title: title),
            _Secondary(
              title: title,
              saved: saved,
              onToggleSaved: onToggleSaved,
            ),
          ],
        ),
      ],
    );
    if (compact) {
      // One group per title, read together.
      return Semantics(
        container: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: VeloraSpacing.md,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: VeloraSpacing.md,
              children: [
                poster,
                Expanded(child: heading),
              ],
            ),
            details,
          ],
        ),
      );
    }
    return Semantics(
      container: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: VeloraSpacing.xl,
        children: [
          poster,
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: VeloraLayout.readingWidth,
              ),
              child: details,
            ),
          ),
        ],
      ),
    );
  }
}

/// The poster fades and rises into place as its title arrives.
class _PosterEntrance extends StatelessWidget {
  const _PosterEntrance({required this.animate, required this.child});

  final bool animate;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!animate) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: VeloraMotion.heroCrossfade,
      curve: VeloraMotion.curve,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, (1 - value) * VeloraSpacing.lg),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _GenreChip extends StatelessWidget {
  const _GenreChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: VeloraColors.surfaceOverlay.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(VeloraRadii.sm),
        border: Border.all(color: VeloraColors.outlineSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VeloraSpacing.xs,
          vertical: VeloraSpacing.xxs,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(color: VeloraColors.textPrimary),
        ),
      ),
    );
  }
}

/// Watch now: a movie plays, after sign-in if needed, through the same
/// player as its page, which checks the pass and the device. A series, or
/// a build that can't play, opens the title's page.
class _WatchNow extends StatelessWidget {
  const _WatchNow({required this.title});

  final FeaturedTitle title;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final itemId = title.itemId;
    final access = watchAccess(context);
    if (title.kind == EditionKind.movie &&
        itemId != null &&
        access == WatchAccess.signInFirst) {
      final auth = AuthScope.of(context)!;
      return VeloraButton(
        label: l.signInToWatchButton,
        icon: Icons.login,
        onPressed: auth.isBusy ? null : auth.signIn,
      );
    }
    return VeloraButton(
      label: l.watchNow,
      icon: Icons.play_arrow,
      onPressed: () {
        if (title.kind == EditionKind.movie &&
            itemId != null &&
            access == WatchAccess.yes) {
          openPlayer(context, itemId: itemId, title: title.title);
        } else {
          openEdition(context, title.card);
        }
      },
    );
  }
}

/// A movie's Watch List button, or Details for a series, whose episodes
/// are saved one by one on its page.
class _Secondary extends StatelessWidget {
  const _Secondary({
    required this.title,
    required this.saved,
    required this.onToggleSaved,
  });

  final FeaturedTitle title;
  final bool? saved;
  final void Function(String itemId) onToggleSaved;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final itemId = title.itemId;
    final details = VeloraButton(
      label: l.heroDetails,
      icon: Icons.info_outline,
      variant: VeloraButtonVariant.secondary,
      onPressed: () => openEdition(context, title.card),
    );
    if (title.kind != EditionKind.movie || itemId == null) return details;
    final access = watchAccess(context);
    if (access == WatchAccess.notHere) return details;
    if (access == WatchAccess.signInFirst) {
      final auth = AuthScope.of(context)!;
      return VeloraButton(
        label: l.watchListAdd,
        icon: Icons.add,
        variant: VeloraButtonVariant.secondary,
        onPressed: auth.isBusy ? null : auth.signIn,
      );
    }
    final isSaved = saved ?? false;
    // Merged, so the button itself is read as on or off.
    return MergeSemantics(
      child: Semantics(
        toggled: isSaved,
        child: Tooltip(
          message: isSaved ? l.watchListRemove : l.watchListAdd,
          child: VeloraButton(
            label: isSaved ? l.heroInWatchList : l.watchListAdd,
            icon: isSaved ? Icons.check : Icons.add,
            variant: VeloraButtonVariant.secondary,
            onPressed: () => onToggleSaved(itemId),
          ),
        ),
      ),
    );
  }
}

/// A dot per title, the current one filling as its time passes, and the
/// pause button.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.count,
    required this.index,
    required this.progress,
    required this.showProgress,
    required this.canPause,
    required this.paused,
    required this.onSelect,
    required this.onPause,
  });

  final int count;
  final int index;
  final Animation<double> progress;
  final bool showProgress;
  final bool canPause;
  final bool paused;
  final void Function(int index) onSelect;
  final VoidCallback onPause;

  @override
  Widget build(BuildContext context) {
    if (count < 2) return const SizedBox(height: VeloraSpacing.xs);
    final l = context.l10n;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Semantics(
            button: true,
            selected: i == index,
            label: l.heroSlide(i + 1, count),
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onSelect(i),
              customBorder: const StadiumBorder(),
              child: SizedBox(
                width: VeloraLayout.minTouchTarget,
                height: VeloraLayout.minTouchTarget,
                child: Center(
                  child: _Dot(
                    active: i == index,
                    progress: showProgress ? progress : null,
                  ),
                ),
              ),
            ),
          ),
        const Spacer(),
        if (canPause)
          IconButton(
            onPressed: onPause,
            tooltip: paused ? l.heroPlay : l.heroPause,
            color: VeloraColors.textPrimary,
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.active, required this.progress});

  final bool active;
  final Animation<double>? progress;

  @override
  Widget build(BuildContext context) {
    final width = active ? VeloraSpacing.lg : VeloraSpacing.xs;
    final track = Container(
      width: width,
      height: VeloraSpacing.xs,
      decoration: BoxDecoration(
        color: active
            ? VeloraColors.textPrimary.withValues(alpha: 0.35)
            : VeloraColors.textMuted,
        borderRadius: BorderRadius.circular(VeloraSpacing.xxs),
      ),
    );
    final progress = this.progress;
    if (!active) return track;
    return Stack(
      children: [
        track,
        if (progress == null)
          Container(
            width: width,
            height: VeloraSpacing.xs,
            decoration: BoxDecoration(
              color: VeloraColors.textPrimary,
              borderRadius: BorderRadius.circular(VeloraSpacing.xxs),
            ),
          )
        else
          AnimatedBuilder(
            animation: progress,
            builder: (context, _) => Container(
              width: width * progress.value,
              height: VeloraSpacing.xs,
              decoration: BoxDecoration(
                color: VeloraColors.textPrimary,
                borderRadius: BorderRadius.circular(VeloraSpacing.xxs),
              ),
            ),
          ),
      ],
    );
  }
}

/// A placeholder with the hero's shape, while it loads.
class HeroCarouselSkeleton extends StatelessWidget {
  const HeroCarouselSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final compact =
        MediaQuery.sizeOf(context).width < VeloraLayout.mediumBreakpoint;
    return VeloraLoadingRegion(
      label: context.l10n.loadingTitles,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = compact
              ? width / VeloraLayout.heroAspectCompact
              : (width / VeloraLayout.heroAspectWide).clamp(
                  VeloraLayout.heroMinHeight,
                  VeloraLayout.heroMaxHeight,
                );
          return VeloraSkeleton(
            height: height,
            radius: compact ? 0 : VeloraRadii.lg,
          );
        },
      ),
    );
  }
}
