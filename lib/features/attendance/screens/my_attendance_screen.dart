import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/cache/saved_notice.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/location/locator.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';
import 'package:instructor_app/features/attendance/widgets/attendance_mark.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// Today's classes are read again this often, so check-in opens and closes
/// without a reload (as the web).
const _refresh = Duration(minutes: 1);

/// A problem shown under a class, and whether "Open settings" helps.
typedef _Problem = ({String text, LocationProblem? settings});

/// The web's "My attendance" (ATT-18, ATT-04): today's classes with "Check
/// in" while a class is open (in-person classes send one fresh location; the
/// server decides everything), then the month of the person's own classes
/// with counts and the attendance rate.
class MyAttendanceScreen extends ConsumerStatefulWidget {
  const MyAttendanceScreen({super.key});

  @override
  ConsumerState<MyAttendanceScreen> createState() => _MyAttendanceScreenState();
}

class _MyAttendanceScreenState extends ConsumerState<MyAttendanceScreen> {
  Timer? _timer;
  String? _month;
  String? _busySlot;
  final _problems = <String, _Problem>{};

  /// Classes saved by a check-in, shown until today's list is read again.
  final _saved = <String, MyClass>{};

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(_refresh, (_) => ref.invalidate(myTodayProvider));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String? _knownError(AppLocalizations l10n, ApiException e, String language) {
    final d = e.details is Map ? e.details! as Map : const <String, Object?>{};
    num n(String k) => (d[k] as num?) ?? 0;
    final opens = d['opens_at'] is String
        ? DateTime.tryParse(d['opens_at'] as String)
        : null;
    return switch (e.code) {
      'ATTENDANCE_CHECKIN_NOT_OPEN' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINNOTOPEN(
          opens == null ? '' : OrgTime.time(opens, language),
        ),
      'ATTENDANCE_CHECKIN_CLOSED' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINCLOSED,
      'ATTENDANCE_CHECKIN_ALREADY' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINALREADY,
      'ATTENDANCE_CHECKIN_NO_PIN' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINNOPIN,
      // The web's sentence is about the browser; the app has its own.
      'ATTENDANCE_CHECKIN_LOCATION_REQUIRED' => l10n.appLocationDenied,
      'ATTENDANCE_CHECKIN_ACCURACY_POOR' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINACCURACYPOOR(
          n('accuracy_m').round(),
        ),
      'ATTENDANCE_CHECKIN_TOO_FAR' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINTOOFAR(
          n('distance_m').round(),
          n('radius_m').round(),
        ),
      'ATTENDANCE_CHECKIN_CLOSED_DAY' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINCLOSEDDAY,
      'ATTENDANCE_CHECKIN_PAPER_REGISTER' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINPAPERREGISTER,
      'ATTENDANCE_CHECKIN_NO_CLASS_TODAY' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINNOCLASSTODAY,
      'ATTENDANCE_CHECKIN_NOT_YOUR_CLASS' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINNOTYOURCLASS,
      'ATTENDANCE_CHECKIN_CANCELLED' =>
        l10n.myAttendanceErrorsATTENDANCECHECKINCANCELLED,
      _ => null,
    };
  }

