import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_labels.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/organization/screens/organization_overview_screen.dart';
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';
import 'package:instructor_app/features/organization/screens/subjects_classes_screens.dart';

typedef SetupClass = ({
  String id,
  String name,
  int subjects,
  int sections,
  int students,
  List<String> withoutTeacher,
});

typedef SetupSummary = ({
  bool done,
  String? sessionId,
  String? sessionName,
  List<SetupClass> classes,
  bool pinMissing,
});

final setupSummaryProvider = FutureProvider.autoDispose<SetupSummary>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/setup')).payload;
  final j = p is Map ? p : const <String, Object?>{};
  final s = j['session'] is Map ? j['session'] as Map : null;
  return (
    done: j['setup_completed_at'] != null,
    sessionId: s?['id'] as String?,
    sessionName: s?['name'] as String?,
    classes: [
      if (j['classes'] is List)
        for (final c in j['classes'] as List)
          if (c is Map && c['id'] is String)
            (
              id: c['id'] as String,
              name: (c['name'] as String?) ?? '',
              subjects: (c['subject_count'] as num?)?.toInt() ?? 0,
              sections: (c['section_count'] as num?)?.toInt() ?? 0,
              students: (c['student_count'] as num?)?.toInt() ?? 0,
              withoutTeacher: [
                if (c['subjects_without_teacher'] is List)
                  for (final x in c['subjects_without_teacher'] as List)
                    x is Map ? '${x['name'] ?? ''}' : '$x',
              ],
            ),
    ],
    pinMissing: j['checkin_pin_missing'] == true,
  );
}, retry: (retryCount, error) => null);

/// The web's academic setup wizard (`/organization/setup`): names and
/// languages, the session, classes and their subjects, sections, then a
/// summary before finishing. Every step saves as it goes, so the wizard can
/// be left and picked up again. Owners and admins.
class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen> {
  int _step = 0;
  bool _finishing = false;

