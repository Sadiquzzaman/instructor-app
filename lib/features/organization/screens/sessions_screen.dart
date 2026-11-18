import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';

typedef AcademicSession = ({
  String id,
  String name,
  String? start,
  String? end,
  bool active,
  bool isDefault,
});

typedef Term = ({String id, String name, String? start, String? end});

String? _day(Object? v) =>
    v is String && v.length >= 10 ? v.substring(0, 10) : null;

final sessionsProvider = FutureProvider.autoDispose<List<AcademicSession>>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/sessions')).payload;
  return [
    if (p is List)
      for (final s in p)
        if (s is Map && s['id'] is String)
          (
            id: s['id'] as String,
            name: (s['name'] as String?) ?? '',
            start: _day(s['start_date']),
            end: _day(s['end_date']),
            active: s['status'] != 'CLOSED',
            isDefault: s['is_default'] == true,
          ),
  ];
}, retry: (retryCount, error) => null);

final termsProvider = FutureProvider.autoDispose.family<List<Term>, String>((
  ref,
  sessionId,
) async {
  final p =
      (await ref.read(apiClientProvider).get('/sessions/$sessionId/terms'))
          .payload;
  return [
    if (p is List)
      for (final t in p)
        if (t is Map && t['id'] is String)
          (
            id: t['id'] as String,
            name: (t['name'] as String?) ?? '',
            start: _day(t['start_date']),
            end: _day(t['end_date']),
          ),
  ];
}, retry: (retryCount, error) => null);

/// The web's rule (useAcademicsRequest): the owner of a personal workspace,
/// or an organisation's owners and admins, manage sessions; only owners
/// reopen a closed one.
({bool manage, bool reopen}) sessionRights(Session? s) {
  final personal = s != null && !s.isOrganization && s.role == 'TEACHER';
  final role = s?.memberRole;
  return (
    manage: personal || role == 'OWNER' || role == 'ADMIN',
    reopen: personal || role == 'OWNER',
  );
}

