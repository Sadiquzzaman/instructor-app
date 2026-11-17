import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

import 'helpers/pump_app.dart';

void main() {
  testWidgets('the app starts on the placeholder home with the brand name', (
    tester,
  ) async {
    await pumpInstructorApp(tester);

    expect(find.byType(PlaceholderHome), findsOneWidget);
    expect(find.text(AppConfig.appName), findsOneWidget);
  });

  testWidgets('the placeholder home fits a 360 px wide phone', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpInstructorApp(tester, prefs: {'language': 'bn'});

    expect(tester.takeException(), isNull);
    expect(find.text(AppConfig.appName), findsOneWidget);
  });
}
