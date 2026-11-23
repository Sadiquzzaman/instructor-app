import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/attendance/screens/teacher_report.dart';
import 'package:instructor_app/features/attendance/data/attendance_reports.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';
import 'package:instructor_app/features/attendance/widgets/attendance_mark.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';

DateTime _day(String s) => DateTime.parse('${s}T00:00:00Z');

/// A report refusal in the web's words (`reports.errors`); null otherwise.
String? _reportError(WidgetRef ref, BuildContext context, Object e) {
  if (e is! ApiException) return null;
  final l10n = context.l10n;
  final m = switch (e.code) {
    'ATTENDANCE_REPORT_DATE_INVALID' =>
      l10n.reportsErrorsATTENDANCEREPORTDATEINVALID,
    'ATTENDANCE_REPORT_SECTION_NOT_FOUND' =>
      l10n.reportsErrorsATTENDANCEREPORTSECTIONNOTFOUND,
    'ATTENDANCE_REGISTER_SECTION_NOT_FOUND' =>
      l10n.reportsErrorsATTENDANCEREGISTERSECTIONNOTFOUND,
    'ATTENDANCE_REGISTER_SESSION_CLOSED' =>
      l10n.reportsErrorsATTENDANCEREGISTERSESSIONCLOSED,
    _ => null,
  };
  return m == null ? null : ref.levels(context, m);
}

/// The view for a failed report: locked, a known refusal, or retry.
Widget _failure(
  WidgetRef ref,
  BuildContext context,
  Object e,
  VoidCallback retry,
) {
  final l10n = context.l10n;
  if (e is ApiException && e.isFeatureLocked) {
    return EmptyView(icon: Icons.lock_outline, title: l10n.featuresLockedTitle);
  }
  return ErrorView(
    title: l10n.reportsLoadFailed,
    message: _reportError(ref, context, e),
    retryLabel: l10n.uiErrorRetry,
    onRetry: retry,
  );
}

/// The colour of a report day: a day still waiting shows as upcoming.
String _dayColour(String status) => status == 'WAITING' ? 'UPCOMING' : status;

/// Attendance reports (the web's `/attendance-reports`): the daily summary
/// per section, the monthly register and, for owners and admins, the
/// teachers' report. Printing and the CSV file stay on the web.
class AttendanceReportsScreen extends ConsumerStatefulWidget {
  const AttendanceReportsScreen({super.key});

  @override
  ConsumerState<AttendanceReportsScreen> createState() =>
      _AttendanceReportsScreenState();
}

