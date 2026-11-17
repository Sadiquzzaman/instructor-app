import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/cache/read_cache.dart';
import 'package:instructor_app/core/location/locator.dart';
import 'package:instructor_app/core/time/org_time.dart';

/// PRESENT, LATE, ABSENT or LEAVE, with how the person checked in.
@immutable
class AttendanceRecord {
  const AttendanceRecord({required this.status, this.lateMinutes, this.flag});

  final String status;
  final int? lateMinutes;

  /// EDGE_ACCURACY or IMPOSSIBLE_JUMP: saved, but the teacher may check it.
  final String? flag;

  static AttendanceRecord? fromJson(Object? j) =>
      j is Map && j['status'] is String
      ? AttendanceRecord(
          status: j['status'] as String,
          lateMinutes: (j['late_minutes'] as num?)?.toInt(),
          flag: j['flag'] as String?,
        )
      : null;
}

/// "Mathematics · Class 6 A", or "Class 6 A" for a whole-section class
/// (the web's `classLabel`).
String classLabelOf(Object? section, Object? subject) {
  final s = section is Map ? section : const <String, Object?>{};
  final name = '${s['class_name'] ?? ''} ${s['name'] ?? ''}'.trim();
  final sub = subject is Map ? subject['name'] as String? : null;
  return sub != null && sub.isNotEmpty ? '$sub · $name' : name;
}

/// One of the person's classes today (`GET /attendance/me/today`).
@immutable
class MyClass {
  const MyClass({
    required this.slotId,
    required this.label,
    required this.role,
    required this.classType,
    required this.mode,
    required this.startTime,
    required this.endTime,
    required this.state,
    required this.needsLocation,
    required this.canCheckIn,
    this.opensAt,
    this.endsAt,
    this.blocked,
    this.record,
  });

  final String slotId;
  final String label;

  /// STUDENT or TEACHER.
  final String role;

  /// IN_PERSON or ONLINE.
  final String classType;

  /// How attendance is kept (PAPER_REGISTER means on paper).
  final String mode;

  /// "09:00" style times of day.
  final String startTime;
  final String endTime;
  final DateTime? opensAt;
  final DateTime? endsAt;

  /// UPCOMING, OPEN or CLOSED.
  final String state;
  final bool needsLocation;

  /// CLOSED_DAY, CANCELLED, PAPER_REGISTER, NO_PIN or null.
  final String? blocked;
  final bool canCheckIn;
  final AttendanceRecord? record;

  /// What the class shows today (the web's `todayStatus`): cancelled, its
  /// record, or where its check-in window stands.
  String get status {
    if (blocked == 'CANCELLED') return 'CANCELLED';
    if (record != null) return record!.status;
    if (blocked == 'CLOSED_DAY') return 'CLOSED_DAY';
    if (state == 'OPEN') return 'OPEN';
    if (state == 'UPCOMING') return 'UPCOMING';
    return mode == 'PAPER_REGISTER' ? 'NOT_RECORDED' : 'ABSENT';
  }

  static MyClass? fromJson(Object? j) {
    if (j is! Map || j['slot_id'] is! String) return null;
    DateTime? time(String k) =>
        j[k] is String ? DateTime.tryParse(j[k] as String) : null;
    return MyClass(
      slotId: j['slot_id'] as String,
      label: classLabelOf(j['section'], j['subject']),
      role: (j['role'] as String?) ?? 'STUDENT',
      classType: (j['class_type'] as String?) ?? 'IN_PERSON',
      mode: (j['mode'] as String?) ?? '',
      startTime: (j['start_time'] as String?) ?? '',
      endTime: (j['end_time'] as String?) ?? '',
      opensAt: time('opens_at'),
      endsAt: time('ends_at'),
      state: (j['state'] as String?) ?? 'CLOSED',
      needsLocation: j['needs_location'] == true,
      blocked: j['blocked'] as String?,
      canCheckIn: j['can_check_in'] == true,
      record: AttendanceRecord.fromJson(j['record']),
    );
  }
}

/// A weekly off day or holiday.
@immutable
class ClosedDay {
  const ClosedDay(this.reason, this.holidayName);
  final String reason;
  final String? holidayName;

  static ClosedDay? fromJson(Object? j) => j is Map && j['reason'] is String
      ? ClosedDay(j['reason'] as String, j['holiday_name'] as String?)
      : null;
}

@immutable
class MyToday {
  const MyToday({
    required this.date,
    required this.classes,
    this.closed,
    this.onLeave = false,
    this.savedAt,
  });

  final String date;
  final List<MyClass> classes;
  final ClosedDay? closed;

  /// On approved leave today: classes count as Leave unless they check in.
  final bool onLeave;

  /// Set when there was no connection and this is the copy saved then:
  /// shown, but nobody can check in from it.
  final DateTime? savedAt;

