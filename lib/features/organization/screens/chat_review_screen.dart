import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/chat/data/chat.dart';

typedef AdminChat = ({
  String type,
  String id,
  String label,
  bool closed,
  DateTime? last,
});

AdminChat? _chat(Object? c) {
  if (c is! Map || c['id'] is! String) return null;
  final last = c['last_message_at'] ?? c['last_activity_at'];
  return (
    type: (c['type'] as String?) ?? 'GROUP',
    id: c['id'] as String,
    label: (c['label'] as String?) ?? '',
    closed: c['closed'] == true,
    last: last is String ? DateTime.tryParse(last) : null,
  );
}

final adminChatsProvider = FutureProvider.autoDispose<List<AdminChat>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/chat/admin/chats'))
      .payload;
  return [
    if (p is List)
      for (final c in p) ?_chat(c),
  ];
}, retry: (retryCount, error) => null);

typedef ChatReport = ({
  String id,
  String chatLabel,
  String reporter,
  String reason,
  List<String> context,
  bool open,
  String? resolution,
  String? resolvedBy,
});

final chatReportsProvider = FutureProvider.autoDispose
    .family<List<ChatReport>, String>((ref, status) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get('/chat/admin/reports', query: {'status': status}))
              .payload;
      return [
        if (p is List)
          for (final r in p)
            if (r is Map && r['id'] is String)
              (
                id: r['id'] as String,
                chatLabel: (r['chat_label'] as String?) ?? '',
                reporter: r['reporter'] is Map
                    ? ((r['reporter'] as Map)['name'] as String?) ?? ''
                    : '',
                reason: (r['reason'] as String?) ?? '',
                context: [
                  if (r['context'] is List)
                    for (final m in r['context'] as List)
                      if (m is Map)
                        '${m['author_name'] ?? ''}: ${(m['content'] as String?)?.isNotEmpty == true ? m['content'] : (m['files'] is List && (m['files'] as List).isNotEmpty ? (m['files'] as List).join(', ') : '\u0000')}',
                ],
                open: r['status'] != 'RESOLVED',
                resolution: r['resolution'] as String?,
                resolvedBy: r['resolved_by'] is Map
                    ? (r['resolved_by'] as Map)['name'] as String?
                    : null,
              ),
      ];
    }, retry: (retryCount, error) => null);

typedef AccessRow = ({
  String id,
  DateTime? when,
  String who,
  String chat,
  String reason,
});

final chatAccessLogProvider = FutureProvider.autoDispose<List<AccessRow>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/chat/admin/access-log'))
      .payload;
  return [
    if (p is List)
      for (final r in p)
        if (r is Map && r['id'] is String)
          (
            id: r['id'] as String,
            when: r['opened_at'] is String
                ? DateTime.tryParse(r['opened_at'] as String)
                : null,
            who: r['actor'] is Map
                ? ((r['actor'] as Map)['name'] as String?) ?? ''
                : '',
            chat: (r['chat_label'] as String?) ?? '',
            reason: (r['reason'] as String?) ?? '',
          ),
  ];
}, retry: (retryCount, error) => null);

String _failText(BuildContext context, Object e) {
  final l10n = context.l10n;
  return e is ApiException && e.statusCode == 403
      ? l10n.chatReviewNotAllowed
      : l10n.chatReviewLoadFailed;
}

/// The web's /chat-admin: the organisation's chats (opening one asks for a
/// reason, which is logged; its messages then show with delete and mute,
/// and the chat can be closed), reports to keep or delete, and (owners) the
/// access log.
class ChatReviewScreen extends ConsumerStatefulWidget {
  const ChatReviewScreen({super.key});

  @override
  ConsumerState<ChatReviewScreen> createState() => _ChatReviewScreenState();
}

