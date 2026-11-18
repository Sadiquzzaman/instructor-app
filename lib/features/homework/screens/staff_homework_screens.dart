import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/text/html_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/homework/data/homework.dart';
import 'package:instructor_app/features/homework/homework_text.dart';
import 'package:instructor_app/features/homework/screens/homework_review_section.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

const _types = ['FILE', 'TEXT', 'PAPER'];
const _filters = ['ACTIVE', 'DRAFT', 'SCHEDULED', 'PUBLISHED', 'CANCELLED'];

String _statusName(AppLocalizations l10n, String s) => switch (s) {
  'DRAFT' => l10n.homeworkStatusesDRAFT,
  'SCHEDULED' => l10n.homeworkStatusesSCHEDULED,
  'CANCELLED' => l10n.homeworkStatusesCANCELLED,
  _ => l10n.homeworkStatusesPUBLISHED,
};

StatusTone _statusTone(String s) => switch (s) {
  'SCHEDULED' => StatusTone.warning,
  'PUBLISHED' => StatusTone.success,
  'CANCELLED' => StatusTone.danger,
  _ => StatusTone.neutral,
};

String _typeName(AppLocalizations l10n, String t) => switch (t) {
  'TEXT' => l10n.homeworkEditorTypesTEXT,
  'PAPER' => l10n.homeworkEditorTypesPAPER,
  _ => l10n.homeworkEditorTypesFILE,
};

String _typeHint(AppLocalizations l10n, String t) => switch (t) {
  'TEXT' => l10n.homeworkEditorTypeHintsTEXT,
  'PAPER' => l10n.homeworkEditorTypeHintsPAPER,
  _ => l10n.homeworkEditorTypeHintsFILE,
};

/// A homework refusal the screens explain (`homework.errors`), or null.
String? homeworkFormError(AppLocalizations l10n, String? code) =>
    switch (code) {
      'TITLE_REQUIRED' => l10n.homeworkErrorsTITLEREQUIRED,
      'CLASS_REQUIRED' => l10n.homeworkErrorsCLASSREQUIRED,
      'HOMEWORK_TARGETS_INVALID' => l10n.homeworkErrorsHOMEWORKTARGETSINVALID,
      'HOMEWORK_TARGETS_MIXED' => l10n.homeworkErrorsHOMEWORKTARGETSMIXED,
      'HOMEWORK_STUDENT_NOT_IN_CLASS' =>
        l10n.homeworkErrorsHOMEWORKSTUDENTNOTINCLASS,
      'HOMEWORK_SESSION_CLOSED' => l10n.homeworkErrorsHOMEWORKSESSIONCLOSED,
      'HOMEWORK_FILE_INVALID' => l10n.homeworkErrorsHOMEWORKFILEINVALID,
      'HOMEWORK_DUE_INVALID' => l10n.homeworkErrorsHOMEWORKDUEINVALID,
      'HOMEWORK_WRONG_STATUS' => l10n.homeworkErrorsHOMEWORKWRONGSTATUS,
      _ => null,
    };

/// The instant for a date and "HH:MM" in the organisation's time zone.
DateTime _instant(String date, String time) {
  final d = DateTime.parse('${date}T00:00:00Z');
  final p = time.split(':');
  return DateTime.utc(
    d.year,
    d.month,
    d.day,
    int.tryParse(p.first) ?? 0,
    p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0,
  ).subtract(OrgTime.offset);
}

/// A date and "HH:MM" in the organisation's time zone.
({String date, String time}) _parts(DateTime instant) {
  final w = OrgTime.wallClock(instant);
  return (
    date: DateFormat('yyyy-MM-dd').format(w),
    time: DateFormat('HH:mm').format(w),
  );
}

Future<String?> _pickDate(BuildContext context, String current) async {
  final today = OrgTime.today();
  DateTime d(String s) => DateTime.parse('${s}T00:00:00');
  final picked = await showDatePicker(
    context: context,
    initialDate: d(current.isEmpty ? today : current),
    firstDate: d(today).subtract(const Duration(days: 365)),
    lastDate: d(today).add(const Duration(days: 730)),
  );
  return picked == null ? null : DateFormat('yyyy-MM-dd').format(picked);
}

