import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../api/catalogue_api.dart' show EditionKind;
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/edition_cards.dart' show VjAvatar;
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/movie_poster.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';
import 'draft_screen.dart';
import 'image_picker.dart';
import 'library_view.dart' show libraryState;

/// A link's name as admins see it.
String vjLinkLabel(AppLocalizations l, String name) => switch (name) {
  'facebook' => 'Facebook',
  'instagram' => 'Instagram',
  'tiktok' => 'TikTok',
  'youtube' => 'YouTube',
  'x' => 'X',
  'whatsapp' => 'WhatsApp',
  _ => l.website,
};

/// "12 published · 2 drafts · 340 viewers in 30 days".
String vjFacts(AppLocalizations l, AdminVj vj) => [
  l.publishedCount(vj.published),
  if (vj.hidden > 0) l.hiddenTitleCount(vj.hidden),
  if (vj.drafts > 0) l.draftCount(vj.drafts),
  l.viewersLately(vj.viewers, 30),
].join(' · ');

/// Every VJ, active or not: searched, filtered and sorted. Each opens on
/// their own page, with their titles.
class VjsView extends StatefulWidget {
  const VjsView({super.key});

  @override
  State<VjsView> createState() => _VjsViewState();
}

class _VjsViewState extends State<VjsView> {
  final _search = TextEditingController();
  List<AdminVj>? _vjs;
  AdminException? _failure;
  bool _started = false;

  /// all, active, inactive or featured.
  String _show = 'all';

  /// name, titles, viewers or order.
  String _sort = 'name';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = AdminScope.of(context);
    if (api == null) return;
    try {
      final vjs = await api.vjs();
      if (mounted) {
        setState(() {
          _vjs = vjs;
          _failure = null;
        });
      }
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _add() async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => const VjDialog(),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _open(AdminVj vj) async {
    await Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => VjScreen(vjId: vj.id)));
    if (mounted) await _load();
  }

  /// The VJs shown, as the search, filter and sort say.
  List<AdminVj> _shown(List<AdminVj> vjs) {
    final words = _search.text.trim().toLowerCase();
    final shown = [
      for (final vj in vjs)
        if ((words.isEmpty ||
                vj.name.toLowerCase().contains(words) ||
                vj.matchNames.any((m) => m.toLowerCase().contains(words))) &&
            switch (_show) {
              'active' => vj.active,
              'inactive' => !vj.active,
              'featured' => vj.featured,
              _ => true,
            })
          vj,
    ];
    int compare(AdminVj a, AdminVj b) {
      final first = switch (_sort) {
        'titles' => b.published.compareTo(a.published),
        'viewers' => b.viewers.compareTo(a.viewers),
        // As the app lists them: featured, then by place.
        'order' =>
          a.featured != b.featured
              ? (a.featured ? -1 : 1)
              : (a.sortOrder ?? 100000).compareTo(b.sortOrder ?? 100000),
        _ => 0,
      };
      // Equal ones by name.
      return first != 0
          ? first
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    }

    return shown..sort(compare);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final vjs = _vjs;
    final failure = _failure;
    final shown = vjs == null ? const <AdminVj>[] : _shown(vjs);
    return ScreenBody(
      heading: l.adminVjs,
      intro: l.adminVjsIntro,
      maxWidth: VeloraLayout.browseWidth,
      status: VeloraButton(
        label: l.addVj,
        icon: Icons.person_add_alt,
        onPressed: _add,
      ),
      children: [
        if (failure != null)
          ErrorState(
            title: l.adminLoadFailed,
            message: adminFailureMessage(l, failure),
            onRetry: _load,
          )
        else if (vjs == null)
          Center(
            child: VeloraLoadingRegion(
              label: l.loading,
              child: const VeloraSpinner(size: 32),
            ),
          )
        else if (vjs.isEmpty)
          EmptyState(
            icon: Icons.groups_outlined,
            title: l.noVjsTitle,
            message: l.noVjsMessage,
          )
        else ...[
          TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l.searchVjs,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          Wrap(
            spacing: VeloraSpacing.xs,
            runSpacing: VeloraSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final (value, label) in [
                ('all', l.libraryAll),
                ('active', l.vjActive),
                ('inactive', l.vjInactive),
                ('featured', l.vjFeatured),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _show == value,
                  onSelected: (_) => setState(() => _show = value),
                ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<String>(
                  initialValue: _sort,
                  isExpanded: true,
                  isDense: true,
                  decoration: InputDecoration(labelText: l.sortBy),
                  items: [
                    for (final (value, label) in [
                      ('name', l.sortName),
                      ('titles', l.sortMostTitles),
                      ('viewers', l.sortViewers),
                      ('order', l.sortAppOrder),
                    ])
                      DropdownMenuItem(value: value, child: Text(label)),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? 'name'),
                ),
              ),
            ],
          ),
          Text(l.vjCount(shown.length)),
          for (final vj in shown)
            _VjTile(key: ValueKey(vj.id), vj: vj, onTap: () => _open(vj)),
        ],
      ],
    );
  }
}

