import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';
import 'package:instructor_app/features/calendar/data/reminders.dart';
import 'package:instructor_app/features/calendar/widgets/calendar_item_tile.dart';

const _allWorkspaces = '*';

/// The web's /calendar (month view): the person's classes, events, exams,
/// homework and holidays from every workspace, by kind and workspace; a
/// day's list beside the month; "My reminders", read only. Adding events
/// (staff), the week and day views and the calendar link stay on the web.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late String _day = OrgTime.today();
  final _kinds = {...CalendarKind.values};
  String _workspace = _allWorkspaces;

  String get _month => _day.substring(0, 7);

  CalendarRange get _range {
    final first = DateTime.utc(
      int.parse(_month.substring(0, 4)),
      int.parse(_month.substring(5, 7)),
    );
    final last = DateTime.utc(first.year, first.month + 1, 0);
    String f(DateTime d) => DateFormat('yyyy-MM-dd').format(d);
    return (from: f(first), to: f(last));
  }

  void _move(int months) {
    final today = OrgTime.today();
    final y = int.parse(_month.substring(0, 4));
    final m = int.parse(_month.substring(5, 7)) + months;
    final next = DateTime.utc(y, m);
    final key = DateFormat('yyyy-MM').format(next);
    // A month opens on today when it is this month, else on its first day.
    setState(() => _day = key == today.substring(0, 7) ? today : '$key-01');
  }

  String _kindFilter(AppLocalizations l10n, CalendarKind k) => switch (k) {
    CalendarKind.classItem => l10n.calendarFiltersCLASS,
    CalendarKind.event => l10n.calendarFiltersEVENT,
    CalendarKind.exam => l10n.calendarFiltersEXAM,
    CalendarKind.homework => l10n.calendarFiltersHOMEWORK,
    CalendarKind.holiday => l10n.calendarFiltersHOLIDAY,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final locale = OrgTime.intlLocale(language);
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final feed = ref.watch(calendarFeedProvider(_range));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.calendarTitle, style: text.headlineSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.calendarIntro,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                IconButton(
                  tooltip: l10n.calendarPrevious,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _move(-1),
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM(locale)
                        .format(DateTime.parse('$_month-01T00:00:00Z')),
                    textAlign: TextAlign.center,
                    style: text.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: l10n.calendarNext,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _move(1),
                ),
                TextButton(
                  onPressed: () => setState(() => _day = OrgTime.today()),
                  child: Text(l10n.calendarToday),
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final k in CalendarKind.values)
                  FilterChip(
                    label: Text(_kindFilter(l10n, k)),
                    selected: _kinds.contains(k),
                    onSelected: (on) =>
                        setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...feed.when(
              loading: () => [
                SizedBox(
                  height: 240,
                  child: LoadingView(semanticsLabel: l10n.calendarTitle),
                ),
              ],
              error: (_, _) => [
                SizedBox(
                  height: 300,
                  child: ErrorView(
                    title: l10n.calendarLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(calendarFeedProvider(_range)),
                  ),
                ),
              ],
              data: (feed) {
                final workspaces = feed.workspaces ?? const [];
                final items = feed.items
                    .where(
                      (i) =>
                          _kinds.contains(i.kind) &&
                          (_workspace == _allWorkspaces ||
                              i.workspace?.key == _workspace),
                    )
                    .toList();
                final day = items.where((i) => i.day == _day).toList();
                return [
                  if (workspaces.length > 1) ...[
                    DropdownButtonFormField<String>(
                      key: const Key('calendar-workspace'),
                      initialValue: _workspace,
                      decoration: InputDecoration(
                        labelText: l10n.calendarWorkspace,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: _allWorkspaces,
                          child: Text(l10n.calendarAllWorkspaces),
                        ),
                        for (final w in workspaces)
                          DropdownMenuItem(value: w.key, child: Text(w.label)),
                      ],
                      onChanged: (v) =>
                          setState(() => _workspace = v ?? _allWorkspaces),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  _MonthGrid(
                    month: _month,
                    items: items,
                    selected: _day,
                    onSelect: (d) => setState(() => _day = d),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    key: const Key('calendar-day'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          DateFormat.MMMMEEEEd(locale)
                              .format(DateTime.parse('${_day}T00:00:00Z')),
                          style: text.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        if (day.isEmpty)
                          Text(
                            l10n.calendarNothingThisDay,
                            style: text.bodyMedium?.copyWith(
                              color: colors.inkMuted,
                            ),
                          )
                        else
                          for (final (n, i) in day.indexed) ...[
                            if (n > 0) const SizedBox(height: AppSpacing.sm),
                            CalendarItemTile(
                              item: i,
                              showWorkspace: workspaces.length > 1,
                            ),
                          ],
                      ],
                    ),
                  ),
                ];
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            const _Reminders(),
          ],
        ),
      ),
    );
  }
}

