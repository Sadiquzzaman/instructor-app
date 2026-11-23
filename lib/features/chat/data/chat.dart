import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

typedef ChatPreview = ({String author, String text, DateTime? at});

ChatPreview? _preview(Object? j) => j is Map
    ? (
        author: (j['author_name'] as String?) ?? '',
        text: (j['preview'] as String?) ?? '',
        at: _time(j['created_at']),
      )
    : null;

/// A class chat in the list (`GET /chat/groups`).
@immutable
class ChatGroup {
  const ChatGroup({
    required this.id,
    required this.label,
    required this.classId,
    this.unread = 0,
    this.muted = false,
    this.last,
  });

  final String id;

  /// "Mathematics · Class 6 A".
  final String label;
  final String classId;
  final int unread;
  final bool muted;
  final ChatPreview? last;

  static ChatGroup? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final s = j['subject'];
    final subject = s is Map ? (s['name'] as String?) ?? '' : '';
    final section = (j['section_label'] as String?) ?? '';
    return ChatGroup(
      id: j['id'] as String,
      label: [subject, section].where((x) => x.isNotEmpty).join(' · '),
      classId: (j['class_id'] as String?) ?? '',
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      muted: j['muted'] == true,
      last: _preview(j['last_message']),
    );
  }
}

/// `GET /chat/groups/:id`.
@immutable
class ChatGroupDetail {
  const ChatGroupDetail({
    required this.id,
    required this.label,
    required this.classId,
    required this.teachers,
    required this.pinned,
    this.announcementOnly = false,
    this.readOnly = false,
    this.closed = false,
    this.muted = false,
    this.teacher = false,
  });

  final String id;
  final String label;

  /// The caller teaches this class: posts when only teachers can, pins,
  /// deletes anyone's message and sets "Only teachers can post".
  final bool teacher;
  final String classId;
  final List<String> teachers;
  final List<ChatMessage> pinned;
  final bool announcementOnly;
  final bool readOnly;
  final bool closed;
  final bool muted;

  factory ChatGroupDetail.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    return ChatGroupDetail(
      id: (j['id'] as String?) ?? '',
      label: (j['label'] as String?) ?? '',
      classId: (j['class_id'] as String?) ?? '',
      teachers: [
        if (j['teachers'] is List)
          for (final t in j['teachers'] as List)
            if (t is Map) (t['name'] as String?) ?? '',
      ],
      pinned: ChatMessage.listOf(j['pinned']),
      announcementOnly: j['announcement_only'] == true,
      readOnly: j['read_only'] == true,
      closed: j['closed'] == true,
      muted: j['muted'] == true,
      teacher: j['role'] == 'TEACHER',
    );
  }
}

/// A private chat in the list (`GET /chat/direct`).
@immutable
class DirectChat {
  const DirectChat({
    required this.id,
    required this.otherName,
    this.otherIsTeacher = false,
    this.unread = 0,
    this.closed = false,
    this.muted = false,
    this.otherReadAt,
    this.last,
  });

  final String id;
  final String otherName;
  final bool otherIsTeacher;
  final int unread;
  final bool closed;
  final bool muted;
  final DateTime? otherReadAt;
  final ChatPreview? last;

  static DirectChat? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final o = j['other'];
    return DirectChat(
      id: j['id'] as String,
      otherName: o is Map ? (o['name'] as String?) ?? '' : '',
      otherIsTeacher: o is Map && o['is_teacher'] == true,
      unread: (j['unread'] as num?)?.toInt() ?? 0,
      closed: j['closed'] == true,
      muted: j['muted'] == true,
      otherReadAt: _time(j['other_read_at']),
      last: _preview(j['last_message']),
    );
  }
}

typedef ChatFile = ({String id, String name, String mime});

