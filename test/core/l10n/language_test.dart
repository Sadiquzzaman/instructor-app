import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/theme/app_text.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('a saved choice wins over the phone\'s language', (tester) async {
    final container = await pumpInstructorApp(
      tester,
      prefs: {LanguageController.prefsKey: 'bn'},
    );
    expect(container.read(languageProvider).languageCode, 'bn');
    // In Bangla the switch offers English.
    expect(find.text('English'), findsOneWidget);
  });

  testWidgets('switching to Bangla changes the text, the font and is saved', (
    tester,
  ) async {
    final container = await pumpInstructorApp(
      tester,
      prefs: {LanguageController.prefsKey: 'en'},
    );
    expect(find.text('বাংলা'), findsOneWidget);
    expect(
      Theme.of(tester.element(find.text('বাংলা')))
          .textTheme
          .bodyLarge!
          .fontFamily,
      AppFonts.latin,
    );

    await tester.tap(find.text('বাংলা'));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(container.read(languageProvider).languageCode, 'bn');
    expect(
      Theme.of(tester.element(find.text('English')))
          .textTheme
          .bodyLarge!
          .fontFamily,
      AppFonts.bangla,
    );
    final prefs = container.read(sharedPreferencesProvider);
    expect(prefs.getString(LanguageController.prefsKey), 'bn');
  });

  testWidgets('the switch is announced in the current language', (
    tester,
  ) async {
    await pumpInstructorApp(tester, prefs: {LanguageController.prefsKey: 'en'});
    expect(find.bySemanticsLabel('Switch language to Bangla'), findsOneWidget);
  });
}
