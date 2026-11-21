import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/homework/data/homework.dart';
import 'package:instructor_app/features/homework/data/plagiarism.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// Where a similarity match opens.
String matchRoute(String id) => '/integrity/matches/$id';

StatusTone _tone(String level) => switch (level) {
  'HIGH' => StatusTone.danger,
  'MEDIUM' => StatusTone.warning,
  _ => StatusTone.neutral,
};

String _level(AppLocalizations l10n, String level) => switch (level) {
  'HIGH' => l10n.plagiarismLevelsHIGH,
  'MEDIUM' => l10n.plagiarismLevelsMEDIUM,
  _ => l10n.plagiarismLevelsLOW,
};

String _notChecked(AppLocalizations l10n, String why) => switch (why) {
  'TOO_SHORT' => l10n.plagiarismNotCheckedTOOSHORT,
  'NO_TEXT' => l10n.plagiarismNotCheckedNOTEXT,
  'HANDWRITTEN_IMAGE' => l10n.plagiarismNotCheckedHANDWRITTENIMAGE,
  _ => l10n.plagiarismNotCheckedFILENOTREAD,
};

String _decision(AppLocalizations l10n, String d) =>
    d == 'COPIED' ? l10n.plagiarismDecisionsCOPIED : l10n.plagiarismDecisionsOK;

Widget _failure(BuildContext context, Object e, VoidCallback retry) {
  final l10n = context.l10n;
  return ErrorView(
    title: e is ApiException && e.statusCode == 403
        ? l10n.plagiarismNotAvailable
        : l10n.plagiarismLoadFailed,
    retryLabel: l10n.uiErrorRetry,
    onRetry: retry,
  );
}

/// A homework's plagiarism results (the web's
/// /homework/:id/similarity): each hand-in's similarity with the most
/// similar classmates, the similar pairs with the teacher's review, and Run
/// check now. Staff only; opening it after the due date runs the first
/// check by itself.
class SimilarityScreen extends ConsumerStatefulWidget {
  const SimilarityScreen({required this.homeworkId, super.key})
    : scopeType = 'HOMEWORK';

  /// An IELTS opening's Writing (the web's
  /// /ielts/assignments/:id/similarity).
  const SimilarityScreen.ieltsWriting({required String assignmentId, super.key})
    : homeworkId = assignmentId,
      scopeType = 'IELTS_WRITING';

  /// The homework, or the IELTS opening.
  final String homeworkId;
  final String scopeType;

  bool get ielts => scopeType == 'IELTS_WRITING';

  @override
  ConsumerState<SimilarityScreen> createState() => _SimilarityScreenState();
}

class _SimilarityScreenState extends ConsumerState<SimilarityScreen> {
  SimilarityReport? _latest;
  bool _busy = false;