/// A post, a comment or a private message.
@immutable
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatId,
    required this.authorId,
    required this.authorName,
    required this.content,
    this.parentId,
    this.authorIsTeacher = false,
    this.files = const [],
    this.replyTo,
    this.commentCount = 0,
    this.pinned = false,
    this.deleted = false,
    this.createdAt,
  });

  final String id;

  /// The group or private chat it belongs to.
  final String chatId;
  final String? parentId;
  final String authorId;
  final String authorName;
  final bool authorIsTeacher;
  final String content;
  final List<ChatFile> files;

  /// "Name: text" of the message it answers.
  final ({String name, String text})? replyTo;
  final int commentCount;
  final bool pinned;
  final bool deleted;
  final DateTime? createdAt;

  ChatMessage withPinned(bool on) => ChatMessage(
    id: id,
    chatId: chatId,
    parentId: parentId,
    authorId: authorId,
    authorName: authorName,
    authorIsTeacher: authorIsTeacher,
    content: content,
    files: files,
    replyTo: replyTo,
    commentCount: commentCount,
    pinned: on,
    deleted: deleted,
    createdAt: createdAt,
  );

  static ChatMessage? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final a = j['author'];
    final r = j['reply_to'];
    return ChatMessage(
      id: j['id'] as String,
      chatId: (j['group_id'] ?? j['chat_id'] ?? '') as String,
      parentId: j['parent_id'] as String?,
      authorId: a is Map ? (a['id'] as String?) ?? '' : '',
      authorName: a is Map ? (a['name'] as String?) ?? '' : '',
      authorIsTeacher: a is Map && a['is_teacher'] == true,
      content: (j['content'] as String?) ?? '',
      files: [
        if (j['attachments'] is List)
          for (final f in j['attachments'] as List)
            if (f is Map && f['file_id'] is String)
              (
                id: f['file_id'] as String,
                name: (f['name'] as String?) ?? '',
                mime: (f['mime'] as String?) ?? '',
              ),
      ],
      replyTo: r is Map && r['deleted'] != true
          ? (
              name: (r['author_name'] as String?) ?? '',
              text: (r['content'] as String?) ?? '',
            )
          : null,
      commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
      pinned: j['pinned'] == true,
      deleted: j['deleted'] == true,
      createdAt: _time(j['created_at']),
    );
  }

  static List<ChatMessage> listOf(Object? p) => [
    if (p is List)
      for (final m in p) ?ChatMessage.fromJson(m),
  ];
}

typedef Contact = ({String id, String name, List<String> via});

class ChatRepository {
  ChatRepository(this._api);

  final ApiClient _api;
  static const page = 30;

  Future<List<ChatGroup>> groups() async {
    final p = (await _api.get('/chat/groups')).payload;
    return [
      if (p is List)
        for (final g in p) ?ChatGroup.fromJson(g),
    ];
  }

  Future<List<DirectChat>> direct() async {
    final p = (await _api.get('/chat/direct')).payload;
    return [
      if (p is List)
        for (final c in p) ?DirectChat.fromJson(c),
    ];
  }

  Future<List<Contact>> contacts() async {
    final p = (await _api.get('/chat/direct/contacts')).payload;
    return [
      if (p is List)
        for (final c in p)
          if (c is Map && c['id'] is String)
            (
              id: c['id'] as String,
              name: (c['name'] as String?) ?? '',
              via: [
                if (c['via'] is List)
                  for (final v in c['via'] as List) '$v',
              ],
            ),
    ];
  }

  Future<DirectChat?> startWith(String userId) async => DirectChat.fromJson(
    (await _api.post('/chat/direct', data: {'user_id': userId})).payload,
  );

  Future<ChatGroupDetail> group(String id) async =>
      ChatGroupDetail.fromJson((await _api.get('/chat/groups/$id')).payload);

  /// Newest first; [before] pages back.
  Future<List<ChatMessage>> messages(String path, {DateTime? before}) async =>
      ChatMessage.listOf(
        (await _api.get(
          '$path/messages',
          query: {
            'before': before?.toUtc().toIso8601String(),
            'limit': before == null ? null : page,
          },
        )).payload,
      );

  Future<List<ChatMessage>> comments(String path, String postId) async =>
      ChatMessage.listOf(
        (await _api.get('$path/messages/$postId/comments')).payload,
      );

