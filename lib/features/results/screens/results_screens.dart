import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/results/screens/paper_exam_screens.dart';
import 'package:instructor_app/features/results/data/results.dart';

/// "80.5%" or "—" in the language's digits.
String pct(num? v, String language) => v == null
    ? '—'
    : '${OrgTime.number(num.parse(v.toStringAsFixed(1)), language)}%';

/// A page: title, intro, then the content; staff see "use the website".
class _Page extends ConsumerWidget {
  const _Page({
    required this.title,
    required this.intro,
    required this.body,
    required this.onRefresh,
  });

  final String title;
  final String? intro;
  final List<Widget> body;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: onRefresh,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(title, style: text.headlineSmall),
              if (intro != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  intro!,
                  style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              ...body,
            ],
          ),
        ),
      ),
    );
  }
}

Widget? _staffGate(BuildContext context, WidgetRef ref, String title) =>
    ref.watch(sessionProvider)?.role == 'STUDENT'
    ? null
    : EmptyView(
        icon: Icons.public,
        title: title,
        message: context.l10n.appNotYetBody,
      );

/// The web's /marks for a student: paper-exam results once published.
class MarksScreen extends ConsumerWidget {
  const MarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    // Staff manage paper exams (the web's StaffExams).
    if (ref.watch(sessionProvider)?.role != 'STUDENT') {
      return const StaffMarksScreen();
    }
    final results = ref.watch(myPaperResultsProvider);
    return _Page(
      title: l10n.marksMyTitle,
      intro: l10n.marksMyIntro,
      onRefresh: () async {
        ref.invalidate(myPaperResultsProvider);
        await ref
            .read(myPaperResultsProvider.future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      body: results.when(
        loading: () => [
          SizedBox(
            height: 200,
            child: LoadingView(semanticsLabel: l10n.marksMyTitle),
          ),
        ],
        error: (_, _) => [
          SizedBox(
            height: 280,
            child: ErrorView(
              title: l10n.marksLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(myPaperResultsProvider),
            ),
          ),
        ],
        data: (list) => list.isEmpty
            ? [
                SizedBox(
                  height: 260,
                  child: EmptyView(
                    icon: Icons.grading_outlined,
                    title: l10n.marksMyEmpty,
                    message: l10n.marksMyEmptyHint,
                  ),
                ),
              ]
            : [
                for (final r in list) ...[
                  AppCard(
                    key: Key('paper-${r.id}'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.name, style: text.titleSmall),
                              Text(
                                [
                                      r.subject,
                                      if (r.date != null)
                                        OrgTime.schoolDay(r.date!, language),
                                      r.term,
                                    ]
                                    .whereType<String>()
                                    .where((s) => s.isNotEmpty)
                                    .join(' · '),
                                style: text.bodySmall?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (r.absent)
                          StatusPill(label: l10n.marksAbsent)
                        else
                          Text(
                            [
                              if (r.marks != null)
                                '${OrgTime.number(r.marks!, language)}/${OrgTime.number(r.total, language)}',
                              if (r.percent != null) pct(r.percent, language),
                              if (r.grade != null) '(${r.grade})',
                            ].join(' · '),
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: AppRadius.inputAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: colors.inkMuted)),
          Text(value, style: text.titleLarge),
        ],
      ),
    );
  }
}

/// Subjects with their score and grade.
class _SubjectTable extends StatelessWidget {
  const _SubjectTable({
    required this.lines,
    required this.subjectLabel,
    required this.scoreLabel,
    required this.gradeLabel,
  });

  final List<ScoreLine> lines;
  final String subjectLabel;
  final String scoreLabel;
  final String gradeLabel;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    TableRow row(List<String> cells, {bool head = false}) => TableRow(
      children: [
        for (final c in cells)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              c,
              style: head
                  ? text.labelMedium?.copyWith(color: colors.inkMuted)
                  : text.bodyMedium,
            ),
          ),
      ],
    );
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(),
        2: FlexColumnWidth(),
      },
      children: [
        row([subjectLabel, scoreLabel, gradeLabel], head: true),
        for (final s in lines)
          row([s.subject ?? '—', pct(s.score, language), s.grade ?? '—']),
      ],
    );
  }
}

