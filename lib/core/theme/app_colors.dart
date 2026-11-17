import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/tokens.g.dart';

/// The web's colours, named by role (docs/ui/design-system.md §3.2), so a dark
/// palette can be added later without touching screens.
///
/// Read it with `AppColors.of(context)`; never write a colour in a widget.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primary,
    required this.primaryHover,
    required this.primarySoft,
    required this.ink,
    required this.inkMuted,
    required this.inkInverse,
    required this.canvas,
    required this.surface,
    required this.surfaceRaised,
    required this.border,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
  });

  /// The only palette for now (owner's decision: light mode only).
  static const AppColors light = AppColors(
    primary: Tokens.colorPrimary,
    primaryHover: Tokens.colorPrimaryHover,
    primarySoft: Tokens.colorPrimarySoft,
    ink: Tokens.colorInk,
    inkMuted: Tokens.colorInkMuted,
    inkInverse: Tokens.colorInkInverse,
    canvas: Tokens.colorCanvas,
    surface: Tokens.colorSurface,
    surfaceRaised: Tokens.colorSurfaceRaised,
    border: Tokens.colorBorder,
    success: Tokens.colorSuccess,
    successSoft: Tokens.colorSuccessSoft,
    warning: Tokens.colorWarning,
    warningSoft: Tokens.colorWarningSoft,
    danger: Tokens.colorDanger,
    dangerSoft: Tokens.colorDangerSoft,
    info: Tokens.colorInfo,
    infoSoft: Tokens.colorInfoSoft,
  );

  /// Brand green: buttons, links, the selected state.
  final Color primary;
  final Color primaryHover;

  /// Tint for selected rows and badges.
  final Color primarySoft;

  /// Main text.
  final Color ink;

  /// Secondary text.
  final Color inkMuted;

  /// Text on primary or dark fills.
  final Color inkInverse;

  /// Page background (warm off-white).
  final Color canvas;

  /// Cards.
  final Color surface;

  /// Menus and popovers.
  final Color surfaceRaised;
  final Color border;
  final Color success;
  final Color successSoft;

  /// Amber: needs action today.
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({
    Color? primary,
    Color? primaryHover,
    Color? primarySoft,
    Color? ink,
    Color? inkMuted,
    Color? inkInverse,
    Color? canvas,
    Color? surface,
    Color? surfaceRaised,
    Color? border,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
  }) {
    return AppColors(
      primary: primary ?? this.primary,
      primaryHover: primaryHover ?? this.primaryHover,
      primarySoft: primarySoft ?? this.primarySoft,
      ink: ink ?? this.ink,
      inkMuted: inkMuted ?? this.inkMuted,
      inkInverse: inkInverse ?? this.inkInverse,
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      border: border ?? this.border,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      primary: mix(primary, other.primary),
      primaryHover: mix(primaryHover, other.primaryHover),
      primarySoft: mix(primarySoft, other.primarySoft),
      ink: mix(ink, other.ink),
      inkMuted: mix(inkMuted, other.inkMuted),
      inkInverse: mix(inkInverse, other.inkInverse),
      canvas: mix(canvas, other.canvas),
      surface: mix(surface, other.surface),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      border: mix(border, other.border),
      success: mix(success, other.success),
      successSoft: mix(successSoft, other.successSoft),
      warning: mix(warning, other.warning),
      warningSoft: mix(warningSoft, other.warningSoft),
      danger: mix(danger, other.danger),
      dangerSoft: mix(dangerSoft, other.dangerSoft),
      info: mix(info, other.info),
      infoSoft: mix(infoSoft, other.infoSoft),
    );
  }
}
