import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/tokens.g.dart';

/// The 4-point spacing scale: 4, 8, 12, 16, 24, 32, 48.
abstract final class AppSpacing {
  static const double xs = Tokens.spacingBase; // 4
  static const double sm = Tokens.spacingBase * 2; // 8
  static const double md = Tokens.spacingBase * 3; // 12
  static const double lg = Tokens.spacingBase * 4; // 16
  static const double xl = Tokens.spacingBase * 6; // 24
  static const double xxl = Tokens.spacingBase * 8; // 32
  static const double xxxl = Tokens.spacingBase * 12; // 48

  /// Smallest tap target (design system §3.5).
  static const double tapTarget = 44;

  /// Wider than this is a tablet layout (side rail instead of a bottom bar).
  static const double tabletBreakpoint = 600;
}

/// Corner radii: inputs, cards, sheets and dialogs.
abstract final class AppRadius {
  static const double input = Tokens.radiusInput;
  static const double card = Tokens.radiusCard;
  static const double sheet = Tokens.radiusSheet;

  static const BorderRadius inputAll = BorderRadius.all(Radius.circular(input));
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
  static const BorderRadius sheetTop = BorderRadius.vertical(
    top: Radius.circular(sheet),
  );
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

/// The two elevations: cards and overlays.
abstract final class AppShadows {
  static const List<BoxShadow> card = Tokens.shadowCard;
  static const List<BoxShadow> overlay = Tokens.shadowOverlay;
}

/// Motion; off when the phone asks for reduced motion.
abstract final class AppMotion {
  static Duration fast(BuildContext context) =>
      _reduced(context) ? Duration.zero : Tokens.motionFastDuration;

  static Duration sheet(BuildContext context) =>
      _reduced(context) ? Duration.zero : Tokens.motionSheetDuration;

  static const Curve fastCurve = Tokens.motionFastEasing;
  static const Curve sheetCurve = Tokens.motionSheetEasing;

  static bool _reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}
