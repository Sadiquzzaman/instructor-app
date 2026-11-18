import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/attendance/data/class_attendance.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';
import 'package:instructor_app/features/attendance/widgets/attendance_mark.dart';
import 'package:instructor_app/features/calendar/data/calendar_feed.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// Classes can be cancelled this many days ahead (the API's limit, ATT-19),
/// so the date picker reaches that far.
const _aheadDays = 60;

/// How far back the date picker goes (a teacher's corrections are limited
/// by the server; the list is still worth reading).
const _backDays = 365;

DateTime _day(String s) => DateTime.parse('${s}T00:00:00Z');

/// A refusal the screens explain in the web's words; null for anything else.
String? classAttendanceErrorText(AppLocalizations l10n, Object e) {
  if (e is! ApiException) return null;
  return switch (e.code) {
    'ATTENDANCE_CORRECTION_NOT_STARTED' =>
      l10n.classAttendanceErrorsATTENDANCECORRECTIONNOTSTARTED,
    'ATTENDANCE_CORRECTION_CLOSED_DAY' =>
      l10n.classAttendanceErrorsATTENDANCECORRECTIONCLOSEDDAY,
    'ATTENDANCE_CORRECTION_PERSON_NOT_FOUND' =>
      l10n.classAttendanceErrorsATTENDANCECORRECTIONPERSONNOTFOUND,
    'ATTENDANCE_CORRECTION_TEACHER_RECORD' =>
      l10n.classAttendanceErrorsATTENDANCECORRECTIONTEACHERRECORD,
    'ATTENDANCE_CORRECTION_NO_CHANGE' =>
      l10n.classAttendanceErrorsATTENDANCECORRECTIONNOCHANGE,
    'ATTENDANCE_CORRECTION_CANCELLED' =>
      l10n.classAttendanceErrorsATTENDANCECORRECTIONCANCELLED,
    'ATTENDANCE_CORRECTION_TOO_OLD' =>
      l10n.classAttendanceErrorsATTENDANCECORRECTIONTOOOLD,
    'ATTENDANCE_CANCEL_CLOSED_DAY' =>
      l10n.classAttendanceErrorsATTENDANCECANCELCLOSEDDAY,
    'ATTENDANCE_CANCEL_PAST' => l10n.classAttendanceErrorsATTENDANCECANCELPAST,
    'ATTENDANCE_CANCEL_TOO_FAR' =>
      l10n.classAttendanceErrorsATTENDANCECANCELTOOFAR,
    'ATTENDANCE_CANCEL_ENDED' =>
      l10n.classAttendanceErrorsATTENDANCECANCELENDED,
    'ATTENDANCE_CANCEL_ALREADY' =>
      l10n.classAttendanceErrorsATTENDANCECANCELALREADY,
    'ATTENDANCE_CANCEL_NOT_CANCELLED' =>
      l10n.classAttendanceErrorsATTENDANCECANCELNOTCANCELLED,
    _ => null,
  };
}

String _closedText(AppLocalizations l10n, ClosedDay c) => c.reason == 'HOLIDAY'
    ? l10n.classAttendanceClosedHOLIDAY(c.holidayName ?? '')
    : l10n.classAttendanceClosedWEEKLYOFF;

/// Class attendance for staff (the web's `/attendance`): the classes of a
/// day with how many students are present, late, absent or not in yet, and
/// flagged check-ins. A class opens its list, to correct a status with a
/// reason or to cancel or restore it for the day. No roll call: students
/// check themselves in.
class ClassAttendanceScreen extends ConsumerStatefulWidget {
  const ClassAttendanceScreen({super.key});

  @override
  ConsumerState<ClassAttendanceScreen> createState() =>
      _ClassAttendanceScreenState();
}

class _ClassAttendanceScreenState extends ConsumerState<ClassAttendanceScreen> {
  /// The chosen date; null shows today as the server says.
  String? _date;

