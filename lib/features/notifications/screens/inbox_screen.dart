import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/notifications/data/notifications_repository.dart';
import 'package:instructor_app/features/notifications/state/inbox_controller.dart';

/// The inbox (the web's bell panel): newest first, unread marked, more on
/// scroll, "Mark all as read". Opening an item marks it read and, when the
/// app has its page, goes there.
class InboxScreen extends ConsumerStatefulWidget {
  const InboxScreen({super.key});

  @override
  ConsumerState<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends ConsumerState<InboxScreen> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) {
        ref.read(inboxProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _open(InboxItem item) async {
    await ref.read(inboxProvider.notifier).markRead(item);
    final link = item.link;
    if (link != null && AppRoutes.isAppPage(link) && mounted) {
      context.go(link);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final inbox = ref.watch(inboxProvider);
    final hasUnread = inbox.value?.items.any((i) => i.unread) ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.notificationsTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              if (hasUnread)
                TextButton(
                  onPressed: () async {
                    try {
                      await ref.read(inboxProvider.notifier).markAllRead();
                    } on Object catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(apiErrorText(l10n, e))),
                        );
                      }
                    }
                  },
                  child: Text(l10n.notificationsMarkAllRead),
                ),
            ],
          ),
        ),
        Expanded(
          child: inbox.when(
            loading: () => LoadingView(semanticsLabel: l10n.uiLoading),
            error: (e, _) => ErrorView(
              title: l10n.uiErrorTitle,
              message: apiErrorText(l10n, e),
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(inboxProvider),
            ),
            data: (state) => state.items.isEmpty
                ? EmptyView(
                    icon: Icons.notifications_none,
                    title: l10n.notificationsEmpty,
                    message: l10n.notificationsEmptyHint,
                  )
                : RefreshIndicator(
                    onRefresh: () => ref.refresh(inboxProvider.future),
                    child: ListView.separated(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: state.items.length + (state.hasNext ? 1 : 0),
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        if (index == state.items.length) {
                          return const Padding(
                            padding: EdgeInsets.all(AppSpacing.lg),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final item = state.items[index];
                        return _InboxTile(item: item, onTap: () => _open(item));
                      },
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _InboxTile extends StatelessWidget {
  const _InboxTile({required this.item, required this.onTap});

  final InboxItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final language = Localizations.localeOf(context).languageCode;
    return Semantics(
      label: item.unread ? context.l10n.notificationsUnread : null,
      // Its own Material, so the unread colour and the tap ripple always show.
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          key: Key('inbox-${item.id}'),
          onTap: onTap,
          tileColor: item.unread ? colors.primarySoft : null,
          leading: Icon(
            item.unread ? Icons.circle : Icons.circle_outlined,
            size: AppSpacing.md,
            color: item.unread ? colors.primary : colors.border,
          ),
          // Server text in the person's language: shown as it comes.
          title: Text(
            item.title,
            style: text.titleSmall?.copyWith(
              fontWeight: item.unread ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (item.body != null && item.body!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(item.body!, style: text.bodyMedium),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                OrgTime.dateTime(item.createdAt, language),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