class _VjTile extends StatelessWidget {
  const _VjTile({super.key, required this.vj, required this.onTap});

  final AdminVj vj;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Card.outlined(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VeloraRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(VeloraSpacing.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.sm,
            children: [
              VjAvatar(name: vj.name, photoUrl: vj.photoUrl, size: 48),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: VeloraSpacing.xxs,
                  children: [
                    Text(
                      vj.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(vjFacts(l, vj)),
                    if (vj.matchNames.isNotEmpty)
                      Text(
                        l.alsoSpelled(vj.matchNames.join(', ')),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    _VjBadges(vj: vj),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _VjBadges extends StatelessWidget {
  const _VjBadges({required this.vj});

  final AdminVj vj;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final order = vj.sortOrder;
    return Wrap(
      spacing: VeloraSpacing.xs,
      runSpacing: VeloraSpacing.xxs,
      children: [
        StatusBadge(
          label: vj.active ? l.vjActive : l.vjInactive,
          tone: vj.active ? StatusTone.success : StatusTone.neutral,
        ),
        if (vj.featured)
          StatusBadge(label: l.vjFeatured, tone: StatusTone.info),
        if (order != null)
          StatusBadge(label: l.vjPlace(order), tone: StatusTone.neutral),
      ],
    );
  }
}

/// One VJ: their profile and links, what they have, and what can be done:
/// edit, make inactive or active, merge into another VJ, delete.
class VjScreen extends StatefulWidget {
  const VjScreen({super.key, required this.vjId});

  final String vjId;

  @override
  State<VjScreen> createState() => _VjScreenState();
}

class _VjScreenState extends State<VjScreen> {
  AdminVj? _vj;
  List<LibraryTitle>? _titles;
  int _total = 0;
  AdminException? _failure;
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
      final vj = await api.vj(widget.vjId);
      final page = await api.library(vjId: widget.vjId, sort: 'title');
      if (!mounted) return;
      setState(() {
        _vj = vj;
        _titles = page.titles;
        _total = page.total;
        _failure = null;
      });
    } on AdminException catch (error) {
      if (mounted) setState(() => _failure = error);
    }
  }

  Future<void> _edit(AdminVj vj) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => VjDialog(vj: vj),
    );
    if (changed == true && mounted) await _load();
  }

  Future<void> _setActive(AdminVj vj, bool active) async {
    final l = context.l10n;
    if (!active &&
        !await confirm(
          context,
          title: l.deactivateVjTitle(vj.name),
          message: l.deactivateVjMessage,
          action: l.makeInactive,
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final saved = await runAdmin(
      context,
      (api) => api.changeVj(vj.id, active: active),
      done: active ? l.vjActivated(vj.name) : l.vjDeactivated(vj.name),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (saved != null) _vj = saved;
    });
  }

  Future<void> _merge(AdminVj vj) async {
    final l = context.l10n;
    final others = await runAdmin(context, (api) => api.vjs());
    if (others == null || !mounted) return;
    final into = await showDialog<AdminVj>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: Text(l.mergeVjTitle(vj.name)),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: VeloraSpacing.lg),
            child: Text(l.mergeVjChoose),
          ),
          for (final other in others)
            if (other.id != vj.id)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialog).pop(other),
                child: Text(
                  '${other.name} · ${l.publishedCount(other.published)}',
                ),
              ),
        ],
      ),
    );
    if (into == null || !mounted) return;
    if (!await confirm(
      context,
      title: l.mergeVjConfirmTitle(vj.name, into.name),
      message: l.mergeVjConfirmMessage(vj.editions, vj.name, into.name),
      action: l.mergeVj,
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final merged = await runAdmin(
      context,
      (api) => api.mergeVj(vj.id, into.id),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (merged == null) return;
    final (moved, target) = merged;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(l.vjMerged(moved, target.name))));
    // This VJ is gone: their titles are now the other's.
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => VjScreen(vjId: target.id)),
    );
  }

  Future<void> _delete(AdminVj vj) async {
    final l = context.l10n;
    if (!await confirm(
      context,
      title: l.deleteVjTitle(vj.name),
      message: l.deleteVjMessage,
      action: l.deletePermanently,
      danger: true,
    )) {
      return;
    }
    if (!mounted) return;
    final done = await runAdmin(
      context,
      (api) => api.deleteVj(vj.id).then((_) => true),
      done: l.vjDeleted(vj.name),
    );
    if (done == true && mounted) Navigator.of(context).pop();
  }

  Future<void> _openTitle(LibraryTitle title) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DraftScreen(editionId: title.id)),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final vj = _vj;
    final failure = _failure;
    return Scaffold(
      appBar: AppBar(title: Text(vj?.name ?? l.adminVjs)),
      body: SafeArea(
        child: failure != null
            ? ScreenBody(
                heading: l.adminVjs,
                children: [
                  ErrorState(
                    title: l.adminLoadFailed,
                    message: adminFailureMessage(l, failure),
                    onRetry: _load,
                  ),
                ],
              )
            : vj == null
            ? Center(
                child: VeloraLoadingRegion(
                  label: l.loading,
                  child: const VeloraSpinner(size: 32),
                ),
              )
            : AbsorbPointer(absorbing: _busy, child: _body(l, vj)),
      ),
    );
  }

  Widget _body(AppLocalizations l, AdminVj vj) {
    final titles = _titles ?? const <LibraryTitle>[];
    return ScreenBody(
      heading: vj.name,
      intro: vjFacts(l, vj),
      maxWidth: VeloraLayout.browseWidth,
      children: [
        AdminSection(
          title: l.vjProfile,
          status: _VjBadges(vj: vj),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: VeloraSpacing.md,
              children: [
                VjAvatar(name: vj.name, photoUrl: vj.photoUrl, size: 72),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: VeloraSpacing.xs,
                    children: [
                      Text((vj.bio ?? '').isEmpty ? l.vjNoBioYet : vj.bio!),
                      if (vj.matchNames.isNotEmpty)
                        Text(l.alsoSpelled(vj.matchNames.join(', '))),
                    ],
                  ),
                ),
              ],
            ),
            if (vj.links.isEmpty)
              Text(l.vjNoLinks)
            else
              Wrap(
                spacing: VeloraSpacing.xs,
                runSpacing: VeloraSpacing.xs,
                children: [
                  for (final name in vjLinkNames)
                    if (vj.links[name] case final url?)
                      Tooltip(
                        message: url,
                        child: Chip(
                          avatar: const Icon(Icons.link, size: 18),
                          label: Text(vjLinkLabel(l, name)),
                        ),
                      ),
                ],
              ),
            Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.xs,
              children: [
                VeloraButton(
                  label: l.editVj,
                  icon: Icons.edit_outlined,
                  onPressed: () => _edit(vj),
                ),
                VeloraButton(
                  label: vj.active ? l.makeInactive : l.makeActive,
                  icon: vj.active
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  variant: VeloraButtonVariant.secondary,
                  onPressed: () => _setActive(vj, !vj.active),
                ),
                VeloraButton(
                  label: l.mergeVj,
                  icon: Icons.merge_type,
                  variant: VeloraButtonVariant.secondary,
                  onPressed: () => _merge(vj),
                ),
                if (vj.editions == 0)
                  VeloraButton(
                    label: l.deletePermanently,
                    icon: Icons.delete_forever_outlined,
                    variant: VeloraButtonVariant.danger,
                    onPressed: () => _delete(vj),
                  ),
              ],
            ),
          ],
        ),
        AdminSection(
          title: l.vjTitles(_total),
          children: [
            if (vj.drafts > 0) Text(l.vjDraftsElsewhere(vj.drafts)),
            if (_titles == null)
              const Center(child: VeloraSpinner(size: 24))
            else if (titles.isEmpty)
              Text(l.vjNoTitles)
            else
              for (final title in titles)
                _VjTitleTile(
                  key: ValueKey(title.id),
                  title: title,
                  onTap: () => _openTitle(title),
                ),
            if (titles.length < _total)
              Text(l.vjMoreInLibrary(_total - titles.length)),
          ],
        ),
      ],
    );
  }
}