  Future<void> _finish() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _finishing = true);
    try {
      await ref.read(apiClientProvider).post('/setup/complete');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.academicsSetupFinished)),
      );
      ref
        ..invalidate(setupSummaryProvider)
        ..invalidate(setupDoneProvider);
      router.go(AppRoutes.organization);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final role = ref.watch(sessionProvider)?.memberRole;
    if (!managesOrganization(role)) {
      return EmptyView(
        icon: Icons.lock_outline,
        title: l10n.organizationGateNoAccessTitle,
        message: l10n.organizationGateNoAccess,
      );
    }
    final steps = [
      l10n.academicsSetupStepsBasics,
      l10n.academicsSetupStepsSession,
      ref.levels(context, l10n.academicsSetupStepsClasses),
      ref.levels(context, l10n.academicsSetupStepsSections),
      l10n.academicsSetupStepsSummary,
    ];
    final summary = _step == 4 ? ref.watch(setupSummaryProvider).value : null;
    final canFinish =
        summary != null &&
        summary.classes.isNotEmpty &&
        summary.classes.every((c) => c.sections > 0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.academicsSetupTitle, style: text.headlineSmall),
            Text(
              ref.levels(context, l10n.academicsSetupIntro),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (i, label) in steps.indexed)
                  ChoiceChip(
                    key: Key('setup-step-$i'),
                    label: Text(
                      '${OrgTime.number(i + 1, Localizations.localeOf(context).languageCode)}. $label',
                    ),
                    selected: _step == i,
                    onSelected: (_) => setState(() => _step = i),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            switch (_step) {
              0 => const _BasicsStep(),
              1 => const _SessionStep(),
              2 => const _ClassesStep(),
              3 => const _SectionsStep(),
              _ => const _SummaryStep(),
            },
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                OutlinedButton(
                  key: const Key('setup-back'),
                  onPressed: _step == 0
                      ? null
                      : () => setState(() => _step -= 1),
                  child: Text(l10n.academicsSetupBack),
                ),
                const Spacer(),
                if (_step < 4)
                  FilledButton(
                    key: const Key('setup-next'),
                    onPressed: () => setState(() {
                      _step += 1;
                      if (_step == 4) ref.invalidate(setupSummaryProvider);
                    }),
                    child: Text(l10n.academicsSetupNext),
                  )
                else
                  FilledButton(
                    key: const Key('setup-finish'),
                    onPressed: canFinish && !_finishing ? _finish : null,
                    child: Text(l10n.academicsSetupFinish),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 1: the organisation's settings, and (owners) what its levels are
/// called.
class _BasicsStep extends ConsumerWidget {
  const _BasicsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final owner = ref.watch(sessionProvider)?.memberRole == 'OWNER';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const OrganizationSettingsCard(),
        const SizedBox(height: AppSpacing.md),
        if (owner)
          const LevelLabelsCard()
        else
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.academicsSetupBasicsNamesTitle),
                Text(ref.levels(context, l10n.academicsSetupBasicsOwnerOnly)),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the workspace calls its two levels: Class / Section, Course /
/// Batch, or its own words (English one and many, Bangla). Owners.
class LevelLabelsCard extends ConsumerStatefulWidget {
  const LevelLabelsCard({super.key});

  @override
  ConsumerState<LevelLabelsCard> createState() => _LevelLabelsCardState();
}

class _LevelLabelsCardState extends ConsumerState<LevelLabelsCard> {
  late String _preset = ref.read(levelLabelsProvider).preset;
  late final _fields = {
    for (final (level, name) in [
      ('class', ref.read(levelLabelsProvider).classLevel),
      ('section', ref.read(levelLabelsProvider).sectionLevel),
    ])
      for (final (k, v) in [
        ('one', name.one),
        ('other', name.other),
        ('bn', name.bn),
      ])
        '$level-$k': TextEditingController(text: v),
  };
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Read the saved names now, not lazily during dispose.
    _fields.length;
    _preset.length;
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _ok(String key) {
    final v = _fields[key]!.text.trim();
    return v.isNotEmpty && v.length <= 30;
  }

  bool get _valid => _preset != 'CUSTOM' || _fields.keys.every(_ok);

  Map<String, Object?> _name(String level) => {
    'en': {
      'one': _fields['$level-one']!.text.trim(),
      'other': _fields['$level-other']!.text.trim(),
    },
    'bn': _fields['$level-bn']!.text.trim(),
  };

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .patch(
            '/workspace/level-labels',
            data: _preset == 'CUSTOM'
                ? {
                    'preset': 'CUSTOM',
                    'class': _name('class'),
                    'section': _name('section'),
                  }
                : {'preset': _preset},
          );
      ref
          .read(levelLabelsProvider.notifier)
          .set(LevelLabels.fromJson(r.payload));
      messenger.showSnackBar(SnackBar(content: Text(l10n.levelLabelsSaved)));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    return AppCard(
      key: const Key('level-labels'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.levelLabelsTitle, style: text.titleMedium),
          Text(l10n.levelLabelsIntro, style: muted),
          const SizedBox(height: AppSpacing.sm),
          Text(l10n.levelLabelsChoice, style: text.labelLarge),
          RadioGroup<String>(
            groupValue: _preset,
            onChanged: (v) => setState(() => _preset = v ?? _preset),
            child: Column(
              children: [
                for (final (v, label, hint) in [
                  (
                    'CLASS_SECTION',
                    l10n.levelLabelsPresetsCLASSSECTION,
                    l10n.levelLabelsPresetHintsCLASSSECTION,
                  ),
                  (
                    'COURSE_BATCH',
                    l10n.levelLabelsPresetsCOURSEBATCH,
                    l10n.levelLabelsPresetHintsCOURSEBATCH,
                  ),
                  (
                    'CUSTOM',
                    l10n.levelLabelsPresetsCUSTOM,
                    l10n.levelLabelsPresetHintsCUSTOM,
                  ),
                ])
                  RadioListTile<String>(
                    key: Key('preset-$v'),
                    contentPadding: EdgeInsets.zero,
                    value: v,
                    title: Text(label),
                    subtitle: Text(hint),
                  ),
              ],
            ),
          ),
          if (_preset == 'CUSTOM')
            for (final (level, title) in [
              ('class', l10n.levelLabelsClassLevel),
              ('section', l10n.levelLabelsSectionLevel),
            ]) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(title, style: text.labelLarge),
              for (final (k, label) in [
                ('one', l10n.levelLabelsOne),
                ('other', l10n.levelLabelsOther),
                ('bn', l10n.levelLabelsBn),
              ])
                TextField(
                  key: Key('label-$level-$k'),
                  controller: _fields['$level-$k'],
                  maxLength: 30,
                  decoration: InputDecoration(
                    labelText: label,
                    errorText: _ok('$level-$k')
                        ? null
                        : l10n.levelLabelsRequired(30),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
            ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: FilledButton(
              key: const Key('labels-save'),
              onPressed: _saving || !_valid ? null : _save,
              child: Text(l10n.levelLabelsSave),
            ),
          ),
        ],
      ),
    );
  }
}

