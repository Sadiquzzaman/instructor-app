import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';

String? _gradeOf(Object? g) => g is Map ? g['grade'] as String? : null;

/// A published paper-exam result (`GET /offline-exams/mine`).
@immutable
class PaperResult {
  const PaperResult({
    required this.id,
    required this.name,
    required this.subject,
    required this.total,
    this.date,
    this.term,
    this.marks,
    this.percent,
    this.grade,
    this.absent = false,
  });

  final String id;
  final String name;
  final String subject;
  final num total;
  final String? date;
  final String? term;
  final num? marks;
  final num? percent;
  final String? grade;
  final bool absent;

  static PaperResult? fromJson(Object? j) {
    if (j is! Map || j['exam'] is! Map) return null;
    final e = j['exam'] as Map;
    if (e['id'] is! String) return null;
    final subject = e['subject'];
    final term = e['term'];
    return PaperResult(
      id: e['id'] as String,
      name: (e['name'] as String?) ?? '',
      subject: subject is Map ? (subject['name'] as String?) ?? '' : '',
      total: (e['total_marks'] as num?) ?? 0,
      date: e['exam_date'] as String?,
      term: term is Map ? term['name'] as String? : null,
      marks: j['marks'] as num?,
      percent: j['percent'] as num?,
      grade: _gradeOf(j['grade']),
      absent: j['is_absent'] == true,
    );
  }
}

/// A score with its parts (exams, homework, attendance, behaviour).
@immutable
class ScoreLine {
  const ScoreLine({
    this.score,
    this.grade,
    this.gpa,
    this.exams,
    this.homework,
    this.attendance,
    this.behaviour,
    this.subject,
  });

  final num? score;
  final String? grade;
  final num? gpa;
  final num? exams;
  final num? homework;
  final num? attendance;
  final num? behaviour;

  /// For a subject's line.
  final String? subject;

  static ScoreLine fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final g = j['grade'];
    final s = j['subject'];
    return ScoreLine(
      score: j['score_pct'] as num?,
      grade: _gradeOf(g),
      gpa: g is Map ? g['gpa'] as num? : null,
      exams: j['exams_pct'] as num?,
      homework: j['homework_pct'] as num?,
      attendance: j['attendance_pct'] as num?,
      behaviour: j['behaviour_pct'] as num?,
      subject: s is Map ? s['name'] as String? : null,
    );
  }
}

typedef ExamLine = ({
  String name,
  String kind,
  String? subject,
  String? date,
  num? marks,
  num total,
  bool absent,
});

/// `GET /scores/students/:me`: the student's own published results.
@immutable
class MyPerformance {
  const MyPerformance({
    required this.overall,
    required this.subjects,
    required this.exams,
    this.position,
    this.classSize = 0,
    this.onTime,
    this.publishedOnly = true,
    this.name,
  });

  /// The student's name (shown when a teacher opens it).
  final String? name;
  final ScoreLine overall;
  final List<ScoreLine> subjects;
  final List<ExamLine> exams;
  final int? position;
  final int classSize;
  final num? onTime;
  final bool publishedOnly;

  factory MyPerformance.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final hw = j['homework'];
    return MyPerformance(
      name: j['student'] is Map
          ? (j['student'] as Map)['full_name'] as String?
          : null,
      overall: ScoreLine.fromJson(j['overall']),
      subjects: [
        if (j['subjects'] is List)
          for (final s in j['subjects'] as List) ScoreLine.fromJson(s),
      ],
      exams: [
        if (j['exams'] is List)
          for (final e in j['exams'] as List)
            if (e is Map)
              (
                name: (e['name'] as String?) ?? '',
                kind: (e['kind'] as String?) ?? 'ONLINE',
                subject: e['subject'] is Map
                    ? (e['subject'] as Map)['name'] as String?
                    : null,
                date: e['date'] as String?,
                marks: e['marks'] as num?,
                total: (e['total'] as num?) ?? 0,
                absent: e['is_absent'] == true,
              ),
      ],
      position: (j['position'] as num?)?.toInt(),
      classSize: (j['class_size'] as num?)?.toInt() ?? 0,
      onTime: hw is Map ? hw['on_time_pct'] as num? : null,
      publishedOnly: j['published_only'] != false,
    );
  }
}

