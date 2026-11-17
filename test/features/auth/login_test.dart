import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/features/auth/data/login_validation.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  group('LoginValidation (the web\'s rules and wording)', () {
    final l10n = AppLocalizationsEn();

    test('identifier', () {
      String? v(String s) => LoginValidation.identifier(s, l10n);
      expect(v('  '), 'Please enter your email or phone number');
      expect(v('0171234567'), 'Phone number must be 11 digits');
      expect(v('02123456789'), 'Invalid Bangladeshi phone number');
      expect(v('a@b'), 'Invalid email address');
      expect(v('hello'), 'Enter a valid email or phone number');
      expect(v('01712345678'), isNull);
      expect(v(' Demo@Example.com '), isNull);
    });

    test('password', () {
      expect(LoginValidation.password('', l10n), 'Please enter a password');
      expect(
        LoginValidation.password('short', l10n),
        'Password must be at least 8 characters.',
      );
      expect(LoginValidation.password('longenough', l10n), isNull);
    });

    test('email (lower-cased) or phone in the body', () {
      expect(LoginValidation.identifierField(' Demo@Example.com '), {
        'email': 'demo@example.com',
      });
      expect(LoginValidation.identifierField('01712345678'), {
        'phone': '01712345678',
      });
    });
  });

  // AppTextField wraps a TextField; enterText needs the TextField itself.
  Finder field(String key) => find.descendant(
    of: find.byKey(Key(key)),
    matching: find.byType(TextField),
  );

  testWidgets('signs in, sends the device, stores the session, goes home', (
    tester,
  ) async {
    final api = FakeApi()..on('POST /auth/login', (_) => ok(sessionPayload()));
    final container = await pumpInstructorApp(tester, api: api);

    await tester.enterText(
      field('login-identifier'),
      ' Demo.Student1@yopmail.com ',
    );
    await tester.enterText(field('login-password'), 'a-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    final body = api.to('POST /auth/login').single.body! as Map;
    expect(body['email'], 'demo.student1@yopmail.com');
    expect(body['password'], 'a-password');
    expect(body['device'], {
      'platform': 'ANDROID',
      'name': 'Google Pixel 8',
      'app_version': '0.1.0',
    });
    expect(api.to('POST /auth/login').single.headers['Authorization'], isNull);
    expect(
      container.read(sessionHolderProvider).current!.organizationId,
      'org-1',
    );
    expect(find.byType(PlaceholderHome), findsOneWidget);
  });

  testWidgets('a phone number is sent as phone', (tester) async {
    final api = FakeApi()..on('POST /auth/login', (_) => ok(sessionPayload()));
    await pumpInstructorApp(tester, api: api);
    await tester.enterText(field('login-identifier'), '01712345678');
    await tester.enterText(field('login-password'), 'a-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    final body = api.to('POST /auth/login').single.body! as Map;
    expect(body['phone'], '01712345678');
    expect(body.containsKey('email'), isFalse);
  });

  testWidgets('invalid input is caught before sending', (tester) async {
    final api = FakeApi();
    await pumpInstructorApp(tester, api: api);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('Please enter your email or phone number'),
      findsOneWidget,
    );
    expect(api.to('POST /auth/login'), isEmpty);
  });

  testWidgets('a wrong password shows the app\'s sentence, in Bangla too', (
    tester,
  ) async {
    final api = FakeApi()
      ..on(
        'POST /auth/login',
        (_) => apiError(401, message: 'Invalid credentials'),
      );
    await pumpInstructorApp(tester, api: api, prefs: {'language': 'bn'});
    await tester.enterText(field('login-identifier'), '01712345678');
    await tester.enterText(field('login-password'), 'a-password');
    await tester.tap(find.text('সাইন ইন'));
    await tester.pumpAndSettle();
    expect(
      find.text('ইমেইল, ফোন নম্বর বা পাসওয়ার্ড সঠিক নয়।'),
      findsOneWidget,
    );
    expect(find.byType(LoginScreen), findsOneWidget);
    // The server's English message is never shown.
    expect(find.text('Invalid credentials'), findsNothing);
  });

  testWidgets('no connection says so', (tester) async {
    final api = FakeApi()
      ..on(
        'POST /auth/login',
        (r) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: '/auth/login'),
          reason: 'offline',
        ),
      );
    await pumpInstructorApp(tester, api: api);
    await tester.enterText(field('login-identifier'), '01712345678');
    await tester.enterText(field('login-password'), 'a-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(
      find.text('No internet connection. Check it and try again.'),
      findsOneWidget,
    );
  });

  testWidgets('the account\'s language is applied after sign-in', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('POST /auth/login', (_) => ok(sessionPayload()..['locale'] = 'bn'));
    final container = await pumpInstructorApp(
      tester,
      api: api,
      prefs: {LanguageController.prefsKey: 'en'},
    );
    await tester.enterText(field('login-identifier'), '01712345678');
    await tester.enterText(field('login-password'), 'a-password');
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(container.read(languageProvider).languageCode, 'bn');
  });

  testWidgets('sign out ends the device session and returns to login', (
    tester,
  ) async {
    final api = FakeApi()..on('POST /auth/logout', (_) => ok(null));
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
    );
    expect(find.byType(PlaceholderHome), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(api.to('POST /auth/logout').single.body, {
      'refreshToken': 'refresh-1',
    });
    expect(container.read(sessionHolderProvider).current, isNull);
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('sign out works even when the server cannot be reached', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('POST /auth/logout', (_) => apiError(502, message: 'Bad Gateway'));
    await pumpInstructorApp(tester, api: api, session: testSession());
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('a refused refresh sends the person back to login', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /auth/profile', (_) => apiError(401))
      ..on('POST /auth/refresh', (_) => apiError(401));
    final container = await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
    );
    // A direct call outside a widget: run it on real time, not the test's
    // simulated clock (Dio waits on real timers).
    await tester.runAsync(
      () => expectLater(
        container.read(apiClientProvider).get('/auth/profile'),
        throwsA(anything),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });
}
