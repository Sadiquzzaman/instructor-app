import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';

/// Where a group's choices come from (backend `question-groups.ts`): the
/// question's own options, the group's shared list, a fixed set, or written
/// answers.
enum IeltsChoices { question, shared, fixed, text }

/// The 16 question-group types of the real paper, as the API checks them.
const ieltsGroupRules =
    <
      String,
      ({IeltsChoices choices, List<String> modules, List<String>? fixed})
    >{
      'MCQ_SINGLE': (choices: IeltsChoices.question, modules: _lr, fixed: null),
      'MCQ_MULTI': (choices: IeltsChoices.question, modules: _lr, fixed: null),
      'TFNG': (
        choices: IeltsChoices.fixed,
        modules: _r,
        fixed: ['TRUE', 'FALSE', 'NOT GIVEN'],
      ),
      'YNNG': (
        choices: IeltsChoices.fixed,
        modules: _r,
        fixed: ['YES', 'NO', 'NOT GIVEN'],
      ),
      'MATCH_HEADINGS': (
        choices: IeltsChoices.shared,
        modules: _r,
        fixed: null,
      ),
      'MATCH_INFO': (choices: IeltsChoices.shared, modules: _r, fixed: null),
      'MATCH_FEATURES': (
        choices: IeltsChoices.shared,
        modules: _lr,
        fixed: null,
      ),
      'MATCH_ENDINGS': (choices: IeltsChoices.shared, modules: _r, fixed: null),
      'SENTENCE_COMPLETION': (
        choices: IeltsChoices.text,
        modules: _lr,
        fixed: null,
      ),
      'SUMMARY_COMPLETION': (
        choices: IeltsChoices.text,
        modules: _lr,
        fixed: null,
      ),
      'NOTE_COMPLETION': (
        choices: IeltsChoices.text,
        modules: _lr,
        fixed: null,
      ),
      'TABLE_COMPLETION': (
        choices: IeltsChoices.text,
        modules: _lr,
        fixed: null,
      ),
      'FLOWCHART_COMPLETION': (
        choices: IeltsChoices.text,
        modules: _lr,
        fixed: null,
      ),
      'FORM_COMPLETION': (
        choices: IeltsChoices.text,
        modules: ['LISTENING'],
        fixed: null,
      ),
      'DIAGRAM_LABEL': (choices: IeltsChoices.text, modules: _lr, fixed: null),
      'SHORT_ANSWER': (choices: IeltsChoices.text, modules: _lr, fixed: null),
    };

const _lr = ['LISTENING', 'READING'];
const _r = ['READING'];

/// Completion types show their text with gaps; their answers can come from
/// a word box instead.
bool isCompletion(String type) =>
    ieltsGroupRules[type]?.choices == IeltsChoices.text &&
    type != 'SHORT_ANSWER';

/// The group types a module uses, in the web's order.
List<String> groupTypesFor(String module) => [
  for (final e in ieltsGroupRules.entries)
    if (e.value.modules.contains(module)) e.key,
];

/// The next free letter for a new option: A, B, C…
String nextKey(Iterable<String> keys) {
  for (var i = 0; i < 26; i++) {
    final k = String.fromCharCode(65 + i);
    if (!keys.contains(k)) return k;
  }
  return '';
}

typedef IeltsOption = ({String key, String text});

List<IeltsOption> _options(Object? raw) => [
  if (raw is List)
    for (final o in raw)
      if (o is Map) (key: '${o['key'] ?? ''}', text: '${o['text'] ?? ''}'),
];

List<String> _strings(Object? raw) => [
  if (raw is List)
    for (final s in raw) '$s',
];

/// A question of a group: its prompt, own options (multiple choice), the
/// right keys or accepted spellings, and the numbers (1–40) it takes.
typedef IeltsQuestion = ({
  String id,
  String? prompt,
  List<IeltsOption>? options,
  List<String> keys,
  List<String> accepted,
  int? numberFrom,
  int? numberTo,
});

typedef IeltsGroup = ({
  String id,
  String type,
  String instruction,
  int? wordLimit,
  List<IeltsOption>? sharedOptions,
  String? sharedText,
  String? imageFileId,
  int? numberFrom,
  int? numberTo,
  List<IeltsQuestion> questions,
});

typedef IeltsPart = ({
  String id,
  String module,
  int partNo,
  String? title,

  /// HTML from the web's editor (passages, tasks, Speaking questions).
  String? content,
  String? audioFileId,
  String? imageFileId,
  List<IeltsGroup> groups,
});

typedef IeltsTest = ({
  String id,
  String title,
  String purpose,
  String testType,
  String status,
  List<String> modules,

  /// Seconds per module.
  Map<String, int> durations,
  bool canEdit,
  bool needsReview,
  List<IeltsPart> parts,
});

int? _int(Object? v) => (v as num?)?.toInt();

