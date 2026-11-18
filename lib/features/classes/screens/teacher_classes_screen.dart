import 'package:flutter/services.dart';
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
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/classes/data/teacher_classes.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// A member's name as the web shows it: their name, else their contact,
/// else "Student" and their ID, else "Invited student".
String memberName(BuildContext context, ClassMember m) {
  final l10n = context.l10n;
  return m.name ??
      m.contact ??
      (m.publicId != null
          ? l10n.classesRosterStudentWithId(m.publicId!)
          : l10n.classesRosterInvitedStudent);
}

/// Shows the class's join link with Copy (the web's Share class dialog).
Future<void> showShareClass(
  BuildContext context,
  WidgetRef ref,
  TeacherClass c, {
  bool created = false,
  int invited = 0,
}) {
  final link = classJoinLink(c.id);
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final l10n = dialogContext.l10n;
      final text = Theme.of(dialogContext).textTheme;
      final colors = AppColors.of(dialogContext);
      return AlertDialog(
        title: Text(
          ref.levels(
            dialogContext,
            created
                ? l10n.classesShareModalCreated
                : l10n.classesShareModalTitle,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              created
                  ? l10n.classesShareModalCreatedDetail(c.name, invited)
                  : l10n.classesShareModalShareDetail(c.name),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              ref.levels(dialogContext, l10n.classesShareModalAnyone),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              ref.levels(dialogContext, l10n.classesShareModalLink),
              style: text.labelMedium,
            ),
            SelectableText(link, key: const Key('share-link')),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('share-copy'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (!dialogContext.mounted) return;
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(
                    ref.levels(
                      dialogContext,
                      l10n.classesShareModalCopiedDetail,
                    ),
                  ),
                ),
              );
            },
            child: Text(l10n.classesShareModalCopy),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.classesShareModalDone),
          ),
        ],
      );
    },
  );
}

/// The web's /classes for a teacher: their classes in this workspace with
/// students and tests taken, searchable; Create class in a personal
/// workspace (schools create classes in their setup); each opens its page.
class TeacherClassesScreen extends ConsumerStatefulWidget {
  const TeacherClassesScreen({super.key});

  @override
  ConsumerState<TeacherClassesScreen> createState() =>
      _TeacherClassesScreenState();
}

