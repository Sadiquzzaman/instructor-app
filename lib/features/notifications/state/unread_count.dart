import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/notifications/data/notifications_repository.dart';

/// The bell's unread count, as the web keeps it (NotificationBell.tsx): read
/// at once, every minute while the app is open, and when the app comes back
/// to the front. A failed read keeps the last number. Signed out: 0, no timer.
/// (Push comes with the server's PM-04.)
final unreadCountProvider = NotifierProvider<UnreadCount, int>(UnreadCount.new);

class UnreadCount extends Notifier<int> {
  static const pollEvery = Duration(minutes: 1);

  Timer? _timer;
  AppLifecycleListener? _lifecycle;

  @override
  int build() {
    final userId = ref.watch(sessionProvider.select((s) => s?.userId));
    ref.onDispose(_stop);
    if (userId == null) return 0;
    _timer = Timer.periodic(pollEvery, (_) => refresh());
    _lifecycle = AppLifecycleListener(onResume: refresh);
    Future.microtask(refresh);
    return 0;
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }

  Future<void> refresh() async {
    try {
      final count = await ref
          .read(notificationsRepositoryProvider)
          .unreadCount();
      if (ref.mounted) state = count;
    } on Object {
      // Keep the last number.
    }
  }

  /// After the inbox changed it (read one, read all, a fresh page).
  void set(int count) => state = count < 0 ? 0 : count;
}
