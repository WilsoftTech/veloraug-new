import 'dart:async';

import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/catalogue_api.dart' show EditionKind;
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import 'admin_common.dart';
import 'draft_screen.dart';
import 'new_draft_screen.dart';
import 'uploads/upload_queue.dart';
import 'uploads/uploads_view.dart' show UploadsScope;

/// While a video is being checked, converted or sent, Drafts asks again
/// this often, so its bar moves.
const Duration draftsRefreshEvery = Duration(seconds: 5);

/// The word typed to delete every draft. The API asks for the same word.
const String deleteAllWord = 'DELETE';

/// Drafts whose video has finished uploading, hidden editions, and series
/// with episodes waiting, each with what it still needs and how far its
/// videos have got. Drafts still uploading are listed apart, below.
class DraftsView extends StatefulWidget {
  const DraftsView({super.key});

  @override
  State<DraftsView> createState() => _DraftsViewState();
}

class _DraftsViewState extends State<DraftsView> {
  List<AdminEdition>? _drafts;
  AdminException? _failure;
  bool _loading = true;
  bool _started = false;
  Timer? _refresh;

  /// Each load's number. Only the newest load's answer is shown, so a slow
  /// older one can't bring back a draft deleted since.
  int _generation = 0;

  /// This browser's uploads, and those already seen finished.
  UploadQueue? _queue;
  final Set<String> _finished = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final queue = UploadsScope.of(context);
    if (!identical(queue, _queue)) {
      _queue?.removeListener(_uploadsChanged);
      _queue = queue;
      _finished
        ..clear()
        ..addAll(_finishedIds(queue));
      queue?.addListener(_uploadsChanged);
    }
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _refresh?.cancel();
    _queue?.removeListener(_uploadsChanged);
    super.dispose();
  }

  static Set<String> _finishedIds(UploadQueue? queue) => {
    for (final t in queue?.tasks ?? const <UploadTask>[])
      if (t.phase == UploadPhase.finished) t.id,
  };

  /// An upload from this browser just finished: its draft moves up.
  void _uploadsChanged() {
    final now = _finishedIds(_queue);
    final fresh = now.difference(_finished).isNotEmpty;
    _finished
      ..clear()
      ..addAll(now);
    if (fresh && mounted) _load();
  }

  Future<void> _load() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    _refresh?.cancel();
    final generation = ++_generation;
    setState(() => _loading = true);
    try {
      final drafts = await api.drafts();
      if (!mounted || generation != _generation) return;
      setState(() {
        _drafts = drafts;
        _failure = null;
        _loading = false;
      });
      if (drafts.any(_working)) {
        _refresh = Timer(draftsRefreshEvery, () {
          if (mounted) _load();
        });
      }
    } on AdminException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = error;
        _loading = false;
      });
    }
  }

  /// A video of it is uploading, or being checked, converted or sent.
  static bool _working(AdminEdition draft) => draft.items.any(
    (item) => item.video == 'uploading' || VideoStageProgress.shows(item.video),
  );

  Future<void> _open(String editionId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DraftScreen(editionId: editionId),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _newDraft() async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const NewDraftScreen()));
    if (mounted) _load();
  }

  Future<void> _delete(AdminEdition draft) async {
    final l = context.l10n;
    final sure = await confirm(
      context,
      title: l.deleteDraftTitle(draft.displayTitle),
      message: l.deleteDraftMessage,
      action: l.deletePermanently,
      danger: true,
    );
    if (!sure || !mounted) return;
    final queue = UploadsScope.of(context);
    final done = await runAdmin(
      context,
      (api) => api.deleteEdition(draft.id).then((_) => true),
      done: l.draftDeleted(draft.displayTitle),
    );
    // Only once the server has deleted it: its uploads stop, and their
    // parts are deleted. A refused delete leaves them running.
    if (done == true) await queue?.removeForEdition(draft.id);
    if (done == true && mounted) await _load();
  }

  Future<void> _deleteAll(List<AdminEdition> drafts) async {
    final l = context.l10n;
    final count = drafts.where((d) => d.status == 'draft').length;
    final sure = await confirm(
      context,
      title: l.deleteAllDraftsTitle(count),
      message: l.deleteAllDraftsMessage,
      action: l.deleteAllDrafts,
      danger: true,
      typeToConfirm: deleteAllWord,
    );
    if (!sure || !mounted) return;
    final queue = UploadsScope.of(context);
    final deleted = await runAdmin(context, (api) => api.deleteAllDrafts());
    if (deleted == null) return;
    // Only the uploads of drafts the server deleted: one hidden meanwhile
    // keeps its uploads.
    if (queue != null) {
      await Future.wait([for (final id in deleted) queue.removeForEdition(id)]);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.draftsDeleted(deleted.length))));
    await _load();
  }

  void _goToUploads() => DefaultTabController.maybeOf(context)?.animateTo(1);

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final drafts = _drafts;
    final failure = _failure;
    final ready = [
      for (final d in drafts ?? const <AdminEdition>[])
        if (!d.incomplete) d,
    ];
    final incomplete = [
      for (final d in drafts ?? const <AdminEdition>[])
        if (d.incomplete) d,
    ];
    final deletable = (drafts ?? const []).any((d) => d.status == 'draft');
    return ScreenBody(
      heading: l.adminDrafts,
      intro: l.adminDraftsIntro,
      maxWidth: VeloraLayout.browseWidth,
      status: Wrap(
        spacing: VeloraSpacing.sm,
        runSpacing: VeloraSpacing.xs,
        children: [
          VeloraButton(
            label: l.newDraft,
            icon: Icons.add,
            onPressed: _newDraft,
          ),
          VeloraButton(
            label: l.refresh,
            icon: Icons.refresh,
            variant: VeloraButtonVariant.secondary,
            isLoading: _loading,
            onPressed: _load,
          ),
          if (deletable)
            VeloraButton(
              label: l.deleteAllDrafts,
              icon: Icons.delete_sweep_outlined,
              variant: VeloraButtonVariant.danger,
              onPressed: () => _deleteAll(drafts!),
            ),
        ],
      ),
      children: [
        if (failure != null)
          ErrorState(
            title: l.adminLoadFailed,
            message: adminFailureMessage(l, failure),
            onRetry: _load,
          )
        else if (drafts == null)
          Center(
            child: VeloraLoadingRegion(
              label: l.loading,
              child: const VeloraSpinner(size: 32),
            ),
          )
        else ...[
          if (ready.isEmpty)
            EmptyState(
              icon: Icons.inbox_outlined,
              title: l.noDraftsTitle,
              message: incomplete.isEmpty
                  ? l.noDraftsMessage
                  : l.noDraftsReadyMessage,
            )
          else
            for (final draft in ready)
              _DraftTile(
                key: ValueKey(draft.id),
                draft: draft,
                onTap: () => _open(draft.id),
                onDelete: draft.published ? null : () => _delete(draft),
              ),
          if (incomplete.isNotEmpty)
            _IncompleteSection(
              drafts: incomplete,
              onOpen: _open,
              onDelete: _delete,
              onGoToUploads: _goToUploads,
            ),
        ],
      ],
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({
    super.key,
    required this.draft,
    required this.onTap,
    required this.onDelete,
  });

  final AdminEdition draft;
  final VoidCallback onTap;

  /// Null for a published edition: it is hidden first, then deleted.
  final VoidCallback? onDelete;

  /// At most this many videos' bars, then "and N more".
  static const int _shownStages = 3;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (status, tone) = editionStatus(l, draft);
    final waiting = draft.items.where((item) => !item.approved).length;
    final stages = [
      for (final item in draft.items)
        if (VideoStageProgress.shows(item.video)) item,
    ];
    final uploading = draft.items.where((i) => i.video == 'uploading').length;
    final failed = draft.items.where(
      (i) => i.video == 'failed' || i.video == 'refused',
    );
    return Card.outlined(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VeloraRadii.md),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            VeloraSpacing.md,
            VeloraSpacing.sm,
            VeloraSpacing.xs,
            VeloraSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: VeloraSpacing.xs,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: VeloraSpacing.xxs,
                      children: [
                        Text(
                          draft.displayTitle,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(_kindLine(l, draft)),
                        if (draft.missing.isNotEmpty)
                          Text(
                            l.stillNeeds(
                              draft.missing
                                  .map((m) => missingLabel(l, m))
                                  .join(', '),
                            ),
                          )
                        else if (draft.published && waiting > 0)
                          Text(l.episodesWaiting(waiting))
                        else if (!draft.published)
                          Text(l.readyToPublish),
                        // Under the details, so a narrow phone has room.
                        StatusBadge(label: status, tone: tone),
                      ],
                    ),
                  ),
                  _DraftMenu(onOpen: onTap, onDelete: onDelete),
                ],
              ),
              for (final item in stages.take(_shownStages))
                Padding(
                  padding: const EdgeInsets.only(right: VeloraSpacing.sm),
                  child: VideoStageProgress(
                    key: ValueKey(item.id),
                    label: itemName(l, item),
                    item: item,
                  ),
                ),
              if (stages.length > _shownStages)
                Text(l.andMoreVideos(stages.length - _shownStages)),
              if (uploading > 0) Text(l.episodesStillUploading(uploading)),
              for (final item in failed)
                Text(
                  [
                    '${itemName(l, item)}: ${videoState(l, item.video).$1}',
                    ?item.videoReason,
                  ].join(' · '),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _kindLine(AppLocalizations l, AdminEdition draft) => [
  draft.kind == EditionKind.series ? l.seriesBadge : l.movie,
  draft.vjName ?? l.noVjYet,
  if (draft.test) l.testFilm,
].join(' · ');

class _DraftMenu extends StatelessWidget {
  const _DraftMenu({required this.onOpen, required this.onDelete});

  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final danger = Theme.of(context).colorScheme.error;
    return PopupMenuButton<VoidCallback>(
      tooltip: l.moreActions,
      onSelected: (action) => action(),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: onOpen,
          child: ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: Text(l.openDraft),
          ),
        ),
        if (onDelete case final delete?)
          PopupMenuItem(
            value: delete,
            child: ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: danger),
              title: Text(l.deletePermanently, style: TextStyle(color: danger)),
            ),
          ),
      ],
    );
  }
}