Future<String?> _pickTime(BuildContext context, String current) async {
  final p = current.split(':');
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(
      hour: int.tryParse(p.first) ?? 23,
      minute: p.length > 1 ? int.tryParse(p[1]) ?? 59 : 59,
    ),
  );
  if (t == null) return null;
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// The web's /homework for staff: the homework they manage, by status
/// (active by default), newest first; New homework; each opens its page.
class StaffHomeworkListScreen extends ConsumerStatefulWidget {
  const StaffHomeworkListScreen({super.key});

  @override
  ConsumerState<StaffHomeworkListScreen> createState() =>
      _StaffHomeworkListScreenState();
}

class _StaffHomeworkListScreenState
    extends ConsumerState<StaffHomeworkListScreen> {
  String _status = 'ACTIVE';

  Future<void> _new() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await openHomeworkEditor(context, null);
    if (saved == null || !mounted) return;
    ref.invalidate(managedHomeworkProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved.status == 'PUBLISHED'
              ? l10n.homeworkPublished
              : l10n.homeworkSavedDraft,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final list = ref.watch(managedHomeworkProvider(_status));
    String filterName(String f) => switch (f) {
      'DRAFT' => l10n.homeworkFiltersDRAFT,
      'SCHEDULED' => l10n.homeworkFiltersSCHEDULED,
      'PUBLISHED' => l10n.homeworkFiltersPUBLISHED,
      'CANCELLED' => l10n.homeworkFiltersCANCELLED,
      _ => l10n.homeworkFiltersACTIVE,
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(managedHomeworkProvider(_status));
            await ref
                .read(managedHomeworkProvider(_status).future)
                .then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.homeworkTitle, style: text.headlineSmall),
                  ),
                  FilledButton.icon(
                    key: const Key('homework-new'),
                    onPressed: _new,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.homeworkNew),
                  ),
                ],
              ),
              Text(
                l10n.homeworkStaffIntro,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: const Key('homework-filter'),
                initialValue: _status,
                decoration: InputDecoration(labelText: l10n.homeworkShow),
                items: [
                  for (final f in _filters)
                    DropdownMenuItem(value: f, child: Text(filterName(f))),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
              const SizedBox(height: AppSpacing.md),
              ...list.when(
                loading: () => [
                  SizedBox(
                    height: 220,
                    child: LoadingView(semanticsLabel: l10n.homeworkTitle),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 300,
                    child: e is ApiException && e.isFeatureLocked
                        ? EmptyView(
                            icon: Icons.lock_outline,
                            title: l10n.featuresLockedTitle,
                          )
                        : ErrorView(
                            title: l10n.homeworkLoadFailed,
                            retryLabel: l10n.uiErrorRetry,
                            onRetry: () => ref.invalidate(
                              managedHomeworkProvider(_status),
                            ),
                          ),
                  ),
                ],
                data: (items) => items.isEmpty
                    ? [
                        SizedBox(
                          height: 260,
                          child: EmptyView(
                            icon: Icons.assignment_outlined,
                            title: l10n.homeworkStaffEmpty,
                            message: l10n.homeworkStaffEmptyHint,
                          ),
                        ),
                      ]
                    : [
                        for (final h in items) ...[
                          AppCard(
                            key: Key('homework-${h.id}'),
                            onTap: () async {
                              await context.push(
                                '${AppRoutes.homework}/${h.id}',
                              );
                              if (mounted) {
                                ref.invalidate(managedHomeworkProvider);
                              }
                            },
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        h.title,
                                        style: text.titleMedium,
                                      ),
                                    ),
                                    StatusPill(
                                      label: _statusName(l10n, h.status),
                                      tone: _statusTone(h.status),
                                    ),
                                  ],
                                ),
                                Text(
                                  [
                                    h.subject,
                                    h.classesLabel,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: text.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                                Text(
                                  '${l10n.homeworkColumnsDue}: '
                                  '${h.dueAt == null ? '—' : OrgTime.dateTime(h.dueAt!, language)}'
                                  ' · ${l10n.homeworkColumnsStudents}: '
                                  '${OrgTime.number(h.studentCount, language)}',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens the editor over the whole screen; returns what was saved.
Future<Homework?> openHomeworkEditor(BuildContext context, Homework? h) =>
    Navigator.of(context, rootNavigator: true).push<Homework>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => HomeworkEditorScreen(homework: h),
      ),
    );

/// A homework's page for staff (the web's HomeworkDetail): status, due,
/// what it is, instructions and files; Edit, Publish now or at a time, and
/// Withdraw (kept, never deleted) when the caller may; then the hand-ins
/// and marking ([HomeworkReviewSection]).
class StaffHomeworkDetailScreen extends ConsumerStatefulWidget {
  const StaffHomeworkDetailScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<StaffHomeworkDetailScreen> createState() =>
      _StaffHomeworkDetailScreenState();
}

class _StaffHomeworkDetailScreenState
    extends ConsumerState<StaffHomeworkDetailScreen> {
  Homework? _latest;
  bool _busy = false;

  Future<void> _act(Future<Homework?> Function() action, String done) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final h = await action();
      if (!mounted) return;
      if (h != null) setState(() => _latest = h);
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (e) {
      if (!mounted) return;
      final known = e is ApiException ? homeworkFormError(l10n, e.code) : null;
      if (known != null) {
        messenger.showSnackBar(SnackBar(content: Text(known)));
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _schedule(Homework h) async {
    final l10n = context.l10n;
    var date = '';
    var time = '08:00';
    final at = await showDialog<DateTime>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(l10n.homeworkDetailScheduleTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.homeworkDetailScheduleHint),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: const Key('schedule-date'),
                onPressed: () async {
                  final v = await _pickDate(d, date);
                  if (v != null) setD(() => date = v);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(
                  '${l10n.homeworkDetailScheduleDate}: '
                  '${date.isEmpty ? '—' : OrgTime.schoolDay(date, Localizations.localeOf(d).languageCode)}',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: const Key('schedule-time'),
                onPressed: () async {
                  final v = await _pickTime(d, time);
                  if (v != null) setD(() => time = v);
                },
                icon: const Icon(Icons.schedule),
                label: Text(
                  '${l10n.homeworkDetailScheduleTime}: '
                  '${OrgTime.timeOfDay(time, Localizations.localeOf(d).languageCode)}',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(),
              child: Text(l10n.homeworkEditorCancel),
            ),
            FilledButton(
              key: const Key('schedule-save'),
              onPressed: date.isEmpty
                  ? null
                  : () => Navigator.of(d).pop(_instant(date, time)),
              child: Text(l10n.homeworkDetailSchedule),
            ),
          ],
        ),
      ),
    );
    if (at == null) return;
    await _act(
      () => ref.read(homeworkRepositoryProvider).publish(h.id, at: at),
      l10n.homeworkScheduled,
    );
  }

  Future<void> _withdraw(Homework h) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.homeworkDetailWithdrawTitle),
        content: Text(l10n.homeworkDetailWithdrawDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.homeworkEditorCancel),
          ),
          FilledButton(
            key: const Key('withdraw-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(d).danger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.homeworkDetailWithdraw),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _act(
      () => ref.read(homeworkRepositoryProvider).withdraw(h.id),
      l10n.homeworkWithdrawn,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = ref.watch(homeworkProvider(widget.id));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: _latest != null
            ? _page(_latest!)
            : loaded.when(
                loading: () => LoadingView(semanticsLabel: l10n.homeworkTitle),
                error: (e, _) => e is ApiException && e.statusCode == 404
                    ? EmptyView(
                        icon: Icons.assignment_late_outlined,
                        title: l10n.homeworkNotFound,
                      )
                    : ErrorView(
                        title: l10n.homeworkLoadFailed,
                        retryLabel: l10n.uiErrorRetry,
                        onRetry: () =>
                            ref.invalidate(homeworkProvider(widget.id)),
                      ),
                data: (h) => h == null
                    ? EmptyView(
                        icon: Icons.assignment_late_outlined,
                        title: l10n.homeworkNotFound,
                      )
                    : _page(h),
              ),
      ),
    );
  }

  Widget _page(Homework h) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final (dueLabel, dueTone) = dueText(l10n, h.dueAt, language);
    final canPublish =
        h.canEdit && (h.status == 'DRAFT' || h.status == 'SCHEDULED');
    Widget fact(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: colors.inkMuted)),
          Text(value, style: text.bodyLarge),
        ],
      ),
    );
    final instructions = h.instructionsHtml == null
        ? ''
        : htmlToText(h.instructionsHtml!);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(h.title, style: text.headlineSmall),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (h.canEdit)
              StatusPill(
                key: const Key('homework-status'),
                label: _statusName(l10n, h.status),
                tone: _statusTone(h.status),
              ),
            StatusPill(label: dueLabel, tone: dueTone),
            if (h.status == 'SCHEDULED' && h.publishAt != null)
              Text(
                l10n.homeworkDetailScheduledFor(
                  OrgTime.dateTime(h.publishAt!, language),
                ),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
          ],
        ),
        if (h.canEdit) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                key: const Key('homework-edit'),
                onPressed: _busy
                    ? null
                    : () async {
                        final saved = await openHomeworkEditor(context, h);
                        if (saved == null || !mounted) return;
                        setState(() => _latest = saved);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              saved.status == 'PUBLISHED' &&
                                      h.status != 'PUBLISHED'
                                  ? l10n.homeworkPublished
                                  : l10n.homeworkSaved,
                            ),
                          ),
                        );
                      },
                child: Text(l10n.homeworkDetailEdit),
              ),
              if (canPublish) ...[
                OutlinedButton(
                  key: const Key('homework-schedule'),
                  onPressed: _busy ? null : () => _schedule(h),
                  child: Text(l10n.homeworkDetailSchedule),
                ),
                FilledButton(
                  key: const Key('homework-publish'),
                  onPressed: _busy
                      ? null
                      : () => _act(
                          () => ref
                              .read(homeworkRepositoryProvider)
                              .publish(h.id),
                          l10n.homeworkPublished,
                        ),
                  child: Text(l10n.homeworkDetailPublishNow),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              fact(l10n.homeworkDetailSubject, h.subject),
              fact(l10n.homeworkDetailType, _typeName(l10n, h.type)),
              fact(
                l10n.homeworkDetailMarks,
                h.totalMarks == null
                    ? l10n.homeworkDetailNotScored
                    : OrgTime.number(h.totalMarks!, language),
              ),
              if (h.canEdit || h.targets.isNotEmpty)
                fact(l10n.homeworkDetailClasses, h.classesLabel),
              if (h.canEdit)
                fact(
                  l10n.homeworkDetailStudents,
                  OrgTime.number(h.studentCount, language),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.homeworkDetailInstructions, style: text.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                instructions.isEmpty
                    ? l10n.homeworkDetailNoInstructions
                    : instructions,
                style: instructions.isEmpty
                    ? text.bodySmall?.copyWith(color: colors.inkMuted)
                    : text.bodyMedium,
              ),
            ],
          ),
        ),
        if (h.attachments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.homeworkDetailAttachments, style: text.titleMedium),
                for (final f in h.attachments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      f.isImage
                          ? Icons.image_outlined
                          : Icons.insert_drive_file_outlined,
                    ),
                    title: Text(f.name ?? l10n.homeworkDetailFile),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: () => openFile(context, ref, f.id),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        HomeworkReviewSection(homework: h),
        if (h.canEdit && h.status != 'CANCELLED') ...[
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              key: const Key('homework-withdraw'),
              style: TextButton.styleFrom(foregroundColor: colors.danger),
              onPressed: _busy ? null : () => _withdraw(h),
              child: Text(l10n.homeworkDetailWithdraw),
            ),
          ),
        ],
      ],
    );
  }
}