  Future<void> _pick(SessionsOnDate? day) async {
    final today = day?.today.isNotEmpty == true ? day!.today : OrgTime.today();
    final current = _date ?? day?.date ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: _day(current),
      firstDate: _day(addDays(today, -_backDays)),
      lastDate: _day(addDays(today, _aheadDays)),
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
    final day = ref.watch(classSessionsProvider(_date));
    final shown = day.value;

    Future<void> reload() async {
      ref.invalidate(classSessionsProvider(_date));
      await ref
          .read(classSessionsProvider(_date).future)
          .catchError(
            (Object _) =>
                const SessionsOnDate(date: '', today: '', sessions: []),
          );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.classAttendanceTitle, style: text.headlineSmall),
              Text(
                l10n.classAttendanceIntro,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const Key('attendance-date'),
                  onPressed: () => _pick(shown),
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    '${l10n.classAttendanceDate}: '
                    '${shown == null || shown.date.isEmpty ? (_date ?? '') : OrgTime.schoolDay(shown.date, language)}',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              ...day.when(
                skipLoadingOnReload: true,
                loading: () => [
                  SizedBox(
                    height: 240,
                    child: LoadingView(
                      semanticsLabel: l10n.classAttendanceTitle,
                    ),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 320,
                    child: e is ApiException && e.isFeatureLocked
                        ? EmptyView(
                            icon: Icons.lock_outline,
                            title: l10n.featuresLockedTitle,
                          )
                        : ErrorView(
                            title: l10n.classAttendanceLoadFailed,
                            retryLabel: l10n.uiErrorRetry,
                            onRetry: () =>
                                ref.invalidate(classSessionsProvider(_date)),
                          ),
                  ),
                ],
                data: (d) => _list(d),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _list(SessionsOnDate d) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return [
      if (d.date.isNotEmpty)
        Text(
          l10n.classAttendanceClassesOn(
            DateFormat.MMMMEEEEd(OrgTime.intlLocale(language))
                .format(_day(d.date)),
          ),
          style: text.titleMedium,
        ),
      if (d.closed != null)
        Text(
          _closedText(l10n, d.closed!),
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
      const SizedBox(height: AppSpacing.sm),
      if (d.sessions.isEmpty)
        SizedBox(
          height: 260,
          child: EmptyView(
            icon: Icons.event_busy_outlined,
            title: l10n.classAttendanceEmpty,
            message: l10n.classAttendanceEmptyHint,
          ),
        )
      else
        for (final s in d.sessions) ...[
          _SessionCard(
            s,
            onOpen: () async {
              await context.push(
                '${AppRoutes.attendance}/${s.slotId}/${s.date}',
              );
              // Corrections and cancellations change the counts.
              if (mounted) ref.invalidate(classSessionsProvider(_date));
            },
          ),
          const SizedBox(height: AppSpacing.md),
        ],
    ];
  }
}

/// A class's state: closed day, cancelled, paper register, or check-in's.
Widget _statePill(AppLocalizations l10n, ClassSession s) {
  if (s.closed != null) return StatusPill(label: l10n.classAttendanceClosedDay);
  if (s.cancelled != null) {
    return StatusPill(label: l10n.classAttendanceCancelled);
  }
  if (s.mode == 'PAPER_REGISTER') {
    return StatusPill(label: l10n.classAttendancePaperRegister);
  }
  return switch (s.state) {
    'OPEN' => StatusPill(
      label: l10n.classAttendanceStateOPEN,
      tone: StatusTone.primary,
    ),
    'CLOSED' => StatusPill(label: l10n.classAttendanceStateCLOSED),
    _ => StatusPill(label: l10n.classAttendanceStateUPCOMING),
  };
}

String _times(BuildContext context, ClassSession s) {
  final language = Localizations.localeOf(context).languageCode;
  return context.l10n.classAttendanceTimeRange(
    OrgTime.timeOfDay(s.startTime, language),
    OrgTime.timeOfDay(s.endTime, language),
  );
}

class _SessionCard extends StatelessWidget {
  const _SessionCard(this.s, {required this.onOpen});

  final ClassSession s;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final c = s.counts;
    return AppCard(
      key: Key('session-${s.slotId}'),
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(s.label, style: text.titleMedium),
              if (s.change != null)
                StatusPill(
                  label: l10n.classAttendanceChanged,
                  tone: StatusTone.warning,
                ),
            ],
          ),
          Text(
            [_times(context, s), ?s.teacher?.name].join(' · '),
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _statePill(l10n, s),
              StatusPill(
                label: l10n.classAttendanceCountPresent(c.present),
                tone: StatusTone.success,
              ),
              StatusPill(
                label: l10n.classAttendanceCountLate(c.late),
                tone: StatusTone.warning,
              ),
              StatusPill(
                label: l10n.classAttendanceCountAbsent(c.absent),
                tone: StatusTone.danger,
              ),
              if (c.leave > 0)
                StatusPill(
                  label: l10n.classAttendanceCountLeave(c.leave),
                  tone: StatusTone.info,
                ),
              if (c.waiting > 0)
                StatusPill(label: l10n.classAttendanceCountWaiting(c.waiting)),
              if (c.flagged > 0)
                StatusPill(
                  label: l10n.classAttendanceCountFlagged(c.flagged),
                  tone: StatusTone.warning,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: onOpen,
              child: Text(
                s.canCorrect
                    ? l10n.classAttendanceViewAndCorrect
                    : l10n.classAttendanceView,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One class on a date (the web's drawer): everyone's status with check-in
/// time, minutes late, distance and flag, and the corrections so far; a
/// correction takes the new status and a reason. The class can be cancelled
/// for the day with a note, and restored, or given other times or a
/// substitute teacher for the day.
class ClassSessionScreen extends ConsumerStatefulWidget {
  const ClassSessionScreen({
    required this.slotId,
    required this.date,
    super.key,
  });

  final String slotId;
  final String date;

  @override
  ConsumerState<ClassSessionScreen> createState() => _ClassSessionScreenState();
}

class _ClassSessionScreenState extends ConsumerState<ClassSessionScreen> {
  late final _key = (slotId: widget.slotId, date: widget.date);

  /// The class as the last change returned it (fresher than the load).
  ClassSessionDetail? _latest;
  bool _cancelForm = false;
  bool _busy = false;
  String? _cancelProblem;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _cancelOrRestore({required bool cancel}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(classAttendanceRepositoryProvider);
    setState(() {
      _busy = true;
      _cancelProblem = null;
    });
    try {
      final d = cancel
          ? await repo.cancel(
              widget.slotId,
              widget.date,
              note: _note.text.trim(),
            )
          : await repo.restore(widget.slotId, widget.date);
      if (!mounted) return;
      setState(() {
        _latest = d;
        _cancelForm = false;
        _note.clear();
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            cancel
                ? l10n.classAttendanceCancelledToast(d.session.label)
                : l10n.classAttendanceRestoredToast(d.session.label),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final known = classAttendanceErrorText(l10n, e);
      if (known != null) {
        setState(() => _cancelProblem = known);
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        setState(() => _cancelProblem = apiErrorText(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _correct(RosterRow row) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final d = await showDialog<ClassSessionDetail>(
      context: context,
      builder: (_) =>
          _CorrectionDialog(slotId: widget.slotId, date: widget.date, row: row),
    );
    if (d == null || !mounted) return;
    setState(() => _latest = d);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.classAttendanceCorrected(row.name))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = ref.watch(classSessionProvider(_key));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _latest != null
            ? _body(_latest!)
            : loaded.when(
                loading: () =>
                    LoadingView(semanticsLabel: l10n.classAttendanceTitle),
                error: (e, _) => ErrorView(
                  title: l10n.classAttendanceLoadFailed,
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () => ref.invalidate(classSessionProvider(_key)),
                ),
                data: _body,
              ),
      ),
    );
  }

  Widget _body(ClassSessionDetail d) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final s = d.session;
    final classType = s.classType == 'ONLINE'
        ? l10n.myAttendanceClassTypeONLINE
        : l10n.myAttendanceClassTypeINPERSON;
    final now = DateTime.now();
    final hint = s.canCorrect || s.closed != null || s.cancelled != null
        ? null
        : (s.state == 'UPCOMING' ||
                  (s.startsAt != null && now.isBefore(s.startsAt!))
              ? l10n.classAttendanceNotStartedHint
              : l10n.classAttendanceTooOldHint);
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _latest = null);
        ref.invalidate(classSessionProvider(_key));
        await ref
            .read(classSessionProvider(_key).future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(s.label, style: text.headlineSmall),
          Text(
            [
              OrgTime.schoolDay(s.date, language),
              _times(context, s),
              classType,
              if (s.closed != null) _closedText(l10n, s.closed!),
            ].join(' · '),
            style: text.bodyMedium?.copyWith(color: colors.inkMuted),
          ),
          if (s.cancelled == null && (s.change != null || s.canChange)) ...[
            const SizedBox(height: AppSpacing.md),
            _ChangeSection(
              s,
              onChanged: (d) {
                setState(() => _latest = d);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.classAttendanceChangedToast(d.session.label),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _cancellation(s),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(hint, style: text.bodySmall?.copyWith(color: colors.inkMuted)),
          ],
          const SizedBox(height: AppSpacing.lg),
          Text(
            l10n.classAttendanceStudentsCount(d.students.length),
            style: text.titleMedium,
          ),
          if (d.students.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                l10n.classAttendanceNoStudents,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
            )
          else
            for (final r in d.students) _PersonRow(r, onCorrect: _correct),
          if (d.teachers.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(l10n.classAttendanceTeachers, style: text.titleMedium),
            for (final r in d.teachers) _PersonRow(r, onCorrect: _correct),
          ],
        ],
      ),
    );
  }

  Widget _cancellation(ClassSession s) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final problem = _cancelProblem == null
        ? null
        : Text(
            _cancelProblem!,
            key: const Key('cancel-problem'),
            style: text.bodySmall?.copyWith(color: colors.danger),
          );
    final x = s.cancelled;
    if (x != null) {
      return AppCard(
        key: const Key('cancelled-banner'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AttendanceMark(
                  status: 'CANCELLED',
                  letter: attendanceLetter(l10n, 'CANCELLED'),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  attendanceStatusName(l10n, 'CANCELLED'),
                  style: text.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.classAttendanceCancelledHint,
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            if (x.at != null)
              Text(
                l10n.classAttendanceCancelledBanner(
                  x.by?.name ?? l10n.classAttendanceSomeone,
                  OrgTime.dateTime(x.at!, language),
                ),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
            if (x.note != null && x.note!.isNotEmpty)
              Text(
                l10n.classAttendanceCancelledBannerNote(x.note!),
                style: text.bodySmall,
              ),
            ?problem,
            if (s.canRestore)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: OutlinedButton(
                  key: const Key('restore-class'),
                  onPressed: _busy
                      ? null
                      : () => _cancelOrRestore(cancel: false),
                  child: Text(
                    _busy
                        ? l10n.classAttendanceRestoring
                        : l10n.classAttendanceRestoreClass,
                  ),
                ),
              ),
          ],
        ),
      );
    }
    if (!s.canCancel) return const SizedBox.shrink();
    if (!_cancelForm) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton(
          key: const Key('cancel-class'),
          onPressed: () => setState(() => _cancelForm = true),
          child: Text(l10n.classAttendanceCancelClass),
        ),
      );
    }
    return AppCard(
      key: const Key('cancel-form'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.classAttendanceCancelIntro,
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('cancel-note'),
            controller: _note,
            maxLength: 300,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: l10n.classAttendanceCancelNote,
              helperText: l10n.classAttendanceCancelNoteHint,
              helperMaxLines: 3,
            ),
          ),
          ?problem,
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: AppSpacing.sm,
            children: [
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _cancelForm = false;
                        _cancelProblem = null;
                      }),
                child: Text(l10n.classAttendanceKeepClass),
              ),
              FilledButton(
                key: const Key('confirm-cancel'),
                style: FilledButton.styleFrom(backgroundColor: colors.danger),
                onPressed: _busy ? null : () => _cancelOrRestore(cancel: true),
                child: Text(
                  _busy
                      ? l10n.classAttendanceCancelling
                      : l10n.classAttendanceConfirmCancel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A refusal of a day's change, in the web's words; null for anything else.
String? _changeErrorText(AppLocalizations l10n, Object e) {
  if (e is! ApiException) return null;
  final d = e.details is Map ? e.details! as Map : const <String, Object?>{};
  return switch (e.code) {
    'ATTENDANCE_CHANGE_STARTED' =>
      l10n.classAttendanceErrorsATTENDANCECHANGESTARTED,
    'ATTENDANCE_CHANGE_TIME_INVALID' =>
      l10n.classAttendanceErrorsATTENDANCECHANGETIMEINVALID,
    'ATTENDANCE_CHANGE_OVERLAP' =>
      l10n.classAttendanceErrorsATTENDANCECHANGEOVERLAP(
        (d['start_time'] as String?) ?? '',
        (d['end_time'] as String?) ?? '',
      ),
    'ATTENDANCE_CHANGE_TEACHER_INVALID' =>
      l10n.classAttendanceErrorsATTENDANCECHANGETEACHERINVALID,
    'ATTENDANCE_CHANGE_NONE' => l10n.classAttendanceErrorsATTENDANCECHANGENONE,
    _ => classAttendanceErrorText(l10n, e),
  };
}

/// "HH:MM" of an instant in the organisation's time zone.
String _hhmm(DateTime instant) =>
    DateFormat('HH:mm').format(OrgTime.wallClock(instant));

/// A one-day change of the class (the web's `ClassChangeSection`): a change
/// already made (routine and new times, the substitute, who and when, the
/// note) with Undo; before check-in opens, other times that day and/or a
/// substitute teacher, with a note for students. The routine stays as it is.
class _ChangeSection extends ConsumerStatefulWidget {
  const _ChangeSection(this.s, {required this.onChanged});

  final ClassSession s;
  final void Function(ClassSessionDetail) onChanged;

  @override
  ConsumerState<_ChangeSection> createState() => _ChangeSectionState();
}

class _ChangeSectionState extends ConsumerState<_ChangeSection> {
  bool _open = false;
  bool _busy = false;
  String? _problem;
  String _start = '';
  String _end = '';

  /// The substitute's id; null keeps the routine's teacher.
  String? _substitute;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  ClassSession get s => widget.s;

  void _startForm() {
    setState(() {
      _start = s.startsAt != null ? _hhmm(s.startsAt!) : s.startTime;
      _end = s.endsAt != null ? _hhmm(s.endsAt!) : s.endTime;
      _substitute = s.change?.substitute?.id;
      _note.text = s.change?.note ?? '';
      _problem = null;
      _open = true;
    });
  }

  Future<void> _pickTime({required bool start}) async {
    final current = start ? _start : _end;
    final parts = current.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.first) ?? 9,
        minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
      ),
    );
    if (picked == null || !mounted) return;
    final v =
        '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    setState(() => start ? _start = v : _end = v);
  }

  Future<void> _send({
    required String start,
    required String end,
    String? substitute,
    String note = '',
  }) async {
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final d = await ref
          .read(classAttendanceRepositoryProvider)
          .change(
            s.slotId,
            s.date,
            start: start,
            end: end,
            substituteId: substitute,
            note: note,
          );
      if (!mounted) return;
      setState(() => _open = false);
      widget.onChanged(d);
    } catch (e) {
      if (!mounted) return;
      final known = _changeErrorText(l10n, e);
      if (known != null) {
        setState(() => _problem = known);
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        setState(() => _problem = apiErrorText(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _save() {
    // "HH:MM" strings compare in time order.
    if (_start.isEmpty || _end.isEmpty || _end.compareTo(_start) <= 0) {
      setState(
        () => _problem =
            context.l10n.classAttendanceErrorsATTENDANCECHANGETIMEINVALID,
      );
      return;
    }
    _send(
      start: _start,
      end: _end,
      substitute: _substitute,
      note: _note.text.trim(),
    );
  }

  void _undo() {
    final c = s.change;
    if (c == null) return;
    _send(start: c.routineStart, end: c.routineEnd);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final c = s.change;
    String t(String v) => OrgTime.timeOfDay(v, language);
    // Who teaches when nobody substitutes.
    final routineTeacher = c == null
        ? s.teacher
        : (c.substitute == null ? s.teacher : null);
    final orgId = ref.watch(sessionProvider)?.isOrganization == true
        ? ref.watch(sessionProvider)?.organizationId
        : null;
    final teachers = _open && orgId != null
        ? ref.watch(assignableTeachersProvider(orgId)).value ?? const <Who>[]
        : const <Who>[];
    final choices = [
      for (final w in teachers)
        if (w.id != routineTeacher?.id) w,
    ];
    // A substitute chosen earlier stays a choice even if the list is late.
    if (_substitute != null && choices.every((w) => w.id != _substitute)) {
      final known = c?.substitute;
      if (known != null && known.id == _substitute) choices.add(known);
    }
    return AppCard(
      key: const Key('change-section'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (c != null) ...[
            Text(
              l10n.classAttendanceChangeChangedTitle,
              style: text.titleSmall,
            ),
            Text(
              '${l10n.classAttendanceChangeRoutineTimes(t(c.routineStart), t(c.routineEnd))}'
              ' → ${l10n.classAttendanceChangeDayTimes(t(s.startTime), t(s.endTime))}',
              style: text.bodySmall,
            ),
            if (c.substitute != null)
              Text(
                l10n.classAttendanceChangeSubstituteIs(c.substitute!.name),
                style: text.bodySmall,
              ),
            if (c.at != null)
              Text(
                l10n.classAttendanceChangeChangedBy(
                  c.by?.name ?? l10n.classAttendanceChangeSomeone,
                  OrgTime.dateTime(c.at!, language),
                ),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
            if (c.note != null && c.note!.isNotEmpty)
              Text(
                l10n.classAttendanceChangeNoteIs(c.note!),
                style: text.bodySmall,
              ),
          ] else
            Text(l10n.classAttendanceChangeTitle, style: text.titleSmall),
          if (_open) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.classAttendanceChangeIntro,
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(
                  key: const Key('change-start'),
                  onPressed: _busy ? null : () => _pickTime(start: true),
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    '${l10n.classAttendanceChangeStart}: ${t(_start)}',
                  ),
                ),
                OutlinedButton.icon(
                  key: const Key('change-end'),
                  onPressed: _busy ? null : () => _pickTime(start: false),
                  icon: const Icon(Icons.schedule),
                  label: Text('${l10n.classAttendanceChangeEnd}: ${t(_end)}'),
                ),
              ],
            ),
            if (orgId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: const Key('change-substitute'),
                initialValue: _substitute,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.classAttendanceChangeSubstitute,
                ),
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(
                      routineTeacher != null
                          ? l10n.classAttendanceChangeRoutineTeacher(
                              routineTeacher.name,
                            )
                          : l10n.classAttendanceChangeNoSubstitute,
                    ),
                  ),
                  for (final w in choices)
                    DropdownMenuItem<String?>(value: w.id, child: Text(w.name)),
                ],
                onChanged: _busy
                    ? null
                    : (v) => setState(() => _substitute = v),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('change-note'),
              controller: _note,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.classAttendanceChangeNote,
                helperText: l10n.classAttendanceChangeNoteHint,
                helperMaxLines: 3,
              ),
            ),
          ],
          if (_problem != null)
            Text(
              _problem!,
              key: const Key('change-problem'),
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
          if (s.canChange) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.sm,
              children: _open
                  ? [
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _open = false;
                                _problem = null;
                              }),
                        child: Text(l10n.classAttendanceChangeClose),
                      ),
                      FilledButton(
                        key: const Key('change-save'),
                        onPressed: _busy ? null : _save,
                        child: Text(l10n.classAttendanceChangeSave),
                      ),
                    ]
                  : [
                      if (c != null)
                        TextButton(
                          key: const Key('change-undo'),
                          onPressed: _busy ? null : _undo,
                          child: Text(l10n.classAttendanceChangeUndo),
                        ),
                      OutlinedButton(
                        key: const Key('change-open'),
                        onPressed: _startForm,
                        child: Text(
                          c != null
                              ? l10n.classAttendanceChangeEditChange
                              : l10n.classAttendanceChangeOpen,
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

/// One person: their mark, status, check-in and flag; the corrections so
/// far; and Correct when the server allows it.
class _PersonRow extends StatelessWidget {
  const _PersonRow(this.r, {required this.onCorrect});

  final RosterRow r;
  final void Function(RosterRow) onCorrect;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final roll = r.rollNo == null || r.rollNo!.isEmpty
        ? null
        : (int.tryParse(r.rollNo!) != null
              ? OrgTime.number(int.parse(r.rollNo!), language)
              : r.rollNo);
    final status = r.status == 'LATE' && r.lateMinutes != null
        ? l10n.myAttendanceLateBy(r.lateMinutes!)
        : attendanceStatusName(l10n, r.status);
    final details = [
      status,
      if (r.checkedInAt != null)
        l10n.classAttendanceCheckedInAt(OrgTime.time(r.checkedInAt!, language)),
      if (r.distanceM != null)
        l10n.classAttendanceDistance(r.distanceM!, r.accuracyM ?? 0),
    ].join(' · ');
    return Padding(
      key: Key('person-${r.id}'),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AttendanceMark(
                status: r.status,
                letter: attendanceLetter(l10n, r.status),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      roll == null ? r.name : '$roll. ${r.name}',
                      style: text.bodyLarge,
                    ),
                    Text(
                      details,
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                    if (r.flag != null)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: StatusPill(
                          label: r.flag == 'IMPOSSIBLE_JUMP'
                              ? l10n.classAttendanceFlagIMPOSSIBLEJUMP
                              : l10n.classAttendanceFlagEDGEACCURACY,
                          tone: StatusTone.warning,
                        ),
                      ),
                  ],
                ),
              ),
              if (r.canCorrect)
                TextButton(
                  key: Key('correct-${r.id}'),
                  onPressed: () => onCorrect(r),
                  child: Text(l10n.classAttendanceCorrect),
                ),
            ],
          ),
          if (r.corrections.isNotEmpty)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: AppSpacing.xxl,
                top: AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final c in r.corrections)
                    Text(
                      '${l10n.classAttendanceTrailLine(c.from == null ? l10n.classAttendanceNoRecord : attendanceStatusName(l10n, c.from!), attendanceStatusName(l10n, c.to), c.by?.name ?? l10n.classAttendanceSomeone, c.at == null ? '' : OrgTime.dateTime(c.at!, language))}'
                      ' — ${c.reason}',
                      key: Key('trail-${c.id}'),
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// The new status (Present, Late with minutes, Absent) and a reason of 3 or
/// more letters; returns the class as it is now.
class _CorrectionDialog extends ConsumerStatefulWidget {
  const _CorrectionDialog({
    required this.slotId,
    required this.date,
    required this.row,
  });

  final String slotId;
  final String date;
  final RosterRow row;

  @override
  ConsumerState<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends ConsumerState<_CorrectionDialog> {
  late String _status = widget.row.status == 'PRESENT' ? 'ABSENT' : 'PRESENT';
  late final _minutes = TextEditingController(
    text: widget.row.lateMinutes?.toString() ?? '',
  );
  final _reason = TextEditingController();
  bool _saving = false;
  String? _problem;

  @override
  void dispose() {
    _minutes.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() => _problem = l10n.classAttendanceReasonRequired);
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final d = await ref
          .read(classAttendanceRepositoryProvider)
          .correct(
            widget.slotId,
            widget.date,
            widget.row.id,
            status: _status,
            reason: reason,
            lateMinutes: int.tryParse(_minutes.text.trim()),
          );
      if (mounted) Navigator.of(context).pop(d);
    } catch (e) {
      if (!mounted) return;
      final known = classAttendanceErrorText(l10n, e);
      if (known != null) {
        setState(() => _problem = known);
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        setState(() => _problem = apiErrorText(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    return AlertDialog(
      title: Text(l10n.classAttendanceCorrectFor(widget.row.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              key: const Key('correction-status'),
              initialValue: _status,
              decoration: InputDecoration(
                labelText: l10n.classAttendanceNewStatus,
              ),
              items: [
                for (final s in const ['PRESENT', 'LATE', 'ABSENT'])
                  DropdownMenuItem(
                    value: s,
                    child: Text(attendanceStatusName(l10n, s)),
                  ),
              ],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
            if (_status == 'LATE') ...[
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('correction-minutes'),
                controller: _minutes,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.classAttendanceLateMinutes,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const Key('correction-reason'),
              controller: _reason,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.classAttendanceReason,
                helperText: l10n.classAttendanceReasonHint,
                helperMaxLines: 3,
              ),
            ),
            if (_problem != null)
              Text(
                _problem!,
                key: const Key('correction-problem'),
                style: TextStyle(color: colors.danger),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.classAttendanceCancel),
        ),
        FilledButton(
          key: const Key('correction-save'),
          onPressed: _saving ? null : _save,
          child: Text(
            _saving
                ? l10n.classAttendanceSaving
                : l10n.classAttendanceSaveCorrection,
          ),
        ),
      ],
    );
  }
}