/// Drafts with no finished upload. Their progress, when this browser is
/// uploading them, comes from the upload queue.
class _IncompleteSection extends StatelessWidget {
  const _IncompleteSection({
    required this.drafts,
    required this.onOpen,
    required this.onDelete,
    required this.onGoToUploads,
  });

  final List<AdminEdition> drafts;
  final ValueChanged<String> onOpen;
  final ValueChanged<AdminEdition> onDelete;
  final VoidCallback onGoToUploads;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final queue = UploadsScope.of(context);
    Widget list(List<UploadTask> tasks) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.xs,
      children: [
        for (final draft in drafts)
          _IncompleteTile(
            key: ValueKey(draft.id),
            draft: draft,
            tasks: [
              for (final t in tasks)
                if (t.editionId == draft.id) t,
            ],
            onOpen: () => onOpen(draft.id),
            onDelete: draft.published ? null : () => onDelete(draft),
          ),
      ],
    );
    return Card.outlined(
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            title: Text(l.incompleteUploadsTitle(drafts.length)),
            subtitle: Text(l.incompleteUploadsIntro),
            childrenPadding: const EdgeInsets.fromLTRB(
              VeloraSpacing.sm,
              0,
              VeloraSpacing.sm,
              VeloraSpacing.sm,
            ),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (queue == null)
                list(const [])
              else
                ListenableBuilder(
                  listenable: queue,
                  builder: (_, _) => list(queue.tasks),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: VeloraButton(
                  label: l.goToUploads,
                  icon: Icons.cloud_upload_outlined,
                  variant: VeloraButtonVariant.tertiary,
                  onPressed: onGoToUploads,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IncompleteTile extends StatelessWidget {
  const _IncompleteTile({
    super.key,
    required this.draft,
    required this.tasks,
    required this.onOpen,
    required this.onDelete,
  });

  final AdminEdition draft;

  /// This browser's uploads for it.
  final List<UploadTask> tasks;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final task = tasks.firstOrNull;
    final uploadingElsewhere = draft.items.any((i) => i.video == 'uploading');
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VeloraSpacing.sm,
          VeloraSpacing.xs,
          VeloraSpacing.xs,
          VeloraSpacing.sm,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.xxs,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        draft.displayTitle,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(_kindLine(l, draft)),
                    ],
                  ),
                ),
                _DraftMenu(onOpen: onOpen, onDelete: onDelete),
              ],
            ),
            if (task != null) ...[
              Semantics(
                label: l.uploadProgressLabel(task.fileName),
                value: l.uploadPercent(task.percent),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VeloraRadii.sm),
                  child: LinearProgressIndicator(
                    value: task.fraction,
                    minHeight: 6,
                  ),
                ),
              ),
              Text(l.incompleteUploadingHere(task.percent)),
            ] else
              Text(
                uploadingElsewhere
                    ? l.incompleteUploadingElsewhere
                    : l.incompleteWaitingForVideo,
              ),
          ],
        ),
      ),
    );
  }
}
