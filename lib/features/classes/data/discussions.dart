import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/file_uploader.dart';

typedef Person = ({String id, String name});

Person? _person(Object? j) => j is Map && j['id'] is String
    ? (id: j['id'] as String, name: (j['name'] as String?) ?? '')
    : null;

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

/// A subject of a class that has a discussion, with its teachers.
@immutable
class DiscussionSubject {
  const DiscussionSubject(this.id, this.label, this.teachers);
  final String id;

  /// "English — ENG".
  final String label;
  final List<Person> teachers;

  static DiscussionSubject? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final cs = j['class_subject'];
    final s = cs is Map ? cs['subject'] : null;
    final name = s is Map ? (s['name'] as String?) ?? '' : '';
    final code = s is Map ? s['code'] as String? : null;
    final teachers = j['teachers'];
    return DiscussionSubject(
      j['id'] as String,
      code != null && code.isNotEmpty ? '$name — $code' : name,
      [
        if (teachers is List)
          for (final t in teachers) ?_person(t),
      ],
    );
  }
}

/// A file on a post or message, as the API keeps it.
@immutable
class DiscussionFile {
  const DiscussionFile({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    this.url,
  });

  final String id;
  final String name;
  final String mime;
  final int size;
  final String? url;

  bool get isImage => mime.startsWith('image/');

  static List<DiscussionFile> listOf(Object? j) => [
    if (j is List)
      for (final a in j)
        if (a is Map && a['id'] is String)
          DiscussionFile(
            id: a['id'] as String,
            name: (a['file_name'] as String?) ?? '',
            mime: (a['mime_type'] as String?) ?? '',
            size: (a['size'] as num?)?.toInt() ?? 0,
            url: a['url'] as String?,
          ),
  ];

  /// What a post or message sends for an uploaded file (the web's
  /// `DiscussionAttachment`).
  static Map<String, Object?> toJson(UploadedFile f) => {
    'id': f.id,
    'key': f.id,
    'url': f.url ?? '/files/${f.id}/content',
    'file_name': f.name,
    'mime_type': f.mime,
    'size': f.size,
    'kind': f.isImage ? 'image' : 'file',
  };
}

@immutable
class DiscussionPost {
  const DiscussionPost({
    required this.id,
    required this.content,
    required this.category,
    required this.commentsCount,
    this.author,
    this.createdAt,
    this.files = const [],
  });

  final String id;
  final String content;

  /// general, question, idea or resource.
  final String category;
  final int commentsCount;
  final Person? author;
  final DateTime? createdAt;
  final List<DiscussionFile> files;

  static DiscussionPost? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return DiscussionPost(
      id: j['id'] as String,
      content: (j['content'] as String?) ?? '',
      category: (j['category'] as String?) ?? 'general',
      commentsCount: (j['comments_count'] as num?)?.toInt() ?? 0,
      author: _person(j['author']),
      createdAt: _time(j['created_at']),
      files: DiscussionFile.listOf(j['attachments']),
    );
  }
}

/// A comment on a post, or a private message.
@immutable
class DiscussionNote {
  const DiscussionNote({
    required this.id,
    required this.content,
    this.author,
    this.createdAt,
    this.files = const [],
  });

  final String id;
  final String content;
  final Person? author;
  final DateTime? createdAt;
  final List<DiscussionFile> files;

  static DiscussionNote? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    return DiscussionNote(
      id: j['id'] as String,
      content: (j['content'] as String?) ?? '',
      author: _person(j['author'] ?? j['sender']),
      createdAt: _time(j['created_at']),
      files: DiscussionFile.listOf(j['attachments']),
    );
  }
}

/// A private conversation between a student and a teacher.
@immutable
class Conversation {
  const Conversation(this.id, this.student, this.teacher);
  final String id;
  final Person? student;
  final Person? teacher;

  static Conversation? fromJson(Object? j) => j is Map && j['id'] is String
      ? Conversation(
          j['id'] as String,
          _person(j['student']),
          _person(j['teacher']),
        )
      : null;
}

/// A page of items and whether more remain.
typedef Page<T> = ({List<T> items, bool more});

class DiscussionsRepository {
  DiscussionsRepository(this._api);

  final ApiClient _api;
  static const pageSize = 20;

