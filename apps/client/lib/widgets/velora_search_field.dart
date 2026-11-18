import 'package:flutter/material.dart';

import '../l10n/l10n.dart';

/// A labelled search box with a clear control. It sends nothing itself: the
/// caller decides what to do with the text.
class VeloraSearchField extends StatefulWidget {
  const VeloraSearchField({
    super.key,
    this.label,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
  });

  /// Defaults to "Search titles and VJs".
  final String? label;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;

  @override
  State<VeloraSearchField> createState() => _VeloraSearchFieldState();
}

class _VeloraSearchFieldState extends State<VeloraSearchField> {
  TextEditingController? _ownController;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());

  @override
  void dispose() {
    _ownController?.dispose();
    super.dispose();
  }

  void _clear() {
    _controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final showClear = _controller.text.isNotEmpty && widget.enabled;
        return TextField(
          controller: _controller,
          enabled: widget.enabled,
          textInputAction: TextInputAction.search,
          onChanged: widget.onChanged,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            labelText: widget.label ?? context.l10n.searchLabel,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: showClear
                ? IconButton(
                    tooltip: context.l10n.clearSearch,
                    icon: const Icon(Icons.close),
                    onPressed: _clear,
                  )
                : null,
          ),
        );
      },
    );
  }
}
