import 'package:instructor_app/features/tests/data/test_draft.dart';

/// The plain text of the simple HTML the app writes (paragraphs and line
/// breaks), or null when [html] has anything more — bold, lists, tables,
/// maths, links — that the app can't edit without losing it (Stage 4 plan
/// §7.1 A).
String? htmlToPlain(String? html) {
  final s = (html ?? '').trim();
  if (s.isEmpty) return '';
  // Any tag but <p>, </p> and <br>.
  if (RegExp(r'<(?!/?p>|br\s*/?>)[^>]*>', caseSensitive: false).hasMatch(s)) {
    return null;
  }
  final text = s
      .replaceAll(RegExp(r'</p>\s*<p>', caseSensitive: false), '\n\n')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'</?p>', caseSensitive: false), '');
  // An entity the app doesn't write may stand for formatting: keep it on
  // the web.
  if (RegExp(r'&(?!amp;|lt;|gt;|quot;|#39;|nbsp;)').hasMatch(text)) {
    return null;
  }
  return text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .trim();
}

/// Thrown inside [draftFromExam] for anything the app can't edit.
class _NotEditable implements Exception {
  const _NotEditable();
}

String _plain(Object? html) {
  final t = htmlToPlain(html is String ? html : null);
  if (t == null) throw const _NotEditable();
  return t;
}

String? _str(Object? v) => v is String && v.trim().isNotEmpty ? v : null;

List<DraftOption> _options(Object? raw) => [
  if (raw is List)
    for (final o in raw)
      if (o is Map)
        DraftOption(
          id: '${o['id']}',
          text: _plain(o['text']),
          image: _str(o['image']),
        ),
];

DraftQuestion _question(Map<dynamic, dynamic> q, {String? asType}) {
  final type = asType ?? '${q['type']}';
  final subType = '${q['subType']}';
  final allowed = switch (type) {
    'ungraded' => ungradedTypes,
    passageType => [...gradedTypes, 'essay'],
    _ => gradedTypes,
  };
  if (!allowed.contains(subType)) throw const _NotEditable();
  final answer = q['answer'] is Map ? q['answer'] as Map : null;
  final values = [
    if (answer?['value'] is List)
      for (final v in answer!['value'] as List) '$v',
  ];
  var left = <DraftOption>[];
  var right = <DraftOption>[];
  if (subType == 'matching-ordering') {
    final m = q['matchingOptions'];
    if (m is! Map) throw const _NotEditable();
    for (final side in [m['left'], m['right']]) {
      if (side is List &&
          side.any((o) => o is Map && _str(o['image']) != null)) {
        throw const _NotEditable();
      }
    }
    left = _options(m['left']);
    final byId = {for (final o in _options(m['right'])) o.id: o};
    // The app pairs left i with right i: put the right side in the
    // answer's order.
    final pairs = {
      for (final v in values)
        if (v.split(matchingPairDelimiter) case [final l, final r]) l: r,
    };
    right = [
      for (final l in left)
        if (byId[pairs[l.id]] case final r?) r else throw const _NotEditable(),
    ];
    if (right.length != byId.length) throw const _NotEditable();
  }
  final manual = type == 'ungraded' || subType == 'essay';
  return DraftQuestion(
    id: '${q['id']}',
    type: type,
    subType: subType,
    text: _plain(q['text']),
    instruction: _plain(q['instruction']),
    image: _str(q['image']),
    options: subType == 'matching-ordering' || manual
        ? const []
        : _options(q['options']),
    left: left,
    right: right,
    answer: manual || subType == 'matching-ordering'
        ? const []
        : subType == 'fill-in-the-blanks'
        ? [values.isEmpty ? '' : values[0], values.length > 1 ? values[1] : '']
        : values,
    points: (q['points'] as num?) ?? 1,
  );
}

DraftQuestion _root(Map<dynamic, dynamic> q) {
  if (q['type'] == passageType || q['childQuestions'] is List) {
    if (_str(q['audioUrl']) != null || _str(q['imageUrl']) != null) {
      throw const _NotEditable();
    }
    final kids = [
      for (final c in (q['childQuestions'] as List?) ?? const [])
        if (c is Map) _question(c, asType: passageType),
    ];
    if (kids.isEmpty) throw const _NotEditable();
    return DraftQuestion(
      id: '${q['id']}',
      type: passageType,
      subType: passageSubType,
      text: _plain(q['passageText']),
      children: kids,
      language: q['instructionLanguage'] == 'en' ? 'en' : 'bn',
    );
  }
  return _question(q);
}

/// A test from `GET /exams/:id` as a draft to edit, as the web's
/// `hydrateFromExam`; null when it has anything the app can't edit without
/// losing it (formatting, maths, IELTS, other audiences or media), so it
/// is edited on the website instead.
TestDraft? draftFromExam(Map<String, Object?> exam) {
  try {
    final form = exam['formState'] is Map
        ? exam['formState']! as Map
        : const <String, Object?>{};
    final publish = exam['publishState'] is Map
        ? exam['publishState']! as Map
        : const <String, Object?>{};
    if ((form['examCategory'] ?? exam['exam_category'] ?? 'academic') !=
        'academic') {
      return null;
    }
    final audience = '${publish['testAudience'] ?? 'anyone'}';
    if (audience != 'anyone' && audience != 'selected_class') return null;

    final rows = <(int, String, DraftQuestion)>[];
    final subjects = <DraftSubject>[];
    for (final s in (exam['subjects'] as List?) ?? const []) {
      if (s is! Map) continue;
      final qs = <DraftQuestion>[];
      for (final q in (s['questions'] as List?) ?? const []) {
        if (q is! Map) continue;
        final d = _root(q);
        qs.add(d);
        rows.add(((q['sortOrder'] as num?)?.toInt() ?? 0, '${s['id']}', d));
      }
      subjects.add(
        DraftSubject(
          id: '${s['id']}',
          name: '${s['name'] ?? ''}',
          questions: qs,
        ),
      );
    }
    rows.sort((a, b) => a.$1.compareTo(b.$1));

    final proctoring = form['proctoring'] is Map
        ? (form['proctoring']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    String text(Object? v) => v == null ? '' : '$v';
    final negative = form['allowNegativeMarking'] == true;
    return TestDraft(
      name: text(form['testName'] ?? exam['test_name']),
      duration: text(form['duration']),
      passingScore: text(form['passingScore']),
      isModelTest: form['isModelTest'] == true,
      negative: negative,
      negativePercent: negative ? text(form['negativeMarking']) : '',
      proctoringLevel: _str(proctoring['level']),
      keptProctoring: {
        for (final e in proctoring.entries)
          if (e.key != 'level' && e.value != null) e.key: e.value,
      },
      classId: _str(publish['selectedClassId']) ?? _str(exam['class_id']),
      offeringId: _str(publish['selectedOfferingId']),
      subjects: subjects,
      order: [for (final (_, _, q) in rows) q.id],
      activeSubjectId: subjects.isEmpty ? null : subjects.first.id,
      // Keep its times: an edit doesn't move the test.
      publishNow: false,
      scheduleAt: DateTime.tryParse(text(publish['scheduleAt'])),
      endingAt: DateTime.tryParse(text(publish['endingAt'])),
      audience: audience,
      excluded: [
        if (publish['excluded_students'] is List)
          for (final e in publish['excluded_students'] as List) '$e',
      ],
    );
  } on _NotEditable {
    return null;
  }
}