class _ChatReviewScreenState extends ConsumerState<ChatReviewScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final owner = ref.watch(sessionProvider)?.memberRole == 'OWNER';
    final tabs = [
      l10n.chatReviewChats,
      l10n.chatReviewReports,
      if (owner) l10n.chatReviewAccessLog,
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.chatReviewTitle, style: text.headlineSmall),
            Text(
              l10n.chatReviewDescription,
              style: text.bodySmall?.copyWith(
                color: AppColors.of(context).inkMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SegmentedButton<int>(
              key: const Key('review-tabs'),
              segments: [
                for (final (i, label) in tabs.indexed)
                  ButtonSegment(value: i, label: Text(label)),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            const SizedBox(height: AppSpacing.md),
            switch (_tab) {
              0 => const _ChatsTab(),
              1 => const _ReportsTab(),
              _ => const _AccessLogTab(),
            },
          ],
        ),
      ),
    );
  }
}

class _ChatsTab extends ConsumerWidget {
  const _ChatsTab();

  Future<void> _open(BuildContext context, WidgetRef ref, AdminChat c) async {
    final opened = await showDialog<Object?>(
      context: context,
      builder: (_) => _ReasonDialog(chat: c),
    );
    if (opened == null || !context.mounted) return;
    await Navigator.of(context, rootNavigator: true).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => OpenedChatScreen(chat: c, payload: opened),
      ),
    );
    ref.invalidate(adminChatsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final chats = ref.watch(adminChatsProvider);
    return chats.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => SizedBox(
        height: 240,
        child: ErrorView(
          title: _failText(context, e),
          retryLabel: l10n.uiErrorRetry,
          onRetry: () => ref.invalidate(adminChatsProvider),
        ),
      ),
      data: (list) => list.isEmpty
          ? Text(l10n.chatReviewNoChats, style: muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final c in list) ...[
                  AppCard(
                    key: Key('chat-${c.type}-${c.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(c.label, style: text.titleSmall),
                        Wrap(
                          spacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              c.type == 'DIRECT'
                                  ? l10n.chatReviewTypesDIRECT
                                  : l10n.chatReviewTypesGROUP,
                              style: muted,
                            ),
                            StatusPill(
                              label: c.closed
                                  ? l10n.chatReviewClosed
                                  : l10n.chatReviewOpen,
                              tone: c.closed
                                  ? StatusTone.danger
                                  : StatusTone.success,
                            ),
                            if (c.last != null)
                              Text(
                                OrgTime.dateTime(c.last!, language),
                                style: muted,
                              ),
                          ],
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: OutlinedButton(
                            key: Key('open-${c.id}'),
                            onPressed: () => _open(context, ref, c),
                            child: Text(l10n.chatReviewOpenChat),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
            ),
    );
  }
}

/// Opening a chat needs a reason (logged). Pops the answer of `…/open`.
class _ReasonDialog extends ConsumerStatefulWidget {
  const _ReasonDialog({required this.chat});

  final AdminChat chat;

  @override
  ConsumerState<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends ConsumerState<_ReasonDialog> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post(
            '/chat/admin/chats/${widget.chat.type}/${widget.chat.id}/open',
            data: {'reason': _reason.text.trim()},
          );
      navigator.pop(r.payload ?? const <String, Object?>{});
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.chatReviewReasonTitle(widget.chat.label)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.chatReviewReasonDetail),
            TextField(
              key: const Key('open-reason'),
              controller: _reason,
              maxLength: 300,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(labelText: l10n.chatReviewReason),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.chatReviewCancel),
        ),
        FilledButton(
          key: const Key('open-confirm'),
          onPressed: _busy || _reason.text.trim().isEmpty ? null : _open,
          child: Text(l10n.chatReviewOpenChat),
        ),
      ],
    );
  }
}

/// A chat opened with a reason: its messages (newest first) with delete
/// and mute, and close or reopen it.
class OpenedChatScreen extends ConsumerStatefulWidget {
  const OpenedChatScreen({
    required this.chat,
    required this.payload,
    super.key,
  });

  final AdminChat chat;
  final Object? payload;

  @override
  ConsumerState<OpenedChatScreen> createState() => _OpenedChatScreenState();
}

class _OpenedChatScreenState extends ConsumerState<OpenedChatScreen> {
  late bool _closed = widget.chat.closed;
  late List<ChatMessage> _messages = ChatMessage.listOf(
    widget.payload is Map ? (widget.payload! as Map)['messages'] : null,
  );

