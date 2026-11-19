import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../theme/tokens.dart';
import 'video_view.dart';
import '../l10n/l10n.dart';

/// ExoPlayer on Android, through video_player.
Widget platformVideoView(BuildContext context, VideoViewRequest request) =>
    _NativeVideoView(key: ValueKey(request.url), request: request);

class _NativeVideoView extends StatefulWidget {
  const _NativeVideoView({super.key, required this.request});

  final VideoViewRequest request;

  @override
  State<_NativeVideoView> createState() => _NativeVideoViewState();
}

class _NativeVideoViewState extends State<_NativeVideoView> {
  late final VideoPlayerController _controller;
  bool _reported = false;
  bool _ended = false;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      widget.request.url,
      formatHint: VideoFormat.hls,
    )..addListener(_changed);
    _start();
  }

  Future<void> _start() async {
    try {
      await _controller.initialize();
      if (widget.request.startAt > Duration.zero) {
        await _controller.seekTo(widget.request.startAt);
      }
      await _controller.play();
      if (mounted) setState(() => _ready = true);
    } on Object {
      _fail();
    }
  }

  void _changed() {
    final value = _controller.value;
    if (value.hasError) {
      _fail();
      return;
    }
    if (_ready && value.position > Duration.zero) {
      widget.request.onProgress?.call(value.position);
    }
    if (value.isCompleted && !_ended && mounted) {
      _ended = true;
      widget.request.onEnded?.call();
    }
  }

  void _fail() {
    if (_reported || !mounted) return;
    _reported = true;
    final position = _controller.value.position;
    widget.request.onFailed(
      position > Duration.zero ? position : widget.request.startAt,
    );
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return Center(
        child: CircularProgressIndicator(
          semanticsLabel: context.l10n.loadingVideo,
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: Center(
            child: AspectRatio(
              aspectRatio: _controller.value.aspectRatio,
              child: VideoPlayer(_controller),
            ),
          ),
        ),
        _Controls(controller: _controller),
      ],
    );
  }
}

String _clock(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

class _Controls extends StatefulWidget {
  const _Controls({required this.controller});

  final VideoPlayerController controller;

  @override
  State<_Controls> createState() => _ControlsState();
}

class _ControlsState extends State<_Controls> {
  /// While the slider is dragged: where it is, in milliseconds. One seek is
  /// made when the drag ends, not one per movement.
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final total = value.duration.inMilliseconds.toDouble();
        final at =
            _dragging ??
            value.position.inMilliseconds
                .clamp(0, value.duration.inMilliseconds)
                .toDouble();
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VeloraSpacing.sm,
            vertical: VeloraSpacing.xs,
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: value.isPlaying
                    ? context.l10n.pause
                    : context.l10n.play,
                icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                color: Colors.white,
                onPressed: value.isPlaying ? controller.pause : controller.play,
              ),
              Text(
                _clock(value.position),
                style: const TextStyle(color: Colors.white),
              ),
              Expanded(
                child: Semantics(
                  label: context.l10n.position,
                  child: Slider(
                    value: total > 0 ? at : 0,
                    max: total > 0 ? total : 1,
                    onChanged: total > 0
                        ? (ms) => setState(() => _dragging = ms)
                        : null,
                    onChangeEnd: (ms) {
                      setState(() => _dragging = null);
                      controller.seekTo(Duration(milliseconds: ms.round()));
                    },
                  ),
                ),
              ),
              Text(
                _clock(value.duration),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        );
      },
    );
  }
}
