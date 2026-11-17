import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';
import 'package:instructor_app/features/calendar/screens/calendar_screen.dart';
import 'package:instructor_app/l10n/generated/app_localizations_bn.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

final _en = AppLocalizationsEn();
final _today = OrgTime.today();
final _month = _today.substring(0, 7);
// Another day this month (the 1st, or the 2nd when today is the 1st).
final _other = '$_month-${_today.endsWith('-01') ? '02' : '01'}';

const _here = {'key': 'org:org-1', 'label': 'Demo School'};
const _there = {'key': 'org:org-9', 'label': 'Sunrise School'};

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on('GET /me/entitlements', (_) => ok({'features': <String, bool>{}}))
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on(
    'GET /calendar/me',
    (r) => ok({
      'from': r.query['from'],
      'to': r.query['to'],
      'time_zone': 'Asia/Dhaka',
      'workspaces': [_here, _there],
      'items': [
        {
          'kind': 'EXAM',
          'id': 'x1',
          'starts_at': '${_today}T10:00:00+06:00',
          'ends_at': '${_today}T11:00:00+06:00',
          'title': 'Maths monthly test',
          'class_name': 'Class 6',
          'workspace': _here,
        },
        {
          'kind': 'EVENT',
          'id': 'e1',
          'starts_at': '${_other}T14:00:00+06:00',
          'ends_at': '${_other}T15:00:00+06:00',
          'title': 'Science fair',
          'cancelled': false,
          'workspace': _there,
        },
      ],
    }),
  )
  ..on(
    'GET /reminders',
    (_) => ok({
      'defaults': <String, Object>{},
      'mine': {
        'CLASS': {
          'offsets': [
            {'minutes': 30, 'channel': 'IN_APP'},
          ],
          'own': false,
        },
        'EXAM': {
          'offsets': [
            {'minutes': 1440, 'channel': 'SMS'},
          ],
          'own': true,
        },
        'EVENT': {'offsets': <Object>[], 'own': true},
      },
    }),
  );

Future<FakeApi> _open(WidgetTester tester, {String? lang}) async {
  final api = _api();
  final c = await pumpInstructorApp(
    tester,
    api: api,
    session: testSession(),
    prefs: {'language': ?lang},
  );
  c.read(routerProvider).go(AppRoutes.calendar);
  await tester.pumpAndSettle();
  return api;
}

Finder _inDay(Finder f) =>
    find.descendant(of: find.byKey(const Key('calendar-day')), matching: f);

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(
    f,
    200,
    scrollable: find
        .descendant(
          of: find.byType(CalendarScreen),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the month; today\'s list; another day; next month', (
    tester,
  ) async {
    final api = await _open(tester);
    // Today (home) asks for its week first; the calendar asks for the month.
    final month = api
        .to('GET /calendar/me')
        .map((r) => r.query)
        .firstWhere((q) => q['from'] == '$_month-01');
    expect((month['to']! as String).startsWith(_month), isTrue);

    await _scrollTo(tester, find.byKey(const Key('calendar-day')));
    expect(_inDay(find.text('Maths monthly test')), findsOneWidget);
    expect(_inDay(find.text('Science fair')), findsNothing);

    await _scrollTo(tester, find.byKey(Key('day-$_other')));
    await tester.tap(find.byKey(Key('day-$_other')));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('calendar-day')));
    expect(_inDay(find.text('Science fair')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byTooltip(_en.calendarNext),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(CalendarScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.byTooltip(_en.calendarNext));
    await tester.pumpAndSettle();
    final next = DateTime.utc(
      int.parse(_month.substring(0, 4)),
      int.parse(_month.substring(5)) + 1,
    );
    expect(
      api.to('GET /calendar/me').last.query['from'],
      '${next.year}-${next.month.toString().padLeft(2, '0')}-01',
    );
    expect(addDays('2026-11-30', 1), '2026-12-01');
  });

  testWidgets('filters: by kind and by workspace', (tester) async {
    await _open(tester);
    await tester.tap(find.widgetWithText(FilterChip, _en.calendarFiltersEXAM));
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('calendar-day')));
    expect(_inDay(find.text('Maths monthly test')), findsNothing);

    await tester.scrollUntilVisible(
      find.widgetWithText(FilterChip, _en.calendarFiltersEXAM),
      -200,
      scrollable: find
          .descendant(
            of: find.byType(CalendarScreen),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.widgetWithText(FilterChip, _en.calendarFiltersEXAM));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('calendar-workspace')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunrise School').last);
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byKey(const Key('calendar-day')));
    expect(_inDay(find.text('Maths monthly test')), findsNothing);
  });

  testWidgets('my reminders, read only', (tester) async {
    await _open(tester);
    await _scrollTo(tester, find.byKey(const Key('calendar-reminders')));
    expect(
      find.textContaining(
        _en.calendarRemindersItem(
          _en.calendarRemindersMinutes(30),
          _en.calendarRemindersChannelsINAPP,
        ),
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(_en.calendarRemindersUsingDefault),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        _en.calendarRemindersItem(
          _en.calendarRemindersDays(1),
          _en.calendarRemindersChannelsSMS,
        ),
      ),
      findsOneWidget,
    );
    expect(find.text(_en.calendarRemindersOff), findsOneWidget);
  });

  testWidgets('in Bangla', (tester) async {
    final bn = AppLocalizationsBn();
    await _open(tester, lang: 'bn');
    expect(find.text(bn.calendarTitle), findsWidgets);
    expect(find.text(bn.calendarFiltersEXAM), findsOneWidget);
  });
}
