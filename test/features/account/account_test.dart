import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/language_switcher.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/features/account/data/account_repository.dart';
import 'package:instructor_app/features/account/data/change_password_validation.dart';
import 'package:instructor_app/features/account/screens/account_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

const _strong = 'Fresh#Pass2026';

Map<String, Object?> _device(
  String id, {
  String platform = 'WEB',
  bool current = false,
  String? name,
}) => {
  'id': id,
  'platform': platform,
  'device_name': name,
  'app_version': platform == 'WEB' ? null : '0.1.0',
  'last_used_at': '2026-11-17T06:30:00.000Z',
  'created_at': '2026-11-01T06:30:00.000Z',
  'current': current,
};

List<Map<String, Object?>> _prefs({bool absentSms = false}) => [
  {
    'event_type': 'attendance.absent',
    'channels': ['IN_APP', if (absentSms) 'SMS'],
    'allowed': ['IN_APP', 'SMS', 'EMAIL'],
  },
  {
    'event_type': 'exam.scheduled',
    'channels': ['IN_APP', 'EMAIL'],
    'allowed': ['IN_APP', 'EMAIL'],
  },
];

FakeApi _api({List<Map<String, Object?>>? devices}) => FakeApi()
  ..on('GET /me/notification-prefs', (_) => ok(_prefs()))
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on(
    'GET /auth/profile',
    (_) => ok({
      'full_name': 'Test Student',
      'role': 'STUDENT',
      'email': null,
      'phone': '01100000000',
      'is_verified': true,
      'created_at': '2026-01-05T10:00:00.000Z',
    }),
  )
  ..on(
    'GET /auth/sessions',
    (_) => ok(
      devices ??
          [
            _device('s1', platform: 'ANDROID', current: true, name: 'Pixel'),
            _device('s2', name: 'Chrome on Windows'),
            _device('s3', platform: 'IOS'),
          ],
    ),
  );