/// A report card in the list (`GET /report-cards/mine`).
@immutable
class ReportCardItem {
  const ReportCardItem({
    required this.id,
    required this.locale,
    this.term,
    this.generatedAt,
  });

  final String id;
  final String locale;
  final String? term;
  final DateTime? generatedAt;

  static ReportCardItem? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final term = j['term'];
    return ReportCardItem(
      id: j['id'] as String,
      locale: (j['locale'] as String?) ?? 'en',
      term: term is Map ? term['name'] as String? : null,
      generatedAt: j['generated_at'] is String
          ? DateTime.tryParse(j['generated_at'] as String)
          : null,
    );
  }
}

/// `GET /report-cards/:id`: the card as it was made (its snapshot).
@immutable
class ReportCard {
  const ReportCard({
    required this.organization,
    required this.overall,
    required this.subjects,
    this.term,
    this.student,
    this.className,
    this.position,
    this.classSize = 0,
    this.showPosition = false,
    this.present,
    this.absent,
    this.leave,
    this.teacherRemark,
    this.principalRemark,
  });

  final String organization;
  final String? term;
  final String? student;
  final String? className;
  final ScoreLine overall;
  final List<ScoreLine> subjects;
  final int? position;
  final int classSize;
  final bool showPosition;
  final int? present;
  final int? absent;
  final int? leave;
  final String? teacherRemark;
  final String? principalRemark;

  factory ReportCard.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final snap = j['snapshot'] is Map
        ? j['snapshot'] as Map
        : const <String, Object?>{};
    final page = snap['page'] is Map
        ? snap['page'] as Map
        : const <String, Object?>{};
    final org = snap['organization'];
    final student = page['student'];
    final section = page['section'];
    final term = j['term'];
    final att = page['attendance'] is Map ? page['attendance'] as Map : null;
    final counts = att?['counts'] is Map ? att!['counts'] as Map : null;
    int? n(String k) => (counts?[k] as num?)?.toInt();
    return ReportCard(
      organization: org is Map ? (org['name'] as String?) ?? '' : '',
      term: term is Map ? term['name'] as String? : null,
      student: student is Map ? student['full_name'] as String? : null,
      className: section is Map
          ? '${section['class_name'] ?? ''} ${section['name'] ?? ''}'.trim()
          : null,
      overall: ScoreLine.fromJson(page['overall']),
      subjects: [
        if (page['subjects'] is List)
          for (final s in page['subjects'] as List) ScoreLine.fromJson(s),
      ],
      position: (page['position'] as num?)?.toInt(),
      classSize: (page['class_size'] as num?)?.toInt() ?? 0,
      showPosition: snap['show_position'] == true,
      present: n('present'),
      absent: n('absent'),
      leave: n('leave'),
      teacherRemark: j['teacher_remark'] as String?,
      principalRemark: j['principal_remark'] as String?,
    );
  }
}

final myPaperResultsProvider = FutureProvider.autoDispose<List<PaperResult>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/offline-exams/mine'))
      .payload;
  return [
    if (p is List)
      for (final r in p) ?PaperResult.fromJson(r),
  ];
}, retry: (retryCount, error) => null);

final myPerformanceProvider = FutureProvider.autoDispose<MyPerformance>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final me = ref.read(sessionProvider)?.userId ?? '';
  final r = await ref.read(apiClientProvider).get('/scores/students/$me');
  return MyPerformance.fromJson(r.payload);
}, retry: (retryCount, error) => null);

/// A student's results for their teacher (`GET /scores/students/:id`).
final studentPerformanceProvider = FutureProvider.autoDispose
    .family<MyPerformance, String>((ref, id) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref.read(apiClientProvider).get('/scores/students/$id');
      return MyPerformance.fromJson(r.payload);
    }, retry: (retryCount, error) => null);

final myReportCardsProvider = FutureProvider.autoDispose<List<ReportCardItem>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/report-cards/mine'))
      .payload;
  return [
    if (p is List)
      for (final c in p) ?ReportCardItem.fromJson(c),
  ];
}, retry: (retryCount, error) => null);

final reportCardProvider = FutureProvider.autoDispose
    .family<ReportCard, String>((ref, id) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref.read(apiClientProvider).get('/report-cards/$id');
      return ReportCard.fromJson(r.payload);
    }, retry: (retryCount, error) => null);
