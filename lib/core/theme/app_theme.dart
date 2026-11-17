import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/theme/app_text.dart';

/// The app's one theme, built only from the web's tokens.
abstract final class AppTheme {
  /// Light theme; [bangla] switches fonts and line heights for Bangla.
  static ThemeData light({required bool bangla}) {
    const c = AppColors.light;
    final text = AppText.forLanguage(bangla: bangla, color: c.ink);
    final textTheme = text.toTextTheme();

    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: c.primary,
      onPrimary: c.inkInverse,
      primaryContainer: c.primarySoft,
      onPrimaryContainer: c.ink,
      secondary: c.primary,
      onSecondary: c.inkInverse,
      secondaryContainer: c.primarySoft,
      onSecondaryContainer: c.ink,
      tertiary: c.warning,
      onTertiary: c.inkInverse,
      error: c.danger,
      onError: c.inkInverse,
      errorContainer: c.dangerSoft,
      onErrorContainer: c.danger,
      surface: c.surface,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.border,
      outlineVariant: c.border,
      shadow: c.ink,
      surfaceTint: c.surface,
      inverseSurface: c.ink,
      onInverseSurface: c.inkInverse,
      inversePrimary: c.primarySoft,
    );

    const buttonShape = RoundedRectangleBorder(
      borderRadius: AppRadius.inputAll,
    );
    const minButtonSize = Size(AppSpacing.tapTarget, AppSpacing.tapTarget + 4);
    const buttonPadding = EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: AppRadius.inputAll,
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.canvas,
      canvasColor: c.canvas,
      fontFamily: bangla ? AppFonts.bangla : AppFonts.latin,
      fontFamilyFallback: [bangla ? AppFonts.latin : AppFonts.bangla],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      dividerColor: c.border,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      extensions: const [AppColors.light],
      appBarTheme: AppBarTheme(
        backgroundColor: c.canvas,
        foregroundColor: c.ink,
        surfaceTintColor: c.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleSm,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.primary,
          foregroundColor: c.inkInverse,
          disabledBackgroundColor: c.border,
          disabledForegroundColor: c.inkMuted,
          minimumSize: minButtonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          backgroundColor: c.surface,
          side: BorderSide(color: c.border),
          minimumSize: minButtonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.primary,
          minimumSize: minButtonSize,
          padding: buttonPadding,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        labelStyle: text.bodySm.copyWith(color: c.inkMuted),
        floatingLabelStyle: text.bodySm.copyWith(color: c.primary),
        hintStyle: text.body.copyWith(color: c.inkMuted),
        helperStyle: text.caption.copyWith(color: c.inkMuted),
        errorStyle: text.caption.copyWith(color: c.danger),
        border: inputBorder(c.border),
        enabledBorder: inputBorder(c.border),
        disabledBorder: inputBorder(c.border),
        focusedBorder: inputBorder(c.primary, 2),
        errorBorder: inputBorder(c.danger),
        focusedErrorBorder: inputBorder(c.danger, 2),
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardAll,
          side: BorderSide(color: c.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 1),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: c.surfaceRaised,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
        showDragHandle: true,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: c.surfaceRaised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sheet)),
        ),
        titleTextStyle: text.titleSm,
        contentTextStyle: text.body,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: text.bodySm.copyWith(color: c.inkInverse),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.inputAll),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        indicatorColor: c.primarySoft,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelMedium),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: c.surface,
        indicatorColor: c.primarySoft,
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: c.primary,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: c.inkMuted,
        ),
      ),
    );
  }
}
