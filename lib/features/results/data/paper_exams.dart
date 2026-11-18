import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

typedef PaperPart = ({String name, num marks});

/// A paper exam staff manage (`GET /offline-exams`, `…/:id`).
@immutable
class PaperExam {
  const PaperExam({
    required this.id,
    required this.name,
    required this.date,
    required this.total,
    required this.offeringId,
    required this.subject,
    required this.section,
    required this.students,
    required this.entered,
    this.parts = const [],
    this.termId,
    this.termName,
    this.publishedAt,
    this.canEdit = false,
  });

  final String id;
  final String name;

  /// "YYYY-MM-DD".
  final String date;
  final num total;
  final List<PaperPart> parts;
  final String? termId;
  final String? termName;
  final String offeringId;
  final String subject;

  /// "Class 6 A".
  final String section;
  final DateTime? publishedAt;
  final int students;
  final int entered;
  final bool canEdit;

  static PaperExam? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final o = j['offering'] is Map
        ? j['offering'] as Map
        : const <String, Object?>{};
    final sub = o['subject'] is Map
        ? o['subject'] as Map
        : const <String, Object?>{};
    final sec = o['section'] is Map
        ? o['section'] as Map
        : const <String, Object?>{};
    final term = j['term'] is Map ? j['term'] as Map : null;
    final c = j['counts'] is Map
        ? j['counts'] as Map
        : const <String, Object?>{};
    return PaperExam(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      date: (j['exam_date'] as String?) ?? '',
      total: (j['total_marks'] as num?) ?? 0,
      parts: [
        if (j['parts'] is List)
          for (final p in j['parts'] as List)
            if (p is Map && p['name'] is String)
              (name: p['name'] as String, marks: (p['marks'] as num?) ?? 0),
      ],
      termId: term?['id'] as String?,
      termName: term?['name'] as String?,
      offeringId: (o['id'] as String?) ?? '',
      subject: (sub['name'] as String?) ?? '',
      section: '${sec['class_name'] ?? ''} ${sec['name'] ?? ''}'.trim(),
      publishedAt: j['published_at'] is String
          ? DateTime.tryParse(j['published_at'] as String)
          : null,
      students: (c['students'] as num?)?.toInt() ?? 0,
      entered: (c['entered'] as num?)?.toInt() ?? 0,
      canEdit: j['can_edit'] == true,
    );
  }
}

/// A subject class paper exams can be added to.
typedef PaperClassChoice = ({
  String offeringId,
  String label,
  List<({String id, String name})> terms,
});

/// A student's marks on the grid.
typedef PaperMarkRow = ({
  String studentId,
  String name,
  String? rollNo,
  num? marks,
  Map<String, num> partMarks,
  bool absent,
  num? percent,
  String? grade,
});

/// `GET /offline-exams/:id/marks`.
typedef PaperMarksGrid = ({PaperExam exam, List<PaperMarkRow> rows});

PaperMarksGrid _grid(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  return (
    exam: PaperExam.fromJson(j['exam'])!,
    rows: [
      if (j['rows'] is List)
        for (final r in j['rows'] as List)
          if (r is Map && r['student'] is Map)
            (
              studentId: ((r['student'] as Map)['id'] as String?) ?? '',
              name: ((r['student'] as Map)['full_name'] as String?) ?? '',
              rollNo: (r['student'] as Map)['roll_no'] as String?,
              marks: r['marks'] as num?,
              partMarks: {
                if (r['part_marks'] is Map)
                  for (final MapEntry(:key, :value)
                      in (r['part_marks'] as Map).entries)
                    if (key is String && value is num) key: value,
              },
              absent: r['is_absent'] == true,
              percent: r['percent'] as num?,
              grade: r['grade'] is Map
                  ? (r['grade'] as Map)['grade'] as String?
                  : null,
            ),
    ],
  );
}

class PaperExamsRepository {
  PaperExamsRepository(this._api);

  final ApiClient _api;

  Future<List<PaperExam>> all() async {
    final p = (await _api.get('/offline-exams')).payload;
    return [
      if (p is List)
        for (final e in p) ?PaperExam.fromJson(e),
    ]..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<List<PaperClassChoice>> choices() async {
    final p = (await _api.get('/offline-exams/subject-classes')).payload;
    return [
      if (p is List)
        for (final c in p)
          if (c is Map && c['offering_id'] is String)
            (
              offeringId: c['offering_id'] as String,
              label:
                  '${c['subject'] is Map ? (c['subject'] as Map)['name'] ?? '' : ''} · ${c['section_label'] ?? ''}',
              terms: [
                if (c['terms'] is List)
                  for (final t in c['terms'] as List)
                    if (t is Map && t['id'] is String)
                      (
                        id: t['id'] as String,
                        name: (t['name'] as String?) ?? '',
                      ),
              ],
            ),
    ];
  }

  /// Adds a paper exam ([offeringId]) or changes one ([id]).
  Future<PaperExam?> save({
    String? id,
    String? offeringId,
    required String name,
    required String date,
    required num total,
    List<PaperPart>? parts,
    String? termId,
  }) async {
    final body = {
      'name': name,
      'exam_date': date,
      'total_marks': total,
      'parts': parts == null
          ? null
          : [
              for (final p in parts) {'name': p.name, 'marks': p.marks},
            ],
      'term_id': termId,
    };
    final r = id == null
        ? await _api.post(
            '/offline-exams',
            data: {...body, 'offering_id': offeringId},
          )
        : await _api.patch('/offline-exams/$id', data: body);
    return PaperExam.fromJson(r.payload);
  }

  Future<PaperMarksGrid> marks(String id) async =>
      _grid((await _api.get('/offline-exams/$id/marks')).payload);

  Future<PaperMarksGrid> saveMarks(
    String id,
    List<Map<String, Object?>> rows,
  ) async => _grid(
    (await _api.put('/offline-exams/$id/marks', data: {'rows': rows})).payload,
  );

  Future<void> publish(String id) =>
      _api.post('/offline-exams/$id/publish', data: const <String, Object>{});

  Future<void> remove(String id) => _api.delete('/offline-exams/$id');
}

final paperExamsRepositoryProvider = Provider<PaperExamsRepository>(
  (ref) => PaperExamsRepository(ref.watch(apiClientProvider)),
);

final paperExamsProvider = FutureProvider.autoDispose<List<PaperExam>>((ref) {
  ref.watch(workspaceKeyProvider);
  return ref.read(paperExamsRepositoryProvider).all();
}, retry: (retryCount, error) => null);

final paperClassChoicesProvider =
    FutureProvider.autoDispose<List<PaperClassChoice>>((ref) {
      ref.watch(workspaceKeyProvider);
      return ref.read(paperExamsRepositoryProvider).choices();
    }, retry: (retryCount, error) => null);

final paperMarksProvider = FutureProvider.autoDispose
    .family<PaperMarksGrid, String>((ref, id) {
      ref.watch(workspaceKeyProvider);
      return ref.read(paperExamsRepositoryProvider).marks(id);
    }, retry: (retryCount, error) => null);