/// Writes or changes a homework (the web's HomeworkEditor): title, the
/// subject classes (one subject) or chosen students of them, instructions
/// as plain text (Stage 2 plan §7.1), how it is handed in, marks, due time
/// and files. Saved as a draft, or published straight after. A published
/// homework keeps its classes, students and type.
class HomeworkEditorScreen extends ConsumerStatefulWidget {
  const HomeworkEditorScreen({this.homework, super.key});

  /// The homework being changed; null for a new one.
  final Homework? homework;

  @override
  ConsumerState<HomeworkEditorScreen> createState() =>
      _HomeworkEditorScreenState();
}

class _HomeworkEditorScreenState extends ConsumerState<HomeworkEditorScreen> {
  late final Homework? _h = widget.homework;
  late final bool _locked = _h?.status == 'PUBLISHED';
  late final _title = TextEditingController(text: _h?.title ?? '');
  late final _instructions = TextEditingController(
    text: _h?.instructionsHtml == null ? '' : htmlToText(_h!.instructionsHtml!),
  );
  late final _marks = TextEditingController(
    text: _h?.totalMarks == null ? '' : '${_h!.totalMarks}',
  );
  late final Set<String> _offerings = {
    for (final t in _h?.targets ?? const <HomeworkTarget>[]) t.offeringId,
  };
  late bool _someStudents = (_h?.targets ?? const <HomeworkTarget>[]).any(
    (t) => t.studentIds.isNotEmpty,
  );
  late final Set<String> _students = {
    for (final t in _h?.targets ?? const <HomeworkTarget>[]) ...t.studentIds,
  };
  late String _type = _h?.type ?? 'FILE';
  late String _dueDate = _h?.dueAt == null ? '' : _parts(_h!.dueAt!).date;
  late String _dueTime = _h?.dueAt == null
      ? (_h == null ? '23:59' : '')
      : _parts(_h!.dueAt!).time;
  late List<HomeworkFile> _kept = [...?_h?.attachments];
  List<UploadedFile> _added = const [];
  bool _uploading = false;

