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
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/organization/data/log_names.g.dart';

const _pageSize = 20;

/// A school day's start in the organisation's time zone, as the API wants
/// it; [next] gives the start of the day after (an inclusive "to").
String? dayBoundary(String? day, {bool next = false}) {
  if (day == null || day.isEmpty) return null;
  final start = DateTime.parse('${day}T00:00:00Z').subtract(OrgTime.offset);
  return (next ? start.add(const Duration(days: 1)) : start).toIso8601String();
}

/// The areas the activity log can be filtered by, in the web's order.
const auditAreas = [
  'member', 'subscription', 'plan', 'payment', 'feature_request', 'exam', //
  'grade', 'grading_scale', 'organization', 'teacher_request', 'user',
  'teacher', 'message_template', 'sms_credits', 'guardian', 'student',
  'attendance_settings', 'holiday', 'branch', 'section_attendance',
  'schedule', 'attendance', 'homework', 'routine', 'event', 'reminders',
  'offline_exam', 'behaviour', 'score', 'performance', 'report_card',
];

typedef LogPage<T> = ({List<T> rows, int pages});

typedef AuditRow = ({
  String id,
  DateTime? when,
  String? actor,
  bool hasActor,
  String action,
  Map<String, Object?> before,
  Map<String, Object?> after,
  String? reason,
});

typedef AuditQuery = ({int page, String area, String? from, String? to});

final auditLogProvider = FutureProvider.autoDispose
    .family<LogPage<AuditRow>, AuditQuery>((ref, q) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/audit-logs',
            query: {
              'page': q.page,
              'limit': _pageSize,
              'action': q.area.isEmpty ? null : '${q.area}.',
              'from': dayBoundary(q.from),
              'to': dayBoundary(q.to, next: true),
            },
          );
      Map<String, Object?> map(Object? v) =>
          v is Map ? v.cast<String, Object?>() : const {};
      return (
        rows: [
          if (r.payload is List)
            for (final a in r.payload! as List)
              if (a is Map && a['id'] is String)
                (
                  id: a['id'] as String,
                  when: a['created_at'] is String
                      ? DateTime.tryParse(a['created_at'] as String)
                      : null,
                  actor: a['actor'] is Map
                      ? (a['actor'] as Map)['full_name'] as String?
                      : null,
                  hasActor: a['actor'] is Map,
                  action: (a['action'] as String?) ?? '',
                  before: map(a['before']),
                  after: map(a['after']),
                  reason: a['reason'] as String?,
                ),
        ],
        pages: r.meta?.totalPages ?? 1,
      );
    }, retry: (retryCount, error) => null);

/// The fields that differ between before and after (all of them for a
/// create or delete), as the web lists them.
List<
  ({String key, Object? before, Object? after, bool hadBefore, bool hasAfter})
>
auditChanges(Map<String, Object?> before, Map<String, Object?> after) => [
  for (final key in {...before.keys, ...after.keys})
    if ('${before[key]}' != '${after[key]}')
      (
        key: key,
        before: before[key],
        after: after[key],
        hadBefore: before[key] != null,
        hasAfter: after.containsKey(key),
      ),
];

/// The paging row under a log.
class _Pager extends StatelessWidget {
  const _Pager({required this.page, required this.pages, required this.onPage});

  final int page;
  final int pages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    if (pages <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          key: const Key('log-prev'),
          tooltip: MaterialLocalizations.of(context).previousPageTooltip,
          icon: const Icon(Icons.chevron_left),
          onPressed: page > 1 ? () => onPage(page - 1) : null,
        ),
        Text(
          '${OrgTime.number(page, language)} / ${OrgTime.number(pages, language)}',
        ),
        IconButton(
          key: const Key('log-next'),
          tooltip: MaterialLocalizations.of(context).nextPageTooltip,
          icon: const Icon(Icons.chevron_right),
          onPressed: page < pages ? () => onPage(page + 1) : null,
        ),
      ],
    );
  }
}

/// The web's /activity-log: who changed what in this workspace and when,
/// by area and dates, 20 at a time; a row opens what changed.
class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen> {
  int _page = 1;
  String _area = '';
  String? _from;
  String? _to;

