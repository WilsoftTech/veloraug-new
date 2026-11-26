import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../api/admin_api.dart';
import '../api/catalogue_api.dart' show EditionKind;
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/movie_poster.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import 'admin_common.dart';
import 'draft_screen.dart';

/// The search waits this long after typing stops.
const Duration librarySearchDelay = Duration(milliseconds: 400);

/// The badge for a Library title's state.
(String, StatusTone) libraryState(AppLocalizations l, String state) =>
    switch (state) {
      'published' => (l.statusPublished, StatusTone.success),
      'hidden' => (l.statusHidden, StatusTone.warning),
      _ => (l.statusWithdrawn, StatusTone.neutral),
    };

/// Published, hidden and withdrawn titles: searched, filtered, sorted, and
/// changed one at a time or many at once. Each opens in the editor.
class LibraryView extends StatefulWidget {
  const LibraryView({super.key});

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final _search = TextEditingController();
  Timer? _searchDelay;

  String? _state;
  EditionKind? _kind;
  String? _vjId;
  String? _category;
  String _sort = 'newest';

  List<LibraryTitle> _titles = const [];
  int _total = 0;
  int _viewerDays = 30;
  AdminException? _failure;
  bool _loading = true;
  bool _loadingMore = false;
  bool _started = false;
  int _generation = 0;
  final Set<String> _selected = {};

