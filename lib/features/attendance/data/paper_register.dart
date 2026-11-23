import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// The letters the register uses for each mark (the server reads them,
/// and their Bangla forms, as on the web's CSV).
const registerLetters = {
  'PRESENT': 'P',
  'LATE': 'L',
  'ABSENT': 'A',
  'LEAVE': 'LV',
};

/// A class-day column: [header] is the date, plus the start time when the
/// day has two classes (the CSV's header).
typedef RegisterColumn = ({String header, String date, String startTime});

typedef RegisterStudent = ({
  String id,
  String name,
  String? rollNo,
  List<String?> marks,
});

/// `GET /attendance/register/sections/:id?month`: a section's month.
@immutable
class PaperRegister {
  const PaperRegister({
    required this.sectionName,
    required this.month,
    required this.mode,
    required this.canImport,
    required this.columns,
    required this.students,
  });

  final String sectionName;
  final String month;

  /// SELF_CHECKIN or PAPER_REGISTER.
  final String mode;
  final bool canImport;
  final List<RegisterColumn> columns;
  final List<RegisterStudent> students;

  factory PaperRegister.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final s = j['section'] is Map
        ? j['section'] as Map
        : const <String, Object?>{};
    return PaperRegister(
      sectionName: '${s['class_name'] ?? ''} ${s['name'] ?? ''}'.trim(),
      month: (j['month'] as String?) ?? '',
      mode: (j['mode'] as String?) ?? 'SELF_CHECKIN',
      canImport: j['can_import'] == true,
      columns: [
        if (j['classes'] is List)
          for (final c in j['classes'] as List)
            if (c is Map && c['header'] is String)
              (
                header: c['header'] as String,
                date: (c['date'] as String?) ?? '',
                startTime: (c['start_time'] as String?) ?? '',
              ),
      ],
      students: [
        if (j['students'] is List)
          for (final st in j['students'] as List)
            if (st is Map && st['id'] is String)
              (
                id: st['id'] as String,
                name: (st['full_name'] as String?) ?? '',
                rollNo: st['roll_no'] as String?,
                marks: [
                  if (st['marks'] is List)
                    for (final m in st['marks'] as List) m as String?,
                ],
              ),
      ],
    );
  }
}

/// A problem or note on a column, a line or a cell of a checked register.
typedef RegisterProblem = ({int? row, int? column, String code, String value});

/// `POST …/preview` and `…/import`: whether the register can be saved, the
/// problems where they are, and how many marks are new or changed.
@immutable
class RegisterCheck {
  const RegisterCheck({
    required this.valid,
    required this.problems,
    required this.newMarks,
    required this.changed,
    required this.checkIns,
  });

  final bool valid;
  final List<RegisterProblem> problems;
  final int newMarks;
  final int changed;

  /// Self check-ins the register disagrees with (kept unless replaced).
  final int checkIns;

  factory RegisterCheck.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final sm = j['summary'] is Map
        ? j['summary'] as Map
        : const <String, Object?>{};
    int n(Object? v) => (v as num?)?.toInt() ?? 0;
    List<String> codes(Object? v) => [
      if (v is List)
        for (final c in v)
          if (c is String) c,
    ];
    final problems = <RegisterProblem>[
      if (j['columns'] is List)
        for (final c in j['columns'] as List)
          if (c is Map)
            for (final code in codes(c['issues']))
              (row: null, column: n(c['column']), code: code, value: ''),
      if (j['rows'] is List)
        for (final r in j['rows'] as List)
          if (r is Map) ...[
            for (final code in codes(r['issues']))
              (row: n(r['row']), column: null, code: code, value: ''),
            if (r['cells'] is List)
              for (final c in r['cells'] as List)
                if (c is Map)
                  for (final code in codes(c['issues']))
                    (
                      row: n(r['row']),
                      column: n(c['column']),
                      code: code,
                      value: (c['value'] as String?) ?? '',
                    ),
          ],
    ];
    return RegisterCheck(
      valid: j['valid'] == true,
      problems: problems,
      newMarks: n(sm['new']),
      changed: n(sm['changed']),
      checkIns: n(sm['check_ins']),
    );
  }
}

class PaperRegisterRepository {
  PaperRegisterRepository(this._api);

  final ApiClient _api;

  Future<PaperRegister> month(String sectionId, String month) async =>
      PaperRegister.fromJson(
        (await _api.get(
          '/attendance/register/sections/$sectionId',
          query: {'month': month},
        )).payload,
      );

  /// The register as the CSV would carry it: roll_no, name and one column
  /// per class day; a line per student with their letters ("" for none).
  /// Line numbers in the answer count from 1 after the header, columns
  /// from 0.
  static Map<String, Object?> body(
    PaperRegister r,
    List<List<String?>> marks, {
    bool overwriteCheckIns = false,
  }) => {
    'month': r.month,
    'header': ['roll_no', 'name', for (final c in r.columns) c.header],
    'rows': [
      for (final (i, s) in r.students.indexed)
        {
          'cells': [
            s.rollNo ?? '',
            s.name,
            for (final m in marks[i]) m == null ? '' : registerLetters[m] ?? '',
          ],
        },
    ],
    if (overwriteCheckIns) 'overwrite_check_ins': true,
  };

  Future<RegisterCheck> preview(
    String sectionId,
    Map<String, Object?> body,
  ) async => RegisterCheck.fromJson(
    (await _api.post(
      '/attendance/register/sections/$sectionId/preview',
      data: body,
    )).payload,
  );

  Future<RegisterCheck> import(
    String sectionId,
    Map<String, Object?> body,
  ) async => RegisterCheck.fromJson(
    (await _api.post(
      '/attendance/register/sections/$sectionId/import',
      data: body,
    )).payload,
  );
}

final paperRegisterRepositoryProvider = Provider<PaperRegisterRepository>(
  (ref) => PaperRegisterRepository(ref.watch(apiClientProvider)),
);

/// A section's register for a month ("YYYY-MM").
final paperRegisterProvider = FutureProvider.autoDispose
    .family<PaperRegister, ({String sectionId, String month})>((ref, k) {
      ref.watch(workspaceKeyProvider);
      return ref
          .read(paperRegisterRepositoryProvider)
          .month(k.sectionId, k.month);
    }, retry: (retryCount, error) => null);
