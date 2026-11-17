import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// What `GET /student/exams/:id/eligibility` says (with the proctoring that
/// will run, P8-01).
@immutable
class Eligibility {
  const Eligibility({
    required this.canAccess,
    required this.reasonCode,
    this.level = 'OFF',
    this.checks = const [],
    this.camera = false,
    this.autoDisqualify,
  });

  final bool canAccess;

  /// OK, NOT_STARTED, ENDED, ALREADY_SUBMITTED, DISQUALIFIED, NOT_ASSIGNED,
  /// EXAM_FULL.
  final String reasonCode;

  /// OFF, LIGHT or STRICT.
  final String level;
  final List<String> checks;
  final bool camera;
  final AutoDisqualify? autoDisqualify;

  /// Strict tests (camera, microphone) need a computer (owner's decision 7).
  bool get needsComputer => level == 'STRICT' || camera;

  factory Eligibility.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final p = j['proctoring'] is Map ? j['proctoring'] as Map : null;
    final a = p?['auto_disqualify'];
    return Eligibility(
      canAccess: j['can_access'] == true || j['eligible'] == true,
      reasonCode: (j['reason_code'] as String?) ?? 'OK',
      level: (p?['level'] as String?) ?? 'OFF',
      checks: [
        if (p?['checks'] is List)
          for (final c in p!['checks'] as List)
            if (c is String) c,
      ],
      camera: p?['camera'] == true,
      autoDisqualify: a is Map && a['threshold'] is num
          ? AutoDisqualify(
              threshold: (a['threshold'] as num).toInt(),
              warnAt: (a['warn_at'] as num?)?.toInt() ?? 0,
              checks: [
                if (a['checks'] is List)
                  for (final c in a['checks'] as List)
                    if (c is String) c,
              ],
            )
          : null,
    );
  }
}

/// Auto-disqualification (PRO-02): flags of [checks] count; a warning at
/// [warnAt]; the test ends at [threshold].
@immutable
class AutoDisqualify {
  const AutoDisqualify({
    required this.threshold,
    required this.warnAt,
    required this.checks,
  });

  final int threshold;
  final int warnAt;
  final List<String> checks;
}

typedef Choice = ({String id, String text});

/// single-select, multi-select, matching or text. Spoken answers
/// (audio-record) are IELTS only and need a computer.
String inputModeOf(String type, String subType) {
  if (subType.startsWith('speaking-part')) return 'audio-record';
  if (type == 'ungraded') return 'text';
  if (subType == 'matching-ordering') return 'matching';
  if (subType == 'multiple-response') return 'multi-select';
  const text = {
    'essay',
    'fill-in-the-gaps',
    'fill-in-the-blanks',
    'answer-box',
    'sentence-completion',
    'summary-completion',
    'table-completion',
    'diagram-label',
    'short-answer',
    'writing-task-1',
    'writing-task-2',
  };
  return text.contains(subType) ? 'text' : 'single-select';
}

@immutable
class PaperQuestion {
  const PaperQuestion({
    required this.id,
    required this.number,
    required this.text,
    required this.points,
    required this.mode,
    this.instruction,
    this.choices = const [],
    this.left = const [],
    this.right = const [],
    this.passage,
  });

  final String id;
  final int number;
  final String text;
  final String? instruction;
  final num points;
  final String mode;
  final List<Choice> choices;
  final List<Choice> left;
  final List<Choice> right;

  /// The reading passage above it, shown once for its questions.
  final String? passage;

  /// What an empty answer is: text "" or a list.
  Object get empty => mode == 'text' ? '' : const <String>[];
}

List<Choice> _choices(Object? list) => [
  if (list is List)
    for (final o in list)
      if (o is Map && o['id'] is String)
        (id: o['id'] as String, text: (o['text'] as String?) ?? ''),
];

/// The test as the student writes it (`GET /exams/:id` after starting).
@immutable
class TestPaper {
  const TestPaper({
    required this.id,
    required this.name,
    required this.questions,
    this.remainingSeconds,
    this.totalMarks = 0,
  });

  final String id;
  final String name;
  final List<PaperQuestion> questions;
  final int? remainingSeconds;
  final num totalMarks;

  bool get hasSpokenAnswers => questions.any((q) => q.mode == 'audio-record');

