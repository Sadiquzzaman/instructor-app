import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/features/auth/data/auth_error_text.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

// The error codes of tes-taker#345: the app says each in its own words, in
// the person's language, and never shows the server's English message.

const _phone = '01100000001';
const _strong = 'Strong#Pass1';
const _codes = [
  'PHONE_ALREADY_REGISTERED',
  'EMAIL_ALREADY_REGISTERED',
  'OTP_SEND_FAILED',
  'ACCOUNT_NOT_FOUND',
  'PHONE_ALREADY_VERIFIED',
  'OTP_INVALID',
  'OTP_EXPIRED',
  'OTP_LOCKED',
  'INVALID_CREDENTIALS',
  'ACCOUNT_NOT_VERIFIED',
  'ACCOUNT_DISABLED',
];

final _en = AppLocalizationsEn();

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

Future<void> _type(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(_field(key));
  await tester.enterText(_field(key), text);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _signUp(WidgetTester tester, FakeApi api) async {
  await pumpInstructorApp(tester, api: api);
  await _tap(tester, find.text('Sign Up'));
  await _tap(tester, find.text('Student'));
  await _type(tester, 'signup-name', 'Test Person');
  await _type(tester, 'signup-phone', _phone);
  await _type(tester, 'signup-email', 'test.person@example.com');
  await _type(tester, 'signup-password', _strong);
  await _type(tester, 'signup-confirm', _strong);
  await _tap(tester, find.byKey(const Key('signup-terms')));
  await _tap(tester, find.widgetWithText(FilledButton, 'Sign Up'));
}

Future<void> _login(
  WidgetTester tester,
  FakeReply reply, {
  String? lang,
}) async {
  final api = FakeApi()..on('POST /auth/login', (_) => reply);
  await pumpInstructorApp(tester, api: api, prefs: {'language': ?lang});
  await _type(tester, 'login-identifier', _phone);
  await _type(tester, 'login-password', 'a-password');
  await _tap(tester, find.byType(FilledButton));
}

void main() {
  test('every code has its own sentence, in English and Bangla', () {
    final bn = AppLocalizationsBn();
    for (final language in [_en, bn]) {
      final texts = {
        for (final code in _codes)
          authErrorText(
            ApiException(kind: ApiErrorKind.badRequest, code: code),
            language,
          ),
      };
      expect(texts, isNot(contains(null)));
      expect(texts, hasLength(_codes.length));
    }
    expect(
      authErrorText(
        const ApiException(kind: ApiErrorKind.forbidden, code: 'OTHER'),
        _en,
      ),
      isNull,
    );
    expect(
      authErrorText(const ApiException(kind: ApiErrorKind.network), _en),
      isNull,
    );
  });

  group('sign-in', () {
    testWidgets('not verified yet: how to get a new code', (tester) async {
      await _login(
        tester,
        apiError(
          401,
          code: 'ACCOUNT_NOT_VERIFIED',
          message: 'Please verify your phone number with OTP before logging in',
        ),
      );
      expect(find.text(_en.appLoginNotVerified), findsOneWidget);
      expect(find.textContaining('before logging in'), findsNothing);
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    testWidgets('disabled account, in Bangla', (tester) async {
      await _login(tester, apiError(401, code: 'ACCOUNT_DISABLED'), lang: 'bn');
      expect(find.text(AppLocalizationsBn().appLoginDisabled), findsOneWidget);
    });

    testWidgets('wrong password with its code', (tester) async {
      await _login(tester, apiError(401, code: 'INVALID_CREDENTIALS'));
      expect(find.text(_en.appLoginInvalid), findsOneWidget);
    });
  });

  group('sign-up', () {
    testWidgets('a phone with an account: said under the phone', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(
          'POST /auth/register',
          (_) => apiError(400, code: 'PHONE_ALREADY_REGISTERED'),
        );
      await _signUp(tester, api);
      expect(
        find.descendant(
          of: find.byKey(const Key('signup-phone')),
          matching: find.text(_en.appPhoneTaken),
        ),
        findsOneWidget,
      );
      expect(find.text(_en.appSignupFailed), findsNothing);
    });

    testWidgets('an email with an account: said under the email', (
      tester,
    ) async {
      final api = FakeApi()
        ..on(
          'POST /auth/register',
          (_) => apiError(400, code: 'EMAIL_ALREADY_REGISTERED'),
        );
      await _signUp(tester, api);
      expect(
        find.descendant(
          of: find.byKey(const Key('signup-email')),
          matching: find.text(_en.appEmailTaken),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the code could not be sent', (tester) async {
      final api = FakeApi()
        ..on(
          'POST /auth/register',
          (_) => apiError(400, code: 'OTP_SEND_FAILED'),
        );
      await _signUp(tester, api);
      expect(find.text(_en.appCodeNotSent), findsOneWidget);
    });
  });

  group('the sign-up code', () {
    Future<FakeApi> codeScreen(WidgetTester tester, FakeReply verify) async {
      var registered = 0;
      final api = FakeApi()
        ..on(
          'POST /auth/register',
          // The first sends the code; a resend is over the hourly limit.
          (_) => registered++ == 0
              ? ok(null)
              : apiError(400, code: 'OTP_SEND_FAILED'),
        )
        ..on('POST /auth/register/verify-otp', (_) => verify);
      await _signUp(tester, api);
      return api;
    }

    Future<void> verify(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('otp')), '123456');
      await _tap(tester, find.text('Verify & Continue'));
    }

    testWidgets('a wrong code', (tester) async {
      await codeScreen(tester, apiError(400, code: 'OTP_INVALID'));
      await verify(tester);
      expect(find.text(_en.appCodeWrong), findsOneWidget);
    });

    testWidgets('expired', (tester) async {
      await codeScreen(tester, apiError(400, code: 'OTP_EXPIRED'));
      await verify(tester);
      expect(find.text(_en.appCodeExpired), findsOneWidget);
    });

    testWidgets('locked after too many wrong codes (429)', (tester) async {
      await codeScreen(
        tester,
        apiError(
          429,
          code: 'OTP_LOCKED',
          message: 'Too many wrong codes. Please try again in 15 minutes.',
        ),
      );
      await verify(tester);
      expect(find.text(_en.appCodeLocked), findsOneWidget);
    });

    testWidgets('already verified', (tester) async {
      await codeScreen(tester, apiError(400, code: 'PHONE_ALREADY_VERIFIED'));
      await verify(tester);
      expect(find.text(_en.appAlreadyVerified), findsOneWidget);
    });

    testWidgets('a resend over the limit says so', (tester) async {
      await codeScreen(tester, ok(null));
      await tester.pump(const Duration(seconds: 61));
      await _tap(tester, find.text('Resend code'));
      expect(find.text(_en.appCodeNotSent), findsOneWidget);
    });
  });

  group('forgot password', () {
    testWidgets('no account with that phone or email', (tester) async {
      final api = FakeApi()
        ..on(
          'POST /auth/forgot-password',
          (_) => apiError(404, code: 'ACCOUNT_NOT_FOUND'),
        );
      await pumpInstructorApp(tester, api: api);
      await _tap(tester, find.text('Forgot password?'));
      await _type(tester, 'forgot-identifier', _phone);
      await _tap(tester, find.text('Send code'));
      expect(find.text(_en.appAccountNotFound), findsOneWidget);
    });

    testWidgets('a wrong code', (tester) async {
      final api = FakeApi()
        ..on(
          'POST /auth/forgot-password',
          (_) => ok({
            'data': {'channel': 'sms', 'maskedPhone': '011*****001'},
          }),
        )
        ..on(
          'POST /auth/reset-password/verify-otp',
          (_) => apiError(400, code: 'OTP_INVALID'),
        );
      await pumpInstructorApp(tester, api: api);
      await _tap(tester, find.text('Forgot password?'));
      await _type(tester, 'forgot-identifier', _phone);
      await _tap(tester, find.text('Send code'));
      await tester.enterText(find.byKey(const Key('otp')), '333333');
      await _tap(tester, find.text('Verify & Continue'));
      expect(find.text(_en.appCodeWrong), findsOneWidget);
    });
  });
}
