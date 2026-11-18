import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/classes/data/discussions.dart';

/// Posts and messages are read again this often (the web's POLL_MS).
const _poll = Duration(seconds: 20);
const _maxFiles = 5;
const _categories = ['general', 'question', 'idea', 'resource'];

String _categoryName(AppLocalizations l10n, String c) => switch (c) {
  'question' => l10n.discussionsCategoryQuestion,
  'idea' => l10n.discussionsCategoryIdea,
  'resource' => l10n.discussionsCategoryResource,
  _ => l10n.discussionsCategoryGeneral,
};

/// A class's discussions, kept per subject (the web's ClassDiscussions):
/// the class discussion (posts by type, with files and replies) and private
/// messages: a student's with the subject's teachers, or, when [students]
/// is given (a teacher), the teacher's with the class's joined students.
class ClassDiscussions extends ConsumerStatefulWidget {
  const ClassDiscussions({required this.classId, this.students, super.key});

  final String classId;

  /// The class's joined students, for a teacher; null for a student.
  final List<Person>? students;

  @override
  ConsumerState<ClassDiscussions> createState() => _ClassDiscussionsState();
}

class _ClassDiscussionsState extends ConsumerState<ClassDiscussions> {
  String? _subject;
  bool _private = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final subjects = ref.watch(discussionSubjectsProvider(widget.classId));
    return subjects.when(
      loading: () => SizedBox(
        height: 160,
        child: LoadingView(semanticsLabel: l10n.discussionsLoadingSubjects),
      ),
      error: (e, _) => SizedBox(
        height: 280,
        child: e is ApiException && e.statusCode == 403
            ? EmptyView(
                icon: Icons.lock_outline,
                title: ref.levels(context, l10n.discussionsSubjectsForbidden),
              )
            : ErrorView(
                title: l10n.discussionsSubjectsFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () =>
                    ref.invalidate(discussionSubjectsProvider(widget.classId)),
              ),
      ),
      data: (list) {
        if (list.isEmpty) {
          return Text(
            l10n.discussionsPickSubject,
            style: text.bodyMedium?.copyWith(color: colors.inkMuted),
          );
        }
        final subject = list.firstWhere(
          (s) => s.id == _subject,
          orElse: () => list.first,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.discussionsScoped,
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: const Key('discussion-subject'),
              initialValue: subject.id,
              decoration: InputDecoration(labelText: l10n.discussionsSubject),
              items: [
                for (final s in list)
                  DropdownMenuItem(value: s.id, child: Text(s.label)),
              ],
              onChanged: (v) => setState(() => _subject = v),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(ref.levels(context, l10n.discussionsPublic)),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(l10n.discussionsPrivate),
                ),
              ],
              selected: {_private},
              onSelectionChanged: (s) => setState(() => _private = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_private)
              _PrivateMessages(
                key: ValueKey('private-${subject.id}'),
                classId: widget.classId,
                subject: subject,
                students: widget.students,
              )
            else
              _Feed(
                key: ValueKey('feed-${subject.id}'),
                classId: widget.classId,
                subjectId: subject.id,
              ),
          ],
        );
      },
    );
  }
}

class _Feed extends ConsumerStatefulWidget {
  const _Feed({required this.classId, required this.subjectId, super.key});

  final String classId;
  final String subjectId;

  @override
  ConsumerState<_Feed> createState() => _FeedState();
}

class _FeedState extends ConsumerState<_Feed> {
  final _content = TextEditingController();
  List<DiscussionPost>? _posts;
  bool _more = false;
  int _page = 1;
  String? _filter;
  String _category = 'general';
  List<UploadedFile> _files = const [];
  bool _uploading = false;
  bool _posting = false;
  int _round = 0;
  Object? _error;
  Timer? _timer;

