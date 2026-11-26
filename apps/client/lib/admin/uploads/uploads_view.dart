import 'dart:async';

import 'package:flutter/material.dart';

import '../../api/admin_api.dart';
import '../../api/catalogue_api.dart' show EditionKind;
import '../../l10n/l10n.dart';
import '../../theme/tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/status_badge.dart';
import '../../widgets/velora_button.dart';
import '../admin_common.dart';
import '../draft_screen.dart';
import 'file_names.dart';
import 'upload_platform.dart' as platform;
import 'upload_queue.dart';

/// Gives the screens below it the upload queue, which lives as long as the
/// app so uploads carry on while the admin browses elsewhere. Null when
/// this build can't upload from the browser.
class UploadsScope extends InheritedWidget {
  const UploadsScope({
    super.key,
    required this.queue,
    this.pick = platform.pickVideos,
    required super.child,
  });

  final UploadQueue? queue;

  /// The file chooser. Tests replace it.
  final Future<List<PickedVideo>> Function() pick;

  static UploadQueue? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UploadsScope>()?.queue;

  static Future<List<PickedVideo>> Function() pickerOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<UploadsScope>()?.pick ??
      platform.pickVideos;

  @override
  bool updateShouldNotify(UploadsScope oldWidget) =>
      queue != oldWidget.queue || pick != oldWidget.pick;
}

