import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/chat/data/chat.dart';

/// The web's /chat for a student: a chat for each subject class, and
/// private chats with their teachers; live through Socket.IO `/chat`.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  bool _private = false;
  StreamSubscription<ChatEvent>? _live;

  @override
  void initState() {
    super.initState();
    // A new message anywhere refreshes the lists (unread counts, previews).
    _live = ref.read(chatLiveProvider).events.listen((_) {
      ref
        ..invalidate(chatGroupsProvider)
        ..invalidate(directChatsProvider);
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _open(
    String path,
    String title, {
    required bool group,
    String? classId,
  }) async {
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        builder: (_) => ChatThreadScreen(
          path: path,
          title: title,
          group: group,
          classId: classId,
        ),
      ),
    );
    ref
      ..invalidate(chatGroupsProvider)
      ..invalidate(directChatsProvider);
  }

  Future<void> _newMessage() async {
    final l10n = context.l10n;
    final repo = ref.read(chatRepositoryProvider);
    List<Contact> contacts;
    try {
      contacts = await repo.contacts();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
      return;
    }
    if (!mounted) return;
    final pick = await showModalBottomSheet<Contact>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                l10n.chatPickPersonStudent,
                style: Theme.of(sheet).textTheme.titleMedium,
              ),
            ),
            for (final c in contacts)
              ListTile(
                key: Key('contact-${c.id}'),
                leading: const Icon(Icons.person_outline),
                title: Text(c.name),
                subtitle: Text(c.via.join(', ')),
                onTap: () => Navigator.of(sheet).pop(c),
              ),
          ],
        ),
      ),
    );
    if (pick == null) return;
    try {
      final chat = await repo.startWith(pick.id);
      if (chat != null && mounted) {
        await _open('/chat/direct/${chat.id}', chat.otherName, group: false);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final groups = ref.watch(chatGroupsProvider);
    final direct = ref.watch(directChatsProvider);
    Widget failure(Object e, VoidCallback retry) => SizedBox(
      height: 280,
      child: e is ApiException && e.statusCode == 403
          ? EmptyView(icon: Icons.lock_outline, title: l10n.chatNotAvailable)
          : ErrorView(
              title: l10n.chatLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: retry,
            ),
    );
    Widget tile({
      required Key key,
      required String title,
      required int unread,
      required bool muted,
      required ChatPreview? last,
      required VoidCallback onTap,
    }) => AppCard(
      key: key,
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(
                  last == null
                      ? l10n.chatNoMessages
                      : '${last.author}: ${last.text}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          ),
          if (muted)
            Icon(
              Icons.notifications_off_outlined,
              size: 18,
              color: colors.inkMuted,
            ),
          if (unread > 0)
            StatusPill(
              label: l10n.chatUnread(unread),
              tone: StatusTone.primary,
            ),
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: () async {
            ref
              ..invalidate(chatGroupsProvider)
              ..invalidate(directChatsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.chatTitle, style: text.headlineSmall),
              Text(
                l10n.chatDescriptionStudent,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(l10n.chatClassChats)),
                  ButtonSegment(
                    value: true,
                    label: Text(l10n.chatPrivateChats),
                  ),
                ],
                selected: {_private},
                onSelectionChanged: (s) => setState(() => _private = s.first),
              ),
              const SizedBox(height: AppSpacing.md),
              if (!_private)
                ...groups.when(
                  loading: () => [
                    SizedBox(
                      height: 160,
                      child: LoadingView(semanticsLabel: l10n.chatTitle),
                    ),
                  ],
                  error: (e, _) => [
                    failure(e, () => ref.invalidate(chatGroupsProvider)),
                  ],
                  data: (list) => list.isEmpty
                      ? [
                          SizedBox(
                            height: 240,
                            child: EmptyView(
                              icon: Icons.forum_outlined,
                              title: l10n.chatEmpty,
                              message: l10n.chatEmptyHintStudent,
                            ),
                          ),
                        ]
                      : [
                          for (final g in list) ...[
                            tile(
                              key: Key('group-${g.id}'),
                              title: g.label,
                              unread: g.unread,
                              muted: g.muted,
                              last: g.last,
                              onTap: () => _open(
                                '/chat/groups/${g.id}',
                                g.label,
                                group: true,
                                classId: g.classId,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                )
              else ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppButton(
                    key: const Key('new-message'),
                    label: l10n.chatNewMessageToTeacher,
                    icon: Icons.edit_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: _newMessage,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                ...direct.when(
                  loading: () => [
                    SizedBox(
                      height: 160,
                      child: LoadingView(semanticsLabel: l10n.chatPrivateChats),
                    ),
                  ],
                  error: (e, _) => [
                    failure(e, () => ref.invalidate(directChatsProvider)),
                  ],
                  data: (list) => list.isEmpty
                      ? [
                          SizedBox(
                            height: 240,
                            child: EmptyView(
                              icon: Icons.chat_bubble_outline,
                              title: l10n.chatNoPrivate,
                              message: l10n.chatNoPrivateHintStudent,
                            ),
                          ),
                        ]
                      : [
                          for (final c in list) ...[
                            tile(
                              key: Key('direct-${c.id}'),
                              title: c.otherName,
                              unread: c.unread,
                              muted: c.muted,
                              last: c.last,
                              onTap: () => _open(
                                '/chat/direct/${c.id}',
                                c.otherName,
                                group: false,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                          ],
                        ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A class chat (posts with comments, files, pinned posts) or a private
/// chat (messages): newest at the bottom, older ones on request; send,
/// reply, delete your own, report others', mute; marked read on opening.
class ChatThreadScreen extends ConsumerStatefulWidget {
  const ChatThreadScreen({
    required this.path,
    required this.title,
    required this.group,
    this.classId,
    super.key,
  });

  /// `/chat/groups/:id` or `/chat/direct/:id`.
  final String path;
  final String title;
  final bool group;
  final String? classId;

  @override
  ConsumerState<ChatThreadScreen> createState() => _ChatThreadScreenState();
}

class _ChatThreadScreenState extends ConsumerState<ChatThreadScreen> {
  final _text = TextEditingController();
  ChatGroupDetail? _detail;
  List<ChatMessage>? _messages;
  bool _older = true;
  bool _muted = false;
  ChatMessage? _replyTo;
  List<UploadedFile> _files = const [];
  bool _uploading = false;
  bool _sending = false;
  int _round = 0;
  Object? _error;
  StreamSubscription<ChatEvent>? _live;

  ChatRepository get _repo => ref.read(chatRepositoryProvider);
  String get _chatId => widget.path.split('/').last;

  @override
  void initState() {
    super.initState();
    _load();
    _live = ref.read(chatLiveProvider).events.listen(_onLive);
  }

  @override
  void dispose() {
    _live?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final detail = widget.group ? await _repo.group(_chatId) : null;
      final messages = await _repo.messages(widget.path);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _muted = detail?.muted ?? false;
        _messages = messages;
        _older = messages.isNotEmpty;
        _error = null;
      });
      unawaited(_repo.read(widget.path).catchError((Object _) {}));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadOlder() async {
    final list = _messages;
    if (list == null || list.isEmpty) return;
    try {
      final more = await _repo.messages(
        widget.path,
        before: list.last.createdAt,
      );
      if (mounted) {
        setState(() {
          _messages = [...list, ...more];
          _older = more.length >= ChatRepository.page;
        });
      }
    } on ApiException {
      // Kept as it is; the button stays.
    }
  }

  void _onLive(ChatEvent e) {
    if (!mounted || _messages == null) return;
    switch (e) {
      case ChatNewMessage(:final message)
          when message.chatId == _chatId && message.parentId == null:
        if (_messages!.any((m) => m.id == message.id)) return;
        setState(() => _messages = [message, ..._messages!]);
        unawaited(_repo.read(widget.path).catchError((Object _) {}));
      case ChatDeleted(:final messageId):
        setState(() {
          _messages = [
            for (final m in _messages!) m.id == messageId ? _deletedCopy(m) : m,
          ];
        });
      case ChatNewMessage():
        break;
    }
  }

  ChatMessage _deletedCopy(ChatMessage m) => ChatMessage(
    id: m.id,
    chatId: m.chatId,
    authorId: m.authorId,
    authorName: m.authorName,
    content: '',
    deleted: true,
    createdAt: m.createdAt,
  );

  bool get _canPost {
    final d = _detail;
    if (d == null) return true;
    return !d.readOnly && !d.closed && (d.teacher || !d.announcementOnly);
  }

  bool get _teacher => widget.group && (_detail?.teacher ?? false);

  Future<void> _pin(ChatMessage m) async {
    try {
      await _repo.pin(widget.path, m.id, pinned: !m.pinned);
      final detail = await _repo.group(_chatId);
      if (!mounted) return;
      final ids = {for (final p in detail.pinned) p.id};
      setState(() {
        _detail = detail;
        _messages = [
          for (final x in _messages!)
            x.pinned == ids.contains(x.id)
                ? x
                : x.withPinned(ids.contains(x.id)),
        ];
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorText(context.l10n, e))));
      }
    }
  }

  Future<void> _setAnnouncementOnly(bool on) async {
    try {
      await _repo.setAnnouncementOnly(_chatId, on: on);
      final detail = await _repo.group(_chatId);
      if (mounted) setState(() => _detail = detail);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorText(context.l10n, e))));
      }
    }
  }

  Future<void> _send() async {
    final content = _text.text.trim();
    if (content.isEmpty && _files.isEmpty) return;
    setState(() => _sending = true);
    try {
      final sent = await _repo.send(
        widget.path,
        content: content,
        fileIds: [for (final f in _files) f.id],
        replyToId: _replyTo?.id,
      );
      _text.clear();
      if (!mounted) return;
      setState(() {
        _replyTo = null;
        _files = const [];
        _round++;
        if (sent != null && !_messages!.any((m) => m.id == sent.id)) {
          _messages = [sent, ..._messages!];
        }
      });
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorText(context.l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(ChatMessage m) async {
    try {
      await _repo.delete(widget.path, m.id);
      if (mounted) {
        setState(
          () => _messages = [
            for (final x in _messages!) x.id == m.id ? _deletedCopy(x) : x,
          ],
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorText(context.l10n, e))));
      }
    }
  }

  Future<void> _report(ChatMessage m) async {
    final l10n = context.l10n;
    final why = await showDialog<String>(
      context: context,
      builder: (_) => const _ReportDialog(),
    );
    if (why == null || !mounted) return;
    try {
      await _repo.report(
        chatType: widget.group ? 'GROUP' : 'DIRECT',
        chatId: _chatId,
        messageId: m.id,
        reason: why,
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.chatReported)));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    }
  }

  Future<void> _setMute(bool muted) async {
    setState(() => _muted = muted);
    try {
      await _repo.mute(widget.path, muted: muted);
    } on ApiException {
      if (mounted) setState(() => _muted = !muted);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final d = _detail;
    final error = _error;
    return Scaffold(
      appBar: AppBar(
        title: Text(d?.label.isNotEmpty == true ? d!.label : widget.title),
        actions: [
          IconButton(
            key: const Key('mute'),
            tooltip: l10n.chatMute,
            icon: Icon(
              _muted ? Icons.notifications_off : Icons.notifications_none,
            ),
            onPressed: _messages == null ? null : () => _setMute(!_muted),
          ),
        ],
      ),
      body: SafeArea(
        child: error != null && _messages == null
            ? (error is ApiException && error.statusCode == 403
                  ? EmptyView(
                      icon: Icons.lock_outline,
                      title: l10n.chatNotAvailable,
                    )
                  : ErrorView(
                      title: l10n.chatLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: _load,
                    ))
            : _messages == null
            ? LoadingView(semanticsLabel: widget.title)
            : Column(
                children: [
                  if (d != null && d.teachers.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        0,
                      ),
                      child: Text(
                        l10n.chatTeachers(d.teachers.join(', ')),
                        style: text.bodySmall?.copyWith(color: colors.inkMuted),
                      ),
                    ),
                  if (d != null && _teacher && !d.readOnly && !d.closed)
                    SwitchListTile(
                      key: const Key('announcement-only'),
                      dense: true,
                      title: Text(l10n.chatAnnouncementOnly),
                      subtitle: Text(l10n.chatAnnouncementOnlyHint),
                      value: d.announcementOnly,
                      onChanged: _setAnnouncementOnly,
                    ),
                  Expanded(
                    child: ListView(
                      reverse: true,
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      children: [
                        for (final m in _messages!)
                          _MessageTile(
                            key: Key('msg-${m.id}'),
                            message: m,
                            path: widget.path,
                            group: widget.group,
                            onReply: _canPost
                                ? () => setState(() => _replyTo = m)
                                : null,
                            teacher: _teacher,
                            onPin: _teacher && m.parentId == null
                                ? () => _pin(m)
                                : null,
                            onDelete: () => _delete(m),
                            onReport: () => _report(m),
                          ),
                        if (_older && _messages!.isNotEmpty)
                          TextButton(
                            onPressed: _loadOlder,
                            child: Text(l10n.chatLoadOlder),
                          ),
                        if (d != null && d.pinned.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: colors.infoSoft,
                              borderRadius: AppRadius.inputAll,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(l10n.chatPinned, style: text.labelMedium),
                                for (final p in d.pinned)
                                  Text(
                                    '${p.authorName}: ${p.content}',
                                    style: text.bodySmall,
                                  ),
                              ],
                            ),
                          ),
                        if (_messages!.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.xl),
                            child: Text(
                              l10n.chatNoMessages,
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _composer(context),
                ],
              ),
      ),
    );
  }

  Widget _composer(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final d = _detail;
    final note = d == null
        ? null
        : d.closed
        ? l10n.chatClosedBySchool
        : d.readOnly
        ? l10n.chatReadOnly
        : d.announcementOnly && !d.teacher
        ? l10n.chatTeachersOnly
        : null;
    return Material(
      color: colors.surface,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: note != null
            ? Text(
                note,
                key: const Key('chat-note'),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_replyTo != null)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.chatReplyingTo(
                              _replyTo!.authorName,
                              _replyTo!.content,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _replyTo = null),
                          child: Text(l10n.chatCancel),
                        ),
                      ],
                    ),
                  if (widget.group &&
                      widget.classId != null &&
                      widget.classId!.isNotEmpty)
                    AttachmentField(
                      key: ValueKey('chat-files-$_round'),
                      label: l10n.chatAttach,
                      purpose: FilePurpose.discussion,
                      scopeId: widget.classId,
                      maxFiles: 5,
                      enabled: !_sending,
                      onChanged: (f) => setState(() => _files = f),
                      onBusyChanged: (b) => setState(() => _uploading = b),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('chat-text'),
                          controller: _text,
                          minLines: 1,
                          maxLines: 4,
                          enabled: !_sending,
                          decoration: InputDecoration(
                            hintText: widget.group
                                ? l10n.chatNewPost
                                : l10n.chatMessage,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('chat-send'),
                        tooltip: l10n.chatSend,
                        icon: const Icon(Icons.send),
                        onPressed: _sending || _uploading ? null : _send,
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _MessageTile extends ConsumerWidget {
  const _MessageTile({
    required this.message,
    required this.path,
    required this.group,
    required this.onDelete,
    required this.onReport,
    this.onReply,
    this.onPin,
    this.teacher = false,
    super.key,
  });

  final ChatMessage message;

  /// The caller teaches this class: may delete anyone's message.
  final bool teacher;
  final VoidCallback? onPin;
  final String path;
  final bool group;
  final VoidCallback? onReply;
  final VoidCallback onDelete;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final m = message;
    final mine = m.authorId == ref.watch(sessionProvider)?.userId;
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mine ? colors.primarySoft : colors.surface,
          borderRadius: AppRadius.inputAll,
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  m.authorName,
                  style: text.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (m.authorIsTeacher)
                  StatusPill(label: l10n.chatTeacher, tone: StatusTone.primary),
                if (m.pinned)
                  StatusPill(
                    label: l10n.chatPinnedBadge,
                    tone: StatusTone.info,
                  ),
                if (m.createdAt != null)
                  Text(
                    OrgTime.dateTime(m.createdAt!, language),
                    style: text.labelSmall?.copyWith(color: colors.inkMuted),
                  ),
              ],
            ),
            if (m.replyTo != null)
              Container(
                margin: const EdgeInsets.only(top: AppSpacing.xs),
                padding: const EdgeInsets.all(AppSpacing.xs),
                color: colors.canvas,
                child: Text(
                  '${m.replyTo!.name}: ${m.replyTo!.text}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodySmall,
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
            if (m.deleted)
              Text(
                l10n.chatDeleted,
                style: text.bodyMedium?.copyWith(
                  color: colors.inkMuted,
                  fontStyle: FontStyle.italic,
                ),
              )
            else ...[
              if (m.content.isNotEmpty)
                SelectableText(m.content, style: text.bodyMedium),
              for (final f in m.files)
                TextButton.icon(
                  icon: Icon(
                    f.mime.startsWith('image/')
                        ? Icons.image_outlined
                        : Icons.attach_file,
                  ),
                  label: Text(f.name),
                  onPressed: () => openFile(context, ref, f.id),
                ),
              Wrap(
                spacing: AppSpacing.xs,
                children: [
                  if (group)
                    TextButton(
                      key: Key('comments-${m.id}'),
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        builder: (_) => _Comments(path: path, post: m),
                      ),
                      child: Text(l10n.chatComments(m.commentCount)),
                    ),
                  if (onReply != null)
                    TextButton(onPressed: onReply, child: Text(l10n.chatReply)),
                  if (onPin != null)
                    TextButton(
                      key: Key('pin-${m.id}'),
                      onPressed: onPin,
                      child: Text(m.pinned ? l10n.chatUnpin : l10n.chatPin),
                    ),
                  if (mine || teacher)
                    TextButton(
                      key: Key('delete-${m.id}'),
                      onPressed: onDelete,
                      child: Text(l10n.chatDelete),
                    ),
                  if (!mine)
                    TextButton(
                      key: Key('report-${m.id}'),
                      onPressed: onReport,
                      child: Text(l10n.chatReport),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A post's comments, and writing one (students may comment even when only
/// teachers post).
class _Comments extends ConsumerStatefulWidget {
  const _Comments({required this.path, required this.post});

  final String path;
  final ChatMessage post;

  @override
  ConsumerState<_Comments> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<_Comments> {
  final _text = TextEditingController();
  List<ChatMessage>? _comments;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final c = await ref
          .read(chatRepositoryProvider)
          .comments(widget.path, widget.post.id);
      if (mounted) setState(() => _comments = c);
    } on ApiException {
      if (mounted) setState(() => _comments = const []);
    }
  }

  Future<void> _send() async {
    final content = _text.text.trim();
    if (content.isEmpty) return;
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .send(widget.path, content: content, parentId: widget.post.id);
      _text.clear();
      await _load();
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorText(context.l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.chatCommentsLabel, style: text.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (_comments == null)
              const LinearProgressIndicator()
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _comments!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.authorName, style: text.labelMedium),
                        subtitle: Text(
                          c.deleted ? l10n.chatDeleted : c.content,
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('comment-text'),
                    controller: _text,
                    enabled: !_sending,
                    decoration: InputDecoration(hintText: l10n.chatNewComment),
                  ),
                ),
                IconButton(
                  key: const Key('comment-send'),
                  tooltip: l10n.chatSend,
                  icon: const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Report this message": pops the reason, or nothing when cancelled.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog();

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.chatReportTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.chatReportDetail),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('report-reason'),
              controller: _reason,
              maxLines: 3,
              decoration: InputDecoration(labelText: l10n.chatReportReason),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.chatCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          child: Text(l10n.chatReportSend),
        ),
      ],
    );
  }
}
