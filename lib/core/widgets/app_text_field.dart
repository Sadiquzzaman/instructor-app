import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_metrics.dart';

/// A labelled text field. Every field has a visible label (design system:
/// "every control has a visible label"); text comes from the caller.
///
/// For passwords pass [obscure] with [showLabel] and [hideLabel] (the web's
/// `auth.showPassword` / `auth.hidePassword`) for the eye button.
class AppTextField extends StatefulWidget {
  const AppTextField({
    required this.label,
    this.controller,
    this.hint,
    this.errorText,
    this.helperText,
    this.keyboardType,
    this.textInputAction,
    this.autofillHints,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.obscure = false,
    this.showLabel,
    this.hideLabel,
    this.maxLines = 1,
    this.maxLength,
    this.autofocus = false,
    super.key,
  }) : assert(
         !obscure || (showLabel != null && hideLabel != null),
         'A password field needs the show and hide labels.',
       );

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool enabled;
  final bool obscure;
  final String? showLabel;
  final String? hideLabel;
  final int maxLines;

  /// A character limit, with a counter under the field.
  final int? maxLength;

  /// Takes the focus (and opens the keyboard) when it first shows.
  final bool autofocus;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late bool _hidden = widget.obscure;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: TextField(
        controller: widget.controller,
        autofocus: widget.autofocus,
        enabled: widget.enabled,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        autofillHints: widget.autofillHints,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        obscureText: _hidden,
        enableSuggestions: !widget.obscure,
        autocorrect: !widget.obscure,
        maxLines: widget.obscure ? 1 : widget.maxLines,
        maxLength: widget.maxLength,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: widget.errorText,
          helperText: widget.helperText,
          suffixIcon: widget.obscure
              ? IconButton(
                  tooltip: _hidden ? widget.showLabel : widget.hideLabel,
                  icon: Icon(
                    _hidden
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                  onPressed: () => setState(() => _hidden = !_hidden),
                )
              : null,
        ),
      ),
    );
  }
}
