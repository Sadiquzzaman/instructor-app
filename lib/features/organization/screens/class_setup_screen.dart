import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/organization/screens/attendance_settings_screen.dart';
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';

typedef Slot = ({
  int day,
  String start,
  String end,
  String? subject,
  String? teacher,
});

@immutable
class SectionSetup {
  const SectionSetup({
    required this.id,
    required this.name,
    required this.classId,
    required this.className,
    required this.slots,
    required this.classType,
    required this.mode,
    required this.canEdit,
    this.shift,
    this.branchId,
    this.grace,
  });

  final String id;
  final String name;
  final String classId;
  final String className;
  final String? shift;
  final List<Slot> slots;
  final String? branchId;
  final String classType;
  final String mode;
  final int? grace;
  final bool canEdit;

  String get label => '$className $name';

  static SectionSetup? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final c = j['class'] is Map ? j['class'] as Map : const <String, Object?>{};
    return SectionSetup(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      classId: (c['id'] as String?) ?? '',
      className: (c['name'] as String?) ?? '',
      shift: j['shift'] as String?,
      slots: [
        if (j['slots'] is List)
          for (final s in j['slots'] as List)
            if (s is Map)
              (
                day: (s['day_of_week'] as num?)?.toInt() ?? 1,
                start: (s['start_time'] as String?) ?? '',
                end: (s['end_time'] as String?) ?? '',
                subject: s['subject'] is Map
                    ? (s['subject'] as Map)['name'] as String?
                    : null,
                teacher: s['teacher'] is Map
                    ? (s['teacher'] as Map)['full_name'] as String?
                    : null,
              ),
      ],
      branchId: j['branch_id'] as String?,
      classType: (j['class_type'] as String?) ?? 'IN_PERSON',
      mode: (j['mode'] as String?) ?? 'SELF_CHECKIN',
      grace: (j['grace_minutes'] as num?)?.toInt(),
      canEdit: j['can_edit'] == true,
    );
  }
}

typedef ClassSetup = ({
  String sessionName,
  bool canManage,
  int lateGrace,
  List<SectionSetup> sections,
});

/// [sessionId] '' is the default session.
final classSetupProvider = FutureProvider.autoDispose
    .family<ClassSetup, String>((ref, sessionId) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get(
                    '/attendance/setup',
                    query: {'session_id': sessionId.isEmpty ? null : sessionId},
                  ))
              .payload;
      final j = p is Map ? p : const <String, Object?>{};
      return (
        sessionName: j['session'] is Map
            ? ((j['session'] as Map)['name'] as String?) ?? ''
            : '',
        canManage: j['can_manage'] == true,
        lateGrace: (j['late_grace_minutes'] as num?)?.toInt() ?? 10,
        sections: [
          if (j['sections'] is List)
            for (final s in j['sections'] as List) ?SectionSetup.fromJson(s),
        ],
      );
    }, retry: (retryCount, error) => null);

/// The schedule as lines (the web's `periodsOf`): slots with the same
/// times, subject and teacher share a line, days in school-week order.
List<
  ({List<int> days, String start, String end, String? subject, String? teacher})
>
periodsOf(List<Slot> slots) {
  final lines =
      <
        ({
          List<int> days,
          String start,
          String end,
          String? subject,
          String? teacher,
        })
      >[];
  for (final s in slots) {
    final i = lines.indexWhere(
      (l) =>
          l.start == s.start &&
          l.end == s.end &&
          l.subject == s.subject &&
          l.teacher == s.teacher,
    );
    if (i >= 0) {
      lines[i].days.add(s.day);
    } else {
      lines.add((
        days: [s.day],
        start: s.start,
        end: s.end,
        subject: s.subject,
        teacher: s.teacher,
      ));
    }
  }
  int order(int d) => schoolWeek.indexOf(d);
  for (final l in lines) {
    l.days.sort((a, b) => order(a) - order(b));
  }
  lines.sort((a, b) {
    final c = a.start.compareTo(b.start);
    return c != 0 ? c : order(a.days.first) - order(b.days.first);
  });
  return lines;
}

const _graceChoices = [0, 5, 10, 15, 20, 30, 45, 60];