  /// Roster per subject class, loaded for "only some students".
  final _rosters = <String, List<RosterStudent>>{};
  String? _problem;
  String? _saving;

  bool get _hadFormatting {
    final html = _h?.instructionsHtml ?? '';
    return RegExp(
      '<(strong|b|em|i|u|a|table|img|h[1-6])[ >]',
      caseSensitive: false,
    ).hasMatch(html);
  }

  @override
  void dispose() {
    _title.dispose();
    _instructions.dispose();
    _marks.dispose();
    super.dispose();
  }

  Future<void> _loadRosters() async {
    final repo = ref.read(homeworkRepositoryProvider);
    for (final id in _offerings) {
      if (_rosters.containsKey(id)) continue;
      try {
        final r = await repo.roster(id);
        if (mounted) setState(() => _rosters[id] = r);
      } catch (_) {
        if (mounted) setState(() => _rosters[id] = const []);
      }
    }
  }

  Future<void> _save({required bool publish}) async {
    final l10n = context.l10n;
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _problem = homeworkFormError(l10n, 'TITLE_REQUIRED'));
      return;
    }
    if (_offerings.isEmpty) {
      setState(() => _problem = homeworkFormError(l10n, 'CLASS_REQUIRED'));
      return;
    }
    final text = _instructions.text.trim();
    final marks = num.tryParse(_marks.text.trim().replaceAll(',', '.'));
    final body = <String, Object?>{
      'title': title,
      'instructions': text.isEmpty ? null : {'html': textToHtml(text)},
      'total_marks': _marks.text.trim().isEmpty ? null : marks,
      'due_at': _dueDate.isEmpty
          ? null
          : _instant(
              _dueDate,
              _dueTime.isEmpty ? '23:59' : _dueTime,
            ).toIso8601String(),
      'attachment_ids': [
        for (final f in _kept) f.id,
        for (final f in _added) f.id,
      ],
      if (!_locked) ...{
        'submission_type': _type,
        'offering_ids': [..._offerings],
        'student_ids': _someStudents ? [..._students] : <String>[],
      },
    };
    setState(() {
      _problem = null;
      _saving = publish ? 'publish' : 'draft';
    });
    final repo = ref.read(homeworkRepositoryProvider);
    try {
      var saved = await repo.save(_h?.id, body);
      if (saved != null && publish && saved.status != 'PUBLISHED') {
        saved = await repo.publish(saved.id) ?? saved;
      }
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      final known = e is ApiException ? homeworkFormError(l10n, e.code) : null;
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
      if (mounted) setState(() => _saving = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final choices = ref.watch(homeworkClassChoicesProvider);
    final picked = choices.value ?? const <HomeworkClassChoice>[];
    final subjectId = picked
        .where((c) => _offerings.contains(c.offeringId))
        .firstOrNull
        ?.subjectId;
    final roster = <String, RosterStudent>{
      for (final id in _offerings)
        for (final s in _rosters[id] ?? const <RosterStudent>[]) s.id: s,
    }.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    final busy = _saving != null || _uploading;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _h == null
              ? l10n.homeworkEditorNewTitle
              : l10n.homeworkEditorEditTitle,
        ),
        leading: IconButton(
          tooltip: l10n.homeworkEditorCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                _locked
                    ? l10n.homeworkEditorPublishedHint
                    : l10n.homeworkEditorIntro,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('editor-title'),
                controller: _title,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: l10n.homeworkEditorTitle,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.homeworkEditorClasses, style: text.titleSmall),
              Text(
                l10n.homeworkEditorClassesHint,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              ...choices.when(
                loading: () => [const LinearProgressIndicator()],
                error: (_, _) => [Text(l10n.homeworkEditorNoClasses)],
                data: (list) => list.isEmpty
                    ? [Text(l10n.homeworkEditorNoClasses)]
                    : [
                        for (final c in list)
                          CheckboxListTile(
                            key: Key('offering-${c.offeringId}'),
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: Text('${c.sectionLabel} · ${c.subjectName}'),
                            value: _offerings.contains(c.offeringId),
                            // One subject per homework.
                            onChanged:
                                _locked ||
                                    (subjectId != null &&
                                        c.subjectId != subjectId)
                                ? null
                                : (v) {
                                    setState(() {
                                      v == true
                                          ? _offerings.add(c.offeringId)
                                          : _offerings.remove(c.offeringId);
                                      _students.clear();
                                    });
                                    if (_someStudents) _loadRosters();
                                  },
                          ),
                      ],
              ),
              if (_offerings.isNotEmpty)
                CheckboxListTile(
                  key: const Key('editor-some-students'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.homeworkEditorSomeStudents),
                  subtitle: Text(l10n.homeworkEditorSomeStudentsHint),
                  value: _someStudents,
                  onChanged: _locked
                      ? null
                      : (v) {
                          setState(() {
                            _someStudents = v ?? false;
                            _students.clear();
                          });
                          if (_someStudents) _loadRosters();
                        },
                ),
              if (_someStudents && roster.isNotEmpty)
                Container(
                  constraints: const BoxConstraints(maxHeight: 260),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: AppRadius.inputAll,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in roster)
                        CheckboxListTile(
                          key: Key('student-${s.id}'),
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(
                            s.rollNo == null
                                ? s.name
                                : '${s.rollNo}. ${s.name}',
                          ),
                          value: _students.contains(s.id),
                          onChanged: _locked
                              ? null
                              : (v) => setState(
                                  () => v == true
                                      ? _students.add(s.id)
                                      : _students.remove(s.id),
                                ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('editor-instructions'),
                controller: _instructions,
                minLines: 4,
                maxLines: 12,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  labelText: l10n.homeworkEditorInstructions,
                  hintText: l10n.homeworkEditorInstructionsPlaceholder,
                  alignLabelWithHint: true,
                  helperText: _hadFormatting ? l10n.appHomeworkPlainText : null,
                  helperMaxLines: 3,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.homeworkEditorType, style: text.titleSmall),
              RadioGroup<String>(
                groupValue: _type,
                onChanged: (v) {
                  if (!_locked && v != null) setState(() => _type = v);
                },
                child: Column(
                  children: [
                    for (final t in _types)
                      RadioListTile<String>(
                        key: Key('type-$t'),
                        contentPadding: EdgeInsets.zero,
                        value: t,
                        enabled: !_locked,
                        title: Text(_typeName(l10n, t)),
                        subtitle: Text(_typeHint(l10n, t)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('editor-marks'),
                controller: _marks,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                ],
                decoration: InputDecoration(
                  labelText: l10n.homeworkEditorMarks,
                  helperText: l10n.homeworkEditorMarksHint,
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    key: const Key('editor-due-date'),
                    onPressed: () async {
                      final v = await _pickDate(context, _dueDate);
                      if (v != null) {
                        setState(() {
                          _dueDate = v;
                          if (_dueTime.isEmpty) _dueTime = '23:59';
                        });
                      }
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      '${l10n.homeworkEditorDueDate}: '
                      '${_dueDate.isEmpty ? '—' : OrgTime.schoolDay(_dueDate, language)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const Key('editor-due-time'),
                    onPressed: _dueDate.isEmpty
                        ? null
                        : () async {
                            final v = await _pickTime(context, _dueTime);
                            if (v != null) setState(() => _dueTime = v);
                          },
                    icon: const Icon(Icons.schedule),
                    label: Text(
                      '${l10n.homeworkEditorDueTime}: '
                      '${_dueTime.isEmpty ? '—' : OrgTime.timeOfDay(_dueTime, language)}',
                    ),
                  ),
                  if (_dueDate.isNotEmpty)
                    IconButton(
                      key: const Key('editor-due-clear'),
                      tooltip: l10n.homeworkEditorCancel,
                      onPressed: () => setState(() {
                        _dueDate = '';
                        _dueTime = '';
                      }),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              Text(
                l10n.homeworkEditorDueHint,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              for (final f in _kept)
                ListTile(
                  key: Key('kept-${f.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(f.name ?? l10n.homeworkDetailFile),
                  trailing: IconButton(
                    tooltip: l10n.homeworkEditorCancel,
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(
                      () => _kept = [
                        for (final k in _kept)
                          if (k.id != f.id) k,
                      ],
                    ),
                  ),
                ),
              AttachmentField(
                label: l10n.homeworkEditorAttachments,
                purpose: FilePurpose.homework,
                enabled: _saving == null,
                onChanged: (files) => setState(() => _added = files),
                onBusyChanged: (b) => setState(() => _uploading = b),
              ),
              Text(
                l10n.homeworkEditorAttachmentsAccept,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              if (_problem != null)
                Container(
                  key: const Key('editor-problem'),
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: colors.dangerSoft,
                    borderRadius: AppRadius.inputAll,
                  ),
                  child: Text(
                    _problem!,
                    style: text.bodySmall?.copyWith(color: colors.danger),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.homeworkEditorCancel),
                  ),
                  if (!_locked)
                    OutlinedButton(
                      key: const Key('editor-draft'),
                      onPressed: busy ? null : () => _save(publish: false),
                      child: Text(l10n.homeworkEditorSaveDraft),
                    ),
                  FilledButton(
                    key: const Key('editor-publish'),
                    onPressed: busy ? null : () => _save(publish: !_locked),
                    child: Text(
                      _locked
                          ? l10n.homeworkEditorSave
                          : l10n.homeworkEditorPublish,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
