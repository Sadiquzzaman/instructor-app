import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

/// A test on the grading list (`GET /exams/grading/list`).
typedef GradingItem = ({
  String id,
  String name,
  String? subject,
  String? className,
  DateTime? endedAt,
  int submitted,
  int graded,
  int pending,
  num? averagePercent,

  /// NEEDS_GRADING, GRADED or PUBLISHED.
  String status,
});

/// A submission on a test's grading page.
typedef GradingSubmission = ({
  String id,
  String? name,
  String? contact,
  DateTime? submittedAt,
  num? score,
  num? maxScore,
  num? percent,

  /// PENDING or GRADED.
  String gradingStatus,
  int flags,
});

/// `GET /exams/grading/:examId`: the test, its counts and submissions.
@immutable
class GradingSummary {
  const GradingSummary({
    required this.name,
    required this.status,
    required this.published,
    required this.students,
    required this.submissions,
    required this.graded,
    required this.pending,
    required this.rows,
    this.subject,
    this.className,
  });

  final String name;
  final String? subject;
  final String? className;
  final String status;
  final bool published;
  final int students;
  final int submissions;
  final int graded;
  final int pending;
  final List<GradingSubmission> rows;

  /// Results can be published once every submission is graded.
  bool get canPublish => !published && pending == 0 && submissions > 0;

  factory GradingSummary.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final e = j['exam'] is Map ? j['exam'] as Map : const <String, Object?>{};
    final s = j['stats'] is Map ? j['stats'] as Map : const <String, Object?>{};
    return GradingSummary(
      name: (e['test_name'] as String?) ?? '',
      subject: e['subject'] as String?,
      className: e['class_name'] as String?,
      status: (e['grading_status'] as String?) ?? 'NEEDS_GRADING',
      published: e['is_result_published'] == true,
      students: _int(s['total_students']),
      submissions: _int(s['submissions']),
      graded: _int(s['graded']),
      pending: _int(s['pending']),
      rows: [
        if (j['submissions'] is List)
          for (final r in j['submissions'] as List)
            if (r is Map && r['submission_id'] is String)
              (
                id: r['submission_id'] as String,
                name: r['student_name'] as String?,
                contact: (r['email'] as String?) ?? (r['phone'] as String?),
                submittedAt: _time(r['submitted_at']),
                score: r['total_score'] as num?,
                maxScore: r['max_score'] as num?,
                percent: r['percentage'] as num?,
                gradingStatus: (r['grading_status'] as String?) ?? 'PENDING',
                flags: r['proctoring_summary'] is Map
                    ? _int((r['proctoring_summary'] as Map)['total_violations'])
                    : 0,
              ),
      ],
    );
  }
}

/// One question on a submission.
@immutable
class GradedQuestion {
  const GradedQuestion({
    required this.id,
    required this.text,
    required this.points,
    required this.marks,
    required this.manual,
    this.answer,
    this.feedback,
    this.correct,
    this.passage,
    this.options = const {},
    this.chosen = const [],
  });

  final String id;
  final String text;
  final num points;
  final num marks;

  /// Marked by hand: a written answer.
  final bool manual;

  /// A written answer.
  final String? answer;
  final String? feedback;

  /// Objective questions: right, wrong, or null when not answered or manual.
  final bool? correct;

  /// The passage this question belongs to, if any.
  final String? passage;

  /// Option ids to their text, and the ones the student chose.
  final Map<String, String> options;
  final List<String> chosen;

  static GradedQuestion? fromJson(Object? json, {String? passage}) {
    if (json is! Map || json['question_id'] is! String) return null;
    final a = json['answer'] is Map
        ? json['answer'] as Map
        : const <String, Object?>{};
    final manual = a['type'] == 'text';
    return GradedQuestion(
      id: json['question_id'] as String,
      text: (json['question'] as String?) ?? '',
      points: (json['points'] as num?) ?? 0,
      marks: (json['marks_obtained'] as num?) ?? 0,
      manual: manual,
      answer: manual ? (a['student_answer'] as String?) : null,
      feedback: manual ? (a['explanation'] as String?) : null,
      correct: json['is_correct'] as bool?,
      passage: passage,
      options: {
        if (json['options'] is List)
          for (final o in json['options'] as List)
            if (o is Map && o['id'] is String)
              o['id'] as String: (o['text'] as String?) ?? '',
      },
      chosen: [
        if (a['student_selected'] is List)
          for (final s in a['student_selected'] as List)
            if (s is String) s,
      ],
    );
  }
}

