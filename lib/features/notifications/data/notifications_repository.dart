import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/api/api_response.dart';

/// One in-app notification (`GET /me/notifications`). The title and body are
/// written by the server in the person's language when it was sent; they are
/// shown as they come.
@immutable
class InboxItem {
  const InboxItem({
    required this.id,
    required this.title,
    required this.createdAt,
    this.body,
    this.link,
    this.readAt,
    this.type,
  });

  final String id;
  final String title;
  final String? body;

  /// The web page it is about (`/tests/…`), if any.
  final String? link;
  final DateTime createdAt;
  final DateTime? readAt;
  final String? type;

  bool get unread => readAt == null;

  static InboxItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], created = json['created_at'];
    if (id is! String || created is! String) return null;
    final createdAt = DateTime.tryParse(created);
    if (createdAt == null) return null;
    final read = json['read_at'];
    return InboxItem(
      id: id,
      title: (json['title'] as String?) ?? '',
      body: json['body'] as String?,
      link: json['link'] as String?,
      createdAt: createdAt,
      readAt: read is String ? DateTime.tryParse(read) : null,
      type: json['type'] as String?,
    );
  }

  InboxItem markedRead(DateTime when) => InboxItem(
    id: id,
    title: title,
    body: body,
    link: link,
    createdAt: createdAt,
    readAt: readAt ?? when,
    type: type,
  );
}

/// A page of the inbox.
@immutable
class InboxPage {
  const InboxPage({required this.items, this.meta});
  final List<InboxItem> items;
  final PageMeta? meta;

  bool get hasNext => meta?.hasNext ?? false;
  int? get unread => (meta?.extra['unread'] as num?)?.toInt();
}

/// The bell (FND-12): `/me/notifications…`. Per person, not per workspace.
class NotificationsRepository {
  NotificationsRepository(this.api);

  final ApiClient api;

  static const pageSize = 20;

  Future<int> unreadCount() async {
    final r = await api.get('/me/notifications/unread-count');
    return ((r.object['count'] as num?) ?? 0).toInt();
  }

  Future<InboxPage> page(int page) async {
    final r = await api.get(
      '/me/notifications',
      query: {'page': page, 'limit': pageSize},
    );
    final payload = r.payload;
    return InboxPage(
      items: payload is List
          ? payload.map(InboxItem.fromJson).nonNulls.toList()
          : const [],
      meta: r.meta,
    );
  }

  Future<void> markRead(String id) => api.patch('/me/notifications/$id/read');

  Future<void> markAllRead() => api.post('/me/notifications/read-all');
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(apiClientProvider)),
);
