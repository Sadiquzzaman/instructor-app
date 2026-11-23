import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:go_router/go_router.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/tests/data/tests.dart';
import 'package:instructor_app/features/tests/screens/teacher_tests_screens.dart';
import 'package:instructor_app/features/tests/widgets/test_card.dart';

/// Tests with a status filter (the web's ClassTests filters), each as a
/// [TestCard]. Used by /tests and a class's Tests tab.
class TestList extends StatefulWidget {
  const TestList({
    required this.tests,
    this.onStart,
    this.onOpen,
    this.emptyMessage,
    super.key,
  });

  final List<TestItem> tests;
  final void Function(TestItem)? onStart;

  /// Opens a test's page (teachers).
  final void Function(TestItem)? onOpen;

  /// Under "No tests yet"; the students' wording by default.
  final String? emptyMessage;

  @override
  State<TestList> createState() => _TestListState();
}

class _TestListState extends State<TestList> {
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final shown = _filter == null
        ? widget.tests
        : widget.tests.where((t) => t.status == _filter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final (value, label) in [
              (null, l10n.testsFilterAll),
              ('ongoing', l10n.testsFilterOngoing),
              ('pending', l10n.testsFilterPending),
              ('completed', l10n.testsFilterCompleted),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _filter == value,
                onSelected: (_) => setState(() => _filter = value),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (shown.isEmpty)
          SizedBox(
            height: 260,
            child: EmptyView(
              icon: Icons.quiz_outlined,
              title: l10n.testsEmpty,
              message: widget.emptyMessage ?? l10n.testsEmptyStudent,
            ),
          )
        else
          for (final t in shown) ...[
            TestCard(
              test: t,
              onStart: widget.onStart == null ? null : () => widget.onStart!(t),
              onOpen: widget.onOpen == null ? null : () => widget.onOpen!(t),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

/// Opens the test over the whole screen (rules, then the questions).
void startTest(BuildContext context, TestItem test) =>
    context.push('${AppRoutes.tests}/${test.id}/take');

/// The web's /tests for a student.
class TestsScreen extends ConsumerWidget {
  const TestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    // Teachers follow their own tests (the web's TestList for a teacher).
    if (ref.watch(sessionProvider)?.role != 'STUDENT') {
      return const TeacherTestsScreen();
    }
    final tests = ref.watch(myTestsProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: tests.when(
          loading: () => LoadingView(semanticsLabel: l10n.testsTitle),
          error: (_, _) => ErrorView(
            title: l10n.testsResultsFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(myTestsProvider),
          ),
          data: (list) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myTestsProvider);
              await ref
                  .read(myTestsProvider.future)
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
                TestList(tests: list, onStart: (t) => startTest(context, t)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
