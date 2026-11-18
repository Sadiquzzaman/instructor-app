import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/api/api_response.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';

typedef Who = ({String id, String name});

Who? _who(Object? j) => j is Map && j['id'] is String
    ? (id: j['id'] as String, name: (j['full_name'] as String?) ?? '')
    : null;

int _int(Object? v) => (v as num?)?.toInt() ?? 0;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// How many students are present, late, absent, on leave or not in yet,
/// and how many check-ins are flagged.
typedef SessionCounts = ({
  int students,
  int present,
  int late,
  int absent,
  int leave,
  int waiting,
  int flagged,
});

/// A class cancelled for the day (ATT-19).
typedef Cancellation = ({DateTime? at, Who? by, String? note});

/// A one-day change of a class (P5-04): the routine's times and the
/// substitute, who changed it, when and why.
typedef ClassChange = ({
  String routineStart,
  String routineEnd,
  Who? substitute,
  DateTime? at,
  Who? by,
  String? note,
});

/// A class on a date for staff (`GET /attendance/sessions`).
@immutable
class ClassSession {
  const ClassSession({
    required this.slotId,
    required this.date,
    required this.label,
    required this.startTime,
    required this.endTime,
    required this.state,
    required this.mode,
    required this.classType,
    required this.counts,
    this.startsAt,
    this.endsAt,
    this.closed,
    this.teacher,
    this.cancelled,
    this.change,
    this.canCorrect = false,
    this.canCancel = false,
    this.canRestore = false,
    this.canChange = false,
  });

  final String slotId;
  final String date;

  /// "Mathematics · Class 6 A".
  final String label;

  /// HH:MM in the organisation's time zone.
  final String startTime;
  final String endTime;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// UPCOMING, OPEN or CLOSED (check-in).
  final String state;

  /// CHECK_IN or PAPER_REGISTER.
  final String mode;

  /// IN_PERSON or ONLINE.
  final String classType;
  final ClosedDay? closed;
  final Who? teacher;
  final SessionCounts counts;
  final Cancellation? cancelled;
  final ClassChange? change;
  final bool canCorrect;
  final bool canCancel;
  final bool canRestore;
  final bool canChange;

  static ClassSession? fromJson(Object? json) {
    if (json is! Map || json['slot_id'] is! String) return null;
    final c = json['counts'] is Map
        ? json['counts'] as Map
        : const <String, Object?>{};
    final x = json['cancelled'];
    final ch = json['change'];
    return ClassSession(
      slotId: json['slot_id'] as String,
      date: (json['date'] as String?) ?? '',
      label: classLabelOf(json['section'], json['subject']),
      startTime: (json['start_time'] as String?) ?? '',
      endTime: (json['end_time'] as String?) ?? '',
      startsAt: _time(json['starts_at']),
      endsAt: _time(json['ends_at']),
      state: (json['state'] as String?) ?? 'UPCOMING',
      mode: (json['mode'] as String?) ?? 'CHECK_IN',
      classType: (json['class_type'] as String?) ?? 'IN_PERSON',
      closed: ClosedDay.fromJson(json['closed']),
      teacher: _who(json['teacher']),
      counts: (
        students: _int(c['students']),
        present: _int(c['present']),
        late: _int(c['late']),
        absent: _int(c['absent']),
        leave: _int(c['leave']),
        waiting: _int(c['waiting']),
        flagged: _int(c['flagged']),
      ),
      cancelled: x is Map
          ? (at: _time(x['at']), by: _who(x['by']), note: x['note'] as String?)
          : null,
      change: ch is Map
          ? (
              routineStart: (ch['routine_start_time'] as String?) ?? '',
              routineEnd: (ch['routine_end_time'] as String?) ?? '',
              substitute: _who(ch['substitute']),
              at: _time(ch['at']),
              by: _who(ch['by']),
              note: ch['note'] as String?,
            )
          : null,
      canCorrect: json['can_correct'] == true,
      canCancel: json['can_cancel'] == true,
      canRestore: json['can_restore'] == true,
      canChange: json['can_change'] == true,
    );
  }
}

