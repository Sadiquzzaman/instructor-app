import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';

/// A section, term or subject: its id and name.
typedef Named = ({String id, String name});

/// `GET /scores/sections`: the sections and terms the caller may see.
typedef VisibleSections = ({List<Named> sections, List<Named> terms});

/// A score line: the four parts, the score and the grade.
typedef ScorePart = ({
  num? exams,
  num? homework,
  num? attendance,
  num? behaviour,
  num? score,
  String? grade,
});

ScorePart _line(Object? j) {
  final m = j is Map ? j : const <String, Object?>{};
  return (
    exams: m['exams_pct'] as num?,
    homework: m['homework_pct'] as num?,
    attendance: m['attendance_pct'] as num?,
    behaviour: m['behaviour_pct'] as num?,
    score: m['score_pct'] as num?,
    grade: m['grade'] is Map ? (m['grade'] as Map)['grade'] as String? : null,
  );
}

/// A student on a section's dashboard.
typedef SectionStudent = ({
  String id,
  String name,
  String? rollNo,
  ScorePart overall,
  Map<String, ScorePart> subjects,
  int homeworkSet,
  int homeworkMissing,
  int missingHomework,

  /// SCORE, ATTENDANCE or MISSING_HOMEWORK.
  List<String> atRisk,
  int? position,
});

/// `GET /scores/sections/:id?term_id`.
@immutable
class SectionScores {
  const SectionScores({
    required this.name,
    required this.weights,
    required this.thresholds,
    required this.subjects,
    required this.students,
  });

  final String name;
  final ({num exams, num homework, num attendance, num behaviour}) weights;
  final ({num score, num attendance, num missing}) thresholds;
  final List<Named> subjects;
  final List<SectionStudent> students;

  factory SectionScores.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final s = j['section'] is Map
        ? j['section'] as Map
        : const <String, Object?>{};
    final w = j['weights'] is Map
        ? j['weights'] as Map
        : const <String, Object?>{};
    final t = j['thresholds'] is Map
        ? j['thresholds'] as Map
        : const <String, Object?>{};
    num n(Object? v) => (v as num?) ?? 0;
    return SectionScores(
      name: '${s['class_name'] ?? ''} ${s['name'] ?? ''}'.trim(),
      weights: (
        exams: n(w['exams_pct']),
        homework: n(w['homework_pct']),
        attendance: n(w['attendance_pct']),
        behaviour: n(w['behaviour_pct']),
      ),
      thresholds: (
        score: n(t['score_pct']),
        attendance: n(t['attendance_pct']),
        missing: n(t['missing_homework']),
      ),
      subjects: [
        if (j['subjects'] is List)
          for (final x in j['subjects'] as List)
            if (x is Map && x['id'] is String)
              (id: x['id'] as String, name: (x['name'] as String?) ?? ''),
      ],
      students: [
        if (j['students'] is List)
          for (final r in j['students'] as List)
            if (r is Map && r['student'] is Map)
              (
                id: ((r['student'] as Map)['id'] as String?) ?? '',
                name: ((r['student'] as Map)['full_name'] as String?) ?? '',
                rollNo: (r['student'] as Map)['roll_no'] as String?,
                overall: _line(r['overall']),
                subjects: {
                  if (r['subjects'] is List)
                    for (final x in r['subjects'] as List)
                      if (x is Map && x['subject'] is Map)
                        ((x['subject'] as Map)['id'] as String? ?? ''): _line(
                          x,
                        ),
                },
                homeworkSet: n(
                  (r['homework'] is Map
                      ? r['homework'] as Map
                      : const <String, Object?>{})['set'],
                ).toInt(),
                homeworkMissing: n(
                  (r['homework'] is Map
                      ? r['homework'] as Map
                      : const <String, Object?>{})['missing'],
                ).toInt(),
                missingHomework: n(r['missing_homework']).toInt(),
                atRisk: [
                  if (r['at_risk'] is List)
                    for (final a in r['at_risk'] as List)
                      if (a is String) a,
                ],
                position: (r['position'] as num?)?.toInt(),
              ),
      ],
    );
  }
}

final visibleSectionsProvider = FutureProvider.autoDispose<VisibleSections>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/scores/sections')).payload;
  final j = p is Map ? p : const <String, Object?>{};
  List<Named> list(Object? v, {bool section = false}) => [
    if (v is List)
      for (final x in v)
        if (x is Map && x['id'] is String)
          (
            id: x['id'] as String,
            name: section
                ? '${x['class_name'] ?? ''} ${x['name'] ?? ''}'.trim()
                : (x['name'] as String?) ?? '',
          ),
  ];
  return (
    sections: list(j['sections'], section: true),
    terms: list(j['terms']),
  );
}, retry: (retryCount, error) => null);

