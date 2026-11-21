import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';

const maxOptions = 6;

/// The web's validation message for one of [questionProblems]' keys.
String problemText(AppLocalizations l10n, String key) {
  if (key.startsWith('optionEmpty:')) {
    return l10n.createTestValidationOptionEmpty(int.parse(key.split(':')[1]));
  }
  return switch (key) {
    'title' => l10n.createTestValidationTitleOrImageMissing,
    'points' => l10n.createTestValidationPointsPositive,
    'optionCount' => l10n.createTestValidationOptionCount(2, maxOptions),
    'pickTwo' => l10n.createTestValidationPickTwoCorrect,
    'pickOne' => l10n.createTestValidationPickOneCorrect,
    _ => l10n.createTestValidationAnswerMissing,
  };
}

/// One question being written (the web's QuestionCard): its text, an
/// instruction, points, the options with the correct one marked, and
/// duplicate or delete. The web's problems show under it.
class QuestionEditor extends ConsumerStatefulWidget {
  const QuestionEditor({
    required this.number,
    required this.question,
    required this.onChanged,
    required this.onDelete,
    required this.onDuplicate,
    super.key,
  });

  final int number;
  final DraftQuestion question;
  final ValueChanged<DraftQuestion> onChanged;
  final VoidCallback onDelete;
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

  @override
  void dispose() {
    for (final c in [_text, _instruction, _points, ..._options.values]) {
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
              Expanded(
                child: Text(
                  '${widget.number}. ${l10n.createTestTypesGradedMultipleChoice}',
                  style: text.titleSmall,
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
          for (final (i, o) in q.options.indexed)
            Row(
              children: [
                Checkbox(
                  key: Key('option-correct-${o.id}'),
                  value: q.answer.contains(o.id),
                  onChanged: (_) => toggle(o.id),
                ),
                Expanded(
                  child: TextField(
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
                IconButton(
                  key: Key('option-delete-${o.id}'),
                  tooltip: l10n.createTestCardDeleteOption(i + 1),
                  icon: const Icon(Icons.close),
                  onPressed: q.options.length <= 2
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
          Wrap(
            spacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                key: Key('option-add-${q.id}'),
                icon: const Icon(Icons.add),
                label: Text(l10n.createTestCardAddOption),
                onPressed: q.options.length >= maxOptions
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
              if (q.options.length >= maxOptions)
                Text(
                  l10n.createTestCardMaxOptions(maxOptions),
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
}