  Future<ChatMessage?> send(
    String path, {
    required String content,
    List<String> fileIds = const [],
    String? parentId,
    String? replyToId,
  }) async => ChatMessage.fromJson(
    (await _api.post(
      '$path/messages',
      data: {
        'content': content,
        'file_ids': fileIds,
        'parent_id': ?parentId,
        'reply_to_id': ?replyToId,
      },
    )).payload,
  );

  Future<void> delete(String path, String messageId) =>
      _api.delete('$path/messages/$messageId');

  /// Teachers: pin a post (at most 3; the oldest pin drops off) or unpin it.
  Future<void> pin(String path, String messageId, {required bool pinned}) =>
      _api.put('$path/messages/$messageId/pin', data: {'pinned': pinned});

  /// Teachers: turn "Only teachers can post" on or off.
  Future<void> setAnnouncementOnly(String groupId, {required bool on}) =>
      _api.patch('/chat/groups/$groupId', data: {'announcement_only': on});

  Future<void> read(String path) => _api.post('$path/read');

  Future<void> mute(String path, {required bool muted}) =>
      _api.put('$path/mute', data: {'muted': muted});

  /// [chatType] GROUP or DIRECT.
  Future<void> report({
    required String chatType,
    required String chatId,
    required String messageId,
    required String reason,
  }) => _api.post(
    '/chat/reports',
    data: {
      'chat_type': chatType,
      'chat_id': chatId,
      'message_id': messageId,
      'reason': reason,
    },
  );
}

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(apiClientProvider)),
);

final chatGroupsProvider = FutureProvider.autoDispose<List<ChatGroup>>((ref) {
  ref.watch(workspaceKeyProvider);
  return ref.read(chatRepositoryProvider).groups();
}, retry: (retryCount, error) => null);

final directChatsProvider = FutureProvider.autoDispose<List<DirectChat>>((ref) {
  ref.watch(workspaceKeyProvider);
  return ref.read(chatRepositoryProvider).direct();
}, retry: (retryCount, error) => null);

/// What the live chat says (Socket.IO `/chat`).
sealed class ChatEvent {}

class ChatNewMessage extends ChatEvent {
  ChatNewMessage(this.message);
  final ChatMessage message;
}

class ChatDeleted extends ChatEvent {
  ChatDeleted(this.chatId, this.messageId);
  final String chatId;
  final String messageId;
}

/// The live chat connection. A provider so tests stand in.
abstract class ChatLive {
  Stream<ChatEvent> get events;
  void dispose();
}

class SocketChatLive implements ChatLive {
  SocketChatLive(String Function() token) {
    final u = Uri.parse(AppConfig.apiBaseUrl);
    _socket = io.io(
      '${u.scheme}://${u.authority}/chat',
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          // A fresh token on each (re)connection, after any refresh.
          .setAuthFn((cb) => cb({'token': token()}))
          .disableAutoConnect()
          .build(),
    );
    _socket
      ..onConnect((_) => _socket.emit('chat:subscribe'))
      ..on('chat:message', (data) {
        final m = ChatMessage.fromJson(data);
        if (m != null) _events.add(ChatNewMessage(m));
      })
      ..on('chat:deleted', (data) {
        if (data is Map && data['id'] is String) {
          _events.add(
            ChatDeleted('${data['group_id'] ?? ''}', data['id'] as String),
          );
        }
      })
      ..connect();
  }

  late final io.Socket _socket;
  final _events = StreamController<ChatEvent>.broadcast();

  @override
  Stream<ChatEvent> get events => _events.stream;

  @override
  void dispose() {
    _socket.dispose();
    _events.close();
  }
}

final chatLiveProvider = Provider.autoDispose<ChatLive>((ref) {
  ref.watch(workspaceKeyProvider);
  final sessions = ref.watch(sessionHolderProvider);
  final live = SocketChatLive(() => sessions.current?.accessToken ?? '');
  ref.onDispose(live.dispose);
  return live;
});