final sectionScoresProvider = FutureProvider.autoDispose
    .family<SectionScores, ({String sectionId, String? termId})>((
      ref,
      k,
    ) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/scores/sections/${k.sectionId}',
            query: {'term_id': ?k.termId},
          );
      return SectionScores.fromJson(r.payload);
    }, retry: (retryCount, error) => null);

/// The web's /performance for a teacher (Academic): a section and a term
/// (or the whole session), optionally one subject; the average, highest and
/// lowest, homework and attendance rates, the students at risk, and every
/// student's score with their position. A name opens the student's page.
/// The charts, the whole-school view (owners) and the weights stay on the
/// web.
class SectionPerformanceScreen extends ConsumerStatefulWidget {
  const SectionPerformanceScreen({super.key});

  @override
  ConsumerState<SectionPerformanceScreen> createState() =>
      _SectionPerformanceScreenState();
}

class _SectionPerformanceScreenState
    extends ConsumerState<SectionPerformanceScreen> {
  String? _sectionId;
  String? _termId;
  String? _subjectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final visible = ref.watch(visibleSectionsProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.performanceTitle, style: text.headlineSmall),
            Text(
              ref.levels(context, l10n.performanceIntro),
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ...visible.when(
              loading: () => [
                SizedBox(
                  height: 220,
                  child: LoadingView(semanticsLabel: l10n.performanceTitle),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 300,
                  child: e is ApiException && e.isFeatureLocked
                      ? EmptyView(
                          icon: Icons.lock_outline,
                          title: l10n.featuresLockedTitle,
                        )
                      : ErrorView(
                          title: l10n.performanceLoadFailed,
                          retryLabel: l10n.uiErrorRetry,
                          onRetry: () =>
                              ref.invalidate(visibleSectionsProvider),
                        ),
                ),
              ],
              data: (v) {
                if (v.sections.isEmpty) {
                  return [
                    SizedBox(
                      height: 260,
                      child: EmptyView(
                        icon: Icons.insights_outlined,
                        title: ref.levels(context, l10n.performanceNoSections),
                        message: ref.levels(
                          context,
                          l10n.performanceNoSectionsHint,
                        ),
                      ),
                    ),
                  ];
                }
                final section = v.sections.any((s) => s.id == _sectionId)
                    ? _sectionId!
                    : v.sections.first.id;
                final term = v.terms.any((t) => t.id == _termId)
                    ? _termId
                    : null;
                return [
                  DropdownButtonFormField<String>(
                    key: const Key('perf-section'),
                    initialValue: section,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: ref.levels(context, l10n.performanceSection),
                    ),
                    items: [
                      for (final s in v.sections)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (x) => setState(() {
                      _sectionId = x;
                      _subjectId = null;
                    }),
                  ),
                  if (v.terms.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<String?>(
                      key: const Key('perf-term'),
                      initialValue: term,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.performanceTerm,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          child: Text(l10n.performanceWholeSession),
                        ),
                        for (final t in v.terms)
                          DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(t.name),
                          ),
                      ],
                      onChanged: (x) => setState(() => _termId = x),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _SectionView(
                    key: ValueKey('$section/$term'),
                    sectionId: section,
                    termId: term,
                    subjectId: _subjectId,
                    onSubject: (s) => setState(() => _subjectId = s),
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionView extends ConsumerWidget {
  const _SectionView({
    required this.sectionId,
    required this.termId,
    required this.subjectId,
    required this.onSubject,
    super.key,
  });

  final String sectionId;
  final String? termId;
  final String? subjectId;
  final ValueChanged<String?> onSubject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final key = (sectionId: sectionId, termId: termId);
    final data = ref.watch(sectionScoresProvider(key));
    String n(num v) => OrgTime.number(v, language);
    String pct(num? v) => v == null ? '—' : '${n(v)}%';
    return data.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, _) => SizedBox(
        height: 260,
        child: ErrorView(
          title: l10n.performanceLoadFailed,
          retryLabel: l10n.uiErrorRetry,
          onRetry: () => ref.invalidate(sectionScoresProvider(key)),
        ),
      ),
      data: (d) {
        ScorePart? lineOf(SectionStudent s) =>
            subjectId == null ? s.overall : s.subjects[subjectId];
        num round1(num v) => (v * 10).round() / 10;
        final scores = [for (final s in d.students) ?lineOf(s)?.score];
        final set = d.students.fold<int>(0, (a, s) => a + s.homeworkSet);
        final missing = d.students.fold<int>(
          0,
          (a, s) => a + s.homeworkMissing,
        );
        final attendance = [for (final s in d.students) ?s.overall.attendance];
        final average = scores.isEmpty
            ? null
            : round1(scores.reduce((a, b) => a + b) / scores.length);
        final highest = scores.isEmpty
            ? null
            : scores.reduce((a, b) => a > b ? a : b);
        final lowest = scores.isEmpty
            ? null
            : scores.reduce((a, b) => a < b ? a : b);
        final homeworkRate = set == 0
            ? null
            : round1((set - missing) / set * 100);
        final attendanceRate = attendance.isEmpty
            ? null
            : round1(attendance.reduce((a, b) => a + b) / attendance.length);
        final grades = <String, int>{};
        for (final s in d.students) {
          final g = lineOf(s)?.grade;
          if (g != null) grades[g] = (grades[g] ?? 0) + 1;
        }
        final atRisk = [
          for (final s in d.students)
            if (s.atRisk.isNotEmpty) s,
        ];
        final rows = [...d.students]
          ..sort(
            (a, b) => (a.position ?? 1 << 30).compareTo(b.position ?? 1 << 30),
          );
        Widget stat(String label, String value) => Container(
          constraints: const BoxConstraints(minWidth: 104),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: colors.canvas,
            borderRadius: AppRadius.inputAll,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              Text(value, style: text.titleMedium),
            ],
          ),
        );
        void open(SectionStudent s) =>
            context.push('${AppRoutes.performance}/students/${s.id}');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.performanceWeightsLine(
                n(d.weights.exams),
                n(d.weights.homework),
                n(d.weights.attendance),
                n(d.weights.behaviour),
              ),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            if (d.subjects.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: const Key('perf-subject'),
                initialValue: subjectId,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.performanceSubject),
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(l10n.performanceAllSubjects),
                  ),
                  for (final s in d.subjects)
                    DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: onSubject,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                stat(l10n.performanceAverage, pct(average)),
                stat(l10n.performanceHighest, pct(highest)),
                stat(l10n.performanceLowest, pct(lowest)),
                stat(l10n.performanceHomeworkRate, pct(homeworkRate)),
                stat(l10n.performanceAttendanceRate, pct(attendanceRate)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.performanceGradesTitle, style: text.titleMedium),
                  if (grades.isEmpty)
                    Text(
                      l10n.performanceNoScores,
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    )
                  else
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final g in grades.keys.toList()..sort())
                          StatusPill(
                            label:
                                '$g · ${l10n.performanceStudentsCount(grades[g]!)}',
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            AppCard(
              key: const Key('perf-at-risk'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.performanceAtRiskTitle, style: text.titleMedium),
                  Text(
                    l10n.performanceAtRiskLimits(
                      n(d.thresholds.score),
                      n(d.thresholds.attendance),
                      n(d.thresholds.missing),
                    ),
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  if (atRisk.isEmpty)
                    Text(l10n.performanceNoneAtRisk, style: text.bodySmall)
                  else
                    for (final s in atRisk)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            InkWell(
                              onTap: () => open(s),
                              child: Text(
                                s.name,
                                style: text.bodyMedium?.copyWith(
                                  color: colors.primary,
                                ),
                              ),
                            ),
                            for (final r in s.atRisk)
                              StatusPill(
                                tone: StatusTone.warning,
                                label: switch (r) {
                                  'ATTENDANCE' =>
                                    l10n.performanceRiskATTENDANCE(
                                      pct(s.overall.attendance),
                                    ),
                                  'MISSING_HOMEWORK' =>
                                    l10n.performanceRiskMISSINGHOMEWORK(
                                      n(s.missingHomework),
                                    ),
                                  _ => l10n.performanceRiskSCORE(
                                    pct(s.overall.score),
                                  ),
                                },
                              ),
                          ],
                        ),
                      ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.performanceTableCaption(d.name), style: text.titleMedium),
            if (rows.isEmpty)
              Text(
                ref.levels(context, l10n.performanceNoStudents),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              )
            else
              for (final s in rows)
                ListTile(
                  key: Key('perf-student-${s.id}'),
                  contentPadding: EdgeInsets.zero,
                  onTap: () => open(s),
                  leading: CircleAvatar(
                    backgroundColor: colors.primarySoft,
                    foregroundColor: colors.primary,
                    child: Text(s.position == null ? '—' : n(s.position!)),
                  ),
                  title: Text(
                    s.rollNo == null ? s.name : '${s.rollNo}. ${s.name}',
                  ),
                  subtitle: Text(
                    [
                      '${l10n.performancePartsExams} ${pct(lineOf(s)?.exams)}',
                      '${l10n.performancePartsHomework} ${pct(lineOf(s)?.homework)}',
                      '${l10n.performancePartsAttendance} ${pct(s.overall.attendance)}',
                      '${l10n.performancePartsBehaviour} ${pct(lineOf(s)?.behaviour)}',
                    ].join(' · '),
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                  trailing: Text(
                    '${pct(lineOf(s)?.score)}'
                    '${lineOf(s)?.grade == null ? '' : ' (${lineOf(s)!.grade})'}',
                    style: text.titleSmall,
                  ),
                ),
          ],
        );
      },
    );
  }
}
