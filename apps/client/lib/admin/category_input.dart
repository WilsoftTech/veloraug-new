import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/l10n.dart';
import '../theme/tokens.dart';
import '../widgets/velora_text_field.dart';

/// At most this many categories on a title. The API checks too.
const int maxCategories = 10;

/// A category's name is at most this long. The API checks too.
const int maxCategoryLength = 40;

/// Trimmed, with single spaces, as the API saves it.
String tidyCategory(String name) => name.trim().split(RegExp(r'\s+')).join(' ');

/// A title's categories as chips, with a field to add more. Enter or a comma
/// adds what was typed; a suggestion can be tapped. Each chip's × removes
/// it, and so does Backspace in the empty field, for the last one.
///
/// A name matching a suggestion whatever its case takes the suggestion's
/// spelling, so "indian" adds "Indian". Every change is passed to
/// [onChanged], which saves it.
class CategoryInput extends StatefulWidget {
  const CategoryInput({
    super.key,
    required this.categories,
    required this.suggestions,
    required this.onChanged,
  });

  final List<String> categories;

  /// Known category names, the most used first.
  final List<String> suggestions;
  final ValueChanged<List<String>> onChanged;

  @override
  State<CategoryInput> createState() => _CategoryInputState();
}

class _CategoryInputState extends State<CategoryInput> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _full => widget.categories.length >= maxCategories;

  bool _has(List<String> names, String name) =>
      names.any((other) => other.toLowerCase() == name.toLowerCase());

  /// Adds each name, in order. False, with an error shown, if one can't be.
  bool _add(Iterable<String> typed) {
    final l = context.l10n;
    final names = [...widget.categories];
    for (final raw in typed) {
      final name = tidyCategory(raw);
      if (name.isEmpty || _has(names, name)) continue;
      if (name.length > maxCategoryLength) {
        setState(() => _error = l.categoryTooLong(maxCategoryLength));
        return false;
      }
      if (names.length >= maxCategories) {
        setState(() => _error = l.categoriesFull(maxCategories));
        return false;
      }
      names.add(
        widget.suggestions
                .where((known) => known.toLowerCase() == name.toLowerCase())
                .firstOrNull ??
            name,
      );
    }
    setState(() => _error = null);
    if (names.length != widget.categories.length) widget.onChanged(names);
    return true;
  }

  void _remove(String name) {
    setState(() => _error = null);
    widget.onChanged([
      for (final other in widget.categories)
        if (other != name) other,
    ]);
  }

  /// A comma adds everything before it, and keeps what follows.
  void _typed(String text) {
    if (!text.contains(',')) {
      if (_error != null) setState(() => _error = null);
      return;
    }
    final parts = text.split(',');
    final rest = parts.removeLast();
    if (_add(parts)) _set(rest.trimLeft());
  }

  void _submitted(String text) {
    if (_add([text])) _set('');
    _focus.requestFocus();
  }

  void _set(String text) => _controller.value = TextEditingValue(
    text: text,
    selection: TextSelection.collapsed(offset: text.length),
  );

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controller.text.isEmpty &&
        widget.categories.isNotEmpty) {
      _remove(widget.categories.last);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.sm,
      children: [
        if (widget.categories.isEmpty)
          Text(l.categoriesNone, style: theme.textTheme.bodyMedium)
        else
          Wrap(
            spacing: VeloraSpacing.xs,
            runSpacing: VeloraSpacing.xs,
            children: [
              for (final name in widget.categories)
                InputChip(
                  key: ValueKey('category-$name'),
                  label: Text(name),
                  onDeleted: () => _remove(name),
                  deleteButtonTooltipMessage: l.categoryRemove(name),
                ),
            ],
          ),
        Focus(
          onKeyEvent: _key,
          canRequestFocus: false,
          skipTraversal: true,
          child: RawAutocomplete<String>(
            textEditingController: _controller,
            focusNode: _focus,
            optionsBuilder: (value) {
              final typed = tidyCategory(value.text).toLowerCase();
              if (typed.isEmpty) return const [];
              return widget.suggestions
                  .where(
                    (name) =>
                        name.toLowerCase().contains(typed) &&
                        !_has(widget.categories, name),
                  )
                  .take(8);
            },
            onSelected: (name) {
              if (_add([name])) _set('');
              _focus.requestFocus();
            },
            fieldViewBuilder: (context, controller, focusNode, _) =>
                VeloraTextField(
                  key: const ValueKey('category-field'),
                  label: l.categoryField,
                  helperText: l.categoryCount(
                    widget.categories.length,
                    maxCategories,
                  ),
                  hintText: l.categoryHint,
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !_full,
                  textInputAction: TextInputAction.done,
                  onChanged: _typed,
                  onFieldSubmitted: _submitted,
                ),
            optionsViewBuilder: (context, onSelected, options) => Align(
              alignment: Alignment.topLeft,
              child: Card.outlined(
                margin: EdgeInsets.zero,
                clipBehavior: Clip.antiAlias,
                child: ConstrainedBox(
                  // Five suggestions, then it scrolls.
                  constraints: const BoxConstraints(
                    maxHeight: VeloraLayout.minTouchTarget * 5,
                    maxWidth: VeloraLayout.formWidth,
                  ),
                  child: ListView(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    children: [
                      for (final name in options)
                        ListTile(
                          key: ValueKey('category-option-$name'),
                          title: Text(name),
                          onTap: () => onSelected(name),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_error case final error?)
          Semantics(liveRegion: true, child: VeloraFieldError(error)),
        if (_full)
          Text(
            l.categoriesFull(maxCategories),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
  }
}
