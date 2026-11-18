import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/catalogue_api.dart' show EditionKind, Episode;
import '../l10n/l10n.dart';
import '../screens/player_screen.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/movie_poster.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';
import 'drafts_view.dart' show checkNumber;
import 'image_picker.dart';

/// One edition, as an admin works on it: its videos and upload keys, a
/// preview, TMDB's details, the poster, the VJ credit, and Publish.
class DraftScreen extends StatefulWidget {
  const DraftScreen({super.key, required this.editionId});

  final String editionId;

  @override
  State<DraftScreen> createState() => _DraftScreenState();
}

class _DraftScreenState extends State<DraftScreen> {
  AdminEdition? _edition;
  AdminException? _failure;
  Credit? _credit;
  List<AdminVj> _vjs = const [];
  PosterOptions? _posters;
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final edition = await api.edition(widget.editionId);
      final credit = await api.credit(widget.editionId);
      final vjs = await api.vjs();
      if (!mounted) return;
      setState(() {
        _edition = edition;
        _credit = credit;
        _vjs = vjs;
        _failure = null;
      });
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  /// Runs a change that answers with the edition, and shows the new state.
  Future<void> _change(
    Future<AdminEdition> Function(AdminApi api) action, {
    String? done,
  }) async {
    setState(() => _busy = true);
    final edition = await runAdmin(context, action, done: done);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (edition != null) _edition = edition;
    });
    if (edition != null) {
      final credit = await runAdmin(
        context,
        (api) => api.credit(widget.editionId),
      );
      if (mounted && credit != null) setState(() => _credit = credit);
    }
  }

  /// Anything that doesn't answer with the edition: reload afterwards.
  Future<void> _act(
    Future<void> Function(AdminApi api) action, {
    String? done,
  }) async {
    setState(() => _busy = true);
    await runAdmin(context, action, done: done);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final edition = _edition;
    final failure = _failure;
    return Scaffold(
      appBar: AppBar(title: Text(edition?.displayTitle ?? l.draft)),
      body: SafeArea(
        child: failure != null
            ? ScreenBody(
                heading: l.draft,
                children: [
                  ErrorState(
                    title: l.adminLoadFailed,
                    message: adminFailureMessage(l, failure),
                    onRetry: _load,
                  ),
                ],
              )
            : edition == null
            ? Center(
                child: VeloraLoadingRegion(
                  label: l.loading,
                  child: const VeloraSpinner(size: 32),
                ),
              )
            : AbsorbPointer(absorbing: _busy, child: _body(l, edition)),
      ),
    );
  }

  Widget _body(AppLocalizations l, AdminEdition edition) {
    final (status, tone) = editionStatus(l, edition);
    return ScreenBody(
      heading: edition.displayTitle,
      intro: [
        edition.kind == EditionKind.series ? l.seriesBadge : l.movie,
        edition.language,
        if (edition.test) l.testFilm,
      ].join(' · '),
      status: Wrap(
        spacing: VeloraSpacing.sm,
        runSpacing: VeloraSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusBadge(label: status, tone: tone),
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined),
            label: Text(l.renameTitle),
            onPressed: () => _rename(edition),
          ),
        ],
      ),
      maxWidth: VeloraLayout.browseWidth,
      children: [
        _videos(l, edition),
        _details(l, edition),
        _poster(l, edition),
        _creditSection(l, edition),
        _publishing(l, edition),
      ],
    );
  }

  // --- Title -----------------------------------------------------------------

  Future<void> _rename(AdminEdition edition) async {
    final title = await _ask(
      title: context.l10n.renameTitle,
      label: context.l10n.displayTitle,
      initial: edition.displayTitle,
    );
    if (title == null || !mounted) return;
    await _change((api) => api.rename(edition.id, title));
  }

  /// Asks for one line of text. Null if cancelled or empty.
  Future<String?> _ask({
    required String title,
    required String label,
    String initial = '',
    String? help,
  }) async {
    final controller = TextEditingController(text: initial);
    final l = context.l10n;
    final answer = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: VeloraTextField(
          label: label,
          helperText: help,
          controller: controller,
          onFieldSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l.cancel),
          ),
          VeloraButton(
            label: l.save,
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    final text = answer?.trim();
    return text == null || text.isEmpty ? null : text;
  }

  // --- Videos and keys -------------------------------------------------------

  Widget _videos(AppLocalizations l, AdminEdition edition) {
    final series = edition.kind == EditionKind.series;
    return AdminSection(
      title: series ? l.episodes : l.video,
      children: [
        Text(l.videosIntro),
        for (final item in edition.items) _itemTile(l, edition, item),
        if (series)
          Align(
            alignment: Alignment.centerLeft,
            child: VeloraButton(
              label: l.addEpisode,
              icon: Icons.add,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _addEpisode(edition),
            ),
          ),
      ],
    );
  }

  Widget _itemTile(AppLocalizations l, AdminEdition edition, AdminItem item) {
    final (state, tone) = videoState(l, item.video);
    final reason = item.videoReason;
    final liveKeys = item.keys.where((k) => !k.used && !k.revoked).toList();
    return Card.outlined(
      key: ValueKey(item.id),
      child: Padding(
        padding: const EdgeInsets.all(VeloraSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.xs,
          children: [
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  [itemName(l, item), ?item.episodeTitle].join(' · '),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                StatusBadge(label: state, tone: tone),
                if (edition.published && edition.kind == EditionKind.series)
                  StatusBadge(
                    label: item.approved ? l.approved : l.waitingApproval,
                    tone: item.approved
                        ? StatusTone.success
                        : StatusTone.warning,
                  ),
              ],
            ),
            if (reason != null) Text(reason),
            if (item.filename case final name?) Text(l.fileName(name)),
            if (item.creditHints case final hints?) Text(l.fileTags(hints)),
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.xs,
              children: [
                if (item.previewable)
                  VeloraButton(
                    label: l.preview,
                    icon: Icons.play_arrow,
                    onPressed: () => _preview(edition, item),
                  ),
                if (edition.published && !item.approved && item.previewable)
                  VeloraButton(
                    label: l.approveEpisode,
                    icon: Icons.check,
                    variant: VeloraButtonVariant.secondary,
                    onPressed: () => _act(
                      (api) => api.approve(item.id),
                      done: l.episodeApproved,
                    ),
                  ),
                VeloraButton(
                  label: l.newUploadKey,
                  icon: Icons.key_outlined,
                  variant: VeloraButtonVariant.secondary,
                  onPressed: () => _newKey(item),
                ),
              ],
            ),
            for (final key in liveKeys)
              Wrap(
                spacing: VeloraSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    l.keyLine(
                      key.label,
                      MaterialLocalizations.of(context)
                          .formatMediumDate(key.expiresAt.toLocal()),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _revoke(key),
                    child: Text(l.revoke),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  void _preview(AdminEdition edition, AdminItem item) {
    final episodes = [
      for (final i in edition.items)
        if (i.season != null && i.episode != null)
          Episode(
            itemId: i.id,
            season: i.season!,
            episode: i.episode!,
            title: i.episodeTitle,
            playable: i.previewable,
          ),
    ];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlayerScreen(
          itemId: item.id,
          title: edition.displayTitle,
          episodes: episodes,
          preview: true,
        ),
      ),
    );
  }

  Future<void> _newKey(AdminItem item) async {
    final l = context.l10n;
    final label = await _ask(
      title: l.newUploadKey,
      label: l.keyLabel,
      help: l.keyLabelHelp,
      initial: l.keyLabelDefault,
    );
    if (label == null || !mounted) return;
    final made = await runAdmin(
      context,
      (api) => api.newKey(item.id, label: label),
    );
    if (made == null || !mounted) return;
    await showUploadKey(context, made);
    await _load();
  }

  Future<void> _revoke(UploadKeyInfo key) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.revokeKeyTitle,
      message: l.revokeKeyMessage(key.label),
      action: l.revoke,
    )) {
      return;
    }
    if (!mounted) return;
    await _act((api) => api.revokeKey(key.id), done: l.keyRevoked);
  }

  Future<void> _addEpisode(AdminEdition edition) async {
    final last = edition.items.isEmpty ? null : edition.items.last;
    final made = await showDialog<KeyMade>(
      context: context,
      builder: (_) => _AddEpisodeDialog(
        editionId: edition.id,
        season: last?.season ?? 1,
        episode: (last?.episode ?? 0) + 1,
      ),
    );
    if (made == null || !mounted) return;
    await showUploadKey(context, made);
    await _load();
  }

  // --- Details from TMDB, or typed in --------------------------------------

  Widget _details(AppLocalizations l, AdminEdition edition) {
    final chosen = edition.detailsFrom != null;
    final lookup = switch (edition.tmdbLookup) {
      null => l.lookupWaiting,
      'clear' => l.lookupClear,
      'choose' => l.lookupChoose,
      'none' => l.lookupNone,
      'failed' => l.lookupFailed,
      'chosen' => l.lookupChosen,
      'manual' => l.lookupManual,
      final other => other,
    };
    return AdminSection(
      title: l.details,
      status: StatusBadge(
        label: chosen ? l.done : l.needed,
        tone: chosen ? StatusTone.success : StatusTone.warning,
      ),
      children: [
        Text(lookup),
        if (chosen) ...[
          Text(
            [
              edition.sourceTitle ?? '',
              if (edition.sourceYear != null) '${edition.sourceYear}',
              if (edition.sourceTmdbId != null) l.tmdbId(edition.sourceTmdbId!),
            ].join(' · '),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (edition.sourceOverview case final overview?) Text(overview),
        ],
        for (final match in edition.matches)
          Card.outlined(
            key: ValueKey(match.tmdbId),
            child: ListTile(
              leading: SizedBox(
                width: 46,
                child: MoviePoster(url: match.posterUrl),
              ),
              title: Text(
                [
                  match.title,
                  if (match.year != null) '(${match.year})',
                ].join(' '),
              ),
              subtitle: Text(
                [
                  if (match.originalTitle != null &&
                      match.originalTitle != match.title)
                    match.originalTitle!,
                  l.tmdbId(match.tmdbId),
                  if (match.overview != null) match.overview!,
                ].join(' · '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton(
                onPressed: () =>
                    _change((api) => api.chooseTmdb(edition.id, match.tmdbId)),
                child: Text(l.useThis),
              ),
            ),
          ),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.xs,
          children: [
            VeloraButton(
              label: l.searchTmdbAgain,
              icon: Icons.search,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _searchAgain(edition),
            ),
            VeloraButton(
              label: l.useTmdbId,
              icon: Icons.tag,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _useTmdbId(edition),
            ),
            VeloraButton(
              label: l.typeDetails,
              icon: Icons.edit_note,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _typeDetails(edition),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _searchAgain(AdminEdition edition) async {
    final l = context.l10n;
    final title = await _ask(
      title: l.searchTmdbAgain,
      label: l.titleToSearch,
      initial: edition.displayTitle,
      help: l.titleToSearchHelp,
    );
    if (title == null || !mounted) return;
    setState(() => _busy = true);
    final result = await runAdmin(
      context,
      (api) => api.searchTmdb(edition.id, title: title),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result != null) _edition = result.edition;
    });
  }

  Future<void> _useTmdbId(AdminEdition edition) async {
    final l = context.l10n;
    final text = await _ask(
      title: l.useTmdbId,
      label: l.tmdbIdLabel,
      help: edition.kind == EditionKind.series
          ? l.tmdbIdHelpSeries
          : l.tmdbIdHelpMovie,
    );
    final id = int.tryParse(text ?? '');
    if (id == null || id <= 0 || !mounted) return;
    await _change((api) => api.chooseTmdb(edition.id, id));
  }

  Future<void> _typeDetails(AdminEdition edition) async {
    final details = await showDialog<ManualDetails>(
      context: context,
      builder: (_) => _ManualDetailsDialog(title: edition.displayTitle),
    );
    if (details == null || !mounted) return;
    await _change((api) => api.typeDetails(edition.id, details));
  }

  // --- Poster ----------------------------------------------------------------

  Widget _poster(AppLocalizations l, AdminEdition edition) {
    final posters = _posters;
    final chosen = edition.posterPath != null;
    return AdminSection(
      title: l.poster,
      status: StatusBadge(
        label: chosen ? l.done : l.needed,
        tone: chosen ? StatusTone.success : StatusTone.warning,
      ),
      children: [
        if (edition.posterUrl != null)
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(VeloraRadii.md),
                child: MoviePoster(url: edition.posterUrl),
              ),
            ),
          ),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.xs,
          children: [
            if (edition.sourceTmdbId != null)
              VeloraButton(
                label: l.showTmdbPosters,
                icon: Icons.photo_library_outlined,
                variant: VeloraButtonVariant.secondary,
                onPressed: () => _loadPosters(edition),
              ),
            VeloraButton(
              label: l.uploadPoster,
              icon: Icons.upload_outlined,
              variant: VeloraButtonVariant.secondary,
              onPressed: () => _uploadPoster(edition),
            ),
          ],
        ),
        if (posters != null && posters.options.isEmpty) Text(l.noTmdbPosters),
        if (posters != null && posters.options.isNotEmpty)
          Wrap(
            spacing: VeloraSpacing.sm,
            runSpacing: VeloraSpacing.sm,
            children: [
              for (final option in posters.options)
                Semantics(
                  button: true,
                  selected: option.path == edition.posterPath,
                  label: l.choosePoster,
                  child: InkWell(
                    key: ValueKey(option.path),
                    onTap: () => _change(
                      (api) => api.choosePoster(edition.id, option.path),
                    ),
                    child: Container(
                      width: 110,
                      decoration: BoxDecoration(
                        border: Border.all(
                          width: 3,
                          color: option.path == edition.posterPath
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: MoviePoster(url: option.url),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Future<void> _loadPosters(AdminEdition edition) async {
    final posters = await runAdmin(context, (api) => api.posters(edition.id));
    if (mounted && posters != null) setState(() => _posters = posters);
  }

  Future<void> _uploadPoster(AdminEdition edition) async {
    final l = context.l10n;
    final image = await pickImage();
    if (image == null || !mounted) return;
    if (image.bytes.length > maxImageBytes) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.imageTooBig)));
      return;
    }
    await _change((api) async {
      final path = await api.uploadImage(
        poster: true,
        ownerId: edition.id,
        bytes: image.bytes,
        contentType: image.contentType,
      );
      return api.choosePoster(edition.id, path);
    }, done: l.posterUploaded);
  }

  // --- VJ credit ---------------------------------------------------------------

  Widget _creditSection(AppLocalizations l, AdminEdition edition) {
    final credit = _credit;
    final confirmed = edition.vjId != null;
    return AdminSection(
      title: l.vjCredit,
      status: StatusBadge(
        label: confirmed ? l.done : l.needed,
        tone: confirmed ? StatusTone.success : StatusTone.warning,
      ),
      children: [
        Text(confirmed ? l.creditedTo(edition.vjName ?? '') : l.creditIntro),
        if (credit != null && credit.suggestions.isNotEmpty) ...[
          Text(l.suggestions, style: Theme.of(context).textTheme.titleSmall),
          for (final suggestion in credit.suggestions)
            Wrap(
              key: ValueKey('${suggestion.name}-${suggestion.foundIn}'),
              spacing: VeloraSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l.suggestionLine(suggestion.name, suggestion.foundIn)),
                TextButton(
                  onPressed: () => _confirmCredit(
                    edition,
                    vjId: suggestion.vjId,
                    newVj: suggestion.vjId == null ? suggestion.name : null,
                    name: suggestion.name,
                  ),
                  child: Text(
                    suggestion.vjId == null
                        ? l.addAndCredit(suggestion.name)
                        : l.creditThisVj,
                  ),
                ),
              ],
            ),
        ] else if (credit != null)
          Text(l.noSuggestions),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.xs,
          children: [
            VeloraButton(
              label: l.chooseVj,
              icon: Icons.person_search_outlined,
              variant: VeloraButtonVariant.secondary,
              onPressed: _vjs.isEmpty ? null : () => _chooseVj(edition),
            ),
            VeloraButton(
              label: l.addNewVj,
              icon: Icons.person_add_alt,
              variant: VeloraButtonVariant.secondary,
              onPressed: () async {
                final name = await _ask(title: l.addNewVj, label: l.vjName);
                if (name == null || !mounted) return;
                await _confirmCredit(edition, newVj: name, name: name);
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _chooseVj(AdminEdition edition) async {
    final l = context.l10n;
    final vj = await showDialog<AdminVj>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(l.chooseVj),
        children: [
          for (final vj in _vjs)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(vj),
              child: Text(vj.name),
            ),
        ],
      ),
    );
    if (vj == null || !mounted) return;
    await _confirmCredit(edition, vjId: vj.id, name: vj.name);
  }

  /// The admin confirms, having previewed the video: a wrong credit,
  /// published, is a real harm to a VJ.
  Future<void> _confirmCredit(
    AdminEdition edition, {
    String? vjId,
    String? newVj,
    required String name,
  }) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.confirmCreditTitle,
      message: l.confirmCreditMessage(name, edition.displayTitle),
      action: l.confirmCredit,
    )) {
      return;
    }
    if (!mounted) return;
    await _change(
      (api) => api.setCredit(edition.id, vjId: vjId, newVj: newVj),
      done: l.creditedTo(name),
    );
    if (newVj != null && mounted) {
      final vjs = await runAdmin(context, (api) => api.vjs());
      if (mounted && vjs != null) setState(() => _vjs = vjs);
    }
  }

  // --- Publishing ----------------------------------------------------------

  Widget _publishing(AppLocalizations l, AdminEdition edition) {
    return AdminSection(
      title: l.publishing,
      children: [
        if (edition.missing.isNotEmpty) ...[
          Text(l.cantPublishYet),
          for (final missing in edition.missing)
            Text('• ${missingLabel(l, missing)}'),
        ] else if (!edition.published)
          Text(l.readyToPublish)
        else
          Text(l.publishedExplained),
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.xs,
          children: [
            if (!edition.published)
              VeloraButton(
                label: l.publish,
                icon: Icons.public,
                onPressed: () => _publish(edition),
              ),
            if (edition.published)
              VeloraButton(
                label: l.hide,
                icon: Icons.visibility_off_outlined,
                variant: VeloraButtonVariant.secondary,
                onPressed: () => _hide(edition),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _publish(AdminEdition edition) async {
    final l = context.l10n;
    final api = AdminScope.of(context);
    if (api == null) return;
    setState(() => _busy = true);
    try {
      final published = await api.publish(edition.id);
      if (!mounted) return;
      setState(() => _edition = published);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.publishedNow)));
    } on AdminException catch (error) {
      if (!mounted) return;
      final missing = error.missing;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            missing.isEmpty
                ? adminFailureMessage(l, error)
                : l.stillNeeds(
                    missing.map((m) => missingLabel(l, m)).join(', '),
                  ),
          ),
        ),
      );
      if (missing.isNotEmpty) await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hide(AdminEdition edition) async {
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
    await _change((api) => api.hide(edition.id), done: l.hiddenNow);
  }
}

/// Adds an episode to a series edition. Pops with its key.
class _AddEpisodeDialog extends StatefulWidget {
  const _AddEpisodeDialog({
    required this.editionId,
    required this.season,
    required this.episode,
  });

  final String editionId;
  final int season;
  final int episode;

  @override
  State<_AddEpisodeDialog> createState() => _AddEpisodeDialogState();
}

class _AddEpisodeDialogState extends State<_AddEpisodeDialog> {
  final _form = GlobalKey<FormState>();
  late final _season = TextEditingController(text: '${widget.season}');
  late final _episode = TextEditingController(text: '${widget.episode}');
  final _title = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _season.dispose();
    _episode.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final title = _title.text.trim();
    final made = await runAdmin(
      context,
      (api) => api.createDraft(
        kind: EditionKind.series,
        seriesEditionId: widget.editionId,
        season: int.parse(_season.text.trim()),
        episode: int.parse(_episode.text.trim()),
        episodeTitle: title.isEmpty ? null : title,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (made != null) Navigator.of(context).pop(made);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.addEpisode),
      content: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: VeloraSpacing.sm,
          children: [
            VeloraTextField(
              label: l.season,
              controller: _season,
              keyboardType: TextInputType.number,
              validator: (v) => checkNumber(l, v, min: 0, max: 999),
            ),
            VeloraTextField(
              label: l.episode,
              controller: _episode,
              keyboardType: TextInputType.number,
              validator: (v) => checkNumber(l, v, min: 1, max: 9999),
            ),
            VeloraTextField(label: l.episodeTitleOptional, controller: _title),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        VeloraButton(
          label: l.addEpisode,
          isLoading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Details typed in when TMDB has nothing. Pops with them.
class _ManualDetailsDialog extends StatefulWidget {
  const _ManualDetailsDialog({required this.title});

  final String title;

  @override
  State<_ManualDetailsDialog> createState() => _ManualDetailsDialogState();
}

class _ManualDetailsDialogState extends State<_ManualDetailsDialog> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.title);
  final _year = TextEditingController();
  final _overview = TextEditingController();
  final _genres = TextEditingController();
  final _runtime = TextEditingController();

  @override
  void dispose() {
    for (final c in [_title, _year, _overview, _genres, _runtime]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    if (!(_form.currentState?.validate() ?? false)) return;
    final overview = _overview.text.trim();
    Navigator.of(context).pop(
      ManualDetails(
        title: _title.text.trim(),
        year: int.tryParse(_year.text.trim()),
        overview: overview.isEmpty ? null : overview,
        genres: [
          for (final genre in _genres.text.split(','))
            if (genre.trim().isNotEmpty) genre.trim(),
        ],
        runtimeMinutes: int.tryParse(_runtime.text.trim()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.typeDetails),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VeloraLayout.readingWidth),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: VeloraSpacing.sm,
              children: [
                VeloraTextField(
                  label: l.originalTitle,
                  controller: _title,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l.required : null,
                ),
                VeloraTextField(
                  label: l.yearOptional,
                  controller: _year,
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      checkNumber(l, v, min: 1900, max: 2100, optional: true),
                ),
                VeloraTextField(
                  label: l.runtimeOptional,
                  controller: _runtime,
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      checkNumber(l, v, min: 1, max: 1000, optional: true),
                ),
                VeloraTextField(
                  label: l.genresOptional,
                  helperText: l.genresHelp,
                  controller: _genres,
                ),
                VeloraTextField(
                  label: l.overviewOptional,
                  controller: _overview,
                  maxLines: 5,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        VeloraButton(label: l.save, onPressed: _submit),
      ],
    );
  }
}
