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

/// Asks before something that can't be undone from here. A [danger]
/// action shows in the danger colour. With [typeToConfirm], the action
/// stays off until that word is typed, for deleting many things at once.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool danger = false,
  String? typeToConfirm,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmDialog(
      title: title,
      message: message,
      action: action,
      danger: danger,
      typeToConfirm: typeToConfirm,
    ),
  );
  return answer ?? false;
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.action,
    required this.danger,
    this.typeToConfirm,
  });

  final String title;
  final String message;
  final String action;
  final bool danger;
  final String? typeToConfirm;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _ready =>
      widget.typeToConfirm == null ||
      _typed.text.trim() == widget.typeToConfirm;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final word = widget.typeToConfirm;
    return AlertDialog(
      icon: widget.danger ? const Icon(Icons.warning_amber_rounded) : null,
      title: Text(widget.title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VeloraLayout.readingWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.sm,
          children: [
            Text(widget.message),
            if (word != null)
              TextField(
                controller: _typed,
                autofocus: true,
                decoration: InputDecoration(labelText: l.typeToConfirm(word)),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (_ready) Navigator.of(context).pop(true);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        VeloraButton(
          label: widget.action,
          variant: widget.danger
              ? VeloraButtonVariant.danger
              : VeloraButtonVariant.primary,
          onPressed: _ready ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}

/// "3 min left". Hours and minutes past an hour.
String formatEta(AppLocalizations l, Duration left) {
  if (left.inHours > 0) {
    return l.uploadHoursLeft(left.inHours, left.inMinutes.remainder(60));
  }
  if (left.inMinutes > 0) return l.uploadMinutesLeft(left.inMinutes + 1);
  return l.uploadSecondsLeft(left.inSeconds);
}

/// Where one video is between uploaded and ready: the stage, a bar, and
/// the percentage and time left that the media worker reported. A stage
/// with no figure to show, such as checking, has a moving bar instead.
class VideoStageProgress extends StatelessWidget {
  const VideoStageProgress({
    super.key,
    required this.label,
    required this.item,
  });

  /// "Movie" or "S1 E2".
  final String label;
  final AdminItem item;

  /// States with a stage to show. Others, such as ready, show none.
  static bool shows(String? state) => const {
    'received',
    'checking',
    'converting',
    'publishing',
  }.contains(state);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final percent = item.progress;
    final eta = item.etaSeconds;
    final stage = switch (item.video) {
      'received' => l.stageQueued,
      'checking' => l.stageChecking,
      'converting' => l.stageConverting,
      _ => l.stageSending,
    };
    final detail = [
      if (item.video == 'received' && item.queuePosition != null)
        l.stageQueuePosition(item.queuePosition!),
      if (percent != null) l.uploadPercent(percent),
      if (eta != null) formatEta(l, Duration(seconds: eta)),
      if (item.video == 'checking') l.stageCheckingHelp,
    ].join(' · ');
    return Semantics(
      label: l.stageProgressLabel(label, stage),
      value: percent == null ? null : l.uploadPercent(percent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: VeloraSpacing.xxs,
        children: [
          Text(
            '$label · $stage',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(VeloraRadii.sm),
            child: LinearProgressIndicator(
              // Waiting in the queue: an empty bar. No figure: a moving one.
              value: item.video == 'received'
                  ? 0
                  : percent == null
                  ? null
                  : percent / 100,
              minHeight: 6,
            ),
          ),
          if (detail.isNotEmpty)
            Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Checks a whole number between [min] and [max]. Empty is fine if
/// [optional].
String? checkNumber(
  AppLocalizations l,
  String? value, {
  required int min,
  required int max,
  bool optional = false,
}) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return optional ? null : l.required;
  final number = int.tryParse(text);
  if (number == null || number < min || number > max) {
    return l.numberBetween(min, max);
  }
  return null;
}
