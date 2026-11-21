import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/clock.dart';
import 'package:instructor_app/features/ielts/data/marking.dart';
import 'package:instructor_app/features/ielts/data/recording.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

class _FakeRecorder implements SpeakingRecorder {
  _FakeRecorder({required this.allowed, required this.file});

  final bool allowed;
  final String file;

  @override
  Future<bool> hasPermission() async => allowed;

  @override
  Future<void> start() async {}

  @override
  Future<String?> stop() async => file;

  @override
  Future<void> dispose() async {}
}

class _FakePlayer implements RecordingPlayer {
  @override
  Future<void> play(Uri uri) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}

Map<String, Object?> _attempt({Map<String, Object?> recordings = const {}}) => {
  'attempt': {
    'id': 'x1',
    'module': 'SPEAKING',
    'status': 'IN_PROGRESS',
    'mode': 'RECORDED',
    'deadline': '2026-11-25T04:24:00.000Z',
    'now': '2026-11-25T04:00:00.000Z',
    'raw_score': null,
    'band': null,
    'recordings': recordings,
    'review_seconds': 0,
  },
  'test': {'id': 't1', 'title': 'Speaking practice', 'purpose': 'PRACTICE'},
  'parts': [
    for (final no in [1, 2])
      {
        'id': 'p$no',
        'module': 'SPEAKING',
        'part_no': no,
        'title': null,
        'content': no == 2
            ? '<p>Describe a place you like.</p>'
            : '<p>Where do you live?</p>',
        'audio_file_id': null,
        'image_file_id': null,
        'groups': <Object>[],
      },
  ],
  'answers': <String, Object>{},
};

Map<String, Object?> _marking({
  String mode = 'LIVE',
  String status = 'IN_PROGRESS',
}) => {
  'attempt_id': 'x7',
  'module': 'SPEAKING',
  'status': status,
  'student': {'id': 's1', 'full_name': 'Tania Akter'},
  'test': {'id': 't1', 'title': 'Full mock 1'},
  'batch': 'Evening A',
  'submitted_at': null,
  'band': null,
  'mode': mode,
  'tasks': [
    {
      'part_id': 'p1',
      'part_no': 1,
      'title': null,
      'content': '<p>Where do you live?</p>',
      'image_file_id': null,
      'script': '',
      'words': 0,
      'min_words': 0,
      'recording_file_id': null,
    },
  ],
  'marks': <Object>[],
  'speaking': null,
  'feedback': null,
};

FakeApi _api() => FakeApi()
  ..on('GET /auth/contexts', (_) => ok(<Object>[]))
  ..on(
    'GET /me/entitlements',
    (_) => ok({
      'features': {'ielts': true},
    }),
  )
  ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
  ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
  ..on('GET /dashboard/teacher', (_) => ok(<String, Object>{}))
  ..on('GET /ielts/my/attempts/x1', (_) => ok(_attempt()))
  ..on(
    'POST /files/presign',
    (_) => ok({
      'file': {'id': 'f5'},
      'upload': {
        'url': 'https://storage.test/b/f5',
        'headers': {'Content-Type': 'audio/x-m4a'},
      },
      'storage': {'warning': false},
    }),
  )
  ..on('PUT /b/f5', (_) => (200, null))
  ..on(
    'POST /files/f5/complete',
    (_) => ok({'id': 'f5', 'name': 'a.m4a', 'mime': 'audio/x-m4a'}),
  )
  ..on(
    'PUT /ielts/my/attempts/x1/recordings',
    (_) => ok(_attempt(recordings: {'p1': 'f5'})),
  )
  ..on('GET /ielts/marking/x7', (_) => ok(_marking()))
  ..on('PUT /ielts/marking/x7/speaking', (_) => ok(_marking(status: 'MARKED')));