/// A correction in a record's trail (ATT-12).
typedef Correction = ({
  String id,
  String? from,
  String to,
  String reason,
  Who? by,
  DateTime? at,
});

/// One person on a class's list.
@immutable
class RosterRow {
  const RosterRow({
    required this.id,
    required this.name,
    required this.status,
    this.rollNo,
    this.lateMinutes,
    this.checkedInAt,
    this.distanceM,
    this.accuracyM,
    this.flag,
    this.corrections = const [],
    this.canCorrect = false,
  });

  final String id;
  final String name;
  final String? rollNo;

  /// A class status: PRESENT, LATE, ABSENT, LEAVE, UPCOMING, OPEN,
  /// NOT_RECORDED, CANCELLED, CLOSED_DAY.
  final String status;
  final int? lateMinutes;
  final DateTime? checkedInAt;
  final int? distanceM;
  final int? accuracyM;

  /// EDGE_ACCURACY or IMPOSSIBLE_JUMP.
  final String? flag;
  final List<Correction> corrections;
  final bool canCorrect;

  static RosterRow? fromJson(Object? json) {
    if (json is! Map) return null;
    final p = json['person'];
    if (p is! Map || p['id'] is! String) return null;
    final r = json['record'] is Map
        ? json['record'] as Map
        : const <String, Object?>{};
    final cs = json['corrections'];
    return RosterRow(
      id: p['id'] as String,
      name: (p['full_name'] as String?) ?? '',
      rollNo: p['roll_no'] as String?,
      status: (json['status'] as String?) ?? 'NOT_RECORDED',
      lateMinutes: (r['late_minutes'] as num?)?.toInt(),
      checkedInAt: _time(r['checked_in_at']),
      distanceM: (r['distance_m'] as num?)?.round(),
      accuracyM: (r['accuracy_m'] as num?)?.round(),
      flag: r['flag'] as String?,
      corrections: [
        if (cs is List)
          for (final c in cs)
            if (c is Map && c['new_status'] is String)
              (
                id: (c['id'] as String?) ?? '',
                from: c['old_status'] as String?,
                to: c['new_status'] as String,
                reason: (c['reason'] as String?) ?? '',
                by: _who(c['corrected_by']),
                at: _time(c['created_at']),
              ),
      ],
      canCorrect: json['can_correct'] == true,
    );
  }
}

/// `GET /attendance/sessions/:slotId/:date`: the class and everyone on it.
@immutable
class ClassSessionDetail {
  const ClassSessionDetail({
    required this.session,
    required this.students,
    required this.teachers,
  });

  final ClassSession session;
  final List<RosterRow> students;
  final List<RosterRow> teachers;

  static ClassSessionDetail? fromJson(Object? json) {
    final s = ClassSession.fromJson(json);
    if (s == null || json is! Map) return null;
    List<RosterRow> rows(Object? v) => [
      if (v is List)
        for (final r in v) ?RosterRow.fromJson(r),
    ];
    return ClassSessionDetail(
      session: s,
      students: rows(json['students']),
      teachers: rows(json['teachers']),
    );
  }
}

/// `GET /attendance/sessions`: the classes of a school date.
@immutable
class SessionsOnDate {
  const SessionsOnDate({
    required this.date,
    required this.today,
    required this.sessions,
    this.closed,
  });

  final String date;
  final String today;
  final ClosedDay? closed;
  final List<ClassSession> sessions;

  factory SessionsOnDate.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final s = j['sessions'];
    return SessionsOnDate(
      date: (j['date'] as String?) ?? '',
      today: (j['today'] as String?) ?? '',
      closed: ClosedDay.fromJson(j['closed']),
      sessions: [
        if (s is List)
          for (final i in s) ?ClassSession.fromJson(i),
      ],
    );
  }
}

class ClassAttendanceRepository {
  ClassAttendanceRepository(this._api);

  final ApiClient _api;

