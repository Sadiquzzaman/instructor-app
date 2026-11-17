import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/cache/read_cache.dart';
import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/attendance/screens/my_attendance_screen.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
final _today = OrgTime.today();

Never _offline(FakeRequest r) => throw DioException.connectionError(
  requestOptions: RequestOptions(path: r.path),
  reason: 'offline',
);

Future<ApiClient> _client(FakeApi api) async {
  final sessions = SessionHolder(MemorySessionStore(testSession()));
  await sessions.restore();
  return ApiClient(
    baseUrl: 'https://api.test/api/v1',
    sessions: sessions,
    device: () async => testDevice,
    onSessionExpired: sessions.clear,
    adapter: api,
  );
}

Map<String, Object?> _myToday(String date) => {
  'date': date,
  'classes': [
    {
      'slot_id': 'online',
      'role': 'STUDENT',
      'section': {'id': 's', 'name': 'A', 'class_name': 'Class 6'},
      'subject': {'id': 'e', 'name': 'English'},
      'class_type': 'ONLINE',
      'mode': 'SELF_CHECK_IN',
      'start_time': '10:00:00',
      'end_time': '10:45:00',
      'state': 'OPEN',
      'needs_location': false,
      'blocked': null,
      'can_check_in': true,
      'record': null,
    },
  ],
};

FakeApi _shell() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /attendance/me/calendar', (_) => ok({'month': '2026-11'}));

void main() {
  group('the cache', () {
    late SharedPreferences prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test(
      'saves each answer; with no connection gives it back, dated',
      () async {
        var online = true;
        final api = FakeApi()
          ..on('GET /x', (r) => online ? ok({'n': 1}) : _offline(r));
        final cache = ReadCache(prefs, await _client(api), 'u/org/1');
        final fresh = await cache.get('x', '/x');
        expect(fresh.isSaved, isFalse);
        online = false;
        final saved = await cache.get('x', '/x');
        expect(saved.payload, {'n': 1});
        expect(saved.isSaved, isTrue);
      },
    );

    test('a server error is not hidden by the saved copy', () async {
      var fail = false;
      final api = FakeApi()
        ..on('GET /x', (_) => fail ? apiError(500) : ok({'n': 1}));
      final cache = ReadCache(prefs, await _client(api), 'u/org/1');
      await cache.get('x', '/x');
      fail = true;
      await expectLater(cache.get('x', '/x'), throwsA(isA<ApiException>()));
    });

    test('another workspace never sees it; sign-out clears all', () async {
      var online = true;
      final api = FakeApi()
        ..on('GET /x', (r) => online ? ok({'n': 1}) : _offline(r));
      final client = await _client(api);
      await ReadCache(prefs, client, 'u/org/1').get('x', '/x');
      online = false;
      await expectLater(
        ReadCache(prefs, client, 'u/org/2').get('x', '/x'),
        throwsA(isA<ApiException>()),
      );
      // Without a workspace nothing is kept.
      online = true;
      await ReadCache(prefs, client, null).get('y', '/x');
      expect(
        prefs.getKeys().where((k) => k.startsWith('cache/')),
        hasLength(1),
      );
      await ReadCache.clearAll(prefs);
      expect(prefs.getKeys().where((k) => k.startsWith('cache/')), isEmpty);
    });
  });

  testWidgets('Today offline: the saved week, marked as saved', (tester) async {
    final key = 'cache/user-1/organization/org-1/calendar-week';
    final api = _shell()..on('GET /calendar/me', _offline);
    await pumpInstructorApp(
      tester,
      api: api,
      session: testSession(),
      prefs: {
        key: jsonEncode({
          'saved_at': '2026-11-18T03:00:00.000Z',
          'payload': {
            'from': _today,
            'to': addDays(_today, 7),
            'items': [
              {
                'kind': 'EVENT',
                'id': 'e1',
                'starts_at': '${_today}T14:00:00+06:00',
                'ends_at': '${_today}T15:00:00+06:00',
                'title': 'Science fair',
                'cancelled': false,
              },
            ],
          },
        }),
      },
    );
    expect(find.byKey(const Key('saved-copy')), findsOneWidget);
    expect(find.text('Science fair'), findsOneWidget);
  });

  testWidgets('Today offline with only an old copy: the error', (tester) async {
    final key = 'cache/user-1/organization/org-1/calendar-week';
    await pumpInstructorApp(
      tester,
      api: _shell()..on('GET /calendar/me', _offline),
      session: testSession(),
      prefs: {
        key: jsonEncode({
          'saved_at': '2026-11-01T03:00:00.000Z',
          'payload': {'from': '2026-11-01', 'items': <Object>[]},
        }),
      },
    );
    expect(find.text(_en.todayLoadFailed), findsOneWidget);
    expect(find.byKey(const Key('saved-copy')), findsNothing);
  });

  testWidgets('My attendance offline: classes shown, no check-in', (
    tester,
  ) async {
    final key = 'cache/user-1/organization/org-1/attendance-today';
    final c = await pumpInstructorApp(
      tester,
      api: _shell()
        ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
        ..on('GET /attendance/me/today', _offline),
      session: testSession(),
      prefs: {
        key: jsonEncode({
          'saved_at': '2026-11-18T03:00:00.000Z',
          'payload': _myToday(_today),
        }),
      },
    );
    c.read(routerProvider).go(AppRoutes.myAttendance);
    await tester.pumpAndSettle();
    expect(find.byType(MyAttendanceScreen), findsOneWidget);
    expect(find.byKey(const Key('saved-copy')), findsOneWidget);
    expect(find.text('English · Class 6 A'), findsOneWidget);
    expect(find.text(_en.myAttendanceCheckIn), findsNothing);
  });

  testWidgets('signing out removes the saved copies', (tester) async {
    final key = 'cache/user-1/organization/org-1/attendance-today';
    final c = await pumpInstructorApp(
      tester,
      api: _shell()
        ..on('GET /calendar/me', (_) => ok({'items': <Object>[]}))
        ..on('POST /auth/logout', (_) => ok(null)),
      session: testSession(),
      prefs: {
        key: jsonEncode({'saved_at': 'x', 'payload': <String, Object>{}}),
      },
    );
    await c.read(sessionHolderProvider).clear();
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys().where((k) => k.startsWith('cache/')), isEmpty);
  });
}
