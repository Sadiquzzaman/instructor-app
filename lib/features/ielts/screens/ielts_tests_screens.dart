import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/data/ielts_tests.dart';
import 'package:instructor_app/features/ielts/data/profiles.dart';

String ieltsTestStatusName(AppLocalizations l10n, String s) => switch (s) {
  'PUBLISHED' => l10n.ieltsTestsStatusesPUBLISHED,
  'ARCHIVED' => l10n.ieltsTestsStatusesARCHIVED,
  _ => l10n.ieltsTestsStatusesDRAFT,
};

StatusTone ieltsTestStatusTone(String s) => switch (s) {
  'PUBLISHED' => StatusTone.success,
  'ARCHIVED' => StatusTone.warning,
  _ => StatusTone.neutral,
};

String ieltsTestTypeName(AppLocalizations l10n, String t) =>
    t == 'GENERAL' ? l10n.ieltsTestsTypesGENERAL : l10n.ieltsTestsTypesACADEMIC;

String ieltsPartName(AppLocalizations l10n, String module, int no) =>
    switch (module) {
      'LISTENING' => l10n.ieltsTestsPartNamesLISTENING(no),
      'READING' => l10n.ieltsTestsPartNamesREADING(no),
      'WRITING' => l10n.ieltsTestsPartNamesWRITING(no),
      _ => l10n.ieltsTestsPartNamesSPEAKING(no),
    };

/// A test's page until the builder lands (Stage 5 PR 5): "use the website
/// for IELTS for now".
class IeltsTestPlaceholder extends StatelessWidget {
  const IeltsTestPlaceholder({super.key});

  @override
  Widget build(BuildContext context) => EmptyView(
    icon: Icons.translate,
    title: context.l10n.ieltsTestsPageTitle,
    message: context.l10n.appNotYetIelts,
  );
}

/// Where a test opens: the builder (PR 5 of Stage 5).
String ieltsTestRoute(String id) => '/ielts/tests/$id';

/// Academic exams made for IELTS before the IELTS builder (P10-08).
final _oldExamsProvider =
    FutureProvider.autoDispose<
      List<({String id, String title, DateTime? created, String? copyId})>
    >((ref) async {
      ref.watch(workspaceKeyProvider);
      final p = (await ref.read(apiClientProvider).get('/ielts/old-exams'))
          .payload;
      return [
        if (p is List)
          for (final e in p)
            if (e is Map)
              (
                id: '${e['id']}',
                title: '${e['title'] ?? ''}',
                created: DateTime.tryParse('${e['created_at']}'),
                copyId: e['converted_test_id'] as String?,
              ),
      ];
    }, retry: (retryCount, error) => null);

/// The web's /ielts/tests (P10-03): mocks and practice sets with their
/// status and questions per module, filtered by purpose and status; a new
/// test starts from the real template; copy, archive or delete (asked
/// first). Old academic IELTS exams can be copied into the new format.
class IeltsTestsScreen extends ConsumerStatefulWidget {
  const IeltsTestsScreen({super.key});

  @override
  ConsumerState<IeltsTestsScreen> createState() => _IeltsTestsScreenState();
}

class _IeltsTestsScreenState extends ConsumerState<IeltsTestsScreen> {
  String? _purpose;
  String? _status;
  bool _busy = false;

  ({String? purpose, String? status}) get _filter =>
      (purpose: _purpose, status: _status);

  Future<void> _act(Future<void> Function() action, String done) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(ieltsTestsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy(IeltsTestSummary t) async {
    final router = GoRouter.of(context);
    await _act(() async {
      final r = await ref
          .read(apiClientProvider)
          .post('/ielts/tests/${t.id}/duplicate');
      final id = r.payload is Map ? (r.payload! as Map)['id'] : null;
      if (id != null) unawaited(router.push(ieltsTestRoute('$id')));
    }, context.l10n.ieltsTestsCopied);
  }

  Future<void> _delete(IeltsTestSummary t) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.ieltsTestsDeleteTitle),
        content: Text(l10n.ieltsTestsDeleteDescription(t.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.ieltsTestsCancel),
          ),
          FilledButton(
            key: const Key('ielts-test-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(d).danger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.ieltsTestsDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _act(
      () => ref.read(apiClientProvider).delete('/ielts/tests/${t.id}'),
      l10n.ieltsTestsDeleted,
    );
  }

