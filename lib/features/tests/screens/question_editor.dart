import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/features/shell/data/entitlements.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';

/// The graded types the web's builder offers for an academic test (IELTS
/// types come with Stage 5).
const gradedChoiceTypes = gradedTypes;

/// The types a question of [type] may take (the web's tabs per category).
List<String> typesFor(String type) => switch (type) {
  'ungraded' => ungradedTypes,
  'ielts' => ieltsTypes,
  passageType => [...gradedChoiceTypes, 'essay'],
  _ => gradedChoiceTypes,
};

/// The web's name for [subType] under [type]'s category.
String typeName(
  AppLocalizations l10n,
  String subType, {
  String type = 'graded',
}) => switch ((type, subType)) {
  ('ungraded', 'true-false') => l10n.createTestTypesUngradedTrueFalse,
  ('ungraded', 'fill-in-the-gaps') => l10n.createTestTypesUngradedFillInTheGaps,
  ('ungraded', _) => l10n.createTestTypesUngradedEssay,
  ('ielts', 'multiple-response') => l10n.createTestTypesIeltsMultipleResponse,
  ('ielts', 'true-false-not-given') => l10n.createTestTypesIeltsTrueFalse,
  ('ielts', 'yes-no-not-given') => l10n.createTestTypesIeltsYesNoNotGiven,
  ('ielts', 'matching-ordering') => l10n.createTestTypesIeltsMatchingOrdering,
  ('ielts', 'fill-in-the-blanks') => l10n.createTestTypesIeltsFillInTheBlanks,
  ('ielts', 'sentence-completion') =>
    l10n.createTestTypesIeltsSentenceCompletion,
  ('ielts', 'summary-completion') => l10n.createTestTypesIeltsSummaryCompletion,
  ('ielts', 'table-completion') => l10n.createTestTypesIeltsTableCompletion,
  ('ielts', 'diagram-label') => l10n.createTestTypesIeltsDiagramLabel,
  ('ielts', 'short-answer') => l10n.createTestTypesIeltsShortAnswer,
  ('ielts', 'writing-task-1') => l10n.createTestTypesIeltsWritingTask1,
  ('ielts', 'writing-task-2') => l10n.createTestTypesIeltsWritingTask2,
  ('ielts', 'speaking-part-1') => l10n.createTestTypesIeltsSpeakingPart1,
  ('ielts', 'speaking-part-2') => l10n.createTestTypesIeltsSpeakingPart2,
  ('ielts', 'speaking-part-3') => l10n.createTestTypesIeltsSpeakingPart3,
  ('ielts', _) => l10n.createTestTypesIeltsMultipleChoice,
  (passageType, 'essay') => l10n.createTestTypesPassageQuestionEssay,
  (passageType, 'multiple-response') =>
    l10n.createTestTypesPassageQuestionMultipleResponse,
  (passageType, 'true-false') => l10n.createTestTypesPassageQuestionTrueFalse,
  (passageType, 'fill-in-the-blanks') =>
    l10n.createTestTypesPassageQuestionFillInTheBlanks,
  (passageType, 'matching-ordering') =>
    l10n.createTestTypesPassageQuestionMatchingOrdering,
  (passageType, _) => l10n.createTestTypesPassageQuestionMultipleChoice,
  (_, 'multiple-response') => l10n.createTestTypesGradedMultipleResponse,
  (_, 'true-false') => l10n.createTestTypesGradedTrueFalse,
  (_, 'fill-in-the-blanks') => l10n.createTestTypesGradedFillInTheBlanks,
  (_, 'matching-ordering') => l10n.createTestTypesGradedMatchingOrdering,
  _ => l10n.createTestTypesGradedMultipleChoice,
};

/// The web's validation message for one of [questionProblems]' keys.
String problemText(AppLocalizations l10n, String key) {
  final parts = key.split(':');
  final n = parts.length > 1 ? int.parse(parts[1]) : 0;
  switch (parts.first) {
    case 'optionEmpty':
      return l10n.createTestValidationOptionEmpty(n);
    case 'leftEmpty':
      return l10n.createTestValidationLeftChoiceEmpty(n);
    case 'rightEmpty':
      return l10n.createTestValidationRightChoiceEmpty(n);
  }
  return switch (key) {
    'title' => l10n.createTestValidationTitleOrImageMissing,
    'titleText' => l10n.createTestValidationTitleMissing,
    'passage' => l10n.createTestValidationPassageMissing,
    'pairs' => l10n.createTestValidationMatchingPairs(
      minMatchingPairs,
      maxMatchingPairs,
    ),
    'points' => l10n.createTestValidationPointsPositive,
    'optionCount' => l10n.createTestValidationOptionCount(
      minVariableOptions,
      maxVariableOptions,
    ),
    'pickTwo' => l10n.createTestValidationPickTwoCorrect,
    'pickOne' => l10n.createTestValidationPickOneCorrect,
    _ => l10n.createTestValidationAnswerMissing,
  };
}

