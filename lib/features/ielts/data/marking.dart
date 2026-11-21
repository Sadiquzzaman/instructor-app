import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';

/// A task (Writing) or part (Speaking) to mark.
typedef MarkingTask = ({
  String partId,
  int partNo,
  String? title,
  String? content,
  String? imageFileId,
  String script,
  int words,
  int minWords,
  String? recordingFileId,
});

/// Marks given to a Writing task.
typedef TaskMarks = ({
  String partId,
  Map<String, num> criteria,
  num? band,
  String? comment,
});

/// `GET /ielts/marking/:attemptId`.
typedef IeltsMarkingView = ({
  String attemptId,
  String module,
  String status,
  String studentId,
  String studentName,
  String testTitle,
  String batch,
  num? band,
  String? mode,
  List<MarkingTask> tasks,
  List<TaskMarks> marks,
  Map<String, num>? speaking,
  String? feedback,
});

Map<String, num> _nums(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries)
      if (e.value is num) '${e.key}': e.value as num,
};

IeltsMarkingView? markingFromJson(Object? j) {
  if (j is! Map || j['attempt_id'] == null) return null;
  final s = j['student'] is Map
      ? j['student'] as Map
      : const <String, Object?>{};
  final t = j['test'] is Map ? j['test'] as Map : const <String, Object?>{};
  return (
    attemptId: '${j['attempt_id']}',
    module: '${j['module'] ?? ''}',
    status: '${j['status'] ?? ''}',
    studentId: '${s['id'] ?? ''}',
    studentName: '${s['full_name'] ?? ''}',
    testTitle: '${t['title'] ?? ''}',
    batch: '${j['batch'] ?? ''}',
    band: j['band'] as num?,
    mode: j['mode'] as String?,
    tasks: [
      for (final k in (j['tasks'] as List?) ?? const [])
        if (k is Map)
          (
            partId: '${k['part_id']}',
            partNo: (k['part_no'] as num?)?.toInt() ?? 1,
            title: k['title'] as String?,
            content: k['content'] as String?,
            imageFileId: k['image_file_id'] as String?,
            script: '${k['script'] ?? ''}',
            words: (k['words'] as num?)?.toInt() ?? 0,
            minWords: (k['min_words'] as num?)?.toInt() ?? 0,
            recordingFileId: k['recording_file_id'] as String?,
          ),
    ],
    marks: [
      for (final m in (j['marks'] as List?) ?? const [])
        if (m is Map)
          (
            partId: '${m['part_id']}',
            criteria: _nums(m['criteria']),
            band: m['band'] as num?,
            comment: m['comment'] as String?,
          ),
    ],
    speaking: j['speaking'] is Map ? _nums(j['speaking']) : null,
    feedback: j['feedback'] as String?,
  );
}

final ieltsMarkingProvider = FutureProvider.autoDispose
    .family<IeltsMarkingView?, String>((ref, attemptId) async {
      ref.watch(workspaceKeyProvider);
      return markingFromJson(
        (await ref.read(apiClientProvider).get('/ielts/marking/$attemptId'))
            .payload,
      );
    }, retry: (retryCount, error) => null);

/// To the nearest half band: .25 up to .5, .75 up to the next band (the
/// server's `bands.ts`).
num roundBand(num value) => (value * 2 + 1e-9).round() / 2;

/// The band of criteria: their average to the nearest half band.
num? criteriaBand(Map<String, num?> c, List<String> keys) {
  if (keys.any((k) => c[k] == null)) return null;
  return roundBand(keys.fold<num>(0, (s, k) => s + c[k]!) / keys.length);
}

/// Speaking's criteria: FC, LR, GRA, P.
const speakingCriteria = ['FC', 'LR', 'GRA', 'P'];

/// Writing's criteria: Task 1 TA, Task 2 TR; both CC, LR, GRA.
List<String> writingCriteria(int partNo) => [
  partNo == 1 ? 'TA' : 'TR',
  'CC',
  'LR',
  'GRA',
];

/// The Writing band: Task 2 counts double; one task alone is that task's.
num? writingBand(num? task1, num? task2) {
  if (task1 == null && task2 == null) return null;
  if (task1 == null) return task2;
  if (task2 == null) return task1;
  return roundBand((task1 + 2 * task2) / 3);
}
