import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/homework/data/homework.dart';
import 'package:instructor_app/features/homework/homework_text.dart';

/// The web's /homework for a student: every homework set to them, with
/// "Handed in (version n)" or when it is due. Each opens its page.
class HomeworkListScreen extends ConsumerWidget {
  const HomeworkListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    // Teachers' homework (create, mark) is Stage 2: the website for now.
    if (ref.watch(sessionProvider)?.role != 'STUDENT') {
      return EmptyView(
        icon: Icons.public,
        title: l10n.homeworkTitle,
        message: l10n.appNotYetBody,
      );
    }
    final items = ref.watch(myHomeworkProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: items.when(
          loading: () => LoadingView(semanticsLabel: l10n.homeworkTitle),
          error: (_, _) => ErrorView(
            title: l10n.homeworkLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(myHomeworkProvider),
          ),
          data: (items) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myHomeworkProvider);
              await ref
                  .read(myHomeworkProvider.future)
                  .then<void>((_) {}, onError: (Object _) {});
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(l10n.homeworkTitle, style: text.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.homeworkStudentIntro,
                  style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (items.isEmpty)
                  SizedBox(
                    height: 320,
                    child: EmptyView(
                      icon: Icons.assignment_outlined,
                      title: l10n.homeworkStudentEmpty,
                      message: l10n.homeworkStudentEmptyHint,
                    ),
                  )
                else
                  for (final h in items) ...[
                    AppCard(
                      key: Key('homework-${h.id}'),
                      onTap: () =>
                          context.push('${AppRoutes.homework}/${h.id}'),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h.title,
                                  style: text.titleSmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  h.subject,
                                  style: text.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: h.handedInVersion != null
                                ? StatusPill(
                                    label: l10n.homeworkHandedIn(
                                      h.handedInVersion!,
                                    ),
                                    tone: StatusTone.success,
                                  )
                                : Builder(
                                    builder: (_) {
                                      final (label, tone) = dueText(
                                        l10n,
                                        h.dueAt,
                                        language,
                                      );
                                      return StatusPill(
                                        label: label,
                                        tone: tone,
                                      );
                                    },
                                  ),
                          ),
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