/// The web's /attendance-setup: each section of a session with its weekly
/// schedule, branch, in person or online, attendance mode and grace.
/// Choices save at once; a section's settings can be applied to its whole
/// class or shift after a preview. Owners, admins and assistants change
/// every section, a teacher the sections they teach. Changing the
/// schedule itself is the timetable's job; the CSV import stays on the
/// website.
class ClassSetupScreen extends ConsumerStatefulWidget {
  const ClassSetupScreen({super.key});

  @override
  ConsumerState<ClassSetupScreen> createState() => _ClassSetupScreenState();
}

class _ClassSetupScreenState extends ConsumerState<ClassSetupScreen> {
  String _session = '';
  String _class = '';
  String _shift = '';
  String? _saving;

  Future<void> _update(SectionSetup s, Map<String, Object?> body) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = s.id);
    try {
      await ref
          .read(apiClientProvider)
          .patch('/attendance/setup/sections/${s.id}', data: body);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.classSetupSaved(s.label))),
      );
      ref.invalidate(classSetupProvider(_session));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }

  Future<void> _apply(SectionSetup s) async {
    final count = await showDialog<int>(
      context: context,
      builder: (_) => _ApplyDialog(source: s),
    );
    if (count == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ref.levels(context, context.l10n.classSetupApplied(count)),
        ),
      ),
    );
    ref.invalidate(classSetupProvider(_session));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final setup = ref.watch(classSetupProvider(_session));
    final sessions = sessionRights(ref.watch(sessionProvider)).manage
        ? ref.watch(sessionsProvider).value
        : null;
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    String dayShort(int d) => switch (d) {
      1 => l10n.classSetupDayShort1,
      2 => l10n.classSetupDayShort2,
      3 => l10n.classSetupDayShort3,
      4 => l10n.classSetupDayShort4,
      5 => l10n.classSetupDayShort5,
      6 => l10n.classSetupDayShort6,
      _ => l10n.classSetupDayShort7,
    };
    String shiftName(String s) => switch (s) {
      'MORNING' => l10n.classSetupShiftMORNING,
      'DAY' => l10n.classSetupShiftDAY,
      _ => l10n.classSetupShiftEVENING,
    };
    String time(String hhmm) {
      final p = hhmm.split(':');
      if (p.length < 2) return hhmm;
      return '${OrgTime.twoDigits(int.parse(p[0]), language)}:'
          '${OrgTime.twoDigits(int.parse(p[1]), language)}';
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.classSetupTitle, style: text.headlineSmall),
            Text(ref.levels(context, l10n.classSetupIntro), style: muted),
            const SizedBox(height: AppSpacing.md),
            if (sessions != null && sessions.length > 1) ...[
              DropdownButtonFormField<String>(
                key: const Key('setup-session'),
                initialValue: _session.isEmpty ? null : _session,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.classSetupSession),
                items: [
                  for (final s in sessions)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() => _session = v ?? ''),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            ...setup.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(semanticsLabel: l10n.classSetupTitle),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 280,
                  child: ErrorView(
                    title: l10n.classSetupLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(classSetupProvider(_session)),
                  ),
                ),
              ],
              data: (d) {
                if (d.sections.isEmpty) {
                  return [
                    SizedBox(
                      height: 240,
                      child: EmptyView(
                        icon: Icons.schedule_outlined,
                        title: ref.levels(context, l10n.classSetupEmpty),
                        message: ref.levels(context, l10n.classSetupEmptyHint),
                      ),
                    ),
                  ];
                }
                final classes = <String, String>{
                  for (final s in d.sections) s.classId: s.className,
                };
                final rows = [
                  for (final s in d.sections)
                    if ((_class.isEmpty || s.classId == _class) &&
                        (_shift.isEmpty || s.shift == _shift))
                      s,
                ];
                final without = d.sections.where((s) => s.slots.isEmpty).length;
                return [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          key: const Key('setup-class'),
                          initialValue: _class,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: ref.levels(
                              context,
                              l10n.classSetupClass,
                            ),
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(
                                ref.levels(context, l10n.classSetupAllClasses),
                              ),
                            ),
                            for (final MapEntry(:key, :value)
                                in classes.entries)
                              DropdownMenuItem(value: key, child: Text(value)),
                          ],
                          onChanged: (v) => setState(() => _class = v ?? ''),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: DropdownButtonFormField<String>(
                          key: const Key('setup-shift'),
                          initialValue: _shift,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.classSetupShiftLabel,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: '',
                              child: Text(l10n.classSetupAllShifts),
                            ),
                            for (final s in ['MORNING', 'DAY', 'EVENING'])
                              DropdownMenuItem(
                                value: s,
                                child: Text(shiftName(s)),
                              ),
                          ],
                          onChanged: (v) => setState(() => _shift = v ?? ''),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    ref.levels(
                      context,
                      l10n.classSetupSectionsIn(d.sessionName),
                    ),
                    style: text.titleMedium,
                  ),
                  if (without > 0)
                    Text(
                      ref.levels(
                        context,
                        l10n.classSetupWithoutSchedule(without),
                      ),
                      key: const Key('setup-without'),
                      style: muted,
                    ),
                  for (final s in rows) ...[
                    const SizedBox(height: AppSpacing.sm),
                    AppCard(
                      key: Key('setup-${s.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(s.label, style: text.titleSmall),
                          if (s.shift != null)
                            Text(shiftName(s.shift!), style: muted),
                          const SizedBox(height: AppSpacing.xs),
                          if (s.slots.isEmpty)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: StatusPill(
                                label: l10n.classSetupNoSchedule,
                                tone: StatusTone.warning,
                              ),
                            )
                          else
                            for (final line in periodsOf(s.slots))
                              Text(
                                '${line.days.map(dayShort).join(', ')} '
                                '${time(line.start)}–${time(line.end)}'
                                '${line.subject != null ? ' · ${line.subject}' : ''}'
                                '${line.teacher != null ? ' · ${line.teacher}' : ''}',
                                style: text.bodySmall,
                              ),
                          const SizedBox(height: AppSpacing.sm),
                          if (branches.length > 1)
                            _Choice(
                              key: Key('branch-${s.id}'),
                              label: l10n.classSetupBranch,
                              value: s.branchId,
                              enabled:
                                  d.canManage && s.canEdit && _saving != s.id,
                              options: {
                                for (final b in branches)
                                  b.id: (b.name ?? '').isNotEmpty
                                      ? b.name!
                                      : l10n.branchesMainBranch,
                              },
                              onChanged: (v) => _update(s, {'branch_id': v}),
                            ),
                          _Choice(
                            key: Key('type-${s.id}'),
                            label: l10n.classSetupClassType,
                            value: s.classType,
                            enabled: s.canEdit && _saving != s.id,
                            options: {
                              'IN_PERSON': l10n.classSetupClassTypesINPERSON,
                              'ONLINE': l10n.classSetupClassTypesONLINE,
                            },
                            onChanged: (v) => _update(s, {'class_type': v}),
                          ),
                          if (s.classType == 'IN_PERSON' &&
                              branches
                                      .where((b) => b.id == s.branchId)
                                      .firstOrNull
                                      ?.lat ==
                                  null &&
                              branches.any((b) => b.id == s.branchId))
                            Text(
                              l10n.classSetupNoPin,
                              key: Key('nopin-${s.id}'),
                              style: text.bodySmall?.copyWith(
                                color: colors.warning,
                              ),
                            ),
                          _Choice(
                            key: Key('mode-${s.id}'),
                            label: l10n.classSetupMode,
                            value: s.mode,
                            enabled: s.canEdit && _saving != s.id,
                            options: {
                              'SELF_CHECKIN': l10n.classSetupModesSELFCHECKIN,
                              'PAPER_REGISTER':
                                  l10n.classSetupModesPAPERREGISTER,
                            },
                            onChanged: (v) => _update(s, {'mode': v}),
                          ),
                          _Choice(
                            key: Key('grace-${s.id}'),
                            label: l10n.classSetupGrace,
                            value: s.grace?.toString() ?? '',
                            enabled: s.canEdit && _saving != s.id,
                            options: {
                              '': l10n.classSetupGraceDefault(d.lateGrace),
                              for (final m in {
                                ..._graceChoices,
                                ?s.grace,
                              }.toList()..sort())
                                '$m': l10n.classSetupGraceMinutes(m),
                            },
                            onChanged: (v) => _update(s, {
                              'grace_minutes': v.isEmpty ? null : int.parse(v),
                            }),
                          ),
                          if (d.canManage && s.canEdit)
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton(
                                key: Key('apply-${s.id}'),
                                onPressed: () => _apply(s),
                                child: Text(l10n.classSetupApply),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String? value;
  final Map<String, String> options;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.sm),
    child: DropdownButtonFormField<String>(
      initialValue: options.containsKey(value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final MapEntry(:key, :value) in options.entries)
          DropdownMenuItem(value: key, child: Text(value)),
      ],
      onChanged: enabled
          ? (v) {
              if (v != null && v != value) onChanged(v);
            }
          : null,
    ),
  );
}

