import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/ielts/data/courses.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/organization/screens/attendance_settings_screen.dart';

String courseStatusName(AppLocalizations l10n, String s) => switch (s) {
  'RUNNING' => l10n.ieltsCoursesStatusesRUNNING,
  'ENDED' => l10n.ieltsCoursesStatusesENDED,
  _ => l10n.ieltsCoursesStatusesUPCOMING,
};

StatusTone courseStatusTone(String s) => switch (s) {
  'RUNNING' => StatusTone.success,
  'ENDED' => StatusTone.neutral,
  _ => StatusTone.info,
};

String _dates(IeltsCourse c, String lang) {
  String d(String v) {
    final t = DateTime.tryParse(v);
    return t == null ? v : OrgTime.schoolDay(v, lang);
  }

  return '${d(c.startDate)} – ${d(c.endDate)}';
}

String _teacherLine(AppLocalizations l10n, IeltsCourse c) => [
  for (final m in c.teachers)
    '${ieltsModuleShort(l10n, m.module)}: '
        '${m.teachers.isEmpty ? l10n.ieltsCoursesNoTeacher : m.teachers.map((t) => t.name ?? '—').join(', ')}',
].join(' · ');

/// The organisation's teachers who can teach a course module.
final _courseTeachersProvider = FutureProvider.autoDispose
    .family<List<({String id, String name})>, String>((ref, org) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get('/organizations/$org/assignable-teachers'))
              .payload;
      return [
        if (p is List)
          for (final m in p)
            if (m is Map && m['user'] is Map)
              (
                id: '${(m['user'] as Map)['id']}',
                name:
                    ((m['user'] as Map)['full_name'] as String?) ??
                    ((m['user'] as Map)['phone'] as String?) ??
                    '—',
              ),
      ];
    }, retry: (retryCount, error) => null);

/// The web's /ielts/courses (P12-05): each course with its branch, dates,
/// status, modules, students against seats and teachers. Owners, admins,
/// branch managers and solo trainers make, change and remove them (a
/// course with students can't be removed); teachers read the ones they
/// teach. Students and the timetable are on the course's class page.
class IeltsCoursesScreen extends ConsumerStatefulWidget {
  const IeltsCoursesScreen({super.key});

  @override
  ConsumerState<IeltsCoursesScreen> createState() => _IeltsCoursesScreenState();
}

class _IeltsCoursesScreenState extends ConsumerState<IeltsCoursesScreen> {
  String? _status;

  bool get _canManage {
    final s = ref.read(sessionProvider);
    if (s == null) return false;
    return !s.isOrganization ||
        const {'OWNER', 'ADMIN', 'BRANCH_MANAGER'}.contains(s.memberRole);
  }

