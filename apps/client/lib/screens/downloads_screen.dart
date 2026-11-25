import 'package:flutter/material.dart';

import '../downloads/download_ui.dart';
import '../downloads/downloads.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';

/// The downloads started on this phone: their progress, and Open once
/// done. Android saves them to Downloads/VeloraUG, where they stay, theirs
/// to keep, whatever happens to the app. A tab on Android; also opened from
/// a movie's or an episode's Download.
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
  @override
  void initState() {
    super.initState();
    // Android may have finished or failed some while the app was away.
    // Once, here: refreshing notifies this screen, so doing it on every
    // change of dependencies would never stop.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) DownloadsScope.peek(context)?.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final downloads = DownloadsScope.of(context);
    if (downloads != null && !downloads.followed) {
      return ScreenBody(
        heading: l.downloads,
        children: [
          EmptyState(
            icon: Icons.phone_android,
            title: l.androidOnlyTitle,
            message: l.androidOnlyMessage,
          ),
        ],
      );
    }
    if (downloads == null || !downloads.loaded) {
      return Center(
        child: VeloraLoadingRegion(
          label: l.downloads,
          child: const VeloraSpinner(size: VeloraIconSizes.large),
        ),
      );
    }
    final all = downloads.downloads;
    final used = downloads.usedBytes;
    return ScreenBody(
      heading: l.downloads,
      intro: l.downloadsFolderNote,
      status: used == 0
          ? null
          : StatusBadge(
              label: l.downloadsUsed(formatBytes(context, used)),
              icon: Icons.sd_storage_outlined,
            ),
      children: [
        if (all.isEmpty)
          EmptyState(
            icon: Icons.download_for_offline_outlined,
            title: l.downloadsEmptyTitle,
            message: l.downloadsEmptyMessage,
          ),
        for (final (title, group) in [
          (l.downloadsInProgress, all.where(_inProgress).toList()),
          (
            l.downloadsCompleted,
            all.where((d) => d.state == FileState.done).toList(),
          ),
          (
            l.downloadsFailed,
            all.where((d) => d.state == FileState.failed).toList(),
          ),
        ])
          if (group.isNotEmpty) ...[
            Semantics(
              header: true,
              child: Text(
                l.downloadsGroup(title, group.length),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final download in group)
              _DownloadTile(
                key: ValueKey(download.id),
                downloads: downloads,
                download: download,
              ),
          ],
      ],
    );
  }
}

/// Queued, downloading, or paused for any reason.
bool _inProgress(Download download) =>
    download.state == FileState.waiting ||
    download.state == FileState.running ||
    download.state == FileState.paused;

class _DownloadTile extends StatelessWidget {
  const _DownloadTile({
    super.key,
    required this.downloads,
    required this.download,
  });

  final Downloads downloads;
  final Download download;

  String _title(AppLocalizations l) {
    final info = download.info;
    return info.isEpisode
        ? l.episodeHeading(info.title, info.season!, info.episode!)
        : info.title;
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteDownloadTitle),
        content: Text(l.deleteDownloadMessage(download.fileName)),
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
    if (yes == true) await downloads.remove(download);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final state = download.state;
    final busy =
        state == FileState.waiting ||
        state == FileState.running ||
        state == FileState.paused;
    // While downloading: how much has arrived. Once done: the file's size.
    final size = busy
        ? downloadBytesLabel(context, download)
        : switch (download.status.total) {
            final total? => formatBytes(context, total),
            null => null,
          };
    final facts = [
      download.quality,
      ?size,
      downloadStateLabel(l, download),
    ].join(' · ');

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
                Icon(
                  state == FileState.done
                      ? Icons.movie_outlined
                      : Icons.downloading,
                  size: VeloraIconSizes.large,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: VeloraSpacing.xxs,
                    children: [
                      Text(_title(l), style: theme.textTheme.titleMedium),
                      if (download.info.episodeTitle case final name?)
                        Text(name, style: muted),
                      Text(download.info.label, style: muted),
                      Text(facts, style: muted),
                      Text(download.fileName, style: muted),
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
            if (state == FileState.failed && download.status.noRoom)
              Text(
                l.downloadNoRoom,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: VeloraSpacing.xs,
              children: [
                if (state == FileState.done)
                  Semantics(
                    label: l.openDownloadNamed(_title(l)),
                    excludeSemantics: true,
                    button: true,
                    child: VeloraButton(
                      label: l.openDownload,
                      icon: Icons.play_arrow,
                      onPressed: () => openDownload(context, download),
                    ),
                  ),
                if (state == FileState.failed)
                  VeloraButton(
                    label: l.downloadAgain,
                    icon: Icons.refresh,
                    variant: VeloraButtonVariant.secondary,
                    onPressed: () async {
                      await downloads.remove(download);
                      if (context.mounted) {
                        await startDownload(
                          context,
                          itemId: download.itemId,
                          info: download.info,
                        );
                      }
                    },
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
