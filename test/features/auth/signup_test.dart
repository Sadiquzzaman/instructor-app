import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/features/auth/data/signup_validation.dart';
import 'package:instructor_app/features/auth/screens/forgot_password_screen.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/auth/screens/signup_choice_screen.dart';
import 'package:instructor_app/features/auth/screens/verify_code_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

const _phone = '01100000001';
const _strong = 'Strong#Pass1';

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

Future<void> _fillPerson(WidgetTester tester) async {
  await _type(tester, 'signup-name', 'Test Person');
  await _type(tester, 'signup-phone', _phone);
  await _type(tester, 'signup-email', ' Test.Person@Example.com ');
  await _type(tester, 'signup-password', _strong);
  await _type(tester, 'signup-confirm', _strong);
  await _tap(tester, find.byKey(const Key('signup-terms')));
}

void main() {
  group('SignUpValidation (the web\'s rules and wording)', () {
    final l10n = AppLocalizationsEn();

    test('password complexity, in the web\'s order', () {
      String? v(String p) => SignUpValidation.passwordComplexity(p, l10n);
      expect(v(''), 'Please enter a password');
      expect(v('Ab1#'), 'Password must be at least 8 characters.');
      expect(v('abcdefg1#'), contains('uppercase'));
      expect(v('ABCDEFG1#'), contains('lowercase'));
      expect(v('Abcdefgh#'), contains('number'));
      expect(v('Abcdefgh1'), contains('special'));
      expect(v(_strong), isNull);
      expect(
        SignUpValidation.passwordComplexity('', l10n, field: 'newPassword'),
        'Please enter a new password',
      );
    });

    test('sign-up: one problem at a time, in order', () {
      Map<String, String> v(SignUpForm f, {String? org}) =>
          SignUpValidation.signUp(f, l10n, organizationName: org);
      const ok = SignUpForm(
        fullName: 'A',
        phone: _phone,
        email: 'a@b.co',
        password: _strong,
        confirmPassword: _strong,
        agreed: true,
      );
      expect(v(ok), isEmpty);
      expect(v(ok, org: ' ').keys, ['organization_name']);
      expect(
        v(
          const SignUpForm(
            fullName: '',
            phone: '',
            email: '',
            password: '',
            confirmPassword: '',
            agreed: false,
          ),
        ).keys,
        ['full_name'],
      );
      expect(
        v(
          const SignUpForm(
            fullName: 'A',
            phone: '0110000000',
            email: 'a@b.co',
            password: _strong,
            confirmPassword: _strong,
            agreed: true,
          ),
        ),
        {'phone': 'Please enter a valid 11-digit phone number'},
      );
      expect(
        v(
          const SignUpForm(
            fullName: 'A',
            phone: _phone,
            email: 'a@b.co',
            password: _strong,
            confirmPassword: 'Other#Pass1',
            agreed: true,
          ),
        ),
        {'confirm_password': 'Password and Confirm password do not match'},
      );
      expect(
        v(
          const SignUpForm(
            fullName: 'A',
            phone: _phone,
            email: 'a@b.co',
            password: _strong,
            confirmPassword: _strong,
            agreed: false,
          ),
        ).keys,
        ['terms'],
      );
    });

    test('reset and masking', () {
      expect(SignUpValidation.reset(_strong, '', l10n).keys, [
        'confirm_password',
      ]);
      expect(SignUpValidation.reset(_strong, _strong, l10n), isEmpty);
      expect(SignUpValidation.mask('01100000001'), '011*****001');
      expect(SignUpValidation.mask('abc'), 'abc');
    });
  });

  testWidgets('login links to sign-up and forgot password', (tester) async {
    await pumpInstructorApp(tester);
    await _tap(tester, find.text('Sign Up'));
    expect(find.byType(SignUpChoiceScreen), findsOneWidget);
    await _tap(tester, find.byType(BackButton));
    await _tap(tester, find.text('Forgot password?'));
    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('student: register, code, back to login with the message', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('POST /auth/register', (_) => ok({'otpSent': true}))
      ..on(
        'POST /auth/register/verify-otp',
        (_) => ok({'data': <String, Object?>{}}),
      );
    await pumpInstructorApp(tester, api: api);
    await _tap(tester, find.text('Sign Up'));
    await _tap(tester, find.text('Student'));
    await _fillPerson(tester);
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign Up'));

    expect(api.to('POST /auth/register').single.body, {
      'full_name': 'Test Person',
      'phone': _phone,
      'email': 'test.person@example.com',
      'password': _strong,
      'confirm_password': _strong,
      'role': 'STUDENT',
      'request_teacher': false,
    });
    expect(
      api.to('POST /auth/register').single.headers['Authorization'],
      isNull,
    );
    expect(find.byType(VerifyCodeScreen), findsOneWidget);
    expect(
      find.textContaining('011*****001', findRichText: true),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('otp')), '123456');
    await _tap(tester, find.text('Verify & Continue'));

    expect(api.to('POST /auth/register/verify-otp').single.body, {
      'phone': _phone,
      'otp': '123456',
    });
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('OTP verified successfully.'), findsOneWidget);
  });

  testWidgets('teacher: request_teacher with IELTS, pending message', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('POST /auth/register', (_) => ok(null))
      ..on('POST /auth/register/verify-otp', (_) => ok(null));
    await pumpInstructorApp(tester, api: api);
    await _tap(tester, find.text('Sign Up'));
    await _tap(tester, find.text('Sign Up as Teacher'));
    await _tap(tester, find.text('IELTS'));
    await _fillPerson(tester);
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign Up'));

    final body = api.to('POST /auth/register').single.body! as Map;
    expect(body['request_teacher'], isTrue);
    expect(body['workspace_type'], 'IELTS');
    expect(body['role'], 'STUDENT');

    await tester.enterText(find.byKey(const Key('otp')), '654321');
    await _tap(tester, find.text('Verify & Continue'));
    expect(find.textContaining('pending admin approval'), findsOneWidget);
  });

  testWidgets('organisation: IELTS centre, the organisation number at login', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('POST /auth/register/organization', (_) => ok(null))
      ..on(
        'POST /auth/register/verify-otp',
        (_) => ok({
          'data': {
            'organization': {'organization_number': 100042},
          },
        }),
      );
    await pumpInstructorApp(tester, api: api);
    await _tap(tester, find.text('Sign Up'));
    await _tap(tester, find.text('Organization'));
    await _tap(tester, find.text('IELTS centre'));
    await _type(tester, 'signup-organization', 'Bright Test Centre');
    await _fillPerson(tester);
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign Up'));

    final body = api.to('POST /auth/register/organization').single.body! as Map;
    expect(body['kind'], 'IELTS_CENTRE');
    expect(body['organization_name'], 'Bright Test Centre');
    expect(body.containsKey('role'), isFalse);

    await tester.enterText(find.byKey(const Key('otp')), '111111');
    await _tap(tester, find.text('Verify & Continue'));
    expect(find.textContaining('100042'), findsOneWidget);
  });

  testWidgets(
    'a refused sign-up shows the app\'s sentence, not the server\'s',
    (tester) async {
      final api = FakeApi()
        ..on(
          'POST /auth/register',
          (_) => apiError(
            400,
            message: 'Phone number already registered and verified',
          ),
        );
      await pumpInstructorApp(tester, api: api);
      await _tap(tester, find.text('Sign Up'));
      await _tap(tester, find.text('Student'));
      await _fillPerson(tester);
      await _tap(tester, find.widgetWithText(FilledButton, 'Sign Up'));
      expect(
        find.text('Sign up failed. Check your details and try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('already registered'), findsNothing);
    },
  );

  testWidgets('code screen: incomplete code, wrong code, resend after 60 s', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('POST /auth/register', (_) => ok(null))
      ..on(
        'POST /auth/register/verify-otp',
        (_) => apiError(400, message: 'Invalid OTP. Please try again.'),
      );
    await pumpInstructorApp(tester, api: api);
    await _tap(tester, find.text('Sign Up'));
    await _tap(tester, find.text('Student'));
    await _fillPerson(tester);
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign Up'));

    await tester.enterText(find.byKey(const Key('otp')), '12');
    await _tap(tester, find.text('Verify & Continue'));
    expect(find.text('Please enter the complete OTP code'), findsOneWidget);
    expect(api.to('POST /auth/register/verify-otp'), isEmpty);

    await tester.enterText(find.byKey(const Key('otp')), '123456');
    await _tap(tester, find.text('Verify & Continue'));
    expect(
      find.text('OTP verification failed. Please try again.'),
      findsOneWidget,
    );

    expect(find.textContaining('Resend available in'), findsOneWidget);
    expect(find.text('Resend code'), findsNothing);
    await tester.pump(const Duration(seconds: 61));
    await _tap(tester, find.text('Resend code'));
    final sent = api.to('POST /auth/register');
    expect(sent, hasLength(2));
    expect(sent[1].body, sent[0].body);
  });

  testWidgets('forgot password: code by SMS, check it, set a new password', (
    tester,
  ) async {
    final api = FakeApi()
      ..on(
        'POST /auth/forgot-password',
        (_) => ok({
          'data': {'channel': 'sms', 'maskedPhone': '011*****001'},
        }),
      )
      ..on('POST /auth/reset-password/verify-otp', (_) => ok(null))
      ..on('POST /auth/reset-password', (_) => ok(null));
    await pumpInstructorApp(tester, api: api);
    await _tap(tester, find.text('Forgot password?'));

    await _type(tester, 'forgot-identifier', ' $_phone ');
    await _tap(tester, find.text('Send code'));
    expect(api.to('POST /auth/forgot-password').single.body, {
      'identifier': _phone,
    });
    expect(
      find.textContaining('011*****001', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('SMS inbox', findRichText: true),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('otp')), '222222');
    await _tap(tester, find.text('Verify & Continue'));
    expect(api.to('POST /auth/reset-password/verify-otp').single.body, {
      'identifier': _phone,
      'otp': '222222',
    });

    await _type(tester, 'forgot-password', _strong);
    await _type(tester, 'forgot-confirm', _strong);
    await _tap(tester, find.text('Reset password'));
    expect(api.to('POST /auth/reset-password').single.body, {
      'identifier': _phone,
      'otp': '222222',
      'password': _strong,
      'confirm_password': _strong,
    });
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(
      find.text('Your password has been reset. Please login.'),
      findsOneWidget,
    );
  });

  testWidgets('forgot password: a refused code says so', (tester) async {
    final api = FakeApi()
      ..on(
        'POST /auth/forgot-password',
        (_) => ok({
          'data': {'channel': 'email', 'maskedEmail': 'tes***com'},
        }),
      )
      ..on('POST /auth/reset-password/verify-otp', (_) => apiError(400));
    await pumpInstructorApp(tester, api: api);
    await _tap(tester, find.text('Forgot password?'));
    await _type(tester, 'forgot-identifier', 'Test@Example.com');
    await _tap(tester, find.text('Send code'));
    expect(api.to('POST /auth/forgot-password').single.body, {
      'identifier': 'test@example.com',
    });
    await tester.enterText(find.byKey(const Key('otp')), '333333');
    await _tap(tester, find.text('Verify & Continue'));
    expect(
      find.text(
        'Could not reset the password. Check your details and the code, and try again.',
      ),
      findsOneWidget,
    );
  });
}