/// The web's /performance for a student: their own published results.
class PerformanceScreen extends ConsumerWidget {
  const PerformanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    if (_staffGate(context, ref, l10n.performanceMyTitle) case final gate?) {
      return gate;
    }
    final perf = ref.watch(myPerformanceProvider);
    return _Page(
      title: l10n.performanceMyTitle,
      intro: l10n.performancePublishedOnly,
      onRefresh: () async {
        ref.invalidate(myPerformanceProvider);
        await ref
            .read(myPerformanceProvider.future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      body: perf.when(
        loading: () => [
          SizedBox(
            height: 200,
            child: LoadingView(semanticsLabel: l10n.performanceMyTitle),
          ),
        ],
        error: (_, _) => [
          SizedBox(
            height: 280,
            child: ErrorView(
              title: l10n.performanceLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(myPerformanceProvider),
            ),
          ),
        ],
        data: (p) => [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _Stat(l10n.performanceOverall, pct(p.overall.score, language)),
              _Stat(l10n.performanceColumnsGrade, p.overall.grade ?? '—'),
              if (p.overall.gpa != null)
                _Stat(
                  l10n.performanceGpa,
                  OrgTime.number(p.overall.gpa!, language),
                ),
              if (p.position != null)
                _Stat(
                  l10n.performancePosition,
                  l10n.performancePositionOf(p.position!, p.classSize),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              _Stat(l10n.performancePartsExams, pct(p.overall.exams, language)),
              _Stat(
                l10n.performancePartsHomework,
                pct(p.overall.homework, language),
              ),
              _Stat(
                l10n.performancePartsAttendance,
                pct(p.overall.attendance, language),
              ),
              _Stat(
                l10n.performancePartsBehaviour,
                pct(p.overall.behaviour, language),
              ),
              if (p.onTime != null)
                _Stat(l10n.performanceOnTime, pct(p.onTime, language)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            key: const Key('perf-subjects'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.performanceSubjectsCaption, style: text.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (p.subjects.isEmpty)
                  Text(
                    l10n.performanceNoSubjects,
                    style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                  )
                else
                  _SubjectTable(
                    lines: p.subjects,
                    subjectLabel: l10n.performanceColumnsSubject,
                    scoreLabel: l10n.performanceColumnsScore,
                    gradeLabel: l10n.performanceColumnsGrade,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            key: const Key('perf-exams'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.performanceExamsTitle, style: text.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                if (p.exams.isEmpty)
                  Text(
                    l10n.performanceNoExams,
                    style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                  )
                else
                  for (final e in p.exams)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(e.name),
                      subtitle: Text(
                        [
                          e.kind == 'PAPER'
                              ? l10n.performanceKindsPAPER
                              : l10n.performanceKindsONLINE,
                          e.subject,
                          if (e.date != null)
                            OrgTime.schoolDay(
                              e.date!.substring(0, 10),
                              language,
                            ),
                        ].whereType<String>().join(' · '),
                      ),
                      trailing: e.absent
                          ? StatusPill(label: l10n.performanceAbsent)
                          : Text(
                              e.marks == null
                                  ? '—'
                                  : '${OrgTime.number(e.marks!, language)}/${OrgTime.number(e.total, language)}',
                            ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The web's /report-cards for a student: the cards the school made.
class ReportCardsScreen extends ConsumerWidget {
  const ReportCardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    if (_staffGate(context, ref, l10n.reportCardsMyTitle) case final gate?) {
      return gate;
    }
    final cards = ref.watch(myReportCardsProvider);
    return _Page(
      title: l10n.reportCardsMyTitle,
      intro: l10n.reportCardsMyIntro,
      onRefresh: () async {
        ref.invalidate(myReportCardsProvider);
        await ref
            .read(myReportCardsProvider.future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      body: cards.when(
        loading: () => [
          SizedBox(
            height: 200,
            child: LoadingView(semanticsLabel: l10n.reportCardsMyTitle),
          ),
        ],
        error: (_, _) => [
          SizedBox(
            height: 280,
            child: ErrorView(
              title: l10n.reportCardsLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(myReportCardsProvider),
            ),
          ),
        ],
        data: (list) => list.isEmpty
            ? [
                SizedBox(
                  height: 260,
                  child: EmptyView(
                    icon: Icons.description_outlined,
                    title: l10n.reportCardsMyEmpty,
                    message: l10n.reportCardsMyEmptyHint,
                  ),
                ),
              ]
            : [
                for (final c in list) ...[
                  AppCard(
                    key: Key('card-${c.id}'),
                    onTap: () =>
                        context.push('${AppRoutes.reportCards}/${c.id}'),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.term ?? l10n.reportCardWholeSession,
                                style: text.titleSmall,
                              ),
                              if (c.generatedAt != null)
                                Text(
                                  l10n.reportCardsMadeOn(
                                    OrgTime.date(c.generatedAt!, language),
                                  ),
                                  style: text.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
      ),
    );
  }
}

/// One report card as it was made; printing stays on the web.
class ReportCardScreen extends ConsumerWidget {
  const ReportCardScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final card = ref.watch(reportCardProvider(id));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: card.when(
          loading: () => LoadingView(semanticsLabel: l10n.reportCardTitle),
          error: (_, _) => ErrorView(
            title: l10n.reportCardsLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(reportCardProvider(id)),
          ),
          data: (c) => ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                c.organization,
                style: text.titleMedium?.copyWith(color: colors.primary),
              ),
              Text(l10n.reportCardTitle, style: text.headlineSmall),
              Text(
                [
                  c.student,
                  c.className,
                  c.term ?? l10n.reportCardWholeSession,
                ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _Stat(l10n.reportCardOverall, pct(c.overall.score, language)),
                  _Stat(l10n.reportCardGrade, c.overall.grade ?? '—'),
                  if (c.overall.gpa != null)
                    _Stat(
                      l10n.reportCardGpa,
                      OrgTime.number(c.overall.gpa!, language),
                    ),
                  if (c.showPosition && c.position != null)
                    _Stat(
                      l10n.reportCardPosition,
                      l10n.reportCardPositionOf(c.position!, c.classSize),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.reportCardSubjects, style: text.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    _SubjectTable(
                      lines: c.subjects,
                      subjectLabel: l10n.reportCardSubject,
                      scoreLabel: l10n.reportCardScore,
                      gradeLabel: l10n.reportCardGrade,
                    ),
                  ],
                ),
              ),
              if (c.present != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(l10n.reportCardAttendance, style: text.titleSmall),
                Text(
                  l10n.reportCardAttendanceDays(
                    OrgTime.number(c.present!, language),
                    OrgTime.number(c.absent ?? 0, language),
                    OrgTime.number(c.leave ?? 0, language),
                  ),
                ),
              ],
              for (final (label, remark) in [
                (l10n.reportCardTeacherRemark, c.teacherRemark),
                (l10n.reportCardPrincipalRemark, c.principalRemark),
              ])
                if (remark != null && remark.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(label, style: text.titleSmall),
                  Text(remark, style: text.bodyMedium),
                ],
            ],
          ),
        ),
      ),
    );
  }
}
