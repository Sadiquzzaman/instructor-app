import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/cache/read_cache.dart';

/// "Class 6 A", or the section's name alone.
String sectionLabelOf(Map<Object?, Object?> s) {
  final cls = s['class_name'] as String?;
  final name = (s['name'] as String?) ?? '';
  return cls != null && cls.isNotEmpty ? '$cls $name' : name;
}

/// One weekly period.
@immutable
class RoutinePeriod {
  const RoutinePeriod({
    required this.id,
    required this.sectionId,
    required this.day,
    required this.startTime,
    required this.endTime,
    this.subject,
    this.teacher,
    this.room,
  });

  final String id;
  final String sectionId;

  /// ISO day: 1 Monday … 7 Sunday.
  final int day;

  /// "HH:MM" in the organisation's time zone.
  final String startTime;
  final String endTime;
  final String? subject;

  /// The teacher named on the period, else its subject's teachers.
  final String? teacher;
  final String? room;
}

/// `GET /routine`: the session's week for the person's sections.
@immutable
class Routine {
  const Routine({required this.sections, required this.periods, this.savedAt});

  /// Section id → "Class 6 A", in the API's order.
  final Map<String, String> sections;
  final List<RoutinePeriod> periods;

  /// Set when there was no connection and this is the saved copy.
  final DateTime? savedAt;

  factory Routine.fromJson(Object? json, {DateTime? savedAt}) {
    final j = json is Map ? json : const <String, Object?>{};
    List<Map<Object?, Object?>> list(String k) => [
      if (j[k] is List)
        for (final i in j[k] as List)
          if (i is Map) i,
    ];
    final teacherName = {
      for (final t in list('teachers'))
        if (t['id'] is String) t['id']: (t['full_name'] as String?) ?? '',
    };
    final subjectTeachers = {
      for (final sc in list('subject_classes'))
        sc['offering_id']: [
          if (sc['teacher_ids'] is List)
            for (final id in sc['teacher_ids'] as List)
              if (teacherName[id] != null) teacherName[id]!,
        ],
    };
    final periods = <RoutinePeriod>[];
    for (final s in list('slots')) {
      final section = s['section'];
      final subject = s['subject'];
      final teacher = s['teacher'];
      if (s['id'] is! String || section is! Map || s['day_of_week'] is! num) {
        continue;
      }
      final named = teacher is Map ? teacher['full_name'] as String? : null;
      final bySubject = subject is Map
          ? subjectTeachers[subject['offering_id']]
          : null;
      periods.add(
        RoutinePeriod(
          id: s['id'] as String,
          sectionId: (section['id'] as String?) ?? '',
          day: (s['day_of_week'] as num).toInt(),
          startTime: (s['start_time'] as String?) ?? '',
          endTime: (s['end_time'] as String?) ?? '',
          subject: subject is Map ? subject['name'] as String? : null,
          teacher:
              named ??
              (bySubject != null && bySubject.isNotEmpty
                  ? bySubject.join(', ')
                  : null),
          room: s['room'] as String?,
        ),
      );
    }
    periods.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      return byDay != 0 ? byDay : a.startTime.compareTo(b.startTime);
    });
    return Routine(
      sections: {
        for (final s in list('sections'))
          if (s['id'] is String) s['id']! as String: sectionLabelOf(s),
      },
      periods: periods,
      savedAt: savedAt,
    );
  }
}

/// The routine of the current session; kept in the read-only cache for
/// when there is no connection.
final routineProvider = FutureProvider.autoDispose<Routine>((ref) async {
  ref.watch(workspaceKeyProvider);
  final c = await ref.read(readCacheProvider).get('routine', '/routine');
  return Routine.fromJson(c.payload, savedAt: c.savedAt);
}, retry: (retryCount, error) => null);
