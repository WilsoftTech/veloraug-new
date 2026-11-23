import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/playback_api.dart';
import '../l10n/l10n.dart';
import '../screens/devices_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/offline_player_screen.dart';
import '../screens/pass_screen.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/velora_button.dart';
import 'download_manager.dart';
import 'hls.dart';

/// "1.2 GB" or "350 MB".
String formatBytes(BuildContext context, int bytes) {
  final l = context.l10n;
  final locale = Localizations.localeOf(context).toLanguageTag();
  const mb = 1000 * 1000;
  if (bytes >= 1000 * mb) {
    return l.sizeGb(NumberFormat('0.0', locale).format(bytes / (1000 * mb)));
  }
  return l.sizeMb(
    NumberFormat.decimalPattern(locale).format((bytes / mb).ceil()),
  );
}

String downloadProblemMessage(AppLocalizations l, DownloadProblem? problem) =>
    switch (problem) {
      DownloadProblem.noPass => l.downloadProblemNoPass,
      DownloadProblem.deviceLimit => l.downloadProblemDeviceLimit,
      DownloadProblem.deviceRemoved => l.downloadProblemDeviceRemoved,
      DownloadProblem.storageFull => l.downloadProblemStorageFull,
      DownloadProblem.signedOut => l.downloadProblemSignedOut,
      DownloadProblem.unexpected || null => l.downloadProblemOther,
    };

/// One short line for where a download has got to.
String downloadStateLabel(AppLocalizations l, Download download) =>
    switch (download.state) {
      DownloadState.queued => l.downloadQueued,
      DownloadState.downloading => l.downloadingPercent(
        ((download.progress ?? 0) * 100).floor(),
      ),
      DownloadState.waiting => l.downloadWaiting,
      DownloadState.paused => l.downloadPaused,
      DownloadState.done => l.downloaded,
      DownloadState.failed => l.downloadStopped,
      DownloadState.unavailable => l.downloadUnavailable,
    };

/// Asks which quality to download, then starts it, from a movie's or an
/// episode's page.
Future<void> startDownload(
  BuildContext context, {
  required String itemId,
  required DownloadInfo info,
}) async {
  final downloads = DownloadsScope.of(context);
  if (downloads == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  final chosen = await showModalBottomSheet<_Choice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DownloadSheet(downloads: downloads, itemId: itemId),
  );
  if (chosen == null) return;
  await downloads.start(chosen.offer, chosen.quality, info);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(l.downloadStarted(info.title)),
        action: SnackBarAction(
          label: l.downloads,
          onPressed: () => DownloadsScreen.open(messenger.context),
        ),
      ),
    );
}

/// Plays a finished download, or says why it can't play yet.
Future<void> openDownload(BuildContext context, Download download) async {
  final downloads = DownloadsScope.of(context);
  if (downloads == null) return;
  var watchable = downloads.watchable(download);
  if (watchable == Watchable.checkIn || watchable == Watchable.clockChanged) {
    // Online, this renews the licence at once.
    await downloads.renewLicences(force: true);
    if (!context.mounted) return;
    watchable = downloads.watchable(download);
  }
  if (!context.mounted) return;
  switch (watchable) {
    case Watchable.yes:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => OfflinePlayerScreen(download: download),
        ),
      );
    case Watchable.notFinished:
      await DownloadsScreen.open(context);
    case Watchable.checkIn || Watchable.clockChanged:
      final l = context.l10n;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              download.problem != null
                  ? downloadProblemMessage(l, download.problem)
                  : watchable == Watchable.clockChanged
                  ? l.downloadClockChanged
                  : l.downloadCheckIn,
            ),
          ),
        );
  }
}

/// What the viewer chose in the sheet.
class _Choice {
  const _Choice(this.offer, this.quality);

  final DownloadOffer offer;
  final DownloadQuality quality;
}

enum _SheetPhase { preparing, choosing, failed }

/// Gets a download ready, then offers its qualities with their sizes.
class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({required this.downloads, required this.itemId});

  final DownloadManager downloads;
  final String itemId;

  @override
  State<_DownloadSheet> createState() => _DownloadSheetState();
}

