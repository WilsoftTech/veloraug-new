import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';

/// Runs an admin action. A failure, or [done] on success, shows in a snack
/// bar. Returns null on failure.
Future<T?> runAdmin<T>(
  BuildContext context,
  Future<T> Function(AdminApi api) action, {
  String? done,
}) async {
  final api = AdminScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final l = context.l10n;
  if (api == null) {
    messenger.showSnackBar(SnackBar(content: Text(l.adminNotSetUp)));
    return null;
  }
  try {
    final result = await action(api);
    if (done != null) messenger.showSnackBar(SnackBar(content: Text(done)));
    return result;
  } on AdminException catch (error) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(adminFailureMessage(l, error)),
        duration: const Duration(seconds: 8),
      ),
    );
    return null;
  }
}

/// What publishing still needs, in the app's words when the API's phrase is
/// known, and in the API's otherwise.
String missingLabel(AppLocalizations l, String missing) => switch (missing) {
  'a ready video' => l.missingVideo,
  'details, from TMDB or typed in' => l.missingDetails,
  'a chosen poster' => l.missingPoster,
  'a confirmed VJ credit' => l.missingCredit,
  _ => missing,
};

/// A video's state, from upload to ready.
(String, StatusTone) videoState(AppLocalizations l, String? state) =>
    switch (state) {
      null => (l.videoNone, StatusTone.neutral),
      'uploading' => (l.videoUploading, StatusTone.info),
      'received' || 'checking' => (l.videoChecking, StatusTone.info),
      'converting' || 'publishing' => (l.videoConverting, StatusTone.info),
      'ready' => (l.videoReady, StatusTone.success),
      'refused' => (l.videoRefused, StatusTone.danger),
      'failed' => (l.videoFailed, StatusTone.danger),
      'removing' || 'removed' => (l.videoRemoved, StatusTone.warning),
      _ => (state, StatusTone.neutral),
    };

(String, StatusTone) editionStatus(AppLocalizations l, AdminEdition e) =>
    switch (e.status) {
      'published' => (l.statusPublished, StatusTone.success),
      'hidden' => (l.statusHidden, StatusTone.warning),
      _ => (l.statusDraft, StatusTone.info),
    };

/// "S1 E2" for an episode, nothing for a movie's one video.
String itemName(AppLocalizations l, AdminItem item) =>
    item.season == null || item.episode == null
    ? l.movieVideo
    : l.episodeShort(item.season!, item.episode!);

/// Shows a new upload key once, with Copy. It is never kept by the app.
Future<void> showUploadKey(BuildContext context, KeyMade key) {
  final l = context.l10n;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: Text(l.uploadKeyTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VeloraLayout.readingWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.sm,
          children: [
            Text(l.uploadKeyOnce),
            SelectableText(
              key.uploadKey,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            Text(
              l.uploadKeyExpires(
                MaterialLocalizations.of(context)
                    .formatMediumDate(key.expiresAt.toLocal()),
              ),
            ),
            Text(l.uploadKeyHowTo),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          icon: const Icon(Icons.copy),
          label: Text(l.copy),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: key.uploadKey));
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(l.copied)));
            }
          },
        ),
        VeloraButton(
          label: l.done,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

/// A titled card that groups one part of a draft.
class AdminSection extends StatelessWidget {
  const AdminSection({
    super.key,
    required this.title,
    required this.children,
    this.status,
  });

  final String title;
  final List<Widget> children;
  final Widget? status;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.sm,
          children: [
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                ?status,
              ],
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Asks before something that can't be undone from here.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final l = context.l10n;
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        VeloraButton(
          label: action,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return answer ?? false;
}