/// The web's /sessions: school years or coaching terms. Add and change
/// them, choose the default, close (asked first) and reopen; each
/// session's terms.
class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});

  Future<void> _act(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() call,
    String done,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(sessionsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    AcademicSession? s,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SessionDialog(session: s),
    );
    if (saved == true) ref.invalidate(sessionsProvider);
  }

  Future<void> _close(
    BuildContext context,
    WidgetRef ref,
    AcademicSession s,
  ) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.academicsSessionsCloseTitle(s.name)),
        content: Text(l10n.academicsSessionsCloseDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.academicsSessionsCancel),
          ),
          FilledButton(
            key: const Key('session-close-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.academicsSessionsCloseConfirm),
          ),
        ],
      ),
    );
    if (yes != true || !context.mounted) return;
    await _act(
      context,
      ref,
      () => ref.read(apiClientProvider).post('/sessions/${s.id}/close'),
      l10n.academicsSessionsClosed,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final rights = sessionRights(ref.watch(sessionProvider));
    if (!rights.manage) {
      return EmptyView(
        icon: Icons.lock_outline,
        title: l10n.academicsSessionsTitle,
        message: l10n.academicsSessionsNoAccess,
      );
    }
    final sessions = ref.watch(sessionsProvider);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    String day(String? v) => v == null ? '—' : OrgTime.schoolDay(v, language);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.academicsSessionsTitle, style: text.headlineSmall),
            Text(
              ref.levels(context, l10n.academicsSessionsIntro),
              style: muted,
            ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                key: const Key('session-add'),
                icon: const Icon(Icons.add),
                label: Text(l10n.academicsSessionsAdd),
                onPressed: () => _edit(context, ref, null),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ...sessions.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(
                    semanticsLabel: l10n.academicsSessionsTitle,
                  ),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 280,
                  child: ErrorView(
                    title: e is ApiException
                        ? apiErrorText(l10n, e)
                        : l10n.uiErrorTitle,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(sessionsProvider),
                  ),
                ),
              ],
              data: (list) => list.isEmpty
                  ? [
                      SizedBox(
                        height: 200,
                        child: EmptyView(
                          icon: Icons.event_note_outlined,
                          title: l10n.academicsSessionsEmpty,
                        ),
                      ),
                    ]
                  : [
                      for (final s in list) ...[
                        AppCard(
                          key: Key('session-${s.id}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.xs,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(s.name, style: text.titleSmall),
                                  if (s.isDefault)
                                    StatusPill(
                                      label: l10n.academicsSessionsDefault,
                                      tone: StatusTone.primary,
                                    ),
                                  StatusPill(
                                    label: s.active
                                        ? l10n.academicsSessionsStatusActive
                                        : l10n.academicsSessionsStatusClosed,
                                    tone: s.active
                                        ? StatusTone.success
                                        : StatusTone.neutral,
                                  ),
                                ],
                              ),
                              Text(
                                '${day(s.start)} – ${day(s.end)}',
                                style: muted,
                              ),
                              Wrap(
                                alignment: WrapAlignment.end,
                                spacing: AppSpacing.xs,
                                children: [
                                  TextButton(
                                    key: Key('terms-${s.id}'),
                                    onPressed: () => showModalBottomSheet<void>(
                                      context: context,
                                      isScrollControlled: true,
                                      builder: (_) => TermsSheet(session: s),
                                    ),
                                    child: Text(
                                      l10n.academicsSessionsTermsFor(s.name),
                                    ),
                                  ),
                                  if (s.active) ...[
                                    TextButton(
                                      key: Key('edit-${s.id}'),
                                      onPressed: () => _edit(context, ref, s),
                                      child: Text(
                                        l10n.academicsSessionsEditFor(s.name),
                                      ),
                                    ),
                                    if (!s.isDefault)
                                      TextButton(
                                        key: Key('default-${s.id}'),
                                        onPressed: () => _act(
                                          context,
                                          ref,
                                          () => ref
                                              .read(apiClientProvider)
                                              .post(
                                                '/sessions/${s.id}/default',
                                              ),
                                          l10n.academicsSessionsDefaultChanged,
                                        ),
                                        child: Text(
                                          l10n.academicsSessionsMakeDefaultFor(
                                            s.name,
                                          ),
                                        ),
                                      ),
                                    TextButton(
                                      key: Key('close-${s.id}'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: colors.danger,
                                      ),
                                      onPressed: () => _close(context, ref, s),
                                      child: Text(
                                        l10n.academicsSessionsCloseFor(s.name),
                                      ),
                                    ),
                                  ] else if (rights.reopen)
                                    OutlinedButton(
                                      key: Key('reopen-${s.id}'),
                                      onPressed: () => _act(
                                        context,
                                        ref,
                                        () => ref
                                            .read(apiClientProvider)
                                            .post('/sessions/${s.id}/reopen'),
                                        l10n.academicsSessionsReopened,
                                      ),
                                      child: Text(
                                        l10n.academicsSessionsReopenFor(s.name),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Add or change a session: a name and its dates; a new one can become the
/// default at once. Pops true when saved.
class _SessionDialog extends ConsumerStatefulWidget {
  const _SessionDialog({this.session});

  final AcademicSession? session;

  @override
  ConsumerState<_SessionDialog> createState() => _SessionDialogState();
}

class _SessionDialogState extends ConsumerState<_SessionDialog> {
  late final _name = TextEditingController(text: widget.session?.name ?? '');
  late String? _start = widget.session?.start;
  late String? _end = widget.session?.end;
  bool _makeDefault = false;
  bool _saving = false;
  String? _problem;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _datesInvalid =>
      _start != null && _end != null && _end!.compareTo(_start!) < 0;

  bool get _canSave =>
      _name.text.trim().isNotEmpty &&
      _start != null &&
      _end != null &&
      !_datesInvalid;

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final s = widget.session;
    final body = {
      'name': _name.text.trim(),
      'start_date': _start,
      'end_date': _end,
    };
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      if (s == null) {
        await api.post(
          '/sessions',
          data: {...body, 'is_default': _makeDefault},
        );
      } else {
        await api.patch('/sessions/${s.id}', data: body);
      }
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.academicsSessionsSaved)),
      );
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _problem = apiErrorText(l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = widget.session != null;
    return AlertDialog(
      title: Text(
        editing ? l10n.academicsSessionsEdit : l10n.academicsSessionsAdd,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const Key('session-name'),
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: l10n.academicsSessionsName,
                hintText: l10n.academicsSessionsNamePlaceholder,
              ),
              onChanged: (_) => setState(() {}),
            ),
            DateField(
              key: const Key('session-start'),
              label: l10n.academicsSessionsStart,
              value: _start,
              onChanged: (v) => setState(() => _start = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            DateField(
              key: const Key('session-end'),
              label: l10n.academicsSessionsEnd,
              value: _end,
              min: _start,
              error: _datesInvalid ? l10n.academicsSessionsDatesInvalid : null,
              onChanged: (v) => setState(() => _end = v),
            ),
            if (!editing)
              CheckboxListTile(
                key: const Key('session-default'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _makeDefault,
                title: Text(l10n.academicsSessionsMakeDefaultOnCreate),
                onChanged: (v) => setState(() => _makeDefault = v ?? false),
              ),
            if (_problem != null)
              Text(
                _problem!,
                style: TextStyle(color: AppColors.of(context).danger),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.academicsSessionsCancel),
        ),
        FilledButton(
          key: const Key('session-save'),
          onPressed: _saving || !_canSave ? null : _save,
          child: Text(l10n.academicsSessionsSave),
        ),
      ],
    );
  }
}

/// A session's terms (half-yearly, annual, …): add, change, delete (asked
/// first). Read-only when the session is closed.
class TermsSheet extends ConsumerStatefulWidget {
  const TermsSheet({required this.session, super.key});

  final AcademicSession session;

  @override
  ConsumerState<TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends ConsumerState<TermsSheet> {
  final _name = TextEditingController();
  String? _editing;
  String? _start;
  String? _end;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _reset() {
    _editing = null;
    _name.clear();
    _start = null;
    _end = null;
  }

  bool get _datesInvalid =>
      _start != null && _end != null && _end!.compareTo(_start!) < 0;

  Future<void> _run(Future<void> Function() call, String done) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(termsProvider(widget.session.id));
      if (mounted) setState(_reset);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save(int count) {
    final l10n = context.l10n;
    final api = ref.read(apiClientProvider);
    final name = _name.text.trim();
    final id = _editing;
    return _run(
      () => id != null
          ? api.patch(
              '/terms/$id',
              data: {'name': name, 'start_date': _start, 'end_date': _end},
            )
          : api.post(
              '/sessions/${widget.session.id}/terms',
              data: {
                'name': name,
                'start_date': ?_start,
                'end_date': ?_end,
                'sort_order': count,
              },
            ),
      l10n.academicsTermsSaved,
    );
  }

  Future<void> _delete(Term t) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.academicsTermsDeleteTitle(t.name)),
        content: Text(l10n.academicsTermsDeleteDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.academicsSessionsCancel),
          ),
          FilledButton(
            key: const Key('term-delete-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.academicsTermsDeleteConfirm),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(
      () => ref.read(apiClientProvider).delete('/terms/${t.id}'),
      l10n.academicsTermsDeleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final terms = ref.watch(termsProvider(widget.session.id));
    final open = widget.session.active;
    String day(String? v) => v == null ? '—' : OrgTime.schoolDay(v, language);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          top: AppSpacing.lg,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(widget.session.name, style: text.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              ...terms.when(
                loading: () => [const LinearProgressIndicator()],
                error: (e, _) => [
                  Text(e is ApiException ? apiErrorText(l10n, e) : '$e'),
                ],
                data: (list) => [
                  if (list.isEmpty)
                    Text(l10n.academicsTermsEmpty, style: muted),
                  for (final t in list)
                    ListTile(
                      key: Key('term-${t.id}'),
                      contentPadding: EdgeInsets.zero,
                      title: Text(t.name),
                      subtitle: Text('${day(t.start)} – ${day(t.end)}'),
                      trailing: open
                          ? Wrap(
                              children: [
                                IconButton(
                                  key: Key('term-edit-${t.id}'),
                                  tooltip: l10n.academicsTermsEditFor(t.name),
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => setState(() {
                                    _editing = t.id;
                                    _name.text = t.name;
                                    _start = t.start;
                                    _end = t.end;
                                  }),
                                ),
                                IconButton(
                                  key: Key('term-delete-${t.id}'),
                                  tooltip: l10n.academicsTermsDeleteFor(t.name),
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _delete(t),
                                ),
                              ],
                            )
                          : null,
                    ),
                  const Divider(),
                  if (!open)
                    Text(l10n.academicsTermsClosedNote, style: muted)
                  else ...[
                    TextField(
                      key: const Key('term-name'),
                      controller: _name,
                      maxLength: 80,
                      decoration: InputDecoration(
                        labelText: l10n.academicsTermsName,
                        hintText: l10n.academicsTermsNamePlaceholder,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    DateField(
                      label: l10n.academicsTermsStart,
                      value: _start,
                      onChanged: (v) => setState(() => _start = v),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DateField(
                      label: l10n.academicsTermsEnd,
                      value: _end,
                      min: _start,
                      error: _datesInvalid
                          ? l10n.academicsSessionsDatesInvalid
                          : null,
                      onChanged: (v) => setState(() => _end = v),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        FilledButton(
                          key: const Key('term-save'),
                          onPressed:
                              _saving ||
                                  _name.text.trim().isEmpty ||
                                  _datesInvalid
                              ? null
                              : () => _save(list.length),
                          child: Text(
                            _editing != null
                                ? l10n.academicsTermsSave
                                : l10n.academicsTermsAdd,
                          ),
                        ),
                        if (_editing != null)
                          TextButton(
                            onPressed: () => setState(_reset),
                            child: Text(l10n.academicsTermsCancelEdit),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