/// A month, Saturday first; each day shows a dot per kind it has, holidays
/// greyed; today outlined; the selected day filled.
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final String month;
  final List<CalendarItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final locale = OrgTime.intlLocale(language);
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final first = DateTime.parse('$month-01T00:00:00Z');
    final days = DateTime.utc(first.year, first.month + 1, 0).day;
    final lead = (first.weekday + 1) % 7;
    final today = OrgTime.today();
    final byDay = <String, List<CalendarItem>>{};
    for (final i in items) {
      (byDay[i.day] ??= []).add(i);
    }
    Color dot(CalendarKind k) => switch (k) {
      CalendarKind.classItem => c.primary,
      CalendarKind.event => c.success,
      CalendarKind.exam => c.warning,
      CalendarKind.homework => c.info,
      CalendarKind.holiday => c.inkMuted,
    };
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - 6 * 4) / 7;
        return Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (var i = 0; i < 7; i++)
              SizedBox(
                width: width,
                child: Center(
                  child: Text(
                    DateFormat.E(locale).format(DateTime.utc(2026, 11, 14 + i)),
                    style: text.labelSmall?.copyWith(color: c.inkMuted),
                  ),
                ),
              ),
            for (var i = 0; i < lead; i++) SizedBox(width: width),
            for (var d = 1; d <= days; d++)
              Builder(
                builder: (_) {
                  final date = '$month-${d.toString().padLeft(2, '0')}';
                  final here = byDay[date] ?? const [];
                  final kinds = {for (final i in here) i.kind};
                  final closed = kinds.contains(CalendarKind.holiday);
                  final isSelected = date == selected;
                  return SizedBox(
                    width: width,
                    child: Semantics(
                      button: true,
                      selected: isSelected,
                      label: l10n.calendarOpenDay(
                        OrgTime.schoolDay(date, language),
                      ),
                      excludeSemantics: true,
                      child: InkWell(
                        key: Key('day-$date'),
                        borderRadius: AppRadius.inputAll,
                        onTap: () => onSelect(date),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 48),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? c.primarySoft
                                : closed
                                ? c.canvas
                                : c.surface,
                            borderRadius: AppRadius.inputAll,
                            border: Border.all(
                              color: date == today ? c.primary : c.border,
                              width: date == today ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                OrgTime.number(d, language),
                                style: text.labelMedium?.copyWith(
                                  color: closed ? c.inkMuted : c.ink,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : null,
                                ),
                              ),
                              Wrap(
                                spacing: 2,
                                children: [
                                  for (final k in CalendarKind.values)
                                    if (kinds.contains(k) &&
                                        k != CalendarKind.holiday)
                                      Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: dot(k),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

/// "My reminders", read only: changed on the web.
class _Reminders extends ConsumerWidget {
  const _Reminders();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final reminders = ref.watch(remindersProvider).value;
    if (reminders == null || reminders.isEmpty) return const SizedBox.shrink();
    String before(int minutes) => minutes % 1440 == 0
        ? l10n.calendarRemindersDays(minutes ~/ 1440)
        : minutes % 60 == 0
        ? l10n.calendarRemindersHours(minutes ~/ 60)
        : l10n.calendarRemindersMinutes(minutes);

    String target(String k) => switch (k) {
      'CLASS' => l10n.calendarRemindersTargetsCLASS,
      'EXAM' => l10n.calendarRemindersTargetsEXAM,
      _ => l10n.calendarRemindersTargetsEVENT,
    };
    return AppCard(
      key: const Key('calendar-reminders'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.calendarRemindersTitle, style: text.titleMedium),
          Text(
            l10n.calendarRemindersIntro,
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final k in const ['CLASS', 'EXAM', 'EVENT'])
            if (reminders[k] case final r?)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 96,
                      child: Text(target(k), style: text.bodyMedium),
                    ),
                    Expanded(
                      child: Text(
                        [
                          if (r.offsets.isEmpty) l10n.calendarRemindersOff,
                          for (final o in r.offsets)
                            l10n.calendarRemindersItem(
                              before(o.minutes),
                              o.channel == 'SMS'
                                  ? l10n.calendarRemindersChannelsSMS
                                  : l10n.calendarRemindersChannelsINAPP,
                            ),
                          if (!r.own) '(${l10n.calendarRemindersUsingDefault})',
                        ].join('\n'),
                        style: text.bodyMedium,
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
