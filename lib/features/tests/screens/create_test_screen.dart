import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';
import 'package:instructor_app/features/tests/screens/question_editor.dart';

typedef Choice = ({String id, String label});

/// The classes the person teaches in (a subject class, or a section's
/// class teacher), as the web's `classesTaughtBy`.
final taughtClassesProvider = FutureProvider.autoDispose<List<Choice>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final me = ref.watch(sessionProvider)?.userId;
  final api = ref.read(apiClientProvider);
  final (classes, sections, offerings) = await (
    api.get('/classes'),
    api.get('/sections'),
    api.get('/offerings'),
  ).wait;
  List<Object?> list(Object? p) => p is List ? p : const [];
  final classOfSection = {
    for (final s in list(sections.payload))
      if (s is Map && s['id'] is String) s['id'] as String: s['class_id'],
  };
  final taught = <Object?>{
    for (final s in list(sections.payload))
      if (s is Map &&
          s['class_teacher'] is Map &&
          (s['class_teacher'] as Map)['id'] == me)
        s['class_id'],
    for (final o in list(offerings.payload))
      if (o is Map && list(o['teachers']).any((t) => t is Map && t['id'] == me))
        classOfSection[o['section_id']],
  };
  return [
    for (final c in list(classes.payload))
      if (c is Map && c['id'] is String && taught.contains(c['id']))
        (id: c['id'] as String, label: (c['class_name'] as String?) ?? ''),
  ];
}, retry: (retryCount, error) => null);

/// A class's subjects the person may set a test in
/// (`GET /classes/:id/subjects/assigned`).
final assignedSubjectsProvider = FutureProvider.autoDispose
    .family<List<Choice>, String>((ref, classId) async {
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get('/classes/$classId/subjects/assigned'))
              .payload;
      return [
        if (p is List)
          for (final s in p)
            if (s is Map && s['subject_id'] is String)
              (
                id: s['subject_id'] as String,
                label: (s['code'] as String?)?.trim().isNotEmpty == true
                    ? '${s['name']} (${(s['code'] as String).trim()})'
                    : (s['name'] as String?) ?? '',
              ),
      ];
    }, retry: (retryCount, error) => null);

/// A personal workspace's subject catalogue (`GET /subjects`).
final catalogSubjectsProvider = FutureProvider.autoDispose<List<Choice>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/subjects')).payload;
  return [
    if (p is List)
      for (final s in p)
        if (s is Map && s['id'] is String)
          (id: s['id'] as String, label: (s['name'] as String?) ?? ''),
  ];
}, retry: (retryCount, error) => null);

/// The proctoring levels the plan allows (`GET /exams/proctoring-options`).
final proctoringLevelsProvider =
    FutureProvider.autoDispose<({List<String> levels, String? fallback})>((
      ref,
    ) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref.read(apiClientProvider).get('/exams/proctoring-options'))
              .payload;
      final j = p is Map ? p : const <String, Object?>{};
      return (
        levels: [
          if (j['levels'] is List)
            for (final l in j['levels'] as List)
              if (l is Map && l['available'] == true && l['level'] is String)
                l['level'] as String,
        ],
        fallback: j['default_level'] as String?,
      );
    }, retry: (retryCount, error) => null);

/// A class's subject classes, for "only this subject class" on publishing.
final classOfferingsProvider = FutureProvider.autoDispose
    .family<List<Choice>, String>((ref, classId) async {
      final api = ref.read(apiClientProvider);
      final (sections, offerings) = await (
        api.get('/sections'),
        api.get('/offerings'),
      ).wait;
      List<Object?> list(Object? p) => p is List ? p : const [];
      final names = {
        for (final s in list(sections.payload))
          if (s is Map && s['class_id'] == classId) s['id']: s['name'],
      };
      return [
        for (final o in list(offerings.payload))
          if (o is Map && names.containsKey(o['section_id']))
            (
              id: o['id'] as String,
              label:
                  '${names[o['section_id']]} · ${o['subject'] is Map ? (o['subject'] as Map)['name'] : ''}',
            ),
      ];
    }, retry: (retryCount, error) => null);

/// The web's /tests/create: build a test in steps — the basics, the
/// questions, and publishing — then save it (`POST /exams`). The test is
/// kept on the device as it is built (Stage 4 plan §7.4) and cleared when
/// saved. Questions are plain text in the app (§7.1).
class CreateTestScreen extends ConsumerStatefulWidget {
  const CreateTestScreen({super.key});

  @override
  ConsumerState<CreateTestScreen> createState() => _CreateTestScreenState();
}