/// Step 2: the sessions; add the first one or change it.
class _SessionStep extends ConsumerWidget {
  const _SessionStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final sessions = ref.watch(sessionsProvider);
    Future<void> edit(AcademicSession? s) async {
      final saved = await showDialog<bool>(
        context: context,
        builder: (_) => SessionDialog(session: s),
      );
      if (saved == true) ref.invalidate(sessionsProvider);
    }

    String day(String? v) => v == null ? '—' : OrgTime.schoolDay(v, language);
    return AppCard(
      key: const Key('setup-session'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.academicsSetupSessionTitle, style: text.titleMedium),
          Text(
            ref.levels(context, l10n.academicsSetupSessionIntro),
            style: muted,
          ),
          ...sessions.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(apiErrorText(l10n, e))],
            data: (list) => [
              for (final s in list)
                ListTile(
                  key: Key('setup-session-${s.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      Text(s.name),
                      if (s.isDefault)
                        StatusPill(
                          label: l10n.academicsSetupSessionDefault,
                          tone: StatusTone.primary,
                        ),
                    ],
                  ),
                  subtitle: Text('${day(s.start)} – ${day(s.end)}'),
                  trailing: s.active
                      ? TextButton(
                          onPressed: () => edit(s),
                          child: Text(l10n.academicsSetupSessionEdit),
                        )
                      : null,
                ),
            ],
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton.icon(
              key: const Key('setup-session-add'),
              icon: const Icon(Icons.add),
              label: Text(l10n.academicsSetupSessionAdd),
              onPressed: () => edit(null),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _ClassSubject = ({String id, String subjectId, String name});

final _classSubjectsProvider = FutureProvider.autoDispose
    .family<List<_ClassSubject>, String>((ref, classId) async {
      final p =
          (await ref.read(apiClientProvider).get('/classes/$classId/subjects'))
              .payload;
      return [
        if (p is List)
          for (final r in p)
            if (r is Map && r['id'] is String)
              (
                id: r['id'] as String,
                subjectId:
                    (r['subject_id'] as String?) ??
                    (r['subject'] is Map
                        ? ((r['subject'] as Map)['id'] as String?) ?? ''
                        : ''),
                name: r['subject'] is Map
                    ? ((r['subject'] as Map)['name'] as String?) ?? ''
                    : '',
              ),
      ];
    }, retry: (retryCount, error) => null);

/// Step 3: classes, and each class's subjects (from the catalogue, or a new
/// subject made on the spot).
class _ClassesStep extends ConsumerStatefulWidget {
  const _ClassesStep();

  @override
  ConsumerState<_ClassesStep> createState() => _ClassesStepState();
}

class _ClassesStepState extends ConsumerState<_ClassesStep> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addClass() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final added = ref.levels(context, l10n.academicsSetupClassesClassAdded);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .post('/classes', data: {'class_name': _name.text.trim()});
      _name.clear();
      messenger.showSnackBar(SnackBar(content: Text(added)));
      ref.invalidate(setupSummaryProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final summary = ref.watch(setupSummaryProvider);
    return AppCard(
      key: const Key('setup-classes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ref.levels(context, l10n.academicsSetupClassesTitle),
            style: text.titleMedium,
          ),
          Text(
            ref.levels(context, l10n.academicsSetupClassesIntro),
            style: muted,
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('setup-class-name'),
                  controller: _name,
                  decoration: InputDecoration(
                    labelText: ref.levels(
                      context,
                      l10n.academicsSetupClassesClassName,
                    ),
                    hintText: ref.levels(
                      context,
                      l10n.academicsSetupClassesClassNamePlaceholder,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilledButton(
                key: const Key('setup-class-add'),
                onPressed: _busy || _name.text.trim().isEmpty
                    ? null
                    : _addClass,
                child: Text(
                  ref.levels(context, l10n.academicsSetupClassesAddClass),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ...summary.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(apiErrorText(l10n, e))],
            data: (s) => s.classes.isEmpty
                ? [
                    Text(
                      ref.levels(context, l10n.academicsSetupClassesEmpty),
                      style: text.titleSmall,
                    ),
                    Text(
                      ref.levels(
                        context,
                        l10n.academicsSetupClassesEmptyDetail,
                      ),
                      style: muted,
                    ),
                  ]
                : [
                    for (final c in s.classes)
                      _ClassSubjects(key: Key('setup-class-${c.id}'), klass: c),
                  ],
          ),
        ],
      ),
    );
  }
}

const _newSubject = '__new__';

class _ClassSubjects extends ConsumerStatefulWidget {
  const _ClassSubjects({required this.klass, super.key});

  final SetupClass klass;

  @override
  ConsumerState<_ClassSubjects> createState() => _ClassSubjectsState();
}

class _ClassSubjectsState extends ConsumerState<_ClassSubjects> {
  String? _pick;
  final _newName = TextEditingController();
  final _newCode = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _newName.dispose();
    _newCode.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final org = ref.read(sessionProvider)?.organizationId;
    final api = ref.read(apiClientProvider);
    setState(() => _busy = true);
    try {
      var id = _pick;
      if (id == _newSubject) {
        final r = await api.post(
          '/organizations/$org/subjects',
          data: {'name': _newName.text.trim(), 'code': _newCode.text.trim()},
        );
        id = r.payload is Map ? (r.payload! as Map)['id'] as String? : null;
        ref.invalidate(orgSubjectsProvider);
      }
      if (id == null) return;
      await api.post(
        '/classes/${widget.klass.id}/subjects',
        data: {'subject_id': id},
      );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.academicsSetupClassesSubjectAdded)),
      );
      _newName.clear();
      _newCode.clear();
      setState(() => _pick = null);
      ref
        ..invalidate(_classSubjectsProvider(widget.klass.id))
        ..invalidate(setupSummaryProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final attached =
        ref.watch(_classSubjectsProvider(widget.klass.id)).value ??
        const <_ClassSubject>[];
    final catalog =
        ref.watch(orgSubjectsProvider).value ?? const <OrgSubject>[];
    final free = [
      for (final s in catalog)
        if (!attached.any((a) => a.subjectId == s.id)) s,
    ];
    final creating = _pick == _newSubject;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          Text(widget.klass.name, style: text.titleSmall),
          Text(
            attached.isEmpty
                ? l10n.academicsSetupClassesNoSubjects
                : attached.map((a) => a.name).join(', '),
            style: muted,
          ),
          DropdownButtonFormField<String>(
            key: Key('setup-subject-${widget.klass.id}'),
            initialValue: _pick,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.academicsSetupClassesSubject,
              hintText: l10n.academicsSetupClassesChooseSubject,
            ),
            items: [
              for (final s in free)
                DropdownMenuItem(value: s.id, child: Text(s.name)),
              DropdownMenuItem(
                value: _newSubject,
                child: Text(l10n.academicsSetupClassesNewSubjectOption),
              ),
            ],
            onChanged: (v) => setState(() => _pick = v),
          ),
          if (creating) ...[
            TextField(
              key: Key('setup-new-name-${widget.klass.id}'),
              controller: _newName,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: l10n.academicsSetupClassesSubjectName,
              ),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              key: Key('setup-new-code-${widget.klass.id}'),
              controller: _newCode,
              maxLength: 20,
              decoration: InputDecoration(
                labelText: l10n.academicsSetupClassesSubjectCode,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: OutlinedButton(
              key: Key('setup-subject-add-${widget.klass.id}'),
              onPressed:
                  _busy ||
                      _pick == null ||
                      (creating &&
                          (_newName.text.trim().isEmpty ||
                              _newCode.text.trim().isEmpty))
                  ? null
                  : _add,
              child: Text(
                creating
                    ? l10n.academicsSetupClassesCreateAndAdd
                    : l10n.academicsSetupClassesAddSubject,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _Section = ({String id, String name});

final _sectionsOfClassProvider = FutureProvider.autoDispose
    .family<List<_Section>, ({String classId, String? sessionId})>((
      ref,
      k,
    ) async {
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get(
                    '/classes/${k.classId}/sections',
                    query: {'session_id': k.sessionId},
                  ))
              .payload;
      return [
        if (p is List)
          for (final s in p)
            if (s is Map && s['id'] is String)
              (id: s['id'] as String, name: (s['name'] as String?) ?? ''),
      ];
    }, retry: (retryCount, error) => null);

/// Step 4: each class's sections; add one by name.
class _SectionsStep extends ConsumerWidget {
  const _SectionsStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final summary = ref.watch(setupSummaryProvider);
    return AppCard(
      key: const Key('setup-sections'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ref.levels(context, l10n.academicsSetupStepsSections),
            style: text.titleMedium,
          ),
          Text(
            ref.levels(context, l10n.academicsSetupSectionsIntro),
            style: muted,
          ),
          ...summary.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(apiErrorText(l10n, e))],
            data: (s) => s.classes.isEmpty
                ? [
                    Text(
                      ref.levels(context, l10n.academicsSetupSectionsNoClasses),
                      style: text.titleSmall,
                    ),
                    Text(
                      ref.levels(
                        context,
                        l10n.academicsSetupSectionsNoClassesDetail,
                      ),
                      style: muted,
                    ),
                  ]
                : [
                    for (final c in s.classes)
                      _ClassSections(
                        key: Key('setup-sec-${c.id}'),
                        klass: c,
                        sessionId: s.sessionId,
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _ClassSections extends ConsumerStatefulWidget {
  const _ClassSections({
    required this.klass,
    required this.sessionId,
    super.key,
  });

  final SetupClass klass;
  final String? sessionId;

  @override
  ConsumerState<_ClassSections> createState() => _ClassSectionsState();
}

class _ClassSectionsState extends ConsumerState<_ClassSections> {
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final saved = ref.levels(context, l10n.academicsSectionsSaved);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/classes/${widget.klass.id}/sections',
            data: {'name': _name.text.trim(), 'session_id': ?widget.sessionId},
          );
      _name.clear();
      messenger.showSnackBar(SnackBar(content: Text(saved)));
      ref
        ..invalidate(_sectionsOfClassProvider)
        ..invalidate(setupSummaryProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final sections =
        ref
            .watch(
              _sectionsOfClassProvider((
                classId: widget.klass.id,
                sessionId: widget.sessionId,
              )),
            )
            .value ??
        const <_Section>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Text(widget.klass.name, style: text.titleSmall),
        Text(
          sections.isEmpty
              ? ref.levels(context, l10n.academicsSectionsEmpty)
              : sections.map((s) => s.name).join(', '),
          style: muted,
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: Key('setup-section-name-${widget.klass.id}'),
                controller: _name,
                decoration: InputDecoration(
                  labelText: ref.levels(context, l10n.academicsSectionsName),
                  hintText: ref.levels(
                    context,
                    l10n.academicsSectionsNamePlaceholder,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            OutlinedButton(
              key: Key('setup-section-add-${widget.klass.id}'),
              onPressed: _busy || _name.text.trim().isEmpty ? null : _add,
              child: Text(ref.levels(context, l10n.academicsSectionsAdd)),
            ),
          ],
        ),
      ],
    );
  }
}

/// Step 5: what was set up and what still needs attention; a class without
/// sections blocks finishing.
class _SummaryStep extends ConsumerWidget {
  const _SummaryStep();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final summary = ref.watch(setupSummaryProvider);
    return summary.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => ErrorView(
        title: apiErrorText(l10n, e),
        retryLabel: l10n.uiErrorRetry,
        onRetry: () => ref.invalidate(setupSummaryProvider),
      ),
      data: (s) {
        String names(Iterable<SetupClass> c) => c.map((x) => x.name).join(', ');
        final noSection = s.classes.where((c) => c.sections == 0);
        final noSubjects = s.classes.where((c) => c.subjects == 0);
        final noStudents = s.classes.where(
          (c) => c.sections > 0 && c.students == 0,
        );
        return AppCard(
          key: const Key('setup-summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.academicsSetupSummaryTitle, style: text.titleMedium),
              if (s.sessionName != null)
                Text(
                  l10n.academicsSetupSummarySession(s.sessionName!),
                  style: muted,
                ),
              if (s.classes.isEmpty)
                Text(
                  ref.levels(context, l10n.academicsSetupSummaryNeedsClass),
                  style: text.bodySmall?.copyWith(color: colors.danger),
                ),
              for (final c in s.classes)
                ListTile(
                  key: Key('summary-${c.id}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(c.name),
                  subtitle: Text(
                    [
                      '${l10n.academicsSetupSummarySubjects} ${OrgTime.number(c.subjects, language)}',
                      '${ref.levels(context, l10n.academicsSetupSummarySections)} ${OrgTime.number(c.sections, language)}',
                      '${l10n.academicsSetupSummaryStudents} ${OrgTime.number(c.students, language)}',
                    ].join(' · '),
                  ),
                  trailing: switch (c) {
                    _ when c.sections == 0 => StatusPill(
                      label: ref.levels(
                        context,
                        l10n.academicsSetupSummaryNeedsSection,
                      ),
                      tone: StatusTone.danger,
                    ),
                    _ when c.subjects == 0 => StatusPill(
                      label: l10n.academicsSetupSummaryNoSubjects,
                      tone: StatusTone.warning,
                    ),
                    _ when c.withoutTeacher.isNotEmpty => StatusPill(
                      label: l10n.academicsSetupSummaryNeedsTeacher,
                      tone: StatusTone.warning,
                    ),
                    _ when c.students == 0 => StatusPill(
                      label: l10n.academicsSetupSummaryNoStudents,
                      tone: StatusTone.warning,
                    ),
                    _ => StatusPill(
                      label: l10n.academicsSetupSummaryReady,
                      tone: StatusTone.success,
                    ),
                  },
                ),
              if (noSection.isNotEmpty)
                Text(
                  ref.levels(
                    context,
                    l10n.academicsSetupSummaryNeedsSectionDetail(
                      names(noSection),
                    ),
                  ),
                  key: const Key('summary-needs-section'),
                  style: text.bodySmall?.copyWith(color: colors.danger),
                ),
              if (noSubjects.isNotEmpty)
                Text(
                  ref.levels(
                    context,
                    l10n.academicsSetupSummaryNoSubjectsDetail(
                      names(noSubjects),
                    ),
                  ),
                  style: muted,
                ),
              if (s.classes.any((c) => c.withoutTeacher.isNotEmpty))
                Text(
                  ref.levels(
                    context,
                    l10n.academicsSetupSummaryNeedsTeacherDetail,
                  ),
                  style: muted,
                ),
              if (noStudents.isNotEmpty)
                Text(
                  ref.levels(
                    context,
                    l10n.academicsSetupSummaryNoStudentsDetail(
                      names(noStudents),
                    ),
                  ),
                  style: muted,
                ),
              if (s.pinMissing)
                Text(l10n.academicsSetupSummaryPinMissing, style: muted),
            ],
          ),
        );
      },
    );
  }
}
