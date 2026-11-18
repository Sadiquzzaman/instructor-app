import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

typedef PersonRef = ({String id, String name});

PersonRef _person(Object? j) => j is Map
    ? (id: (j['id'] as String?) ?? '', name: (j['full_name'] as String?) ?? '')
    : (id: '', name: '');

num _n(Object? v) => (v as num?) ?? 0;

/// A submission on the plagiarism report.
typedef SimilarityRow = ({
  String submissionId,
  PersonRef student,
  int words,

  /// TOO_SHORT, NO_TEXT, HANDWRITTEN_IMAGE or FILE_NOT_READ.
  String? notChecked,
  num percent,

  /// HIGH, MEDIUM or LOW.
  String? level,
  List<({String matchId, PersonRef student, num percent})> mostSimilar,
});

/// A pair of similar submissions, and the teacher's review.
typedef SimilarityPair = ({
  String id,
  PersonRef a,
  PersonRef b,
  num score,
  String level,

  /// OK or COPIED.
  String? decision,
});

/// `GET /integrity/checks/latest`, `POST /integrity/checks`.
@immutable
class SimilarityReport {
  const SimilarityReport({
    required this.rows,
    required this.pairs,
    required this.high,
    required this.medium,
    required this.minWords,
    this.ranAt,
    this.compared = 0,
  });

  final DateTime? ranAt;
  final int compared;
  final num high;
  final num medium;
  final num minWords;
  final List<SimilarityRow> rows;
  final List<SimilarityPair> pairs;

  factory SimilarityReport.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final c = j['check'] is Map ? j['check'] as Map : null;
    final t = j['thresholds'] is Map
        ? j['thresholds'] as Map
        : const <String, Object?>{};
    return SimilarityReport(
      ranAt: c?['ran_at'] is String
          ? DateTime.tryParse(c!['ran_at'] as String)
          : null,
      compared: (c?['submissions'] as num?)?.toInt() ?? 0,
      high: _n(t['high']),
      medium: _n(t['medium']),
      minWords: _n(t['min_words']),
      rows: [
        if (j['submissions'] is List)
          for (final s in j['submissions'] as List)
            if (s is Map)
              (
                submissionId: (s['submission_id'] as String?) ?? '',
                student: _person(s['student']),
                words: (s['words'] as num?)?.toInt() ?? 0,
                notChecked: s['not_checked'] as String?,
                percent: _n(s['percent']),
                level: s['level'] as String?,
                mostSimilar: [
                  if (s['most_similar'] is List)
                    for (final m in s['most_similar'] as List)
                      if (m is Map)
                        (
                          matchId: (m['match_id'] as String?) ?? '',
                          student: _person(m['student']),
                          percent: _n(m['percent']),
                        ),
                ],
              ),
      ],
      pairs: [
        if (j['matches'] is List)
          for (final m in j['matches'] as List)
            if (m is Map)
              (
                id: (m['id'] as String?) ?? '',
                a: _person(m['a'] is Map ? (m['a'] as Map)['student'] : null),
                b: _person(m['b'] is Map ? (m['b'] as Map)['student'] : null),
                score: _n(m['score']),
                level: (m['level'] as String?) ?? 'LOW',
                decision: m['review_decision'] as String?,
              ),
      ],
    );
  }
}

/// One side of a match: the student's text and the shared passages.
typedef MatchSide = ({
  PersonRef student,
  String text,
  List<({int start, int end})> spans,
  num percent,
});

/// `GET /integrity/matches/:id`: two texts side by side and the review.
@immutable
class SimilarityMatch {
  const SimilarityMatch({
    required this.a,
    required this.b,
    required this.score,
    required this.level,
    this.decision,
    this.note,
    this.reviewedAt,
  });

  final MatchSide a;
  final MatchSide b;
  final num score;
  final String level;
  final String? decision;
  final String? note;
  final DateTime? reviewedAt;

  static MatchSide _side(Object? j) {
    final m = j is Map ? j : const <String, Object?>{};
    return (
      student: _person(m['student']),
      text: (m['text'] as String?) ?? '',
      spans: [
        if (m['spans'] is List)
          for (final s in m['spans'] as List)
            if (s is Map)
              (
                start: (s['start'] as num?)?.toInt() ?? 0,
                end: (s['end'] as num?)?.toInt() ?? 0,
              ),
      ],
      percent: _n(m['percent']),
    );
  }

  factory SimilarityMatch.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    return SimilarityMatch(
      a: _side(j['a']),
      b: _side(j['b']),
      score: _n(j['score']),
      level: (j['level'] as String?) ?? 'LOW',
      decision: j['review_decision'] as String?,
      note: j['review_note'] as String?,
      reviewedAt: j['reviewed_at'] is String
          ? DateTime.tryParse(j['reviewed_at'] as String)
          : null,
    );
  }
}

/// [text] cut into plain and shared pieces (the web's `Marked`).
List<({String text, bool marked})> markedPieces(
  String text,
  List<({int start, int end})> spans,
) {
  final out = <({String text, bool marked})>[];
  var at = 0;
  final sorted = [...spans]..sort((x, y) => x.start.compareTo(y.start));
  for (final s in sorted) {
    final start = s.start.clamp(at, text.length);
    final end = s.end.clamp(start, text.length);
    if (start > at) out.add((text: text.substring(at, start), marked: false));
    if (end > start) out.add((text: text.substring(start, end), marked: true));
    at = end;
  }
  if (at < text.length) out.add((text: text.substring(at), marked: false));
  return out;
}

class PlagiarismRepository {
  PlagiarismRepository(this._api);

  final ApiClient _api;

  Future<SimilarityReport> latest(String homeworkId) async =>
      SimilarityReport.fromJson(
        (await _api.get(
          '/integrity/checks/latest',
          query: {'scope_type': 'HOMEWORK', 'scope_id': homeworkId},
        )).payload,
      );

  Future<SimilarityReport> run(String homeworkId) async =>
      SimilarityReport.fromJson(
        (await _api.post(
          '/integrity/checks',
          data: {'scope_type': 'HOMEWORK', 'scope_id': homeworkId},
        )).payload,
      );

  Future<SimilarityMatch> match(String id) async => SimilarityMatch.fromJson(
    (await _api.get('/integrity/matches/$id')).payload,
  );

  /// "Reviewed — OK" (OK) or "Copied" (COPIED), with an optional note.
  Future<SimilarityMatch> review(
    String id, {
    required String decision,
    String note = '',
  }) async => SimilarityMatch.fromJson(
    (await _api.put(
      '/integrity/matches/$id/review',
      data: {
        'decision': decision,
        if (note.trim().isNotEmpty) 'note': note.trim(),
      },
    )).payload,
  );
}

final plagiarismRepositoryProvider = Provider<PlagiarismRepository>(
  (ref) => PlagiarismRepository(ref.watch(apiClientProvider)),
);

final similarityReportProvider = FutureProvider.autoDispose
    .family<SimilarityReport, String>((ref, homeworkId) {
      ref.watch(workspaceKeyProvider);
      return ref.read(plagiarismRepositoryProvider).latest(homeworkId);
    }, retry: (retryCount, error) => null);

final similarityMatchProvider = FutureProvider.autoDispose
    .family<SimilarityMatch, String>((ref, id) {
      ref.watch(workspaceKeyProvider);
      return ref.read(plagiarismRepositoryProvider).match(id);
    }, retry: (retryCount, error) => null);
