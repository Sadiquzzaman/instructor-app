import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'package:instructor_app/features/shell/screens/placeholder_home.dart';
import 'package:instructor_app/features/version/data/version_check.dart';
import 'package:instructor_app/features/version/screens/version_gate.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';

void main() {
  group('VersionStatus.fromPayload', () {
    test('reads the answer', () {
      final s = VersionStatus.fromPayload({
        'update': 'OPTIONAL',
        'latest': '0.2.0',
        'update_url': 'https://github.com/Sadiquzzaman/instructor-app/releases',
      });
      expect(s.need, UpdateNeed.optional);
      expect(s.latest, '0.2.0');
      expect(s.updateUrl!.host, 'github.com');
    });

    test('only https links are kept; unknown answers mean no update', () {
      expect(
        VersionStatus.fromPayload({
          'update': 'REQUIRED',
          'update_url': 'http://example.com',
        }).updateUrl,
        isNull,
      );
      expect(
        VersionStatus.fromPayload({'update_url': 'javascript:alert(1)'})
            .updateUrl,
        isNull,
      );
      expect(VersionStatus.fromPayload({'update': null}).need, UpdateNeed.none);
    });
  });

  testWidgets('asks with this build\'s platform and version, without sign-in', (
    tester,
  ) async {
    final api = FakeApi();
    await pumpInstructorApp(tester, api: api);
    final r = api.to('GET /app/version').single;
    expect(r.query, {'platform': 'ANDROID', 'current': '0.1.0'});
    expect(r.headers.containsKey('Authorization'), isFalse);
    expect(find.byType(PlaceholderHome), findsOneWidget);
  });

  testWidgets('REQUIRED: the app is replaced by the update screen', (
    tester,
  ) async {
    final opened = <Uri>[];
    final api = FakeApi()
      ..on(
        'GET /app/version',
        (_) => ok({
          'update': 'REQUIRED',
          'minimum': '0.2.0',
          'latest': '0.2.0',
          'update_url': 'https://example.com/instructor.apk',
        }),
      );
    await pumpInstructorApp(tester, api: api, openedLinks: opened);

    expect(find.byType(UpdateRequiredScreen), findsOneWidget);
    expect(find.byType(PlaceholderHome), findsNothing);
    expect(find.text('Please update Instructor'), findsOneWidget);

    await tester.tap(find.text('Update'));
    expect(opened, [Uri.parse('https://example.com/instructor.apk')]);
  });

  testWidgets('REQUIRED without a link says where to get it, in Bangla too', (
    tester,
  ) async {
    final api = FakeApi()
      ..on('GET /app/version', (_) => ok({'update': 'REQUIRED'}));
    await pumpInstructorApp(tester, api: api, prefs: {'language': 'bn'});
    expect(find.text('Instructor আপডেট করুন'), findsOneWidget);
    expect(
      find.text('নতুন সংস্করণ আপনার প্রতিষ্ঠান বা অ্যাপ স্টোর থেকে নিন।'),
      findsOneWidget,
    );
  });

  testWidgets('OPTIONAL: a banner above the app, "Later" hides it', (
    tester,
  ) async {
    final api = FakeApi()
      ..on(
        'GET /app/version',
        (_) => ok({
          'update': 'OPTIONAL',
          'update_url': 'https://example.com/instructor.apk',
        }),
      );
    await pumpInstructorApp(tester, api: api);

    expect(
      find.text('A new version of Instructor is available.'),
      findsOneWidget,
    );
    expect(find.byType(PlaceholderHome), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(
      find.text('A new version of Instructor is available.'),
      findsNothing,
    );
  });

  testWidgets('a failed check never blocks the app', (tester) async {
    final api = FakeApi()
      ..on('GET /app/version', (_) => apiError(502, message: 'Bad Gateway'));
    await pumpInstructorApp(tester, api: api);
    expect(find.byType(PlaceholderHome), findsOneWidget);
    expect(find.byType(UpdateRequiredScreen), findsNothing);
  });

  testWidgets('coming back within an hour does not ask again', (tester) async {
    final api = FakeApi();
    await pumpInstructorApp(tester, api: api);
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pumpAndSettle();
    expect(api.to('GET /app/version'), hasLength(1));
    expect(VersionGate.recheckAfter, const Duration(hours: 1));
  });
}
