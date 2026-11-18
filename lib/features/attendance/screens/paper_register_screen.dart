import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/attendance/data/attendance_reports.dart';
import 'package:instructor_app/features/attendance/data/my_attendance.dart';
import 'package:instructor_app/features/attendance/data/paper_register.dart';
import 'package:instructor_app/features/attendance/widgets/attendance_mark.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// The marks a cell cycles through when tapped; null is "no mark".
const _cycle = <String?>[null, 'PRESENT', 'LATE', 'ABSENT', 'LEAVE'];

/// A register problem in the web's words (`register.importer.issues`).
String _issueText(AppLocalizations l10n, RegisterProblem p) => switch (p.code) {
  'COLUMN_UNKNOWN' => l10n.registerImporterIssuesCOLUMNUNKNOWN,
  'COLUMN_NOT_IN_MONTH' => l10n.registerImporterIssuesCOLUMNNOTINMONTH,
  'NOT_CLASS_DAY' => l10n.registerImporterIssuesNOTCLASSDAY,
  'CLOSED_DAY' => l10n.registerImporterIssuesCLOSEDDAY,
  'CANCELLED' => l10n.registerImporterIssuesCANCELLED,
  'NOT_STARTED' => l10n.registerImporterIssuesNOTSTARTED,
  'TIME_NEEDED' => l10n.registerImporterIssuesTIMENEEDED,
  'NOT_CLASS_TIME' => l10n.registerImporterIssuesNOTCLASSTIME,
  'DUPLICATE_COLUMN' => l10n.registerImporterIssuesDUPLICATECOLUMN,
  'STUDENT_MISSING' => l10n.registerImporterIssuesSTUDENTMISSING,
  'STUDENT_NOT_FOUND' => l10n.registerImporterIssuesSTUDENTNOTFOUND,
  'STUDENT_AMBIGUOUS' => l10n.registerImporterIssuesSTUDENTAMBIGUOUS,
  'STUDENT_DUPLICATE' => l10n.registerImporterIssuesSTUDENTDUPLICATE,
  'STATUS_INVALID' => l10n.registerImporterIssuesSTATUSINVALID(p.value),
  'NOT_JOINED' => l10n.registerImporterIssuesNOTJOINED,
  'TOO_OLD' => l10n.registerImporterIssuesTOOOLD,
  _ => l10n.registerImporterHasErrors,
};

/// A register refusal in the web's words (`register.errors`); null otherwise.
String? _registerError(AppLocalizations l10n, Object e) {
  if (e is! ApiException) return null;
  return switch (e.code) {
    'ATTENDANCE_REGISTER_SECTION_NOT_FOUND' =>
      l10n.registerErrorsATTENDANCEREGISTERSECTIONNOTFOUND,
    'ATTENDANCE_REGISTER_MONTH_INVALID' =>
      l10n.registerErrorsATTENDANCEREGISTERMONTHINVALID,
    'ATTENDANCE_REGISTER_SELF_CHECKIN' =>
      l10n.registerErrorsATTENDANCEREGISTERSELFCHECKIN,
    'ATTENDANCE_REGISTER_SESSION_CLOSED' =>
      l10n.registerErrorsATTENDANCEREGISTERSESSIONCLOSED,
    'ATTENDANCE_REGISTER_INVALID' =>
      l10n.registerErrorsATTENDANCEREGISTERINVALID,
    'ATTENDANCE_REGISTER_CHANGED' =>
      l10n.registerErrorsATTENDANCEREGISTERCHANGED,
    _ => null,
  };
}

/// The monthly register (the web's `/attendance-register`), as a grid
/// instead of a CSV file (owner's decision, Stage 2 plan §7.3): a section's
/// month, a student per line and a class day per column. For a paper
/// register section, tapping a cell sets P, L, A, LV or nothing; Save checks
/// the marks with the server and saves them all or none, with any problem
/// shown on its line and column. Self check-in sections are read-only.
class PaperRegisterScreen extends ConsumerStatefulWidget {
  const PaperRegisterScreen({super.key});

  @override
  ConsumerState<PaperRegisterScreen> createState() =>
      _PaperRegisterScreenState();
}

