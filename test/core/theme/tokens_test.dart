import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/theme/tokens.g.dart';

/// Mirrors the web's frontend/design/tokens.test.ts: the generated Dart file
/// matches tool/tokens.json, and every text colour passes WCAG AA.
void main() {
  final json = jsonDecode(
    File('tool/tokens.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final jsonColors = (json['color'] as Map<String, dynamic>).map(
    (k, v) =>
        MapEntry(k, _hex(((v as Map<String, dynamic>)['value']) as String)),
  );

  const dartColors = <String, Color>{
    'primary': Tokens.colorPrimary,
    'primary-hover': Tokens.colorPrimaryHover,
    'primary-soft': Tokens.colorPrimarySoft,
    'ink': Tokens.colorInk,
    'ink-muted': Tokens.colorInkMuted,
    'ink-inverse': Tokens.colorInkInverse,
    'canvas': Tokens.colorCanvas,
    'surface': Tokens.colorSurface,
    'surface-raised': Tokens.colorSurfaceRaised,
    'border': Tokens.colorBorder,
    'success': Tokens.colorSuccess,
    'success-soft': Tokens.colorSuccessSoft,
    'warning': Tokens.colorWarning,
    'warning-soft': Tokens.colorWarningSoft,
    'danger': Tokens.colorDanger,
    'danger-soft': Tokens.colorDangerSoft,
    'info': Tokens.colorInfo,
    'info-soft': Tokens.colorInfoSoft,
  };

  group('tokens.g.dart is in sync with tool/tokens.json', () {
    test('every colour, with the same value', () {
      expect(
        dartColors.keys.toSet(),
        jsonColors.keys.toSet(),
        reason:
            'A colour was added or removed on the web: run '
            '`dart run tool/import_tokens.dart` and add it to AppColors.',
      );
      for (final MapEntry(:key, :value) in jsonColors.entries) {
        expect(dartColors[key]!.toARGB32(), value.toARGB32(), reason: key);
      }
    });

    test('type scale, line heights and radii', () {
      final text = json['text'] as Map<String, dynamic>;
      double size(String k) =>
          _px((text[k] as Map<String, dynamic>)['size'] as String);
      expect(Tokens.textCaptionSize, size('caption'));
      expect(Tokens.textBodySmSize, size('body-sm'));
      expect(Tokens.textBodySize, size('body'));
      expect(Tokens.textTitleSmSize, size('title-sm'));
      expect(Tokens.textTitleSize, size('title'));
      expect(Tokens.textDisplaySize, size('display'));

      final lh = json['lineHeight'] as Map<String, dynamic>;
      expect(
        Tokens.lineHeightLatin,
        double.parse((lh['latin'] as Map<String, dynamic>)['value'] as String),
      );
      expect(
        Tokens.lineHeightBangla,
        double.parse((lh['bangla'] as Map<String, dynamic>)['value'] as String),
      );

      final radius = json['radius'] as Map<String, dynamic>;
      double r(String k) =>
          _px((radius[k] as Map<String, dynamic>)['value'] as String);
      expect(Tokens.radiusInput, r('input'));
      expect(Tokens.radiusCard, r('card'));
      expect(Tokens.radiusSheet, r('sheet'));
    });

    test('fonts: Instrument Sans for English, Hind Siliguri for Bangla', () {
      expect(Tokens.fontSans.first, 'Instrument Sans');
      expect(Tokens.fontBangla.first, 'Hind Siliguri');
    });
  });

  group('every text colour meets WCAG AA (4.5:1) on its backgrounds', () {
    // The same pairs as the web's tokens.test.ts.
    const pairs = <(String, String)>[
      ('ink', 'surface'),
      ('ink', 'canvas'),
      ('ink', 'primary-soft'),
      ('ink-muted', 'surface'),
      ('ink-muted', 'canvas'),
      ('ink-muted', 'primary-soft'),
      ('ink-inverse', 'primary'),
      ('ink-inverse', 'primary-hover'),
      ('ink-inverse', 'danger'),
      ('primary', 'surface'),
      ('primary', 'canvas'),
      ('primary', 'primary-soft'),
      ('success', 'success-soft'),
      ('success', 'surface'),
      ('warning', 'warning-soft'),
      ('warning', 'surface'),
      ('danger', 'danger-soft'),
      ('danger', 'surface'),
      ('info', 'info-soft'),
      ('info', 'surface'),
    ];
    for (final (fg, bg) in pairs) {
      test('$fg on $bg', () {
        expect(
          _contrast(dartColors[fg]!, dartColors[bg]!),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });
}

Color _hex(String hex) => Color(int.parse('FF${hex.substring(1)}', radix: 16));

double _px(String value) => double.parse(value.replaceAll('px', ''));

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  final (light, dark) = la > lb ? (la, lb) : (lb, la);
  return (light + 0.05) / (dark + 0.05);
}
