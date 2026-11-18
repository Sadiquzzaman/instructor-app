import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';
import 'package:instructor_app/features/tests/data/tests.dart';
import 'package:instructor_app/features/tests/screens/tests_screen.dart';

/// A teacher's tests in this workspace (`GET /exams`).
final teacherTestsProvider = FutureProvider.autoDispose<List<TestItem>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  return TestItem.listOf(
    (await ref.read(apiClientProvider).get('/exams')).payload,
  );
}, retry: (retryCount, error) => null);

/// A class's tests for its teacher (`GET /exams/class/:id`).
final teacherClassTestsProvider = FutureProvider.autoDispose
    .family<List<TestItem>, String>((ref, classId) async {
      ref.watch(workspaceKeyProvider);
      return TestItem.listOf(
        (await ref.read(apiClientProvider).get('/exams/class/$classId'))
            .payload,
      );
    }, retry: (retryCount, error) => null);

/// One of the teacher's tests (`GET /exams/:id`).
final teacherTestProvider = FutureProvider.autoDispose
    .family<TestItem?, String>((ref, id) async {
      ref.watch(workspaceKeyProvider);
      return TestItem.fromJson(
        (await ref.read(apiClientProvider).get('/exams/$id')).payload,
      );
    }, retry: (retryCount, error) => null);

/// Academic sessions that are closed: their tests are read-only (FND-01).
final closedSessionsProvider = FutureProvider.autoDispose<Set<String>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  try {
    final p = (await ref.read(apiClientProvider).get('/sessions')).payload;
    return {
      if (p is List)
        for (final s in p)
          if (s is Map && s['status'] == 'CLOSED' && s['id'] is String)
            s['id'] as String,
    };
  } on ApiException {
    // Not every role may list sessions; the server still refuses changes.
    return const <String>{};
  }
}, retry: (retryCount, error) => null);

void _openTest(BuildContext context, TestItem t) =>
    context.push('${AppRoutes.tests}/${t.id}');

/// The web's /tests for a teacher: their tests in this workspace by status,
/// searchable; each opens its page. Making a test stays on the web
/// (Stage 4).
class TeacherTestsScreen extends ConsumerStatefulWidget {
  const TeacherTestsScreen({super.key});

  @override
  ConsumerState<TeacherTestsScreen> createState() => _TeacherTestsScreenState();
}

