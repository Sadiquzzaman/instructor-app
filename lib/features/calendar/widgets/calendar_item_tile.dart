import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';

/// The title the web shows for an item (`useLabel`): a class's subject and
/// section, homework "Due: …", a closed day's name, else its title.
String calendarLabel(AppLocalizations l10n, CalendarItem item) =>
    switch (item.kind) {
      CalendarKind.classItem =>
        item.subject != null ? '${item.subject} · ${item.title}' : item.title,
      CalendarKind.holiday =>
        item.title.isNotEmpty
            ? item.title
            : item.reason == 'WEEKLY_OFF'
            ? l10n.calendarClosedWEEKLYOFF
            : l10n.calendarClosedHOLIDAY,
      CalendarKind.homework => l10n.calendarDue(item.title),
      _ => item.title,
    };

String calendarKindName(AppLocalizations l10n, CalendarKind kind) =>
    switch (kind) {
      CalendarKind.classItem => l10n.calendarKindsCLASS,
      CalendarKind.event => l10n.calendarKindsEVENT,
      CalendarKind.exam => l10n.calendarKindsEXAM,
      CalendarKind.homework => l10n.calendarKindsHOMEWORK,
      CalendarKind.holiday => l10n.calendarKindsHOLIDAY,
    };

/// Who and where (the web's `detailOf`), and the workspace when there are
/// several.
String calendarDetail(CalendarItem item, {required bool showWorkspace}) {
  final parts = <String?>[
    ...switch (item.kind) {
      // A teacher's own classes don't repeat their name.
      CalendarKind.classItem => [
        item.role == 'TEACHER' ? null : item.teacher,
        item.room,
      ],
      CalendarKind.event => [item.place],
      CalendarKind.homework => [item.subject, item.sections.join(', ')],
      CalendarKind.exam => [item.className],
      CalendarKind.holiday => <String?>[],
    },
    if (showWorkspace) item.workspace?.label,
  ];
  return parts.where((p) => p != null && p.isNotEmpty).join(' · ');
}

/// "09:00–09:45", or the due time for homework.
String calendarTime(CalendarItem item, String language) {
  final start = item.startsAt;
  if (start == null) return '';
  final from = OrgTime.time(start, language);
  if (item.kind == CalendarKind.homework || item.endsAt == null) return from;
  return '$from–${OrgTime.time(item.endsAt!, language)}';
}

/// One item in a day's list (the web's `AgendaItem`): time, title, details,
/// and its state; a coloured edge by kind. Tapping opens [showCalendarItem].
class CalendarItemTile extends StatelessWidget {
  const CalendarItemTile({
    required this.item,
    required this.showWorkspace,
    this.caption,
    super.key,
  });

  final CalendarItem item;
  final bool showWorkspace;

  /// A line above, such as the day ("Wed 19 Nov").
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final (edge, fill) = switch (item.kind) {
      CalendarKind.classItem => (colors.primary, colors.primarySoft),
      CalendarKind.event => (colors.success, colors.successSoft),
      CalendarKind.exam => (colors.warning, colors.warningSoft),
      CalendarKind.homework => (colors.info, colors.infoSoft),
      CalendarKind.holiday => (colors.border, colors.canvas),
    };
    final label = calendarLabel(l10n, item);
    final detail = calendarDetail(item, showWorkspace: showWorkspace);
    final time = calendarTime(item, language);
    final cancelled = item.isCancelled;
    final handedIn = item.kind == CalendarKind.homework ? item.handedIn : null;
    return Semantics(
      button: item.isTimed,
      label: item.isTimed
          ? l10n.calendarOpenItem(
              calendarKindName(l10n, item.kind),
              label,
              OrgTime.time(item.startsAt!, language),
            )
          : null,
      excludeSemantics: item.isTimed,
      child: Material(
        color: fill,
        borderRadius: AppRadius.inputAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: item.isTimed ? () => showCalendarItem(context, item) : null,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(color: edge, width: 4),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (caption != null)
                    Text(
                      caption!,
                      style: text.labelSmall?.copyWith(color: colors.inkMuted),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (time.isNotEmpty) ...[
                        Text(
                          time,
                          style: text.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: text.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                decoration: cancelled
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: cancelled ? colors.inkMuted : null,
                              ),
                            ),
                            if (detail.isNotEmpty)
                              Text(
                                detail,
                                style: text.bodySmall?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (cancelled)
                        StatusPill(label: l10n.calendarCancelled)
                      else if (handedIn != null)
                        StatusPill(
                          label: handedIn
                              ? l10n.calendarHandedIn
                              : l10n.calendarNotHandedIn,
                          tone: handedIn
                              ? StatusTone.success
                              : StatusTone.warning,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The item's details in a sheet (the web's `ItemDrawer`): when, who, where,
/// and a link to its page when the app has it and it is in this workspace.
Future<void> showCalendarItem(BuildContext context, CalendarItem item) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ItemSheet(item: item),
    );

class _ItemSheet extends ConsumerWidget {
  const _ItemSheet({required this.item});

  final CalendarItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final here =
        item.workspace == null ||
        item.workspace!.key == calendarKeyOf(ref.watch(sessionProvider));
    final rows = <(String, String?)>[
      (
        l10n.calendarDetailsWhen,
        '${OrgTime.schoolDay(item.day, language)}, ${calendarTime(item, language)}',
      ),
      ...switch (item.kind) {
        CalendarKind.classItem => [
          (l10n.calendarDetailsSection, item.sectionName ?? item.title),
          (l10n.calendarDetailsTeacher, item.teacher),
          (l10n.calendarDetailsRoom, item.room),
        ],
        CalendarKind.event => [(l10n.calendarDetailsPlace, item.place)],
        CalendarKind.exam => [(l10n.calendarDetailsClass, item.className)],
        CalendarKind.homework => [
          (l10n.calendarDetailsSubject, item.subject),
          (l10n.calendarDetailsSections, item.sections.join(', ')),
        ],
        CalendarKind.holiday => <(String, String?)>[],
      },
      if (item.workspace != null)
        (l10n.calendarDetailsWorkspace, item.workspace!.label),
    ];
    final link = switch (item.kind) {
      CalendarKind.homework => (l10n.calendarOpenHomework, AppRoutes.homework),
      CalendarKind.classItem => (l10n.calendarOpenRoutine, AppRoutes.routine),
      _ => null,
    };
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              calendarKindName(l10n, item.kind),
              style: text.labelMedium?.copyWith(color: colors.inkMuted),
            ),
            Text(calendarLabel(l10n, item), style: text.titleLarge),
            if (item.isCancelled) ...[
              const SizedBox(height: AppSpacing.xs),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusPill(label: l10n.calendarCancelled),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            for (final (label, value) in rows)
              if (value != null && value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          label,
                          style: text.bodyMedium?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                      ),
                      Expanded(child: Text(value, style: text.bodyMedium)),
                    ],
                  ),
                ),
            if (!here)
              Text(
                l10n.calendarOtherWorkspace(item.workspace!.label),
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              )
            else if (link != null && AppRoutes.built.contains(link.$2))
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.go(link.$2);
                  },
                  child: Text(link.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