/// Narrower than this, a matching pair stacks left over right.
const _pairRowWidth = 420.0;

/// One question being written (the web's QuestionCard): its type, text,
/// an instruction, an image (when the plan allows), points, the options
/// with the correct ones marked, and duplicate or delete. The web's
/// problems show under it.
class QuestionEditor extends ConsumerStatefulWidget {
  const QuestionEditor({
    required this.number,
    required this.question,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
    this.label,
    super.key,
  });

  final int number;

  /// Shown in place of [number] (a passage's questions: 2.1, 2.2).
  final String? label;
  final DraftQuestion question;
  final ValueChanged<DraftQuestion> onChanged;

  /// Null when it can't be removed (a passage's only question).
  final VoidCallback? onDelete;
  final VoidCallback onDuplicate;

  @override
  ConsumerState<QuestionEditor> createState() => _QuestionEditorState();
}

class _QuestionEditorState extends ConsumerState<QuestionEditor> {
  late final _text = TextEditingController(text: widget.question.text);
  late final _instruction = TextEditingController(
    text: widget.question.instruction,
  );
  late final _points = TextEditingController(text: '${widget.question.points}');
  final _options = <String, TextEditingController>{};
  late final _answers = [
    for (var i = 0; i < 2; i++)
      TextEditingController(
        text:
            i < widget.question.answer.length &&
                isTextAnswer(widget.question.subType)
            ? widget.question.answer[i]
            : '',
      ),
  ];
  int _imageRound = 0;