/// Apply a section's settings (not its branch or schedule) to every other
/// section of its class or shift, after a preview. Pops how many changed.
class _ApplyDialog extends ConsumerStatefulWidget {
  const _ApplyDialog({required this.source});

  final SectionSetup source;

  @override
  ConsumerState<_ApplyDialog> createState() => _ApplyDialogState();
}

class _ApplyDialogState extends ConsumerState<_ApplyDialog> {
  String _target = 'class';
  List<String>? _preview;
  bool _saving = false;
  int _round = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, Object?> _body(bool dryRun) => {
    'from_section_id': widget.source.id,
    if (_target == 'class')
      'class_id': widget.source.classId
    else
      'shift': widget.source.shift,
    'include_schedule': false,
    'include_settings': true,
    'dry_run': dryRun,
  };

  List<String> _names(Object? payload) => [
    if (payload is Map && payload['sections'] is List)
      for (final s in payload['sections'] as List)
        if (s is Map)
          '${s['class'] is Map ? (s['class'] as Map)['name'] ?? '' : s['class_name'] ?? ''} ${s['name'] ?? ''}'
              .trim(),
  ];

  Future<void> _load() async {
    final round = ++_round;
    setState(() => _preview = null);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/attendance/setup/apply', data: _body(true));
      if (mounted && round == _round) {
        setState(() => _preview = _names(r.payload));
      }
    } on ApiException {
      if (mounted && round == _round) setState(() => _preview = const []);
    }
  }

  Future<void> _apply() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .post('/attendance/setup/apply', data: _body(false));
      navigator.pop(_preview?.length ?? 0);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final s = widget.source;
    final count = _preview?.length ?? 0;
    final shiftName = switch (s.shift) {
      'MORNING' => l10n.classSetupShiftMORNING,
      'DAY' => l10n.classSetupShiftDAY,
      _ => l10n.classSetupShiftEVENING,
    };
    return AlertDialog(
      title: Text(ref.levels(context, l10n.classSetupApplySettingsTitle)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ref.levels(context, l10n.classSetupApplySettingsIntro(s.label)),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.classSetupApplyTo),
            RadioGroup<String>(
              groupValue: _target,
              onChanged: (v) {
                setState(() => _target = v ?? _target);
                _load();
              },
              child: Column(
                children: [
                  RadioListTile<String>(
                    key: const Key('apply-class'),
                    contentPadding: EdgeInsets.zero,
                    value: 'class',
                    title: Text(
                      ref.levels(
                        context,
                        l10n.classSetupApplyToClass(s.className),
                      ),
                    ),
                  ),
                  if (s.shift != null)
                    RadioListTile<String>(
                      key: const Key('apply-shift'),
                      contentPadding: EdgeInsets.zero,
                      value: 'shift',
                      title: Text(
                        ref.levels(
                          context,
                          l10n.classSetupApplyToShift(shiftName),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_preview == null)
              const LinearProgressIndicator()
            else if (count == 0)
              Text(ref.levels(context, l10n.classSetupApplyNone))
            else ...[
              Text(
                ref.levels(context, l10n.classSetupApplySettingsWill(count)),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              for (final n in _preview!) Text('• $n'),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.classSetupCancel),
        ),
        FilledButton(
          key: const Key('apply-confirm'),
          onPressed: _saving || count == 0 ? null : _apply,
          child: Text(
            ref.levels(context, l10n.classSetupApplySettingsConfirm(count)),
          ),
        ),
      ],
    );
  }
}
