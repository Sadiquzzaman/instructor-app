import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/notifications/data/notifications_repository.dart';
import 'package:instructor_app/features/notifications/state/unread_count.dart';

@immutable
class InboxState {
  const InboxState({
    required this.items,
    required this.page,
    required this.hasNext,
    this.loadingMore = false,
  });

  final List<InboxItem> items;
  final int page;
  final bool hasNext;
  final bool loadingMore;

  InboxState copyWith({
    List<InboxItem>? items,
    int? page,
    bool? hasNext,
    bool? loadingMore,
  }) => InboxState(
    items: items ?? this.items,
    page: page ?? this.page,
    hasNext: hasNext ?? this.hasNext,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// The inbox screen's list: first page, more on scroll, mark read.
final inboxProvider =
    AsyncNotifierProvider.autoDispose<InboxController, InboxState>(
      InboxController.new,
      retry: (retryCount, error) => null,
    );

class InboxController extends AsyncNotifier<InboxState> {
  NotificationsRepository get _repo =>
      ref.read(notificationsRepositoryProvider);

  @override
  Future<InboxState> build() async {
    final userId = ref.watch(sessionProvider.select((s) => s?.userId));
    // Signed out (the screen is about to go): nothing to load.
    if (userId == null) {
      return const InboxState(items: [], page: 0, hasNext: false);
    }
    final first = await _repo.page(1);
    _updateBadge(first.unread);
    return InboxState(items: first.items, page: 1, hasNext: first.hasNext);
  }

  void _updateBadge(int? unread) {
    if (unread != null) ref.read(unreadCountProvider.notifier).set(unread);
  }

  /// The next page, if there is one and none is loading.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasNext || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _repo.page(current.page + 1);
      _updateBadge(next.unread);
      final seen = current.items.map((i) => i.id).toSet();
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...next.items.where((i) => !seen.contains(i.id)),
          ],
          page: current.page + 1,
          hasNext: next.hasNext,
          loadingMore: false,
        ),
      );
    } on Object {
      // Keep what is shown; scrolling again tries again.
      state = AsyncData(current.copyWith(loadingMore: false));
    }
  }

  /// Marks one read (shown at once; the badge follows).
  Future<void> markRead(InboxItem item) async {
    if (!item.unread) return;
    _replace(item.id, (i) => i.markedRead(DateTime.now()));
    final badge = ref.read(unreadCountProvider);
    ref.read(unreadCountProvider.notifier).set(badge - 1);
    try {
      await _repo.markRead(item.id);
    } on Object {
      // The next poll corrects the badge.
    }
  }

  Future<void> markAllRead() async {
    final current = state.value;
    if (current == null) return;
    await _repo.markAllRead();
    final now = DateTime.now();
    state = AsyncData(
      current.copyWith(
        items: [for (final i in current.items) i.markedRead(now)],
      ),
    );
    ref.read(unreadCountProvider.notifier).set(0);
  }

  void _replace(String id, InboxItem Function(InboxItem) change) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: [for (final i in current.items) i.id == id ? change(i) : i],
      ),
    );
  }
}
