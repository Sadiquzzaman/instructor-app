import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

import 'helpers/fake_api.dart';
import 'helpers/pump_app.dart';

void main() {
  testWidgets('signed out, the app opens on the login screen', (tester) async {
    await pumpInstructorApp(tester);

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(PlaceholderHome), findsNothing);
  });

  testWidgets('with a stored session it goes straight home', (tester) async {
    await pumpInstructorApp(tester, session: testSession());

    expect(find.byType(PlaceholderHome), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(find.text(AppConfig.appName), findsOneWidget);
    expect(find.text('Test Student · Demo School'), findsOneWidget);
  });

  testWidgets('the login screen fits a 360 px phone in Bangla', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpInstructorApp(tester, prefs: {'language': 'bn'});

    expect(tester.takeException(), isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