  Future<void> _edit(IeltsCourse? course) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _CourseForm(course: course),
    );
    if (saved == true) ref.invalidate(ieltsCoursesProvider);
  }

  Future<void> _remove(IeltsCourse c) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.ieltsCoursesRemoveTitle(c.title)),
        content: Text(l10n.ieltsCoursesRemoveDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.ieltsCoursesCancel),
          ),
          FilledButton(
            key: const Key('course-remove-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(d).danger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.ieltsCoursesRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).delete('/ielts/courses/${c.id}');
      messenger.showSnackBar(SnackBar(content: Text(l10n.ieltsCoursesRemoved)));
      ref.invalidate(ieltsCoursesProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final manage = _canManage;
    final branchManager =
        ref.watch(sessionProvider)?.memberRole == 'BRANCH_MANAGER';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ref
            .watch(ieltsCoursesProvider)
            .when(
              loading: () =>
                  LoadingView(semanticsLabel: l10n.ieltsCoursesTitle),
              error: (e, _) => ErrorView(
                title: l10n.ieltsCoursesLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(ieltsCoursesProvider),
              ),
              data: (all) {
                final shown = [
                  for (final c in all)
                    if (_status == null || c.status == _status) c,
                ];
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(ieltsCoursesProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      Text(l10n.ieltsCoursesTitle, style: text.headlineSmall),
                      Text(l10n.ieltsCoursesIntro, style: muted),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (manage)
                            FilledButton.icon(
                              key: const Key('course-new'),
                              icon: const Icon(Icons.add),
                              label: Text(l10n.ieltsCoursesNew),
                              onPressed: () => _edit(null),
                            ),
                          for (final s in [
                            null,
                            'RUNNING',
                            'UPCOMING',
                            'ENDED',
                          ])
                            ChoiceChip(
                              key: Key('course-filter-${s ?? 'all'}'),
                              label: Text(
                                s == null
                                    ? l10n.ieltsCoursesAllStatuses
                                    : courseStatusName(l10n, s),
                              ),
                              selected: _status == s,
                              onSelected: (_) => setState(() => _status = s),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      if (shown.isEmpty)
                        EmptyView(
                          icon: Icons.school_outlined,
                          title: l10n.ieltsCoursesEmpty,
                          message: manage ? l10n.ieltsCoursesEmptyHint : null,
                        )
                      else
                        for (final c in shown)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AppCard(
                              key: Key('course-${c.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          c.title,
                                          style: text.titleMedium,
                                        ),
                                      ),
                                      StatusPill(
                                        label: courseStatusName(l10n, c.status),
                                        tone: courseStatusTone(c.status),
                                      ),
                                    ],
                                  ),
                                  if (branchManager ||
                                      (c.branch != null &&
                                          !c.branch!.isDefault))
                                    Text(
                                      c.branch?.name ??
                                          l10n.ieltsCoursesMainBranch,
                                      style: muted,
                                    ),
                                  Text(_dates(c, lang), style: muted),
                                  Text(
                                    c.modules
                                        .map((m) => ieltsModuleShort(l10n, m))
                                        .join(', '),
                                    style: text.bodySmall,
                                  ),
                                  Text(
                                    '${l10n.ieltsCoursesStudents}: '
                                    '${c.seatLimit == null ? OrgTime.number(c.students, lang) : l10n.ieltsCoursesSeatsTaken(c.students, c.seatLimit!)}',
                                    style: text.bodySmall,
                                  ),
                                  if (c.teachers.isNotEmpty)
                                    Text(
                                      _teacherLine(l10n, c),
                                      style: text.bodySmall,
                                    ),
                                  Wrap(
                                    spacing: AppSpacing.xs,
                                    children: [
                                      TextButton(
                                        key: Key('course-class-${c.id}'),
                                        onPressed: () => context.push(
                                          '/classes/details/${c.classId}',
                                        ),
                                        child: Text(
                                          l10n.ieltsCoursesStudentsAndTimetable,
                                        ),
                                      ),
                                      if (manage)
                                        TextButton(
                                          key: Key('course-edit-${c.id}'),
                                          onPressed: () => _edit(c),
                                          child: Text(l10n.ieltsCoursesEdit),
                                        ),
                                      if (manage && c.students == 0)
                                        TextButton(
                                          key: Key('course-remove-${c.id}'),
                                          style: TextButton.styleFrom(
                                            foregroundColor: colors.danger,
                                          ),
                                          onPressed: () => _remove(c),
                                          child: Text(l10n.ieltsCoursesRemove),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}

/// Make or change a course (the web's drawer).
class _CourseForm extends ConsumerStatefulWidget {
  const _CourseForm({this.course});

  final IeltsCourse? course;

  @override
  ConsumerState<_CourseForm> createState() => _CourseFormState();
}

class _CourseFormState extends ConsumerState<_CourseForm> {
  late final _title = TextEditingController(text: widget.course?.title ?? '');
  late final _seats = TextEditingController(
    text: widget.course?.seatLimit?.toString() ?? '',
  );
  late String? _start = widget.course?.startDate;
  late String? _end = widget.course?.endDate;
  late final _modules = <String>{...?widget.course?.modules};
  late String? _branch = widget.course?.branch?.isDefault == false
      ? widget.course!.branch!.id
      : null;
  late final _teachers = <String, String>{
    for (final m in [...?widget.course?.teachers])
      m.module: m.teachers.isEmpty ? '' : m.teachers.first.id,
  };
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _seats.dispose();
    super.dispose();
  }

  bool get _ready =>
      _title.text.trim().isNotEmpty &&
      _start != null &&
      _end != null &&
      _modules.isNotEmpty;

  Future<void> _save(List<({String id, String name})>? teachers) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    final body = courseBody(
      title: _title.text,
      startDate: _start!,
      endDate: _end!,
      modules: _modules.toList(),
      seatLimit: _seats.text,
      branchId: _branch,
      teachers: teachers == null || teachers.isEmpty ? null : _teachers,
    );
    try {
      final api = ref.read(apiClientProvider);
      if (widget.course == null) {
        await api.post('/ielts/courses', data: body);
      } else {
        await api.patch('/ielts/courses/${widget.course!.id}', data: body);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            widget.course == null
                ? l10n.ieltsCoursesCreated
                : l10n.ieltsCoursesSaved,
          ),
        ),
      );
      nav.pop(true);
    } catch (e) {
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
    final s = ref.watch(sessionProvider);
    final org = s?.isOrganization == true ? s?.organizationId : null;
    final branchManager = s?.memberRole == 'BRANCH_MANAGER';
    // Branches and teachers: an organisation's owners and admins (the web).
    final lists = org != null && !branchManager;
    final branches = lists
        ? [
            for (final b
                in ref.watch(branchesProvider).value ?? const <Branch>[])
              if (!b.isDefault) b,
          ]
        : const <Branch>[];
    final teachers = lists
        ? ref.watch(_courseTeachersProvider(org)).value
        : null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.course == null
                    ? l10n.ieltsCoursesNew
                    : l10n.ieltsCoursesEdit,
                style: text.titleLarge,
              ),
              Text(l10n.ieltsCoursesFormIntro, style: muted),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('course-title'),
                controller: _title,
                maxLength: 150,
                decoration: InputDecoration(
                  labelText: l10n.ieltsCoursesCourseTitle,
                  helperText: l10n.ieltsCoursesCourseTitleHint,
                  helperMaxLines: 3,
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (branches.isNotEmpty)
                DropdownButtonFormField<String?>(
                  key: const Key('course-branch'),
                  initialValue: _branch,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.ieltsCoursesBranch,
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(l10n.ieltsCoursesMainBranch),
                    ),
                    for (final b in branches)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text(b.name ?? l10n.ieltsCoursesMainBranch),
                      ),
                  ],
                  onChanged: (v) => setState(() => _branch = v),
                ),
              const SizedBox(height: AppSpacing.sm),
              DateField(
                key: const Key('course-start'),
                label: l10n.ieltsCoursesStartDate,
                value: _start,
                onChanged: (v) => setState(() => _start = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              DateField(
                key: const Key('course-end'),
                label: l10n.ieltsCoursesEndDate,
                value: _end,
                min: _start,
                onChanged: (v) => setState(() => _end = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.ieltsCoursesModules, style: text.titleSmall),
              for (final m in ieltsModules)
                CheckboxListTile(
                  key: Key('course-module-$m'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(ieltsModuleShort(l10n, m)),
                  value: _modules.contains(m),
                  onChanged: (v) => setState(
                    () => v == true ? _modules.add(m) : _modules.remove(m),
                  ),
                ),
              TextField(
                key: const Key('course-seats'),
                controller: _seats,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.ieltsCoursesSeatLimit,
                  helperText: l10n.ieltsCoursesSeatLimitHint,
                  helperMaxLines: 3,
                ),
              ),
              if (teachers != null && teachers.isNotEmpty)
                for (final m in ieltsModules)
                  if (_modules.contains(m))
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.sm),
                      child: DropdownButtonFormField<String>(
                        key: Key('course-teacher-$m'),
                        initialValue: teachers.any((t) => t.id == _teachers[m])
                            ? _teachers[m]
                            : '',
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.ieltsCoursesTeacherFor(
                            ieltsModuleShort(l10n, m),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(l10n.ieltsCoursesNoTeacher),
                          ),
                          for (final t in teachers)
                            DropdownMenuItem(value: t.id, child: Text(t.name)),
                        ],
                        onChanged: (v) =>
                            setState(() => _teachers[m] = v ?? ''),
                      ),
                    ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.ieltsCoursesStudentsHint, style: muted),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.ieltsCoursesCancel),
                  ),
                  FilledButton(
                    key: const Key('course-save'),
                    onPressed: _ready && !_saving
                        ? () => _save(teachers)
                        : null,
                    child: Text(l10n.ieltsCoursesSave),
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

/// The web's /ielts/my-courses: a student's courses with dates, status and
/// teachers; the timetable is on the course's class page.
class MyIeltsCoursesScreen extends ConsumerWidget {
  const MyIeltsCoursesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ref
            .watch(ieltsCoursesProvider)
            .when(
              loading: () =>
                  LoadingView(semanticsLabel: l10n.ieltsCoursesMyTitle),
              error: (e, _) => ErrorView(
                title: l10n.ieltsCoursesLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(ieltsCoursesProvider),
              ),
              data: (all) => RefreshIndicator(
                onRefresh: () => ref.refresh(ieltsCoursesProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(l10n.ieltsCoursesMyTitle, style: text.headlineSmall),
                    Text(l10n.ieltsCoursesMyIntro, style: muted),
                    const SizedBox(height: AppSpacing.md),
                    if (all.isEmpty)
                      EmptyView(
                        icon: Icons.school_outlined,
                        title: l10n.ieltsCoursesMyEmpty,
                      )
                    else
                      for (final c in all)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                          child: AppCard(
                            key: Key('my-course-${c.id}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        c.title,
                                        style: text.titleMedium,
                                      ),
                                    ),
                                    StatusPill(
                                      label: courseStatusName(l10n, c.status),
                                      tone: courseStatusTone(c.status),
                                    ),
                                  ],
                                ),
                                Text(_dates(c, lang), style: muted),
                                for (final m in c.teachers)
                                  Text(
                                    '${ieltsModuleShort(l10n, m.module)}: '
                                    '${m.teachers.isEmpty ? l10n.ieltsCoursesNoTeacher : m.teachers.map((t) => t.name ?? '—').join(', ')}',
                                    style: text.bodySmall,
                                  ),
                                TextButton(
                                  key: Key('my-course-class-${c.id}'),
                                  onPressed: () => context.push(
                                    '/classes/details/${c.classId}',
                                  ),
                                  child: Text(
                                    l10n.ieltsCoursesStudentsAndTimetable,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
      ),
    );
  }
}
