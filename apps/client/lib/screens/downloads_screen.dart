import 'package:flutter/material.dart';

import '../downloads/download_manager.dart';
import '../downloads/download_ui.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import 'devices_screen.dart';
import 'pass_screen.dart';

/// Every download on this phone: its progress, pause, resume and delete,
/// and play once it's done. A tab on Android; also opened from a movie's or
/// an episode's Download.
class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  /// The same list on a page of its own.
  static Future<void> open(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(context.l10n.downloads)),
        body: const SafeArea(child: DownloadsScreen()),
      ),
    ),
  );

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  bool _checking = false;

  /// Renews every licence now, as the viewer asked.
  Future<void> _checkNow(DownloadManager downloads) async {
    setState(() => _checking = true);
    final reached = await downloads.renewLicences(force: true);
    if (!mounted) return;
    setState(() => _checking = false);
    if (!reached) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(context.l10n.checkInFailed)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final downloads = DownloadsScope.of(context);
    if (downloads == null || !downloads.loaded) {
      return Center(
        child: VeloraLoadingRegion(
          label: l.downloads,
          child: const VeloraSpinner(size: 32),
        ),
      );
    }
    final all = downloads.downloads;
    final needsCheck = all.any((d) {
      final watchable = downloads.watchable(d);
      return watchable == Watchable.checkIn ||
          watchable == Watchable.clockChanged;
    });
    return ScreenBody(
      heading: l.downloads,
      intro: l.downloadsOfflineNote(DownloadManager.offlineDays),
      status: all.isEmpty
          ? null
          : StatusBadge(
              label: l.downloadsUsed(formatBytes(context, downloads.usedBytes)),
              icon: Icons.sd_storage_outlined,
            ),
      children: [
        if (all.isEmpty)
          EmptyState(
            icon: Icons.download_for_offline_outlined,
            title: l.downloadsEmptyTitle,
            message: l.downloadsEmptyMessage,
          ),
        if (needsCheck)
          Align(
            alignment: Alignment.centerLeft,
            child: VeloraButton(
              label: l.checkNow,
              icon: Icons.sync,
              variant: VeloraButtonVariant.secondary,
              isLoading: _checking,
              onPressed: () => _checkNow(downloads),
            ),
          ),
        for (final download in all)
          _DownloadTile(
            key: ValueKey(download.itemId),
            downloads: downloads,
            download: download,
          ),
      ],
    );
  }
}

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    super.key,
    required this.downloads,
    required this.download,
  });

  final DownloadManager downloads;
  final Download download;

  Future<void> _confirmDelete(BuildContext context) async {
    final l = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteDownloadTitle),
        content: Text(l.deleteDownloadMessage(_title(l))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (yes == true) await downloads.remove(download.itemId);
  }

  String _title(AppLocalizations l) {
    final info = download.info;
    return info.isEpisode
        ? l.episodeHeading(info.title, info.season!, info.episode!)
        : info.title;
  }

  /// What fixes a download's problem, if the viewer can do it here.
  Widget? _fix(BuildContext context) {
    final l = context.l10n;
    return switch (download.problem) {
      DownloadProblem.noPass => VeloraButton(
        label: l.choosePlan,
        icon: Icons.workspace_premium_outlined,
        variant: VeloraButtonVariant.tertiary,
        onPressed: () async {
          if (await BuyPassScreen.open(context)) {
            await downloads.renewLicences(force: true);
          }
        },
      ),
      DownloadProblem.deviceLimit => VeloraButton(
        label: l.manageDevices,
        icon: Icons.devices_outlined,
        variant: VeloraButtonVariant.tertiary,
        onPressed: () async {
          await DevicesScreen.open(context);
          await downloads.renewLicences(force: true);
        },
      ),
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final info = download.info;
    final state = download.state;
    final watchable = downloads.watchable(download);
    final busy =
        state == DownloadState.downloading ||
        state == DownloadState.queued ||
        state == DownloadState.waiting;
    final size = state == DownloadState.done || download.bytes > 0
        ? formatBytes(context, download.bytes)
        : switch (download.estimatedBytes) {
            final bytes? => l.downloadAbout(formatBytes(context, bytes)),
            null => null,
          };
    final facts = [
      download.quality.label,
      ?size,
      downloadStateLabel(l, download),
    ].join(' · ');
    final problem = download.problem != null
        ? downloadProblemMessage(l, download.problem)
        : switch (watchable) {
            Watchable.checkIn => l.downloadCheckIn,
            Watchable.clockChanged => l.downloadClockChanged,
            _ => null,
          };
    final fix = _fix(context);
    final poster = downloads.poster(download);

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.xs,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: VeloraSpacing.sm,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(VeloraRadii.sm),
                  child: SizedBox(
                    width: 56,
                    height: 84,
                    child: poster == null
                        ? ColoredBox(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined),
                          )
                        : Image(
                            image: poster,
                            fit: BoxFit.cover,
                            excludeFromSemantics: true,
                            errorBuilder: (context, _, _) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.movie_outlined),
                            ),
                          ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: VeloraSpacing.xxs,
                    children: [
                      Text(_title(l), style: theme.textTheme.titleMedium),
                      if (info.episodeTitle case final name?)
                        Text(name, style: muted),
                      Text(info.label, style: muted),
                      Text(facts, style: muted),
                      if (state == DownloadState.done &&
                          watchable == Watchable.yes)
                        Text(
                          l.playsOfflineUntil(
                            formatPassEnd(context, download.offlineUntil),
                          ),
                          style: muted,
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (busy)
              LinearProgressIndicator(
                value: download.progress,
                semanticsLabel: downloadStateLabel(l, download),
              ),
            if (problem != null)
              Text(
                problem,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: VeloraSpacing.xs,
              children: [
                ?fix,
                if (state == DownloadState.done)
                  VeloraButton(
                    label: l.play,
                    icon: Icons.play_arrow,
                    onPressed: () => openDownload(context, download),
                  ),
                if (busy)
                  IconButton(
                    tooltip: l.pauseDownload,
                    icon: const Icon(Icons.pause),
                    onPressed: () => downloads.pause(download.itemId),
                  ),
                if (state == DownloadState.paused ||
                    (state == DownloadState.failed && fix == null))
                  IconButton(
                    tooltip: state == DownloadState.paused
                        ? l.resumeDownload
                        : l.tryAgain,
                    icon: Icon(
                      state == DownloadState.paused
                          ? Icons.play_circle_outline
                          : Icons.refresh,
                    ),
                    onPressed: () => downloads.resume(download.itemId),
                  ),
                IconButton(
                  tooltip: l.deleteDownload,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
