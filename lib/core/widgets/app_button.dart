import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';

enum AppButtonVariant {
  /// Filled brand green: the main action on a screen.
  primary,

  /// Outlined: other actions.
  secondary,

  /// Text only: low-emphasis actions and links.
  text,

  /// Filled red: actions that remove, end or cannot be undone.
  danger,
}

/// The app's button. Text comes from the caller (translated); while [loading]
/// it shows a spinner, ignores taps and tells screen readers it is busy.
class AppButton extends StatelessWidget {
  const AppButton({
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
    super.key,
  });

  final String label;

  /// Null disables the button.
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;

  /// Fill the available width (forms on phones).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null && !loading;
    final callback = enabled ? onPressed : null;

    final spinnerColor = switch (variant) {
      AppButtonVariant.primary || AppButtonVariant.danger => colors.inkInverse,
      AppButtonVariant.secondary || AppButtonVariant.text => colors.primary,
    };
    final Widget content = loading
        ? SizedBox.square(
            dimension: AppSpacing.lg + 2,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppSpacing.lg + 2),
                const SizedBox(width: AppSpacing.sm),
              ],
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
            ],
          );

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: callback,
        child: content,
      ),
      AppButtonVariant.danger => FilledButton(
        onPressed: callback,
        style: FilledButton.styleFrom(
          backgroundColor: colors.danger,
          foregroundColor: colors.inkInverse,
        ),
        child: content,
      ),
      AppButtonVariant.secondary => OutlinedButton(
        onPressed: callback,
        child: content,
      ),
      AppButtonVariant.text => TextButton(onPressed: callback, child: content),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: loading ? label : null,
      excludeSemantics: loading,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}
