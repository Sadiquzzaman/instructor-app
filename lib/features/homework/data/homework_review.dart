import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/homework/data/homework.dart';

/// The rating kinds a teacher can give, in order (the web's RATING_KEYS).
const ratingKeys = ['neatness', 'effort', 'on_time'];

/// One student's row on a homework's review (`GET /homework/:id/grid`).
@immutable
class ReviewRow {
  const ReviewRow({
    required this.studentId,
    required this.name,
    required this.versions,
    this.rollNo,
    this.latest,
    this.score,
  });

  final String studentId;
  final String name;
  final String? rollNo;

  /// Their latest hand-in; null when they have not handed in.
  final HandIn? latest;
  final int versions;
  final HomeworkScore? score;

  /// "3. Karim Hasan" (the web's `studentName`).
  String get label =>
      rollNo == null || rollNo!.isEmpty ? name : '$rollNo. $name';
}

/// A homework's review: counts and a row per student.
@immutable
class HomeworkReview {
  const HomeworkReview({
    required this.rows,
    required this.students,
    required this.handedIn,
    required this.late,
    required this.missing,
    required this.scored,
    this.totalMarks,
    this.scoresPublishedAt,
  });

  final List<ReviewRow> rows;
  final int students;
  final int handedIn;
  final int late;
  final int missing;
  final int scored;
  final num? totalMarks;
  final DateTime? scoresPublishedAt;

  factory HomeworkReview.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final h = j['homework'] is Map
        ? j['homework'] as Map
        : const <String, Object?>{};
    final c = j['counts'] is Map
        ? j['counts'] as Map
        : const <String, Object?>{};
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    return HomeworkReview(
      totalMarks: h['total_marks'] as num?,
      scoresPublishedAt: h['scores_published_at'] is String
          ? DateTime.tryParse(h['scores_published_at'] as String)
          : null,
      students: n(c['students']),
      handedIn: n(c['handed_in']),
      late: n(c['late']),
      missing: n(c['missing']),
      scored: n(c['scored']),
      rows: [
        if (j['rows'] is List)
          for (final r in j['rows'] as List)
            if (r is Map && r['student'] is Map)
              ReviewRow(
                studentId: ((r['student'] as Map)['id'] as String?) ?? '',
                name: ((r['student'] as Map)['full_name'] as String?) ?? '',
                rollNo: (r['student'] as Map)['roll_no'] as String?,
                latest: r['latest'] is Map
                    ? HandIn.fromJson(r['latest'] as Map)
                    : null,
                versions: n(r['versions']),
                score: HomeworkScore.fromJson(r['score']),
              ),
      ],
    );
  }
}

/// A score being typed: text while typing, sent as a number.
@immutable
class ScoreDraft {
  const ScoreDraft({
    this.raw = '',
    this.feedback = '',
    this.missing = false,
    this.ratings = const {},
  });

  factory ScoreDraft.of(ReviewRow r) => ScoreDraft(
    raw: r.score?.rawScore == null ? '' : _plain(r.score!.rawScore!),
    feedback: r.score?.feedback ?? '',
    missing: r.score?.isMissing ?? false,
    ratings: {
      for (final MapEntry(:key, :value)
          in r.score?.ratings.entries ?? const <MapEntry<String, num>>[])
        key: value.toInt(),
    },
  );

  final String raw;
  final String feedback;
  final bool missing;
  final Map<String, int> ratings;

  static String _plain(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  ScoreDraft copyWith({
    String? raw,
    String? feedback,
    bool? missing,
    Map<String, int>? ratings,
  }) => ScoreDraft(
    raw: raw ?? this.raw,
    feedback: feedback ?? this.feedback,
    missing: missing ?? this.missing,
    ratings: ratings ?? this.ratings,
  );

  bool same(ScoreDraft o) =>
      raw == o.raw &&
      feedback == o.feedback &&
      missing == o.missing &&
      mapEquals(ratings, o.ratings);

  /// A row of `PUT /homework/:id/scores` (the web's `inputOf`).
  Map<String, Object?> toJson(String studentId, {required bool scored}) => {
    'student_id': studentId,
    if (scored)
      'raw_score': raw.trim().isEmpty || missing
          ? null
          : num.parse(raw.trim().replaceAll(',', '.')),
    'feedback': feedback.trim().isEmpty ? null : feedback.trim(),
    'is_missing': missing,
    'ratings': ratings.isEmpty ? null : ratings,
  };
}

/// A score must be a number from 0 to [total] with at most two decimals
/// (the web's `scoreProblem`); empty is fine.
bool scoreProblem(String value, num? total) {
  final v = value.trim().replaceAll(',', '.');
  if (v.isEmpty) return false;
  final n = num.tryParse(v);
  if (n == null || n < 0 || (total != null && n > total)) return true;
  return (n * 100).round() != n * 100;
}

extension HomeworkReviewCalls on HomeworkRepository {
  Future<HomeworkReview> review(String id) async =>
      HomeworkReview.fromJson((await api.get('/homework/$id/grid')).payload);

  /// Every version a student handed in, newest first.
  Future<List<HandIn>> versions(String id, String submissionId) async {
    final p = (await api.get('/homework/$id/submissions/$submissionId'))
        .payload;
    final v = p is Map ? p['versions'] : null;
    return [
      if (v is List)
        for (final s in v)
          if (s is Map) HandIn.fromJson(s),
    ]..sort((a, b) => b.version.compareTo(a.version));
  }

  Future<HomeworkReview> saveScores(
    String id,
    List<Map<String, Object?>> rows,
  ) async => HomeworkReview.fromJson(
    (await api.put('/homework/$id/scores', data: {'rows': rows})).payload,
  );

  Future<HomeworkReview> returnForRedo(
    String id,
    String submissionId, {
    String note = '',
  }) async => HomeworkReview.fromJson(
    (await api.post(
      '/homework/$id/submissions/$submissionId/return',
      data: {if (note.trim().isNotEmpty) 'note': note.trim()},
    )).payload,
  );

  Future<HomeworkReview> publishScores(String id) async =>
      HomeworkReview.fromJson(
        (await api.post(
          '/homework/$id/publish-scores',
          data: const <String, Object>{},
        )).payload,
      );

  /// Reminds those who have not handed in (and texts their guardians);
  /// returns how many students and texts.
  Future<({int students, int sms})> remindMissing(
    String id, {
    bool smsGuardians = false,
  }) async {
    final p = (await api.post(
      '/homework/$id/remind-missing',
      data: {'sms_guardians': smsGuardians},
    )).payload;
    final m = p is Map ? p : const <String, Object?>{};
    return (
      students: (m['students'] as num?)?.toInt() ?? 0,
      sms: (m['guardian_sms'] as num?)?.toInt() ?? 0,
    );
  }
}

final homeworkReviewProvider = FutureProvider.autoDispose
    .family<HomeworkReview, String>((ref, id) {
      ref.watch(workspaceKeyProvider);
      return ref.read(homeworkRepositoryProvider).review(id);
    }, retry: (retryCount, error) => null);
