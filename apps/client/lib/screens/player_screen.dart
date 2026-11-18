import 'package:flutter/material.dart';

import '../api/catalogue_api.dart';
import '../api/playback_api.dart';
import '../l10n/l10n.dart';
import '../player/video_view.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/velora_button.dart';

enum _Phase { granting, playing, failed }

/// Watches one item: a movie, or one episode of a series. Asks the API for
/// a grant, then plays the playlist it names from the media gateway.
///
/// A grant lasts 6 hours. If playback stops once it has run out, or is
/// about to, a new grant is fetched by itself, and playback carries on from
/// the same moment. Any other stop offers Try again, from the same moment.
///
/// For an episode, [episodes] is the series edition's episodes in order.
/// Next Episode offers the next one, in the same edition, so the same VJ:
/// in the bar at any time, and in the middle of the screen when an episode
/// ends.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.itemId,
    required this.title,
    this.episodes = const [],
    this.preview = false,
    this.viewBuilder = platformVideoView,
    this.clock = DateTime.now,
  });

  final String itemId;

  /// The movie's or series' title.
  final String title;
  final List<Episode> episodes;

  /// An admin's preview of a video that may not be published.
  final bool preview;

  /// Replaced in tests, which can't play video.
  final VideoViewBuilder viewBuilder;
  final DateTime Function() clock;

  /// A grant this close to its end counts as run out.
  static const Duration expiryMargin = Duration(minutes: 1);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  _Phase _phase = _Phase.granting;
  late String _itemId = widget.itemId;
  PlaybackGrant? _grant;
  String? _message;
  Duration _position = Duration.zero;
  bool _started = false;
  bool _ended = false;

  /// Renewing by itself happens once per grant, so a gateway that refuses a
  /// fresh grant can't cause a loop.
  bool _renewedThisGrant = false;

  Episode? get _episode {
    for (final episode in widget.episodes) {
      if (episode.itemId == _itemId) return episode;
    }
    return null;
  }

  Episode? get _next => nextEpisode(widget.episodes, _itemId);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _fetchGrant();
    }
  }

  Future<void> _fetchGrant({bool renewal = false}) async {
    if (mounted) {
      setState(() => _phase = _Phase.granting);
    }
    final l = context.l10n;
    final api = PlaybackScope.of(context);
    if (api == null) {
      _showFailure(playbackFailureMessage(l, PlaybackFailure.unreachable));
      return;
    }
    final itemId = _itemId;
    try {
      final grant = await api.grant(itemId, preview: widget.preview);
      if (!mounted || itemId != _itemId) return;
      setState(() {
        _grant = grant;
        _renewedThisGrant = renewal;
        _phase = _Phase.playing;
      });
    } on PlaybackException catch (error) {
      if (itemId != _itemId) return;
      _showFailure(playbackFailureMessage(l, error.failure));
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _phase = _Phase.failed;
    });
  }

  void _playbackFailed(Duration position) {
    _position = position;
    final grant = _grant;
    final runOut =
        grant != null &&
        !widget.clock().isBefore(
          grant.expiresAt.subtract(PlayerScreen.expiryMargin),
        );
    if (runOut && !_renewedThisGrant) {
      _fetchGrant(renewal: true);
      return;
    }
    _showFailure(context.l10n.playbackStopped);
  }

  void _playbackEnded() {
    if (mounted && _next != null) setState(() => _ended = true);
  }

  /// Starts the next episode from its beginning, with a grant of its own.
  void _playNext() {
    final next = _next;
    if (next == null) return;
    setState(() {
      _itemId = next.itemId;
      _grant = null;
      _position = Duration.zero;
      _ended = false;
    });
    _fetchGrant();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final grant = _grant;
    final episode = _episode;
    final next = _next;
    final title = episode == null
        ? widget.title
        : l.episodeHeading(widget.title, episode.season, episode.episode);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (next != null)
            IconButton(
              tooltip: l.nextEpisodeOf(next.season, next.episode),
              icon: const Icon(Icons.skip_next),
              onPressed: _playNext,
            ),
        ],
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.granting => Center(
            child: VeloraLoadingRegion(
              label: l.gettingReady,
              child: const VeloraSpinner(size: 32),
            ),
          ),
          _Phase.failed => Center(
            child: Padding(
              padding: const EdgeInsets.all(VeloraSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: VeloraLayout.readingWidth,
                ),
                child: ErrorState(
                  title: l.couldNotPlay,
                  message: _message!,
                  onRetry: _fetchGrant,
                ),
              ),
            ),
          ),
          _Phase.playing => Stack(
            children: [
              Positioned.fill(
                child: widget.viewBuilder(
                  context,
                  VideoViewRequest(
                    url: grant!.playlistUrl,
                    startAt: _position,
                    onFailed: _playbackFailed,
                    onEnded: _playbackEnded,
                  ),
                ),
              ),
              if (_ended && next != null)
                Center(
                  child: Semantics(
                    liveRegion: true,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(VeloraSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          spacing: VeloraSpacing.sm,
                          children: [
                            Text(
                              l.upNext(next.season, next.episode),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (next.title case final name?) Text(name),
                            VeloraButton(
                              label: l.nextEpisode,
                              icon: Icons.skip_next,
                              onPressed: _playNext,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        },
      ),
    );
  }
}
