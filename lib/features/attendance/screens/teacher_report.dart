import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/attendance/widgets/attendance_mark.dart';

typedef TeacherClass = ({
  String date,
  String start,
  String end,
  String section,
  String status,
  int? lateMinutes,
});

typedef TeacherRow = ({
  String id,
  String name,
  Map<String, int> counts,
  num? pct,
  int lateMinutes,
  List<TeacherClass> classes,
});

typedef TeacherReport = ({
  String from,
  String to,
  String today,
  List<TeacherRow> teachers,
});

final teacherReportProvider = FutureProvider.autoDispose
    .family<TeacherReport, ({String? from, String? to})>((ref, q) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get(
                    '/attendance/reports/teachers',
                    query: {'from': q.from, 'to': q.to},
                  ))
              .payload;
      final j = p is Map ? p : const <String, Object?>{};
      return (
        from: (j['from'] as String?) ?? '',
        to: (j['to'] as String?) ?? '',
        today: (j['today'] as String?) ?? '',
        teachers: [
          if (j['teachers'] is List)
            for (final t in j['teachers'] as List)
              if (t is Map && t['teacher'] is Map)
                (
                  id: ((t['teacher'] as Map)['id'] as String?) ?? '',
                  name: ((t['teacher'] as Map)['full_name'] as String?) ?? '',
                  counts: {
                    for (final k in ['present', 'late', 'absent', 'leave'])
                      k:
                          ((t['counts'] is Map ? (t['counts'] as Map)[k] : null)
                                  as num?)
                              ?.toInt() ??
                          0,
                  },
                  pct: t['attendance_pct'] as num?,
                  lateMinutes: (t['late_minutes'] as num?)?.toInt() ?? 0,
                  classes: [
                    if (t['classes'] is List)
                      for (final c in t['classes'] as List)
                        if (c is Map)
                          (
                            date: (c['date'] as String?) ?? '',
                            start: (c['start_time'] as String?) ?? '',
                            end: (c['end_time'] as String?) ?? '',
                            section: c['section'] is Map
                                ? '${(c['section'] as Map)['class_name'] ?? ''} ${(c['section'] as Map)['name'] ?? ''}'
                                      .trim()
                                : '',
                            status: (c['status'] as String?) ?? '',
                            lateMinutes: (c['late_minutes'] as num?)?.toInt(),
                          ),
                  ],
                ),
        ],
      );
    }, retry: (retryCount, error) => null);

/// The first and last day of [yyyyMm]'s month.
({String from, String to}) monthRange(String yyyyMm) {
  final y = int.parse(yyyyMm.substring(0, 4));
  final m = int.parse(yyyyMm.substring(5, 7));
  final last = DateTime.utc(y, m + 1, 0).day;
  return (from: '$yyyyMm-01', to: '$yyyyMm-${last.toString().padLeft(2, '0')}');
}

/// The teachers' report (the web's TeacherReport; owners and admins): each
/// teacher's classes from a date to a date (at most 31 days; today by
/// default), with counts, %, minutes late and the classes not on time.
/// Printing and the CSV file stay on the web.
class TeacherReportView extends ConsumerStatefulWidget {
  const TeacherReportView({super.key});

  @override
  ConsumerState<TeacherReportView> createState() => _TeacherReportViewState();
}

class _TeacherReportViewState extends ConsumerState<TeacherReportView> {
  String? _from;
  String? _to;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final report = ref.watch(teacherReportProvider((from: _from, to: _to)));
    final r = report.value;
    final from = _from ?? r?.from;
    final to = _to ?? r?.to;
    String day(String d) => d.isEmpty ? '' : OrgTime.schoolDay(d, language);
    String pct(num? v) => v == null ? '—' : '${OrgTime.number(v, language)}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DateField(
                key: const Key('tr-from'),
                label: l10n.reportsFrom,
                value: from,
                onChanged: (v) => setState(() {
                  _from = v;
                  _to = to != null && to.compareTo(v) >= 0 ? to : v;
                }),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DateField(
                key: const Key('tr-to'),
                label: l10n.reportsTo,
                value: to,
                min: from,
                onChanged: (v) => setState(() {
                  _from = from;
                  _to = v;
                }),
              ),
            ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            OutlinedButton(
              key: const Key('tr-today'),
              onPressed: r == null || r.today.isEmpty
                  ? null
                  : () => setState(() {
                      _from = r.today;
                      _to = r.today;
                    }),
              child: Text(l10n.reportsToday),
            ),
            OutlinedButton(
              key: const Key('tr-month'),
              onPressed: r == null || r.today.isEmpty
                  ? null
                  : () => setState(() {
                      final m = monthRange(r.today.substring(0, 7));
                      _from = m.from;
                      _to = m.to;
                    }),
              child: Text(l10n.reportsThisMonth),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.reportsTeachersTitle, style: text.titleMedium),
        if (r != null)
          Text(
            '${r.from == r.to ? day(r.from) : '${day(r.from)} – ${day(r.to)}'}'
            ' · ${l10n.reportsTeachersHint}',
            style: muted,
          ),
        const SizedBox(height: AppSpacing.sm),
        if (r == null)
          report.hasError
              ? SizedBox(
                  height: 240,
                  child: ErrorView(
                    title: l10n.reportsLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(teacherReportProvider),
                  ),
                )
              : const LinearProgressIndicator()
        else if (r.teachers.isEmpty)
          SizedBox(
            height: 200,
            child: EmptyView(
              icon: Icons.person_search_outlined,
              title: l10n.reportsNoTeachers,
              message: l10n.reportsNoTeachersHint,
            ),
          )
        else ...[
          for (final t in r.teachers) ...[
            AppCard(
              key: Key('tr-${t.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(t.name, style: text.titleSmall)),
                      Text(pct(t.pct), style: text.titleSmall),
                    ],
                  ),
                  Text(
                    [
                      '${l10n.reportsColumnsPresent} ${OrgTime.number(t.counts['present']!, language)}',
                      '${l10n.reportsColumnsLate} ${OrgTime.number(t.counts['late']!, language)}',
                      '${l10n.reportsColumnsAbsent} ${OrgTime.number(t.counts['absent']!, language)}',
                      '${l10n.reportsColumnsLeave} ${OrgTime.number(t.counts['leave']!, language)}',
                      '${l10n.reportsColumnsLateMinutes} ${OrgTime.number(t.lateMinutes, language)}',
                    ].join(' · '),
                    style: muted,
                  ),
                  for (final c in t.classes)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${day(c.date)} ${OrgTime.timeOfDay(c.start, language)}–'
                            '${OrgTime.timeOfDay(c.end, language)} · ${c.section}',
                            style: text.bodySmall,
                          ),
                          StatusPill(
                            label:
                                attendanceStatusName(l10n, c.status) +
                                (c.lateMinutes != null
                                    ? ' · ${l10n.reportsMinutesLate(c.lateMinutes!)}'
                                    : ''),
                            tone: attendanceTone(c.status),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}
