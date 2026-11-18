/// The video surface, chosen when the app is built: hls.js in a `<video>`
/// element on the web, and ExoPlayer, through video_player, on Android.
///
/// Both take a master playlist address on the media gateway, start at
/// [VideoViewRequest.startAt], and call [VideoViewRequest.onFailed] with the
/// position reached if playback stops with an error, such as the gateway
/// refusing a chunk once the grant has run out. They call
/// [VideoViewRequest.onEnded] once when the video plays to its end.
library;

import 'package:flutter/widgets.dart';

export 'video_view_io.dart' if (dart.library.js_interop) 'video_view_web.dart';

class VideoViewRequest {
  const VideoViewRequest({
    required this.url,
    required this.startAt,
    required this.onFailed,
    this.onEnded,
  });

  final Uri url;
  final Duration startAt;
  final ValueChanged<Duration> onFailed;

  /// For Next Episode.
  final VoidCallback? onEnded;
}

typedef VideoViewBuilder = Widget Function(
  BuildContext context,
  VideoViewRequest request,
);