  Future<SessionsOnDate> day(String? date) async => SessionsOnDate.fromJson(
    (await _api.get('/attendance/sessions', query: {'date': ?date})).payload,
  );

  Future<ClassSessionDetail> detail(String slotId, String date) async =>
      _detail(await _api.get('/attendance/sessions/$slotId/$date'));

  /// Sets PRESENT, LATE (with [lateMinutes] if given) or ABSENT, with why.
  Future<ClassSessionDetail> correct(
    String slotId,
    String date,
    String personId, {
    required String status,
    required String reason,
    int? lateMinutes,
  }) async => _detail(
    await _api.put(
      '/attendance/sessions/$slotId/$date/records/$personId',
      data: {
        'status': status,
        'reason': reason,
        if (status == 'LATE') 'late_minutes': ?lateMinutes,
      },
    ),
  );

  /// Cancels the class for the day, with an optional note for students.
  Future<ClassSessionDetail> cancel(
    String slotId,
    String date, {
    String note = '',
  }) async => _detail(
    await _api.post(
      '/attendance/sessions/$slotId/$date/cancel',
      data: {if (note.isNotEmpty) 'note': note},
    ),
  );

  Future<ClassSessionDetail> restore(String slotId, String date) async =>
      _detail(
        await _api.post(
          '/attendance/sessions/$slotId/$date/restore',
          data: const <String, Object>{},
        ),
      );

  /// Changes the class for the day: other times (HH:MM, the organisation's
  /// time zone) and/or a substitute (null: the routine's teacher). The
  /// routine's own times and no substitute undo the change.
  Future<ClassSessionDetail> change(
    String slotId,
    String date, {
    required String start,
    required String end,
    String? substituteId,
    String note = '',
  }) async => _detail(
    await _api.post(
      '/attendance/sessions/$slotId/$date/change',
      data: {
        'start_time': start,
        'end_time': end,
        'substitute_teacher_id': substituteId,
        if (note.isNotEmpty) 'note': note,
      },
    ),
  );

  /// Teachers of the organisation who can take a class.
  Future<List<Who>> assignableTeachers(String organizationId) async {
    final p = (await _api.get(
      '/organizations/$organizationId/assignable-teachers',
    )).payload;
    return [
      if (p is List)
        for (final m in p)
          if (m is Map && m['user'] is Map)
            if (_who(m['user']) case final w?)
              (
                id: w.id,
                name: w.name.isNotEmpty
                    ? w.name
                    : ((m['user'] as Map)['email'] as String?) ?? '',
              ),
    ];
  }

  ClassSessionDetail _detail(ApiResponse r) {
    final d = ClassSessionDetail.fromJson(r.payload);
    if (d == null) throw const FormatException('class session');
    return d;
  }
}

final classAttendanceRepositoryProvider = Provider<ClassAttendanceRepository>(
  (ref) => ClassAttendanceRepository(ref.watch(apiClientProvider)),
);

/// The classes of a date (null: today, as the server says).
final classSessionsProvider = FutureProvider.autoDispose
    .family<SessionsOnDate, String?>((ref, date) {
      ref.watch(workspaceKeyProvider);
      return ref.read(classAttendanceRepositoryProvider).day(date);
    }, retry: (retryCount, error) => null);

/// One class on a date, by `slotId/date`.
final classSessionProvider = FutureProvider.autoDispose
    .family<ClassSessionDetail, ({String slotId, String date})>((ref, k) {
      ref.watch(workspaceKeyProvider);
      return ref
          .read(classAttendanceRepositoryProvider)
          .detail(k.slotId, k.date);
    }, retry: (retryCount, error) => null);

/// Teachers who can take a class, in the organisation with this id.
final assignableTeachersProvider = FutureProvider.autoDispose
    .family<List<Who>, String>((ref, organizationId) {
      ref.watch(workspaceKeyProvider);
      return ref
          .read(classAttendanceRepositoryProvider)
          .assignableTeachers(organizationId);
    }, retry: (retryCount, error) => null);
