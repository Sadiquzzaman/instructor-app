import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

typedef OrgSubject = ({
  String id,
  String name,
  String code,
  List<String> classes,
});

final orgSubjectsProvider = FutureProvider.autoDispose<List<OrgSubject>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final id = ref.watch(sessionProvider)?.organizationId;
  final p =
      (await ref.read(apiClientProvider).get('/organizations/$id/subjects'))
          .payload;
  return [
    if (p is List)
      for (final s in p)
        if (s is Map && s['id'] is String)
          (
            id: s['id'] as String,
            name: (s['name'] as String?) ?? '',
            code: (s['code'] as String?) ?? '',
            classes: [
              if (s['classes'] is List)
                for (final c in s['classes'] as List)
                  if (c is Map) (c['class_name'] as String?) ?? '',
            ],
          ),
  ];
}, retry: (retryCount, error) => null);

typedef OrgClass = ({
  String id,
  String name,
  List<String> subjects,
  int students,
});

final orgClassesProvider = FutureProvider.autoDispose<List<OrgClass>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/classes')).payload;
  return [
    if (p is List)
      for (final c in p)
        if (c is Map && c['id'] is String)
          (
            id: c['id'] as String,
            name: (c['class_name'] as String?) ?? '',
            subjects: [
              if (c['classSubjects'] is List)
                for (final r in c['classSubjects'] as List)
                  if (r is Map &&
                      r['subject'] is Map &&
                      ((r['subject'] as Map)['name'] as String?)?.isNotEmpty ==
                          true)
                    switch (r['subject'] as Map) {
                      final s when (s['code'] as String?)?.isNotEmpty == true =>
                        '${s['name']} (${s['code']})',
                      final s => s['name'] as String,
                    },
            ],
            students: c['classStudents'] is List
                ? (c['classStudents'] as List).length
                : 0,
          ),
  ];
}, retry: (retryCount, error) => null);

Widget _gate(BuildContext context) {
  final l10n = context.l10n;
  return EmptyView(
    icon: Icons.lock_outline,
    title: l10n.organizationGateNoAccessTitle,
    message: l10n.organizationGateNoAccess,
  );
}

/// The web's /organization/subjects (owners, admins, assistants): the
/// organisation's subjects with their code and classes; add, rename and
/// delete (asked first).
class OrgSubjectsScreen extends ConsumerWidget {
  const OrgSubjectsScreen({super.key});

  static const _allowed = {'OWNER', 'ADMIN', 'ASSISTANT'};