class _CreateTestScreenState extends ConsumerState<CreateTestScreen> {
  late TestDraft _d =
      ref.read(testDraftStoreProvider).load() ?? const TestDraft();
  bool _saving = false;

  void _set(TestDraft d) {
    setState(() => _d = d);
    ref.read(testDraftStoreProvider).save(d);
  }

  bool get _personal => !(ref.read(sessionProvider)?.isOrganization ?? false);

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  /// The web's checks before leaving a step; null when it may go on.
  String? _problem(int step) {
    final l10n = context.l10n;
    switch (step) {
      case 0:
        if (_d.name.trim().isEmpty) return l10n.createTestToastNameRequired;
        if (!_personal && _d.classId == null) {
          return ref.levels(context, l10n.createTestToastClassRequired);
        }
        if (_d.subject == null) return l10n.createTestToastSubjectRequired;
        final minutes = num.tryParse(_d.duration.trim());
        if (minutes == null || minutes < 1) {
          return l10n.createTestToastDurationRequired;
        }
        if (_d.negative && num.tryParse(_d.negativePercent.trim()) == null) {
          return l10n.createTestToastNegativeRequired;
        }
      case 1:
        if (_d.questions.isEmpty) return l10n.createTestToastQuestionRequired;
        if (_d.questions.any((q) => questionProblems(q).isNotEmpty)) {
          return l10n.createTestToastFixQuestions;
        }
        final passing = num.tryParse(_d.passingScore.trim());
        if (passing != null && _d.totalMarks < passing) {
          return l10n.createTestToastMarksBelowPassing(_d.totalMarks, passing);
        }
      default:
        if (!_d.publishNow && (_d.scheduleAt == null || _d.endingAt == null)) {
          return l10n.createTestToastScheduleRequired;
        }
        if (_d.audience == 'selected_class' && _d.classId == null) {
          return ref.levels(context, l10n.createTestToastClassRequired);
        }
    }
    return null;
  }

  void _next() {
    final p = _problem(_d.step);
    if (p != null) {
      _snack(p);
      if (_d.step == 1) setState(() {});
      return;
    }
    _set(_d.copyWith(step: _d.step + 1));
  }

