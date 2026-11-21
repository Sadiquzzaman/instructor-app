import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/routing/app_router.dart';
import 'package:instructor_app/core/time/clock.dart';
import 'package:instructor_app/features/ielts/data/listening_audio.dart';
import 'package:instructor_app/features/ielts/screens/listening_player.dart';
import 'package:instructor_app/l10n/generated/app_localizations_en.dart';

import '../../helpers/fake_api.dart';
import '../../helpers/pump_app.dart';
import 'ielts_overview_test.dart' show ieltsMember;

final _en = AppLocalizationsEn();

/// A player the test finishes by hand.
class _FakePlayer implements OncePlayer {
  _FakePlayer(this.log);

  final List<String> log;
  final _done = Completer<void>();
  final _progress = StreamController<double>.broadcast();

  void finish() => _done.complete();

  void at(double p) => _progress.add(p);

  @override
  Future<void> play(Uri uri) {
    log.add('play ${uri.path}');
    return _done.future;
  }

  @override
  Stream<double> get progress => _progress.stream;

  @override
  Future<void> setVolume(double volume) async => log.add('volume $volume');

  @override
  Future<void> dispose() async => _progress.close();
}

Map<String, Object?> _attempt({String? audio = 'f9'}) => {
  'attempt': {
    'id': 'x1',
    'module': 'LISTENING',
    'status': 'IN_PROGRESS',
    'deadline': '2026-11-25T04:32:00.000Z',
    'now': '2026-11-25T04:00:00.000Z',
    'raw_score': null,
    'band': null,
    'review_seconds': 120,
  },
  'test': {'id': 't1', 'title': 'Listening set', 'purpose': 'PRACTICE'},
  'parts': [
    {
      'id': 'p1',
      'module': 'LISTENING',
      'part_no': 1,
      'title': null,
      'content': null,
      'audio_file_id': audio,
      'image_file_id': null,
      'groups': [
        {
          'id': 'g1',
          'type': 'FORM_COMPLETION',
          'instruction': 'Write ONE WORD.',
          'word_limit': 1,
          'shared': null,
          'image_file_id': null,
          'number_from': 1,
          'number_to': 1,
          'questions': [
            {
              'id': 'q1',
              'number_from': 1,
              'number_to': 1,
              'prompt': 'Name:',
              'options': null,
            },
          ],
        },
      ],
    },
  ],
  'answers': <String, Object>{},
};

Future<List<_FakePlayer>> _open(
  WidgetTester tester, {
  String? audio = 'f9',
  Map<String, Object>? prefs,
  List<String>? log,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final players = <_FakePlayer>[];
  final app = await pumpInstructorApp(
    tester,
    api: FakeApi()
      ..on('GET /auth/contexts', (_) => ok(<Object>[]))
      ..on(
        'GET /me/entitlements',
        (_) => ok({
          'features': {'ielts': true},
        }),
      )
      ..on('GET /me/notifications/unread-count', (_) => ok({'count': 0}))
      ..on('GET /workspace/level-labels', (_) => ok(<String, Object>{}))
      ..on('GET /ielts/my/attempts/x1', (_) => ok(_attempt(audio: audio))),
    session: ieltsMember('STUDENT'),
    prefs: prefs ?? const {},
    overrides: [
      clockProvider.overrideWithValue(() => tester.binding.clock.now()),
      oncePlayerProvider.overrideWithValue(() {
        final p = _FakePlayer(log ?? []);
        players.add(p);
        return p;
      }),
    ],
  );
  app.read(routerProvider).go('/ielts/attempts/x1');
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
  return players;
}

void main() {
  testWidgets('a recording plays once, with the volume only', (tester) async {
    final log = <String>[];
    final players = await _open(tester, log: log);
    expect(find.text('1. Name:'), findsOneWidget);
    final play = find.byKey(const Key('listening-play-p1'));
    expect(play, findsOneWidget);
    await tester.tap(play);
    await tester.pump();
    expect(log, contains('play /api/v1/files/f9/content'));
    // While it plays there is nothing to pause or play again.
    expect(play, findsNothing);
    expect(find.text(_en.ieltsTakePlaying), findsOneWidget);
    players.single.at(0.5);
    await tester.pump();
    players.single.finish();
    await tester.pump();
    await tester.pump();
    expect(find.text(_en.ieltsTakePlayed), findsOneWidget);
    expect(find.byKey(const Key('listening-play-p1')), findsNothing);
  });

  testWidgets('one that was playing when the app was left counts as played', (
    tester,
  ) async {
    final players = await _open(
      tester,
      prefs: {listeningKey('x1', 'p1'): 'playing'},
    );
    expect(find.byKey(const Key('listening-play-p1')), findsNothing);
    expect(find.text(_en.ieltsTakePlayed), findsOneWidget);
    expect(players, isEmpty);
  });

  testWidgets('a part without a recording says so', (tester) async {
    await _open(tester, audio: null);
    expect(find.text(_en.ieltsTakeNoRecording), findsOneWidget);
  });
}