IeltsGroup _group(Map<dynamic, dynamic> g) {
  final shared = g['shared'] is Map ? g['shared'] as Map : null;
  return (
    id: '${g['id']}',
    type: '${g['type']}',
    instruction: '${g['instruction'] ?? ''}',
    wordLimit: _int(g['word_limit']),
    sharedOptions: shared?['options'] is List
        ? _options(shared!['options'])
        : null,
    sharedText: shared?['text'] as String?,
    imageFileId: g['image_file_id'] as String?,
    numberFrom: _int(g['number_from']),
    numberTo: _int(g['number_to']),
    questions: [
      for (final q in (g['questions'] as List?) ?? const [])
        if (q is Map)
          (
            id: '${q['id']}',
            prompt: q['prompt'] as String?,
            options: q['options'] is List ? _options(q['options']) : null,
            keys: q['answer'] is Map
                ? _strings((q['answer'] as Map)['keys'])
                : [],
            accepted: q['answer'] is Map
                ? _strings((q['answer'] as Map)['accepted'])
                : [],
            numberFrom: _int(q['number_from']),
            numberTo: _int(q['number_to']),
          ),
    ],
  );
}

IeltsTest? ieltsTestFromJson(Object? j) {
  if (j is! Map || j['id'] == null) return null;
  final d = j['durations'];
  return (
    id: '${j['id']}',
    title: '${j['title'] ?? ''}',
    purpose: '${j['purpose'] ?? 'PRACTICE'}',
    testType: '${j['test_type'] ?? 'ACADEMIC'}',
    status: '${j['status'] ?? 'DRAFT'}',
    modules: [
      for (final m in ieltsModules)
        if ((j['modules'] as List?)?.contains(m) ?? false) m,
    ],
    durations: {
      if (d is Map)
        for (final e in d.entries)
          if (e.value is num) '${e.key}': (e.value as num).toInt(),
    },
    canEdit: j['can_edit'] == true,
    needsReview: j['needs_review'] == true,
    parts: [
      for (final p in (j['parts'] as List?) ?? const [])
        if (p is Map)
          (
            id: '${p['id']}',
            module: '${p['module']}',
            partNo: _int(p['part_no']) ?? 1,
            title: p['title'] as String?,
            content: p['content'] as String?,
            audioFileId: p['audio_file_id'] as String?,
            imageFileId: p['image_file_id'] as String?,
            groups: [
              for (final g in (p['groups'] as List?) ?? const [])
                if (g is Map) _group(g),
            ],
          ),
    ],
  );
}

final ieltsTestProvider = FutureProvider.autoDispose.family<IeltsTest?, String>(
  (ref, id) async {
    ref.watch(workspaceKeyProvider);
    return ieltsTestFromJson(
      (await ref.read(apiClientProvider).get('/ielts/tests/$id')).payload,
    );
  },
  retry: (retryCount, error) => null,
);

/// A question as the group editor holds it.
class QuestionDraft {
  QuestionDraft({
    this.id,
    this.prompt = '',
    List<IeltsOption>? options,
    List<String>? keys,
    List<String>? accepted,
  }) : options = options ?? blankOptions(),
       keys = keys ?? [],
       accepted = accepted ?? [];

  final String? id;
  String prompt;
  List<IeltsOption> options;
  List<String> keys;
  List<String> accepted;
}

List<IeltsOption> blankOptions() => [
  for (final k in ['A', 'B', 'C', 'D']) (key: k, text: ''),
];

/// The body of `POST …/parts/:partId/groups` and `PUT …/groups/:groupId`,
/// as the web's GroupDrawer sends it.
Map<String, Object?> groupBody({
  required String type,
  required String instruction,
  int? wordLimit,
  bool wordBox = false,
  List<IeltsOption> sharedOptions = const [],
  String sharedText = '',
  String? imageFileId,
  required List<QuestionDraft> questions,
}) {
  final rule = ieltsGroupRules[type]!;
  final usesShared =
      rule.choices == IeltsChoices.shared ||
      (rule.choices == IeltsChoices.text && wordBox);
  final writes = rule.choices == IeltsChoices.text && !wordBox;
  final text = isCompletion(type) && sharedText.trim().isNotEmpty;
  Map<String, Object?> opts(IeltsOption o) => {
    'key': o.key.trim(),
    'text': o.text.trim(),
  };
  return {
    'type': type,
    'instruction': instruction.trim(),
    'word_limit': writes ? wordLimit : null,
    'shared': usesShared || text
        ? {
            if (usesShared) 'options': [for (final o in sharedOptions) opts(o)],
            if (text) 'text': sharedText,
          }
        : null,
    'image_file_id': imageFileId,
    'questions': [
      for (final q in questions)
        {
          'id': ?q.id,
          'prompt': q.prompt.trim().isEmpty ? null : q.prompt.trim(),
          'options': rule.choices == IeltsChoices.question
              ? [for (final o in q.options) opts(o)]
              : null,
          'answer': writes
              ? {
                  'accepted': [
                    for (final a in q.accepted)
                      if (a.trim().isNotEmpty) a.trim(),
                  ],
                }
              : {'keys': q.keys},
        },
    ],
  };
}

/// "Questions 1–5" numbers of a group or question.
String numbersText(int? from, int? to) =>
    from == null || to == null ? '' : (from == to ? '$from' : '$from–$to');