Future<FakeApi> _open(
  WidgetTester tester,
  String role,
  String route, {
  bool allowed = true,
}) async {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final dir = Directory.systemTemp.createTempSync('speaking');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/a.m4a')..writeAsBytesSync([1, 2, 3]);
  final api = _api();
  final app = await pumpInstructorApp(
    tester,
    api: api,
    session: ieltsMember(role),
    overrides: [
      clockProvider.overrideWithValue(() => tester.binding.clock.now()),
      speakingRecorderProvider.overrideWithValue(
        () => _FakeRecorder(allowed: allowed, file: file.path),
      ),
      recordingPlayerProvider.overrideWithValue(_FakePlayer.new),
    ],
  );
  app.read(routerProvider).go(route);
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  return api;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  group('bands, as the server rounds them', () {
    test('nearest half band: .25 up, .75 up to the next', () {
      expect(roundBand(6.25), 6.5);
      expect(roundBand(6.75), 7);
      expect(roundBand(6.1), 6);
      expect(
        criteriaBand({'FC': 6, 'LR': 6.5, 'GRA': 6, 'P': 7}, speakingCriteria),
        6.5,
      );
      expect(criteriaBand({'FC': 6}, speakingCriteria), isNull);
    });

    test('Writing: Task 2 counts double', () {
      expect(writingBand(6, 7), 6.5);
      expect(writingBand(null, 7), 7);
      expect(writingBand(null, null), isNull);
    });
  });

  testWidgets('practice: record a part, keep it, record again', (tester) async {
    final api = await _open(tester, 'STUDENT', '/ielts/attempts/x1');
    expect(find.text('Where do you live?'), findsOneWidget);
    await _tap(tester, find.byKey(const Key('speaking-record-p1')));
    expect(find.byKey(const Key('speaking-stop-p1')), findsOneWidget);
    await _tap(tester, find.byKey(const Key('speaking-stop-p1')));
    expect(
      api.to('POST /files/presign').single.body,
      containsPair('purpose', 'IELTS'),
    );
    expect(api.to('PUT /ielts/my/attempts/x1/recordings').single.body, {
      'part_id': 'p1',
      'file_id': 'f5',
    });
    expect(find.text(_en.ieltsSpeakingRecordAgain), findsOneWidget);
    expect(find.byKey(const Key('recording-f5')), findsOneWidget);

    // Part 2 has no recording yet: handing in says so.
    await _tap(tester, find.byKey(const Key('ielts-handin')));
    expect(find.text(_en.ieltsTakeHandInNoRecording(1)), findsOneWidget);
  });

  testWidgets('part 2: preparation and talk timers', (tester) async {
    await _open(tester, 'STUDENT', '/ielts/attempts/x1');
    await _tap(tester, find.byKey(const Key('speaking-prepare-p2')));
    expect(find.text('${_en.ieltsSpeakingPrepare} 01:00'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('${_en.ieltsSpeakingPrepare} 00:59'), findsOneWidget);
  });

  testWidgets('no microphone: says so', (tester) async {
    await _open(tester, 'STUDENT', '/ielts/attempts/x1', allowed: false);
    await _tap(tester, find.byKey(const Key('speaking-record-p1')));
    expect(find.text(_en.ieltsSpeakingMicrophoneDenied), findsOneWidget);
  });

  testWidgets('the examiner: four criteria, the band, save and end', (
    tester,
  ) async {
    final api = await _open(tester, 'TEACHER', '/ielts/speaking/x7');
    expect(
      find.text(_en.ieltsSpeakingExaminerTitle('Tania Akter')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('speaking-record-p1')), findsOneWidget);
    final save = find.byKey(const Key('speaking-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    for (final (k, band) in [
      ('FC', '6.0'),
      ('LR', '6.5'),
      ('GRA', '6.0'),
      ('P', '7.0'),
    ]) {
      await _tap(tester, find.byKey(Key('criterion-$k')));
      await tester.tap(find.text(band).last);
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(find.text(_en.ieltsSpeakingBandPreview('6.5')), findsOneWidget);
    expect(find.text(_en.ieltsSpeakingSaveAndEnd), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('speaking-notes')),
      'Good fluency.',
    );
    await _tap(tester, save);
    expect(api.to('PUT /ielts/marking/x7/speaking').single.body, {
      'criteria': {'FC': 6, 'LR': 6.5, 'GRA': 6, 'P': 7},
      'feedback': 'Good fluency.',
    });
  });
}
