import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/tokens.g.dart';

/// The bundled font families (pubspec.yaml).
abstract final class AppFonts {
  static const String latin = 'InstrumentSans';
  static const String bangla = 'HindSiliguri';
}

/// The type scale 12 / 14 / 16 / 20 / 24 / 32 (design system §3.2).
///
/// English uses Instrument Sans with a 1.5 line height; Bangla uses Hind
/// Siliguri with 1.7, so Bangla never looks like an afterthought. Each family
/// falls back to the other for mixed text (names, numbers).
@immutable
class AppText {
  const AppText._({
    required this.display,
    required this.title,
    required this.titleSm,
    required this.body,
    required this.bodySm,
    required this.caption,
  });

  factory AppText.forLanguage({required bool bangla, required Color color}) {
    final family = bangla ? AppFonts.bangla : AppFonts.latin;
    final fallback = [bangla ? AppFonts.latin : AppFonts.bangla];
    final height = bangla ? Tokens.lineHeightBangla : Tokens.lineHeightLatin;

    TextStyle style(double size, FontWeight weight) => TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: height,
      fontWeight: weight,
      color: color,
      leadingDistribution: TextLeadingDistribution.even,
    );

    return AppText._(
      display: style(Tokens.textDisplaySize, FontWeight.w700),
      title: style(Tokens.textTitleSize, FontWeight.w600),
      titleSm: style(Tokens.textTitleSmSize, FontWeight.w600),
      body: style(Tokens.textBodySize, FontWeight.w400),
      bodySm: style(Tokens.textBodySmSize, FontWeight.w400),
      caption: style(Tokens.textCaptionSize, FontWeight.w400),
    );
  }

  /// 32: page headlines.
  final TextStyle display;

  /// 24: page titles.
  final TextStyle title;

  /// 20: section and card titles.
  final TextStyle titleSm;

  /// 16: running text and inputs.
  final TextStyle body;

  /// 14: secondary text, table cells, buttons.
  final TextStyle bodySm;

  /// 12: captions, badges.
  final TextStyle caption;

  /// Material's text theme from the scale.
  TextTheme toTextTheme() => TextTheme(
    displayLarge: display,
    displayMedium: display,
    displaySmall: display,
    headlineLarge: display,
    headlineMedium: display,
    headlineSmall: title,
    titleLarge: titleSm,
    titleMedium: body.copyWith(fontWeight: FontWeight.w600),
    titleSmall: bodySm.copyWith(fontWeight: FontWeight.w600),
    bodyLarge: body,
    bodyMedium: bodySm,
    bodySmall: caption,
    labelLarge: bodySm.copyWith(fontWeight: FontWeight.w600),
    labelMedium: caption.copyWith(fontWeight: FontWeight.w500),
    labelSmall: caption,
  );
}
