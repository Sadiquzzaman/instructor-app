import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';

typedef SchoolSection = ({
  String id,
  String label,
  int students,
  num? average,
  num? highest,
  num? lowest,
  num? attendance,
  num? homework,
  int atRisk,
});

typedef SchoolSubject = ({String id, String name, num? average, int sections});

typedef SchoolOverview = ({
  List<SchoolSection> sections,
  List<SchoolSubject> subjects,
});

final schoolOverviewProvider = FutureProvider.autoDispose
    .family<SchoolOverview, ({String? sessionId, String? termId})>((
      ref,
      k,
    ) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get(
                    '/scores/overview',
                    query: {'session_id': k.sessionId, 'term_id': k.termId},
                  ))
              .payload;
      final j = p is Map ? p : const <String, Object?>{};
      return (
        sections: [
          if (j['sections'] is List)
            for (final r in j['sections'] as List)
              if (r is Map && r['section'] is Map)
                (
                  id: ((r['section'] as Map)['id'] as String?) ?? '',
                  label:
                      '${(r['section'] as Map)['class_name'] ?? ''} ${(r['section'] as Map)['name'] ?? ''}'
                          .trim(),
                  students: (r['students'] as num?)?.toInt() ?? 0,
                  average: r['average_pct'] as num?,
                  highest: r['highest_pct'] as num?,
                  lowest: r['lowest_pct'] as num?,
                  attendance: r['attendance_pct'] as num?,
                  homework: r['homework_rate_pct'] as num?,
                  atRisk: (r['at_risk'] as num?)?.toInt() ?? 0,
                ),
        ]..sort((a, b) => a.label.compareTo(b.label)),
        subjects: [
          if (j['subjects'] is List)
            for (final r in j['subjects'] as List)
              if (r is Map && r['subject'] is Map)
                (
                  id: ((r['subject'] as Map)['id'] as String?) ?? '',
                  name: ((r['subject'] as Map)['name'] as String?) ?? '',
                  average: r['average_pct'] as num?,
                  sections: (r['sections'] as num?)?.toInt() ?? 0,
                ),
        ]..sort((a, b) => a.name.compareTo(b.name)),
      );
    }, retry: (retryCount, error) => null);

/// The whole school (the web's SchoolView; owners, admins and assistants):
/// each section's numbers and each subject's average across sections; a
/// section opens its own view.
class SchoolOverviewView extends ConsumerWidget {
  const SchoolOverviewView({
    required this.sessionId,
    required this.termId,
    required this.onOpen,
    super.key,
  });

  final String? sessionId;
  final String? termId;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final key = (sessionId: sessionId, termId: termId);
    final data = ref.watch(schoolOverviewProvider(key));
    String pct(num? v) => v == null ? '—' : '${OrgTime.number(v, language)}%';
    return data.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => SizedBox(
        height: 240,
        child: ErrorView(
          title: l10n.performanceLoadFailed,
          retryLabel: l10n.uiErrorRetry,
          onRetry: () => ref.invalidate(schoolOverviewProvider(key)),
        ),
      ),
      data: (d) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ref.levels(context, l10n.performanceBySection),
            style: text.titleMedium,
          ),
          for (final s in d.sections) ...[
            const SizedBox(height: AppSpacing.sm),
            AppCard(
              key: Key('school-${s.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.label, style: text.titleSmall)),
                      Text(pct(s.average), style: text.titleSmall),
                    ],
                  ),
                  Text(
                    [
                      '${l10n.performanceColumnsStudents} ${OrgTime.number(s.students, language)}',
                      '${l10n.performanceHighest} ${pct(s.highest)}',
                      '${l10n.performanceLowest} ${pct(s.lowest)}',
                      '${l10n.performanceAttendanceRate} ${pct(s.attendance)}',
                      '${l10n.performanceHomeworkRate} ${pct(s.homework)}',
                      '${l10n.performanceAtRiskTitle} ${OrgTime.number(s.atRisk, language)}',
                    ].join(' · '),
                    style: muted,
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton(
                      key: Key('school-open-${s.id}'),
                      onPressed: () => onOpen(s.id),
                      child: Text(l10n.performanceOpen),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(l10n.performanceBySubject, style: text.titleMedium),
          for (final s in d.subjects)
            ListTile(
              key: Key('school-subject-${s.id}'),
              contentPadding: EdgeInsets.zero,
              title: Text(s.name),
              subtitle: Text(
                '${ref.levels(context, l10n.performanceColumnsSections)}: ${OrgTime.number(s.sections, language)}',
              ),
              trailing: Text(pct(s.average), style: text.titleSmall),
            ),
        ],
      ),
    );
  }
}
