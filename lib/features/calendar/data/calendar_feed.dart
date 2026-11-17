import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/time/org_time.dart';

enum CalendarKind { classItem, event, exam, homework, holiday }

CalendarKind? _kindOf(Object? v) => switch (v) {
  'CLASS' => CalendarKind.classItem,
  'EVENT' => CalendarKind.event,
  'EXAM' => CalendarKind.exam,
  'HOMEWORK' => CalendarKind.homework,
  'HOLIDAY' => CalendarKind.holiday,
  _ => null,
};

/// The workspace an item comes from: `personal_teacher`, `org:<id>` or
/// `teacher:<id>`, and its name.
@immutable
class CalendarWorkspace {
  const CalendarWorkspace(this.key, this.label);
  final String key;
  final String label;

  static CalendarWorkspace? fromJson(Object? j) =>
      j is Map && j['key'] is String
      ? CalendarWorkspace(j['key'] as String, (j['label'] as String?) ?? '')
      : null;
}

/// The key of the session's workspace in the calendar's terms.
String? calendarKeyOf(Session? s) => switch (s?.contextType) {
  'organization' when s!.organizationId != null => 'org:${s.organizationId}',
  'personal_teacher' => 'personal_teacher',
  'individual_teacher' when s!.teacherId != null => 'teacher:${s.teacherId}',
  _ => null,
};

/// One item of `GET /calendar/me` (the web's `CalendarFeedItem`): a class of
/// the timetable, an event, an exam, homework due, or a closed day.
@immutable
class CalendarItem {
  const CalendarItem({
    required this.kind,
    required this.id,
    required this.title,
    this.date,
    this.startsAt,
    this.endsAt,
    this.subject,
    this.teacher,
    this.room,
    this.role,
    this.status,
    this.sectionName,
    this.className,
    this.place,
    this.eventType,
    this.cancelled = false,
    this.sections = const [],
    this.handedIn,
    this.reason,
    this.workspace,
  });

  final CalendarKind kind;
  final String id;

  /// May be empty for a holiday (then [reason] names it).
  final String title;

  /// `YYYY-MM-DD`: classes and closed days.
  final String? date;
  final DateTime? startsAt;
  final DateTime? endsAt;

  // Classes.
  final String? subject;
  final String? teacher;
  final String? room;

  /// STUDENT or TEACHER: the person's part in the class.
  final String? role;

  /// UPCOMING, OPEN (check-in open), PRESENT, LATE, ABSENT, EXCUSED,
  /// CLOSED_DAY, CANCELLED, NOT_RECORDED.
  final String? status;
  final String? sectionName;

  // Exams.
  final String? className;

  // Events.
  final String? place;
  final String? eventType;
  final bool cancelled;

  // Homework.
  final List<String> sections;

  /// Null for staff.
  final bool? handedIn;

  /// Closed days: WEEKLY_OFF or HOLIDAY.
  final String? reason;
  final CalendarWorkspace? workspace;

  bool get isTimed => kind != CalendarKind.holiday && startsAt != null;
  bool get isCancelled =>
      (kind == CalendarKind.classItem && status == 'CANCELLED') ||
      (kind == CalendarKind.event && cancelled);

  /// The school day it belongs to, in the organisation's time zone.
  String get day => date ?? OrgTime.today(startsAt);

  static CalendarItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = _kindOf(json['kind']);
    final id = json['id'];
    if (kind == null || id is! String) return null;
    DateTime? time(String k) =>
        json[k] is String ? DateTime.tryParse(json[k] as String) : null;
    String? text(String k) => json[k] is String ? json[k] as String : null;
    final section = json['section'];
    final sections = json['sections'];
    final item = CalendarItem(
      kind: kind,
      id: id,
      title: text('title') ?? '',
      date: text('date'),
      startsAt: time('starts_at'),
      endsAt: time('ends_at'),
      subject: text('subject'),
      teacher: text('teacher'),
      room: text('room'),
      role: text('role'),
      status: text('status'),
      sectionName: section is Map ? section['name'] as String? : null,
      className:
          text('class_name') ??
          (section is Map ? section['class_name'] as String? : null),
      place: text('place'),
      eventType: text('event_type'),
      cancelled: json['cancelled'] == true,
      sections: [
        if (sections is List)
          for (final s in sections)
            if (s is String) s,
      ],
      handedIn: json['handed_in'] is bool ? json['handed_in'] as bool : null,
      reason: text('reason'),
      workspace: CalendarWorkspace.fromJson(json['workspace']),
    );
    // A timed item without its time can't be placed; a closed day needs its date.
    if (kind == CalendarKind.holiday ? item.date == null : !item.isTimed) {
      return null;
    }
    return item;
  }
}

@immutable
class CalendarFeed {
  const CalendarFeed({
    required this.items,
    this.workspaces,
    this.timeZone = OrgTime.timeZone,
  });

  final List<CalendarItem> items;

  /// The workspaces included; empty when none has the calendar switched on.
  /// Null when the answer did not say.
  final List<CalendarWorkspace>? workspaces;
  final String timeZone;

  factory CalendarFeed.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final items = j['items'];
    final ws = j['workspaces'];
    return CalendarFeed(
      items: [
        if (items is List)
          for (final i in items) ?CalendarItem.fromJson(i),
      ]..sort(_byStart),
      workspaces: ws is List
          ? [for (final w in ws) ?CalendarWorkspace.fromJson(w)]
          : null,
      timeZone: (j['time_zone'] as String?) ?? OrgTime.timeZone,
    );
  }
}

int _byStart(CalendarItem a, CalendarItem b) {
  final byDay = a.day.compareTo(b.day);
  if (byDay != 0) return byDay;
  // Closed days first, then by time.
  final ta = a.startsAt, tb = b.startsAt;
  if (ta == null || tb == null) return ta == null ? (tb == null ? 0 : -1) : 1;
  return ta.compareTo(tb);
}

/// `YYYY-MM-DD` plus [days].
String addDays(String day, int days) {
  final d = DateTime.utc(
    int.parse(day.substring(0, 4)),
    int.parse(day.substring(5, 7)),
    int.parse(day.substring(8, 10)),
  ).add(Duration(days: days));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

typedef CalendarRange = ({String from, String to});

/// The person's own calendar across their workspaces (`GET /calendar/me`).
/// Reloaded when the workspace changes or the person signs out.
final calendarFeedProvider = FutureProvider.autoDispose
    .family<CalendarFeed, CalendarRange>((ref, range) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get('/calendar/me', query: {'from': range.from, 'to': range.to});
      return CalendarFeed.fromJson(r.payload);
    }, retry: (retryCount, error) => null);
