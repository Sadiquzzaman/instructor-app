import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// A test: set to the student (`/student/exams/assigned`,
/// `/student/exams/class/:id`), or a teacher's (`/exams`,
/// `/exams/class/:id`, `/exams/:id`), whose times sit in `publishState`
/// and duration in `formState`.
@immutable
class TestItem {
  const TestItem({
    required this.id,
    required this.name,
    required this.status,
    this.subject,
    this.className,
    this.startsAt,
    this.endsAt,
    this.durationMinutes,
    this.participants = 0,
    this.submitted = 0,
    this.ielts = false,
    this.active = true,
    this.createdBy,
    this.sessionId,
    this.subjects = const [],
    this.audience,
    this.passingScore,
    this.negativeMarking,
  });

  final String id;
  final String name;

  /// pending (not started), ongoing or completed.
  final String status;
  final String? subject;
  final String? className;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? durationMinutes;
  final int participants;
  final int submitted;
  final bool ielts;

  /// Teachers: switched on (`is_active` 1) or off.
  final bool active;

  /// Teachers: who made it (they mark it, watch it live).
  final String? createdBy;
  final String? sessionId;

  /// Teachers: each subject and how many questions it has.
  final List<({String name, int questions})> subjects;

  /// Teachers: CLASS, OFFERING or SPECIFIC students.
  final String? audience;
  final String? passingScore;

  /// Teachers: the % taken off for a wrong answer; null when off.
  final String? negativeMarking;

  int get questionCount => subjects.fold(0, (n, s) => n + s.questions);

  static TestItem? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final form = j['formState'] is Map
        ? j['formState'] as Map
        : const <String, Object?>{};
    final publish = j['publishState'] is Map
        ? j['publishState'] as Map
        : const <String, Object?>{};
    final subjects = <({String name, int questions})>[
      if (j['subjects'] is List)
        for (final s in j['subjects'] as List)
          if (s is Map)
            (
              name: (s['name'] as String?) ?? '',
              questions: s['questions'] is List
                  ? [
                      for (final q in s['questions'] as List)
                        q is Map && q['childQuestions'] is List
                            ? (q['childQuestions'] as List).length
                            : 1,
                    ].fold(0, (a, b) => a + b)
                  : 0,
            ),
    ];
    final names = subjects.map((s) => s.name).where((n) => n.isNotEmpty);
    return TestItem(
      id: j['id'] as String,
      name: (j['test_name'] as String?) ?? '',
      status: (j['status'] as String?) ?? 'pending',
      subject:
          j['subject'] as String? ?? (names.isEmpty ? null : names.join(', ')),
      className: j['class_name'] as String?,
      startsAt: _time(j['exam_start_time']) ?? _time(publish['scheduleAt']),
      endsAt: _time(j['exam_end_time']) ?? _time(publish['endingAt']),
      durationMinutes:
          (j['duration_minutes'] as num?)?.toInt() ??
          (form['duration'] as num?)?.toInt(),
      active: j['is_active'] != 0,
      createdBy: j['created_by'] as String?,
      sessionId: j['session_id'] as String?,
      subjects: subjects,
      audience: publish['testAudience'] as String?,
      passingScore: form['passingScore']?.toString(),
      negativeMarking: form['allowNegativeMarking'] == true
          ? form['negativeMarking']?.toString()
          : null,
      participants: (j['participant_count'] as num?)?.toInt() ?? 0,
      submitted: (j['submitted_count'] as num?)?.toInt() ?? 0,
      ielts: j['exam_category'] == 'IELTS' || form['examCategory'] == 'IELTS',
    );
  }

  static List<TestItem> listOf(Object? p) => [
    if (p is List)
      for (final t in p) ?TestItem.fromJson(t),
  ];
}

/// One question on the answer sheet, with the student's answer.
@immutable
class ResultQuestion {
  const ResultQuestion({
    required this.question,
    required this.points,
    required this.marks,
    required this.studentAnswer,
    required this.correctAnswer,
    this.isCorrect,
    this.passage,
  });

  final String question;
  final num points;
  final num marks;

  /// The words of the student's choice(s) or text; empty when not answered.
  final List<String> studentAnswer;