  Future<void> _publish() async {
    final l10n = context.l10n;
    final p = _problem(2);
    if (p != null) {
      _snack(p);
      return;
    }
    final router = GoRouter.of(context);
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/exams', data: _d.toBody(DateTime.now()));
      await ref.read(testDraftStoreProvider).clear();
      final id = r.payload is Map ? (r.payload! as Map)['id'] as String? : null;
      _snack(l10n.createTestFooterPublish);
      router.go(id == null ? AppRoutes.tests : '${AppRoutes.tests}/$id');
    } on ApiException catch (e) {
      _snack(apiErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    await ref.read(testDraftStoreProvider).clear();
    if (mounted) context.go(AppRoutes.tests);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final steps = [
      l10n.createTestStepsBasicInfo,
      l10n.createTestStepsQuestions,
      l10n.createTestStepsPublish,
    ];
    final step = _d.step.clamp(0, steps.length - 1);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.createTestTitle, style: text.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final (i, label) in steps.indexed)
                  ChoiceChip(
                    key: Key('create-step-$i'),
                    label: Text(label),
                    selected: step == i,
                    // Earlier steps can be revisited; later ones need the
                    // checks of each step before them.
                    onSelected: i < step
                        ? (_) => _set(_d.copyWith(step: i))
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            switch (step) {
              0 => _BasicsStep(draft: _d, onChanged: _set),
              1 => _QuestionsStep(draft: _d, onChanged: _set),
              _ => _PublishStep(draft: _d, onChanged: _set),
            },
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                TextButton(
                  key: const Key('create-cancel'),
                  onPressed: _cancel,
                  child: Text(l10n.createTestFooterCancel),
                ),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    if (step > 0)
                      OutlinedButton(
                        key: const Key('create-back'),
                        onPressed: () => _set(_d.copyWith(step: step - 1)),
                        child: Text(l10n.createTestFooterBack),
                      ),
                    if (step < steps.length - 1)
                      FilledButton(
                        key: const Key('create-next'),
                        onPressed: _next,
                        child: Text(l10n.createTestFooterNext),
                      )
                    else
                      FilledButton(
                        key: const Key('create-publish'),
                        onPressed: _saving ? null : _publish,
                        child: Text(
                          _saving
                              ? l10n.createTestFooterPublishing
                              : l10n.createTestFooterPublish,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BasicsStep extends ConsumerWidget {
  const _BasicsStep({required this.draft, required this.onChanged});

  final TestDraft draft;
  final ValueChanged<TestDraft> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final d = draft;
    final personal = !(ref.watch(sessionProvider)?.isOrganization ?? false);
    final classes = personal ? null : ref.watch(taughtClassesProvider);
    final subjects = personal
        ? ref.watch(catalogSubjectsProvider)
        : d.classId == null
        ? null
        : ref.watch(assignedSubjectsProvider(d.classId!));
    final levels = ref.watch(proctoringLevelsProvider).value;
    // One subject in the class: it is chosen for them, as on the web.
    final list = subjects?.value;
    if (!personal &&
        list != null &&
        list.length == 1 &&
        d.subject?.id != list.first.id) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => onChanged(
          d.copyWith(
            subjects: [DraftSubject(id: list.first.id, name: list.first.label)],
          ),
        ),
      );
    }
    void pickSubject(String? id) {
      final c = list?.where((s) => s.id == id).firstOrNull;
      if (c == null) return;
      final keep = d.subject?.questions ?? const <DraftQuestion>[];
      onChanged(
        d.copyWith(
          subjects: [DraftSubject(id: c.id, name: c.label, questions: keep)],
        ),
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Field(
            fieldKey: 'create-name',
            label: l10n.createTestBasicName,
            hint: l10n.createTestBasicNamePlaceholder,
            value: d.name,
            maxLength: 200,
            onChanged: (v) => onChanged(d.copyWith(name: v)),
          ),
          if (!personal)
            ...?classes?.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [Text(apiErrorText(l10n, e))],
              data: (cs) => cs.isEmpty
                  ? [
                      Text(
                        ref.levels(context, l10n.createTestBasicNoClass),
                        key: const Key('create-no-class'),
                        style: text.bodySmall?.copyWith(color: colors.danger),
                      ),
                    ]
                  : [
                      DropdownButtonFormField<String>(
                        key: const Key('create-class'),
                        initialValue: cs.any((c) => c.id == d.classId)
                            ? d.classId
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: ref.levels(
                            context,
                            l10n.createTestBasicClass,
                          ),
                          hintText: ref.levels(
                            context,
                            l10n.createTestBasicSelectClass,
                          ),
                        ),
                        items: [
                          for (final c in cs)
                            DropdownMenuItem(value: c.id, child: Text(c.label)),
                        ],
                        onChanged: (v) => onChanged(
                          d.copyWith(
                            classId: v,
                            clearOffering: true,
                            subjects: const [],
                          ),
                        ),
                      ),
                    ],
            ),
          const SizedBox(height: AppSpacing.sm),
          if (subjects == null)
            Text(
              ref.levels(context, l10n.createTestBasicPickClassFirst),
              style: muted,
            )
          else
            ...subjects.when(
              loading: () => [
                Text(l10n.createTestBasicLoadingSubjects, style: muted),
              ],
              error: (e, _) => [Text(apiErrorText(l10n, e))],
              data: (ss) => ss.isEmpty
                  ? [
                      Text(
                        ref.levels(context, l10n.createTestBasicNoSubject),
                        key: const Key('create-no-subject'),
                        style: text.bodySmall?.copyWith(color: colors.danger),
                      ),
                    ]
                  : [
                      DropdownButtonFormField<String>(
                        key: const Key('create-subject'),
                        initialValue: ss.any((s) => s.id == d.subject?.id)
                            ? d.subject?.id
                            : null,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: personal
                              ? l10n.createTestBasicSubject
                              : l10n.createTestBasicOrgSubject,
                          hintText: l10n.createTestBasicSelectSubject,
                        ),
                        items: [
                          for (final s in ss)
                            DropdownMenuItem(value: s.id, child: Text(s.label)),
                        ],
                        onChanged: pickSubject,
                      ),
                    ],
            ),
          const SizedBox(height: AppSpacing.sm),
          _Field(
            fieldKey: 'create-duration',
            label: l10n.createTestBasicDuration,
            hint: l10n.createTestBasicDurationPlaceholder,
            suffix: l10n.createTestBasicMinutes,
            value: d.duration,
            number: true,
            onChanged: (v) => onChanged(d.copyWith(duration: v)),
          ),
          _Field(
            fieldKey: 'create-passing',
            label: l10n.createTestBasicPassingScore,
            hint: l10n.createTestBasicPassingPlaceholder,
            value: d.passingScore,
            number: true,
            onChanged: (v) => onChanged(d.copyWith(passingScore: v)),
          ),
          SwitchListTile(
            key: const Key('create-negative'),
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.createTestBasicNegativeMarking),
            subtitle: Text(l10n.createTestBasicNegativeMarkingHint),
            value: d.negative,
            onChanged: (v) => onChanged(d.copyWith(negative: v)),
          ),
          if (d.negative)
            _Field(
              fieldKey: 'create-negative-percent',
              label: l10n.createTestBasicNegativePercent,
              suffix: '%',
              value: d.negativePercent,
              number: true,
              onChanged: (v) => onChanged(d.copyWith(negativePercent: v)),
            ),
          if (levels != null && levels.levels.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(l10n.createTestProctoringTitle, style: text.titleSmall),
            Text(l10n.createTestProctoringIntro, style: muted),
            DropdownButtonFormField<String>(
              key: const Key('create-proctoring'),
              initialValue: levels.levels.contains(d.proctoringLevel)
                  ? d.proctoringLevel
                  : levels.levels.contains(levels.fallback)
                  ? levels.fallback
                  : levels.levels.last,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.createTestProctoringLevel,
              ),
              items: [
                for (final l in levels.levels)
                  DropdownMenuItem(value: l, child: Text(_levelName(l10n, l))),
              ],
              onChanged: (v) => onChanged(d.copyWith(proctoringLevel: v)),
            ),
          ],
        ],
      ),
    );
  }
}