  Future<void> _checkIn(MyClass item) async {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busySlot = item.slotId;
      _problems.remove(item.slotId);
    });
    try {
      LocationFix? fix;
      if (item.needsLocation) {
        try {
          fix = await ref.read(locatorProvider).currentFix();
        } on LocationException catch (e) {
          final text = switch (e.problem) {
            LocationProblem.serviceOff => l10n.appLocationServiceOff,
            LocationProblem.denied => l10n.appLocationDenied,
            LocationProblem.deniedForever => l10n.appLocationDeniedForever,
            LocationProblem.unavailable => l10n.myAttendanceLocationUnavailable,
          };
          final settings =
              e.problem == LocationProblem.serviceOff ||
                  e.problem == LocationProblem.deniedForever
              ? e.problem
              : null;
          if (mounted) {
            setState(
              () => _problems[item.slotId] = (text: text, settings: settings),
            );
          }
          return;
        }
      }
      final saved = await ref
          .read(myAttendanceRepositoryProvider)
          .checkIn(item.slotId, at: fix);
      if (!mounted) return;
      if (saved != null) {
        setState(() => _saved[saved.slotId] = saved);
        final late = saved.record?.status == 'LATE';
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              late
                  ? l10n.myAttendanceCheckedInLate(
                      saved.record?.lateMinutes ?? 0,
                    )
                  : l10n.myAttendanceCheckedIn,
            ),
          ),
        );
      }
      ref.invalidate(myCalendarProvider(_month));
    } on ApiException catch (e) {
      if (!mounted) return;
      final known = _knownError(l10n, e, language);
      if (known != null) {
        setState(() => _problems[item.slotId] = (text: known, settings: null));
        if (e.code == 'ATTENDANCE_CHECKIN_ALREADY' ||
            e.code == 'ATTENDANCE_CHECKIN_CLOSED') {
          ref.invalidate(myTodayProvider);
        }
      } else if (!await handleCommonApiError(
        context,
        e,
        session: ref.read(sessionProvider),
      )) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busySlot = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    ref.listen(myTodayProvider, (_, next) {
      // A fresh list replaces what check-ins saved.
      if (next.hasValue) _saved.clear();
    });
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(myTodayProvider)
              ..invalidate(myCalendarProvider(_month));
            await ref
                .read(myTodayProvider.future)
                .then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.myAttendanceTitle, style: text.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.myAttendanceIntro,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: () => context.go(AppRoutes.leave),
                  child: Text(l10n.myAttendanceLeaveLink),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _todayCard(),
              const SizedBox(height: AppSpacing.lg),
              _monthCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _todayCard() {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final today = ref.watch(myTodayProvider);
    final value = today.value;
    final title = value == null || value.date.isEmpty
        ? l10n.myAttendanceTodayTitleShort
        : l10n.myAttendanceTodayTitle(
            DateFormat.MMMMEEEEd(OrgTime.intlLocale(language))
                .format(DateTime.parse('${value.date}T00:00:00Z')),
          );
    return AppCard(
      key: const Key('attendance-today'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.titleMedium),
          if (value?.savedAt != null) ...[
            const SizedBox(height: AppSpacing.sm),
            SavedNotice(savedAt: value!.savedAt!),
          ],
          if (value?.onLeave == true || value?.closed != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              value!.onLeave
                  ? l10n.myAttendanceOnLeaveToday
                  : value.closed!.reason == 'WEEKLY_OFF'
                  ? l10n.myAttendanceClosedWEEKLYOFF
                  : l10n.myAttendanceClosedHOLIDAY(
                      value.closed!.holidayName ?? '',
                    ),
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (today.hasError && value == null)
            SizedBox(
              height: 260,
              child: ErrorView(
                title: l10n.myAttendanceLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(myTodayProvider),
              ),
            )
          else if (value == null)
            SizedBox(
              height: 120,
              child: LoadingView(semanticsLabel: l10n.myAttendanceTitle),
            )
          else if (value.classes.isEmpty)
            EmptyView(
              icon: Icons.event_available_outlined,
              title: l10n.myAttendanceNoClassesToday,
              message: l10n.myAttendanceNoClassesTodayHint,
            )
          else
            for (final (i, raw) in value.classes.indexed) ...[
              if (i > 0) const Divider(height: AppSpacing.xl),
              _classRow(
                _saved[raw.slotId] ?? raw,
                // No check-in from a saved copy (no offline check-in, §6a).
                offline: value.savedAt != null,
              ),
            ],
        ],
      ),
    );
  }

  Widget _classRow(MyClass item, {bool offline = false}) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final status = item.status;
    final statusText = switch (status) {
      'LATE' => l10n.myAttendanceLateBy(item.record?.lateMinutes ?? 0),
      'UPCOMING' when item.opensAt != null => l10n.myAttendanceOpensAt(
        OrgTime.time(item.opensAt!, language),
      ),
      'OPEN' when item.endsAt != null => l10n.myAttendanceOpenUntil(
        OrgTime.time(item.endsAt!, language),
      ),
      _ => attendanceStatusName(l10n, status),
    };
    final problem = _problems[item.slotId];
    final busy = _busySlot == item.slotId;
    final blocked = switch (item.blocked) {
      'PAPER_REGISTER' => l10n.myAttendanceBlockedPAPERREGISTER,
      'NO_PIN' => l10n.myAttendanceBlockedNOPIN,
      'CANCELLED' => l10n.myAttendanceBlockedCANCELLED,
      _ => null,
    };
    final flag = switch (item.record?.flag) {
      'EDGE_ACCURACY' => l10n.myAttendanceFlagEDGEACCURACY,
      'IMPOSSIBLE_JUMP' => l10n.myAttendanceFlagIMPOSSIBLEJUMP,
      _ => null,
    };
    return Column(
      key: Key('class-${item.slotId}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              item.label,
              style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (item.role == 'TEACHER')
              StatusPill(
                label: l10n.myAttendanceYouTeach,
                tone: StatusTone.primary,
              ),
          ],
        ),
        Text(
          '${OrgTime.timeOfDay(item.startTime, language)}–'
          '${OrgTime.timeOfDay(item.endTime, language)} · '
          '${item.classType == 'ONLINE' ? l10n.myAttendanceClassTypeONLINE : l10n.myAttendanceClassTypeINPERSON}',
          style: text.bodyMedium?.copyWith(color: colors.inkMuted),
        ),
        if (blocked != null)
          Text(
            blocked,
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
        if (flag != null)
          Text(flag, style: text.bodySmall?.copyWith(color: colors.warning)),
        if (problem != null)
          Semantics(
            liveRegion: true,
            child: Text(
              problem.text,
              style: text.bodyMedium?.copyWith(color: colors.danger),
            ),
          ),
        if (problem?.settings != null)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () =>
                  ref.read(locatorProvider).openSettings(problem!.settings!),
              child: Text(l10n.appLocationOpenSettings),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              label: attendanceStatusName(l10n, status),
              excludeSemantics: true,
              child: StatusPill(
                label: '${attendanceLetter(l10n, status)} $statusText',
                tone: attendanceTone(status),
              ),
            ),
            if (item.canCheckIn && !offline)
              Semantics(
                label: l10n.myAttendanceCheckInTo(item.label),
                button: true,
                excludeSemantics: true,
                child: AppButton(
                  label: busy
                      ? (item.needsLocation
                            ? l10n.myAttendanceLocating
                            : l10n.myAttendanceCheckingIn)
                      : l10n.myAttendanceCheckIn,
                  loading: busy,
                  onPressed: _busySlot == null ? () => _checkIn(item) : null,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _monthCard() {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final calendar = ref.watch(myCalendarProvider(_month));
    final value = calendar.value;
    final shown = value?.month ?? _month;
    return AppCard(
      key: const Key('attendance-month'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.myAttendanceMonthTitle,
                  style: text.titleMedium,
                ),
              ),
              if (shown != null && shown.isNotEmpty) ...[
                IconButton(
                  tooltip: l10n.myAttendancePreviousMonth,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () =>
                      setState(() => _month = shiftMonth(shown, -1)),
                ),
                Text(
                  DateFormat.yMMMM(OrgTime.intlLocale(language))
                      .format(DateTime.parse('$shown-01T00:00:00Z')),
                  style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                IconButton(
                  tooltip: l10n.myAttendanceNextMonth,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () =>
                      setState(() => _month = shiftMonth(shown, 1)),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          if (calendar.hasError && value == null)
            SizedBox(
              height: 260,
              child: ErrorView(
                title: l10n.myAttendanceLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(myCalendarProvider(_month)),
              ),
            )
          else if (value == null)
            SizedBox(
              height: 200,
              child: LoadingView(semanticsLabel: l10n.myAttendanceMonthTitle),
            )
          else ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _Stat(
                  l10n.myAttendanceAttendancePct,
                  value.attendancePct == null
                      ? '—'
                      : '${OrgTime.number(value.attendancePct!, language)}%',
                ),
                _Stat(
                  l10n.myAttendanceStatusPRESENT,
                  OrgTime.number(value.present, language),
                ),
                _Stat(
                  l10n.myAttendanceStatusLATE,
                  OrgTime.number(value.late, language),
                ),
                _Stat(
                  l10n.myAttendanceStatusABSENT,
                  OrgTime.number(value.absent, language),
                ),
                _Stat(
                  l10n.myAttendanceStatusLEAVE,
                  OrgTime.number(value.leave, language),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _MonthGrid(
              calendar: value,
              letter: (s) => attendanceLetter(l10n, s),
              statusName: (s) => attendanceStatusName(l10n, s),
            ),
            const SizedBox(height: AppSpacing.md),
            Semantics(
              label: l10n.myAttendanceLegend,
              child: Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final s in const [
                    'UPCOMING',
                    'PRESENT',
                    'LATE',
                    'ABSENT',
                    'LEAVE',
                    'CLOSED_DAY',
                    'CANCELLED',
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AttendanceMark(
                          status: s,
                          letter: attendanceLetter(l10n, s),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          attendanceStatusName(l10n, s),
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                ],
              ),
            ),
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

/// A month, Saturday first (the school week), one mark per class; closed
/// days greyed; today outlined (the web's `AttendanceCalendar`).
class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.calendar,
    required this.letter,
    required this.statusName,
  });

  final MyCalendar calendar;
  final String Function(String) letter;
  final String Function(String) statusName;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final locale = OrgTime.intlLocale(language);
    final c = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final first = calendar.days.isEmpty
        ? DateTime.parse('${calendar.month}-01T00:00:00Z')
        : DateTime.parse('${calendar.days.first.date}T00:00:00Z');
    // Saturday first: Sat=0 … Fri=6.
    final lead = (first.weekday + 1) % 7;
    final cells = <Widget>[
      for (var i = 0; i < 7; i++)
        Center(
          child: Text(
            // 14 Nov 2026 is a Saturday.
            DateFormat.E(locale).format(DateTime.utc(2026, 11, 14 + i)),
            style: text.labelSmall?.copyWith(color: c.inkMuted),
          ),
        ),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (final day in calendar.days)
        Semantics(
          label: [
            OrgTime.schoolDay(day.date, language),
            for (final m in day.marks)
              l10n.myAttendanceMarkLabel(
                m.label,
                OrgTime.timeOfDay(m.startTime, language),
                statusName(m.status),
              ),
          ].join('. '),
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: day.closed != null && day.marks.isEmpty
                  ? c.canvas
                  : c.surface,
              borderRadius: AppRadius.inputAll,
              border: Border.all(
                color: day.date == calendar.today ? c.primary : c.border,
                width: day.date == calendar.today ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Text(
                  OrgTime.number(int.parse(day.date.substring(8)), language),
                  style: text.labelSmall?.copyWith(
                    color: day.date == calendar.today
                        ? c.primary
                        : day.closed != null
                        ? c.inkMuted
                        : c.ink,
                    fontWeight: day.date == calendar.today
                        ? FontWeight.w700
                        : null,
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 1,
                  runSpacing: 1,
                  children: [
                    for (final m in day.marks)
                      AttendanceMark(
                        status: m.status,
                        letter: letter(m.status),
                        size: 16,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ];
    return Semantics(
      label: l10n.myAttendanceCalendarLabel(
        DateFormat.yMMMM(locale).format(first),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final width = (box.maxWidth - 6 * 4) / 7;
          return Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final cell in cells)
                SizedBox(
                  width: width,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: cell,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
