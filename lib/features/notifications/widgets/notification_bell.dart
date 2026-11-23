import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/features/notifications/state/unread_count.dart';

/// The top-bar bell with the unread badge (the web's NotificationBell). Screen
/// readers hear "Notifications, 3 unread".
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final unread = ref.watch(unreadCountProvider);
    final language = Localizations.localeOf(context).languageCode;
    return IconButton(
      key: const Key('notification-bell'),
      tooltip: unread > 0
          ? l10n.notificationsBellUnread(unread)
          : l10n.notificationsBell,
      onPressed: () => context.go(AppRoutes.notifications),
      // The tooltip is the spoken label; the badge number alone would hide it.
      icon: ExcludeSemantics(
        child: Badge(
          isLabelVisible: unread > 0,
          label: Text(unread > 99 ? '99+' : OrgTime.number(unread, language)),
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
    );
  }
}