  @override
  void didUpdateWidget(QuestionEditor old) {
    super.didUpdateWidget(old);
    // A new type starts with an empty answer: so do its fields.
    if (old.question.subType != widget.question.subType) {
      for (final c in _answers) {
        c.clear();
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _text,
      _instruction,
      _points,
      ..._answers,
      ..._options.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _option(DraftOption o) =>
      _options.putIfAbsent(o.id, () => TextEditingController(text: o.text));

  DraftQuestion get q => widget.question;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final problems = questionProblems(q);
    final multi = q.subType == 'multiple-response';
    final fixed = isFixedChoice(q.subType);
    final blanks = isTextAnswer(q.subType);
    final matching = q.subType == 'matching-ordering';
    final choice = !blanks && !matching && !q.manual;
    final gaps = blanks || q.subType == 'fill-in-the-gaps';
    final canImage =
        ref.watch(entitlementsProvider).value?.has('allow_question_images') ??
        false;
    void toggle(String id) => widget.onChanged(
      q.copyWith(
        answer: multi
            ? (q.answer.contains(id)
                  ? [
                      for (final a in q.answer)
                        if (a != id) a,
                    ]
                  : [...q.answer, id])
            : [id],
      ),
    );
    return AppCard(
      key: Key('question-${q.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('${widget.label ?? widget.number}.', style: text.titleSmall),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: Key('question-type-${q.id}'),
                  initialValue: q.subType,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.createTestCardType,
                  ),
                  items: [
                    for (final t in typesFor(q.type))
                      DropdownMenuItem(
                        value: t,
                        child: Text(typeName(l10n, t, type: q.type)),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) widget.onChanged(q.withSubType(v));
                  },
                ),
              ),
              IconButton(
                key: Key('question-duplicate-${q.id}'),
                tooltip: l10n.createTestCardDuplicate,
                icon: const Icon(Icons.copy_outlined),
                onPressed: widget.onDuplicate,
              ),
              IconButton(
                key: Key('question-delete-${q.id}'),
                tooltip: l10n.createTestCardDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          TextField(
            key: Key('question-text-${q.id}'),
            controller: _text,
            minLines: 2,
            maxLines: 6,
            decoration: InputDecoration(
              labelText: l10n.createTestStepsQuestions,
              hintText: gaps
                  ? l10n.createTestPromptsBlank
                  : q.type == passageType && q.subType == 'essay'
                  ? l10n.createTestPromptsEssayCq
                  : l10n.createTestPromptsDefault,
            ),
            onChanged: (v) => widget.onChanged(q.copyWith(text: v)),
          ),
          TextField(
            key: Key('question-instruction-${q.id}'),
            controller: _instruction,
            maxLength: 500,
            decoration: InputDecoration(
              hintText: l10n.createTestCardInstructionPlaceholder,
            ),
            onChanged: (v) => widget.onChanged(q.copyWith(instruction: v)),
          ),
          if (canImage)
            if (q.image != null)
              Row(
                children: [
                  const Icon(Icons.image_outlined),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      l10n.createTestCardQuestionImageAlt(widget.number),
                      style: text.bodySmall,
                    ),
                  ),
                  TextButton(
                    key: Key('question-image-remove-${q.id}'),
                    onPressed: () {
                      setState(() => _imageRound++);
                      widget.onChanged(q.copyWith(clearImage: true));
                    },
                    child: Text(l10n.createTestCardRemoveQuestionImage),
                  ),
                ],
              )
            else
              AttachmentField(
                key: ValueKey('question-image-${q.id}-$_imageRound'),
                label: l10n.createTestCardUploadQuestionImage,
                purpose: FilePurpose.exam,
                maxFiles: 1,
                onChanged: (files) {
                  final url = files.isEmpty ? null : files.first.url;
                  if (url != null) widget.onChanged(q.copyWith(image: url));
                },
              ),
          if (blanks) ..._blankAnswers(l10n),
          if (matching) ..._pairs(l10n, text, colors),
          if (choice)
            for (final (i, o) in q.options.indexed)
              Row(
                children: [
                  Checkbox(
                    key: Key('option-correct-${o.id}'),
                    value: q.answer.contains(o.id),
                    onChanged: (_) => toggle(o.id),
                  ),
                  Expanded(
                    child: fixed
                        ? Text(o.text, key: Key('option-fixed-${o.id}'))
                        : TextField(
                            key: Key('option-text-${o.id}'),
                            controller: _option(o),
                            decoration: InputDecoration(
                              hintText: '${l10n.createTestCardOption} ${i + 1}',
                            ),
                            onChanged: (v) => widget.onChanged(
                              q.copyWith(
                                options: [
                                  for (final x in q.options)
                                    x.id == o.id ? x.copyWith(text: v) : x,
                                ],
                              ),
                            ),
                          ),
                  ),
                  if (!fixed)
                    IconButton(
                      key: Key('option-delete-${o.id}'),
                      tooltip: l10n.createTestCardDeleteOption(i + 1),
                      icon: const Icon(Icons.close),
                      onPressed: q.options.length <= minVariableOptions
                          ? null
                          : () => widget.onChanged(
                              q.copyWith(
                                options: [
                                  for (final x in q.options)
                                    if (x.id != o.id) x,
                                ],
                                answer: [
                                  for (final a in q.answer)
                                    if (a != o.id) a,
                                ],
                              ),
                            ),
                    ),
                ],
              ),
          if (choice && fixed)
            Text(l10n.createTestValidationFixedOptions, style: text.bodySmall),
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (choice && !fixed)
                TextButton.icon(
                  key: Key('option-add-${q.id}'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.createTestCardAddOption),
                  onPressed: q.options.length >= maxVariableOptions
                      ? null
                      : () => widget.onChanged(
                          q.copyWith(
                            options: [
                              ...q.options,
                              DraftOption(id: newId()),
                            ],
                          ),
                        ),
                ),
              if (choice && !fixed && q.options.length >= maxVariableOptions)
                Text(
                  l10n.createTestCardMaxOptions(maxVariableOptions),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              SizedBox(
                width: 120,
                child: TextField(
                  key: Key('question-points-${q.id}'),
                  controller: _points,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: l10n.createTestCardPoints,
                  ),
                  onChanged: (v) => widget.onChanged(
                    q.copyWith(points: num.tryParse(v.trim()) ?? 0),
                  ),
                ),
              ),
            ],
          ),
          for (final p in problems)
            Text(
              problemText(l10n, p),
              key: Key('question-problem-${q.id}-$p'),
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
        ],
      ),
    );
  }

  /// The expected answer and one alternative (the web's correct-answer
  /// input); the alternative waits until there is an answer.
  List<Widget> _blankAnswers(AppLocalizations l10n) {
    void set(int i, String v) {
      final next = [
        for (var k = 0; k < 2; k++) k < q.answer.length ? q.answer[k] : '',
      ];
      next[i] = v;
      widget.onChanged(q.copyWith(answer: next));
    }

    final hasPrimary = q.answer.isNotEmpty && q.answer.first.trim().isNotEmpty;
    return [
      TextField(
        key: Key('blank-answer-${q.id}'),
        controller: _answers[0],
        decoration: InputDecoration(
          labelText: l10n.createTestCardCorrectAnswer,
          hintText: l10n.createTestPromptsExpectedAnswer,
        ),
        onChanged: (v) => set(0, v),
      ),
      TextField(
        key: Key('blank-alternative-${q.id}'),
        controller: _answers[1],
        enabled: hasPrimary,
        decoration: InputDecoration(
          labelText: l10n.createTestCardAlternativeAnswer,
          hintText: l10n.createTestCardAlternativePlaceholder,
        ),
        onChanged: (v) => set(1, v),
      ),
    ];
  }

  /// Matching pairs, left and right, in the right order (students see them
  /// shuffled). On a narrow phone each pair stacks.
  List<Widget> _pairs(AppLocalizations l10n, TextTheme text, AppColors colors) {
    DraftOption at(List<DraftOption> side, int i) =>
        i < side.length ? side[i] : DraftOption(id: newId());
    final count = q.left.length > q.right.length
        ? q.left.length
        : q.right.length;
    List<DraftOption> edit(List<DraftOption> side, String id, String v) => [
      for (final x in side) x.id == id ? x.copyWith(text: v) : x,
    ];
    Widget field(DraftOption o, bool isLeft) => TextField(
      key: Key('pair-${isLeft ? 'left' : 'right'}-${o.id}'),
      controller: _option(o),
      decoration: InputDecoration(
        hintText: l10n.createTestCardChoicePlaceholder,
      ),
      onChanged: (v) => widget.onChanged(
        isLeft
            ? q.copyWith(left: edit(q.left, o.id, v))
            : q.copyWith(right: edit(q.right, o.id, v)),
      ),
    );
    return [
      Text(
        l10n.createTestCardMatchingHint,
        style: text.bodySmall?.copyWith(color: colors.inkMuted),
      ),
      for (var i = 0; i < count; i++)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: LayoutBuilder(
            builder: (context, box) {
              final l = at(q.left, i);
              final r = at(q.right, i);
              final remove = IconButton(
                key: Key('pair-delete-${q.id}-$i'),
                tooltip: l10n.createTestCardDeletePair(i + 1),
                icon: const Icon(Icons.close),
                onPressed: count <= minMatchingPairs
                    ? null
                    : () => widget.onChanged(
                        q.copyWith(
                          left: [
                            for (final (k, x) in q.left.indexed)
                              if (k != i) x,
                          ],
                          right: [
                            for (final (k, x) in q.right.indexed)
                              if (k != i) x,
                          ],
                        ),
                      ),
              );
              final number = Text('${i + 1}.', style: text.bodyMedium);
              if (box.maxWidth < _pairRowWidth) {
                return Row(
                  children: [
                    number,
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Column(
                        children: [field(l, true), field(r, false)],
                      ),
                    ),
                    remove,
                  ],
                );
              }
              return Row(
                children: [
                  number,
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: field(l, true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: Icon(Icons.arrow_forward),
                  ),
                  Expanded(child: field(r, false)),
                  remove,
                ],
              );
            },
          ),
        ),
      Wrap(
        spacing: AppSpacing.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          TextButton.icon(
            key: Key('pair-add-${q.id}'),
            icon: const Icon(Icons.add),
            label: Text(l10n.createTestCardAddPair),
            onPressed: count >= maxMatchingPairs
                ? null
                : () => widget.onChanged(
                    q.copyWith(
                      left: [
                        ...q.left,
                        DraftOption(id: newId()),
                      ],
                      right: [
                        ...q.right,
                        DraftOption(id: newId()),
                      ],
                    ),
                  ),
          ),
          if (count >= maxMatchingPairs)
            Text(
              l10n.createTestCardMaxPairs(maxMatchingPairs),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
        ],
      ),
    ];
  }
}
