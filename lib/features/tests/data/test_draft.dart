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
    this.answer = const [],
    this.points = 1,
  });

  /// A new multiple-choice question with four empty options.
  factory DraftQuestion.multipleChoice() => DraftQuestion(
    id: newId(),
    type: 'graded',
    subType: 'multiple-choice',
    options: [for (var i = 0; i < 4; i++) DraftOption(id: newId())],
  );

  final String id;

  /// graded, ungraded or passage-question.
  final String type;
  final String subType;
  final String text;
  final String instruction;
  final String? image;
  final List<DraftOption> options;

  /// The correct option ids (or texts, by type).
  final List<String> answer;
  final num points;

  DraftQuestion copyWith({
    String? text,
    String? instruction,
    String? image,
    bool clearImage = false,
    List<DraftOption>? options,
    List<String>? answer,
    num? points,
  }) => DraftQuestion(
    id: id,
    type: type,
    subType: subType,
    text: text ?? this.text,
    instruction: instruction ?? this.instruction,
    image: clearImage ? null : image ?? this.image,
    options: options ?? this.options,
    answer: answer ?? this.answer,
    points: points ?? this.points,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'subType': subType,
    'text': text,
    'instruction': instruction,
    'image': image,
    'options': [for (final o in options) o.toJson()],
    'answer': answer,
    'points': points,
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
    answer: [
      if (j['answer'] is List)
        for (final a in j['answer'] as List) '$a',
    ],
    points: (j['points'] as num?) ?? 1,
  );

  /// The web's wizard body for this question.
  Map<String, Object?> toBody() => {
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
    'answer': {'type': 'optionId', 'value': answer},
    'points': points,
  };
}

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

  num get totalMarks => questions.fold<num>(0, (s, q) => s + q.points);

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

  DraftSubject? get subject => subjects.isEmpty ? null : subjects.first;

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
      'questionOrder': [
        for (final s in withQuestions)
          for (final q in s.questions) q.id,
      ],
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

/// What is wrong with a question, as the web's validation keys: `title`,
/// `points`, `optionCount`, `optionEmpty:<n>`, `pickOne`, `pickTwo`.
List<String> questionProblems(DraftQuestion q) {
  final out = <String>[];
  if (q.text.trim().isEmpty && q.image == null) out.add('title');
  if (q.points <= 0) out.add('points');
  final choice =
      q.subType == 'multiple-choice' || q.subType == 'multiple-response';
  if (choice) {
    if (q.options.length < 2 || q.options.length > 6) out.add('optionCount');
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
  return out;
}

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
