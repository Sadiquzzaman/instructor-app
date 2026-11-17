import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';
import 'package:instructor_app/features/calendar/widgets/calendar_item_tile.dart';

/// How far ahead "Due this week" and "Coming up" look, and how many come up.
const _aheadDays = 7;
const _comingUp = 5;

/// Where everyone starts the day (the web's `/today`, every role, every
/// workspace at once): today's classes, events, exams and homework from the
/// personal calendar, a note when check-in is open, homework due this week,
/// and what comes up next. Anything opens its details.
class TodayScreen extends ConsumerStatefulWidget {
  const TodayScreen({super.key});

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  late DateTime _now = DateTime.now();
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() => _now = DateTime.now()),
    );
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final today = OrgTime.today(_now);
    final range = (from: today, to: addDays(today, _aheadDays));
    final feed = ref.watch(calendarFeedProvider(range));
    final session = ref.watch(sessionProvider);
    final manager =
        session?.isOrganization == true &&
        const {'OWNER', 'ADMIN', 'ASSISTANT'}.contains(session!.memberRole);

    Future<void> reload() async {
      ref.invalidate(calendarFeedProvider(range));
      await ref
          .read(calendarFeedProvider(range).future)
          .catchError((Object _) => const CalendarFeed(items: []));
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                l10n.todayTitle,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                DateFormat.yMMMMEEEEd(OrgTime.intlLocale(language))
                    .format(DateTime.parse('${today}T00:00:00Z')),
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: AppColors.of(context).inkMuted),
              ),
              const SizedBox(height: AppSpacing.lg),
              ...feed.when(
                loading: () => [
                  SizedBox(
                    height: 240,
                    child: LoadingView(semanticsLabel: l10n.todayTitle),
                  ),
                ],
                error: (_, _) => [
                  SizedBox(
                    height: 320,
                    child: ErrorView(
                      title: l10n.todayLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () =>
                          ref.invalidate(calendarFeedProvider(range)),
                    ),
                  ),
                ],
                data: (feed) => _content(feed, today, manager: manager),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    CalendarFeed feed,
    String today, {
    required bool manager,
  }) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final showWorkspace = (feed.workspaces?.length ?? 0) > 1;
    // Weekly days off are left out; holidays are named.
    final items = feed.items
        .where((i) => i.kind != CalendarKind.holiday || i.reason == 'HOLIDAY')
        .toList();
    final todays = items.where((i) => i.day == today).toList();
    final checkInOpen = todays
        .where((i) => i.kind == CalendarKind.classItem && i.status == 'OPEN')
        .toList();
    final due = items
        .where(
          (i) =>
              i.kind == CalendarKind.homework &&
              i.handedIn != true &&
              !i.startsAt!.isBefore(_now),
        )
        .toList();
    final comingUp = items
        .where(
          (i) =>
              (i.kind == CalendarKind.event || i.kind == CalendarKind.exam) &&
              i.day.compareTo(today) > 0 &&
              !(i.kind == CalendarKind.event && i.cancelled),
        )
        .take(_comingUp)
        .toList();
    String dayOf(CalendarItem i) =>
        DateFormat.MMMEd(OrgTime.intlLocale(language))
            .format(DateTime.parse('${i.day}T00:00:00Z'));

    Widget list(List<CalendarItem> items, {bool withDay = false}) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (n, i) in items.indexed) ...[
          if (n > 0) const SizedBox(height: AppSpacing.sm),
          CalendarItemTile(
            item: i,
            showWorkspace: showWorkspace,
            caption: withDay ? dayOf(i) : null,
          ),
        ],
      ],
    );

    final muted = Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: AppColors.of(context).inkMuted);
    return [
      if (checkInOpen.isNotEmpty) ...[
        AppCard(
          key: const Key('check-in-open'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.todayCheckInOpen(
                  checkInOpen.map((i) => calendarLabel(l10n, i)).join(', '),
                ),
                style: Theme.of(context).textTheme.bodyLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: AppButton(
                  label: l10n.todayCheckIn,
                  onPressed: () => context.go(AppRoutes.myAttendance),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
      _Section(
        title: l10n.todaySchedule,
        child: feed.workspaces?.isEmpty == true
            ? EmptyView(
                icon: Icons.event_busy_outlined,
                title: l10n.todayNoCalendar,
                message: l10n.todayNoCalendarHint,
              )
            : todays.isEmpty
            ? Text(l10n.calendarNothingThisDay, style: muted)
            : list(todays),
      ),
      const SizedBox(height: AppSpacing.lg),
      _Section(
        title: l10n.todayDueTitle,
        child: due.isEmpty
            ? Text(l10n.todayNothingDue, style: muted)
            : list(due, withDay: true),
      ),
      const SizedBox(height: AppSpacing.lg),
      _Section(
        title: l10n.todayComingUpTitle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (comingUp.isEmpty)
              Text(l10n.todayNothingComingUp, style: muted)
            else
              list(comingUp, withDay: true),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => context.go(AppRoutes.calendar),
                child: Text(l10n.todayOpenCalendar),
              ),
            ),
          ],
        ),
      ),
      if (manager) ...[
        const SizedBox(height: AppSpacing.lg),
        _Section(
          title: l10n.todaySchoolTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.todaySchoolIntro, style: muted),
              TextButton(
                onPressed: () => context.go(AppRoutes.organization),
                child: Text(l10n.todayOpenOverview),
              ),
            ],
          ),
        ),
      ],
    ];
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    ),
  );
}
