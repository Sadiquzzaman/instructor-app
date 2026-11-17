import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// A file on a homework or a hand-in.
@immutable
class HomeworkFile {
  const HomeworkFile(this.id, this.name, this.mime);
  final String id;
  final String? name;
  final String? mime;

  bool get isImage => mime?.startsWith('image/') ?? false;

  static List<HomeworkFile> listOf(Object? j) => [
    if (j is List)
      for (final f in j)
        if (f is Map && f['id'] is String)
          HomeworkFile(
            f['id'] as String,
            f['name'] as String?,
            f['mime'] as String?,
          ),
  ];
}

/// One homework (`/homework/mine`, `/homework/:id`).
@immutable
class Homework {
  const Homework({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.subject,
    this.instructionsHtml,
    this.totalMarks,
    this.dueAt,
    this.attachments = const [],
    this.handedInVersion,
  });

  final String id;
  final String title;

  /// FILE, TEXT or PAPER.
  final String type;

  /// DRAFT, SCHEDULED, PUBLISHED or CANCELLED.
  final String status;
  final String subject;
  final String? instructionsHtml;
  final num? totalMarks;
  final DateTime? dueAt;
  final List<HomeworkFile> attachments;

  /// The student's latest hand-in, if any.
  final int? handedInVersion;

  static Homework? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final subject = j['subject'];
    final instructions = j['instructions'];
    final mine = j['my_submission'];
    return Homework(
      id: j['id'] as String,
      title: (j['title'] as String?) ?? '',
      type: (j['submission_type'] as String?) ?? 'FILE',
      status: (j['status'] as String?) ?? 'PUBLISHED',
      subject: subject is Map ? (subject['name'] as String?) ?? '' : '',
      instructionsHtml: instructions is Map
          ? instructions['html'] as String?
          : null,
      totalMarks: j['total_marks'] as num?,
      dueAt: j['due_at'] is String
          ? DateTime.tryParse(j['due_at'] as String)
          : null,
      attachments: HomeworkFile.listOf(j['attachments']),
      handedInVersion: mine is Map ? (mine['version'] as num?)?.toInt() : null,
    );
  }
}

/// none, overdue, soon (within a day) or later (the web's `dueState`).
String dueStateOf(DateTime? due, [DateTime? now]) {
  if (due == null) return 'none';
  final n = now ?? DateTime.now();
  if (due.isBefore(n)) return 'overdue';
  return due.difference(n) <= const Duration(days: 1) ? 'soon' : 'later';
}

@immutable
class HandIn {
  const HandIn({
    required this.version,
    required this.submittedAt,
    required this.isLate,
    required this.status,
    this.lateMinutes,
    this.text,
    this.files = const [],
  });

  final int version;
  final DateTime? submittedAt;
  final bool isLate;
  final int? lateMinutes;

  /// SUBMITTED, RETURNED or SCORED.
  final String status;
  final String? text;
  final List<HomeworkFile> files;
}

/// The student's score, once the teacher publishes it.
@immutable
class HomeworkScore {
  const HomeworkScore({
    this.rawScore,
    this.penalty = 0,
    this.finalScore,
    this.totalMarks,
    this.percent,
    this.grade,
    this.feedback,
    this.ratings = const {},
    this.isMissing = false,
  });

  final num? rawScore;
  final num penalty;
  final num? finalScore;
  final num? totalMarks;
  final num? percent;
  final String? grade;
  final String? feedback;

  /// neatness, effort, on_time: 1–5.
  final Map<String, num> ratings;
  final bool isMissing;

  static HomeworkScore? fromJson(Object? j) {
    if (j is! Map) return null;
    final grade = j['grade'];
    final ratings = j['ratings'];
    return HomeworkScore(
      rawScore: j['raw_score'] as num?,
      penalty: (j['penalty'] as num?) ?? 0,
      finalScore: j['final_score'] as num?,
      totalMarks: j['total_marks'] as num?,
      percent: j['percent'] as num?,
      grade: grade is Map ? grade['grade'] as String? : null,
      feedback: j['feedback'] as String?,
      ratings: {
        if (ratings is Map)
          for (final MapEntry(:key, :value) in ratings.entries)
            if (key is String && value is num && value > 0) key: value,
      },
      isMissing: j['is_missing'] == true,
    );
  }
}