  DiscussionsRepository get _repo => ref.read(discussionsRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(_poll, (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _content.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false, bool next = false}) async {
    try {
      final page = next ? _page + 1 : 1;
      final r = await _repo.posts(
        widget.classId,
        widget.subjectId,
        page: page,
        category: _filter,
      );
      if (!mounted) return;
      setState(() {
        _error = null;
        _page = page;
        _more = r.more;
        _posts = next ? [...?_posts, ...r.items] : r.items;
      });
    } on ApiException catch (e) {
      if (mounted && !quiet) setState(() => _error = e);
    }
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final content = _content.text.trim();
    if (content.isEmpty) return;
    setState(() => _posting = true);
    try {
      await _repo.post(
        widget.classId,
        widget.subjectId,
        content: content,
        category: _category,
        files: _files,
      );
      if (!mounted) return;
      _content.clear();
      setState(() {
        _files = const [];
        _round++;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.levels(context, l10n.discussionsPosted))),
      );
      await _load();
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.discussionsComposerPostFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final error = _error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                key: const Key('post-content'),
                label: l10n.discussionsComposerLabel,
                hint: l10n.discussionsComposerPlaceholder,
                controller: _content,
                maxLines: 4,
                enabled: !_posting,
              ),
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: InputDecoration(
                  labelText: l10n.discussionsComposerCategory,
                ),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(
                      value: c,
                      child: Text(_categoryName(l10n, c)),
                    ),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'general'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AttachmentField(
                key: ValueKey('post-files-$_round'),
                label: l10n.discussionsComposerAttach,
                purpose: FilePurpose.discussion,
                scopeId: widget.classId,
                maxFiles: _maxFiles,
                enabled: !_posting,
                onChanged: (f) => setState(() => _files = f),
                onBusyChanged: (b) => setState(() => _uploading = b),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: AppButton(
                  key: const Key('post-submit'),
                  label: _posting
                      ? l10n.discussionsComposerPosting
                      : l10n.discussionsComposerPost,
                  loading: _posting,
                  onPressed: _uploading ? null : _submit,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final (value, label) in [
              (null, l10n.discussionsFilterAll),
              ('question', l10n.discussionsFilterQuestion),
              ('idea', l10n.discussionsFilterIdea),
              ('resource', l10n.discussionsFilterResource),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _filter == value,
                onSelected: (_) {
                  setState(() {
                    _filter = value;
                    _posts = null;
                  });
                  _load();
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        if (error != null && _posts == null)
          SizedBox(
            height: 260,
            child: error is ApiException && error.statusCode == 403
                ? EmptyView(
                    icon: Icons.lock_outline,
                    title: l10n.discussionsPostsForbidden,
                  )
                : ErrorView(
                    title: ref.levels(context, l10n.discussionsPostsFailed),
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: _load,
                  ),
          )
        else if (_posts == null)
          SizedBox(
            height: 120,
            child: LoadingView(
              semanticsLabel: ref.levels(context, l10n.discussionsPublic),
            ),
          )
        else if (_posts!.isEmpty)
          SizedBox(
            height: 220,
            child: EmptyView(
              icon: Icons.forum_outlined,
              title: l10n.discussionsFeedEmpty,
              message: l10n.discussionsFeedEmptyDetail,
            ),
          )
        else ...[
          for (final p in _posts!) ...[
            _PostCard(
              key: Key('post-${p.id}'),
              post: p,
              classId: widget.classId,
              subjectId: widget.subjectId,
              onChanged: _load,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (_more)
            TextButton(
              onPressed: () => _load(next: true),
              child: Text(l10n.discussionsFeedLoadMore),
            ),
        ],
        if (error != null && _posts != null)
          Text(
            ref.levels(context, l10n.discussionsPostsFailed),
            style: text.bodySmall?.copyWith(color: colors.danger),
          ),
      ],
    );
  }
}

class _Files extends ConsumerWidget {
  const _Files({required this.files});

  final List<DiscussionFile> files;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Wrap(
    spacing: AppSpacing.sm,
    runSpacing: AppSpacing.xs,
    children: [
      for (final f in files)
        ActionChip(
          avatar: Icon(
            f.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
            size: 18,
          ),
          label: Text(f.name, overflow: TextOverflow.ellipsis),
          onPressed: () => openFile(context, ref, f.id),
        ),
    ],
  );
}

class _PostCard extends ConsumerStatefulWidget {
  const _PostCard({
    required this.post,
    required this.classId,
    required this.subjectId,
    required this.onChanged,
    super.key,
  });

  final DiscussionPost post;
  final String classId;
  final String subjectId;
  final Future<void> Function() onChanged;

  @override
  ConsumerState<_PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<_PostCard> {
  final _reply = TextEditingController();
  List<DiscussionNote>? _comments;
  bool _open = false;
  bool _sending = false;

  DiscussionsRepository get _repo => ref.read(discussionsRepositoryProvider);

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _loadComments() async {
    try {
      final c = await _repo.comments(
        widget.classId,
        widget.subjectId,
        widget.post.id,
      );
      if (mounted) setState(() => _comments = c);
    } on ApiException {
      if (mounted) setState(() => _comments = const []);
    }
  }

  Future<void> _send() async {
    final content = _reply.text.trim();
    if (content.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _repo.comment(
        widget.classId,
        widget.subjectId,
        widget.post.id,
        content,
      );
      _reply.clear();
      await _loadComments();
      await widget.onChanged();
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.discussionsComposerSendFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete() async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.discussionsPostDeleteTitle),
        content: Text(l10n.discussionsPostDeleteDetail),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.discussionsPostCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.discussionsPostDelete),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await _repo.deletePost(widget.classId, widget.subjectId, widget.post.id);
    } on ApiException {
      // The list is read again either way.
    }
    await widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final p = widget.post;
    final mine = p.author?.id == ref.watch(sessionProvider)?.userId;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    p.author?.name,
                    if (p.createdAt != null)
                      OrgTime.dateTime(p.createdAt!, language),
                  ].whereType<String>().join(' · '),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              ),
              StatusPill(label: _categoryName(l10n, p.category)),
              if (mine)
                IconButton(
                  tooltip: l10n.discussionsPostDelete,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: _delete,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(p.content, style: text.bodyMedium),
          if (p.files.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _Files(files: p.files),
          ],
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () {
                setState(() => _open = !_open);
                if (_open && _comments == null) _loadComments();
              },
              child: Text(l10n.discussionsPostComments(p.commentsCount)),
            ),
          ),
          if (_open) ...[
            if (_comments == null)
              const LinearProgressIndicator()
            else
              for (final c in _comments!)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.author?.name ?? '',
                        style: text.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(c.content, style: text.bodyMedium),
                    ],
                  ),
                ),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: Key('reply-${p.id}'),
                    label: l10n.discussionsPostReply,
                    hint: l10n.discussionsPostReplyPlaceholder,
                    controller: _reply,
                    enabled: !_sending,
                  ),
                ),
                IconButton(
                  tooltip: l10n.discussionsPostReply,
                  icon: const Icon(Icons.send),
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PrivateMessages extends ConsumerStatefulWidget {
  const _PrivateMessages({
    required this.classId,
    required this.subject,
    this.students,
    super.key,
  });

  final String classId;
  final DiscussionSubject subject;

  /// A teacher's joined students; null for a student.
  final List<Person>? students;

  @override
  ConsumerState<_PrivateMessages> createState() => _PrivateMessagesState();
}

class _PrivateMessagesState extends ConsumerState<_PrivateMessages> {
  final _message = TextEditingController();
  List<Conversation>? _conversations;
  Conversation? _open;
  List<DiscussionNote>? _messages;
  String? _with;
  List<UploadedFile> _files = const [];
  bool _uploading = false;
  bool _sending = false;
  int _round = 0;
  Object? _error;
  Timer? _timer;

  DiscussionsRepository get _repo => ref.read(discussionsRepositoryProvider);
  String get _subjectId => widget.subject.id;

  bool get _teacher => widget.students != null;

  /// Who a conversation can be started with.
  List<Person> get _people => widget.students ?? widget.subject.teachers;

  /// The other person in a conversation.
  String _peer(Conversation c) =>
      (_teacher ? c.student?.name : c.teacher?.name) ?? '';

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _timer = Timer.periodic(_poll, (_) {
      if (_open != null) _loadMessages(quiet: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _message.dispose();
    super.dispose();
  }

  Future<void> _loadConversations() async {
    try {
      final c = await _repo.conversations(widget.classId, _subjectId);
      if (mounted) setState(() => _conversations = c);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _loadMessages({bool quiet = false}) async {
    final open = _open;
    if (open == null) return;
    try {
      final m = await _repo.messages(widget.classId, _subjectId, open.id);
      m.sort(
        (a, b) =>
            (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
      );
      if (mounted && _open?.id == open.id) setState(() => _messages = m);
    } on ApiException {
      if (mounted && !quiet) setState(() => _messages = const []);
    }
  }

  Future<void> _start() async {
    final person = _with ?? _people.firstOrNull?.id;
    if (person == null) return;
    try {
      final c = await _repo.startConversation(
        widget.classId,
        _subjectId,
        teacherId: _teacher ? null : person,
        studentId: _teacher ? person : null,
      );
      await _loadConversations();
      if (c != null && mounted) {
        setState(() {
          _open = c;
          _messages = null;
        });
        await _loadMessages();
      }
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.discussionsConversationsFailed)),
        );
      }
    }
  }

  Future<void> _send() async {
    final content = _message.text.trim();
    final open = _open;
    if (open == null || (content.isEmpty && _files.isEmpty)) return;
    setState(() => _sending = true);
    try {
      await _repo.send(
        widget.classId,
        _subjectId,
        open.id,
        content: content,
        files: _files,
      );
      _message.clear();
      setState(() {
        _files = const [];
        _round++;
      });
      await _loadMessages();
    } on ApiException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.discussionsComposerSendFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final me = ref.watch(sessionProvider)?.userId;
    if (_error != null && _conversations == null) {
      final e = _error;
      return SizedBox(
        height: 260,
        child: e is ApiException && e.statusCode == 403
            ? EmptyView(
                icon: Icons.lock_outline,
                title: l10n.discussionsConversationsForbidden,
              )
            : ErrorView(
                title: l10n.discussionsConversationsFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: _loadConversations,
              ),
      );
    }
    if (_conversations == null) {
      return SizedBox(
        height: 120,
        child: LoadingView(semanticsLabel: l10n.discussionsChatTitle),
      );
    }
    final open = _open;
    if (open == null) {
      final people = _people;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.discussionsChatIntro,
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (people.isEmpty)
            Text(
              _teacher
                  ? ref.levels(context, l10n.discussionsChatNoStudents)
                  : l10n.discussionsChatNoTeachers,
              style: text.bodyMedium,
            )
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: const Key('chat-teacher'),
                    initialValue: _with ?? people.first.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: _teacher
                          ? l10n.discussionsChatStartWithStudent
                          : l10n.discussionsChatStartWithTeacher,
                    ),
                    items: [
                      for (final t in people)
                        DropdownMenuItem(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _with = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppButton(
                  key: const Key('chat-start'),
                  label: l10n.discussionsChatStart,
                  variant: AppButtonVariant.secondary,
                  onPressed: _start,
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          Text(l10n.discussionsChatConversations, style: text.titleSmall),
          if (_conversations!.isEmpty)
            Text(
              l10n.discussionsChatNone,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            )
          else
            for (final c in _conversations!)
              ListTile(
                key: Key('conversation-${c.id}'),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(_peer(c)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  setState(() {
                    _open = c;
                    _messages = null;
                  });
                  _loadMessages();
                },
              ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: l10n.discussionsChatConversations,
              icon: const BackButtonIcon(),
              onPressed: () => setState(() => _open = null),
            ),
            Expanded(child: Text(_peer(open), style: text.titleSmall)),
          ],
        ),
        if (_messages == null)
          const LinearProgressIndicator()
        else if (_messages!.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Text(
              l10n.discussionsChatNoMessages,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
          )
        else
          for (final m in _messages!)
            Align(
              alignment: m.author?.id == me
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: m.author?.id == me
                      ? colors.primarySoft
                      : colors.canvas,
                  borderRadius: AppRadius.inputAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (m.content.isNotEmpty)
                      SelectableText(m.content, style: text.bodyMedium),
                    if (m.files.isNotEmpty) _Files(files: m.files),
                    if (m.createdAt != null)
                      Text(
                        OrgTime.dateTime(m.createdAt!, language),
                        style: text.labelSmall?.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
        AppTextField(
          key: const Key('chat-message'),
          label: l10n.discussionsChatMessage,
          hint: l10n.discussionsChatPlaceholder,
          controller: _message,
          maxLines: 3,
          enabled: !_sending,
        ),
        AttachmentField(
          key: ValueKey('chat-files-$_round'),
          label: l10n.discussionsComposerAttach,
          purpose: FilePurpose.discussion,
          scopeId: widget.classId,
          maxFiles: _maxFiles,
          enabled: !_sending,
          onChanged: (f) => setState(() => _files = f),
          onBusyChanged: (b) => setState(() => _uploading = b),
        ),
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: AppButton(
            key: const Key('chat-send'),
            label: l10n.discussionsChatSend,
            loading: _sending,
            onPressed: _uploading ? null : _send,
          ),
        ),
      ],
    );
  }
}
