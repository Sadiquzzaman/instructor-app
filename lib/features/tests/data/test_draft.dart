import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';

final _random = Random.secure();

/// A random UUID v4, as the web's wizard gives new questions and options.
String newId() {
  final b = List<int>.generate(16, (_) => _random.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String hex(int from, int to) =>
      [for (var i = from; i < to; i++) b[i].toRadixString(16).padLeft(2, '0')]
          .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

/// One answer choice.
@immutable
class DraftOption {
  const DraftOption({required this.id, this.text = '', this.image});

  final String id;
  final String text;
  final String? image;

  DraftOption copyWith({
    String? text,
    String? image,
    bool clearImage = false,
  }) => DraftOption(
    id: id,
    text: text ?? this.text,
    image: clearImage ? null : image ?? this.image,
  );

  Map<String, Object?> toJson() => {'id': id, 'text': text, 'image': image};

  static DraftOption fromJson(Map<String, Object?> j) => DraftOption(
    id: (j['id'] as String?) ?? newId(),
    text: (j['text'] as String?) ?? '',
    image: j['image'] as String?,
  );
}

/// A question in the wizard (`WizardGradedQuestionDto` /
/// `WizardUngradedQuestionDto`): text is plain text in the app (Stage 4 plan
/// §7.1 A), sent as simple HTML.
@immutable
class DraftQuestion {
  const DraftQuestion({
    required this.id,
    required this.type,
    required this.subType,
    this.text = '',
    this.instruction = '',
    this.image,
    this.options = const [],
    this.left = const [],
    this.right = const [],
    this.answer = const [],
    this.points = 1,
    this.children = const [],
    this.language = 'bn',
  });

  /// A new multiple-choice question with the fewest options it may have.
  factory DraftQuestion.multipleChoice() =>
      DraftQuestion.create('multiple-choice');

  /// A new graded question of [subType], as the web's `createQuestion`:
  /// choice types start with [minVariableOptions] empty options, true/false
  /// with its fixed three.
  ///
  /// [type] is graded, ungraded (no options or answer: the teacher marks
  /// it) or passage-question (a question inside a passage).
  factory DraftQuestion.create(String subType, {String type = 'graded'}) =>
      DraftQuestion(
        id: newId(),
        type: type,
        subType: subType,
        options: _startOptions(subType, type),
        left: _startPairs(subType),
        right: _startPairs(subType),
        answer: subType == 'fill-in-the-blanks' ? const ['', ''] : const [],
      );

  /// A new passage with one multiple-choice question under it (the web's
  /// `createPassageQuestion`); instructions in Bangla by default.
  factory DraftQuestion.passage() => DraftQuestion(
    id: newId(),
    type: passageType,
    subType: passageSubType,
    children: [DraftQuestion.create('multiple-choice', type: passageType)],
  );

  bool get isPassage => subType == passageSubType;

  /// The marks this item adds: a passage adds its questions'.
  num get marks =>
      isPassage ? children.fold<num>(0, (s, c) => s + c.points) : points;

  /// Whether the teacher marks it by hand (no answer to send).
  bool get manual => type == 'ungraded' || subType == 'essay';

  /// A copy with new ids throughout; the correct answers follow the copied
  /// options.
  DraftQuestion duplicate() {
    final ids = <String, String>{};
    List<DraftOption> copy(List<DraftOption> side) => [
      for (final o in side)
        DraftOption(
          id: ids.putIfAbsent(o.id, newId),
          text: o.text,
          image: o.image,
        ),
    ];
    final options = copy(this.options);
    return DraftQuestion(
      id: newId(),
      type: type,
      subType: subType,
      text: text,
      instruction: instruction,
      image: image,
      options: options,
      left: copy(left),
      right: copy(right),
      answer: [for (final a in answer) ids[a] ?? a],
      points: points,
      children: [for (final c in children) c.duplicate()],
      language: language,
    );
  }

  /// The same question as another type, keeping what still fits (the web's
  /// `changeQuestionSubtype`).
  DraftQuestion withSubType(String next) {
    if (next == subType) return this;
    final keep = isVariableChoice(subType) && isVariableChoice(next);
    return DraftQuestion(
      id: id,
      type: type,
      subType: next,
      text: text,
      instruction: instruction,
      image: image,
      options: keep ? options : _startOptions(next, type),
      left: next == 'matching-ordering'
          ? (left.isEmpty ? _startPairs(next) : left)
          : const [],
      right: next == 'matching-ordering'
          ? (right.isEmpty ? _startPairs(next) : right)
          : const [],
      answer: keep
          ? (next == 'multiple-choice' ? answer.take(1).toList() : answer)
          : next == 'fill-in-the-blanks'
          ? const ['', '']
          : const [],
      points: points,
      language: language,
    );
  }

  final String id;

  /// graded, ungraded or passage-question.
  final String type;
  final String subType;
  final String text;
  final String instruction;
  final String? image;
  final List<DraftOption> options;

  /// Matching: left item i pairs with right item i (the web's
  /// `matchingOptions`; students see them shuffled).
  final List<DraftOption> left;
  final List<DraftOption> right;

  /// The correct option ids; for fill in the blanks the answer and an
  /// alternative.
  final List<String> answer;
  final num points;

  /// A passage's questions ([text] is the passage itself).
  final List<DraftQuestion> children;

  /// A passage's instruction language: bn or en.
  final String language;

  DraftQuestion copyWith({
    String? text,
    String? instruction,
    String? image,
    bool clearImage = false,
    List<DraftOption>? options,
    List<DraftOption>? left,
    List<DraftOption>? right,
    List<String>? answer,
    num? points,
    List<DraftQuestion>? children,
    String? language,
  }) => DraftQuestion(
    id: id,
    type: type,
    subType: subType,
    text: text ?? this.text,
    instruction: instruction ?? this.instruction,
    image: clearImage ? null : image ?? this.image,
    options: options ?? this.options,
    left: left ?? this.left,
    right: right ?? this.right,
    answer: answer ?? this.answer,
    points: points ?? this.points,
    children: children ?? this.children,
    language: language ?? this.language,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'subType': subType,
    'text': text,
    'instruction': instruction,
    'image': image,
    'options': [for (final o in options) o.toJson()],
    'left': [for (final o in left) o.toJson()],
    'right': [for (final o in right) o.toJson()],
    'answer': answer,
    'points': points,
    if (children.isNotEmpty) 'children': [for (final c in children) c.toJson()],
    'language': language,
  };

  static DraftQuestion fromJson(Map<String, Object?> j) => DraftQuestion(
    id: (j['id'] as String?) ?? newId(),
    type: (j['type'] as String?) ?? 'graded',
    subType: (j['subType'] as String?) ?? 'multiple-choice',
    text: (j['text'] as String?) ?? '',
    instruction: (j['instruction'] as String?) ?? '',
    image: j['image'] as String?,
    options: [
      if (j['options'] is List)
        for (final o in j['options'] as List)
          if (o is Map) DraftOption.fromJson(o.cast<String, Object?>()),
    ],
    left: _optionsFrom(j['left']),
    right: _optionsFrom(j['right']),
    answer: [
      if (j['answer'] is List)
        for (final a in j['answer'] as List) '$a',
    ],
    points: (j['points'] as num?) ?? 1,
    children: [
      if (j['children'] is List)
        for (final c in j['children'] as List)
          if (c is Map) DraftQuestion.fromJson(c.cast<String, Object?>()),
    ],
    language: j['language'] == 'en' ? 'en' : 'bn',
  );

  /// The web's wizard body for this question (`WizardPassageQuestionDto`
  /// for a passage).
  Map<String, Object?> toBody() => isPassage
      ? {
          'id': id,
          'type': passageType,
          'passageText': plainToHtml(text),
          'instructionLanguage': language,
          'childQuestions': [for (final c in children) c.toBody()],
        }
      : _questionBody();

  Map<String, Object?> _questionBody() => {
    'id': id,
    'type': type,
    'subType': subType,
    'text': plainToHtml(text),
    if (instruction.trim().isNotEmpty) 'instruction': instruction.trim(),
    'image': ?image,
    if (options.isNotEmpty)
      'options': [
        for (final o in options)
          {'id': o.id, 'text': o.text.trim(), 'image': o.image},
      ],
    if (subType == 'matching-ordering')
      'matchingOptions': {
        'left': [
          for (final o in left) {'id': o.id, 'text': o.text.trim()},
        ],
        'right': [
          for (final o in right) {'id': o.id, 'text': o.text.trim()},
        ],
      },
    if (!manual) 'answer': _answerBody(),
    'points': points,
  };

  Map<String, Object?> _answerBody() {
    if (subType == 'matching-ordering') {
      return {
        'type': 'matchingOrdering',
        'value': [
          for (var i = 0; i < left.length && i < right.length; i++)
            '${left[i].id}$matchingPairDelimiter${right[i].id}',
        ],
      };
    }
    if (subType == 'fill-in-the-blanks') {
      final primary = answer.isEmpty ? '' : answer.first.trim();
      final alternative = answer.length > 1 ? answer[1].trim() : '';
      return {
        'type': 'text',
        'value': [primary, if (primary.isEmpty) '' else alternative],
      };
    }
    return {'type': 'optionId', 'value': answer};
  }
}

List<DraftOption> _optionsFrom(Object? raw) => [
  if (raw is List)
    for (final o in raw)
      if (o is Map) DraftOption.fromJson(o.cast<String, Object?>()),
];

/// The web's matching limits and pair delimiter.
const minMatchingPairs = 2;
const maxMatchingPairs = 5;
const matchingPairDelimiter = '::';

List<DraftOption> _startPairs(String subType) => subType == 'matching-ordering'
    ? [for (var i = 0; i < minMatchingPairs; i++) DraftOption(id: newId())]
    : const [];

/// The web's option limits for multiple choice and multiple response.
const minVariableOptions = 3;
const maxVariableOptions = 5;

/// True / False / Not Given, as the web's fixed options (data, sent as is).
const trueFalseOptions = ['True', 'False', 'Not Given'];

bool isVariableChoice(String subType) =>
    subType == 'multiple-choice' || subType == 'multiple-response';

/// The web's passage block type, and the app's marker for a passage.
const passageType = 'passage-question';
const passageSubType = 'passage';

/// What a teacher may add under each category (the web's tabs).
const ungradedTypes = ['true-false', 'essay', 'fill-in-the-gaps'];

List<DraftOption> _startOptions(String subType, String type) =>
    type == 'ungraded' ? const [] : _choiceOptions(subType);

List<DraftOption> _choiceOptions(String subType) => subType == 'true-false'
    ? [for (final t in trueFalseOptions) DraftOption(id: newId(), text: t)]
    : isVariableChoice(subType)
    ? [for (var i = 0; i < minVariableOptions; i++) DraftOption(id: newId())]
    : const [];

/// Plain text as the simple HTML the web stores: paragraphs, with the
/// characters HTML needs escaped.
String plainToHtml(String text) {
  String esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  final paras = [
    for (final p in text.trim().split(RegExp(r'\n\s*\n')))
      if (p.trim().isNotEmpty)
        '<p>${esc(p.trim()).replaceAll('\n', '<br>')}</p>',
  ];
  return paras.join();
}

/// A subject block (`WizardSubjectBlockDto`).
@immutable
class DraftSubject {
  const DraftSubject({
    required this.id,
    required this.name,
    this.questions = const [],
  });

  final String id;
  final String name;
  final List<DraftQuestion> questions;

  DraftSubject copyWith({List<DraftQuestion>? questions}) =>
      DraftSubject(id: id, name: name, questions: questions ?? this.questions);

  num get totalMarks => questions.fold<num>(0, (s, q) => s + q.marks);

  /// Questions, counting each of a passage's (the web's count).
  int get questionCount => questions.fold<int>(
    0,
    (s, q) => s + (q.isPassage ? q.children.length : 1),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'questions': [for (final q in questions) q.toJson()],
  };

  static DraftSubject fromJson(Map<String, Object?> j) => DraftSubject(
    id: (j['id'] as String?) ?? '',
    name: (j['name'] as String?) ?? '',
    questions: [
      if (j['questions'] is List)
        for (final q in j['questions'] as List)
          if (q is Map) DraftQuestion.fromJson(q.cast<String, Object?>()),
    ],
  );
}

/// The whole wizard (`CreateExamWizardDto`), kept on the device until saved.
@immutable
class TestDraft {
  const TestDraft({
    this.step = 0,
    this.name = '',
    this.duration = '',
    this.passingScore = '',
    this.isModelTest = false,
    this.negative = false,
    this.negativePercent = '',
    this.proctoringLevel,
    this.classId,
    this.offeringId,
    this.subjects = const [],
    this.publishNow = true,
    this.scheduleAt,
    this.endingAt,
    this.audience = 'selected_class',
    this.excluded = const [],
    this.order = const [],
    this.activeSubjectId,
  });

  final int step;
  final String name;
  final String duration;
  final String passingScore;
  final bool isModelTest;
  final bool negative;
  final String negativePercent;

  /// OFF, LIGHT or STRICT; null leaves the plan's best level.
  final String? proctoringLevel;
  final String? classId;
  final String? offeringId;
  final List<DraftSubject> subjects;
  final bool publishNow;
  final DateTime? scheduleAt;
  final DateTime? endingAt;

  /// anyone or selected_class.
  final String audience;
  final List<String> excluded;

  /// The order students see (the web's `questionOrder`: question and
  /// passage ids across subjects); empty until reordered.
  final List<String> order;

  /// The subject whose questions are open (a model test has several).
  final String? activeSubjectId;

  DraftSubject? get subject => subjects.isEmpty ? null : subjects.first;

  /// The open subject: [activeSubjectId], or the first.
  DraftSubject? get activeSubject =>
      subjects.where((s) => s.id == activeSubjectId).firstOrNull ?? subject;

  /// Every question and passage in the order students see: [order] where
  /// it still applies, then any added since, subject by subject.
  List<(DraftSubject, DraftQuestion)> get ordered {
    final all = {
      for (final s in subjects)
        for (final q in s.questions) q.id: (s, q),
    };
    final out = [
      for (final id in order)
        if (all.containsKey(id)) all[id]!,
    ];
    final seen = {for (final (_, q) in out) q.id};
    return [
      ...out,
      for (final e in all.entries)
        if (!seen.contains(e.key)) e.value,
    ];
  }

  int get questionCount => subjects.fold<int>(0, (s, x) => s + x.questionCount);

  List<DraftQuestion> get questions => [
    for (final s in subjects) ...s.questions,
  ];

  num get totalMarks => subjects.fold<num>(0, (s, x) => s + x.totalMarks);

  TestDraft copyWith({
    int? step,
    String? name,
    String? duration,
    String? passingScore,
    bool? isModelTest,
    bool? negative,
    String? negativePercent,
    String? proctoringLevel,
    String? classId,
    bool clearClass = false,
    String? offeringId,
    bool clearOffering = false,
    List<DraftSubject>? subjects,
    bool? publishNow,
    DateTime? scheduleAt,
    DateTime? endingAt,
    String? audience,
    List<String>? excluded,
    List<String>? order,
    String? activeSubjectId,
  }) => TestDraft(
    step: step ?? this.step,
    name: name ?? this.name,
    duration: duration ?? this.duration,
    passingScore: passingScore ?? this.passingScore,
    isModelTest: isModelTest ?? this.isModelTest,
    negative: negative ?? this.negative,
    negativePercent: negativePercent ?? this.negativePercent,
    proctoringLevel: proctoringLevel ?? this.proctoringLevel,
    classId: clearClass ? null : classId ?? this.classId,
    offeringId: clearOffering || clearClass
        ? null
        : offeringId ?? this.offeringId,
    subjects: subjects ?? this.subjects,
    publishNow: publishNow ?? this.publishNow,
    scheduleAt: scheduleAt ?? this.scheduleAt,
    endingAt: endingAt ?? this.endingAt,
    audience: audience ?? this.audience,
    excluded: excluded ?? this.excluded,
    order: order ?? this.order,
    activeSubjectId: activeSubjectId ?? this.activeSubjectId,
  );

  Map<String, Object?> toJson() => {
    'step': step,
    'name': name,
    'duration': duration,
    'passingScore': passingScore,
    'isModelTest': isModelTest,
    'negative': negative,
    'negativePercent': negativePercent,
    'proctoringLevel': proctoringLevel,
    'classId': classId,
    'offeringId': offeringId,
    'subjects': [for (final s in subjects) s.toJson()],
    'publishNow': publishNow,
    'scheduleAt': scheduleAt?.toUtc().toIso8601String(),
    'endingAt': endingAt?.toUtc().toIso8601String(),
    'audience': audience,
    'excluded': excluded,
    'order': order,
    'activeSubjectId': activeSubjectId,
  };

  static TestDraft fromJson(Map<String, Object?> j) => TestDraft(
    step: (j['step'] as num?)?.toInt() ?? 0,
    name: (j['name'] as String?) ?? '',
    duration: (j['duration'] as String?) ?? '',
    passingScore: (j['passingScore'] as String?) ?? '',
    isModelTest: j['isModelTest'] == true,
    negative: j['negative'] == true,
    negativePercent: (j['negativePercent'] as String?) ?? '',
    proctoringLevel: j['proctoringLevel'] as String?,
    classId: j['classId'] as String?,
    offeringId: j['offeringId'] as String?,
    subjects: [
      if (j['subjects'] is List)
        for (final s in j['subjects'] as List)
          if (s is Map) DraftSubject.fromJson(s.cast<String, Object?>()),
    ],
    publishNow: j['publishNow'] != false,
    scheduleAt: j['scheduleAt'] is String
        ? DateTime.tryParse(j['scheduleAt'] as String)
        : null,
    endingAt: j['endingAt'] is String
        ? DateTime.tryParse(j['endingAt'] as String)
        : null,
    audience: (j['audience'] as String?) ?? 'selected_class',
    excluded: [
      if (j['excluded'] is List)
        for (final e in j['excluded'] as List) '$e',
    ],
    order: [
      if (j['order'] is List)
        for (final e in j['order'] as List) '$e',
    ],
    activeSubjectId: j['activeSubjectId'] as String?,
  );

  /// The web's `POST /exams` body (`CreateExamWizardDto`). [now] fills the
  /// times when publishing now (the web: now, ending three days later).
  Map<String, Object?> toBody(DateTime now) {
    final start = publishNow ? now : scheduleAt ?? now;
    final end = publishNow
        ? now.add(const Duration(days: 3))
        : endingAt ?? start.add(const Duration(days: 3));
    final withQuestions = [
      for (final s in subjects)
        if (s.questions.isNotEmpty) s,
    ];
    return {
      'formState': {
        'testName': name.trim(),
        'examCategory': 'academic',
        'duration': num.tryParse(duration.trim()),
        if (passingScore.trim().isNotEmpty)
          'passingScore': num.tryParse(passingScore.trim()),
        'isModelTest': isModelTest,
        'allowNegativeMarking': negative,
        if (negative) 'negativeMarking': num.tryParse(negativePercent.trim()),
        if (proctoringLevel != null) 'proctoring': {'level': proctoringLevel},
      },
      'subjects': [
        for (final s in withQuestions)
          {
            'id': s.id,
            'name': s.name,
            'questions': [for (final q in s.questions) q.toBody()],
          },
      ],
      'questionOrder': [for (final (_, q) in ordered) q.id],
      'publishState': {
        'testAudience': audience,
        'publishTiming': publishNow ? 'immediately' : 'later',
        'scheduleAt': start.toUtc().toIso8601String(),
        'endingAt': end.toUtc().toIso8601String(),
        if (audience == 'selected_class') ...{
          'selectedClassId': classId,
          'excluded_students': excluded,
          'selectedOfferingId': ?offeringId,
        },
      },
    };
  }
}

/// What is wrong with a question, as the web's validation keys: `title`
/// (text or image), `titleText` (text), `points`, `answer`, `optionCount`,
/// `optionEmpty:<n>`, `pickOne`, `pickTwo`, `pairs`, `leftEmpty:<n>`,
/// `rightEmpty:<n>`.
///
/// A passage has `passage` (no text) and `children` (one of its questions
/// has a problem, shown under that question).
List<String> questionProblems(DraftQuestion q) {
  if (q.isPassage) {
    return [
      if (q.text.trim().isEmpty) 'passage',
      if (q.children.isEmpty || q.children.any(_hasProblems)) 'children',
    ];
  }
  final out = <String>[];
  final matching = q.subType == 'matching-ordering';
  if (matching && q.text.trim().isEmpty) {
    out.add('titleText');
  } else if (q.text.trim().isEmpty && q.image == null) {
    out.add('title');
  }
  if (q.points <= 0) out.add('points');
  if (q.subType == 'fill-in-the-blanks' &&
      (q.answer.isEmpty || q.answer.first.trim().isEmpty)) {
    out.add('answer');
  }
  if (matching) {
    final l = q.left.length;
    final r = q.right.length;
    if (l < minMatchingPairs ||
        l > maxMatchingPairs ||
        r < minMatchingPairs ||
        r > maxMatchingPairs ||
        l != r) {
      out.add('pairs');
    }
    for (final (i, o) in q.left.indexed) {
      if (o.text.trim().isEmpty) out.add('leftEmpty:${i + 1}');
    }
    for (final (i, o) in q.right.indexed) {
      if (o.text.trim().isEmpty) out.add('rightEmpty:${i + 1}');
    }
  }
  final choice = isVariableChoice(q.subType);
  if (choice) {
    if (q.options.length < minVariableOptions ||
        q.options.length > maxVariableOptions) {
      out.add('optionCount');
    }
    for (final (i, o) in q.options.indexed) {
      if (o.text.trim().isEmpty && o.image == null) {
        out.add('optionEmpty:${i + 1}');
      }
    }
    final picked = q.answer
        .where((a) => q.options.any((o) => o.id == a))
        .length;
    if (q.subType == 'multiple-choice' && picked != 1) out.add('pickOne');
    if (q.subType == 'multiple-response' && picked < 2) out.add('pickTwo');
  }
  if (q.subType == 'true-false' && q.type != 'ungraded') {
    final picked = q.answer
        .where((a) => q.options.any((o) => o.id == a))
        .length;
    if (picked != 1) out.add('pickOne');
  }
  return out;
}

bool _hasProblems(DraftQuestion q) => questionProblems(q).isNotEmpty;

const _draftPrefix = 'draft.test.';

/// The test being made, kept on the device per workspace (Stage 4 plan
/// §7.4) so a restart doesn't lose it; cleared when saved or on sign-out.
class TestDraftStore {
  TestDraftStore(this._prefs, this._workspace);

  final SharedPreferences _prefs;
  final String? _workspace;

  String? get _key => _workspace == null ? null : '$_draftPrefix$_workspace';

  TestDraft? load() {
    final k = _key;
    final raw = k == null ? null : _prefs.getString(k);
    if (raw == null) return null;
    try {
      return TestDraft.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } on FormatException {
      return null;
    }
  }

  Future<void> save(TestDraft d) async {
    final k = _key;
    if (k != null) await _prefs.setString(k, jsonEncode(d.toJson()));
  }

  Future<void> clear() async {
    final k = _key;
    if (k != null) await _prefs.remove(k);
  }

  /// Every workspace's draft (sign-out).
  static Future<void> clearAll(SharedPreferences prefs) async {
    for (final k in [
      for (final k in prefs.getKeys())
        if (k.startsWith(_draftPrefix)) k,
    ]) {
      await prefs.remove(k);
    }
  }
}

final testDraftStoreProvider = Provider<TestDraftStore>(
  (ref) => TestDraftStore(
    ref.watch(sharedPreferencesProvider),
    ref.watch(workspaceKeyProvider),
  ),
);