  String get _path => '/chat/admin/chats/${widget.chat.type}/${widget.chat.id}';

  Future<bool> _act(Future<void> Function() call, String done) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      return true;
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      return false;
    }
  }

  Future<void> _mute(ChatMessage m) async {
    final body = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (_) => _MuteDialog(name: m.authorName),
    );
    if (body == null || !mounted) return;
    await _act(
      () => ref
          .read(apiClientProvider)
          .post('$_path/mutes', data: {'user_id': m.authorId, ...body}),
      context.l10n.chatReviewMutedDone,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.chat.label)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(
                  l10n.chatReviewReadingNote,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
                SwitchListTile(
                  key: const Key('chat-closed'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.chatReviewCloseChat),
                  subtitle: Text(l10n.chatReviewCloseChatHint),
                  value: _closed,
                  onChanged: (v) async {
                    if (await _act(
                      () => ref
                          .read(apiClientProvider)
                          .put('$_path/closed', data: {'closed': v}),
                      v
                          ? l10n.chatReviewClosedDone
                          : l10n.chatReviewReopenedDone,
                    )) {
                      setState(() => _closed = v);
                    }
                  },
                ),
                const Divider(),
                if (_messages.isEmpty) Text(l10n.chatReviewNoMessages),
                for (final m in _messages)
                  AppCard(
                    key: Key('rmsg-${m.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          [
                            m.authorName,
                            if (m.createdAt != null)
                              OrgTime.dateTime(m.createdAt!, language),
                          ].join(' · '),
                          style: text.labelMedium,
                        ),
                        Text(
                          m.deleted
                              ? l10n.chatReviewDeletedMessage
                              : m.content.isNotEmpty
                              ? m.content
                              : m.files.map((f) => f.name).join(', '),
                        ),
                        if (!m.deleted)
                          Wrap(
                            alignment: WrapAlignment.end,
                            spacing: AppSpacing.xs,
                            children: [
                              TextButton(
                                key: Key('rdelete-${m.id}'),
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.danger,
                                ),
                                onPressed: () async {
                                  if (await _act(
                                    () => ref
                                        .read(apiClientProvider)
                                        .delete('$_path/messages/${m.id}'),
                                    l10n.chatReviewDeletedDone,
                                  )) {
                                    setState(
                                      () => _messages = [
                                        for (final x in _messages)
                                          if (x.id != m.id) x,
                                      ],
                                    );
                                  }
                                },
                                child: Text(l10n.chatReviewDelete),
                              ),
                              TextButton(
                                key: Key('rmute-${m.id}'),
                                onPressed: () => _mute(m),
                                child: Text(
                                  l10n.chatReviewMuteAuthor(m.authorName),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mute someone for 1 hour to 30 days, with an optional reason. Pops the
/// request body.
class _MuteDialog extends StatefulWidget {
  const _MuteDialog({required this.name});

  final String name;

  @override
  State<_MuteDialog> createState() => _MuteDialogState();
}

class _MuteDialogState extends State<_MuteDialog> {
  int _hours = 24;
  final _why = TextEditingController();

  @override
  void dispose() {
    _why.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.chatReviewMuteTitle(widget.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.chatReviewMuteDetail),
            DropdownButtonFormField<int>(
              key: const Key('mute-hours'),
              initialValue: _hours,
              decoration: InputDecoration(labelText: l10n.chatReviewMuteFor),
              items: [
                for (final h in [1, 24, 72, 168, 720])
                  DropdownMenuItem(
                    value: h,
                    child: Text(l10n.chatReviewHours(h)),
                  ),
              ],
              onChanged: (v) => setState(() => _hours = v ?? _hours),
            ),
            TextField(
              key: const Key('mute-why'),
              controller: _why,
              maxLength: 300,
              decoration: InputDecoration(
                labelText: l10n.chatReviewReasonOptional,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.chatReviewCancel),
        ),
        FilledButton(
          key: const Key('mute-confirm'),
          onPressed: () =>
              Navigator.of(context)
                  .pop({'hours': _hours, 'reason': _why.text.trim()}),
          child: Text(l10n.chatReviewMute),
        ),
      ],
    );
  }
}

class _ReportsTab extends ConsumerStatefulWidget {
  const _ReportsTab();

  @override
  ConsumerState<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<_ReportsTab> {
  String _status = 'OPEN';

  Future<void> _resolve(ChatReport r, String resolution) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(apiClientProvider)
          .post(
            '/chat/admin/reports/${r.id}/resolve',
            data: {'resolution': resolution},
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            resolution == 'DELETED'
                ? l10n.chatReviewResolvedDELETED
                : l10n.chatReviewResolvedKEPT,
          ),
        ),
      );
      ref.invalidate(chatReportsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final reports = ref.watch(chatReportsProvider(_status));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: const Key('reports-status'),
          initialValue: _status,
          decoration: InputDecoration(labelText: l10n.chatReviewShow),
          items: [
            DropdownMenuItem(
              value: 'OPEN',
              child: Text(l10n.chatReviewStatusOpen),
            ),
            DropdownMenuItem(
              value: 'RESOLVED',
              child: Text(l10n.chatReviewStatusResolved),
            ),
          ],
          onChanged: (v) => setState(() => _status = v ?? _status),
        ),
        const SizedBox(height: AppSpacing.sm),
        ...reports.when(
          loading: () => [const LinearProgressIndicator()],
          error: (e, _) => [
            SizedBox(
              height: 240,
              child: ErrorView(
                title: _failText(context, e),
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(chatReportsProvider(_status)),
              ),
            ),
          ],
          data: (list) => [
            if (list.isEmpty)
              Text(
                _status == 'OPEN'
                    ? l10n.chatReviewNoReports
                    : l10n.chatReviewNoResolved,
                style: muted,
              ),
            for (final r in list) ...[
              AppCard(
                key: Key('report-${r.id}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(r.chatLabel, style: text.titleSmall),
                    Text(l10n.chatReviewReportedBy(r.reporter, r.reason)),
                    Container(
                      margin: const EdgeInsets.only(top: AppSpacing.xs),
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      color: colors.canvas,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final line in r.context)
                            Text(
                              line.replaceAll(
                                '\u0000',
                                l10n.chatReviewDeletedMessage,
                              ),
                              style: text.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    if (r.open)
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.xs,
                        children: [
                          OutlinedButton(
                            key: Key('keep-${r.id}'),
                            onPressed: () => _resolve(r, 'KEPT'),
                            child: Text(l10n.chatReviewKeep),
                          ),
                          FilledButton(
                            key: Key('delete-msg-${r.id}'),
                            style: FilledButton.styleFrom(
                              backgroundColor: colors.danger,
                            ),
                            onPressed: () => _resolve(r, 'DELETED'),
                            child: Text(l10n.chatReviewDeleteMessage),
                          ),
                        ],
                      )
                    else
                      Text(
                        r.resolution == 'DELETED'
                            ? l10n.chatReviewResolutionDELETED(
                                r.resolvedBy ?? '—',
                              )
                            : l10n.chatReviewResolutionKEPT(
                                r.resolvedBy ?? '—',
                              ),
                        style: muted,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ],
    );
  }
}

class _AccessLogTab extends ConsumerWidget {
  const _AccessLogTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final rows = ref.watch(chatAccessLogProvider);
    return rows.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => SizedBox(
        height: 240,
        child: ErrorView(
          title: _failText(context, e),
          retryLabel: l10n.uiErrorRetry,
          onRetry: () => ref.invalidate(chatAccessLogProvider),
        ),
      ),
      data: (list) => list.isEmpty
          ? Text(l10n.chatReviewNoAccess, style: muted)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in list)
                  ListTile(
                    key: Key('access-${r.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text('${r.who} · ${r.chat}'),
                    subtitle: Text(
                      [
                        if (r.when != null) OrgTime.dateTime(r.when!, language),
                        r.reason,
                      ].join(' · '),
                    ),
                  ),
              ],
            ),
    );
  }
}