String _levelName(AppLocalizations l10n, String level) => switch (level) {
  'OFF' => l10n.createTestProctoringLevelsOFF,
  'LIGHT' => l10n.createTestProctoringLevelsLIGHT,
  _ => l10n.createTestProctoringLevelsSTRICT,
};

/// A text field that keeps its own controller (the draft is rebuilt on
/// every change).
class _Field extends StatefulWidget {
  const _Field({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.suffix,
    this.number = false,
    this.maxLength,
  });

  final String fieldKey;
  final String label;
  final String? hint;
  final String? suffix;
  final String value;
  final bool number;
  final int? maxLength;
  final ValueChanged<String> onChanged;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final _c = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    key: Key(widget.fieldKey),
    controller: _c,
    maxLength: widget.maxLength,
    keyboardType: widget.number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      suffixText: widget.suffix,
    ),
    onChanged: widget.onChanged,
  );
}

class _QuestionsStep extends StatelessWidget {
  const _QuestionsStep({required this.draft, required this.onChanged});

  final TestDraft draft;
  final ValueChanged<TestDraft> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final subject = draft.subject;
    if (subject == null) {
      return Text(l10n.createTestQuestionsSubjectFirst);
    }
    void setQuestions(List<DraftQuestion> qs) =>
        onChanged(draft.copyWith(subjects: [subject.copyWith(questions: qs)]));
    final qs = subject.questions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(l10n.createTestQuestionsTitle, style: text.titleMedium),
        Text(
          '${subject.name} · ${l10n.createTestQuestionsAdded(qs.length)} · '
          '${l10n.createTestQuestionsTotalMarks(subject.totalMarks)}',
          key: const Key('create-questions-summary'),
          style: text.bodySmall,
        ),
        for (final (i, q) in qs.indexed) ...[
          const SizedBox(height: AppSpacing.sm),
          QuestionEditor(
            key: ValueKey(q.id),
            number: i + 1,
            question: q,
            onChanged: (next) =>
                setQuestions([for (final x in qs) x.id == q.id ? next : x]),
            onDelete: () => setQuestions([
              for (final x in qs)
                if (x.id != q.id) x,
            ]),
            onDuplicate: () {
              final copy = DraftQuestion.fromJson({
                ...q.toJson(),
                'id': newId(),
                'options': [
                  for (final o in q.options) {...o.toJson(), 'id': newId()},
                ],
                'answer': <String>[],
              });
              setQuestions([...qs.take(i + 1), copy, ...qs.skip(i + 1)]);
            },
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: FilledButton.icon(
            key: const Key('create-add-question'),
            icon: const Icon(Icons.add),
            label: Text(l10n.createTestQuestionsAddQuestion),
            onPressed: () =>
                setQuestions([...qs, DraftQuestion.multipleChoice()]),
          ),
        ),
      ],
    );
  }
}

class _PublishStep extends ConsumerWidget {
  const _PublishStep({required this.draft, required this.onChanged});

