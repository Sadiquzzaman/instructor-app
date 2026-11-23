import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/features/homework/data/plagiarism.dart'
    show markedPieces;

typedef TextSpanRange = ({int start, int end});

/// Highlights per passage ("attempt:part"), kept while the app is open, so
/// they survive switching passages (as on the web, where they live in the
/// page).
final readingHighlightsProvider = Provider<Map<String, List<TextSpanRange>>>(
  (ref) => {},
);

/// Adds [add] to [marks], joining the ones that touch or overlap.
List<TextSpanRange> addHighlight(List<TextSpanRange> marks, TextSpanRange add) {
  final all = [...marks, add]..sort((a, b) => a.start.compareTo(b.start));
  final out = <TextSpanRange>[];
  for (final m in all) {
    if (out.isNotEmpty && m.start <= out.last.end) {
      final last = out.removeLast();
      out.add((start: last.start, end: m.end > last.end ? m.end : last.end));
    } else {
      out.add(m);
    }
  }
  return out;
}

/// The notes' key on this phone, one per passage of an attempt (the web keeps
/// them in the browser for the attempt too).
String readingNotesKey(String attemptId, String partId) =>
    'ielts-notes:$attemptId:$partId';

/// A Reading passage as on the computer-delivered test (IEL-05): select text
/// and press Highlight, clear the highlights, and keep notes beside it.
class ReadingPassage extends ConsumerStatefulWidget {
  const ReadingPassage({
    required this.attemptId,
    required this.partId,
    required this.text,
    super.key,
  });

  final String attemptId;
  final String partId;
  final String text;

  @override
  ConsumerState<ReadingPassage> createState() => _ReadingPassageState();
}

class _ReadingPassageState extends ConsumerState<ReadingPassage> {
  late final _notes = TextEditingController(
    text:
        ref
            .read(sharedPreferencesProvider)
            .getString(readingNotesKey(widget.attemptId, widget.partId)) ??
        '',
  );
  TextSelection? _selection;

  String get _key => '${widget.attemptId}:${widget.partId}';

  List<TextSpanRange> get _marks =>
      ref.read(readingHighlightsProvider)[_key] ?? const [];

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool get _canHighlight {
    final s = _selection;
    return s != null && s.isValid && !s.isCollapsed;
  }

  void _highlight() {
    final s = _selection!;
    final map = ref.read(readingHighlightsProvider);
    setState(() {
      map[_key] = addHighlight(_marks, (start: s.start, end: s.end));
      _selection = null;
    });
  }

  void _clear() {
    setState(() => ref.read(readingHighlightsProvider).remove(_key));
  }

  void _keepNotes(String value) {
    // Notes still show on this page if the phone can't keep them.
    ref
        .read(sharedPreferencesProvider)
        .setString(readingNotesKey(widget.attemptId, widget.partId), value)
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final pieces = markedPieces(widget.text, _marks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              key: Key('highlight-${widget.partId}'),
              icon: const Icon(Icons.border_color_outlined),
              label: Text(l10n.ieltsTakeHighlight),
              onPressed: _canHighlight ? _highlight : null,
            ),
            TextButton(
              key: Key('clear-highlights-${widget.partId}'),
              onPressed: _marks.isEmpty ? null : _clear,
              child: Text(l10n.ieltsTakeClearHighlights),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SelectableText.rich(
          key: Key('passage-${widget.partId}'),
          TextSpan(
            style: text.bodyMedium,
            children: [
              for (final p in pieces)
                TextSpan(
                  text: p.text,
                  style: p.marked
                      ? TextStyle(
                          backgroundColor: colors.warningSoft,
                          color: colors.ink,
                        )
                      : null,
                ),
            ],
          ),
          onSelectionChanged: (selection, _) =>
              setState(() => _selection = selection),
        ),
        const SizedBox(height: AppSpacing.md),
        AppTextField(
          key: Key('notes-${widget.partId}'),
          label: l10n.ieltsTakeNotes,
          hint: l10n.ieltsTakeNotesHint,
          controller: _notes,
          maxLines: 4,
          onChanged: _keepNotes,
        ),
      ],
    );
  }
}
