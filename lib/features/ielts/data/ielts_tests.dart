import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';

/// Parts per module (the real test): Listening 4, Reading 3 passages,
/// Writing 2 tasks, Speaking 3 parts.
const ieltsPartCount = {
  'LISTENING': 4,
  'READING': 3,
  'WRITING': 2,
  'SPEAKING': 3,
};

/// A row of `GET /ielts/tests`.
typedef IeltsTestSummary = ({
  String id,
  String title,

  /// MOCK or PRACTICE.
  String purpose,

  /// ACADEMIC or GENERAL.
  String testType,
  List<String> modules,
  Map<String, int> questionCounts,

  /// DRAFT, PUBLISHED or ARCHIVED.
  String status,
  DateTime? updatedAt,
  bool needsReview,
});

IeltsTestSummary? testSummaryFromJson(Object? j) {
  if (j is! Map || j['id'] == null) return null;
  final q = j['question_counts'];
  return (
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    purpose: '${j['purpose'] ?? 'PRACTICE'}',
    testType: '${j['test_type'] ?? 'ACADEMIC'}',
    modules: [
      for (final m in ieltsModules)
        if ((j['modules'] as List?)?.contains(m) ?? false) m,
    ],
    questionCounts: {
      if (q is Map)
        for (final e in q.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    },
    status: '${j['status'] ?? 'DRAFT'}',
    updatedAt: DateTime.tryParse('${j['updated_at']}'),
    needsReview: j['needs_review'] == true,
  );
}

/// The centre's tests, by purpose and status (null: all).
final ieltsTestsProvider = FutureProvider.autoDispose
    .family<List<IeltsTestSummary>, ({String? purpose, String? status})>((
      ref,
      f,
    ) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get(
                    '/ielts/tests',
                    query: {'purpose': ?f.purpose, 'status': ?f.status},
                  ))
              .payload;
      return [
        if (p is List)
          for (final r in p) ?testSummaryFromJson(r),
      ];
    }, retry: (retryCount, error) => null);

/// The body of `POST /ielts/tests`: a mock gets every part of its modules;
/// a practice set the chosen parts of one module.
Map<String, Object?> newTestBody({
  required String title,
  required String testType,
  required String purpose,
  List<String> modules = const [],
  String module = 'READING',
  List<int> parts = const [],
}) => {
  'title': title.trim(),
  'test_type': testType,
  'purpose': purpose,
  if (purpose == 'MOCK')
    'modules': [
      for (final m in ieltsModules)
        if (modules.contains(m)) m,
    ]
  else ...{
    'module': module,
    'part_nos': [...parts]..sort(),
  },
};

/// One band table (`GET /ielts/band-tables`): raw Listening or Reading
/// scores out of 40 to bands.
typedef IeltsBandTable = ({
  String module,
  String? testType,
  bool customised,
  List<({int minRaw, num band})> rows,
});

List<IeltsBandTable> bandTablesFromJson(Object? p) => [
  if (p is List)
    for (final t in p)
      if (t is Map)
        (
          module: '${t['module']}',
          testType: t['test_type'] as String?,
          customised: t['customised'] == true,
          rows: [
            for (final r in (t['rows'] as List?) ?? const [])
              if (r is Map)
                (
                  minRaw: (r['min_raw'] as num?)?.toInt() ?? 0,
                  band: (r['band'] as num?) ?? 0,
                ),
          ],
        ),
];

final ieltsBandTablesProvider =
    FutureProvider.autoDispose<List<IeltsBandTable>>((ref) async {
      ref.watch(workspaceKeyProvider);
      return bandTablesFromJson(
        (await ref.read(apiClientProvider).get('/ielts/band-tables')).payload,
      );
    }, retry: (retryCount, error) => null);

/// The server's rule for a table (`IELTS_BAND_TABLE_INVALID`): whole raw
/// scores 0–40 going down to 0, bands never going up. True when [rows]
/// keep it, so the app can say so before sending.
bool bandRowsValid(List<({int minRaw, num band})> rows) {
  if (rows.isEmpty || rows.length > 41 || rows.last.minRaw != 0) return false;
  for (var i = 0; i < rows.length; i++) {
    final r = rows[i];
    if (r.minRaw < 0 || r.minRaw > 40) return false;
    if (i > 0) {
      final prev = rows[i - 1];
      if (r.minRaw >= prev.minRaw || r.band > prev.band) return false;
    }
  }
  return true;
}
