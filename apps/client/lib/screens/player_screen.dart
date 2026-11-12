import 'package:flutter/material.dart';

import '../api/playback_api.dart';
import '../player/video_view.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';

enum _Phase { granting, playing, failed }

/// Watches one movie. Asks the API for a grant, then plays the playlist it
/// names from the media gateway.
///
/// A grant lasts 6 hours. If playback stops once it has run out, or is
/// about to, a new grant is fetched by itself, and playback carries on from
/// the same moment. Any other stop offers Try again, from the same moment.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({
    super.key,
    required this.movieId,
    required this.title,
    this.viewBuilder = platformVideoView,
    this.clock = DateTime.now,
  });

  final String movieId;
  final String title;

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
  PlaybackGrant? _grant;
  String? _message;
  Duration _position = Duration.zero;
  bool _started = false;

  /// Renewing by itself happens once per grant, so a gateway that refuses a
  /// fresh grant can't cause a loop.
  bool _renewedThisGrant = false;

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
    final api = PlaybackScope.of(context);
    if (api == null) {
      _showFailure(playbackFailureMessage(PlaybackFailure.unreachable));
      return;
    }
    try {
      final grant = await api.grant(widget.movieId);
      if (!mounted) return;
      setState(() {
        _grant = grant;
        _renewedThisGrant = renewal;
        _phase = _Phase.playing;
      });
    } on PlaybackException catch (error) {
      _showFailure(playbackFailureMessage(error.failure));
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
    _showFailure(
      "Playback stopped. Check your connection, then try again from "
      'where you were.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final grant = _grant;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: switch (_phase) {
          _Phase.granting => const Center(
            child: VeloraLoadingRegion(
              label: 'Getting the movie ready',
              child: VeloraSpinner(size: 32),
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
                  title: "Couldn't play this movie",
                  message: _message!,
                  onRetry: _fetchGrant,
                ),
              ),
            ),
          ),
          _Phase.playing => widget.viewBuilder(
            context,
            VideoViewRequest(
              url: grant!.playlistUrl,
              startAt: _position,
              onFailed: _playbackFailed,
            ),
          ),
        },
      ),
    );
  }
}
