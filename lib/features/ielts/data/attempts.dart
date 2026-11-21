import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/ielts/data/builder.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';

/// A module attempt as My IELTS tests lists it.
typedef IeltsMyAttempt = ({String id, String status, String? mode, num? band});

/// An opening for the student's batch (`GET /ielts/my/assignments`).
typedef IeltsMyOpening = ({
  String id,
  DateTime? opens,
  DateTime? closes,
  bool isOpen,
  String testTitle,
  String purpose,
  List<String> modules,
  Map<String, int> durations,
  Map<String, IeltsMyAttempt> attempts,
});

List<IeltsMyOpening> myOpeningsFromJson(Object? p) => [
  if (p is List)
    for (final a in p)
      if (a is Map)
        () {
          final t = a['test'] is Map
              ? a['test'] as Map
              : const <String, Object?>{};
          final d = t['durations'];
          final at = a['attempts'];
          return (
            id: '${a['id']}',
            opens: DateTime.tryParse('${a['opens_at']}'),
            closes: DateTime.tryParse('${a['closes_at']}'),
            isOpen: a['is_open'] == true,
            testTitle: '${t['title'] ?? ''}',
            purpose: '${t['purpose'] ?? 'PRACTICE'}',
            modules: [
              for (final m in ieltsModules)
                if ((t['modules'] as List?)?.contains(m) ?? false) m,
            ],
            durations: {
              if (d is Map)
                for (final e in d.entries)
                  if (e.value is num) '${e.key}': (e.value as num).toInt(),
            },
            attempts: {
              if (at is Map)
                for (final e in at.entries)
                  if (e.value is Map)
                    '${e.key}': (
                      id: '${(e.value as Map)['id']}',
                      status: '${(e.value as Map)['status'] ?? ''}',
                      mode: (e.value as Map)['mode'] as String?,
                      band: (e.value as Map)['band'] as num?,
                    ),
            },
          );
        }(),
];

final myIeltsOpeningsProvider =
    FutureProvider.autoDispose<List<IeltsMyOpening>>((ref) async {
      ref.watch(workspaceKeyProvider);
      return myOpeningsFromJson(
        (await ref.read(apiClientProvider).get('/ielts/my/assignments'))
            .payload,
      );
    }, retry: (retryCount, error) => null);

/// A mock's modules run in this order; Speaking is with the examiner.
const ieltsMockSequence = ['LISTENING', 'READING', 'WRITING'];

/// Whether a mock's earlier modules still have to be handed in first.
bool waitsForEarlier(IeltsMyOpening o, String module) {
  if (o.purpose != 'MOCK') return false;
  final i = ieltsMockSequence.indexOf(module);
  if (i <= 0) return false;
  return ieltsMockSequence
      .take(i)
      .any(
        (m) =>
            o.modules.contains(m) &&
            !const {'SUBMITTED', 'MARKED'}.contains(o.attempts[m]?.status),
      );
}

/// A question on the paper; after hand-in it may carry the right answer
/// and the marks it got.
typedef PaperQuestion = ({
  String id,
  String? prompt,
  List<IeltsOption>? options,
  int numberFrom,
  int numberTo,
  List<String>? keys,
  List<String>? accepted,
  num? marks,
});

typedef PaperGroup = ({
  String id,
  String type,
  String instruction,
  List<IeltsOption> shared,
  String? gapText,
  String? imageFileId,
  int? numberFrom,
  int? numberTo,
  List<PaperQuestion> questions,
});

typedef PaperPart = ({
  String id,
  String module,
  int partNo,
  String? title,
  String? content,
  String? audioFileId,
  String? imageFileId,
  List<PaperGroup> groups,
});

/// `GET /ielts/my/attempts/:id`: the attempt, the paper (no answers until
/// they may be shown) and the student's answers.
typedef IeltsAttemptView = ({
  String id,
  String module,

  /// IN_PROGRESS, SUBMITTED or MARKED.
  String status,
  String? mode,
  DateTime? deadline,

  /// The server's clock when it answered (the device's may be wrong).
  DateTime? now,
  num? rawScore,
  num? rawTotal,
  num? band,
  Map<String, Object?>? criteria,
  String? feedback,
  Map<String, String> recordings,
  String testTitle,
  String purpose,

  /// Null after hand-in while the answers may not be shown yet.
  List<PaperPart>? parts,
  Map<String, String> answers,
});

List<IeltsOption> _opts(Object? raw) => [
  if (raw is List)
    for (final o in raw)
      if (o is Map) (key: '${o['key'] ?? ''}', text: '${o['text'] ?? ''}'),
];

