import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/playback_api.dart';
import '../l10n/l10n.dart';
import '../screens/devices_screen.dart';
import '../screens/downloads_screen.dart';
import '../screens/pass_screen.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/velora_button.dart';
import 'downloads.dart';

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

/// One short line for where a download on the phone has got to.
String downloadStateLabel(AppLocalizations l, Download download) =>
    switch (download.state) {
      FileState.waiting => l.downloadQueued,
      FileState.running => l.downloadingPercent(
        ((download.progress ?? 0) * 100).floor(),
      ),
      FileState.paused => l.downloadPaused,
      FileState.done => l.downloaded,
      FileState.failed => l.downloadFailed,
    };

void _say(
  ScaffoldMessengerState messenger,
  String text, {
  SnackBarAction? action,
}) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text), action: action));

/// Asks which quality to download, then has the browser or the phone save
/// it.
Future<void> startDownload(
  BuildContext context, {
  required String itemId,
  required DownloadInfo info,
}) async {
  final downloads = DownloadsScope.peek(context);
  if (downloads == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  final l = context.l10n;
  final file = await showModalBottomSheet<DownloadFile>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _DownloadSheet(downloads: downloads, itemId: itemId),
  );
  if (file == null) return;
  try {
    await downloads.start(itemId, file, info);
  } on DownloadRefused catch (refusal) {
    _say(
      messenger,
      refusal.reason == DownloadRefusal.noPermission
          ? l.downloadNoPermission
          : l.downloadStartFailed,
    );
    return;
  }
  if (downloads.followed) {
    _say(
      messenger,
      l.downloadStartedPhone(file.fileName),
      action: SnackBarAction(
        label: l.downloads,
        onPressed: () => DownloadsScreen.open(navigator.context),
      ),
    );
  } else {
    _say(messenger, l.downloadStartedBrowser(file.fileName));
  }
}

/// Opens a finished download in the phone's video player, or says why not.
Future<void> openDownload(BuildContext context, Download download) async {
  final downloads = DownloadsScope.peek(context);
  if (downloads == null) return;
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  if (!await downloads.open(download)) _say(messenger, l.openDownloadFailed);
}

enum _SheetPhase { preparing, choosing, failed }

/// Gets a download ready, then offers each quality with its size.
class _DownloadSheet extends StatefulWidget {
  const _DownloadSheet({required this.downloads, required this.itemId});

  final Downloads downloads;
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
      final offer = await widget.downloads.offer(widget.itemId);
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
          message: _failure == PlaybackFailure.notReady
              ? l.downloadNotReady
              : playbackFailureMessage(l, _failure!),
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
                  widget.downloads.followed
                      ? l.downloadKeepPhone
                      : l.downloadKeepBrowser,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: VeloraSpacing.xs),
          for (final file in offer!.files)
            ListTile(
              key: ValueKey('download-${file.quality.label}'),
              leading: Icon(
                file.quality.height >= 720
                    ? Icons.hd_outlined
                    : Icons.sd_outlined,
              ),
              title: Text(file.quality.label),
              subtitle: switch (file.bytes) {
                final bytes? => Text(formatBytes(context, bytes)),
                null => file.quality.height >= 720 ? Text(l.qualityHd) : null,
              },
              trailing: const Icon(Icons.download_outlined),
              onTap: () => Navigator.of(context).pop(file),
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

/// Download on a movie's page. On a phone it then shows the download's
/// progress, and opens it once done.
class DownloadButton extends StatelessWidget {
  const DownloadButton({super.key, required this.itemId, required this.info});

  final String itemId;
  final DownloadInfo info;

  @override
  Widget build(BuildContext context) {
    final downloads = DownloadsScope.of(context);
    if (downloads == null) return const SizedBox.shrink();
    final l = context.l10n;
    final download = downloads.latestOf(itemId);
    if (download == null || download.state == FileState.failed) {
      return VeloraButton(
        label: download == null ? l.download : l.downloadAgain,
        icon: Icons.download_outlined,
        variant: VeloraButtonVariant.secondary,
        onPressed: () => startDownload(context, itemId: itemId, info: info),
      );
    }
    return VeloraButton(
      label: downloadStateLabel(l, download),
      icon: download.state == FileState.done
          ? Icons.download_done
          : Icons.downloading,
      variant: VeloraButtonVariant.secondary,
      onPressed: () => download.state == FileState.done
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
    final download = downloads.latestOf(itemId);
    final name = l.downloadEpisode(info.season ?? 0, info.episode ?? 0);
    if (download == null || download.state == FileState.failed) {
      return IconButton(
        tooltip: download == null ? name : '$name: ${l.downloadFailed}',
        icon: Icon(
          download == null ? Icons.download_outlined : Icons.error_outline,
        ),
        onPressed: () => startDownload(context, itemId: itemId, info: info),
      );
    }
    final label = '$name: ${downloadStateLabel(l, download)}';
    if (download.state == FileState.done) {
      return IconButton(
        tooltip: label,
        icon: const Icon(Icons.download_done),
        onPressed: () => openDownload(context, download),
      );
    }
    return IconButton(
      tooltip: label,
      onPressed: () => DownloadsScreen.open(context),
      icon: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(
          value: download.progress,
          strokeWidth: 2.5,
          semanticsLabel: label,
        ),
      ),
    );
  }
}