class _TeacherTestsScreenState extends ConsumerState<TeacherTestsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final tests = ref.watch(teacherTestsProvider);
    final needle = _search.text.trim().toLowerCase();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(teacherTestsProvider);
            await ref
                .read(teacherTestsProvider.future)
                .then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.testsTitle, style: text.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.testsIntro,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('tests-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: l10n.testsSearch,
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              tests.when(
                loading: () => SizedBox(
                  height: 220,
                  child: LoadingView(semanticsLabel: l10n.testsTitle),
                ),
                error: (e, _) => SizedBox(
                  height: 300,
                  child: e is ApiException && e.isFeatureLocked
                      ? EmptyView(
                          icon: Icons.lock_outline,
                          title: l10n.featuresLockedTitle,
                        )
                      : ErrorView(
                          title: l10n.testsResultsFailed,
                          retryLabel: l10n.uiErrorRetry,
                          onRetry: () => ref.invalidate(teacherTestsProvider),
                        ),
                ),
                data: (list) {
                  // As the web: a word of the name, subject or class
                  // starting with what was typed.
                  bool hit(String? v) =>
                      v != null &&
                      (v.toLowerCase().startsWith(needle) ||
                          v
                              .toLowerCase()
                              .split(RegExp(r'\s+'))
                              .any((w) => w.startsWith(needle)));
                  final shown = needle.isEmpty
                      ? list
                      : [
                          for (final t in list)
                            if (hit(t.name) ||
                                hit(t.subject) ||
                                hit(t.className))
                              t,
                        ];
                  return TestList(
                    tests: shown,
                    onOpen: (t) => _openTest(context, t),
                    emptyMessage: needle.isEmpty
                        ? l10n.testsEmptyTeacher
                        : l10n.testsNoMatch,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A class's Tests tab for its teacher (the web's ClassTests).
class TeacherClassTests extends ConsumerWidget {
  const TeacherClassTests({required this.classId, super.key});

  final String classId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return ref
        .watch(teacherClassTestsProvider(classId))
        .when(
          loading: () => SizedBox(
            height: 160,
            child: LoadingView(semanticsLabel: l10n.testsTitle),
          ),
          error: (_, _) => SizedBox(
            height: 260,
            child: ErrorView(
              title: l10n.testsResultsFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(teacherClassTestsProvider(classId)),
            ),
          ),
          data: (list) => TestList(
            tests: list,
            onOpen: (t) => _openTest(context, t),
            emptyMessage: l10n.testsEmptyTeacher,
          ),
        );
  }
}

/// A teacher's test (the web's ExamDetails): status, on or off, schedule,
/// class, duration, questions, passing score and negative marking, and the
/// subjects; Switch off (asked first) or on before it starts. Editing stays
/// on the web (Stage 4); the live monitor and marking join as their PRs
/// land.
class TeacherTestScreen extends ConsumerStatefulWidget {
  const TeacherTestScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<TeacherTestScreen> createState() => _TeacherTestScreenState();
}

class _TeacherTestScreenState extends ConsumerState<TeacherTestScreen> {
  bool _busy = false;

  Future<void> _toggle(TestItem t) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    if (t.active) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l10n.testsDetailsDisableTitle),
          content: Text(l10n.testsDetailsDisableDetail),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l10n.uiCancel),
            ),
            FilledButton(
              key: const Key('disable-confirm'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.of(d).danger,
              ),
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l10n.testsDetailsDisable),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .patch('/exams/${t.id}/status', data: {'active': !t.active});
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.testsDetailsStatusSaved)),
      );
      ref
        ..invalidate(teacherTestProvider(t.id))
        ..invalidate(teacherTestsProvider);
    } catch (e) {
      if (mounted &&
          !await handleCommonApiError(
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final test = ref.watch(teacherTestProvider(widget.id));
    Widget notFound() => EmptyView(
      icon: Icons.quiz_outlined,
      title: l10n.testsDetailsNotFound,
      message: l10n.testsDetailsNotFoundDetail,
      actionLabel: l10n.testsDetailsBack,
      onAction: () => context.go(AppRoutes.tests),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: test.when(
          skipLoadingOnReload: true,
          loading: () => LoadingView(semanticsLabel: l10n.testsDetailsTitle),
          error: (e, _) =>
              e is ApiException && (e.statusCode == 404 || e.statusCode == 403)
              ? notFound()
              : ErrorView(
                  title: l10n.testsResultsFailed,
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () => ref.invalidate(teacherTestProvider(widget.id)),
                ),
          data: (t) => t == null ? notFound() : _page(t),
        ),
      ),
    );
  }

  Widget _page(TestItem t) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final closed = ref.watch(closedSessionsProvider).value ?? const <String>{};
    final sessionClosed = t.sessionId != null && closed.contains(t.sessionId);
    final canModify =
        !sessionClosed &&
        t.startsAt != null &&
        DateTime.now().isBefore(t.startsAt!);
    // The live monitor: the teacher who made the test, or the school's
    // owners and admins (the web's canMonitor).
    final session = ref.watch(sessionProvider);
    final canMonitor =
        (t.createdBy != null && t.createdBy == session?.userId) ||
        const {'OWNER', 'ADMIN'}.contains(session?.memberRole);
    String n(num v) => OrgTime.number(v, language);
    final audience = switch (t.audience) {
      'anyone' => l10n.testsAudienceAnyone,
      'selectedClass' => l10n.testsAudienceSelectedClass,
      'specificStudents' => l10n.testsAudienceSpecificStudents,
      _ => '—',
    };
    final passing = num.tryParse(t.passingScore ?? '');
    final negative = num.tryParse(t.negativeMarking ?? '');
    final facts = [
      (
        l10n.testsDetailsSubjects,
        t.subjects.map((s) => s.name).where((s) => s.isNotEmpty).join(', '),
      ),
      (l10n.testsDetailsAudience, audience),
      (l10n.testsDetailsClass, t.className ?? '—'),
      (
        l10n.testsDetailsDuration,
        l10n.testsDetailsMinutes(t.durationMinutes ?? 0),
      ),
      (
        l10n.testsDetailsStarts,
        t.startsAt == null ? '—' : OrgTime.dateTime(t.startsAt!, language),
      ),
      (
        l10n.testsDetailsEnds,
        t.endsAt == null ? '—' : OrgTime.dateTime(t.endsAt!, language),
      ),
      (l10n.testsDetailsQuestions, n(t.questionCount)),
      (l10n.testsDetailsPassingScore, passing == null ? '—' : n(passing)),
      (
        l10n.testsDetailsNegativeMarking,
        negative == null ? l10n.testsDetailsOff : '${n(negative)}%',
      ),
    ];
    final status = switch (t.status) {
      'ongoing' => (l10n.testsStatusOngoing, StatusTone.success),
      'completed' => (l10n.testsStatusCompleted, StatusTone.neutral),
      _ => (l10n.testsStatusPending, StatusTone.info),
    };
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(teacherTestProvider(widget.id));
        await ref
            .read(teacherTestProvider(widget.id).future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Text(t.name, style: text.headlineSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              StatusPill(label: status.$1, tone: status.$2),
              StatusPill(
                key: const Key('test-on-off'),
                label: t.active ? l10n.testsEnabled : l10n.testsDisabled,
                tone: t.active ? StatusTone.neutral : StatusTone.danger,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (canMonitor && t.status != 'completed')
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  key: const Key('test-monitor'),
                  onPressed: () =>
                      context.push('${AppRoutes.tests}/${t.id}/monitor'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text(l10n.testsDetailsMonitor),
                ),
              ),
            ),
          if (canModify)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: t.active
                  ? OutlinedButton(
                      key: const Key('test-toggle'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.danger,
                      ),
                      onPressed: _busy ? null : () => _toggle(t),
                      child: Text(l10n.testsDetailsDisable),
                    )
                  : FilledButton(
                      key: const Key('test-toggle'),
                      onPressed: _busy ? null : () => _toggle(t),
                      child: Text(l10n.testsDetailsEnable),
                    ),
            )
          else
            Text(
              sessionClosed
                  ? l10n.testsDetailsSessionClosed
                  : l10n.testsDetailsLocked,
              key: const Key('test-locked'),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (label, value) in facts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: text.bodySmall?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                        Text(
                          value.isEmpty ? '—' : value,
                          style: text.titleSmall,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (t.subjects.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.testsDetailsSubjects, style: text.titleMedium),
                  for (final s in t.subjects)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      trailing: Text(
                        l10n.testsDetailsQuestionCount(s.questions),
                        style: text.bodySmall?.copyWith(color: colors.inkMuted),
                      ),
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