Future<void> _openAccount(WidgetTester tester, ProviderContainer c) async {
  c.read(routerProvider).go(AppRoutes.account);
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find
        .descendant(
          of: find.byType(AccountScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  final l10n = AppLocalizationsEn();

  test('change password checks one thing at a time, in the web order', () {
    Map<String, String> check(String c, String n, String f) =>
        validateChangePassword(current: c, next: n, confirm: f, l10n: l10n);
    expect(check('', '', '').keys, ['current']);
    expect(check('old', 'short', '').keys, ['new']);
    expect(
      check(_strong, _strong, _strong)['new'],
      l10n.validationNewPasswordSame,
    );
    expect(check('old', _strong, '').keys, ['confirm']);
    expect(
      check('old', _strong, 'Other#Pass2026')['confirm'],
      l10n.validationNewPasswordMismatch,
    );
    expect(check('old', _strong, _strong), isEmpty);
  });

  test('a device reads the API answer', () {
    final d = SignedInDevice.fromJson(_device('s1', platform: 'IOS'))!;
    expect(d.platform, 'IOS');
    expect(d.appVersion, '0.1.0');
    expect(d.lastUsedAt, DateTime.utc(2026, 11, 17, 6, 30));
    expect(SignedInDevice.fromJson({'platform': 'IOS'}), isNull);
    expect(AppRoutes.isAppPage('/account'), isTrue);
  });

  testWidgets('the account page shows the profile and the devices', (
    tester,
  ) async {
    final c = await pumpInstructorApp(
      tester,
      api: _api(),
      session: testSession(),
    );
    await _openAccount(tester, c);
    expect(find.text('Test Student'), findsWidgets);
    expect(find.text(l10n.accountRolesSTUDENT), findsOneWidget);
    expect(find.text(l10n.accountNotProvided), findsOneWidget); // no email
    expect(find.text(l10n.accountVerified), findsOneWidget);

    await _scrollTo(tester, find.byKey(const Key('device-s3')));
    expect(find.text(l10n.accountDevicesThisDevice), findsOneWidget);
    expect(find.text('Chrome on Windows'), findsOneWidget);
    // No name: the platform stands in.
    expect(find.text(l10n.accountDevicesPlatformIOS), findsWidgets);
    // This device cannot sign itself out from here.
    expect(
      find.descendant(
        of: find.byKey(const Key('device-s1')),
        matching: find.text(l10n.accountDevicesSignOut),
      ),
      findsNothing,
    );
  });

  testWidgets('signing out one device asks first', (tester) async {
    final api = _api()..on('DELETE /auth/sessions/s2', (_) => ok({'id': 's2'}));
    final c = await pumpInstructorApp(tester, api: api, session: testSession());
    await _openAccount(tester, c);
    final button = find.descendant(
      of: find.byKey(const Key('device-s2')),
      matching: find.text(l10n.accountDevicesSignOut),
    );
    await _scrollTo(tester, button);

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.accountDevicesOneConfirmTitle('Chrome on Windows')),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.uiCancel));
    await tester.pumpAndSettle();
    expect(api.to('DELETE /auth/sessions/s2'), isEmpty);

    final before = api.to('GET /auth/sessions').length;
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.accountDevicesSignOut),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.to('DELETE /auth/sessions/s2'), hasLength(1));
    expect(find.text(l10n.accountDevicesOneDone), findsOneWidget);
    expect(api.to('GET /auth/sessions').length, before + 1); // reloaded
  });

  testWidgets('signing out the others says how many', (tester) async {
    final api = _api()
      ..on('POST /auth/sessions/revoke-others', (_) => ok({'signed_out': 2}));
    final c = await pumpInstructorApp(tester, api: api, session: testSession());
    await _openAccount(tester, c);
    final button = find.text(l10n.accountDevicesSignOutOthers);
    await _scrollTo(tester, button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text(l10n.accountDevicesOthersConfirmTitle(2)), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(l10n.accountDevicesSignOut),
      ),
    );
    await tester.pumpAndSettle();
    expect(api.to('POST /auth/sessions/revoke-others'), hasLength(1));
    expect(find.text(l10n.accountDevicesOthersDone(2)), findsOneWidget);
  });

  testWidgets('only this device: no "sign out the others"', (tester) async {
    final api = _api(
      devices: [_device('s1', platform: 'ANDROID', current: true)],
    );
    final c = await pumpInstructorApp(tester, api: api, session: testSession());
    await _openAccount(tester, c);
    await _scrollTo(tester, find.text(l10n.accountDevicesOnlyThisOne));
    expect(find.text(l10n.accountDevicesSignOutOthers), findsNothing);
  });

  testWidgets('notifications: each message, SMS or email where allowed', (
    tester,
  ) async {
    final api = _api()
      ..on('PUT /me/notification-prefs', (_) => ok(_prefs(absentSms: true)));
    final c = await pumpInstructorApp(tester, api: api, session: testSession());
    await _openAccount(tester, c);
    await _scrollTo(tester, find.byKey(const Key('pref-exam.scheduled')));
    expect(find.text(l10n.notificationsPrefsTitle), findsOneWidget);
    expect(find.text(l10n.messageLogEventsAttendanceAbsent), findsOneWidget);
    expect(find.text(l10n.messageLogEventsExamScheduled), findsOneWidget);
    // Exams can only add email; SMS is not offered there.
    expect(find.byKey(const Key('pref-exam.scheduled-SMS')), findsNothing);
    expect(find.text(l10n.notificationsPrefsSmsHint), findsOneWidget);

    final sms = find.byKey(const Key('pref-attendance.absent-SMS'));
    await _scrollTo(tester, sms);
    await tester.tap(sms);
    await tester.pumpAndSettle();
    expect(api.to('PUT /me/notification-prefs').single.body, {
      'event_type': 'attendance.absent',
      'channels': ['IN_APP', 'SMS'],
    });
    expect(find.text(l10n.notificationsPrefsSaved), findsOneWidget);
    // The saved answer shows: SMS is now ticked.
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(of: sms, matching: find.byType(Checkbox)),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('notification settings that fail to load say so', (tester) async {
    final api = _api()..on('GET /me/notification-prefs', (_) => apiError(500));
    final c = await pumpInstructorApp(tester, api: api, session: testSession());
    await _openAccount(tester, c);
    await _scrollTo(tester, find.text(l10n.notificationsPrefsLoadFailed));
    expect(find.text(l10n.notificationsPrefsLoadFailed), findsOneWidget);
  });

  testWidgets('devices that fail to load can be retried', (tester) async {
    var fail = true;
    final api = _api()
      ..on(
        'GET /auth/sessions',
        (_) => fail ? apiError(500) : ok([_device('s1', current: true)]),
      );
    final c = await pumpInstructorApp(tester, api: api, session: testSession());
    await _openAccount(tester, c);
    await _scrollTo(tester, find.text(l10n.accountDevicesLoadFailed));
    fail = false;
    await tester.tap(find.text(l10n.uiErrorRetry).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.accountDevicesOnlyThisOne), findsOneWidget);
  });

  group('change password', () {
    Future<(FakeApi, ProviderContainer)> open(
      WidgetTester tester,
      FakeHandler reply,
    ) async {
      final api = _api()..on('POST /auth/change-password', reply);
      final c = await pumpInstructorApp(
        tester,
        api: api,
        session: testSession(),
      );
      await _openAccount(tester, c);
      return (api, c);
    }

    Future<void> fill(WidgetTester tester, String current) async {
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('password-current')),
          matching: find.byType(EditableText),
        ),
        current,
      );
      for (final key in ['new', 'confirm']) {
        await tester.enterText(
          find.descendant(
            of: find.byKey(Key('password-$key')),
            matching: find.byType(EditableText),
          ),
          _strong,
        );
      }
    }

    Future<void> submit(WidgetTester tester) async {
      final button = find.widgetWithText(
        FilledButton,
        l10n.accountChangePasswordSubmit,
      );
      await _scrollTo(tester, button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    testWidgets('an empty form is not sent', (tester) async {
      final (api, _) = await open(tester, (_) => ok(null));
      await submit(tester);
      expect(find.text(l10n.validationCurrentPasswordRequired), findsOneWidget);
      expect(api.to('POST /auth/change-password'), isEmpty);
    });

    testWidgets('success clears the form and says so', (tester) async {
      final (api, _) = await open(tester, (_) => ok(null));
      await _scrollTo(tester, find.byKey(const Key('password-current')));
      await fill(tester, 'Old#Pass2025');
      await submit(tester);
      final sent = api.to('POST /auth/change-password').single.body! as Map;
      expect(sent['current_password'], 'Old#Pass2025');
      expect(sent['new_password'], _strong);
      expect(sent['confirm_password'], _strong);
      expect(find.text(l10n.authChangePasswordDoneDescription), findsOneWidget);
      expect(find.text('Old#Pass2025'), findsNothing);
    });

    testWidgets('a wrong current password (400, no code)', (tester) async {
      final (_, _) = await open(
        tester,
        (_) => apiError(400, message: 'Current password is incorrect'),
      );
      await _scrollTo(tester, find.byKey(const Key('password-current')));
      await fill(tester, 'Wrong#Pass2025');
      await submit(tester);
      expect(find.text(l10n.appChangePasswordFailed), findsOneWidget);
      // Still signed in: a 400 is not an expired session.
      expect(find.byKey(const Key('password-current')), findsOneWidget);
    });

    testWidgets('no connection', (tester) async {
      final (_, _) = await open(
        tester,
        (r) => throw DioException.connectionError(
          requestOptions: RequestOptions(path: r.path),
          reason: 'offline',
        ),
      );
      await _scrollTo(tester, find.byKey(const Key('password-current')));
      await fill(tester, 'Old#Pass2025');
      await submit(tester);
      expect(find.text(l10n.appNoConnection), findsOneWidget);
    });
  });

  group('the language switch', () {
    testWidgets('saves the language on the account when signed in', (
      tester,
    ) async {
      final api = _api()..on('PATCH /user/me/locale', (_) => ok(null));
      await pumpInstructorApp(tester, api: api, session: testSession());
      await tester.tap(find.byType(LanguageSwitcher));
      await tester.pumpAndSettle();
      expect(api.to('PATCH /user/me/locale').single.body, {'locale': 'bn'});
    });

    testWidgets('says so, in the new language, when that fails', (
      tester,
    ) async {
      final api = _api()..on('PATCH /user/me/locale', (_) => apiError(500));
      await pumpInstructorApp(tester, api: api, session: testSession());
      await tester.tap(find.byType(LanguageSwitcher));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'এই ডিভাইসে ভাষা বদলানো হয়েছে, কিন্তু আপনার অ্যাকাউন্টে সংরক্ষণ করা যায়নি।',
        ),
        findsOneWidget,
      );
    });

    testWidgets('signed out: only this phone', (tester) async {
      final api = _api();
      await pumpInstructorApp(tester, api: api);
      await tester.tap(find.byType(LanguageSwitcher));
      await tester.pumpAndSettle();
      expect(api.to('PATCH /user/me/locale'), isEmpty);
    });
  });
}
