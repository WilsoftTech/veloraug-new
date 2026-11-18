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
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';
import 'draft_screen.dart';

/// Drafts, hidden editions and series with episodes waiting, each with what
/// it still needs.
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
    setState(() => _loading = true);
    try {
      final drafts = await api.drafts();
      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _failure = null;
        _loading = false;
      });
    } on AdminException catch (error) {
      if (!mounted) return;
      setState(() {
        _failure = error;
        _loading = false;
      });
    }
  }

  Future<void> _open(String editionId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DraftScreen(editionId: editionId),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _newDraft() async {
    final made = await showDialog<KeyMade>(
      context: context,
      builder: (_) => const NewDraftDialog(),
    );
    if (made == null || !mounted) return;
    await showUploadKey(context, made);
    final editionId = made.editionId;
    if (editionId != null && mounted) await _open(editionId);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final drafts = _drafts;
    final failure = _failure;
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
        else if (drafts.isEmpty)
          EmptyState(
            icon: Icons.inbox_outlined,
            title: l.noDraftsTitle,
            message: l.noDraftsMessage,
          )
        else
          for (final draft in drafts)
            _DraftTile(
              key: ValueKey(draft.id),
              draft: draft,
              onTap: () => _open(draft.id),
            ),
      ],
    );
  }
}

class _DraftTile extends StatelessWidget {
  const _DraftTile({super.key, required this.draft, required this.onTap});

  final AdminEdition draft;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (status, tone) = editionStatus(l, draft);
    final waiting = draft.items.where((item) => !item.approved).length;
    return Card.outlined(
      child: ListTile(
        onTap: onTap,
        title: Text(draft.displayTitle),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.xxs,
          children: [
            Text(
              [
                draft.kind == EditionKind.series ? l.seriesBadge : l.movie,
                draft.vjName ?? l.noVjYet,
                if (draft.test) l.testFilm,
              ].join(' · '),
            ),
            if (draft.missing.isNotEmpty)
              Text(
                l.stillNeeds(
                  draft.missing.map((m) => missingLabel(l, m)).join(', '),
                ),
              )
            else if (draft.published && waiting > 0)
              Text(l.episodesWaiting(waiting))
            else if (!draft.published)
              Text(l.readyToPublish),
          ],
        ),
        trailing: StatusBadge(label: status, tone: tone),
      ),
    );
  }
}

/// Starts a draft: title, movie or series, language, year, and for a series
/// the first episode's numbers. Pops with the new key.
class NewDraftDialog extends StatefulWidget {
  const NewDraftDialog({super.key});

  @override
  State<NewDraftDialog> createState() => _NewDraftDialogState();
}

class _NewDraftDialogState extends State<NewDraftDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _year = TextEditingController();
  final _season = TextEditingController(text: '1');
  final _episode = TextEditingController(text: '1');
  final _episodeTitle = TextEditingController();
  EditionKind _kind = EditionKind.movie;
  String _language = 'lg';
  List<AdminLanguage> _languages = const [
    AdminLanguage(code: 'lg', name: 'Luganda'),
  ];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final languages = await runAdmin(context, (api) => api.languages());
      if (languages != null && languages.isNotEmpty && mounted) {
        setState(() => _languages = languages);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _year, _season, _episode, _episodeTitle]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final series = _kind == EditionKind.series;
    final episodeTitle = _episodeTitle.text.trim();
    final made = await runAdmin(
      context,
      (api) => api.createDraft(
        kind: _kind,
        title: _title.text.trim(),
        year: int.tryParse(_year.text.trim()),
        language: _language,
        season: series ? int.parse(_season.text.trim()) : null,
        episode: series ? int.parse(_episode.text.trim()) : null,
        episodeTitle: series && episodeTitle.isNotEmpty ? episodeTitle : null,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (made != null) Navigator.of(context).pop(made);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final series = _kind == EditionKind.series;
    return AlertDialog(
      title: Text(l.newDraft),
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
                Text(l.newDraftIntro),
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
                VeloraTextField(
                  label: l.titleAsSubmitted,
                  helperText: l.titleAsSubmittedHelp,
                  controller: _title,
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? l.required : null,
                ),
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration: InputDecoration(labelText: l.language),
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
                VeloraTextField(
                  label: l.yearOptional,
                  controller: _year,
                  keyboardType: TextInputType.number,
                  validator: (value) => _number(l, value, 1900, 2100, true),
                ),
                if (series) ...[
                  VeloraTextField(
                    label: l.season,
                    controller: _season,
                    keyboardType: TextInputType.number,
                    validator: (value) => _number(l, value, 0, 999, false),
                  ),
                  VeloraTextField(
                    label: l.episode,
                    controller: _episode,
                    keyboardType: TextInputType.number,
                    validator: (value) => _number(l, value, 1, 9999, false),
                  ),
                  VeloraTextField(
                    label: l.episodeTitleOptional,
                    controller: _episodeTitle,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        VeloraButton(
          label: l.startDraft,
          isLoading: _saving,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Checks a whole number between [min] and [max]. Empty is fine if
/// [optional].
String? _number(
  AppLocalizations l,
  String? value,
  int min,
  int max,
  bool optional,
) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return optional ? null : l.required;
  final number = int.tryParse(text);
  if (number == null || number < min || number > max) {
    return l.numberBetween(min, max);
  }
  return null;
}

/// For other forms: the same check.
String? checkNumber(
  AppLocalizations l,
  String? value, {
  required int min,
  required int max,
  bool optional = false,
}) => _number(l, value, min, max, optional);