/// "1.2 GB", "350 MB". Units are the same in English and Luganda.
String formatBytes(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

String formatTimeLeft(AppLocalizations l, Duration left) {
  if (left.inHours > 0) {
    return l.uploadHoursLeft(left.inHours, left.inMinutes.remainder(60));
  }
  if (left.inMinutes > 0) return l.uploadMinutesLeft(left.inMinutes + 1);
  return l.uploadSecondsLeft(left.inSeconds);
}

/// The admin's Uploads tab: drop or choose video files, check what each
/// becomes, and watch them upload.
class UploadsView extends StatefulWidget {
  const UploadsView({super.key});

  @override
  State<UploadsView> createState() => _UploadsViewState();
}

class _UploadsViewState extends State<UploadsView>
    with AutomaticKeepAliveClientMixin {
  final List<_ReviewRow> _review = [];
  List<AdminVj> _vjs = const [];
  List<AdminSeries> _series = const [];
  List<AdminLanguage> _languages = const [];
  bool _hover = false;
  bool _loadingReference = false;
  String? _vjFilter;
  void Function()? _stopListening;
  Timer? _ticker;
  UploadQueue? _queue;

  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final queue = UploadsScope.of(context);
    if (identical(queue, _queue)) return;
    _queue?.removeListener(_queueChanged);
    _queue = queue;
    queue?.addListener(_queueChanged);
    queue?.restore();
    _stopListening ??= platform.listenForVideoDrops(
      onHover: (over) {
        if (mounted && over != _hover) setState(() => _hover = over);
      },
      onDrop: _received,
    );
  }

  @override
  void dispose() {
    _queue?.removeListener(_queueChanged);
    _stopListening?.call();
    _ticker?.cancel();
    for (final row in _review) {
      row.dispose();
    }
    super.dispose();
  }

  /// Counts down "Trying again in 5 s" while anything waits to retry.
  void _queueChanged() {
    final waiting =
        _queue?.tasks.any((t) => t.phase == UploadPhase.retrying) ?? false;
    if (waiting && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!waiting) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  Future<void> _choose() async =>
      _received(await UploadsScope.pickerOf(context)());

  /// Files dropped or chosen: the same file as an unfinished upload carries
  /// it on, and the rest wait in the review list.
  Future<void> _received(List<PickedVideo> picked) async {
    final queue = _queue;
    if (queue == null || picked.isEmpty || !mounted) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final videos = [
      for (final video in picked)
        if (isVideoFileName(video.file.name)) video,
    ];
    final skipped = picked.length - videos.length;
    final fresh = await queue.attach(videos);
    final resumed = videos.length - fresh.length;
    if (fresh.isNotEmpty) await _loadReference();
    if (!mounted) return;
    setState(() {
      for (final video in fresh) {
        if (_review.any(
          (row) =>
              row.video.file.name == video.file.name &&
              row.video.file.size == video.file.size,
        )) {
          continue;
        }
        _review.add(_ReviewRow.from(video, _vjs, _series));
      }
    });
    final notes = [
      if (resumed > 0) l.uploadsResumedFromDrop(resumed),
      if (skipped > 0) l.uploadsNotVideos(skipped),
    ];
    if (notes.isNotEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(notes.join(' '))));
    }
  }

  /// VJs, series and languages, for reading names and filling the rows.
  Future<void> _loadReference() async {
    final api = AdminScope.of(context);
    if (api == null || _loadingReference) return;
    setState(() => _loadingReference = true);
    try {
      final results = await Future.wait([
        api.vjs(),
        api.series(),
        api.languages(),
      ]);
      if (!mounted) return;
      setState(() {
        _vjs = results[0] as List<AdminVj>;
        _series = results[1] as List<AdminSeries>;
        _languages = results[2] as List<AdminLanguage>;
      });
    } on AdminException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(adminFailureMessage(context.l10n, error))),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingReference = false);
    }
  }

  Future<void> _start() async {
    final queue = _queue;
    if (queue == null) return;
    final l = context.l10n;
    var valid = true;
    for (final row in _review) {
      row.error = row.check(l, _series, _review);
      if (row.error != null) valid = false;
    }
    if (!valid) {
      setState(() {});
      return;
    }
    final rows = List.of(_review);
    setState(_review.clear);
    await queue.add([
      for (final row in rows) (row.video, row.plan(_vjs, _series)),
    ]);
    for (final row in rows) {
      row.dispose();
    }
  }

  void _clearReview() {
    setState(() {
      for (final row in _review) {
        row.dispose();
      }
      _review.clear();
    });
  }

  Future<void> _remove(UploadTask task) async {
    final l = context.l10n;
    final sure = await confirm(
      context,
      title: l.removeUploadTitle,
      message: l.removeUploadMessage,
      action: l.remove,
    );
    if (sure) await _queue?.remove(task.id);
  }

  Future<void> _removeAll(UploadQueue queue) async {
    final l = context.l10n;
    final count = queue.tasks
        .where((t) => t.phase != UploadPhase.removing)
        .length;
    final sure = await confirm(
      context,
      title: l.removeAllUploadsTitle(count),
      message: l.removeAllUploadsMessage,
      action: l.removeAll,
      danger: true,
    );
    if (sure) await queue.removeAll();
  }

  Future<void> _openDraft(String editionId) => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => DraftScreen(editionId: editionId)),
  );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l = context.l10n;
    final queue = _queue;
    if (queue == null) {
      return ScreenBody(
        heading: l.adminUploads,
        maxWidth: VeloraLayout.browseWidth,
        children: [
          EmptyState(
            icon: Icons.cloud_off_outlined,
            title: l.uploadsNotSetUpTitle,
            message: l.uploadsNotSetUpMessage,
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final tasks = queue.tasks;
        final vjNames = {for (final t in tasks) t.plan.vjName ?? ''}.toList()
          ..sort();
        final shown = [
          for (final task in tasks)
            if (_vjFilter == null || (task.plan.vjName ?? '') == _vjFilter)
              task,
        ];
        return ScreenBody(
          heading: l.adminUploads,
          intro: l.adminUploadsIntro,
          maxWidth: VeloraLayout.browseWidth,
          children: [
            _DropZone(hover: _hover, onChoose: _choose),
            if (_review.isNotEmpty)
              AdminSection(
                title: l.reviewUploadsTitle(_review.length),
                children: [
                  Text(l.reviewUploadsIntro),
                  for (final row in _review)
                    _ReviewCard(
                      key: ObjectKey(row),
                      row: row,
                      vjs: _vjs,
                      series: _series,
                      languages: _languages,
                      onChanged: () => setState(() {}),
                      onRemove: () => setState(() {
                        _review.remove(row);
                        row.dispose();
                      }),
                    ),
                  Wrap(
                    spacing: VeloraSpacing.sm,
                    runSpacing: VeloraSpacing.xs,
                    children: [
                      VeloraButton(
                        label: l.startUploads(_review.length),
                        icon: Icons.cloud_upload_outlined,
                        isLoading: _loadingReference,
                        onPressed: _start,
                      ),
                      VeloraButton(
                        label: l.cancel,
                        variant: VeloraButtonVariant.tertiary,
                        onPressed: _clearReview,
                      ),
                    ],
                  ),
                ],
              ),
            if (tasks.isNotEmpty)
              AdminSection(
                title: l.uploadsListTitle,
                children: [
                  Wrap(
                    spacing: VeloraSpacing.xs,
                    runSpacing: VeloraSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (vjNames.length > 1) ...[
                        ChoiceChip(
                          label: Text(l.allVjs),
                          selected: _vjFilter == null,
                          onSelected: (_) => setState(() => _vjFilter = null),
                        ),
                        for (final name in vjNames)
                          ChoiceChip(
                            label: Text(name.isEmpty ? l.noVjYet : name),
                            selected: _vjFilter == name,
                            onSelected: (_) => setState(() => _vjFilter = name),
                          ),
                      ],
                      if (tasks.any((t) => t.phase == UploadPhase.finished))
                        VeloraButton(
                          label: l.clearFinished,
                          variant: VeloraButtonVariant.tertiary,
                          onPressed: queue.clearFinished,
                        ),
                    ],
                  ),
                  _BulkBar(queue: queue, onRemoveAll: () => _removeAll(queue)),
                  for (final task in shown)
                    _TaskCard(
                      key: ValueKey(task.id),
                      task: task,
                      onPause: () => queue.pause(task.id),
                      onResume: () => queue.resume(task.id),
                      onRemove: () => _remove(task),
                      onChoose: _choose,
                      onOpen: task.editionId == null
                          ? null
                          : () => _openDraft(task.editionId!),
                    ),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _DropZone extends StatelessWidget {
  const _DropZone({required this.hover, required this.onChoose});

  final bool hover;
  final VoidCallback onChoose;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.all(VeloraSpacing.lg),
      decoration: BoxDecoration(
        color: hover ? scheme.primaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(VeloraRadii.sm),
        border: Border.all(
          color: hover ? scheme.primary : scheme.outlineVariant,
          width: hover ? 2 : 1,
        ),
      ),
      child: Column(
        spacing: VeloraSpacing.sm,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 40, color: scheme.primary),
          Text(
            hover ? l.dropToAdd : l.dropVideosHere,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          VeloraButton(
            label: l.chooseFiles,
            icon: Icons.folder_open,
            variant: VeloraButtonVariant.secondary,
            onPressed: onChoose,
          ),
          Text(l.uploadsHowItWorks, textAlign: TextAlign.center),
          // The expander paints on a Material, not on the coloured box.
          Material(
            type: MaterialType.transparency,
            child: Theme(
              data: Theme.of(context)
                  .copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(l.namingGuideTitle),
                childrenPadding: const EdgeInsets.only(
                  bottom: VeloraSpacing.sm,
                ),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.namingGuideIntro),
                  const SizedBox(height: VeloraSpacing.xs),
                  for (final example in [
                    l.namingGuideMovie,
                    l.namingGuideEpisode,
                  ])
                    SelectableText(
                      example,
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  const SizedBox(height: VeloraSpacing.xs),
                  Text(l.namingGuideRules),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One dropped file in the review list, and what it will become.
class _ReviewRow {
  _ReviewRow._(this.video, ParsedName parsed)
    : title = TextEditingController(text: parsed.title),
      year = TextEditingController(text: parsed.year?.toString() ?? ''),
      season = TextEditingController(text: parsed.season?.toString() ?? ''),
      episode = TextEditingController(text: parsed.episode?.toString() ?? ''),
      kind = parsed.isEpisode ? EditionKind.series : EditionKind.movie,
      fileVj = parsed.vj;

  factory _ReviewRow.from(
    PickedVideo video,
    List<AdminVj> vjs,
    List<AdminSeries> series,
  ) {
    final parsed = parseVideoName(video.file.name, knownVjs: vjs);
    final row = _ReviewRow._(video, parsed);
    row.vjId = matchKnownVj(parsed.vj, vjs)?.id;
    if (row.kind == EditionKind.series) {
      row.seriesId = _matchingSeries(series, parsed.title, row.vjId)?.id;
    }
    return row;
  }

  final PickedVideo video;
  final TextEditingController title;
  final TextEditingController year;
  final TextEditingController season;
  final TextEditingController episode;
  EditionKind kind;

  /// The VJ as the file names them, when no known VJ matches.
  final String? fileVj;
  String? vjId;

  /// An existing series to add the episode to, or null for a new one.
  String? seriesId;
  String? language;
  String? error;

  static AdminSeries? _matchingSeries(
    List<AdminSeries> series,
    String title,
    String? vjId,
  ) {
    final key = titleKey(title);
    if (key.isEmpty) return null;
    final found = [
      for (final s in series)
        if (titleKey(s.title) == key && (vjId == null || s.vjId == vjId)) s,
    ];
    return found.length == 1 ? found.single : null;
  }

  int? _number(TextEditingController field) => int.tryParse(field.text.trim());

  String? check(
    AppLocalizations l,
    List<AdminSeries> allSeries,
    List<_ReviewRow> rows,
  ) {
    final series = kind == EditionKind.series;
    if ((!series || seriesId == null) && title.text.trim().isEmpty) {
      return l.reviewNeedsTitle;
    }
    final yearText = year.text.trim();
    if (!series && yearText.isNotEmpty) {
      final value = int.tryParse(yearText);
      if (value == null || value < 1900 || value > 2100) {
        return l.reviewBadYear;
      }
    }
    if (series) {
      final s = _number(season);
      final e = _number(episode);
      if (s == null || e == null || s < 0 || e < 1) return l.reviewNeedsEpisode;
      final existing = allSeries.where((x) => x.id == seriesId).firstOrNull;
      if (existing != null && existing.hasEpisode(s, e)) {
        return l.reviewEpisodeExists(s, e);
      }
      final twice = rows.where(
        (other) =>
            other.kind == EditionKind.series &&
            other.seriesId == seriesId &&
            (seriesId != null ||
                titleKey(other.title.text) == titleKey(title.text)) &&
            other._number(other.season) == s &&
            other._number(other.episode) == e,
      );
      if (twice.length > 1) return l.reviewEpisodeTwice(s, e);
    }
    return null;
  }

  UploadPlan plan(List<AdminVj> vjs, List<AdminSeries> allSeries) {
    final series = kind == EditionKind.series;
    final existing = series
        ? allSeries.where((x) => x.id == seriesId).firstOrNull
        : null;
    final vj = vjs.where((v) => v.id == vjId).firstOrNull;
    return UploadPlan(
      kind: kind,
      title: existing?.title ?? title.text.trim(),
      year: series ? null : _number(year),
      language: existing == null ? language : null,
      season: series ? _number(season) : null,
      episode: series ? _number(episode) : null,
      vjId: existing == null ? vj?.id : null,
      vjName: existing?.vjName ?? vj?.name ?? fileVj,
      seriesEditionId: existing?.id,
      seriesTitle: existing?.title,
    );
  }

  void dispose() {
    title.dispose();
    year.dispose();
    season.dispose();
    episode.dispose();
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    super.key,
    required this.row,
    required this.vjs,
    required this.series,
    required this.languages,
    required this.onChanged,
    required this.onRemove,
  });

  final _ReviewRow row;
  final List<AdminVj> vjs;
  final List<AdminSeries> series;
  final List<AdminLanguage> languages;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final isSeries = row.kind == EditionKind.series;
    final existing = isSeries
        ? series.where((s) => s.id == row.seriesId).firstOrNull
        : null;
    final unknownVj =
        row.vjId == null && row.fileVj != null && existing == null;
    Widget field(
      String label,
      TextEditingController controller, {
      double width = 120,
      bool numeric = true,
    }) => SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        decoration: InputDecoration(labelText: label, isDense: true),
        onChanged: (_) {
          if (row.error != null) {
            row.error = null;
            onChanged();
          }
        },
      ),
    );

    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.sm,
          children: [
            Row(
              children: [
                const Icon(Icons.movie_outlined),
                const SizedBox(width: VeloraSpacing.xs),
                Expanded(
                  child: Text(
                    '${row.video.file.name} · ${formatBytes(row.video.file.size)}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: l.leaveOut,
                  icon: const Icon(Icons.close),
                  onPressed: onRemove,
                ),
              ],
            ),
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 180,
                  child: DropdownButtonFormField<EditionKind>(
                    initialValue: row.kind,
                    isExpanded: true,
                    isDense: true,
                    decoration: InputDecoration(labelText: l.kind),
                    items: [
                      DropdownMenuItem(
                        value: EditionKind.movie,
                        child: Text(l.movie),
                      ),
                      DropdownMenuItem(
                        value: EditionKind.series,
                        child: Text(l.seriesBadge),
                      ),
                    ],
                    onChanged: (kind) {
                      row
                        ..kind = kind ?? EditionKind.movie
                        ..error = null;
                      if (row.kind == EditionKind.series &&
                          row.season.text.isEmpty) {
                        row.season.text = '1';
                        row.episode.text = '1';
                      }
                      onChanged();
                    },
                  ),
                ),
                if (isSeries)
                  SizedBox(
                    width: 280,
                    child: DropdownButtonFormField<String?>(
                      initialValue: row.seriesId,
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(labelText: l.addToSeries),
                      items: [
                        DropdownMenuItem(child: Text(l.newSeries)),
                        for (final s in series)
                          DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              [s.title, ?s.vjName].join(' · '),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (id) {
                        row
                          ..seriesId = id
                          ..error = null;
                        onChanged();
                      },
                    ),
                  ),
                if (existing == null)
                  field(
                    l.titleAsSubmitted,
                    row.title,
                    width: 280,
                    numeric: false,
                  ),
                if (isSeries) ...[
                  field(l.season, row.season, width: 90),
                  field(l.episode, row.episode, width: 90),
                ] else
                  field(l.yearOptional, row.year),
                if (existing == null) ...[
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String?>(
                      initialValue: row.vjId,
                      isExpanded: true,
                      isDense: true,
                      decoration: InputDecoration(labelText: l.vjCredit),
                      items: [
                        DropdownMenuItem(child: Text(l.noVjYet)),
                        for (final vj in vjs)
                          DropdownMenuItem(value: vj.id, child: Text(vj.name)),
                      ],
                      onChanged: (id) {
                        row.vjId = id;
                        onChanged();
                      },
                    ),
                  ),
                  if (languages.length > 1)
                    SizedBox(
                      width: 160,
                      child: DropdownButtonFormField<String?>(
                        initialValue: row.language,
                        isExpanded: true,
                        isDense: true,
                        decoration: InputDecoration(labelText: l.language),
                        items: [
                          for (final language in languages)
                            DropdownMenuItem(
                              value: language.code,
                              child: Text(language.name),
                            ),
                        ],
                        onChanged: (code) {
                          row.language = code;
                          onChanged();
                        },
                      ),
                    ),
                ],
              ],
            ),
            if (existing != null)
              Text(
                l.episodeGoesTo(existing.title, existing.vjName ?? l.noVjYet),
              )
            else if (unknownVj)
              Text(l.reviewUnknownVj(row.fileVj!))
            else if (row.vjId != null)
              Text(l.reviewVjCredited),
            if (row.error case final error?)
              Text(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pause all, Resume all and Remove all, with how many are running.
class _BulkBar extends StatelessWidget {
  const _BulkBar({required this.queue, required this.onRemoveAll});

  final UploadQueue queue;
  final VoidCallback onRemoveAll;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final tasks = queue.tasks;
    final running = tasks.where((t) => t.active).length;
    final finished = tasks.where((t) => t.phase == UploadPhase.finished).length;
    final total = tasks.fold<int>(0, (sum, t) => sum + t.size);
    final sent = tasks.fold<int>(0, (sum, t) => sum + t.sent);
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.xs,
          children: [
            Text(
              [
                l.uploadsSummary(running, finished, tasks.length),
                if (total > 0)
                  l.uploadBytesOf(formatBytes(sent), formatBytes(total)),
              ].join(' · '),
            ),
            Wrap(
              spacing: VeloraSpacing.xs,
              runSpacing: VeloraSpacing.xs,
              children: [
                VeloraButton(
                  label: l.pauseAll,
                  icon: Icons.pause,
                  variant: VeloraButtonVariant.secondary,
                  onPressed: queue.canPauseAll ? queue.pauseAll : null,
                ),
                VeloraButton(
                  label: l.resumeAll,
                  icon: Icons.play_arrow,
                  variant: VeloraButtonVariant.secondary,
                  onPressed: queue.canResumeAll ? queue.resumeAll : null,
                ),
                VeloraButton(
                  label: l.removeAll,
                  icon: Icons.delete_sweep_outlined,
                  variant: VeloraButtonVariant.danger,
                  onPressed: queue.canRemoveAll ? onRemoveAll : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onRemove,
    required this.onChoose,
    required this.onOpen,
  });

  final UploadTask task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onRemove;
  final VoidCallback onChoose;
  final VoidCallback? onOpen;

  String _name(AppLocalizations l) {
    final plan = task.plan;
    if (plan.kind == EditionKind.series &&
        plan.season != null &&
        plan.episode != null) {
      return '${plan.seriesTitle ?? plan.title} · '
          '${l.episodeShort(plan.season!, plan.episode!)}';
    }
    return plan.year == null ? plan.title : '${plan.title} (${plan.year})';
  }

  (String, StatusTone) _badge(AppLocalizations l) => switch (task.phase) {
    UploadPhase.needsFile => (l.uploadNeedsFile, StatusTone.warning),
    UploadPhase.queued => (l.uploadQueued, StatusTone.neutral),
    UploadPhase.preparing => (l.uploadStarting, StatusTone.info),
    UploadPhase.uploading => (l.uploadUploading, StatusTone.info),
    UploadPhase.paused => (l.uploadPaused, StatusTone.neutral),
    UploadPhase.retrying => (l.uploadRetrying, StatusTone.warning),
    UploadPhase.offline => (l.uploadOffline, StatusTone.warning),
    UploadPhase.finished => (l.uploadFinished, StatusTone.success),
    UploadPhase.failed => (l.uploadFailed, StatusTone.danger),
    UploadPhase.removing => (l.uploadRemoving, StatusTone.neutral),
  };

  String _status(AppLocalizations l) {
    final done = l.uploadPercent(task.percent);
    switch (task.phase) {
      case UploadPhase.needsFile:
        return task.canReopen
            ? l.uploadNeedsFileResume(task.percent)
            : l.uploadNeedsFileDrop(task.percent, task.fileName);
      case UploadPhase.queued:
        return l.uploadWaitingTurn;
      case UploadPhase.preparing:
        return l.uploadPreparing;
      case UploadPhase.uploading:
        final speed = task.speed;
        final left = task.timeLeft;
        return [
          done,
          l.uploadBytesOf(formatBytes(task.sent), formatBytes(task.size)),
          if (speed != null) l.uploadSpeed(formatBytes(speed)),
          if (left != null) formatTimeLeft(l, left),
        ].join(' · ');
      case UploadPhase.paused:
        return l.uploadPausedAt(task.percent);
      case UploadPhase.retrying:
        final at = task.retryAt;
        final seconds = at == null
            ? 0
            : at.difference(DateTime.now()).inSeconds.clamp(0, 3600) + 1;
        return l.uploadRetryIn(task.percent, seconds);
      case UploadPhase.offline:
        return l.uploadWaitingNetwork(task.percent);
      case UploadPhase.finished:
        return l.uploadDone;
      case UploadPhase.removing:
        return l.uploadRemovingPart;
      case UploadPhase.failed:
        return switch (task.problem) {
          UploadProblem.keyRefused => l.uploadKeyRefused,
          UploadProblem.tooLarge => l.uploadTooLarge,
          UploadProblem.refused =>
            task.adminError == null
                ? l.somethingWentWrong
                : adminFailureMessage(l, task.adminError!),
          UploadProblem.removeFailed => l.uploadRemoveFailed,
          _ => l.uploadUnexpected,
        };
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (badge, tone) = _badge(l);
    final phase = task.phase;
    final problem = task.problem;
    final scheme = Theme.of(context).colorScheme;
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: VeloraSpacing.xs,
          children: [
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.xxs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_name(l), style: Theme.of(context).textTheme.titleSmall),
                StatusBadge(label: badge, tone: tone),
              ],
            ),
            Text(
              [task.plan.vjName ?? l.noVjYet, task.fileName].join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
            Semantics(
              label: l.uploadProgressLabel(task.fileName),
              value: l.uploadPercent(task.percent),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VeloraRadii.sm),
                child: LinearProgressIndicator(
                  value: phase == UploadPhase.preparing ? null : task.fraction,
                  minHeight: 8,
                  color: phase == UploadPhase.failed ? scheme.error : null,
                ),
              ),
            ),
            Text(_status(l)),
            if (problem == UploadProblem.fileChanged)
              Text(l.uploadFileChanged, style: TextStyle(color: scheme.error))
            else if (problem == UploadProblem.fileUnreadable)
              Text(
                l.uploadFileUnreadable,
                style: TextStyle(color: scheme.error),
              ),
            if (task.restarted && phase != UploadPhase.finished)
              Text(l.uploadRestarted),
            if (task.creditError case final error?)
              Text(l.uploadCreditFailed(adminFailureMessage(l, error))),
            Wrap(
              spacing: VeloraSpacing.xs,
              runSpacing: VeloraSpacing.xs,
              children: [
                if (task.active)
                  VeloraButton(
                    label: l.pause,
                    icon: Icons.pause,
                    variant: VeloraButtonVariant.secondary,
                    onPressed: onPause,
                  ),
                if (phase == UploadPhase.retrying ||
                    phase == UploadPhase.offline)
                  VeloraButton(
                    label: l.tryNow,
                    icon: Icons.refresh,
                    variant: VeloraButtonVariant.tertiary,
                    onPressed: onResume,
                  ),
                if (phase == UploadPhase.paused ||
                    (phase == UploadPhase.needsFile && task.canReopen))
                  VeloraButton(
                    label: l.resume,
                    icon: Icons.play_arrow,
                    onPressed: onResume,
                  ),
                if (phase == UploadPhase.needsFile && !task.canReopen)
                  VeloraButton(
                    label: l.chooseFile,
                    icon: Icons.folder_open,
                    onPressed: onChoose,
                  ),
                if (phase == UploadPhase.failed &&
                    problem != UploadProblem.tooLarge)
                  VeloraButton(
                    label: problem == UploadProblem.removeFailed
                        ? l.removeAgain
                        : l.tryAgain,
                    icon: Icons.refresh,
                    onPressed: onResume,
                  ),
                if (phase != UploadPhase.finished &&
                    phase != UploadPhase.removing)
                  VeloraButton(
                    label: l.remove,
                    icon: Icons.delete_outline,
                    variant: VeloraButtonVariant.danger,
                    onPressed: onRemove,
                  ),
                if (onOpen != null && phase != UploadPhase.removing)
                  VeloraButton(
                    label: l.openDraft,
                    icon: Icons.open_in_new,
                    variant: VeloraButtonVariant.tertiary,
                    onPressed: onOpen,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