/// `GET /homework/:id/my-submissions`.
@immutable
class MySubmissions {
  const MySubmissions({
    required this.handIns,
    required this.canSubmit,
    required this.submissionsLeft,
    required this.lateNow,
    required this.maxFiles,
    this.blockedBy,
    this.score,
  });

  /// Newest first.
  final List<HandIn> handIns;
  final bool canSubmit;

  /// Why not, as an error code.
  final String? blockedBy;
  final int submissionsLeft;
  final bool lateNow;
  final int maxFiles;
  final HomeworkScore? score;

  factory MySubmissions.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final subs = j['submissions'];
    final handIns = [
      if (subs is List)
        for (final s in subs)
          if (s is Map)
            HandIn(
              version: (s['version'] as num?)?.toInt() ?? 1,
              submittedAt: s['submitted_at'] is String
                  ? DateTime.tryParse(s['submitted_at'] as String)
                  : null,
              isLate: s['is_late'] == true,
              lateMinutes: (s['late_minutes'] as num?)?.toInt(),
              status: (s['status'] as String?) ?? 'SUBMITTED',
              text: s['text_answer'] as String?,
              files: HomeworkFile.listOf(s['files']),
            ),
    ]..sort((a, b) => b.version.compareTo(a.version));
    return MySubmissions(
      handIns: handIns,
      canSubmit: j['can_submit'] == true,
      blockedBy: j['blocked_by'] as String?,
      submissionsLeft: (j['submissions_left'] as num?)?.toInt() ?? 0,
      lateNow: j['late_now'] == true,
      maxFiles: (j['max_files'] as num?)?.toInt() ?? 10,
      score: HomeworkScore.fromJson(j['score']),
    );
  }
}

class HomeworkRepository {
  HomeworkRepository(this._api);

  final ApiClient _api;

  Future<List<Homework>> mine() async {
    final r = await _api.get('/homework/mine');
    final p = r.payload;
    return [
      if (p is List)
        for (final h in p) ?Homework.fromJson(h),
    ];
  }

  Future<Homework?> get(String id) async =>
      Homework.fromJson((await _api.get('/homework/$id')).payload);

  Future<MySubmissions> mySubmissions(String id) async =>
      MySubmissions.fromJson(
        (await _api.get('/homework/$id/my-submissions')).payload,
      );

  /// Hands in a text answer and/or files (in page order); the answer is the
  /// updated list of hand-ins.
  Future<MySubmissions> submit(
    String id, {
    String? text,
    List<String> fileIds = const [],
  }) async {
    final t = text?.trim() ?? '';
    final r = await _api.post(
      '/homework/$id/submissions',
      data: {'file_ids': fileIds, if (t.isNotEmpty) 'text_answer': t},
    );
    return MySubmissions.fromJson(r.payload);
  }
}

final homeworkRepositoryProvider = Provider<HomeworkRepository>(
  (ref) => HomeworkRepository(ref.watch(apiClientProvider)),
);

final myHomeworkProvider = FutureProvider.autoDispose<List<Homework>>((ref) {
  ref.watch(workspaceKeyProvider);
  return ref.read(homeworkRepositoryProvider).mine();
}, retry: (retryCount, error) => null);

final homeworkProvider = FutureProvider.autoDispose.family<Homework?, String>((
  ref,
  id,
) {
  ref.watch(workspaceKeyProvider);
  return ref.read(homeworkRepositoryProvider).get(id);
}, retry: (retryCount, error) => null);

final mySubmissionsProvider = FutureProvider.autoDispose
    .family<MySubmissions, String>((ref, id) {
      ref.watch(workspaceKeyProvider);
      return ref.read(homeworkRepositoryProvider).mySubmissions(id);
    }, retry: (retryCount, error) => null);