  List<AdminVj> _vjs = const [];
  List<String> _categories = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
      _loadReference();
    }
  }

  @override
  void dispose() {
    _searchDelay?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadReference() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final vjs = await api.vjs();
      final categories = await api.categories();
      if (!mounted) return;
      setState(() {
        _vjs = vjs;
        _categories = [for (final c in categories) c.name];
      });
    } on AdminException {
      // The filters still work without these lists.
    }
  }

  /// The first page again, as the filters now say. Only the newest load's
  /// answer is shown.
  Future<void> _load({bool more = false}) async {
    final api = AdminScope.of(context);
    if (api == null) return;
    final generation = ++_generation;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
    });
    try {
      final page = await api.library(
        query: _search.text,
        vjId: _vjId,
        kind: _kind,
        category: _category,
        state: _state,
        sort: _sort,
        offset: more ? _titles.length : 0,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _titles = more ? [..._titles, ...page.titles] : page.titles;
        _total = page.total;
        _viewerDays = page.viewerDays;
        _failure = null;
        _loading = false;
        _loadingMore = false;
        final ids = {for (final t in _titles) t.id};
        _selected.retainWhere(ids.contains);
      });
    } on AdminException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failure = error;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  void _searchChanged(String _) {
    _searchDelay?.cancel();
    _searchDelay = Timer(librarySearchDelay, _load);
  }

  void _filter(void Function() change) {
    setState(change);
    _load();
  }

  Future<void> _open(LibraryTitle title) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DraftScreen(editionId: title.id)),
    );
    if (mounted) _load();
  }

  // --- One title -------------------------------------------------------------

  Future<void> _hide(LibraryTitle title) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.hideTitle,
      message: l.hideMessage,
      action: l.hide,
    )) {
      return;
    }
    if (!mounted) return;
    await _act((api) => api.hide(title.id), l.hiddenNow);
  }

  Future<void> _show(LibraryTitle title) async {
    final l = context.l10n;
    await _act((api) => api.publish(title.id), l.shownAgain(title.title));
  }

  Future<void> _withdraw(LibraryTitle title) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.withdrawTitle(title.title),
      message: l.withdrawMessage,
      action: l.withdraw,
    )) {
      return;
    }
    if (!mounted) return;
    await _act((api) => api.withdraw(title.id), l.withdrawnNow(title.title));
  }

  Future<void> _delete(LibraryTitle title) async {
    final l = context.l10n;
    final published = title.state == 'published';
    if (!await confirm(
      context,
      title: l.deleteDraftTitle(title.title),
      message: published ? l.deletePublishedMessage : l.deleteDraftMessage,
      action: l.deletePermanently,
      danger: true,
      typeToConfirm: published ? 'DELETE' : null,
    )) {
      return;
    }
    if (!mounted) return;
    await _act(
      (api) => api.deleteEdition(title.id, published: published),
      l.draftDeleted(title.title),
    );
  }

  Future<void> _act(
    Future<Object?> Function(AdminApi api) action,
    String done,
  ) async {
    final ok = await runAdmin(
      context,
      (api) => action(api).then((_) => true),
      done: done,
    );
    if (ok == true && mounted) await _load();
  }

  // --- Many titles -------------------------------------------------------------

  Future<void> _bulk(String action) async {
    final l = context.l10n;
    final ids = List.of(_selected);
    String? vjId;
    if (action == 'credit') {
      vjId = await _chooseVj();
      if (vjId == null || !mounted) return;
    } else if (action == 'withdraw') {
      if (!await confirm(
        context,
        title: l.withdrawManyTitle(ids.length),
        message: l.withdrawMessage,
        action: l.withdraw,
      )) {
        return;
      }
      if (!mounted) return;
    } else if (action == 'hide') {
      if (!await confirm(
        context,
        title: l.hideManyTitle(ids.length),
        message: l.hideMessage,
        action: l.hide,
      )) {
        return;
      }
      if (!mounted) return;
    }
    final outcome = await runAdmin(
      context,
      (api) => api.bulkChange(ids, action, vjId: vjId),
    );
    if (outcome == null || !mounted) return;
    final names = {for (final t in _titles) t.id: t.title};
    final skipped = [
      for (final MapEntry(:key, :value) in outcome.skipped.entries)
        '${names[key] ?? key}: $value',
    ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: Duration(seconds: skipped.isEmpty ? 4 : 10),
        content: Text(
          [
            l.bulkChanged(outcome.changed),
            if (skipped.isNotEmpty) l.bulkSkipped(skipped.join('\n')),
          ].join('\n'),
        ),
      ),
    );
    setState(_selected.clear);
    await _load();
  }

  Future<String?> _chooseVj() {
    final l = context.l10n;
    return showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(l.creditManyTitle(_selected.length)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeloraSpacing.lg),
            child: Text(l.creditManyMessage),
          ),
          for (final vj in _vjs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialog).pop(vj.id),
              child: Text(vj.name),
            ),
        ],
      ),
    );
  }

  // --- The page --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final failure = _failure;
    final allSelected =
        _titles.isNotEmpty && _titles.every((t) => _selected.contains(t.id));
    return ScreenBody(
      heading: l.adminLibrary,
      intro: l.adminLibraryIntro,
      maxWidth: VeloraLayout.browseWidth,
      status: VeloraButton(
        label: l.refresh,
        icon: Icons.refresh,
        variant: VeloraButtonVariant.secondary,
        isLoading: _loading,
        onPressed: _load,
      ),
      children: [
        _filters(l),
        if (failure != null)
          ErrorState(
            title: l.adminLoadFailed,
            message: adminFailureMessage(l, failure),
            onRetry: _load,
          )
        else if (_loading && _titles.isEmpty)
          Center(
            child: VeloraLoadingRegion(
              label: l.loading,
              child: const VeloraSpinner(size: 32),
            ),
          )
        else if (_titles.isEmpty)
          EmptyState(
            icon: Icons.video_library_outlined,
            title: l.libraryEmptyTitle,
            message: _filtered ? l.libraryNoMatches : l.libraryEmptyMessage,
          )
        else ...[
          Wrap(
            spacing: VeloraSpacing.sm,
            runSpacing: VeloraSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Semantics(
                label: l.selectAllShown,
                child: Checkbox(
                  value: allSelected
                      ? true
                      : _selected.isEmpty
                      ? false
                      : null,
                  tristate: true,
                  onChanged: (_) => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(_titles.map((t) => t.id));
                    }
                  }),
                ),
              ),
              Text(l.libraryCount(_total)),
            ],
          ),
          if (_selected.isNotEmpty) _selectionBar(l),
          for (final title in _titles)
            _LibraryTile(
              key: ValueKey(title.id),
              title: title,
              viewerDays: _viewerDays,
              selected: _selected.contains(title.id),
              onSelected: (on) => setState(() {
                if (on) {
                  _selected.add(title.id);
                } else {
                  _selected.remove(title.id);
                }
              }),
              onOpen: () => _open(title),
              onHide: title.state == 'published' ? () => _hide(title) : null,
              onShow: title.state == 'published' ? null : () => _show(title),
              onWithdraw: title.state == 'withdrawn'
                  ? null
                  : () => _withdraw(title),
              onDelete: () => _delete(title),
            ),
          if (_titles.length < _total)
            Center(
              child: VeloraButton(
                label: l.loadMore(_total - _titles.length),
                variant: VeloraButtonVariant.secondary,
                isLoading: _loadingMore,
                onPressed: () => _load(more: true),
              ),
            ),
        ],
      ],
    );
  }

  bool get _filtered =>
      _search.text.trim().isNotEmpty ||
      _state != null ||
      _kind != null ||
      _vjId != null ||
      _category != null;

  Widget _filters(AppLocalizations l) {
    Widget dropdown<T>({
      required String label,
      required T? value,
      required List<(T?, String)> options,
      required ValueChanged<T?> onChanged,
      double width = 180,
    }) => SizedBox(
      width: width,
      child: DropdownButtonFormField<T?>(
        initialValue: value,
        isExpanded: true,
        isDense: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final (v, text) in options)
            DropdownMenuItem(
              value: v,
              child: Text(text, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.sm,
      children: [
        TextField(
          controller: _search,
          onChanged: _searchChanged,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: InputDecoration(
            labelText: l.librarySearch,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _search.text.isEmpty
                ? null
                : IconButton(
                    tooltip: l.clearSearch,
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _search.clear();
                      _load();
                    },
                  ),
          ),
        ),
        Wrap(
          spacing: VeloraSpacing.xs,
          runSpacing: VeloraSpacing.xs,
          children: [
            for (final (state, label) in [
              (null, l.libraryAll),
              ('published', l.statusPublished),
              ('hidden', l.statusHidden),
              ('withdrawn', l.statusWithdrawn),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _state == state,
                onSelected: (_) => _filter(() => _state = state),
              ),
          ],
        ),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.sm,
          children: [
            dropdown<EditionKind>(
              label: l.kind,
              value: _kind,
              width: 150,
              options: [
                (null, l.libraryAll),
                (EditionKind.movie, l.movies),
                (EditionKind.series, l.seriesPlural),
              ],
              onChanged: (kind) => _filter(() => _kind = kind),
            ),
            dropdown<String>(
              label: l.vjCredit,
              value: _vjId,
              options: [
                (null, l.allVjs),
                for (final vj in _vjs) (vj.id, vj.name),
              ],
              onChanged: (id) => _filter(() => _vjId = id),
            ),
            if (_categories.isNotEmpty)
              dropdown<String>(
                label: l.categoriesSection,
                value: _category,
                options: [
                  (null, l.libraryAll),
                  for (final name in _categories) (name, name),
                ],
                onChanged: (name) => _filter(() => _category = name),
              ),
            dropdown<String>(
              label: l.sortBy,
              value: _sort,
              options: [
                ('newest', l.sortNewest),
                ('oldest', l.sortOldest),
                ('title', l.sortTitle),
                ('viewers', l.sortViewers),
                ('updated', l.sortUpdated),
              ],
              onChanged: (sort) => _filter(() => _sort = sort ?? 'newest'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _selectionBar(AppLocalizations l) {
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Wrap(
          spacing: VeloraSpacing.xs,
          runSpacing: VeloraSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(l.selectedCount(_selected.length)),
            VeloraButton(
              label: l.hide,
              icon: Icons.visibility_off_outlined,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _bulk('hide'),
            ),
            VeloraButton(
              label: l.showAgain,
              icon: Icons.visibility_outlined,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _bulk('show'),
            ),
            VeloraButton(
              label: l.withdraw,
              icon: Icons.undo,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _bulk('withdraw'),
            ),
            VeloraButton(
              label: l.changeVj,
              icon: Icons.person_outline,
              variant: VeloraButtonVariant.secondary,
              onPressed: _vjs.isEmpty ? null : () => _bulk('credit'),
            ),
            VeloraButton(
              label: l.clearSelection,
              variant: VeloraButtonVariant.tertiary,
              onPressed: () => setState(_selected.clear),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({
    super.key,
    required this.title,
    required this.viewerDays,
    required this.selected,
    required this.onSelected,
    required this.onOpen,
    required this.onDelete,
    this.onHide,
    this.onShow,
    this.onWithdraw,
  });

  final LibraryTitle title;
  final int viewerDays;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final VoidCallback onOpen;
  final VoidCallback? onHide;
  final VoidCallback? onShow;
  final VoidCallback? onWithdraw;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (badge, tone) = libraryState(l, title.state);
    final date = title.publishedAt;
    final series = title.kind == EditionKind.series;
    final facts = [
      if (date != null)
        l.publishedOn(
          // With the year: a library spans years.
          DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag())
              .format(date.toLocal()),
        ),
      l.viewersLately(title.viewers, viewerDays),
      if (series) l.episodeCount(title.episodes),
      if (title.hiddenEpisodes > 0) l.hiddenEpisodeCount(title.hiddenEpisodes),
      if (title.waiting > 0) l.episodesWaiting(title.waiting),
    ];
    return Card.outlined(
      color: selected ? Theme.of(context).colorScheme.secondaryContainer : null,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(VeloraRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.sm,
            children: [
              Checkbox(
                value: selected,
                semanticLabel: l.selectTitle(title.title),
                onChanged: (on) => onSelected(on ?? false),
              ),
              SizedBox(
                width: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(VeloraRadii.sm),
                  child: MoviePoster(url: title.posterUrl),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: VeloraSpacing.xxs,
                  children: [
                    Text(
                      title.year == null
                          ? title.title
                          : '${title.title} (${title.year})',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      [
                        series ? l.seriesBadge : l.movie,
                        title.vjName ?? l.noVjYet,
                        ...title.categories,
                      ].join(' · '),
                    ),
                    Text(
                      facts.join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    // Under the details, so a narrow phone has room.
                    StatusBadge(label: badge, tone: tone),
                  ],
                ),
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: l.moreActions,
                onSelected: (action) => action(),
                itemBuilder: (_) => [
                  _item(Icons.edit_outlined, l.editTitle, onOpen),
                  if (onHide case final hide?)
                    _item(Icons.visibility_off_outlined, l.hide, hide),
                  if (onShow case final show?)
                    _item(Icons.visibility_outlined, l.showAgain, show),
                  if (onWithdraw case final withdraw?)
                    _item(Icons.undo, l.withdraw, withdraw),
                  _item(
                    Icons.delete_forever_outlined,
                    l.deletePermanently,
                    onDelete,
                    danger: Theme.of(context).colorScheme.error,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<VoidCallback> _item(
    IconData icon,
    String label,
    VoidCallback action, {
    Color? danger,
  }) => PopupMenuItem(
    value: action,
    child: ListTile(
      leading: Icon(icon, color: danger),
      title: Text(
        label,
        style: danger == null ? null : TextStyle(color: danger),
      ),
    ),
  );
}