  String _value(String field, Object? v) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    if (v == null || v == '') return '—';
    if (v is bool) return v ? l10n.auditYes : l10n.auditNo;
    if (v is num) return OrgTime.number(v, language);
    if (v is String) {
      if (RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}').hasMatch(v)) {
        final t = DateTime.tryParse(v);
        if (t != null) return OrgTime.dateTime(t, language);
      }
      return v;
    }
    final s = '$v';
    return s.length > 80 ? '${s.substring(0, 79)}…' : s;
  }

  String _change(
    ({String key, Object? before, Object? after, bool hadBefore, bool hasAfter})
    c,
  ) {
    final l10n = context.l10n;
    if (!c.hadBefore) return _value(c.key, c.after);
    if (!c.hasAfter) return _value(c.key, c.before);
    return l10n.auditBeforeAfter(
      _value(c.key, c.before),
      _value(c.key, c.after),
    );
  }

  String _field(String key) =>
      auditFieldName(context.l10n, key) ?? key.replaceAll('_', ' ');

  void _details(AuditRow r) {
    final l10n = context.l10n;
    final changes = auditChanges(r.before, r.after);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.8,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                auditActionName(l10n, r.action) ?? r.action,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if ((r.reason ?? '').isNotEmpty)
                Text(l10n.auditReasonValue(r.reason!)),
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.auditChanges,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              if (changes.isEmpty) Text(l10n.auditNoChanges),
              for (final c in changes)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(_field(c.key)),
                  subtitle: Text(_change(c)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final query = (page: _page, area: _area, from: _from, to: _to);
    final log = ref.watch(auditLogProvider(query));
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final filtered = _area.isNotEmpty || _from != null || _to != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.auditOrganizationTitle, style: text.headlineSmall),
            Text(l10n.auditOrganizationIntro, style: muted),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: const Key('audit-area'),
              initialValue: _area,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.auditArea),
              items: [
                DropdownMenuItem(value: '', child: Text(l10n.auditAllAreas)),
                for (final a in auditAreas)
                  DropdownMenuItem(
                    value: a,
                    child: Text(auditAreaName(l10n, a) ?? a),
                  ),
              ],
              onChanged: (v) => setState(() {
                _area = v ?? '';
                _page = 1;
              }),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DateField(
                    key: const Key('audit-from'),
                    label: l10n.auditFrom,
                    value: _from,
                    onChanged: (v) => setState(() {
                      _from = v;
                      _page = 1;
                    }),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DateField(
                    key: const Key('audit-to'),
                    label: l10n.auditTo,
                    value: _to,
                    min: _from,
                    onChanged: (v) => setState(() {
                      _to = v;
                      _page = 1;
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...log.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [
                SizedBox(
                  height: 240,
                  child: ErrorView(
                    title: e is ApiException
                        ? apiErrorText(l10n, e)
                        : l10n.auditLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(auditLogProvider(query)),
                  ),
                ),
              ],
              data: (p) => [
                if (p.rows.isEmpty)
                  Text(
                    filtered ? l10n.auditEmptyFiltered : l10n.auditEmpty,
                    style: muted,
                  ),
                for (final r in p.rows) ...[
                  AppCard(
                    key: Key('audit-${r.id}'),
                    child: InkWell(
                      onTap: () => _details(r),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            auditActionName(l10n, r.action) ?? r.action,
                            style: text.titleSmall,
                          ),
                          Text(
                            [
                              r.actor ??
                                  (r.hasActor
                                      ? l10n.auditUnknownUser
                                      : l10n.auditSystem),
                              if (r.when != null)
                                OrgTime.dateTime(r.when!, language),
                            ].join(' · '),
                            style: muted,
                          ),
                          Builder(
                            builder: (context) {
                              final changes = auditChanges(r.before, r.after);
                              final parts = [
                                for (final c in changes.take(2))
                                  '${_field(c.key)}: ${_change(c)}',
                                if (changes.length > 2)
                                  l10n.auditMore(changes.length - 2),
                              ];
                              return parts.isEmpty
                                  ? const SizedBox.shrink()
                                  : Text(
                                      parts.join(' · '),
                                      style: text.bodySmall,
                                    );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _Pager(
                  page: _page,
                  pages: p.pages,
                  onPage: (v) => setState(() => _page = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

typedef MessageRow = ({
  String id,
  DateTime? when,
  String event,
  String channel,
  String status,
  String? recipientId,
  String? recipient,
  String? toAddress,
  String? subject,
  String? body,
  int credits,
  String? error,
});

typedef MessageQuery = ({
  int page,
  String area,
  String channel,
  String status,
  String? from,
  String? to,
  String? recipient,
});

final messageLogProvider = FutureProvider.autoDispose
    .family<LogPage<MessageRow>, MessageQuery>((ref, q) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/notifications/log',
            query: {
              'page': q.page,
              'limit': _pageSize,
              'event_type': q.area.isEmpty ? null : '${q.area}.',
              'channel': q.channel.isEmpty ? null : q.channel,
              'status': q.status.isEmpty ? null : q.status,
              'from': dayBoundary(q.from),
              'to': dayBoundary(q.to, next: true),
              'recipient_id': q.recipient,
            },
          );
      return (
        rows: [
          if (r.payload is List)
            for (final m in r.payload! as List)
              if (m is Map && m['id'] is String)
                (
                  id: m['id'] as String,
                  when: m['created_at'] is String
                      ? DateTime.tryParse(m['created_at'] as String)
                      : null,
                  event: (m['event_type'] as String?) ?? '',
                  channel: (m['channel'] as String?) ?? '',
                  status: (m['status'] as String?) ?? '',
                  recipientId: m['recipient'] is Map
                      ? (m['recipient'] as Map)['id'] as String?
                      : null,
                  recipient: m['recipient'] is Map
                      ? (m['recipient'] as Map)['full_name'] as String?
                      : null,
                  toAddress: m['to_address'] as String?,
                  subject: m['subject'] as String?,
                  body: m['body'] as String?,
                  credits: (m['credits_used'] as num?)?.toInt() ?? 0,
                  error: m['error'] as String?,
                ),
        ],
        pages: r.meta?.totalPages ?? 1,
      );
    }, retry: (retryCount, error) => null);

/// The web's /message-log: every SMS and email sent from this workspace —
/// who it was for, when, whether it went out and the credits it used. By
/// type, channel, status, dates and one recipient; 20 at a time.
class MessageLogScreen extends ConsumerStatefulWidget {
  const MessageLogScreen({super.key});

  @override
  ConsumerState<MessageLogScreen> createState() => _MessageLogScreenState();
}

class _MessageLogScreenState extends ConsumerState<MessageLogScreen> {
  int _page = 1;
  String _area = '';
  String _channel = '';
  String _status = '';
  String? _from;
  String? _to;
  ({String id, String name})? _recipient;

  void _filter(VoidCallback change) => setState(() {
    change();
    _page = 1;
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final query = (
      page: _page,
      area: _area,
      channel: _channel,
      status: _status,
      from: _from,
      to: _to,
      recipient: _recipient?.id,
    );
    final log = ref.watch(messageLogProvider(query));
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final filtered =
        _area.isNotEmpty ||
        _channel.isNotEmpty ||
        _status.isNotEmpty ||
        _from != null ||
        _to != null ||
        _recipient != null;
    Widget choice(
      String key,
      String label,
      String value,
      String all,
      List<String> keys,
      String? Function(String) name,
      ValueChanged<String> onChanged,
    ) => SizedBox(
      width: 200,
      child: DropdownButtonFormField<String>(
        key: Key(key),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          DropdownMenuItem(value: '', child: Text(all)),
          for (final k in keys)
            DropdownMenuItem(value: k, child: Text(name(k) ?? k)),
        ],
        onChanged: (v) => _filter(() => onChanged(v ?? '')),
      ),
    );
    StatusTone tone(String s) => switch (s) {
      'SENT' || 'DELIVERED' => StatusTone.success,
      'FAILED' || 'NO_CREDIT' => StatusTone.danger,
      'PENDING' || 'SENDING' => StatusTone.info,
      _ => StatusTone.neutral,
    };
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.messageLogTitle, style: text.headlineSmall),
            Text(l10n.messageLogIntro, style: muted),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                choice(
                  'msg-area',
                  l10n.messageLogType,
                  _area,
                  l10n.messageLogAllTypes,
                  const ['exam', 'class', 'organization', 'sms', 'attendance'],
                  (k) => messageAreaName(l10n, k),
                  (v) => _area = v,
                ),
                choice(
                  'msg-channel',
                  l10n.messageLogChannel,
                  _channel,
                  l10n.messageLogAllChannels,
                  const ['SMS', 'EMAIL', 'IN_APP'],
                  (k) => messageChannelName(l10n, k),
                  (v) => _channel = v,
                ),
                choice(
                  'msg-status',
                  l10n.messageLogStatus,
                  _status,
                  l10n.messageLogAllStatuses,
                  const [
                    'PENDING',
                    'SENDING',
                    'SENT',
                    'DELIVERED',
                    'FAILED',
                    'NO_CREDIT',
                  ],
                  (k) => messageStatusName(l10n, k),
                  (v) => _status = v,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: DateField(
                    key: const Key('msg-from'),
                    label: l10n.messageLogFrom,
                    value: _from,
                    onChanged: (v) => _filter(() => _from = v),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: DateField(
                    key: const Key('msg-to'),
                    label: l10n.messageLogToDay,
                    value: _to,
                    min: _from,
                    onChanged: (v) => _filter(() => _to = v),
                  ),
                ),
              ],
            ),
            if (_recipient != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  key: const Key('msg-recipient'),
                  label: Text(l10n.messageLogRecipientFilter(_recipient!.name)),
                  onDeleted: () => _filter(() => _recipient = null),
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            ...log.when(
              loading: () => [const LinearProgressIndicator()],
              error: (e, _) => [
                SizedBox(
                  height: 240,
                  child: ErrorView(
                    title: e is ApiException
                        ? apiErrorText(l10n, e)
                        : l10n.uiErrorTitle,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(messageLogProvider(query)),
                  ),
                ),
              ],
              data: (p) => [
                if (p.rows.isEmpty)
                  Text(
                    filtered
                        ? l10n.messageLogEmptyFiltered
                        : l10n.messageLogEmpty,
                    style: muted,
                  ),
                for (final m in p.rows) ...[
                  AppCard(
                    key: Key('msg-${m.id}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              messageEventName(l10n, m.event) ?? m.event,
                              style: text.titleSmall,
                            ),
                            StatusPill(
                              label:
                                  messageStatusName(l10n, m.status) ?? m.status,
                              tone: tone(m.status),
                            ),
                          ],
                        ),
                        Text(
                          [
                            messageChannelName(l10n, m.channel) ?? m.channel,
                            if (m.when != null)
                              OrgTime.dateTime(m.when!, language),
                            '${l10n.messageLogCredits}: ${OrgTime.number(m.credits, language)}',
                          ].join(' · '),
                          style: muted,
                        ),
                        if (m.recipientId != null)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              key: Key('msg-to-${m.id}'),
                              onPressed: () => _filter(
                                () => _recipient = (
                                  id: m.recipientId!,
                                  name: m.recipient ?? l10n.messageLogUnknown,
                                ),
                              ),
                              child: Text(
                                '${l10n.messageLogTo}: ${m.recipient ?? l10n.messageLogUnknown}',
                              ),
                            ),
                          )
                        else
                          Text(
                            '${l10n.messageLogTo}: ${m.toAddress ?? l10n.messageLogUnknown}',
                            style: text.bodySmall,
                          ),
                        if ((m.body ?? '').isNotEmpty)
                          Text(
                            m.body!,
                            style: text.bodySmall,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if ((m.error ?? '').isNotEmpty)
                          Text(
                            m.error!,
                            style: text.bodySmall?.copyWith(
                              color: colors.danger,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _Pager(
                  page: _page,
                  pages: p.pages,
                  onPage: (v) => setState(() => _page = v),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