class _PaperRegisterScreenState extends ConsumerState<PaperRegisterScreen> {
  String? _sectionId;
  String _month = OrgTime.today().substring(0, 7);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final sections = ref.watch(reportSectionsProvider);
    final monthName = DateFormat.yMMMM(OrgTime.intlLocale(language))
        .format(DateTime.parse('$_month-01T00:00:00Z'));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.registerTitle, style: text.headlineSmall),
            const SizedBox(height: AppSpacing.md),
            ...sections.when(
              loading: () => [
                SizedBox(
                  height: 240,
                  child: LoadingView(semanticsLabel: l10n.registerTitle),
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
                          title: l10n.registerLoadFailed,
                          retryLabel: l10n.uiErrorRetry,
                          onRetry: () => ref.invalidate(reportSectionsProvider),
                        ),
                ),
              ],
              data: (list) {
                if (list.isEmpty) {
                  return [
                    SizedBox(
                      height: 280,
                      child: EmptyView(
                        title: ref.levels(context, l10n.registerNoSections),
                        message: ref.levels(
                          context,
                          l10n.registerNoSectionsHint,
                        ),
                      ),
                    ),
                  ];
                }
                final id = list.any((s) => s.id == _sectionId)
                    ? _sectionId!
                    : list.first.id;
                return [
                  DropdownButtonFormField<String>(
                    key: const Key('register-section'),
                    initialValue: id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: ref.levels(context, l10n.registerSection),
                    ),
                    items: [
                      for (final s in list)
                        DropdownMenuItem(
                          value: s.id,
                          child: Text(
                            '${s.name} · ${s.mode == 'PAPER_REGISTER' ? l10n.registerModePAPERREGISTER : l10n.registerModeSELFCHECKIN}',
                          ),
                        ),
                    ],
                    onChanged: (v) => setState(() => _sectionId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: const Key('register-previous'),
                        tooltip: l10n.registerPreviousMonth,
                        onPressed: () =>
                            setState(() => _month = shiftMonth(_month, -1)),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text(monthName, style: text.titleSmall),
                      IconButton(
                        key: const Key('register-next'),
                        tooltip: l10n.registerNextMonth,
                        onPressed: () =>
                            setState(() => _month = shiftMonth(_month, 1)),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  // A new section or month starts a fresh grid.
                  _RegisterMonth(
                    key: ValueKey('$id/$_month'),
                    sectionId: id,
                    month: _month,
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

class _RegisterMonth extends ConsumerStatefulWidget {
  const _RegisterMonth({
    required this.sectionId,
    required this.month,
    super.key,
  });

  final String sectionId;
  final String month;

  @override
  ConsumerState<_RegisterMonth> createState() => _RegisterMonthState();
}

class _RegisterMonthState extends ConsumerState<_RegisterMonth> {
  late final _key = (sectionId: widget.sectionId, month: widget.month);

  /// The marks as edited, per student and column; null until loaded.
  List<List<String?>>? _marks;
  List<RegisterProblem> _problems = const [];
  String? _message;
  bool _messageIsError = false;
  bool _saving = false;
  bool _replaceCheckIns = false;
  int _checkIns = 0;

  void _load(PaperRegister r) {
    _marks ??= [
      for (final s in r.students)
        [
          for (var c = 0; c < r.columns.length; c++)
            c < s.marks.length ? s.marks[c] : null,
        ],
    ];
  }

  bool _dirty(PaperRegister r) {
    final m = _marks;
    if (m == null) return false;
    for (final (i, s) in r.students.indexed) {
      for (var c = 0; c < r.columns.length; c++) {
        if (m[i][c] != (c < s.marks.length ? s.marks[c] : null)) return true;
      }
    }
    return false;
  }

  void _tap(int student, int column) {
    setState(() {
      final m = _marks!;
      final i = _cycle.indexOf(m[student][column]);
      m[student][column] = _cycle[(i + 1) % _cycle.length];
      // An edited cell's old problem no longer applies.
      _problems = [
        for (final p in _problems)
          if (!(p.row == student + 1 && p.column == column + 2)) p,
      ];
      _message = null;
    });
  }

  Future<void> _save(PaperRegister r) async {
    final l10n = context.l10n;
    final repo = ref.read(paperRegisterRepositoryProvider);
    final body = PaperRegisterRepository.body(
      r,
      _marks!,
      overwriteCheckIns: _replaceCheckIns,
    );
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final check = await repo.preview(widget.sectionId, body);
      if (!mounted) return;
      if (!check.valid) {
        setState(() {
          _problems = check.problems;
          _checkIns = check.checkIns;
          _message = l10n.registerImporterPreviewProblems;
          _messageIsError = true;
        });
        return;
      }
      // Self check-ins the grid disagrees with: ask first (as the web's
      // preview does); they stay unless the box is ticked.
      if (check.checkIns > 0 && _checkIns == 0) {
        setState(() {
          _problems = const [];
          _checkIns = check.checkIns;
          _message = l10n.registerImporterPreviewReady;
          _messageIsError = false;
        });
        return;
      }
      final count =
          check.newMarks +
          check.changed +
          (_replaceCheckIns ? check.checkIns : 0);
      if (count == 0) {
        setState(() {
          _problems = const [];
          _message = l10n.registerImporterNothingToChange;
          _messageIsError = false;
        });
        return;
      }
      final done = await repo.import(widget.sectionId, body);
      if (!mounted) return;
      setState(() {
        _problems = const [];
        _checkIns = 0;
        _replaceCheckIns = false;
        _message = l10n.registerImported(done.newMarks, done.changed);
        _messageIsError = false;
        _marks = null;
      });
      ref.invalidate(paperRegisterProvider(_key));
    } catch (e) {
      if (!mounted) return;
      final known = _registerError(l10n, e);
      if (known != null) {
        setState(() {
          _message = ref.levels(context, known);
          _messageIsError = true;
        });
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        setState(() {
          _message = apiErrorText(l10n, e);
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final register = ref.watch(paperRegisterProvider(_key));
    return register.when(
      loading: () => SizedBox(
        height: 200,
        child: LoadingView(semanticsLabel: l10n.registerTitle),
      ),
      error: (e, _) => SizedBox(
        height: 300,
        child: ErrorView(
          title: l10n.registerLoadFailed,
          message: switch (_registerError(l10n, e)) {
            final m? => ref.levels(context, m),
            null => null,
          },
          retryLabel: l10n.uiErrorRetry,
          onRetry: () => ref.invalidate(paperRegisterProvider(_key)),
        ),
      ),
      data: (r) {
        _load(r);
        return _grid(r);
      },
    );
  }

  Widget _grid(PaperRegister r) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final paper = r.mode == 'PAPER_REGISTER';
    final editable = paper && r.canImport;
    if (r.columns.isEmpty) {
      return SizedBox(
        height: 260,
        child: EmptyView(
          icon: Icons.event_busy_outlined,
          title: l10n.registerNoClasses,
          message: ref.levels(context, l10n.registerNoClassesHint),
        ),
      );
    }
    final marks = _marks!;
    final lineProblems = [
      for (final p in _problems)
        if (p.column == null || p.row == null) p,
    ];
    String? cellProblem(int student, int column) {
      for (final p in _problems) {
        if (p.row == student + 1 && p.column == column + 2) {
          return _issueText(l10n, p);
        }
      }
      return null;
    }

    String head(RegisterColumn c) {
      final day = OrgTime.number(int.parse(c.date.substring(8, 10)), language);
      return c.header.length > 10 && c.startTime.isNotEmpty
          ? '$day\n${OrgTime.timeOfDay(c.startTime, language)}'
          : day;
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ref.levels(
              context,
              paper
                  ? l10n.registerPaperHint(r.columns.length, r.students.length)
                  : l10n.registerSelfHint(r.columns.length, r.students.length),
            ),
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (r.students.isEmpty)
            Text(ref.levels(context, l10n.registerNoStudents))
          else
            SingleChildScrollView(
              key: const Key('register-grid'),
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: AppSpacing.sm,
                horizontalMargin: 0,
                headingRowHeight: 44,
                dataRowMinHeight: AppSpacing.tapTarget,
                dataRowMaxHeight: AppSpacing.tapTarget + AppSpacing.sm,
                columns: [
                  DataColumn(label: Text(l10n.registerColumnsRoll)),
                  DataColumn(label: Text(l10n.registerColumnsName)),
                  for (final c in r.columns)
                    DataColumn(
                      label: Text(
                        head(c),
                        textAlign: TextAlign.center,
                        style: text.labelSmall,
                      ),
                    ),
                ],
                rows: [
                  for (final (i, s) in r.students.indexed)
                    DataRow(
                      cells: [
                        DataCell(Text(s.rollNo ?? '—')),
                        DataCell(Text(s.name)),
                        for (var c = 0; c < r.columns.length; c++)
                          DataCell(
                            _Cell(
                              key: Key('cell-${s.id}-$c'),
                              mark: marks[i][c],
                              problem: cellProblem(i, c),
                              onTap: editable && !_saving
                                  ? () => _tap(i, c)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          for (final p in lineProblems)
            Text(
              '${p.row != null ? '${l10n.registerImporterColumnsRow} ${OrgTime.number(p.row!, language)}: ' : ''}${ref.levels(context, _issueText(l10n, p))}',
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
          if (_checkIns > 0 && editable)
            CheckboxListTile(
              key: const Key('register-replace-check-ins'),
              contentPadding: EdgeInsets.zero,
              value: _replaceCheckIns,
              onChanged: (v) => setState(() => _replaceCheckIns = v ?? false),
              title: Text(l10n.registerImporterOverwrite(_checkIns)),
              subtitle: Text(l10n.registerImporterOverwriteHint),
            ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                _message!,
                key: const Key('register-message'),
                style: text.bodySmall?.copyWith(
                  color: _messageIsError ? colors.danger : colors.success,
                ),
              ),
            ),
          if (editable) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton(
                key: const Key('register-save'),
                onPressed: _saving || (!_dirty(r) && _checkIns == 0)
                    ? null
                    : () => _save(r),
                child: Text(l10n.registerImport),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One register cell: the mark's colour and letter, outlined in red with a
/// tooltip when it has a problem.
class _Cell extends StatelessWidget {
  const _Cell({
    required this.mark,
    required this.onTap,
    this.problem,
    super.key,
  });

  final String? mark;
  final String? problem;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final m = mark;
    final child = InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: AppSpacing.tapTarget - AppSpacing.sm,
        height: AppSpacing.tapTarget - AppSpacing.sm,
        alignment: Alignment.center,
        decoration: problem == null
            ? null
            : BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.danger, width: 2),
              ),
        child: m == null
            ? Text('·', style: TextStyle(color: colors.inkMuted))
            : AttendanceMark(status: m, letter: attendanceLetter(l10n, m)),
      ),
    );
    final label = m == null
        ? l10n.registerColumnsMissing
        : attendanceStatusName(l10n, m);
    return Semantics(
      label: problem == null ? label : '$label. $problem',
      button: onTap != null,
      child: problem == null ? child : Tooltip(message: problem, child: child),
    );
  }
}