  /// The words of the right choice(s); empty for written answers.
  final List<String> correctAnswer;

  /// Null when a teacher marks it (essays) or it has no right answer.
  final bool? isCorrect;

  /// The reading passage it belongs to, if any.
  final String? passage;

  static ResultQuestion? fromJson(Object? j, {String? passage}) {
    if (j is! Map) return null;
    final answer = j['answer'] is Map
        ? j['answer'] as Map
        : const <String, Object?>{};
    final options = {
      if (j['options'] is List)
        for (final o in j['options'] as List)
          if (o is Map && o['id'] is String)
            o['id'] as String: (o['text'] as String?) ?? '',
    };
    final matching = j['matchingOptions'];
    final matchText = {
      if (matching is Map)
        for (final side in const ['left', 'right'])
          if (matching[side] is List)
            for (final o in matching[side] as List)
              if (o is Map && o['id'] is String)
                o['id'] as String: (o['text'] as String?) ?? '',
    };
    List<String> words(Object? ids) => [
      if (ids is List)
        for (final id in ids)
          if (id is String) options[id] ?? matchText[id] ?? id,
    ];
    final type = answer['type'];
    final text = (answer['student_answer'] as String?)?.trim() ?? '';
    return ResultQuestion(
      question: (j['question'] as String?) ?? '',
      points: (j['points'] as num?) ?? 0,
      marks: (j['marks_obtained'] as num?) ?? 0,
      studentAnswer: type == 'text'
          ? [if (text.isNotEmpty) text]
          : words(answer['student_selected']),
      correctAnswer: type == 'text'
          ? const []
          : words(answer['correct_answer']),
      isCorrect: j['is_correct'] as bool?,
      passage: passage,
    );
  }
}

/// `GET /student/exams/:id/result`.
@immutable
class TestResult {
  const TestResult({
    required this.questions,
    this.subject,
    this.submittedAt,
    this.totalScore,
    this.maxScore,
    this.percentage,
    this.grade,
    this.correct = 0,
    this.wrong = 0,
    this.unanswered = 0,
  });

  final String? subject;
  final DateTime? submittedAt;
  final num? totalScore;
  final num? maxScore;
  final num? percentage;
  final String? grade;
  final int correct;
  final int wrong;
  final int unanswered;
  final List<ResultQuestion> questions;

  factory TestResult.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final grade = j['grade'];
    final questions = <ResultQuestion>[];
    if (j['questions'] is List) {
      for (final q in j['questions'] as List) {
        if (q is Map && q['childQuestions'] is List) {
          for (final c in q['childQuestions'] as List) {
            final r = ResultQuestion.fromJson(
              c,
              passage: q['passageText'] as String?,
            );
            if (r != null) questions.add(r);
          }
        } else if (ResultQuestion.fromJson(q) case final r?) {
          questions.add(r);
        }
      }
    }
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return TestResult(
      subject: j['subject'] as String?,
      submittedAt: _time(j['submitted_at']),
      totalScore: j['total_score'] as num?,
      maxScore: j['max_score'] as num?,
      percentage: j['percentage'] as num?,
      grade: grade is Map ? grade['grade'] as String? : null,
      correct: n('correct_answers'),
      wrong: n('wrong_answers'),
      unanswered: n('unanswered'),
      questions: questions,
    );
  }
}

final myTestsProvider = FutureProvider.autoDispose<List<TestItem>>((ref) async {
  ref.watch(workspaceKeyProvider);
  final r = await ref.read(apiClientProvider).get('/student/exams/assigned');
  return TestItem.listOf(r.payload);
}, retry: (retryCount, error) => null);

final classTestsProvider = FutureProvider.autoDispose
    .family<List<TestItem>, String>((ref, classId) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get('/student/exams/class/$classId');
      return TestItem.listOf(r.payload);
    }, retry: (retryCount, error) => null);

final testResultProvider = FutureProvider.autoDispose
    .family<TestResult, String>((ref, id) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get('/student/exams/$id/result');
      return TestResult.fromJson(r.payload);
    }, retry: (retryCount, error) => null);
