import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

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
import 'package:instructor_app/features/classes/data/classes.dart';
import 'package:instructor_app/features/classes/screens/class_discussions.dart';

/// The web's /classes for a student: the classes they study in, in the
/// current workspace. Each opens its page. Teachers' classes (students,
/// sections, invitations) are Stage 2: the website for now.
class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    if (session?.role != 'STUDENT') {
      return EmptyView(
        icon: Icons.public,
        title: ref.levels(context, l10n.classesTitle),
        message: l10n.appNotYetBody,
      );
    }
    final classes = ref.watch(myClassesProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: classes.when(
          loading: () => LoadingView(semanticsLabel: l10n.classesTitle),
          error: (_, _) => ErrorView(
            title: ref.levels(context, l10n.classesNotFound),
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(myClassesProvider),
          ),
          data: (list) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myClassesProvider);
              await ref
                  .read(myClassesProvider.future)
                  .then<void>((_) {}, onError: (Object _) {});
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  ref.levels(context, l10n.classesTitle),
                  style: text.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  ref.levels(
                    context,
                    l10n.classesStudentIntro(
                      session?.organizationName ??
                          l10n.classesWorkspaceFallback,
                    ),
                  ),
                  style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (list.isEmpty)
                  SizedBox(
                    height: 300,
                    child: EmptyView(
                      icon: Icons.class_outlined,
                      title: ref.levels(context, l10n.classesEmpty),
                      message: ref.levels(context, l10n.classesEmptyStudent),
                    ),
                  )
                else
                  for (final c in list) ...[
                    AppCard(
                      key: Key('class-${c.id}'),
                      onTap: () =>
                          context.push('${AppRoutes.classes}/details/${c.id}'),
                      child: Row(
                        children: [
                          Icon(Icons.class_outlined, color: colors.primary),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: text.titleSmall),
                                if (c.joinedAt != null)
                                  Text(
                                    l10n.classesJoinedOn(
                                      OrgTime.date(c.joinedAt!, language),
                                    ),
                                    style: text.bodySmall?.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A class's page for a student: who is in it. Its tests and discussions
/// join as their PRs land.
class ClassDetailScreen extends ConsumerWidget {
  const ClassDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final detail = ref.watch(classDetailProvider(id));
    Widget notFound() => EmptyView(
      icon: Icons.class_outlined,
      title: ref.levels(context, l10n.classesNotFound),
      message: ref.levels(context, l10n.classesNotFoundDetail),
      actionLabel: ref.levels(context, l10n.classesBack),
      onAction: () => context.go(AppRoutes.classes),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: detail.when(
          loading: () => LoadingView(semanticsLabel: l10n.classesTitle),
          error: (e, _) =>
              e is ApiException && (e.statusCode == 404 || e.statusCode == 403)
              ? notFound()
              : ErrorView(
                  title: ref.levels(context, l10n.classesNotFound),
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () => ref.invalidate(classDetailProvider(id)),
                ),
          data: (c) => c == null
              ? notFound()
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(c.name, style: text.headlineSmall),
                    if (c.description != null && c.description!.isNotEmpty)
                      Text(
                        c.description!,
                        style: text.bodyMedium?.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    if (c.joinedAt != null)
                      Text(
                        l10n.classesJoinedOn(
                          OrgTime.date(c.joinedAt!, language),
                        ),
                        style: text.bodySmall?.copyWith(color: colors.inkMuted),
                      ),
                    const SizedBox(height: AppSpacing.lg),
                    _ClassTabs(
                      classId: c.id,
                      students: AppCard(
                        key: const Key('classmates'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              l10n.classesRosterTitle,
                              style: text.titleMedium,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (c.classmates.isEmpty)
                              Text(
                                l10n.classesRosterEmpty,
                                style: text.bodyMedium?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              )
                            else
                              for (final m in c.classmates)
                                ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: colors.primarySoft,
                                    foregroundColor: colors.primary,
                                    child: Text(
                                      m.name.isEmpty
                                          ? '?'
                                          : m.name.characters.first
                                                .toUpperCase(),
                                    ),
                                  ),
                                  title: Text(m.name),
                                  subtitle: m.joinedAt == null
                                      ? null
                                      : Text(
                                          '${l10n.classesRosterJoined} '
                                          '${OrgTime.date(m.joinedAt!, language)}',
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
    );
  }
}

/// The class page's tabs (the web's Students and Discussions; Tests join
/// with the tests PR).
class _ClassTabs extends StatefulWidget {
  const _ClassTabs({required this.classId, required this.students});

  final String classId;
  final Widget students;

  @override
  State<_ClassTabs> createState() => _ClassTabsState();
}

class _ClassTabsState extends State<_ClassTabs> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<int>(
          segments: [
            ButtonSegment(value: 0, label: Text(l10n.classesTabsStudents)),
            ButtonSegment(value: 1, label: Text(l10n.classesTabsDiscussions)),
          ],
          selected: {_tab},
          onSelectionChanged: (s) => setState(() => _tab = s.first),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_tab == 0)
          widget.students
        else
          ClassDiscussions(classId: widget.classId),
      ],
    );
  }
}
