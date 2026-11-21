import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
import 'package:instructor_app/features/tests/screens/question_editor.dart';

/// A passage (the web's Passage / CQ block): the passage text, its
/// instruction language and the questions under it, numbered 2.1, 2.2…
/// It keeps at least one question, as the API needs.
class PassageEditor extends StatefulWidget {
  const PassageEditor({
    required this.number,
    required this.passage,
    required this.onChanged,
    required this.onDelete,
    super.key,
  });

  final int number;
  final DraftQuestion passage;
  final ValueChanged<DraftQuestion> onChanged;
  final VoidCallback onDelete;

  @override
  State<PassageEditor> createState() => _PassageEditorState();
}

class _PassageEditorState extends State<PassageEditor> {
  late final _text = TextEditingController(text: widget.passage.text);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  DraftQuestion get p => widget.passage;

  void _children(List<DraftQuestion> next) =>
      widget.onChanged(p.copyWith(children: next));

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final kids = p.children;
    return AppCard(
      key: Key('passage-${p.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.number}. ${l10n.createTestReviewPassage}',
                  style: text.titleSmall,
                ),
              ),
              IconButton(
                key: Key('passage-delete-${p.id}'),
                tooltip: l10n.createTestPassageDelete,
                icon: const Icon(Icons.delete_outline),
                onPressed: widget.onDelete,
              ),
            ],
          ),
          TextField(
            key: Key('passage-text-${p.id}'),
            controller: _text,
            minLines: 4,
            maxLines: 12,
            decoration: InputDecoration(
              hintText: l10n.createTestPassagePlaceholder,
            ),
            onChanged: (v) => widget.onChanged(p.copyWith(text: v)),
          ),
          if (p.text.trim().isEmpty)
            Text(
              problemText(l10n, 'passage'),
              key: Key('passage-problem-${p.id}'),
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.createTestPassageInstructionLanguage,
            style: text.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xs),
          SegmentedButton<String>(
            key: Key('passage-language-${p.id}'),
            segments: [
              ButtonSegment(
                value: 'bn',
                label: Text(l10n.createTestPassageBangla),
              ),
              ButtonSegment(
                value: 'en',
                label: Text(l10n.createTestPassageEnglish),
              ),
            ],
            selected: {p.language},
            onSelectionChanged: (s) =>
                widget.onChanged(p.copyWith(language: s.first)),
          ),
          for (final (j, c) in kids.indexed) ...[
            const SizedBox(height: AppSpacing.sm),
            QuestionEditor(
              key: ValueKey(c.id),
              number: j + 1,
              label: '${widget.number}.${j + 1}',
              question: c,
              onChanged: (next) =>
                  _children([for (final x in kids) x.id == c.id ? next : x]),
              onDelete: kids.length <= 1
                  ? null
                  : () => _children([
                      for (final x in kids)
                        if (x.id != c.id) x,
                    ]),
              onDuplicate: () => _children([
                ...kids.take(j + 1),
                c.duplicate(),
                ...kids.skip(j + 1),
              ]),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: Key('passage-add-${p.id}'),
              icon: const Icon(Icons.add),
              label: Text(l10n.createTestQuestionsAddQuestion),
              onPressed: () => _children([
                ...kids,
                DraftQuestion.create('multiple-choice', type: passageType),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
