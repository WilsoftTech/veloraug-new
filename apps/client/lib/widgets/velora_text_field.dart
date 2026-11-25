import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../l10n/l10n.dart';

/// A labelled text field. It validates inside a [Form], and an error shows an
/// icon and words, so it doesn't rely on the red border.
class VeloraTextField extends StatelessWidget {
  const VeloraTextField({
    super.key,
    required this.label,
    this.controller,
    this.focusNode,
    this.helperText,
    this.hintText,
    this.validator,
    this.onChanged,
    this.onFieldSubmitted,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.prefixIcon,
    this.suffixIcon,
    this.autovalidateMode = AutovalidateMode.onUserInteractionIfError,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final String? helperText;
  final String? hintText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;
  final bool obscureText;
  final bool autocorrect;
  final bool enableSuggestions;
  final Widget? prefixIcon;
  final Widget? suffixIcon;

  /// By default an error appears on submit, then clears as it is corrected.
  final AutovalidateMode autovalidateMode;

  /// More than one for longer text, such as a description.
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      onChanged: onChanged,
      onFieldSubmitted: onFieldSubmitted,
      autovalidateMode: autovalidateMode,
      errorBuilder: (context, errorText) => VeloraFieldError(errorText),
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        hintText: hintText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// A field's error: an icon and words in the danger colour.
class VeloraFieldError extends StatelessWidget {
  const VeloraFieldError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final color = VeloraPalette.of(context).danger;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(Icons.error_outline, size: 16, color: color),
        ),
        const SizedBox(width: VeloraSpacing.xxs),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

/// A password field with a labelled show and hide control. It is presentation
/// only: the caller owns the value and what happens to it.
class VeloraPasswordField extends StatefulWidget {
  const VeloraPasswordField({
    super.key,
    this.label,
    this.controller,
    this.helperText,
    this.validator,
    this.onFieldSubmitted,
    this.textInputAction,
    this.autofillHints = const [AutofillHints.password],
    this.enabled = true,
  });

  /// Defaults to "Password".
  final String? label;
  final TextEditingController? controller;
  final String? helperText;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final bool enabled;

  @override
  State<VeloraPasswordField> createState() => _VeloraPasswordFieldState();
}

class _VeloraPasswordFieldState extends State<VeloraPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return VeloraTextField(
      label: widget.label ?? context.l10n.password,
      controller: widget.controller,
      helperText: widget.helperText,
      validator: widget.validator,
      onFieldSubmitted: widget.onFieldSubmitted,
      textInputAction: widget.textInputAction,
      autofillHints: widget.autofillHints,
      enabled: widget.enabled,
      keyboardType: TextInputType.visiblePassword,
      obscureText: _obscured,
      autocorrect: false,
      enableSuggestions: false,
      suffixIcon: IconButton(
        tooltip: _obscured
            ? context.l10n.showPassword
            : context.l10n.hidePassword,
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: widget.enabled
            ? () => setState(() => _obscured = !_obscured)
            : null,
      ),
    );
  }
}