  factory TestPaper.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final entries = <(num, Map<Object?, Object?>)>[];
    if (j['subjects'] is List) {
      for (final s in j['subjects'] as List) {
        if (s is Map && s['questions'] is List) {
          for (final q in s['questions'] as List) {
            if (q is Map) entries.add(((q['sortOrder'] as num?) ?? 0, q));
          }
        }
      }
    }
    // The web's order: by sortOrder, keeping the list's order on ties.
    final indexed = entries.indexed.toList()
      ..sort((a, b) {
        final c = a.$2.$1.compareTo(b.$2.$1);
        return c != 0 ? c : a.$1.compareTo(b.$1);
      });
    var number = 1;
    num marks = 0;
    final questions = <PaperQuestion>[];
    PaperQuestion build(Map<Object?, Object?> q, {String? passage}) {
      final m = q['matchingOptions'];
      final points = (q['points'] as num?) ?? 0;
      marks += points;
      return PaperQuestion(
        id: q['id'] as String,
        number: number++,
        text: (q['text'] as String?) ?? '',
        instruction: q['instruction'] as String?,
        points: points,
        mode: inputModeOf(
          (q['type'] as String?) ?? 'graded',
          (q['subType'] as String?) ?? '',
        ),
        choices: _choices(q['options']),
        left: m is Map ? _choices(m['left']) : const [],
        right: m is Map ? _choices(m['right']) : const [],
        passage: passage,
      );
    }

    for (final (_, (_, q)) in indexed) {
      if (q['type'] == 'passage-question' && q['childQuestions'] is List) {
        for (final c in q['childQuestions'] as List) {
          if (c is Map && c['id'] is String) {
            questions.add(build(c, passage: q['passageText'] as String?));
          }
        }
      } else if (q['id'] is String) {
        questions.add(build(q));
      }
    }
    return TestPaper(
      id: (j['id'] as String?) ?? '',
      name: (j['test_name'] as String?) ?? '',
      questions: questions,
      remainingSeconds: (j['remaining_time_seconds'] as num?)?.toInt(),
      totalMarks: marks,
    );
  }
}

/// How a test ended (`reason` of the submit).
enum SubmitReason {
  manual('manual'),
  timeout('timeout'),
  disqualified('disqualified');

  const SubmitReason(this.api);
  final String api;
}

/// A flag raised in the app (Light proctoring).
@immutable
class ProctorFlag {
  const ProctorFlag({
    required this.id,
    required this.type,
    required this.message,
    required this.points,
    required this.at,
  });

  final String id;

  /// The web's flag type: tab-switch, paste-attempt.
  final String type;
  final String message;
  final int points;
  final DateTime at;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'message': message,
    'points': points,
    'timestamp': at.toUtc().toIso8601String(),
  };
}

class TakeTestRepository {
  TakeTestRepository(this._api);

  final ApiClient _api;

  Future<Eligibility> eligibility(String id) async => Eligibility.fromJson(
    (await _api.get('/student/exams/$id/eligibility')).payload,
  );

  Future<void> start(String id, {required String userAgent}) =>
      _api.post('/student/exams/$id/start', data: {'user_agent': userAgent});

  Future<TestPaper> paper(String id) async =>
      TestPaper.fromJson((await _api.get('/exams/$id')).payload);

  /// Low-bandwidth mode (PRO-09): only what changed.
  Future<void> save(String id, Map<String, Object> changed) => _api.put(
    '/student/exams/$id/answersheet',
    data: {'answersheet': changed},
  );

  Future<void> submit(
    String id, {
    required String studentId,
    required Map<String, Object> answers,
    required SubmitReason reason,
    List<ProctorFlag> flags = const [],
    String? disqualificationReason,
  }) => _api.post(
    '/student/exams/$id/answersheet',
    data: {
      'studentId': studentId,
      'answersheet': answers,
      'reason': reason.api,
      'disqualification_reason': ?disqualificationReason,
      'proctoring_events': [for (final f in flags) f.toJson()],
    },
  );

  /// TAB_SWITCH (leaving the app) is stored on the attempt, as the web.
  Future<void> reportViolation(String id, String type) => _api.post(
    '/student/exams/$id/report-violation',
    data: {'violation_type': type},
  );
}

final takeTestRepositoryProvider = Provider<TakeTestRepository>(
  (ref) => TakeTestRepository(ref.watch(apiClientProvider)),
);