/// `GET /exams/grading/:examId/submissions/:id`.
@immutable
class SubmissionForGrading {
  const SubmissionForGrading({
    required this.name,
    required this.score,
    required this.maxScore,
    required this.questions,
    required this.manualTotal,
    required this.manualGraded,
  });

  final String name;
  final num score;
  final num maxScore;
  final List<GradedQuestion> questions;
  final int manualTotal;
  final int manualGraded;

  factory SubmissionForGrading.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final s = j['submission'] is Map
        ? j['submission'] as Map
        : const <String, Object?>{};
    final t = j['totals'] is Map
        ? j['totals'] as Map
        : const <String, Object?>{};
    return SubmissionForGrading(
      name: (s['student_name'] as String?) ?? '',
      score: (s['total_score'] as num?) ?? 0,
      maxScore: (s['max_score'] as num?) ?? 0,
      manualTotal: _int(t['manual_total_count']),
      manualGraded: _int(t['manual_graded_count']),
      questions: [
        if (j['questions'] is List)
          for (final q in j['questions'] as List)
            if (q is Map && q['type'] == 'passage-question')
              for (final c in (q['childQuestions'] as List?) ?? const [])
                ?GradedQuestion.fromJson(
                  c,
                  passage: q['passageText'] as String?,
                )
            else
              ?GradedQuestion.fromJson(q),
      ],
    );
  }
}

class GradingRepository {
  GradingRepository(this._api);

  final ApiClient _api;

  /// [status]: null for all, NEEDS_GRADING, GRADED or PUBLISHED.
  Future<List<GradingItem>> list(String? status) async {
    final p = (await _api.get(
      '/exams/grading/list',
      query: {'status': ?status, 'limit': 100},
    )).payload;
    return [
      if (p is List)
        for (final i in p)
          if (i is Map && i['id'] is String)
            (
              id: i['id'] as String,
              name: (i['test_name'] as String?) ?? '',
              subject: i['subject'] as String?,
              className: i['class_name'] as String?,
              endedAt: _time(i['exam_end_time']),
              submitted: _int(i['submitted_count']),
              graded: _int(i['graded_count']),
              pending: _int(i['pending_count']),
              averagePercent: i['average_percentage'] as num?,
              status: (i['grading_status'] as String?) ?? 'NEEDS_GRADING',
            ),
    ];
  }

  Future<GradingSummary> summary(String examId) async =>
      GradingSummary.fromJson(
        (await _api.get(
          '/exams/grading/$examId',
          query: {'limit': 100},
        )).payload,
      );

  Future<SubmissionForGrading> submission(String examId, String id) async =>
      SubmissionForGrading.fromJson(
        (await _api.get('/exams/grading/$examId/submissions/$id')).payload,
      );

  /// Saves marks (and feedback) for written answers.
  Future<void> save(
    String examId,
    String id,
    List<({String questionId, num marks, String feedback})> grades,
  ) => _api.patch(
    '/exams/grading/$examId/submissions/$id',
    data: {
      'grades': [
        for (final g in grades)
          {
            'question_id': g.questionId,
            'marks_obtained': g.marks,
            if (g.feedback.trim().isNotEmpty) 'explanation': g.feedback.trim(),
          },
      ],
    },
  );

  Future<void> publish(String examId) => _api.post(
    '/exams/grading/$examId/publish',
    data: const <String, Object>{},
  );
}

final gradingRepositoryProvider = Provider<GradingRepository>(
  (ref) => GradingRepository(ref.watch(apiClientProvider)),
);

final gradingListProvider = FutureProvider.autoDispose
    .family<List<GradingItem>, String?>((ref, status) {
      ref.watch(workspaceKeyProvider);
      return ref.read(gradingRepositoryProvider).list(status);
    }, retry: (retryCount, error) => null);

final gradingSummaryProvider = FutureProvider.autoDispose
    .family<GradingSummary, String>((ref, examId) {
      ref.watch(workspaceKeyProvider);
      return ref.read(gradingRepositoryProvider).summary(examId);
    }, retry: (retryCount, error) => null);

final submissionForGradingProvider = FutureProvider.autoDispose
    .family<SubmissionForGrading, ({String examId, String id})>((ref, k) {
      ref.watch(workspaceKeyProvider);
      return ref.read(gradingRepositoryProvider).submission(k.examId, k.id);
    }, retry: (retryCount, error) => null);
