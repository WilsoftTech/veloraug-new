import 'dart:async';

import 'package:flutter/material.dart';

import '../api/account_api.dart';
import '../api/catalogue_api.dart';
import '../api/pass_api.dart';
import '../api/playback_api.dart';
import '../auth/auth_controller.dart';
import '../l10n/l10n.dart';
import '../player/video_view.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/velora_button.dart';
import 'devices_screen.dart';
import 'pass_screen.dart';

enum _Phase { granting, playing, failed }

/// Why playback stopped, when it is something the viewer can fix here.
enum _Stop { other, pass, devices, streams, session }

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
///
/// With passes required, Milestone 10, a grant is bound to a playback
/// session that the player keeps alive with a heartbeat. If the session is
/// stopped from another device, the device is removed or the pass ends,
/// the player says so. A device or stream limit offers to manage devices or
/// stop the other playback, then carries on from the same moment.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.itemId,
    required this.title,
    this.episodes = const [],
    this.preview = false,
    this.viewBuilder = platformVideoView,
    this.clock = DateTime.now,
    this.startAt = Duration.zero,
  });

  final String itemId;

  /// Where to start: a saved position, for Resume from watch history.
  final Duration startAt;

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

  /// Where the player got to is saved for watch history at most this often,
  /// and when playback ends or the player closes.
  static const Duration saveEvery = Duration(seconds: 60);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  _Phase _phase = _Phase.granting;
  late String _itemId = widget.itemId;
  PlaybackGrant? _grant;
  String? _message;

  /// What stopped playback, Step 10C and Milestone 10.
  _Stop _stop = _Stop.other;
  bool _passEnded = false;

  /// For a stream limit: what is playing elsewhere.
  List<LiveSession> _elsewhere = const [];

  /// Keeps the playback session alive.
  Timer? _heartbeat;
  late Duration _position = widget.startAt;

  /// Watch history: where the player got to, saved now and then. Null in a
  /// build without playback, and never for an admin's preview.
  AccountApi? _account;
  AuthController? _watcher;
  String? _viewerKey;
  bool _hasProgress = false;
  Future<void> _pendingSave = Future.value();
  DateTime? _savedAt;
  Duration? _savedPosition;
  bool _started = false;
  bool _ended = false;

  /// What this video comes in, from its master playlist. Empty until read,
  /// or if it can't be: then only Auto is offered.
  List<VideoQuality> _qualities = const [];

  /// Where playback has got to, as the video reports it.
  late Duration _playedTo = widget.startAt;

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
      if (!widget.preview) {
        _watcher = AuthScope.of(context);
        _viewerKey = _watcher?.accountKey;
        _account = accountApiOf(context);
      }
      _fetchGrant();
    }
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _savePosition(_playedTo, force: true);
    super.dispose();
  }

  /// Saves where the player got to, for Resume. At most every
  /// [PlayerScreen.saveEvery], unless [force]d, and only once playing.
  void _savePosition(Duration at, {bool finished = false, bool force = false}) {
    final account = _account;
    if (account == null ||
        _grant == null ||
        !_hasProgress ||
        _viewerKey == null ||
        _watcher?.accountKey != _viewerKey) {
      return;
    }
    final now = widget.clock();
    final saved = _savedPosition;
    if (!finished) {
      if (saved != null && (at - saved).abs() < const Duration(seconds: 5)) {
        return;
      }
      final last = _savedAt;
      if (!force &&
          last != null &&
          now.difference(last) < PlayerScreen.saveEvery) {
        return;
      }
    }
    _savedAt = now;
    _savedPosition = at;
    final item = _itemId;
    _pendingSave = _pendingSave.then((_) async {
      if (_viewerKey == _watcher?.accountKey) {
        await account.savePosition(item, at, finished: finished);
      }
    });
  }

  void _progressed(Duration at) {
    if (at <= Duration.zero || (!_hasProgress && at == _position)) return;
    _hasProgress = true;
    _playedTo = at;
    _savePosition(at);
  }

  void _startHeartbeat(PlaybackGrant grant) {
    _heartbeat?.cancel();
    final every = grant.heartbeat;
    final session = grant.sessionId;
    if (every == null || session == null) return;
    _heartbeat = Timer.periodic(every, (_) => _beat(session));
  }

  Future<void> _beat(String session) async {
    final api = PlaybackScope.of(context);
    if (api == null) return;
    final result = await api.heartbeat(session);
    if (!mounted || _grant?.sessionId != session) return;
    _react(result);
  }

  /// What the API said of the session. Answers whether playback must stop.
  bool _react(HeartbeatResult result) {
    switch (result) {
      case HeartbeatResult.passEnded:
        _heartbeat?.cancel();
        _showNeedsPass(ended: true);
        return true;
      case HeartbeatResult.ended || HeartbeatResult.deviceRemoved:
        _heartbeat?.cancel();
        _showStop(_Stop.session, context.l10n.sessionEndedMessage);
        return true;
      case HeartbeatResult.live || HeartbeatResult.unknown:
        return false;
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
      _startHeartbeat(grant);
    } on PlaybackException catch (error) {
      if (itemId != _itemId) return;
      _heartbeat?.cancel();
      switch (error.failure) {
        case PlaybackFailure.needsPass:
          _showNeedsPass(ended: renewal || _grant != null);
        case PlaybackFailure.deviceLimit:
          _showStop(_Stop.devices, l.deviceLimitMessage);
        case PlaybackFailure.streamLimit:
          _elsewhere = error.sessions;
          _showStop(_Stop.streams, l.streamLimitMessage);
        default:
          _showFailure(playbackFailureMessage(l, error.failure));
      }
    }
  }

  void _showStop(_Stop stop, String message) {
    if (!mounted) return;
    setState(() {
      _stop = stop;
      _message = message;
      _phase = _Phase.failed;
    });
  }

  Future<void> _manageDevices() async {
    await DevicesScreen.open(context);
    if (!mounted) return;
    _position = _playedTo;
    await _fetchGrant();
  }

  /// Stops playback on another device, then watches here.
  Future<void> _takeOver(LiveSession session) async {
    final api = PlaybackScope.of(context);
    if (api == null) return;
    try {
      await api.stopSession(session.id);
    } on PassException {
      // Asking for a grant again says what is still in the way.
    }
    if (!mounted) return;
    _position = _playedTo;
    await _fetchGrant();
  }

  /// No pass, or it ended mid-film, Step 10C: offers one, and carries on
  /// from the same moment once it's bought.
  void _showNeedsPass({required bool ended}) {
    if (!mounted) return;
    final l = context.l10n;
    setState(() {
      _stop = _Stop.pass;
      _passEnded = ended;
      _message = ended ? l.passEndedMessage : l.passNeededMessage;
      _phase = _Phase.failed;
    });
  }

  Future<void> _buyPass() async {
    final bought = await BuyPassScreen.open(context);
    if (!bought || !mounted) return;
    _position = _playedTo;
    await _fetchGrant();
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
      _stop = _Stop.other;
      _message = message;
      _phase = _Phase.failed;
    });
  }

  Future<void> _playbackFailed(Duration position) async {
    _position = position;
    _playedTo = position;
    final grant = _grant;
    // A session-bound grant: the gateway may have refused because the
    // session ended. Ask why before anything else.
    final session = grant?.sessionId;
    final api = PlaybackScope.of(context);
    if (session != null && api != null) {
      final result = await api.heartbeat(session);
      if (!mounted || _grant?.sessionId != session) return;
      if (_react(result)) return;
    }
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
    _savePosition(_playedTo, finished: true);
    if (mounted && _next != null) setState(() => _ended = true);
  }

  /// Starts the next episode from its beginning, with a grant of its own.
  void _playNext() {
    final next = _next;
    if (next == null) return;
    _heartbeat?.cancel();
    _savePosition(_playedTo, force: true);
    _savedAt = null;
    _savedPosition = null;
    _hasProgress = false;
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
                child: _failedView(context),
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
                    onProgress: _progressed,
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

extension on _PlayerScreenState {
  Widget _failedView(BuildContext context) {
    final l = context.l10n;
    return switch (_stop) {
      _Stop.pass => ErrorState(
        icon: Icons.workspace_premium_outlined,
        title: _passEnded ? l.passEndedTitle : l.passNeededTitle,
        message: _message!,
        onRetry: _buyPass,
        retryLabel: l.choosePlan,
      ),
      _Stop.devices => ErrorState(
        icon: Icons.devices_outlined,
        title: l.deviceLimitTitle,
        message: _message!,
        onRetry: _manageDevices,
        retryLabel: l.manageDevices,
      ),
      _Stop.streams => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: VeloraSpacing.sm,
        children: [
          ErrorState(
            icon: Icons.tv_off_outlined,
            title: l.streamLimitTitle,
            message: _message!,
            onRetry: _fetchGrant,
          ),
          for (final session in _elsewhere)
            VeloraButton(
              key: ValueKey('take-over-${session.id}'),
              label: l.stopOnDeviceAndWatch(session.deviceLabel),
              icon: Icons.stop_circle_outlined,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _takeOver(session),
            ),
        ],
      ),
      _Stop.session => ErrorState(
        icon: Icons.stop_circle_outlined,
        title: l.sessionEndedTitle,
        message: _message!,
        onRetry: () {
          _position = _playedTo;
          _fetchGrant();
        },
        retryLabel: l.watchHereAgain,
      ),
      _Stop.other => ErrorState(
        title: l.couldNotPlay,
        message: _message!,
        onRetry: _fetchGrant,
      ),
    };
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
