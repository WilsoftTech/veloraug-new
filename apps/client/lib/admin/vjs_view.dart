import 'package:flutter/material.dart';

import '../api/admin_api.dart';
import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/edition_cards.dart' show VjAvatar;
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/screen_body.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_text_field.dart';
import 'admin_common.dart';
import 'image_picker.dart';

/// Every VJ, published or not: add one, or change a name, photo, bio or
/// the other spellings used to suggest credits.
class VjsView extends StatefulWidget {
  const VjsView({super.key});

  @override
  State<VjsView> createState() => _VjsViewState();
}

class _VjsViewState extends State<VjsView> {
  List<AdminVj>? _vjs;
  AdminException? _failure;
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

  Future<void> _edit(AdminVj? vj) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => VjDialog(vj: vj),
    );
    if (changed == true && mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final vjs = _vjs;
    final failure = _failure;
    return ScreenBody(
      heading: l.adminVjs,
      intro: l.adminVjsIntro,
      maxWidth: VeloraLayout.browseWidth,
      status: VeloraButton(
        label: l.addVj,
        icon: Icons.person_add_alt,
        onPressed: () => _edit(null),
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
        else
          for (final vj in vjs)
            Card.outlined(
              key: ValueKey(vj.id),
              child: ListTile(
                leading: VjAvatar(name: vj.name, photoUrl: vj.photoUrl),
                title: Text(vj.name),
                subtitle: Text(
                  [
                    l.publishedCount(vj.editions),
                    if (vj.matchNames.isNotEmpty)
                      l.alsoSpelled(vj.matchNames.join(', ')),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => _edit(vj),
              ),
            ),
      ],
    );
  }
}

/// Adds a VJ, or changes one. Pops with true when something was saved.
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
  late String? _photoUrl = widget.vj?.photoUrl;
  bool _saving = false;
  bool _photoChanged = false;

  @override
  void dispose() {
    _name.dispose();
    _spellings.dispose();
    _bio.dispose();
    super.dispose();
  }

  List<String> get _matchNames => [
    for (final name in _spellings.text.split(','))
      if (name.trim().isNotEmpty) name.trim(),
  ];

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final vj = widget.vj;
    final bio = _bio.text.trim();
    final saved = await runAdmin(
      context,
      (api) => vj == null
          ? api.addVj(
              name: _name.text.trim(),
              matchNames: _matchNames,
              bio: bio.isEmpty ? null : bio,
            )
          : api.changeVj(
              vj.id,
              name: _name.text.trim(),
              matchNames: _matchNames,
              bio: bio,
            ),
    );
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

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final vj = widget.vj;
    return AlertDialog(
      title: Text(vj == null ? l.addVj : l.editVj),
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
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? l.required : null,
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
              ],
            ),
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
