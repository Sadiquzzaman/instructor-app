import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

import '../test/helpers/fake_api.dart';
import '../test/helpers/pump_app.dart';

/// Sign-in and sign-out on a real device (CLAUDE.md: integration tests for
/// sign-in), against the in-process fake API so it never needs the network
/// or a password. Run: `flutter test integration_test -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextField),
  );

  testWidgets('sign in, see home, sign out, back at login', (tester) async {
    final api = FakeApi()
      ..on('POST /auth/login', (r) {
        final body = r.body! as Map;
        return body['phone'] == '01100000001' && body['password'] == 'right-one'
            ? ok(sessionPayload())
            : apiError(401, message: 'Invalid credentials');
      })
      ..on('POST /auth/logout', (_) => ok(null));
    await pumpInstructorApp(tester, api: api, prefs: {'language': 'en'});
    expect(find.byType(LoginScreen), findsOneWidget);

    // A wrong password first.
    await tester.enterText(field('login-identifier'), '01100000001');
    await tester.enterText(field('login-password'), 'wrong-one');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('The email, phone number or password is not right.'),
      findsOneWidget,
    );

    // Then the right one.
    await tester.enterText(field('login-password'), 'right-one');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(PlaceholderHome), findsOneWidget);
    expect(find.text('Test Student'), findsOneWidget);
    expect(find.text('Demo School'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(api.to('POST /auth/logout'), hasLength(1));
  });
}