class _VjTitleTile extends StatelessWidget {
  const _VjTitleTile({super.key, required this.title, required this.onTap});

  final LibraryTitle title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final (badge, tone) = libraryState(l, title.state);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: onTap,
        leading: SizedBox(width: 36, child: MoviePoster(url: title.posterUrl)),
        title: Text(title.title),
        // The badge under the details, so a narrow phone has room.
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: VeloraSpacing.xxs,
          children: [
            Text(
              [
                title.kind == EditionKind.series ? l.seriesBadge : l.movie,
                l.viewersLately(title.viewers, 30),
              ].join(' · '),
            ),
            StatusBadge(label: badge, tone: tone),
          ],
        ),
      ),
    );
  }
}

/// Adds a VJ, or changes one: name, other spellings, bio, photo, links,
/// featured, and their place in the app's list. Pops with true when
/// something was saved.
class VjDialog extends StatefulWidget {
  const VjDialog({super.key, this.vj});

  /// Null to add a new VJ.
  final AdminVj? vj;

  @override
  State<VjDialog> createState() => _VjDialogState();
}

class _VjDialogState extends State<VjDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.vj?.name ?? '');
  late final _spellings = TextEditingController(
    text: widget.vj?.matchNames.join(', ') ?? '',
  );
  late final _bio = TextEditingController(text: widget.vj?.bio ?? '');
  late final _order = TextEditingController(
    text: widget.vj?.sortOrder?.toString() ?? '',
  );
  late final Map<String, TextEditingController> _links = {
    for (final name in vjLinkNames)
      name: TextEditingController(text: widget.vj?.links[name] ?? ''),
  };
  late bool _featured = widget.vj?.featured ?? false;
  late String? _photoUrl = widget.vj?.photoUrl;
  bool _saving = false;
  bool _photoChanged = false;

  @override
  void dispose() {
    for (final c in [_name, _spellings, _bio, _order, ..._links.values]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _matchNames => [
    for (final name in _spellings.text.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];

  Map<String, String> get _linkValues => {
    for (final MapEntry(:key, :value) in _links.entries) key: value.text.trim(),
  };

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final vj = widget.vj;
    final bio = _bio.text.trim();
    final order = int.tryParse(_order.text.trim());
    final saved = await runAdmin(context, (api) async {
      final id =
          vj?.id ??
          (await api.addVj(
            name: _name.text.trim(),
            matchNames: _matchNames,
            bio: bio.isEmpty ? null : bio,
          )).id;
      return api.changeVj(
        id,
        name: vj == null ? null : _name.text.trim(),
        matchNames: vj == null ? null : _matchNames,
        bio: vj == null ? null : bio,
        featured: _featured,
        sortOrder: order,
        clearSortOrder: order == null,
        links: _linkValues,
      );
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (saved != null) Navigator.of(context).pop(true);
  }

  /// Photos go to an existing VJ, so a new VJ is saved first.
  Future<void> _uploadPhoto() async {
    final l = context.l10n;
    final vj = widget.vj;
    if (vj == null) return;
    final image = await pickImage();
    if (image == null || !mounted) return;
    if (image.bytes.length > maxImageBytes) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l.imageTooBig)));
      return;
    }
    setState(() => _saving = true);
    final saved = await runAdmin(context, (api) async {
      final path = await api.uploadImage(
        poster: false,
        ownerId: vj.id,
        bytes: image.bytes,
        contentType: image.contentType,
      );
      return api.changeVj(vj.id, photoPath: path);
    }, done: l.photoUploaded);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved != null) {
        _photoUrl = saved.photoUrl;
        _photoChanged = true;
      }
    });
  }

  String? _checkLink(AppLocalizations l, String name, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return null;
    if (!text.toLowerCase().startsWith('https://') || text.contains(' ')) {
      return l.linkMustBeHttps;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final vj = widget.vj;
    return AlertDialog(
      title: Text(vj == null ? l.addVj : l.editVj),
      scrollable: true,
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: VeloraLayout.readingWidth),
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: VeloraSpacing.sm,
            children: [
              if (vj != null)
                Row(
                  spacing: VeloraSpacing.md,
                  children: [
                    VjAvatar(name: vj.name, photoUrl: _photoUrl, size: 72),
                    Expanded(
                      child: VeloraButton(
                        label: l.uploadPhoto,
                        icon: Icons.upload_outlined,
                        variant: VeloraButtonVariant.secondary,
                        onPressed: _saving ? null : _uploadPhoto,
                      ),
                    ),
                  ],
                )
              else
                Text(l.photoAfterAdding),
              VeloraTextField(
                label: l.vjName,
                controller: _name,
                helperText: l.vjNameHelp,
                validator: (v) => (v ?? '').trim().isEmpty ? l.required : null,
              ),
              VeloraTextField(
                label: l.otherSpellings,
                helperText: l.otherSpellingsHelp,
                controller: _spellings,
              ),
              VeloraTextField(
                label: l.bio,
                controller: _bio,
                maxLines: 4,
                validator: (v) =>
                    (v ?? '').length > 1000 ? l.tooLong(1000) : null,
              ),
              Text(l.vjInTheApp, style: Theme.of(context).textTheme.titleSmall),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l.vjFeatured),
                subtitle: Text(l.vjFeaturedHelp),
                value: _featured,
                onChanged: (on) => setState(() => _featured = on),
              ),
              VeloraTextField(
                label: l.vjPlaceLabel,
                helperText: l.vjPlaceHelp,
                controller: _order,
                keyboardType: TextInputType.number,
                validator: (v) =>
                    checkNumber(l, v, min: 1, max: 9999, optional: true),
              ),
              Text(l.vjLinks, style: Theme.of(context).textTheme.titleSmall),
              for (final name in vjLinkNames)
                VeloraTextField(
                  label: vjLinkLabel(l, name),
                  hintText: 'https://…',
                  controller: _links[name],
                  keyboardType: TextInputType.url,
                  validator: (v) => _checkLink(l, name, v),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving
              ? null
              : () => Navigator.of(context).pop(_photoChanged),
          child: Text(l.cancel),
        ),
        VeloraButton(label: l.save, isLoading: _saving, onPressed: _save),
      ],
    );
  }
}
