import 'dart:async';

import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/catalogue_api.dart' show EditionKind;
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';
import 'category_input.dart';
import 'draft_screen.dart';
import 'image_picker.dart';
import 'uploads/file_names.dart' show isVideoFileName;
import 'uploads/upload_queue.dart';
import 'uploads/uploads_view.dart' show UploadsScope, formatBytes;

/// How a new draft gets its details.
enum DetailsSource {
  /// Searched on TMDB with the title and year, at once.
  tmdb,

  /// Typed in here, when TMDB won't have it.
  typed,

  /// Left for the draft screen.
  later,
}

/// Starts a draft with everything known about it: movie or series, title,
/// VJ, language, year, details, categories, poster, and its video.
///
/// Create makes the draft, then saves each part in turn. A part that fails
/// doesn't lose the others: the draft opens, and says what is still needed.
/// The video joins the Uploads queue for the draft, or without one, an
/// upload key is shown for whoever has the file.
class NewDraftScreen extends StatefulWidget {
  const NewDraftScreen({super.key});

  @override
  State<NewDraftScreen> createState() => _NewDraftScreenState();
}

class _NewDraftScreenState extends State<NewDraftScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _year = TextEditingController();
  final _season = TextEditingController(text: '1');
  final _episode = TextEditingController(text: '1');
  final _episodeTitle = TextEditingController();
  final _overview = TextEditingController();
  final _genres = TextEditingController();
  final _runtime = TextEditingController();

  EditionKind _kind = EditionKind.movie;

  /// An existing series to add the episode to; null for a new one.
  String? _seriesId;
  String? _vjId;
  String _language = 'lg';
  DetailsSource _details = DetailsSource.tmdb;
  List<String> _categories = const [];
  PickedImage? _poster;
  PickedVideo? _video;

  List<AdminVj> _vjs = const [];
  List<AdminSeries> _series = const [];
  List<AdminLanguage> _languages = const [
    AdminLanguage(code: 'lg', name: 'Luganda'),
  ];
  List<String> _knownCategories = const [];
  bool _saving = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _loadReference();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _title,
      _year,
      _season,
      _episode,
      _episodeTitle,
      _overview,
      _genres,
      _runtime,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// VJs, series, languages and categories. Each is optional: without one,
  /// the form still works with what it has.
  Future<void> _loadReference() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    Future<T?> quietly<T>(Future<T> Function() load) async {
      try {
        return await load();
      } on AdminException {
        return null;
      }
    }

    final vjs = await quietly(api.vjs);
    final series = await quietly(api.series);
    final languages = await quietly(api.languages);
    final categories = await quietly(api.categories);
    if (!mounted) return;
    setState(() {
      _vjs = vjs ?? _vjs;
      _series = series ?? _series;
      if (languages != null && languages.isNotEmpty) _languages = languages;
      _knownCategories = [for (final c in categories ?? const []) c.name];
    });
  }

  AdminSeries? get _existingSeries =>
      _series.where((s) => s.id == _seriesId).firstOrNull;

  bool get _newEdition => _kind == EditionKind.movie || _seriesId == null;

  Future<void> _addVj() async {
    final l = context.l10n;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l.addNewVj),
        content: VeloraTextField(
          label: l.vjName,
          controller: controller,
          onFieldSubmitted: (value) => Navigator.of(dialog).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: Text(l.cancel),
          ),
          VeloraButton(
            label: l.save,
            onPressed: () => Navigator.of(dialog).pop(controller.text),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty || !mounted) return;
    final vj = await runAdmin(context, (api) => api.addVj(name: trimmed));
    if (vj == null || !mounted) return;
    setState(() {
      _vjs = [..._vjs, vj]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _vjId = vj.id;
    });
  }

  Future<void> _choosePoster() async {
    final l = context.l10n;
    final image = await pickImage();
    if (image == null || !mounted) return;
    if (image.bytes.length > maxImageBytes) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.imageTooBig)));
      return;
    }
    setState(() => _poster = image);
  }

  Future<void> _chooseVideo() async {
    final l = context.l10n;
    final picked = await UploadsScope.pickerOf(context)();
    if (picked.isEmpty || !mounted) return;
    final video = picked.first;
    if (!isVideoFileName(video.file.name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.uploadsNotVideos(1))));
      return;
    }
    setState(() => _video = video);
  }

  String? _checkEpisode(AppLocalizations l) {
    final series = _existingSeries;
    final season = int.tryParse(_season.text.trim());
    final episode = int.tryParse(_episode.text.trim());
    if (series == null || season == null || episode == null) return null;
    return series.hasEpisode(season, episode)
        ? l.reviewEpisodeExists(season, episode)
        : null;
  }

  Future<void> _create() async {
    final l = context.l10n;
    if (!(_form.currentState?.validate() ?? false)) return;
    final api = AdminScope.of(context);
    if (api == null) return;
    final queue = UploadsScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);

    final series = _kind == EditionKind.series;
    final existing = _existingSeries;
    final title = _title.text.trim();
    final year = int.tryParse(_year.text.trim());
    final season = series ? int.parse(_season.text.trim()) : null;
    final episode = series ? int.parse(_episode.text.trim()) : null;
    final episodeTitle = _episodeTitle.text.trim();

    final KeyMade made;
    try {
      made = await api.createDraft(
        kind: _kind,
        title: existing == null ? title : null,
        year: existing == null && !series ? year : null,
        language: existing == null ? _language : null,
        seriesEditionId: existing?.id,
        season: season,
        episode: episode,
        episodeTitle: series && episodeTitle.isNotEmpty ? episodeTitle : null,
      );
    } on AdminException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(content: Text(adminFailureMessage(l, error))),
      );
      return;
    }
    final editionId = made.editionId!;

    // Each part saved on its own: one failing leaves the rest.
    final problems = <String>[];
    Future<void> step(String what, Future<void> Function() save) async {
      try {
        await save();
      } on AdminException catch (error) {
        problems.add('$what: ${adminFailureMessage(l, error)}');
      }
    }

    if (_newEdition) {
      if (_vjId case final vjId?) {
        await step(l.vjCredit, () => api.setCredit(editionId, vjId: vjId));
      }
      if (_categories.isNotEmpty) {
        await step(
          l.categoriesSection,
          () => api.setCategories(editionId, _categories),
        );
      }
      switch (_details) {
        case DetailsSource.tmdb:
          await step(
            l.details,
            () => api.searchTmdb(editionId, title: title, year: year),
          );
        case DetailsSource.typed:
          final overview = _overview.text.trim();
          await step(
            l.details,
            () => api.typeDetails(
              editionId,
              ManualDetails(
                title: title,
                year: year,
                overview: overview.isEmpty ? null : overview,
                genres: [
                  for (final genre in _genres.text.split(','))
                    if (genre.trim().isNotEmpty) genre.trim(),
                ],
                runtimeMinutes: int.tryParse(_runtime.text.trim()),
              ),
            ),
          );
        case DetailsSource.later:
          break;
      }
      if (_poster case final poster?) {
        await step(l.poster, () async {
          final path = await api.uploadImage(
            poster: true,
            ownerId: editionId,
            bytes: poster.bytes,
            contentType: poster.contentType,
          );
          await api.choosePoster(editionId, path);
        });
      }
    }

    final video = _video;
    final vj = _vjs.where((v) => v.id == _vjId).firstOrNull;
    if (video != null && queue != null) {
      await queue.addToItem(
        video,
        UploadPlan(
          kind: _kind,
          title: existing?.title ?? title,
          year: series ? null : year,
          language: existing == null ? _language : null,
          season: season,
          episode: episode,
          vjId: existing == null ? vj?.id : null,
          vjName: existing?.vjName ?? vj?.name,
          seriesEditionId: existing?.id,
          seriesTitle: existing?.title,
        ),
        editionId: editionId,
        itemId: made.itemId!,
        key: made.uploadKey,
      );
    } else if (mounted) {
      // The draft is made: nothing is loading behind the key.
      setState(() => _saving = false);
      await showUploadKey(context, made);
    }
    if (!mounted) return;

    // The draft opens in this screen's place, and says what happened there.
    unawaited(
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => DraftScreen(editionId: editionId),
        ),
      ),
    );
    // Replaces "Copied", from the key's dialog, rather than waiting behind it.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: problems.isEmpty ? 4 : 10),
          content: Text(
            problems.isEmpty
                ? (video != null && queue != null
                      ? l.newDraftMadeUploading
                      : l.newDraftMade)
                : l.newDraftMadeWithProblems(problems.join('\n')),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final series = _kind == EditionKind.series;
    final existing = _existingSeries;
    final canUpload = UploadsScope.of(context) != null;
    return Scaffold(
      appBar: AppBar(title: Text(l.newDraft)),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
          child: Form(
            key: _form,
            child: ScreenBody(
              heading: l.newDraft,
              intro: l.newDraftScreenIntro,
              maxWidth: VeloraLayout.readingWidth,
              children: [
                AdminSection(
                  title: l.newDraftWhat,
                  children: [
                    SegmentedButton<EditionKind>(
                      segments: [
                        ButtonSegment(
                          value: EditionKind.movie,
                          label: Text(l.movie),
                          icon: const Icon(Icons.movie_outlined),
                        ),
                        ButtonSegment(
                          value: EditionKind.series,
                          label: Text(l.seriesBadge),
                          icon: const Icon(Icons.video_library_outlined),
                        ),
                      ],
                      selected: {_kind},
                      onSelectionChanged: (kinds) =>
                          setState(() => _kind = kinds.first),
                    ),
                    if (series) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _seriesId,
                        isExpanded: true,
                        decoration: InputDecoration(labelText: l.addToSeries),
                        items: [
                          DropdownMenuItem(child: Text(l.newSeries)),
                          for (final s in _series)
                            DropdownMenuItem(
                              value: s.id,
                              child: Text(
                                [s.title, ?s.vjName].join(' · '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (id) => setState(() => _seriesId = id),
                      ),
                      Wrap(
                        spacing: VeloraSpacing.sm,
                        runSpacing: VeloraSpacing.sm,
                        children: [
                          SizedBox(
                            width: 140,
                            child: VeloraTextField(
                              label: l.season,
                              controller: _season,
                              keyboardType: TextInputType.number,
                              validator: (v) =>
                                  checkNumber(l, v, min: 0, max: 999) ??
                                  _checkEpisode(l),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            child: VeloraTextField(
                              label: l.episode,
                              controller: _episode,
                              keyboardType: TextInputType.number,
                              validator: (v) =>
                                  checkNumber(l, v, min: 1, max: 9999) ??
                                  _checkEpisode(l),
                            ),
                          ),
                        ],
                      ),
                      VeloraTextField(
                        label: l.episodeTitleOptional,
                        controller: _episodeTitle,
                      ),
                    ],
                  ],
                ),
                if (existing != null)
                  AdminSection(
                    title: l.titleAndVj,
                    children: [
                      Text(
                        l.episodeGoesTo(
                          existing.title,
                          existing.vjName ?? l.noVjYet,
                        ),
                      ),
                    ],
                  )
                else ...[
                  AdminSection(
                    title: l.titleAndVj,
                    children: [
                      VeloraTextField(
                        label: l.titleAsSubmitted,
                        helperText: l.titleAsSubmittedHelp,
                        controller: _title,
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ? l.required : null,
                      ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: VeloraSpacing.sm,
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _vjId,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l.vjCredit,
                                helperText: l.newDraftVjHelp,
                                helperMaxLines: 3,
                              ),
                              items: [
                                for (final vj in _vjs)
                                  DropdownMenuItem(
                                    value: vj.id,
                                    child: Text(vj.name),
                                  ),
                              ],
                              validator: (id) => id == null ? l.required : null,
                              onChanged: (id) => setState(() => _vjId = id),
                            ),
                          ),
                          IconButton(
                            tooltip: l.addNewVj,
                            icon: const Icon(Icons.person_add_alt),
                            onPressed: _addVj,
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: VeloraSpacing.sm,
                        runSpacing: VeloraSpacing.sm,
                        children: [
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              initialValue: _language,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: l.language,
                              ),
                              items: [
                                for (final language in _languages)
                                  DropdownMenuItem(
                                    value: language.code,
                                    child: Text(language.name),
                                  ),
                              ],
                              onChanged: (code) =>
                                  setState(() => _language = code ?? _language),
                            ),
                          ),
                          if (!series)
                            SizedBox(
                              width: 160,
                              child: VeloraTextField(
                                label: l.yearOptional,
                                controller: _year,
                                keyboardType: TextInputType.number,
                                validator: (v) => checkNumber(
                                  l,
                                  v,
                                  min: 1900,
                                  max: 2100,
                                  optional: true,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  AdminSection(
                    title: l.details,
                    children: [
                      SegmentedButton<DetailsSource>(
                        segments: [
                          ButtonSegment(
                            value: DetailsSource.tmdb,
                            label: Text(l.detailsFromTmdb),
                            icon: const Icon(Icons.search),
                          ),
                          ButtonSegment(
                            value: DetailsSource.typed,
                            label: Text(l.typeDetails),
                            icon: const Icon(Icons.edit_note),
                          ),
                          ButtonSegment(
                            value: DetailsSource.later,
                            label: Text(l.detailsLater),
                          ),
                        ],
                        selected: {_details},
                        onSelectionChanged: (choice) =>
                            setState(() => _details = choice.first),
                      ),
                      Text(switch (_details) {
                        DetailsSource.tmdb => l.detailsFromTmdbHelp,
                        DetailsSource.typed => l.detailsTypedHelp,
                        DetailsSource.later => l.detailsLaterHelp,
                      }),
                      if (_details == DetailsSource.typed) ...[
                        VeloraTextField(
                          label: l.overviewOptional,
                          controller: _overview,
                          maxLines: 5,
                        ),
                        VeloraTextField(
                          label: l.genresOptional,
                          helperText: l.genresHelp,
                          controller: _genres,
                        ),
                        VeloraTextField(
                          label: l.runtimeOptional,
                          controller: _runtime,
                          keyboardType: TextInputType.number,
                          validator: (v) => checkNumber(
                            l,
                            v,
                            min: 1,
                            max: 1000,
                            optional: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                  AdminSection(
                    title: l.categoriesSection,
                    children: [
                      Text(l.categoriesIntro),
                      CategoryInput(
                        categories: _categories,
                        suggestions: _knownCategories,
                        onChanged: (names) =>
                            setState(() => _categories = names),
                      ),
                    ],
                  ),
                  AdminSection(
                    title: l.poster,
                    children: [
                      if (_poster case final poster?)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(VeloraRadii.md),
                            child: Image.memory(
                              poster.bytes,
                              width: 120,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      Wrap(
                        spacing: VeloraSpacing.sm,
                        runSpacing: VeloraSpacing.xs,
                        children: [
                          VeloraButton(
                            label: _poster == null
                                ? l.uploadPoster
                                : l.changePoster,
                            icon: Icons.image_outlined,
                            variant: VeloraButtonVariant.secondary,
                            onPressed: _choosePoster,
                          ),
                          if (_poster != null)
                            VeloraButton(
                              label: l.remove,
                              variant: VeloraButtonVariant.tertiary,
                              onPressed: () => setState(() => _poster = null),
                            ),
                        ],
                      ),
                      Text(l.newDraftPosterHelp),
                    ],
                  ),
                ],
                AdminSection(
                  title: series ? l.episodeVideo : l.video,
                  children: [
                    if (!canUpload)
                      Text(l.newDraftKeyOnly)
                    else if (_video case final video?) ...[
                      Row(
                        spacing: VeloraSpacing.xs,
                        children: [
                          const Icon(Icons.movie_outlined),
                          Expanded(
                            child: Text(
                              '${video.file.name} · '
                              '${formatBytes(video.file.size)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: l.leaveOut,
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _video = null),
                          ),
                        ],
                      ),
                      Text(l.newDraftVideoQueued),
                    ] else ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: VeloraButton(
                          label: l.chooseFile,
                          icon: Icons.folder_open,
                          variant: VeloraButtonVariant.secondary,
                          onPressed: _chooseVideo,
                        ),
                      ),
                      Text(l.newDraftVideoHelp),
                    ],
                  ],
                ),
                Wrap(
                  spacing: VeloraSpacing.sm,
                  runSpacing: VeloraSpacing.xs,
                  children: [
                    VeloraButton(
                      label: l.createDraft,
                      icon: Icons.check,
                      isLoading: _saving,
                      onPressed: _create,
                    ),
                    VeloraButton(
                      label: l.cancel,
                      variant: VeloraButtonVariant.tertiary,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