List<String>? _strs(Object? raw) =>
    raw is List ? [for (final s in raw) '$s'] : null;

PaperGroup _group(Map<dynamic, dynamic> g) {
  final shared = g['shared'] is Map ? g['shared'] as Map : null;
  return (
    id: '${g['id']}',
    type: '${g['type']}',
    instruction: '${g['instruction'] ?? ''}',
    shared: _opts(shared?['options']),
    gapText: shared?['text'] as String?,
    imageFileId: g['image_file_id'] as String?,
    numberFrom: (g['number_from'] as num?)?.toInt(),
    numberTo: (g['number_to'] as num?)?.toInt(),
    questions: [
      for (final q in (g['questions'] as List?) ?? const [])
        if (q is Map)
          (
            id: '${q['id']}',
            prompt: q['prompt'] as String?,
            options: q['options'] is List ? _opts(q['options']) : null,
            numberFrom: (q['number_from'] as num?)?.toInt() ?? 0,
            numberTo:
                (q['number_to'] as num?)?.toInt() ??
                (q['number_from'] as num?)?.toInt() ??
                0,
            keys: q['key'] is Map ? _strs((q['key'] as Map)['keys']) : null,
            accepted: q['key'] is Map
                ? _strs((q['key'] as Map)['accepted'])
                : null,
            marks: q['marks'] as num?,
          ),
    ],
  );
}

IeltsAttemptView? attemptFromJson(Object? j) {
  if (j is! Map || j['attempt'] is! Map) return null;
  final a = j['attempt'] as Map;
  final t = j['test'] is Map ? j['test'] as Map : const <String, Object?>{};
  final rec = a['recordings'];
  final ans = j['answers'];
  return (
    id: '${a['id']}',
    module: '${a['module']}',
    status: '${a['status'] ?? 'IN_PROGRESS'}',
    mode: a['mode'] as String?,
    deadline: DateTime.tryParse('${a['deadline']}'),
    now: DateTime.tryParse('${a['now']}'),
    rawScore: a['raw_score'] as num?,
    rawTotal: a['raw_total'] as num?,
    band: a['band'] as num?,
    criteria: a['criteria'] is Map
        ? (a['criteria'] as Map).cast<String, Object?>()
        : null,
    feedback: a['feedback'] as String?,
    recordings: {
      if (rec is Map)
        for (final e in rec.entries)
          if (e.value != null) '${e.key}': '${e.value}',
    },
    testTitle: '${t['title'] ?? ''}',
    purpose: '${t['purpose'] ?? 'PRACTICE'}',
    parts: j['parts'] is List
        ? [
            for (final p in j['parts'] as List)
              if (p is Map)
                (
                  id: '${p['id']}',
                  module: '${p['module']}',
                  partNo: (p['part_no'] as num?)?.toInt() ?? 1,
                  title: p['title'] as String?,
                  content: p['content'] as String?,
                  audioFileId: p['audio_file_id'] as String?,
                  imageFileId: p['image_file_id'] as String?,
                  groups: [
                    for (final g in (p['groups'] as List?) ?? const [])
                      if (g is Map) _group(g),
                  ],
                ),
          ]
        : null,
    answers: {
      if (ans is Map)
        for (final e in ans.entries)
          if (e.value != null) '${e.key}': '${e.value}',
    },
  );
}

/// Words in a Writing script, numbers included, as the real test counts.
int essayWords(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

/// Words Task 1 and Task 2 ask for; fewer is shown, not blocked.
const ieltsMinWords = {1: 150, 2: 250};

/// The official order of the marking criteria.
const ieltsCriteriaOrder = ['TA', 'TR', 'FC', 'CC', 'LR', 'GRA', 'P'];

/// Questions not answered yet, counting the numbers each takes.
int unansweredNumbers(List<PaperPart> parts, Map<String, String> answers) {
  var n = 0;
  for (final p in parts) {
    for (final g in p.groups) {
      for (final q in g.questions) {
        if ((answers[q.id] ?? '').isEmpty) n += q.numberTo - q.numberFrom + 1;
      }
    }
  }
  return n;
}

/// One entry of `PUT …/answers`: a Writing script per task (part), else an
/// answer per question.
Map<String, Object?> answerEntry(String module, String id, String? answer) =>
    module == 'WRITING'
    ? {'part_id': id, 'answer': answer}
    : {'question_id': id, 'answer': answer};
