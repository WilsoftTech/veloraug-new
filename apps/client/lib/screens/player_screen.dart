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
/// The gear in the bar chooses the quality, as on YouTube: Auto, which
/// follows the connection, or one quality held whatever the connection.
/// Changing it carries on from the same moment. The choice is kept for the
/// next episode, and until the app is closed.
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

  /// The quality last chosen, by its height, or null for Auto. Kept while
  /// the app runs, for every film and episode.
  static int? chosenHeight;

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

  /// What this video comes in, from its master playlist. Empty until read,
  /// or if it can't be: then only Auto is offered.
  List<VideoQuality> _qualities = const [];

  /// Where playback has got to, as the video reports it.
  Duration _playedTo = Duration.zero;

  /// The quality chosen, if this video has it. Otherwise Auto.
  VideoQuality? get _quality {
    final height = PlayerScreen.chosenHeight;
    if (height == null) return null;
    for (final quality in _qualities) {
      if (quality.height == height) return quality;
    }
    return null;
  }

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
      // Read before playing, so a quality chosen before applies from the
      // first frame. A renewed grant is the same video.
      final qualities = renewal && _qualities.isNotEmpty
          ? _qualities
          : await api.qualities(grant);
      if (!mounted || itemId != _itemId) return;
      setState(() {
        _grant = grant;
        _qualities = qualities;
        _renewedThisGrant = renewal;
        _phase = _Phase.playing;
      });
    } on PlaybackException catch (error) {
      if (itemId != _itemId) return;
      _showFailure(playbackFailureMessage(l, error.failure));
    }
  }

  void _chooseQuality(VideoQuality? quality) {
    if (quality == _quality) return;
    setState(() {
      PlayerScreen.chosenHeight = quality?.height;
      _position = _playedTo;
    });
  }

  Future<void> _openQualities() async {
    final l = context.l10n;
    final current = _quality;
    final chosen = await showModalBottomSheet<_QualityChoice>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: VeloraSpacing.md,
                ),
                child: Semantics(
                  header: true,
                  child: Text(
                    l.quality,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              RadioGroup<_QualityChoice>(
                groupValue: _QualityChoice(current),
                onChanged: (choice) => Navigator.of(context).pop(choice),
                child: Column(
                  children: [
                    RadioListTile<_QualityChoice>(
                      value: const _QualityChoice(null),
                      title: Text(l.qualityAuto),
                      subtitle: Text(l.qualityAutoHelp),
                    ),
                    for (final quality in _qualities)
                      RadioListTile<_QualityChoice>(
                        value: _QualityChoice(quality),
                        title: Text(quality.label),
                        subtitle: quality.height >= 720
                            ? Text(l.qualityHd)
                            : null,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (chosen != null && mounted) _chooseQuality(chosen.quality);
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
    _playedTo = position;
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
      _playedTo = Duration.zero;
      _qualities = const [];
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
          if (_phase == _Phase.playing && _qualities.isNotEmpty)
            IconButton(
              tooltip: l.qualityNow(_quality?.label ?? l.qualityAuto),
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openQualities,
            ),
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
                    url: switch (_quality) {
                      final quality? => grant!.qualityUrl(quality),
                      null => grant!.playlistUrl,
                    },
                    startAt: _position,
                    onFailed: _playbackFailed,
                    onEnded: _playbackEnded,
                    onProgress: (at) => _playedTo = at,
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

/// A choice in the quality menu. Null is Auto.
class _QualityChoice {
  const _QualityChoice(this.quality);

  final VideoQuality? quality;

  @override
  bool operator ==(Object other) =>
      other is _QualityChoice && other.quality == quality;

  @override
  int get hashCode => quality.hashCode;
}
