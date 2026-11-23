import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_text.dart';
import 'package:instructor_app/core/theme/app_theme.dart';
import 'package:instructor_app/core/theme/tokens.g.dart';

void main() {
  group('AppTheme.light', () {
    test('English: Instrument Sans, falling back to Hind Siliguri, 1.5', () {
      final theme = AppTheme.light(bangla: false);
      final body = theme.textTheme.bodyLarge!;
      expect(body.fontFamily, AppFonts.latin);
      expect(body.fontFamilyFallback, [AppFonts.bangla]);
      expect(body.height, Tokens.lineHeightLatin);
      expect(body.fontSize, Tokens.textBodySize);
    });

    test('Bangla: Hind Siliguri, falling back to Instrument Sans, 1.7', () {
      final theme = AppTheme.light(bangla: true);
      final body = theme.textTheme.bodyLarge!;
      expect(body.fontFamily, AppFonts.bangla);
      expect(body.fontFamilyFallback, [AppFonts.latin]);
      expect(body.height, Tokens.lineHeightBangla);
    });

    test('the type scale maps onto Material text styles', () {
      final t = AppTheme.light(bangla: false).textTheme;
      expect(t.headlineMedium!.fontSize, Tokens.textDisplaySize);
      expect(t.headlineSmall!.fontSize, Tokens.textTitleSize);
      expect(t.titleLarge!.fontSize, Tokens.textTitleSmSize);
      expect(t.bodyLarge!.fontSize, Tokens.textBodySize);
      expect(t.bodyMedium!.fontSize, Tokens.textBodySmSize);
      expect(t.bodySmall!.fontSize, Tokens.textCaptionSize);
    });

    test('colours come from the tokens and AppColors is available', () {
      final theme = AppTheme.light(bangla: false);
      expect(theme.colorScheme.primary, Tokens.colorPrimary);
      expect(theme.colorScheme.error, Tokens.colorDanger);
      expect(theme.scaffoldBackgroundColor, Tokens.colorCanvas);
      expect(theme.extension<AppColors>(), AppColors.light);
    });
  });

  test('the bundled font files and their licences exist', () {
    for (final family in ['InstrumentSans', 'HindSiliguri']) {
      for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
        expect(
          File('assets/fonts/$family-$weight.ttf').existsSync(),
          isTrue,
          reason: '$family-$weight.ttf',
        );
      }
      expect(File('assets/fonts/$family-OFL.txt').existsSync(), isTrue);
    }
  });
}
