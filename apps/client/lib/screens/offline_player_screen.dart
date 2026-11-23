import 'package:flutter/material.dart';

import '../downloads/download_manager.dart';
import '../l10n/l10n.dart';
import '../player/video_view.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';

/// Plays a download from the phone, with no connection needed: the same
/// player as streaming, given the download's own master playlist, which
/// names only the quality downloaded.
///
/// The download's licence is checked before this screen opens, by
/// openDownload, and again here if it runs out while watching.
class OfflinePlayerScreen extends StatefulWidget {
  const OfflinePlayerScreen({
    super.key,
    required this.download,
    this.viewBuilder = platformVideoView,
  });

  final Download download;

  /// Replaced in tests, which can't play video.
  final VideoViewBuilder viewBuilder;

  @override
  State<OfflinePlayerScreen> createState() => _OfflinePlayerScreenState();
}

class _OfflinePlayerScreenState extends State<OfflinePlayerScreen> {
  bool _failed = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final downloads = DownloadsScope.of(context);
    final download = widget.download;
    final info = download.info;
    final title = info.isEpisode
        ? l.episodeHeading(info.title, info.season!, info.episode!)
        : info.title;
    final watchable = downloads?.watchable(download) ?? Watchable.notFinished;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: _failed || watchable != Watchable.yes || downloads == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(VeloraSpacing.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: VeloraLayout.readingWidth,
                    ),
                    child: ErrorState(
                      title: l.couldNotPlay,
                      message: _failed
                          ? l.offlinePlaybackFailed
                          : watchable == Watchable.clockChanged
                          ? l.downloadClockChanged
                          : l.downloadCheckIn,
                      onRetry: () => Navigator.of(context).maybePop(),
                      retryLabel: l.back,
                    ),
                  ),
                ),
              )
            : widget.viewBuilder(
                context,
                VideoViewRequest(
                  url: downloads.playUri(download),
                  startAt: Duration.zero,
                  onFailed: (_) {
                    if (mounted) setState(() => _failed = true);
                  },
                ),
              ),
      ),
    );
  }
}