  factory MyToday.fromJson(Object? json, {DateTime? savedAt}) {
    final j = json is Map ? json : const <String, Object?>{};
    final classes = j['classes'];
    return MyToday(
      date: (j['date'] as String?) ?? '',
      classes: [
        if (classes is List)
          for (final c in classes) ?MyClass.fromJson(c),
      ],
      closed: ClosedDay.fromJson(j['closed']),
      onLeave: j['on_leave'] == true,
      savedAt: savedAt,
    );
  }

  MyToday replacing(MyClass saved) => MyToday(
    date: date,
    closed: closed,
    onLeave: onLeave,
    savedAt: savedAt,
    classes: [for (final c in classes) c.slotId == saved.slotId ? saved : c],
  );
}

/// A class on the month calendar.
@immutable
class CalendarMark {
  const CalendarMark({
    required this.label,
    required this.startTime,
    required this.status,
  });

  final String label;
  final String startTime;

  /// UPCOMING, OPEN, PRESENT, LATE, ABSENT, LEAVE, CLOSED_DAY, CANCELLED or
  /// NOT_RECORDED.
  final String status;
}

@immutable
class AttendanceDay {
  const AttendanceDay(this.date, this.marks, this.closed);
  final String date;
  final List<CalendarMark> marks;
  final ClosedDay? closed;
}

/// `GET /attendance/me/calendar?month=YYYY-MM`.
@immutable
class MyCalendar {
  const MyCalendar({
    required this.month,
    required this.today,
    required this.days,
    required this.present,
    required this.late,
    required this.absent,
    required this.leave,
    this.attendancePct,
  });

  final String month;
  final String today;
  final List<AttendanceDay> days;
  final int present;
  final int late;
  final int absent;
  final int leave;
  final num? attendancePct;

  factory MyCalendar.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final days = j['days'];
    final counts = j['counts'] is Map
        ? j['counts'] as Map
        : const <String, Object?>{};
    int count(String k) => (counts[k] as num?)?.toInt() ?? 0;
    return MyCalendar(
      month: (j['month'] as String?) ?? '',
      today: (j['today'] as String?) ?? '',
      days: [
        if (days is List)
          for (final d in days)
            if (d is Map && d['date'] is String)
              AttendanceDay(d['date'] as String, [
                if (d['classes'] is List)
                  for (final c in d['classes'] as List)
                    if (c is Map)
                      CalendarMark(
                        label: classLabelOf(c['section'], c['subject']),
                        startTime: (c['start_time'] as String?) ?? '',
                        status: (c['status'] as String?) ?? 'NOT_RECORDED',
                      ),
              ], ClosedDay.fromJson(d['closed'])),
      ],
      present: count('present'),
      late: count('late'),
      absent: count('absent'),
      leave: count('leave'),
      attendancePct: j['attendance_pct'] as num?,
    );
  }
}

/// "YYYY-MM" a number of months from another.
String shiftMonth(String month, int by) {
  final year = int.parse(month.substring(0, 4));
  final mon = int.parse(month.substring(5, 7));
  final index = year * 12 + (mon - 1) + by;
  return '${index ~/ 12}-${(index % 12 + 1).toString().padLeft(2, '0')}';
}

class MyAttendanceRepository {
  MyAttendanceRepository(this._api, this._cache);

  final ApiClient _api;
  final ReadCache _cache;

  Future<MyToday> today() async {
    final c = await _cache.get('attendance-today', '/attendance/me/today');
    final today = MyToday.fromJson(c.payload, savedAt: c.savedAt);
    // A copy saved on another day is not today's.
    if (c.isSaved && today.date != OrgTime.today()) {
      throw const ApiException(kind: ApiErrorKind.network);
    }
    return today;
  }

  Future<MyCalendar> calendar(String? month) async => MyCalendar.fromJson(
    (await _api.get(
      '/attendance/me/calendar',
      query: {'month': month},
    )).payload,
  );

  /// Online classes send no position; the server decides everything else.
  Future<MyClass?> checkIn(String slotId, {LocationFix? at}) async {
    final r = await _api.post(
      '/attendance/check-in',
      data: {
        'slot_id': slotId,
        if (at != null) ...{
          'latitude': at.latitude,
          'longitude': at.longitude,
          'accuracy_m': at.accuracy,
        },
      },
    );
    return MyClass.fromJson(r.payload);
  }
}

final myAttendanceRepositoryProvider = Provider<MyAttendanceRepository>(
  (ref) => MyAttendanceRepository(
    ref.watch(apiClientProvider),
    ref.watch(readCacheProvider),
  ),
);

/// Today's classes; reloaded when the workspace changes.
final myTodayProvider = FutureProvider.autoDispose<MyToday>((ref) {
  ref.watch(workspaceKeyProvider);
  return ref.read(myAttendanceRepositoryProvider).today();
}, retry: (retryCount, error) => null);

/// A month of the person's own classes; null is the current month.
final myCalendarProvider = FutureProvider.autoDispose
    .family<MyCalendar, String?>((ref, month) {
      ref.watch(workspaceKeyProvider);
      return ref.read(myAttendanceRepositoryProvider).calendar(month);
    }, retry: (retryCount, error) => null);