  Future<void> _new() async {
    final id = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => const _NewTestForm(),
    );
    if (id != null && mounted) {
      ref.invalidate(ieltsTestsProvider);
      unawaited(context.push(ieltsTestRoute(id)));
    }
  }

  String _questions(AppLocalizations l10n, IeltsTestSummary t, String lang) {
    final s = [
      for (final m in t.modules)
        if (m == 'LISTENING' || m == 'READING')
          '${ieltsModuleShort(l10n, m)} '
              '${OrgTime.number(t.questionCounts[m] ?? 0, lang)}'
              '${t.purpose == 'MOCK' ? '/${OrgTime.number(40, lang)}' : ''}',
    ].join(' · ');
    return s.isEmpty ? '—' : s;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final rows = ref.watch(ieltsTestsProvider(_filter));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(ieltsTestsProvider(_filter).future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.ieltsTestsPageTitle, style: text.headlineSmall),
              Text(l10n.ieltsTestsPageDescription, style: muted),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const Key('ielts-test-new'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.ieltsTestsNewTest),
                  onPressed: _new,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('ielts-test-purpose'),
                      initialValue: _purpose,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.ieltsTestsPurpose,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.ieltsTestsAllPurposes),
                        ),
                        for (final p in ['MOCK', 'PRACTICE'])
                          DropdownMenuItem(
                            value: p,
                            child: Text(ieltsPurpose(l10n, p)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _purpose = v),
                    ),
                  ),
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String?>(
                      key: const Key('ielts-test-status'),
                      initialValue: _status,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.ieltsTestsStatus,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: null,
                          child: Text(l10n.ieltsTestsAllStatuses),
                        ),
                        for (final s in ['DRAFT', 'PUBLISHED', 'ARCHIVED'])
                          DropdownMenuItem(
                            value: s,
                            child: Text(ieltsTestStatusName(l10n, s)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _status = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ...rows.when(
                loading: () => [
                  SizedBox(
                    height: 160,
                    child: LoadingView(semanticsLabel: l10n.ieltsTestsCaption),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 260,
                    child: ErrorView(
                      title: e is ApiException && e.statusCode == 403
                          ? l10n.ieltsTestsNotAvailable
                          : l10n.ieltsTestsLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () =>
                          ref.invalidate(ieltsTestsProvider(_filter)),
                    ),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [
                        EmptyView(
                          icon: Icons.quiz_outlined,
                          title: l10n.ieltsTestsEmpty,
                          message: l10n.ieltsTestsEmptyHint,
                        ),
                      ]
                    : [
                        for (final t in list)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AppCard(
                              key: Key('ielts-test-${t.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  InkWell(
                                    key: Key('ielts-test-open-${t.id}'),
                                    onTap: () =>
                                        context.push(ieltsTestRoute(t.id)),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            t.title,
                                            style: text.titleMedium?.copyWith(
                                              color: colors.primary,
                                            ),
                                          ),
                                        ),
                                        StatusPill(
                                          label: ieltsTestStatusName(
                                            l10n,
                                            t.status,
                                          ),
                                          tone: ieltsTestStatusTone(t.status),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (t.needsReview)
                                    Text(
                                      l10n.ieltsTestsNeedsReview,
                                      style: text.bodySmall?.copyWith(
                                        color: colors.warning,
                                      ),
                                    ),
                                  Text(
                                    '${ieltsPurpose(l10n, t.purpose)} · '
                                    '${ieltsTestTypeName(l10n, t.testType)} · '
                                    '${t.modules.map((m) => ieltsModuleShort(l10n, m)).join(', ')}',
                                    style: muted,
                                  ),
                                  Text(
                                    '${l10n.ieltsTestsQuestions}: '
                                    '${_questions(l10n, t, lang)}',
                                    style: text.bodySmall,
                                  ),
                                  if (t.updatedAt != null)
                                    Text(
                                      '${l10n.ieltsTestsUpdated}: '
                                      '${OrgTime.date(t.updatedAt!, lang)}',
                                      style: muted,
                                    ),
                                  Wrap(
                                    spacing: AppSpacing.xs,
                                    children: [
                                      TextButton(
                                        key: Key('ielts-test-copy-${t.id}'),
                                        onPressed: _busy
                                            ? null
                                            : () => _copy(t),
                                        child: Text(
                                          l10n.ieltsTestsCopy,
                                          semanticsLabel: l10n
                                              .ieltsTestsCopyFor(t.title),
                                        ),
                                      ),
                                      if (t.status != 'ARCHIVED')
                                        TextButton(
                                          key: Key(
                                            'ielts-test-archive-${t.id}',
                                          ),
                                          onPressed: _busy
                                              ? null
                                              : () => _act(
                                                  () => ref
                                                      .read(apiClientProvider)
                                                      .post(
                                                        '/ielts/tests/${t.id}/archive',
                                                      ),
                                                  l10n.ieltsTestsArchived,
                                                ),
                                          child: Text(l10n.ieltsTestsArchive),
                                        ),
                                      TextButton(
                                        key: Key('ielts-test-delete-${t.id}'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: colors.danger,
                                        ),
                                        onPressed: _busy
                                            ? null
                                            : () => _delete(t),
                                        child: Text(l10n.ieltsTestsDelete),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
              ),
              const _OldExams(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A new draft from the real template (the web's CreateTestModal).
class _NewTestForm extends ConsumerStatefulWidget {
  const _NewTestForm();

  @override
  ConsumerState<_NewTestForm> createState() => _NewTestFormState();
}

class _NewTestFormState extends ConsumerState<_NewTestForm> {
  final _title = TextEditingController();
  String _type = 'ACADEMIC';
  String _purpose = 'MOCK';
  final _modules = <String>{...ieltsModules};
  String _module = 'READING';
  final _parts = <int>{1};
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool get _ready =>
      _title.text.trim().isNotEmpty &&
      (_purpose == 'MOCK' ? _modules.isNotEmpty : _parts.isNotEmpty);

  Future<void> _create() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post(
            '/ielts/tests',
            data: newTestBody(
              title: _title.text,
              testType: _type,
              purpose: _purpose,
              modules: _modules.toList(),
              module: _module,
              parts: _parts.toList(),
            ),
          );
      final id = r.payload is Map ? (r.payload! as Map)['id'] : null;
      nav.pop(id == null ? null : '$id');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.ieltsTestsNewTest, style: text.titleLarge),
              Text(l10n.ieltsTestsNewTestDescription, style: muted),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('ielts-new-title'),
                controller: _title,
                maxLength: 200,
                decoration: InputDecoration(labelText: l10n.ieltsTestsTitle),
                onChanged: (_) => setState(() {}),
              ),
              Text(l10n.ieltsTestsTestType, style: text.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<String>(
                key: const Key('ielts-new-type'),
                segments: [
                  for (final t in ['ACADEMIC', 'GENERAL'])
                    ButtonSegment(
                      value: t,
                      label: Text(ieltsTestTypeName(l10n, t)),
                    ),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(l10n.ieltsTestsPurpose, style: text.titleSmall),
              for (final p in ['MOCK', 'PRACTICE'])
                RadioListTile<String>(
                  key: Key('ielts-new-purpose-$p'),
                  contentPadding: EdgeInsets.zero,
                  value: p,
                  // ignore: deprecated_member_use
                  groupValue: _purpose,
                  // ignore: deprecated_member_use
                  onChanged: (v) => setState(() => _purpose = v!),
                  title: Text(ieltsPurpose(l10n, p)),
                  subtitle: Text(
                    p == 'MOCK'
                        ? l10n.ieltsTestsPurposeHintsMOCK
                        : l10n.ieltsTestsPurposeHintsPRACTICE,
                  ),
                ),
              if (_purpose == 'MOCK') ...[
                Text(l10n.ieltsTestsModules, style: text.titleSmall),
                for (final m in ieltsModules)
                  CheckboxListTile(
                    key: Key('ielts-new-module-$m'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(ieltsModuleShort(l10n, m)),
                    value: _modules.contains(m),
                    onChanged: (v) => setState(
                      () => v == true ? _modules.add(m) : _modules.remove(m),
                    ),
                  ),
              ] else ...[
                DropdownButtonFormField<String>(
                  key: const Key('ielts-new-module'),
                  initialValue: _module,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.ieltsTestsModule),
                  items: [
                    for (final m in ieltsModules)
                      DropdownMenuItem(
                        value: m,
                        child: Text(ieltsModuleShort(l10n, m)),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _module = v!;
                    _parts
                      ..clear()
                      ..add(1);
                  }),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(l10n.ieltsTestsParts, style: text.titleSmall),
                for (var no = 1; no <= ieltsPartCount[_module]!; no++)
                  CheckboxListTile(
                    key: Key('ielts-new-part-$no'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(ieltsPartName(l10n, _module, no)),
                    value: _parts.contains(no),
                    onChanged: (v) => setState(
                      () => v == true ? _parts.add(no) : _parts.remove(no),
                    ),
                  ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.ieltsTestsCancel),
                  ),
                  FilledButton(
                    key: const Key('ielts-new-create'),
                    onPressed: _ready && !_busy ? _create : null,
                    child: Text(l10n.ieltsTestsCreate),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Academic exams made for IELTS (P10-08): copy each into the new format
/// once; hidden when there are none.
class _OldExams extends ConsumerStatefulWidget {
  const _OldExams();

  @override
  ConsumerState<_OldExams> createState() => _OldExamsState();
}

class _OldExamsState extends ConsumerState<_OldExams> {
  String? _busy;

  Future<void> _convert(String id) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = id);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/ielts/old-exams/$id/convert');
      ref.invalidate(_oldExamsProvider);
      final p = r.payload is Map
          ? r.payload! as Map
          : const <String, Object?>{};
      final skipped = [
        for (final s in (p['skipped'] as List?) ?? const [])
          if (s is Map) '${s['reason'] ?? ''}',
      ];
      if (!mounted) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(l10n.ieltsConvertDoneTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.ieltsConvertDoneDescription((p['converted'] as num?) ?? 0),
              ),
              const SizedBox(height: AppSpacing.sm),
              if (skipped.isEmpty)
                Text(l10n.ieltsConvertNothingSkipped)
              else ...[
                Text(l10n.ieltsConvertSkipped(skipped.length)),
                for (final s in skipped) Text('• $s'),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(l10n.ieltsConvertClose),
            ),
            FilledButton(
              key: const Key('ielts-convert-open'),
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(l10n.ieltsConvertOpenCopy),
            ),
          ],
        ),
      );
      if (open == true && mounted && p['test_id'] != null) {
        unawaited(context.push(ieltsTestRoute('${p['test_id']}')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final exams = ref.watch(_oldExamsProvider).value ?? const [];
    if (exams.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        key: const Key('ielts-old-exams'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.ieltsConvertTitle, style: text.titleSmall),
            Text(l10n.ieltsConvertDescription, style: text.bodySmall),
            for (final e in exams)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.title, style: text.bodyMedium),
                        if (e.created != null)
                          Text(
                            OrgTime.date(e.created!, lang),
                            style: text.bodySmall,
                          ),
                      ],
                    ),
                    if (e.copyId != null)
                      TextButton(
                        onPressed: () =>
                            context.push(ieltsTestRoute(e.copyId!)),
                        child: Text(l10n.ieltsConvertOpenCopy),
                      )
                    else
                      OutlinedButton(
                        key: Key('ielts-convert-${e.id}'),
                        onPressed: _busy == null ? () => _convert(e.id) : null,
                        child: Text(
                          l10n.ieltsConvertConvert,
                          semanticsLabel: l10n.ieltsConvertConvertFor(e.title),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The web's /ielts/band-tables (P10-03): the three tables (Listening,
/// Academic Reading, General Training Reading) from raw scores out of 40
/// to bands. Owners and admins change the centre's copy or put it back to
/// the default; other staff read.
class IeltsBandTablesScreen extends ConsumerWidget {
  const IeltsBandTablesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final canEdit = const {
      'OWNER',
      'ADMIN',
    }.contains(ref.watch(sessionProvider)?.memberRole);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ref
            .watch(ieltsBandTablesProvider)
            .when(
              loading: () =>
                  LoadingView(semanticsLabel: l10n.ieltsBandsPageTitle),
              error: (e, _) => ErrorView(
                title: e is ApiException && e.statusCode == 403
                    ? l10n.ieltsBandsNotAvailable
                    : l10n.ieltsBandsLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(ieltsBandTablesProvider),
              ),
              data: (tables) => RefreshIndicator(
                onRefresh: () => ref.refresh(ieltsBandTablesProvider.future),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(l10n.ieltsBandsPageTitle, style: text.headlineSmall),
                    Text(l10n.ieltsBandsPageDescription, style: muted),
                    if (!canEdit) Text(l10n.ieltsBandsReadOnly, style: muted),
                    const SizedBox(height: AppSpacing.md),
                    for (final t in tables)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: _BandTableCard(
                          key: ValueKey(
                            '${t.module}-${t.testType}-${t.customised}-'
                            '${t.rows.length}',
                          ),
                          table: t,
                          canEdit: canEdit,
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

String _tableName(AppLocalizations l10n, IeltsBandTable t) =>
    t.module == 'LISTENING'
    ? l10n.ieltsBandsTablesLISTENING
    : t.testType == 'GENERAL'
    ? l10n.ieltsBandsTablesREADINGGENERAL
    : l10n.ieltsBandsTablesREADINGACADEMIC;

class _BandTableCard extends ConsumerStatefulWidget {
  const _BandTableCard({required this.table, required this.canEdit, super.key});

  final IeltsBandTable table;
  final bool canEdit;

  @override
  ConsumerState<_BandTableCard> createState() => _BandTableCardState();
}

class _BandTableCardState extends ConsumerState<_BandTableCard> {
  late final _raws = [
    for (final r in widget.table.rows)
      TextEditingController(text: '${r.minRaw}'),
  ];
  late final _bands = [for (final r in widget.table.rows) r.band];
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _raws) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, Object?> get _scope => {
    'module': widget.table.module,
    'test_type': ?widget.table.testType,
  };

  List<({int minRaw, num band})> get _rows => [
    for (var i = 0; i < _raws.length; i++)
      (minRaw: int.tryParse(_raws[i].text.trim()) ?? -1, band: _bands[i]),
  ];

  Future<void> _send(Future<void> Function() request, String done) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await request();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(ieltsBandTablesProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final t = widget.table;
    final valid = bandRowsValid(_rows);
    final key = '${t.module}-${t.testType ?? ''}';
    return AppCard(
      key: Key('band-table-$key'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_tableName(l10n, t), style: text.titleSmall),
              ),
              StatusPill(
                label: t.customised
                    ? l10n.ieltsBandsCustomised
                    : l10n.ieltsBandsDefault,
                tone: t.customised ? StatusTone.info : StatusTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.ieltsBandsMinRaw,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              ),
              Expanded(
                child: Text(
                  l10n.ieltsBandsBand,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              ),
              if (widget.canEdit) const SizedBox(width: AppSpacing.xxxl),
            ],
          ),
          for (var i = 0; i < _raws.length; i++)
            if (widget.canEdit)
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('band-raw-$key-$i'),
                      controller: _raws[i],
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButton<num>(
                      key: Key('band-band-$key-$i'),
                      value: ieltsBands.contains(_bands[i]) ? _bands[i] : null,
                      isExpanded: true,
                      items: [
                        for (final b in ieltsBands)
                          DropdownMenuItem(
                            value: b,
                            child: Text(bandText(b, lang)),
                          ),
                      ],
                      onChanged: (v) => setState(() => _bands[i] = v ?? 0),
                    ),
                  ),
                  IconButton(
                    key: Key('band-remove-$key-$i'),
                    tooltip: l10n.ieltsBandsRemoveRow(i + 1),
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _raws.removeAt(i).dispose();
                      _bands.removeAt(i);
                    }),
                  ),
                ],
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        OrgTime.number(t.rows[i].minRaw, lang),
                        style: text.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        bandText(t.rows[i].band, lang),
                        style: text.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          if (widget.canEdit) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              l10n.ieltsBandsRule,
              key: Key('band-rule-$key'),
              style: text.bodySmall?.copyWith(
                color: valid ? colors.inkMuted : colors.danger,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                OutlinedButton(
                  key: Key('band-add-$key'),
                  onPressed: () => setState(() {
                    _raws.add(TextEditingController(text: '0'));
                    _bands.add(0);
                  }),
                  child: Text(l10n.ieltsBandsAddRow),
                ),
                FilledButton(
                  key: Key('band-save-$key'),
                  onPressed: _busy || !valid
                      ? null
                      : () => _send(
                          () => ref
                              .read(apiClientProvider)
                              .put(
                                '/ielts/band-tables',
                                data: {
                                  ..._scope,
                                  'rows': [
                                    for (final r in _rows)
                                      {'min_raw': r.minRaw, 'band': r.band},
                                  ],
                                },
                              ),
                          l10n.ieltsBandsSaved,
                        ),
                  child: Text(l10n.ieltsBandsSave),
                ),
                if (t.customised)
                  TextButton(
                    key: Key('band-reset-$key'),
                    onPressed: _busy
                        ? null
                        : () => _send(
                            () => ref
                                .read(apiClientProvider)
                                .post('/ielts/band-tables/reset', data: _scope),
                            l10n.ieltsBandsResetDone,
                          ),
                    child: Text(l10n.ieltsBandsReset),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