class _TeacherClassesScreenState extends ConsumerState<TeacherClassesScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final created = await Navigator.of(context, rootNavigator: true)
        .push<({TeacherClass c, int invited})>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => const CreateClassScreen(),
          ),
        );
    if (created == null || !mounted) return;
    ref.invalidate(teacherClassesProvider);
    await showShareClass(
      context,
      ref,
      created.c,
      created: true,
      invited: created.invited,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    final canCreate = session?.isOrganization != true;
    final classes = ref.watch(teacherClassesProvider);
    final needle = _search.text.trim().toLowerCase();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(teacherClassesProvider);
            await ref
                .read(teacherClassesProvider.future)
                .then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                ref.levels(context, l10n.classesTitle),
                style: text.headlineSmall,
              ),
              Text(
                ref.levels(context, l10n.classesIntro),
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('classes-search'),
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: ref.levels(context, l10n.classesSearch),
                        prefixIcon: const Icon(Icons.search),
                      ),
                    ),
                  ),
                  if (canCreate) ...[
                    const SizedBox(width: AppSpacing.sm),
                    FilledButton.icon(
                      key: const Key('create-class'),
                      onPressed: _create,
                      icon: const Icon(Icons.add),
                      label: Text(ref.levels(context, l10n.classesCreate)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ...classes.when(
                loading: () => [
                  SizedBox(
                    height: 240,
                    child: LoadingView(semanticsLabel: l10n.classesTitle),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 300,
                    child: ErrorView(
                      title: ref.levels(context, l10n.classesNotFound),
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () => ref.invalidate(teacherClassesProvider),
                    ),
                  ),
                ],
                data: (list) {
                  final shown = [
                    for (final c in list)
                      if (needle.isEmpty ||
                          c.name.toLowerCase().contains(needle))
                        c,
                  ];
                  if (shown.isEmpty) {
                    return [
                      SizedBox(
                        height: 280,
                        child: EmptyView(
                          icon: Icons.class_outlined,
                          title: ref.levels(
                            context,
                            needle.isEmpty
                                ? l10n.classesEmpty
                                : l10n.classesNoMatch,
                          ),
                          message: needle.isEmpty && canCreate
                              ? ref.levels(context, l10n.classesEmptyTeacher)
                              : null,
                        ),
                      ),
                    ];
                  }
                  return [
                    for (final c in shown) ...[
                      AppCard(
                        key: Key('class-${c.id}'),
                        onTap: () => context.push(
                          '${AppRoutes.classes}/details/${c.id}',
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(c.name, style: text.titleMedium),
                            Text(
                              c.lastTestAt == null
                                  ? l10n.classesNoTestYet
                                  : l10n.classesLastTest(
                                      OrgTime.dateTime(c.lastTestAt!, language),
                                    ),
                              style: text.bodySmall?.copyWith(
                                color: colors.inkMuted,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.lg,
                              children: [
                                Text(
                                  '${l10n.classesStudents}: '
                                  '${OrgTime.number(c.members.length, language)}',
                                  style: text.bodySmall,
                                ),
                                Text(
                                  '${l10n.classesTestsTaken}: '
                                  '${OrgTime.number(c.testsTaken, language)}',
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Typing the students to invite: email, phone or Student ID, one at a
/// time; invalid ones are shown in red and can be removed. Duplicates are
/// refused, as on the web.
class InviteField extends StatefulWidget {
  const InviteField({
    required this.entries,
    required this.onChanged,
    super.key,
  });

  final List<String> entries;
  final ValueChanged<List<String>> onChanged;

  @override
  State<InviteField> createState() => _InviteFieldState();
}

class _InviteFieldState extends State<InviteField> {
  final _input = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _add() {
    final l10n = context.l10n;
    final v = _input.text.trim();
    if (v.isEmpty) return;
    final problem = inviteProblem(v);
    if (problem != null) {
      setState(
        () => _problem = switch (problem) {
          'email' => l10n.classesToastInvalidEmail,
          'phone' => l10n.classesToastInvalidPhone,
          _ => l10n.classesToastInvalidInput,
        },
      );
      return;
    }
    final key = normalizeInvite(v);
    if (widget.entries.map(normalizeInvite).contains(key)) {
      setState(() => _problem = l10n.classesToastDuplicate);
      return;
    }
    widget.onChanged([...widget.entries, key]);
    setState(() {
      _problem = null;
      _input.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('invite-input'),
                controller: _input,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  labelText: l10n.classesFormStudentsLabel,
                  hintText: l10n.classesFormStudentsPlaceholder,
                  helperText: l10n.classesFormStudentsHint,
                  helperMaxLines: 3,
                  errorText: _problem,
                  errorMaxLines: 3,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: OutlinedButton(
                key: const Key('invite-add'),
                onPressed: _add,
                child: Text(l10n.classesFormAdd),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (i, e) in widget.entries.indexed)
              InputChip(
                key: Key('invite-$i'),
                label: Text(e),
                onDeleted: () => widget.onChanged([
                  for (final (j, x) in widget.entries.indexed)
                    if (j != i) x,
                ]),
              ),
          ],
        ),
      ],
    );
  }
}

/// Create class (the web's /classes/create): name, description, and the
/// students to invite. Returns the new class and how many were invited.
class CreateClassScreen extends ConsumerStatefulWidget {
  const CreateClassScreen({super.key});

  @override
  ConsumerState<CreateClassScreen> createState() => _CreateClassScreenState();
}

class _CreateClassScreenState extends ConsumerState<CreateClassScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  List<String> _students = const [];
  bool _saving = false;
  String? _nameProblem;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(
        () => _nameProblem = ref.levels(context, l10n.classesToastNameRequired),
      );
      return;
    }
    setState(() {
      _saving = true;
      _nameProblem = null;
      _problem = null;
    });
    try {
      final c = await ref
          .read(teacherClassesRepositoryProvider)
          .create(
            name: name,
            description: _description.text.trim(),
            students: _students,
          );
      if (!mounted) return;
      if (c == null) throw const FormatException('class');
      Navigator.of(context).pop((c: c, invited: _students.length));
    } catch (e) {
      if (!mounted) return;
      if (!await handleCommonApiError(
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
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(ref.levels(context, l10n.classesFormTitle)),
        leading: IconButton(
          tooltip: l10n.classesFormClose,
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
                ref.levels(context, l10n.classesFormDetailsStep),
                style: text.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('class-name'),
                controller: _name,
                maxLength: 100,
                decoration: InputDecoration(
                  labelText: ref.levels(context, l10n.classesFormName),
                  hintText: l10n.classesFormNamePlaceholder,
                  errorText: _nameProblem,
                ),
              ),
              TextField(
                key: const Key('class-description'),
                controller: _description,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.classesFormDescription,
                  hintText: l10n.classesFormDescriptionPlaceholder,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(l10n.classesFormStudentsStep, style: text.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              InviteField(
                entries: _students,
                onChanged: (v) => setState(() => _students = v),
              ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _problem!,
                    key: const Key('create-problem'),
                    style: text.bodySmall?.copyWith(color: colors.danger),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(l10n.classesFormCancel),
                  ),
                  FilledButton(
                    key: const Key('create-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(
                      _saving
                          ? l10n.classesFormSubmitting
                          : ref.levels(context, l10n.classesFormSubmit),
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

/// A teacher's class page (the web's /classes/details/:id, Students tab):
/// students who asked to join (approve or turn down) and members (joined
/// or invited; view or remove), searchable and by section; Add students and
/// Share class.
class TeacherClassScreen extends ConsumerStatefulWidget {
  const TeacherClassScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<TeacherClassScreen> createState() => _TeacherClassScreenState();
}

class _TeacherClassScreenState extends ConsumerState<TeacherClassScreen> {
  final _search = TextEditingController();
  String? _section;
  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _act(Future<void> Function() action) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(teacherClassProvider(widget.id));
      ref.invalidate(teacherClassesProvider);
    } catch (e) {
      if (!mounted) return;
      if (!await handleCommonApiError(
        context,
        e,
        session: ref.read(sessionProvider),
      )) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ClassMember m) async {
    final l10n = context.l10n;
    final name = memberName(context, m);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.classesRosterRemoveTitle(name)),
        content: Text(ref.levels(d, l10n.classesRosterRemoveDetail)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.classesFormCancel),
          ),
          FilledButton(
            key: const Key('remove-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(d).danger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.classesRosterRemoveConfirm),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await _act(
      () => ref.read(teacherClassesRepositoryProvider).remove(widget.id, [
        m.studentId,
      ]),
    );
  }

  Future<void> _view(ClassMember m) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          Text(value),
        ],
      ),
    );
    return showDialog<void>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.classesRosterDetailsTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            row(l10n.classesRosterName, memberName(context, m)),
            row(l10n.classesRosterStudentId, m.publicId ?? '—'),
            row(l10n.classesRosterContact, m.contact ?? '—'),
            row(
              l10n.classesRosterStatus,
              m.status == 'JOINED'
                  ? l10n.classesRosterJoined
                  : l10n.classesRosterInvited,
            ),
            if (m.joinedAt != null)
              row(
                l10n.classesRosterJoinedOn,
                OrgTime.date(m.joinedAt!, language),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: Text(l10n.classesFormClose),
          ),
        ],
      ),
    );
  }

  Future<void> _add() async {
    final l10n = context.l10n;
    var entries = <String>[];
    final send = await showDialog<List<String>>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: Text(l10n.classesAddModalTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.classesAddModalIntro),
                const SizedBox(height: AppSpacing.sm),
                InviteField(
                  entries: entries,
                  onChanged: (v) => setD(() => entries = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(),
              child: Text(l10n.classesFormCancel),
            ),
            FilledButton(
              key: const Key('invite-send'),
              onPressed: entries.isEmpty
                  ? null
                  : () => Navigator.of(d).pop(entries),
              child: Text(l10n.classesAddModalConfirm),
            ),
          ],
        ),
      ),
    );
    if (send == null || send.isEmpty) return;
    await _act(
      () => ref.read(teacherClassesRepositoryProvider).invite(widget.id, send),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = ref.watch(teacherClassProvider(widget.id));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: c.when(
          loading: () => LoadingView(semanticsLabel: l10n.classesTitle),
          error: (e, _) =>
              e is ApiException && (e.statusCode == 404 || e.statusCode == 403)
              ? _notFound()
              : ErrorView(
                  title: ref.levels(context, l10n.classesNotFound),
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () =>
                      ref.invalidate(teacherClassProvider(widget.id)),
                ),
          data: (c) => c == null ? _notFound() : _page(c),
        ),
      ),
    );
  }

  Widget _notFound() {
    final l10n = context.l10n;
    return EmptyView(
      icon: Icons.class_outlined,
      title: ref.levels(context, l10n.classesNotFound),
      message: ref.levels(context, l10n.classesNotFoundDetail),
      actionLabel: ref.levels(context, l10n.classesBack),
      onAction: () => context.go(AppRoutes.classes),
    );
  }

  Widget _page(TeacherClass c) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final sections = <String, String>{
      for (final m in c.members)
        if (m.sectionId != null) m.sectionId!: m.sectionName ?? '',
    };
    final needle = _search.text.trim().toLowerCase();
    bool shown(ClassMember m) =>
        (_section == null || m.sectionId == _section) &&
        (needle.isEmpty ||
            memberName(context, m).toLowerCase().contains(needle) ||
            (m.contact ?? '').toLowerCase().contains(needle));
    final pending = [
      for (final m in c.members)
        if (m.pending && shown(m)) m,
    ];
    // Joined first, then invited (the web's order).
    final members =
        [
          for (final m in c.members)
            if (!m.pending && shown(m)) m,
        ]..sort(
          (a, b) => a.status == b.status ? 0 : (a.status == 'JOINED' ? -1 : 1),
        );

    Widget person(ClassMember m, List<Widget> actions) => ListTile(
      key: Key('member-${m.studentId}'),
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: colors.primarySoft,
        foregroundColor: colors.primary,
        child: Text(memberName(context, m).characters.first.toUpperCase()),
      ),
      title: Text(memberName(context, m)),
      subtitle: Text(
        [?m.contact, ?m.sectionName].join(' · '),
        style: text.bodySmall?.copyWith(color: colors.inkMuted),
      ),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: actions),
    );

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(teacherClassProvider(widget.id));
        await ref
            .read(teacherClassProvider(widget.id).future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(c.name, style: text.headlineSmall),
          if (c.description != null && c.description!.isNotEmpty)
            Text(
              c.description!,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                key: const Key('add-students'),
                onPressed: _busy ? null : _add,
                icon: const Icon(Icons.person_add_alt),
                label: Text(l10n.classesAddStudents),
              ),
              OutlinedButton.icon(
                key: const Key('share-class'),
                onPressed: () => showShareClass(context, ref, c),
                icon: const Icon(Icons.share_outlined),
                label: Text(ref.levels(context, l10n.classesShare)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (c.members.isEmpty)
            SizedBox(
              height: 240,
              child: EmptyView(
                icon: Icons.group_outlined,
                title: l10n.classesRosterEmpty,
                message: l10n.classesRosterEmptyDetail,
              ),
            )
          else ...[
            TextField(
              key: const Key('roster-search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: l10n.classesRosterSearch,
                prefixIcon: const Icon(Icons.search),
              ),
            ),
            if (sections.length > 1) ...[
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: const Key('roster-section'),
                initialValue: _section,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: ref.levels(context, l10n.classesRosterSection),
                ),
                items: [
                  DropdownMenuItem<String?>(
                    child: Text(
                      ref.levels(context, l10n.classesRosterAllSections),
                    ),
                  ),
                  for (final e in sections.entries)
                    DropdownMenuItem<String?>(
                      value: e.key,
                      child: Text(e.value),
                    ),
                ],
                onChanged: (v) => setState(() => _section = v),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.classesRosterPending(pending.length),
              style: text.titleMedium,
            ),
            if (pending.isEmpty)
              Text(
                l10n.classesRosterNoPending,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              )
            else
              for (final m in pending)
                person(m, [
                  IconButton(
                    key: Key('approve-${m.studentId}'),
                    tooltip: l10n.classesRosterApprove(memberName(context, m)),
                    color: colors.primary,
                    onPressed: _busy
                        ? null
                        : () => _act(
                            () => ref
                                .read(teacherClassesRepositoryProvider)
                                .approve(widget.id, m.studentId),
                          ),
                    icon: const Icon(Icons.check),
                  ),
                  IconButton(
                    key: Key('reject-${m.studentId}'),
                    tooltip: l10n.classesRosterReject(memberName(context, m)),
                    color: colors.danger,
                    onPressed: _busy ? null : () => _remove(m),
                    icon: const Icon(Icons.close),
                  ),
                ]),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.classesRosterActive(members.length),
              style: text.titleMedium,
            ),
            for (final m in members)
              person(m, [
                StatusPill(
                  label: m.status == 'JOINED'
                      ? l10n.classesRosterJoined
                      : l10n.classesRosterInvited,
                  tone: m.status == 'JOINED'
                      ? StatusTone.success
                      : StatusTone.warning,
                ),
                IconButton(
                  key: Key('view-${m.studentId}'),
                  tooltip: l10n.classesRosterView(memberName(context, m)),
                  onPressed: () => _view(m),
                  icon: const Icon(Icons.visibility_outlined),
                ),
                IconButton(
                  key: Key('remove-${m.studentId}'),
                  tooltip: l10n.classesRosterRemove(memberName(context, m)),
                  color: colors.danger,
                  onPressed: _busy ? null : () => _remove(m),
                  icon: const Icon(Icons.delete_outline),
                ),
              ]),
            if (c.lastTestAt != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n.classesLastTest(OrgTime.dateTime(c.lastTestAt!, language)),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