  Future<void> _run() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(plagiarismRepositoryProvider)
          .run(widget.homeworkId, scopeType: widget.scopeType);
      if (!mounted) return;
      setState(() => _latest = r);
      messenger.showSnackBar(SnackBar(content: Text(l10n.plagiarismRan)));
    } catch (e) {
      if (mounted &&
          !await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          )) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final provider = widget.ielts
        ? ieltsSimilarityProvider(widget.homeworkId)
        : similarityReportProvider(widget.homeworkId);
    final loaded = ref.watch(provider);
    final title = widget.ielts
        ? null
        : ref.watch(homeworkProvider(widget.homeworkId)).value?.title;
    final r = _latest ?? loaded.value;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: r != null
            ? _page(r, title)
            : loaded.hasError
            ? _failure(context, loaded.error!, () => ref.invalidate(provider))
            : LoadingView(semanticsLabel: l10n.plagiarismCrumb),
      ),
    );
  }

  Widget _page(SimilarityReport r, String? title) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    String pct(num v) => '${OrgTime.number(v, language)}%';
    final pairs = [
      for (final p in r.pairs)
        if (p.level != 'LOW' || p.decision != null) p,
    ];
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          title == null ? l10n.plagiarismCrumb : l10n.plagiarismTitle(title),
          style: text.headlineSmall,
        ),
        Text(
          l10n.plagiarismStaffOnly,
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const Key('plagiarism-run'),
            onPressed: _busy ? null : _run,
            icon: const Icon(Icons.manage_search),
            label: Text(l10n.plagiarismRunNow),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${r.ranAt == null ? l10n.plagiarismNotRunYet : l10n.plagiarismLastRun(OrgTime.dateTime(r.ranAt!, language), r.compared)}'
          ' · ${l10n.plagiarismThresholds(r.high, r.medium, r.minWords)}',
          style: text.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.plagiarismSubmissionsCaption, style: text.titleMedium),
              if (r.rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(l10n.plagiarismNoSubmissions),
                )
              else
                for (final s in r.rows)
                  Padding(
                    key: Key('submission-${s.submissionId}'),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                s.student.name,
                                style: text.titleSmall,
                              ),
                            ),
                            Text(
                              '${l10n.plagiarismWords}: ${OrgTime.number(s.words, language)}',
                              style: text.bodySmall?.copyWith(
                                color: colors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        if (s.notChecked != null)
                          Text(
                            _notChecked(l10n, s.notChecked!),
                            style: text.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          )
                        else if (s.level != null)
                          StatusPill(
                            label:
                                '${_level(l10n, s.level!)} · ${pct(s.percent)}',
                            tone: _tone(s.level!),
                          ),
                        if (s.mostSimilar.isNotEmpty)
                          Wrap(
                            spacing: AppSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '${l10n.plagiarismMostSimilar}:',
                                style: text.bodySmall,
                              ),
                              for (final m in s.mostSimilar)
                                TextButton(
                                  key: Key('compare-${m.matchId}'),
                                  onPressed: () =>
                                      context.push(matchRoute(m.matchId)),
                                  child: Text(
                                    '${m.student.name} (${pct(m.percent)})',
                                  ),
                                ),
                            ],
                          ),
                        const Divider(),
                      ],
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.plagiarismPairsTitle, style: text.titleMedium),
              Text(
                l10n.plagiarismPairsDescription,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              if (pairs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text(l10n.plagiarismNoPairs),
                )
              else
                for (final p in pairs)
                  ListTile(
                    key: Key('pair-${p.id}'),
                    contentPadding: EdgeInsets.zero,
                    onTap: () => context.push(matchRoute(p.id)),
                    title: Text('${p.a.name} · ${p.b.name}'),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          StatusPill(
                            label: '${_level(l10n, p.level)} · ${pct(p.score)}',
                            tone: _tone(p.level),
                          ),
                          Text(
                            p.decision == null
                                ? l10n.plagiarismNotReviewed
                                : _decision(l10n, p.decision!),
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Two hand-ins with the shared passages marked (the web's
/// /integrity/matches/:id): side by side on a tablet, one above the other
/// on a phone; the review "Reviewed — OK" or "Copied" with a note. Nothing
/// changes a score by itself.
class MatchScreen extends ConsumerStatefulWidget {
  const MatchScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<MatchScreen> createState() => _MatchScreenState();
}

class _MatchScreenState extends ConsumerState<MatchScreen> {
  SimilarityMatch? _latest;
  String? _picked;
  TextEditingController? _note;
  bool _busy = false;

  @override
  void dispose() {
    _note?.dispose();
    super.dispose();
  }

  Future<void> _save(String decision) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final m = await ref
          .read(plagiarismRepositoryProvider)
          .review(widget.id, decision: decision, note: _note?.text ?? '');
      if (!mounted) return;
      setState(() => _latest = m);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.plagiarismReviewSaved)),
      );
    } catch (e) {
      if (mounted &&
          !await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          )) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = ref.watch(similarityMatchProvider(widget.id));
    final m = _latest ?? loaded.value;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: m != null
            ? _page(m)
            : loaded.hasError
            ? _failure(
                context,
                loaded.error!,
                () => ref.invalidate(similarityMatchProvider(widget.id)),
              )
            : LoadingView(semanticsLabel: l10n.plagiarismMatchCrumb),
      ),
    );
  }

  Widget _side(MatchSide s) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return AppCard(
      key: Key('side-${s.student.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.student.name, style: text.titleMedium),
          Text(
            l10n.plagiarismSharePercent(s.percent),
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Semantics(
            label: l10n.plagiarismTextOf(s.student.name),
            child: SelectableText.rich(
              TextSpan(
                style: text.bodyMedium,
                children: [
                  for (final p in markedPieces(s.text, s.spans))
                    TextSpan(
                      text: p.text,
                      style: p.marked
                          ? TextStyle(backgroundColor: colors.warningSoft)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(SimilarityMatch m) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    _note ??= TextEditingController(text: m.note ?? '');
    final chosen = _picked ?? m.decision;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(
          l10n.plagiarismMatchTitle(m.a.student.name, m.b.student.name),
          style: text.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: StatusPill(
            label:
                '${_level(l10n, m.level)} · ${OrgTime.number(m.score, language)}%',
            tone: _tone(m.level),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= AppSpacing.tabletBreakpoint
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _side(m.a)),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: _side(m.b)),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _side(m.a),
                    const SizedBox(height: AppSpacing.md),
                    _side(m.b),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.plagiarismReview, style: text.titleMedium),
              Text(l10n.plagiarismDecision, style: text.labelMedium),
              RadioGroup<String>(
                groupValue: chosen,
                onChanged: (v) => setState(() => _picked = v),
                child: Column(
                  children: [
                    for (final d in const ['OK', 'COPIED'])
                      RadioListTile<String>(
                        key: Key('decision-$d'),
                        contentPadding: EdgeInsets.zero,
                        value: d,
                        title: Text(_decision(l10n, d)),
                      ),
                  ],
                ),
              ),
              TextField(
                key: const Key('review-note'),
                controller: _note,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(labelText: l10n.plagiarismNote),
              ),
              Text(
                l10n.plagiarismNoScoreChange,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton(
                  key: const Key('review-save'),
                  onPressed: _busy || chosen == null
                      ? null
                      : () => _save(chosen),
                  child: Text(l10n.plagiarismSaveReview),
                ),
              ),
              if (m.reviewedAt != null)
                Text(
                  l10n.plagiarismReviewedAt(
                    OrgTime.dateTime(m.reviewedAt!, language),
                  ),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