  String _scope(String classId, String subjectId) =>
      '/classes/$classId/subjects/$subjectId';

  Page<T> _page<T>(Object? payload, T? Function(Object?) read) {
    final p = payload is Map ? payload : const <String, Object?>{};
    final items = p['items'];
    final meta = p['meta'] is Map
        ? p['meta'] as Map
        : const <String, Object?>{};
    final page = (meta['page'] as num?)?.toInt() ?? 1;
    final pages = (meta['total_pages'] as num?)?.toInt() ?? 1;
    return (
      items: [
        if (items is List)
          for (final i in items) ?read(i),
      ],
      more: page < pages,
    );
  }

  Future<List<DiscussionSubject>> subjects(String classId) async {
    final p = (await _api.get('/classes/$classId/discussion-subjects')).payload;
    return [
      if (p is List)
        for (final s in p) ?DiscussionSubject.fromJson(s),
    ];
  }

  Future<Page<DiscussionPost>> posts(
    String classId,
    String subjectId, {
    int page = 1,
    String? category,
  }) async {
    final r = await _api.get(
      '${_scope(classId, subjectId)}/discussions',
      query: {'page': page, 'limit': pageSize, 'category': category},
    );
    return _page(r.payload, DiscussionPost.fromJson);
  }

  Future<void> post(
    String classId,
    String subjectId, {
    required String content,
    required String category,
    List<UploadedFile> files = const [],
  }) => _api.post(
    '${_scope(classId, subjectId)}/discussions',
    data: {
      'content': content,
      'category': category,
      'attachments': [for (final f in files) DiscussionFile.toJson(f)],
    },
  );

  Future<void> deletePost(String classId, String subjectId, String postId) =>
      _api.delete('${_scope(classId, subjectId)}/discussions/$postId');

  Future<List<DiscussionNote>> comments(
    String classId,
    String subjectId,
    String postId,
  ) async {
    final r = await _api.get(
      '${_scope(classId, subjectId)}/discussions/$postId/comments',
      query: {'page': 1, 'limit': pageSize},
    );
    return _page(r.payload, DiscussionNote.fromJson).items;
  }

  Future<void> comment(
    String classId,
    String subjectId,
    String postId,
    String content,
  ) => _api.post(
    '${_scope(classId, subjectId)}/discussions/$postId/comments',
    data: {'content': content},
  );

  Future<List<Conversation>> conversations(
    String classId,
    String subjectId,
  ) async {
    final p = (await _api.get(
      '${_scope(classId, subjectId)}/private-conversations',
    )).payload;
    return [
      if (p is List)
        for (final c in p) ?Conversation.fromJson(c),
    ];
  }

  /// Starts (or reopens) a conversation: a student with a teacher
  /// ([teacherId]), or a teacher with a student ([studentId]).
  Future<Conversation?> startConversation(
    String classId,
    String subjectId, {
    String? teacherId,
    String? studentId,
  }) async {
    final r = await _api.post(
      '${_scope(classId, subjectId)}/private-conversations',
      data: {'teacher_id': ?teacherId, 'student_id': ?studentId},
    );
    return Conversation.fromJson(r.payload);
  }

  Future<List<DiscussionNote>> messages(
    String classId,
    String subjectId,
    String conversationId,
  ) async {
    final r = await _api.get(
      '${_scope(classId, subjectId)}/private-conversations/$conversationId/messages',
      query: {'page': 1, 'limit': pageSize},
    );
    return _page(r.payload, DiscussionNote.fromJson).items;
  }

  Future<void> send(
    String classId,
    String subjectId,
    String conversationId, {
    required String content,
    List<UploadedFile> files = const [],
  }) => _api.post(
    '${_scope(classId, subjectId)}/private-conversations/$conversationId/messages',
    data: {
      'content': content,
      'attachments': [for (final f in files) DiscussionFile.toJson(f)],
    },
  );
}

final discussionsRepositoryProvider = Provider<DiscussionsRepository>(
  (ref) => DiscussionsRepository(ref.watch(apiClientProvider)),
);

final discussionSubjectsProvider = FutureProvider.autoDispose
    .family<List<DiscussionSubject>, String>((ref, classId) {
      ref.watch(workspaceKeyProvider);
      return ref.read(discussionsRepositoryProvider).subjects(classId);
    }, retry: (retryCount, error) => null);
