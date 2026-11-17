import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/cache/saved_notice.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/routine/data/routine.dart';

/// The school week, Saturday first (ISO days).
const _schoolWeek = [6, 7, 1, 2, 3, 4, 5];

/// The web's /routine, read only: a section's week, Saturday first, each
/// period with its time, subject, teacher and room; today's day marked.
/// Changing the routine stays on the web.
class RoutineScreen extends ConsumerStatefulWidget {
  const RoutineScreen({super.key});

  @override
  ConsumerState<RoutineScreen> createState() => _RoutineScreenState();
}

class _RoutineScreenState extends ConsumerState<RoutineScreen> {
  String? _section;

  String _day(AppLocalizations l10n, int day) => switch (day) {
    1 => l10n.routineDays1,
    2 => l10n.routineDays2,
    3 => l10n.routineDays3,
    4 => l10n.routineDays4,
    5 => l10n.routineDays5,
    6 => l10n.routineDays6,
    _ => l10n.routineDays7,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final routine = ref.watch(routineProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: routine.when(
          loading: () => LoadingView(semanticsLabel: l10n.routineTitle),
          error: (_, _) => ErrorView(
            title: l10n.routineLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(routineProvider),
          ),
          data: (routine) {
            if (routine.sections.isEmpty) {
              return EmptyView(
                icon: Icons.view_week_outlined,
                title: ref.levels(context, l10n.routineNoSections),
              );
            }
            final current = routine.sections.containsKey(_section)
                ? _section!
                : routine.sections.keys.first;
            final periods = routine.periods
                .where((p) => p.sectionId == current)
                .toList();
            // ISO day of today in the school's time zone.
            final today = OrgTime.wallClock(DateTime.now()).weekday;
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(routineProvider);
                await ref
                    .read(routineProvider.future)
                    .then<void>((_) {}, onError: (Object _) {});
              },
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(l10n.routineTitle, style: text.headlineSmall),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    ref.levels(
                      context,
                      ref.watch(sessionProvider)?.role == 'STUDENT'
                          ? l10n.routineStudentIntro
                          : l10n.routineStaffIntro,
                    ),
                    style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                  ),
                  if (routine.savedAt != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    SavedNotice(savedAt: routine.savedAt!),
                  ],
                  if (routine.sections.length > 1) ...[
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String>(
                      key: const Key('routine-section'),
                      initialValue: current,
                      decoration: InputDecoration(
                        labelText: ref.levels(context, l10n.routineSection),
                      ),
                      items: [
                        for (final MapEntry(:key, :value)
                            in routine.sections.entries)
                          DropdownMenuItem(value: key, child: Text(value)),
                      ],
                      onChanged: (v) => setState(() => _section = v),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  for (final day in _schoolWeek) ...[
                    _DayCard(
                      key: Key('routine-day-$day'),
                      title: _day(l10n, day),
                      today: day == today,
                      periods: [
                        for (final p in periods)
                          if (p.day == day) p,
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.title,
    required this.today,
    required this.periods,
    super.key,
  });

  final String title;
  final bool today;
  final List<RoutinePeriod> periods;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: text.titleSmall?.copyWith(
              color: today ? colors.primary : null,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (periods.isEmpty)
            Text(
              l10n.routineNoClasses,
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            )
          else
            for (final (i, p) in periods.indexed) ...[
              if (i > 0) const Divider(height: AppSpacing.lg),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 104,
                    child: Text(
                      '${OrgTime.timeOfDay(p.startTime, language)}–'
                      '${OrgTime.timeOfDay(p.endTime, language)}',
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (p.subject != null)
                          Text(p.subject!, style: text.bodyMedium),
                        Text(
                          [
                            p.teacher,
                            p.room,
                          ].where((s) => s != null && s.isNotEmpty).join(' · '),
                          style: text.bodySmall?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}
