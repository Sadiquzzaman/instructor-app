import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

String _sectionName(Object? s) {
  final m = s is Map ? s : const <String, Object?>{};
  return '${m['class_name'] ?? ''} ${m['name'] ?? ''}'.trim();
}

/// A section the caller may see (`GET /attendance/register/sections`).
typedef ReportSection = ({String id, String name, String mode});

/// A student's day in the reports: PRESENT, LATE, ABSENT, LEAVE or WAITING,
/// and how many classes they missed that day while coming to others.
typedef DayMark = ({String status, int missed});

DayMark? _day(Object? j) => j is Map && j['status'] is String
    ? (status: j['status'] as String, missed: _int(j['missed']))
    : null;

/// The group a student's day falls in on the daily summary (null: no class
/// counted for them that day).
String? dailyGroup(DayMark? d) {
  if (d == null) return null;
  if ((d.status == 'PRESENT' || d.status == 'LATE') && d.missed > 0) {
    return 'MISSED_SOME';
  }
  return d.status;
}

/// The daily summary's groups, most urgent first.
const dailyGroups = [
  'ABSENT',
  'MISSED_SOME',
  'LATE',
  'LEAVE',
  'WAITING',
  'PRESENT',
];

typedef DailyStudent = ({String id, String name, DayMark? day});

typedef DailyClass = ({String start, String end, bool cancelled});

/// One section on the daily summary.
@immutable
class DailySection {
  const DailySection({
    required this.id,
    required this.name,
    required this.mode,
    required this.classes,
    required this.studentCount,
    required this.students,
  });

  final String id;
  final String name;
  final String mode;
  final List<DailyClass> classes;
  final int studentCount;
  final List<DailyStudent> students;
}

/// `GET /attendance/reports/daily`.
@immutable
class DailyReport {
  const DailyReport({required this.date, required this.sections, this.closed});

  final String date;
  final ClosedDay? closed;
  final List<DailySection> sections;

  factory DailyReport.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final s = j['sections'];
    return DailyReport(
      date: (j['date'] as String?) ?? '',
      closed: ClosedDay.fromJson(j['closed']),
      sections: [
        if (s is List)
          for (final x in s)
            if (x is Map && x['section'] is Map)
              DailySection(
                id: ((x['section'] as Map)['id'] as String?) ?? '',
                name: _sectionName(x['section']),
                mode: (x['mode'] as String?) ?? 'CHECK_IN',
                classes: [
                  if (x['classes'] is List)
                    for (final c in x['classes'] as List)
                      if (c is Map)
                        (
                          start: (c['start_time'] as String?) ?? '',
                          end: (c['end_time'] as String?) ?? '',
                          cancelled: c['cancelled'] == true,
                        ),
                ],
                studentCount: _int(
                  x['counts'] is Map ? (x['counts'] as Map)['students'] : null,
                ),
                students: [
                  if (x['students'] is List)
                    for (final st in x['students'] as List)
                      if (st is Map && st['id'] is String)
                        (
                          id: st['id'] as String,
                          name: (st['full_name'] as String?) ?? '',
                          day: _day(st['day']),
                        ),
                ],
              ),
      ],
    );
  }
}

typedef MonthCounts = ({int present, int late, int absent, int leave});

MonthCounts _counts(Object? j) {
  final m = j is Map ? j : const <String, Object?>{};
  return (
    present: _int(m['present']),
    late: _int(m['late']),
    absent: _int(m['absent']),
    leave: _int(m['leave']),
  );
}

/// A student on the monthly register: a mark per class day, counts and %.
typedef MonthStudent = ({
  String id,
  String name,
  String? rollNo,
  List<DayMark?> days,
  MonthCounts counts,
  num? percent,
});

/// `GET /attendance/reports/sections/:id/month`.
@immutable
class MonthReport {
  const MonthReport({
    required this.month,
    required this.days,
    required this.classCount,
    required this.students,
    this.percent,
  });

  final String month;

  /// The class days, "YYYY-MM-DD".
  final List<String> days;
  final int classCount;
  final List<MonthStudent> students;
  final num? percent;

  factory MonthReport.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    return MonthReport(
      month: (j['month'] as String?) ?? '',
      days: [
        if (j['days'] is List)
          for (final d in j['days'] as List)
            if (d is Map && d['date'] is String) d['date'] as String,
      ],
      classCount: j['classes'] is List ? (j['classes'] as List).length : 0,
      percent: j['attendance_pct'] as num?,
      students: [
        if (j['students'] is List)
          for (final s in j['students'] as List)
            if (s is Map && s['id'] is String)
              (
                id: s['id'] as String,
                name: (s['full_name'] as String?) ?? '',
                rollNo: s['roll_no'] as String?,
                days: [
                  if (s['days'] is List)
                    for (final d in s['days'] as List) _day(d),
                ],
                counts: _counts(s['counts']),
                percent: s['attendance_pct'] as num?,
              ),
      ],
    );
  }
}

/// The sections the caller may see (all for owners and admins, the ones
/// they teach for teachers).
final reportSectionsProvider = FutureProvider.autoDispose<List<ReportSection>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p =
      (await ref.read(apiClientProvider).get('/attendance/register/sections'))
          .payload;
  return [
    if (p is List)
      for (final s in p)
        if (s is Map && s['id'] is String)
          (
            id: s['id'] as String,
            name: _sectionName(s),
            mode: (s['mode'] as String?) ?? 'CHECK_IN',
          ),
  ];
}, retry: (retryCount, error) => null);

/// The daily summary for a date (null: today) and a section (null: all).
final dailyReportProvider = FutureProvider.autoDispose
    .family<DailyReport, ({String? date, String? sectionId})>((ref, k) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/attendance/reports/daily',
            query: {'date': ?k.date, 'section_id': ?k.sectionId},
          );
      return DailyReport.fromJson(r.payload);
    }, retry: (retryCount, error) => null);

/// A section's monthly register ("YYYY-MM").
final monthReportProvider = FutureProvider.autoDispose
    .family<MonthReport, ({String sectionId, String month})>((ref, k) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/attendance/reports/sections/${k.sectionId}/month',
            query: {'month': k.month},
          );
      return MonthReport.fromJson(r.payload);
    }, retry: (retryCount, error) => null);