class _DownloadSheetState extends State<_DownloadSheet> {
  _SheetPhase _phase = _SheetPhase.preparing;
  DownloadOffer? _offer;
  PlaybackFailure? _failure;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    setState(() => _phase = _SheetPhase.preparing);
    try {
      final offer = await widget.downloads.prepare(widget.itemId);
      if (!mounted) return;
      setState(() {
        _offer = offer;
        _phase = _SheetPhase.choosing;
      });
    } on PlaybackException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error.failure;
        _phase = _SheetPhase.failed;
      });
    }
  }

  /// Fixes what stopped the download, then tries again.
  Future<void> _fix() async {
    switch (_failure) {
      case PlaybackFailure.needsPass:
        final bought = await BuyPassScreen.open(context);
        if (!bought) return;
      case PlaybackFailure.deviceLimit:
        await DevicesScreen.open(context);
      default:
        break;
    }
    if (mounted) await _prepare();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final offer = _offer;
    final content = switch (_phase) {
      _SheetPhase.preparing => Padding(
        padding: const EdgeInsets.all(VeloraSpacing.lg),
        child: VeloraLoadingRegion(
          label: l.downloadPreparing,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: VeloraSpacing.md,
            children: [
              const VeloraSpinner(size: 32),
              Text(l.downloadPreparing),
            ],
          ),
        ),
      ),
      _SheetPhase.failed => Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: ErrorState(
          title: l.downloadCouldNotStart,
          message: playbackFailureMessage(l, _failure!),
          onRetry: _fix,
          retryLabel: switch (_failure) {
            PlaybackFailure.needsPass => l.choosePlan,
            PlaybackFailure.deviceLimit => l.manageDevices,
            _ => null,
          },
        ),
      ),
      _SheetPhase.choosing => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeloraSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: VeloraSpacing.xxs,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l.downloadChooseQuality,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Text(
                  l.downloadQualityHelp,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VeloraSpacing.xs),
          for (final quality in offer!.qualities)
            ListTile(
              key: ValueKey('download-${quality.quality.label}'),
              leading: Icon(
                quality.quality.height >= 720
                    ? Icons.hd_outlined
                    : Icons.sd_outlined,
              ),
              title: Text(quality.quality.label),
              subtitle: switch (quality.estimatedBytes) {
                final bytes? => Text(
                  l.downloadAbout(formatBytes(context, bytes)),
                ),
                null =>
                  quality.quality.height >= 720 ? Text(l.qualityHd) : null,
              },
              trailing: const Icon(Icons.download_outlined),
              onTap: () => Navigator.of(context).pop(_Choice(offer, quality)),
            ),
        ],
      ),
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: VeloraSpacing.md),
        child: content,
      ),
    );
  }
}

/// Download on a movie's page: Download, its progress, or Downloaded,
/// which plays it. Nothing on the web.
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.itemId, required this.info});

  final String itemId;
  final DownloadInfo info;

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadsScope.of(context);
    if (downloads == null) return const SizedBox.shrink();
    final l = context.l10n;
    final download = downloads[itemId];
    if (download == null || download.state == DownloadState.unavailable) {
      return VeloraButton(
        label: l.download,
        icon: Icons.download_outlined,
        variant: VeloraButtonVariant.secondary,
        onPressed: () => startDownload(context, itemId: itemId, info: info),
      );
    }
    return VeloraButton(
      label: downloadStateLabel(l, download),
      icon: switch (download.state) {
        DownloadState.done => Icons.download_done,
        DownloadState.failed => Icons.error_outline,
        DownloadState.paused => Icons.pause_circle_outline,
        _ => Icons.downloading,
      },
      variant: VeloraButtonVariant.secondary,
      onPressed: () => download.state == DownloadState.done
          ? openDownload(context, download)
          : DownloadsScreen.open(context),
    );
  }
}

/// Download beside an episode: an icon, with its progress around it.
class EpisodeDownloadButton extends StatelessWidget {
  const EpisodeDownloadButton({
    super.key,
    required this.itemId,
    required this.info,
  });

  final String itemId;
  final DownloadInfo info;

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadsScope.of(context);
    if (downloads == null) return const SizedBox.shrink();
    final l = context.l10n;
    final download = downloads[itemId];
    final name = l.downloadEpisode(info.season ?? 0, info.episode ?? 0);
    if (download == null || download.state == DownloadState.unavailable) {
      return IconButton(
        tooltip: name,
        icon: const Icon(Icons.download_outlined),
        onPressed: () => startDownload(context, itemId: itemId, info: info),
      );
    }
    final label = '$name: ${downloadStateLabel(l, download)}';
    final busy =
        download.state == DownloadState.downloading ||
        download.state == DownloadState.queued ||
        download.state == DownloadState.waiting;
    return IconButton(
      tooltip: label,
      onPressed: () => download.state == DownloadState.done
          ? openDownload(context, download)
          : DownloadsScreen.open(context),
      icon: busy
          ? SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(
                value: download.progress,
                strokeWidth: 2.5,
                semanticsLabel: label,
              ),
            )
          : Icon(switch (download.state) {
              DownloadState.done => Icons.download_done,
              DownloadState.failed => Icons.error_outline,
              _ => Icons.pause_circle_outline,
            }),
    );
  }
}