  final TestDraft draft;
  final ValueChanged<TestDraft> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final d = draft;
    final personal = !(ref.watch(sessionProvider)?.isOrganization ?? false);
    final classes = personal ? null : ref.watch(taughtClassesProvider).value;
    final offerings = d.classId == null
        ? null
        : ref.watch(classOfferingsProvider(d.classId!)).value;
    Widget when(
      String label,
      DateTime? value,
      ValueChanged<DateTime> set,
      Key key,
    ) {
      final wall = value == null ? null : OrgTime.wallClock(value);
      final day = wall == null ? null : DateField.format(wall);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: text.labelLarge),
          Row(
            children: [
              Expanded(
                child: DateField(
                  key: key,
                  label: l10n.createTestPublishDate,
                  value: day,
                  onChanged: (v) {
                    final t = wall ?? DateTime.utc(2000, 1, 1, 9);
                    set(_fromWall(v, t.hour, t.minute));
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: OutlinedButton.icon(
                  key: Key('${(key as ValueKey).value}-time'),
                  icon: const Icon(Icons.schedule),
                  label: Text(
                    wall == null
                        ? l10n.createTestPublishTime
                        : OrgTime.timeOfDay(
                            '${wall.hour}:${wall.minute.toString().padLeft(2, '0')}',
                            language,
                          ),
                  ),
                  onPressed: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay(
                        hour: wall?.hour ?? 9,
                        minute: wall?.minute ?? 0,
                      ),
                    );
                    if (picked == null) return;
                    set(
                      _fromWall(
                        day ?? OrgTime.today(),
                        picked.hour,
                        picked.minute,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.createTestPublishTiming, style: text.titleSmall),
              RadioGroup<bool>(
                groupValue: d.publishNow,
                onChanged: (v) => onChanged(d.copyWith(publishNow: v)),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      key: const Key('publish-now'),
                      contentPadding: EdgeInsets.zero,
                      value: true,
                      title: Text(l10n.createTestPublishNow),
                      subtitle: Text(l10n.createTestPublishNowDetail),
                    ),
                    RadioListTile<bool>(
                      key: const Key('publish-later'),
                      contentPadding: EdgeInsets.zero,
                      value: false,
                      title: Text(l10n.createTestPublishLater),
                      subtitle: Text(l10n.createTestPublishLaterDetail),
                    ),
                  ],
                ),
              ),
              if (!d.publishNow) ...[
                when(
                  l10n.createTestPublishStartsAt,
                  d.scheduleAt,
                  (v) => onChanged(d.copyWith(scheduleAt: v)),
                  const ValueKey('publish-start'),
                ),
                const SizedBox(height: AppSpacing.sm),
                when(
                  l10n.createTestPublishEndsAt,
                  d.endingAt,
                  (v) => onChanged(d.copyWith(endingAt: v)),
                  const ValueKey('publish-end'),
                ),
                Text(l10n.createTestPublishTimeZoneNote, style: muted),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.createTestPublishAudience, style: text.titleSmall),
              if (personal)
                DropdownButtonFormField<String>(
                  key: const Key('publish-audience'),
                  initialValue: d.audience,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.createTestPublishAudienceLabel,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'anyone',
                      child: Text(l10n.createTestPublishAnyone),
                    ),
                    DropdownMenuItem(
                      value: 'selected_class',
                      child: Text(
                        ref.levels(
                          context,
                          l10n.createTestPublishClassAudience,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => onChanged(d.copyWith(audience: v)),
                )
              else ...[
                Text(
                  ref.levels(context, l10n.createTestPublishClass),
                  style: muted,
                ),
                Text(
                  classes?.where((c) => c.id == d.classId).firstOrNull?.label ??
                      l10n.createTestPublishFromBasicInfo,
                  key: const Key('publish-class'),
                  style: text.bodyLarge,
                ),
              ],
              if (d.audience == 'selected_class' &&
                  offerings != null &&
                  offerings.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('publish-offering'),
                  initialValue: offerings.any((o) => o.id == d.offeringId)
                      ? d.offeringId
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: ref.levels(
                      context,
                      l10n.createTestPublishSubjectClass,
                    ),
                    helperText: ref.levels(
                      context,
                      l10n.createTestPublishSubjectClassHint,
                    ),
                    helperMaxLines: 3,
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      child: Text(
                        ref.levels(context, l10n.createTestPublishWholeClass),
                      ),
                    ),
                    for (final o in offerings)
                      DropdownMenuItem<String?>(
                        value: o.id,
                        child: Text(o.label),
                      ),
                  ],
                  onChanged: (v) => onChanged(
                    v == null
                        ? d.copyWith(clearOffering: true)
                        : d.copyWith(offeringId: v),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A school day and a clock time in the organisation's time zone, as an
/// instant.
DateTime _fromWall(String day, int hour, int minute) {
  final p = day.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2], hour, minute).subtract(OrgTime.offset);
}
