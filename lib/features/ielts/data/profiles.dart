import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';

/// Bands a target may take: 0 to 9 in half bands (the web's `BANDS`).
final ieltsBands = [for (var i = 0; i <= 18; i++) i / 2];

/// An IELTS profile (P10-01): test type, targets and the booked test date.
typedef IeltsProfile = ({
  String studentId,
  String name,
  String? batch,

  /// ACADEMIC or GENERAL.
  String? testType,
  num? targetOverall,
  Map<String, num> targets,

  /// YYYY-MM-DD.
  String? testDate,
  int? daysToTest,
});

num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

IeltsProfile? profileFromJson(Object? j) {
  if (j is! Map) return null;
  final s = j['student'] is Map
      ? j['student']! as Map
      : const <String, Object?>{};
  final t = j['target_bands'];
  return (
    studentId: '${s['id'] ?? j['student_id'] ?? ''}',
    name: '${s['full_name'] ?? ''}',
    batch: s['batch'] as String?,
    testType: j['test_type'] as String?,
    targetOverall: _num(j['target_overall']),
    targets: {
      if (t is Map)
        for (final e in t.entries)
          if (ieltsModules.contains(e.key)) '${e.key}': ?_num(e.value),
    },
    testDate: j['test_date'] as String?,
    daysToTest: _num(j['days_to_test'])?.toInt(),
  );
}

/// A centre's students with their profiles, or one batch's.
final ieltsProfilesProvider = FutureProvider.autoDispose
    .family<List<IeltsProfile>, String?>((ref, sectionId) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get('/ielts/profiles', query: {'section_id': ?sectionId}))
              .payload;
      return [
        if (p is List)
          for (final r in p) ?profileFromJson(r),
      ];
    }, retry: (retryCount, error) => null);

/// The signed-in student's own profile.
final myIeltsProfileProvider = FutureProvider.autoDispose<IeltsProfile?>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  return profileFromJson(
    (await ref.read(apiClientProvider).get('/ielts/profiles/me')).payload,
  );
}, retry: (retryCount, error) => null);

/// The body of `PUT /ielts/profiles/:studentId`, as the web sends it: every
/// field, with null for "no target" or "no date".
Map<String, Object?> profileBody({
  String? testType,
  num? targetOverall,
  Map<String, num?> targets = const {},
  String? testDate,
}) => {
  'test_type': testType,
  'target_overall': targetOverall,
  'target_bands': {for (final m in ieltsModules) m: targets[m]},
  'test_date': testDate,
};
