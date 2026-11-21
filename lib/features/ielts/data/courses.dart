import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';

/// An IELTS course (P12-05), as `GET /ielts/courses` returns it.
typedef IeltsCourse = ({
  String id,
  String title,
  ({String id, String? name, bool isDefault})? branch,
  String startDate,
  String endDate,

  /// UPCOMING, RUNNING or ENDED.
  String status,
  List<String> modules,
  int? seatLimit,
  int students,
  List<({String module, List<({String id, String? name})> teachers})> teachers,
  String classId,
});

IeltsCourse? courseFromJson(Object? c) {
  if (c is! Map || c['id'] == null) return null;
  final b = c['branch'];
  return (
    id: '${c['id']}',
    title: '${c['title'] ?? ''}',
    branch: b is Map
        ? (
            id: '${b['id']}',
            name: b['name'] as String?,
            isDefault: b['is_default'] == true,
          )
        : null,
    startDate: '${c['start_date'] ?? ''}',
    endDate: '${c['end_date'] ?? ''}',
    status: '${c['status'] ?? 'UPCOMING'}',
    modules: [
      for (final m in (c['modules'] as List?) ?? const [])
        if (ieltsModules.contains(m)) '$m',
    ],
    seatLimit: (c['seat_limit'] as num?)?.toInt(),
    students: (c['students'] as num?)?.toInt() ?? 0,
    teachers: [
      for (final m in (c['teachers'] as List?) ?? const [])
        if (m is Map)
          (
            module: '${m['module']}',
            teachers: [
              for (final t in (m['teachers'] as List?) ?? const [])
                if (t is Map)
                  (id: '${t['id']}', name: t['full_name'] as String?),
            ],
          ),
    ],
    classId: '${c['class_id'] ?? ''}',
  );
}

/// The courses this person sees: all of the centre's for staff, their
/// branch's for a branch manager, their own for a student.
final ieltsCoursesProvider = FutureProvider.autoDispose<List<IeltsCourse>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/ielts/courses')).payload;
  return [
    if (p is List)
      for (final c in p) ?courseFromJson(c),
  ];
}, retry: (retryCount, error) => null);

/// The body of `POST /ielts/courses` and `PATCH /ielts/courses/:id`, as the
/// web sends it. [teachers] is sent only when the teachers could be listed
/// (so a failed list never clears them); an empty choice clears a module.
Map<String, Object?> courseBody({
  required String title,
  required String startDate,
  required String endDate,
  required List<String> modules,
  String? seatLimit,
  String? branchId,
  Map<String, String>? teachers,
}) => {
  'title': title.trim(),
  'start_date': startDate,
  'end_date': endDate,
  'modules': [
    for (final m in ieltsModules)
      if (modules.contains(m)) m,
  ],
  'seat_limit': int.tryParse((seatLimit ?? '').trim()),
  'branch_id': ?branchId,
  if (teachers != null)
    'teachers': {
      for (final m in ieltsModules)
        if (modules.contains(m) && teachers.containsKey(m))
          m: [if (teachers[m]!.isNotEmpty) teachers[m]],
    },
};