class _AttendanceReportsScreenState
    extends ConsumerState<AttendanceReportsScreen> {
  /// 0 daily, 1 monthly, 2 teachers.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final sections = ref.watch(reportSectionsProvider);
    final role = ref.watch(sessionProvider)?.memberRole;
    final managers = role == 'OWNER' || role == 'ADMIN';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.reportsTitle, style: text.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            ...sections.when(
              loading: () => [
                SizedBox(
                  height: 240,
                  child: LoadingView(semanticsLabel: l10n.reportsTitle),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 320,
                  child: _failure(
                    ref,
                    context,
                    e,
                    () => ref.invalidate(reportSectionsProvider),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SizedBox(
                        height: 280,
                        child: EmptyView(
                          title: ref.levels(context, l10n.reportsNoSections),
                          message: ref.levels(
                            context,
                            l10n.reportsNoSectionsHint,
                          ),
                        ),
                      ),
                    ]
                  : [
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          for (final (i, key, label) in [
                            (0, 'tab-daily', l10n.reportsTabsDaily),
                            (1, 'tab-monthly', l10n.reportsTabsMonthly),
                            if (managers)
                              (2, 'tab-teachers', l10n.reportsTabsTeachers),
                          ])
                            ChoiceChip(
                              key: Key(key),
                              label: Text(label),
                              selected: _tab == i,
                              onSelected: (_) => setState(() => _tab = i),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      switch (_tab) {
                        1 => _Monthly(list),
                        2 when managers => const TeacherReportView(),
                        _ => _Daily(list),
                      },
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A section picker; [all] adds "All sections" (value null).
class _SectionPicker extends ConsumerWidget {
  const _SectionPicker({
    required this.sections,
    required this.value,
    required this.onChanged,
    this.all = false,
  });

  final List<ReportSection> sections;
  final String? value;
  final bool all;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return DropdownButtonFormField<String?>(
      key: const Key('report-section'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: ref.levels(context, l10n.reportsSection),
      ),
      items: [
        if (all)
          DropdownMenuItem<String?>(
            child: Text(ref.levels(context, l10n.reportsAllSections)),
          ),
        for (final s in sections)
          DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
      ],
      onChanged: onChanged,
    );
  }
}

class _Daily extends ConsumerStatefulWidget {
  const _Daily(this.sections);

  final List<ReportSection> sections;

  @override
  ConsumerState<_Daily> createState() => _DailyState();
}

class _DailyState extends ConsumerState<_Daily> {
  String? _date;
  String? _sectionId;

  ({String? date, String? sectionId}) get _key =>
      (date: _date, sectionId: _sectionId);

  Future<void> _pick(String shown) async {
    final today = OrgTime.today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _day(shown.isEmpty ? today : shown),
      firstDate: _day(addDays(today, -730)),
      lastDate: _day(addDays(today, 60)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final report = ref.watch(dailyReportProvider(_key));
    final shown = _date ?? report.value?.date ?? '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const Key('report-date'),
              onPressed: () => _pick(shown),
              icon: const Icon(Icons.event_outlined),
              label: Text(
                '${l10n.reportsDate}: '
                '${shown.isEmpty ? '' : OrgTime.schoolDay(shown, language)}',
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _SectionPicker(
          sections: widget.sections,
          value: _sectionId,
          all: true,
          onChanged: (v) => setState(() => _sectionId = v),
        ),
        const SizedBox(height: AppSpacing.md),
        report.when(
          loading: () => SizedBox(
            height: 200,
            child: LoadingView(semanticsLabel: l10n.reportsTabsDaily),
          ),
          error: (e, _) => SizedBox(
            height: 300,
            child: _failure(
              ref,
              context,
              e,
              () => ref.invalidate(dailyReportProvider(_key)),
            ),
          ),
          data: (r) {
            final closed = r.closed == null
                ? null
                : (r.closed!.reason == 'HOLIDAY'
                      ? l10n.reportsClosedHOLIDAY
                      : l10n.reportsClosedWEEKLYOFF);
            if (r.sections.isEmpty) {
              return SizedBox(
                height: 260,
                child: EmptyView(
                  icon: Icons.event_busy_outlined,
                  title: closed ?? l10n.reportsNoClassesDay,
                  message: l10n.reportsNoClassesDayHint,
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (closed != null)
                  Text(
                    closed,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                for (final s in r.sections) ...[
                  _DailySectionCard(s),
                  const SizedBox(height: AppSpacing.md),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DailySectionCard extends ConsumerWidget {
  const _DailySectionCard(this.s);

  final DailySection s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final times = s.classes
        .map(
          (c) =>
              '${OrgTime.timeOfDay(c.start, language)}–'
              '${OrgTime.timeOfDay(c.end, language)}'
              '${c.cancelled ? ' (${l10n.reportsCancelled})' : ''}',
        )
        .join(', ');
    final mode = s.mode == 'PAPER_REGISTER'
        ? l10n.registerModePAPERREGISTER
        : l10n.registerModeSELFCHECKIN;
    String group(String g) => switch (g) {
      'ABSENT' => ref.levels(context, l10n.reportsGroupABSENT),
      'MISSED_SOME' => l10n.reportsGroupMISSEDSOME,
      'LATE' => l10n.reportsGroupLATE,
      'LEAVE' => l10n.reportsGroupLEAVE,
      'WAITING' => l10n.reportsGroupWAITING,
      _ => l10n.reportsGroupPRESENT,
    };
    StatusTone tone(String g) => switch (g) {
      'ABSENT' => StatusTone.danger,
      'MISSED_SOME' || 'LATE' => StatusTone.warning,
      'LEAVE' => StatusTone.info,
      'PRESENT' => StatusTone.success,
      _ => StatusTone.neutral,
    };
    String nameOf(DailyStudent st) => st.day != null && st.day!.missed > 0
        ? '${st.name} (${l10n.reportsMissedShort(st.day!.missed)})'
        : st.name;
    return AppCard(
      key: Key('daily-${s.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.name, style: text.titleMedium),
          Text(
            '$mode · ${l10n.reportsClassesLine(s.classes.length, times)}'
            ' · ${l10n.reportsStudentsCount(s.studentCount)}',
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final g in dailyGroups)
            if (s.students.where((st) => dailyGroup(st.day) == g).toList()
                case final names when names.isNotEmpty)
              Padding(
                key: Key('group-${s.id}-$g'),
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatusPill(
                      label:
                          '${group(g)} · ${OrgTime.number(names.length, language)}',
                      tone: tone(g),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(names.map(nameOf).join(', '), style: text.bodySmall),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _Monthly extends ConsumerStatefulWidget {
  const _Monthly(this.sections);

  final List<ReportSection> sections;

  @override
  ConsumerState<_Monthly> createState() => _MonthlyState();
}

class _MonthlyState extends ConsumerState<_Monthly> {
  late String _sectionId = widget.sections.first.id;
  String _month = OrgTime.today().substring(0, 7);

  ({String sectionId, String month}) get _key =>
      (sectionId: _sectionId, month: _month);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final report = ref.watch(monthReportProvider(_key));
    final monthName = DateFormat.yMMMM(OrgTime.intlLocale(language))
        .format(_day('$_month-01'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionPicker(
          sections: widget.sections,
          value: _sectionId,
          onChanged: (v) => setState(() => _sectionId = v ?? _sectionId),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              key: const Key('month-previous'),
              tooltip: l10n.reportsPreviousMonth,
              onPressed: () => setState(() => _month = shiftMonth(_month, -1)),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              monthName,
              key: const Key('month-name'),
              style: text.titleSmall,
            ),
            IconButton(
              key: const Key('month-next'),
              tooltip: l10n.reportsNextMonth,
              onPressed: () => setState(() => _month = shiftMonth(_month, 1)),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        report.when(
          loading: () => SizedBox(
            height: 200,
            child: LoadingView(semanticsLabel: l10n.reportsTabsMonthly),
          ),
          error: (e, _) => SizedBox(
            height: 300,
            child: _failure(
              ref,
              context,
              e,
              () => ref.invalidate(monthReportProvider(_key)),
            ),
          ),
          data: (r) => r.days.isEmpty
              ? SizedBox(
                  height: 260,
                  child: EmptyView(
                    icon: Icons.event_busy_outlined,
                    title: l10n.reportsNoClasses,
                    message: ref.levels(context, l10n.reportsNoClassesHint),
                  ),
                )
              : _MonthGrid(r),
        ),
      ],
    );
  }
}

/// Students by class day, with counts and %; scrolls sideways on phones.
class _MonthGrid extends ConsumerWidget {
  const _MonthGrid(this.r);

  final MonthReport r;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    String n(num v) => OrgTime.number(v, language);
    String pct(num? v) => v == null ? '—' : '${n(v)}%';
    Widget head(String s) => Text(s, style: text.labelSmall);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ref.levels(
              context,
              l10n.reportsMonthHint(
                r.days.length,
                r.classCount,
                r.students.length,
                pct(r.percent),
              ),
            ),
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          // The letters and their colours.
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xs,
            children: [
              for (final s in const ['PRESENT', 'LATE', 'ABSENT', 'LEAVE'])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AttendanceMark(
                      status: s,
                      letter: attendanceLetter(l10n, s),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(switch (s) {
                      'PRESENT' => l10n.reportsDayPRESENT,
                      'LATE' => l10n.reportsDayLATE,
                      'ABSENT' => l10n.reportsDayABSENT,
                      _ => l10n.reportsDayLEAVE,
                    }, style: text.bodySmall),
                  ],
                ),
              Text(l10n.reportsLegendMissed, style: text.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (r.students.isEmpty)
            Text(ref.levels(context, l10n.reportsNoStudents))
          else
            SingleChildScrollView(
              key: const Key('month-grid'),
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: AppSpacing.md,
                horizontalMargin: 0,
                headingRowHeight: 36,
                columns: [
                  DataColumn(label: head(l10n.reportsColumnsRoll)),
                  DataColumn(label: head(l10n.reportsColumnsName)),
                  for (final d in r.days)
                    DataColumn(label: head(n(int.parse(d.substring(8, 10))))),
                  DataColumn(
                    numeric: true,
                    label: head(l10n.reportsShortPresent),
                  ),
                  DataColumn(numeric: true, label: head(l10n.reportsShortLate)),
                  DataColumn(
                    numeric: true,
                    label: head(l10n.reportsShortAbsent),
                  ),
                  DataColumn(
                    numeric: true,
                    label: head(l10n.reportsShortLeave),
                  ),
                  const DataColumn(numeric: true, label: Text('%')),
                ],
                rows: [
                  for (final s in r.students)
                    DataRow(
                      key: ValueKey('month-row-${s.id}'),
                      cells: [
                        DataCell(Text(s.rollNo ?? '—')),
                        DataCell(Text(s.name)),
                        for (var i = 0; i < r.days.length; i++)
                          DataCell(
                            _DayCell(i < s.days.length ? s.days[i] : null),
                          ),
                        DataCell(Text(n(s.counts.present))),
                        DataCell(Text(n(s.counts.late))),
                        DataCell(Text(n(s.counts.absent))),
                        DataCell(Text(n(s.counts.leave))),
                        DataCell(Text(pct(s.percent))),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// A register day: its colour and letter, with the classes missed that day
/// as a small number; a dot when no class counted.
class _DayCell extends StatelessWidget {
  const _DayCell(this.d);

  final DayMark? d;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final day = d;
    if (day == null) {
      return Text('·', style: TextStyle(color: colors.inkMuted));
    }
    final colour = _dayColour(day.status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AttendanceMark(
          status: colour,
          letter: day.status == 'WAITING' ? '' : attendanceLetter(l10n, colour),
        ),
        if (day.missed > 0)
          Text(
            OrgTime.number(day.missed, language),
            style: text.labelSmall?.copyWith(color: colors.inkMuted),
          ),
      ],
    );
  }
}