  Future<void> _edit(BuildContext context, WidgetRef ref, OrgSubject? s) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SubjectDialog(subject: s),
    );
    if (saved == true) ref.invalidate(orgSubjectsProvider);
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    OrgSubject s,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.organizationSubjectsDeleteTitle(s.name)),
        content: Text(
          ref.levels(context, l10n.organizationSubjectsDeleteDetail),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.uiCancel),
          ),
          FilledButton(
            key: const Key('subject-delete-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.organizationSubjectsDelete),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final id = ref.read(sessionProvider)?.organizationId;
    try {
      await ref
          .read(apiClientProvider)
          .delete('/organizations/$id/subjects/${s.id}');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.organizationSubjectsDeletedTitle)),
      );
      ref.invalidate(orgSubjectsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    if (!_allowed.contains(session?.memberRole)) {
      return _gate(context);
    }
    final subjects = ref.watch(orgSubjectsProvider);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.organizationSubjectsTitle, style: text.headlineSmall),
            Text(session?.organizationName ?? '', style: muted),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const Key('subject-add'),
                icon: const Icon(Icons.add),
                label: Text(l10n.organizationSubjectsCreate),
                onPressed: () => _edit(context, ref, null),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...subjects.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(
                    semanticsLabel: l10n.organizationSubjectsTitle,
                  ),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 280,
                  child: ErrorView(
                    title: e is ApiException
                        ? apiErrorText(l10n, e)
                        : l10n.uiErrorTitle,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(orgSubjectsProvider),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SizedBox(
                        height: 200,
                        child: EmptyView(
                          icon: Icons.menu_book_outlined,
                          title: l10n.organizationSubjectsEmpty,
                        ),
                      ),
                    ]
                  : [
                      for (final s in list) ...[
                        AppCard(
                          key: Key('subject-${s.id}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(s.name, style: text.titleSmall),
                              Text(
                                '${l10n.organizationSubjectsCode}: ${s.code.isEmpty ? '—' : s.code}',
                                style: muted,
                              ),
                              Text(
                                '${ref.levels(context, l10n.organizationSubjectsClasses)}: ${s.classes.isEmpty ? '—' : s.classes.join(', ')}',
                                style: muted,
                              ),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: AppSpacing.xs,
                                children: [
                                  TextButton(
                                    key: Key('subject-edit-${s.id}'),
                                    onPressed: () => _edit(context, ref, s),
                                    child: Text(l10n.organizationSubjectsEdit),
                                  ),
                                  TextButton(
                                    key: Key('subject-delete-${s.id}'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: colors.danger,
                                    ),
                                    onPressed: () => _delete(context, ref, s),
                                    child: Text(
                                      l10n.organizationSubjectsDelete,
                                    ),
                                  ),
                                ],
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
    );
  }
}

/// Add or rename a subject: a name and a code, both needed. Pops true when
/// saved.
class _SubjectDialog extends ConsumerStatefulWidget {
  const _SubjectDialog({this.subject});

  final OrgSubject? subject;

  @override
  ConsumerState<_SubjectDialog> createState() => _SubjectDialogState();
}

class _SubjectDialogState extends ConsumerState<_SubjectDialog> {
  late final _name = TextEditingController(text: widget.subject?.name ?? '');
  late final _code = TextEditingController(text: widget.subject?.code ?? '');
  bool _saving = false;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final name = _name.text.trim();
    final code = _code.text.trim();
    if (name.isEmpty || code.isEmpty) {
      setState(() => _problem = l10n.organizationSubjectsRequired);
      return;
    }
    final id = ref.read(sessionProvider)?.organizationId;
    final s = widget.subject;
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final body = {'name': name, 'code': code};
      if (s == null) {
        await api.post('/organizations/$id/subjects', data: body);
      } else {
        await api.patch('/organizations/$id/subjects/${s.id}', data: body);
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            s == null
                ? l10n.organizationSubjectsCreatedTitle
                : l10n.organizationSubjectsUpdatedTitle,
          ),
        ),
      );
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = apiErrorText(l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.subject != null;
    return AlertDialog(
      title: Text(
        editing
            ? l10n.organizationSubjectsEditTitle
            : l10n.organizationSubjectsCreate,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!editing) Text(l10n.organizationSubjectsCreateIntro),
            TextField(
              key: const Key('subject-name'),
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.organizationSubjectsName,
                hintText: l10n.organizationSubjectsNamePlaceholder,
              ),
            ),
            TextField(
              key: const Key('subject-code'),
              controller: _code,
              decoration: InputDecoration(
                labelText: l10n.organizationSubjectsCode,
                hintText: l10n.organizationSubjectsCodePlaceholder,
              ),
            ),
            if (_problem != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  _problem!,
                  key: const Key('subject-problem'),
                  style: TextStyle(color: AppColors.of(context).danger),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.uiCancel),
        ),
        FilledButton(
          key: const Key('subject-save'),
          onPressed: _saving ? null : _save,
          child: Text(
            editing
                ? l10n.organizationSubjectsSave
                : l10n.organizationSubjectsCreate,
          ),
        ),
      ],
    );
  }
}

/// The web's /organization/classes: each class with its subjects and how
/// many students; a class opens its page. Making classes is the setup
/// wizard's job (on the website until Stage 4).
class OrgClassesScreen extends ConsumerWidget {
  const OrgClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    if (session?.organizationId == null) {
      return EmptyView(
        icon: Icons.apartment_outlined,
        title: l10n.organizationGateNoWorkspaceTitle,
        message: l10n.organizationGateNoWorkspace,
      );
    }
    final classes = ref.watch(orgClassesProvider);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              ref.levels(context, l10n.organizationClassesTitle),
              style: text.headlineSmall,
            ),
            Text(session?.organizationName ?? '', style: muted),
            const SizedBox(height: AppSpacing.md),
            ...classes.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(
                    semanticsLabel: ref.levels(
                      context,
                      l10n.organizationClassesTitle,
                    ),
                  ),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 280,
                  child: ErrorView(
                    title: e is ApiException
                        ? apiErrorText(l10n, e)
                        : l10n.uiErrorTitle,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(orgClassesProvider),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SizedBox(
                        height: 200,
                        child: EmptyView(
                          icon: Icons.class_outlined,
                          title: ref.levels(
                            context,
                            l10n.organizationClassesEmpty,
                          ),
                        ),
                      ),
                    ]
                  : [
                      for (final c in list) ...[
                        AppCard(
                          key: Key('class-${c.id}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(c.name, style: text.titleSmall),
                              Text(
                                '${l10n.organizationClassesSubjects}: ${c.subjects.isEmpty ? '—' : c.subjects.join(', ')}',
                                style: muted,
                              ),
                              Text(
                                '${l10n.organizationClassesStudents}: ${OrgTime.number(c.students, language)}',
                                style: muted,
                              ),
                              Align(
                                alignment: AlignmentDirectional.centerEnd,
                                child: TextButton(
                                  key: Key('class-view-${c.id}'),
                                  onPressed: () =>
                                      context.push('/classes/details/${c.id}'),
                                  child: Text(l10n.organizationClassesView),
                                ),
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
    );
  }
}
