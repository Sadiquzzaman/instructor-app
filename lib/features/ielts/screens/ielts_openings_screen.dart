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
import 'package:instructor_app/core/widgets/date_time_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/ielts/data/builder.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';

/// An opening (`GET /ielts/tests/:id/assignments`): a batch and its window.
typedef IeltsOpening = ({
  String id,
  String sectionId,
  String batch,
  DateTime? opens,
  DateTime? closes,
  int students,
  Map<String, int> submitted,
});

List<IeltsOpening> openingsFromJson(Object? p) => [
  if (p is List)
    for (final a in p)
      if (a is Map)
        (
          id: '${a['id']}',
          sectionId: '${(a['section'] as Map?)?['id'] ?? ''}',
          batch: '${(a['section'] as Map?)?['name'] ?? ''}',
          opens: DateTime.tryParse('${a['opens_at']}'),
          closes: DateTime.tryParse('${a['closes_at']}'),
          students: (a['students'] as num?)?.toInt() ?? 0,
          submitted: {
            if (a['submitted'] is Map)
              for (final e in (a['submitted'] as Map).entries)
                if (e.value is num) '${e.key}': (e.value as num).toInt(),
          },
        ),
];

/// A student's result per module (`GET /ielts/assignments/:id/results`).
typedef IeltsModuleResult = ({
  String attemptId,
  String status,
  String? mode,
  num? band,
  num? raw,
  num? rawTotal,
});

typedef IeltsResultRow = ({
  String studentId,
  String name,
  Map<String, IeltsModuleResult> modules,
  num? overall,
});

List<IeltsResultRow> resultsFromJson(Object? p) => [
  if (p is List)
    for (final r in p)
      if (r is Map)
        (
          studentId: '${(r['student'] as Map?)?['id'] ?? ''}',
          name: '${(r['student'] as Map?)?['full_name'] ?? ''}',
          modules: {
            if (r['modules'] is Map)
              for (final e in (r['modules'] as Map).entries)
                if (e.value is Map)
                  '${e.key}': (
                    attemptId: '${(e.value as Map)['attempt_id']}',
                    status: '${(e.value as Map)['status'] ?? ''}',
                    mode: (e.value as Map)['mode'] as String?,
                    band: (e.value as Map)['band'] as num?,
                    raw: (e.value as Map)['raw_score'] as num?,
                    rawTotal: (e.value as Map)['raw_total'] as num?,
                  ),
          },
          overall: r['overall'] as num?,
        ),
];

final ieltsOpeningsProvider = FutureProvider.autoDispose
    .family<List<IeltsOpening>, String>((ref, testId) async {
      ref.watch(workspaceKeyProvider);
      return openingsFromJson(
        (await ref
                .read(apiClientProvider)
                .get('/ielts/tests/$testId/assignments'))
            .payload,
      );
    }, retry: (retryCount, error) => null);

final ieltsResultsProvider = FutureProvider.autoDispose
    .family<List<IeltsResultRow>, String>((ref, assignmentId) async {
      ref.watch(workspaceKeyProvider);
      return resultsFromJson(
        (await ref
                .read(apiClientProvider)
                .get('/ielts/assignments/$assignmentId/results'))
            .payload,
      );
    }, retry: (retryCount, error) => null);

final _batchesProvider =
    FutureProvider.autoDispose<List<({String id, String label})>>((ref) async {
      ref.watch(workspaceKeyProvider);
      final api = ref.read(apiClientProvider);
      final r = await Future.wait([api.get('/sections'), api.get('/classes')]);
      final names = {
        if (r[1].payload is List)
          for (final c in r[1].payload! as List)
            if (c is Map) '${c['id']}': '${c['class_name'] ?? ''}',
      };
      return [
        if (r[0].payload is List)
          for (final s in r[0].payload! as List)
            if (s is Map)
              (
                id: '${s['id']}',
                label: '${names[s['class_id']] ?? ''} ${s['name'] ?? ''}'
                    .trim(),
              ),
      ];
    }, retry: (retryCount, error) => null);

/// The web's /ielts/tests/[id]/openings (P10-04): each batch the test is
/// open for, with its window (in the centre's time) and hand-ins per
/// module; open it for another batch, change the window, remove (asked
/// first); each student's band and score per module, and the overall band.
class IeltsOpeningsScreen extends ConsumerWidget {
  const IeltsOpeningsScreen({required this.testId, super.key});

  final String testId;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    IeltsOpening? opening,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _OpeningForm(testId: testId, opening: opening),
    );
    if (saved == true) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.ieltsOpeningsSaved)));
      ref.invalidate(ieltsOpeningsProvider(testId));
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    IeltsOpening o,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.ieltsOpeningsRemoveTitle),
        content: Text(l10n.ieltsOpeningsRemoveDescription(o.batch)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.ieltsOpeningsCancel),
          ),
          FilledButton(
            key: const Key('opening-remove-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(d).danger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.ieltsOpeningsRemove),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiClientProvider).delete('/ielts/assignments/${o.id}');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.ieltsOpeningsRemoved)),
      );
      ref.invalidate(ieltsOpeningsProvider(testId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  void _results(BuildContext context, IeltsOpening o, List<String> modules) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        builder: (_) => _Results(opening: o, modules: modules),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final test = ref.watch(ieltsTestProvider(testId));
    final t = test.value;
    final rows = ref.watch(ieltsOpeningsProvider(testId));
    if (test.hasError) {
      final e = test.error;
      return ErrorView(
        title: e is ApiException && e.statusCode == 403
            ? l10n.ieltsTestsNotAvailable
            : l10n.ieltsOpeningsLoadFailed,
        retryLabel: l10n.uiErrorRetry,
        onRetry: () => ref.invalidate(ieltsTestProvider(testId)),
      );
    }
    final modules = t?.modules ?? const <String>[];
    final published = t?.status == 'PUBLISHED';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(ieltsOpeningsProvider(testId).future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                t == null
                    ? l10n.ieltsOpeningsTitleLoading
                    : l10n.ieltsOpeningsTitle(t.title),
                style: text.headlineSmall,
              ),
              Text(l10n.ieltsOpeningsDescription, style: muted),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.icon(
                  key: const Key('opening-new'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.ieltsOpeningsOpen),
                  onPressed: published ? () => _edit(context, ref, null) : null,
                ),
              ),
              if (t != null && !published)
                Text(l10n.ieltsOpeningsPublishFirst, style: muted),
              const SizedBox(height: AppSpacing.md),
              ...rows.when(
                loading: () => [
                  SizedBox(
                    height: 160,
                    child: LoadingView(
                      semanticsLabel: l10n.ieltsOpeningsCaption,
                    ),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 260,
                    child: ErrorView(
                      title: l10n.ieltsOpeningsLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () =>
                          ref.invalidate(ieltsOpeningsProvider(testId)),
                    ),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [
                        EmptyView(
                          icon: Icons.event_available_outlined,
                          title: l10n.ieltsOpeningsNone,
                          message: l10n.ieltsOpeningsNoneHint,
                        ),
                      ]
                    : [
                        for (final o in list)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AppCard(
                              key: Key('opening-${o.id}'),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(o.batch, style: text.titleSmall),
                                  Text(
                                    '${o.opens == null ? '—' : OrgTime.dateTime(o.opens!, lang)} – '
                                    '${o.closes == null ? '—' : OrgTime.dateTime(o.closes!, lang)}',
                                    style: muted,
                                  ),
                                  Text(
                                    '${l10n.ieltsOpeningsHandedIn}: '
                                    '${[for (final m in modules) '${ieltsModuleShort(l10n, m)} ${OrgTime.number(o.submitted[m] ?? 0, lang)}/${OrgTime.number(o.students, lang)}'].join(' · ')}',
                                    style: text.bodySmall,
                                  ),
                                  Wrap(
                                    spacing: AppSpacing.xs,
                                    children: [
                                      OutlinedButton(
                                        key: Key('opening-results-${o.id}'),
                                        onPressed: () =>
                                            _results(context, o, modules),
                                        child: Text(
                                          l10n.ieltsOpeningsResults,
                                          semanticsLabel: l10n
                                              .ieltsOpeningsResultsFor(o.batch),
                                        ),
                                      ),
                                      if (modules.contains('WRITING'))
                                        TextButton(
                                          key: Key(
                                            'opening-plagiarism-${o.id}',
                                          ),
                                          onPressed: () => context.push(
                                            '/ielts/assignments/${o.id}/similarity',
                                          ),
                                          child: Text(
                                            l10n.ieltsOpeningsPlagiarism,
                                            semanticsLabel: l10n
                                                .ieltsOpeningsPlagiarismFor(
                                                  o.batch,
                                                ),
                                          ),
                                        ),
                                      TextButton(
                                        key: Key('opening-change-${o.id}'),
                                        onPressed: () => _edit(context, ref, o),
                                        child: Text(
                                          l10n.ieltsOpeningsChange,
                                          semanticsLabel: l10n
                                              .ieltsOpeningsChangeFor(o.batch),
                                        ),
                                      ),
                                      TextButton(
                                        key: Key('opening-remove-${o.id}'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: colors.danger,
                                        ),
                                        onPressed: () =>
                                            _remove(context, ref, o),
                                        child: Text(
                                          l10n.ieltsOpeningsRemove,
                                          semanticsLabel: l10n
                                              .ieltsOpeningsRemoveFor(o.batch),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
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

/// A batch and the window, in the centre's time (Asia/Dhaka).
class _OpeningForm extends ConsumerStatefulWidget {
  const _OpeningForm({required this.testId, this.opening});

  final String testId;
  final IeltsOpening? opening;

  @override
  ConsumerState<_OpeningForm> createState() => _OpeningFormState();
}

class _OpeningFormState extends ConsumerState<_OpeningForm> {
  String? _section;
  late DateTime? _opens = widget.opening?.opens;
  late DateTime? _closes = widget.opening?.closes;
  bool _busy = false;

  bool get _ready =>
      (widget.opening != null || _section != null) &&
      _opens != null &&
      _closes != null;

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    final window = {
      'opens_at': _opens!.toUtc().toIso8601String(),
      'closes_at': _closes!.toUtc().toIso8601String(),
    };
    try {
      final api = ref.read(apiClientProvider);
      if (widget.opening != null) {
        await api.patch(
          '/ielts/assignments/${widget.opening!.id}',
          data: window,
        );
      } else {
        await api.post(
          '/ielts/tests/${widget.testId}/assignments',
          data: {'section_id': _section, ...window},
        );
      }
      nav.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final batches = ref.watch(_batchesProvider).value ?? const [];
    final o = widget.opening;
    final openDay = _opens == null
        ? null
        : OrgTime.wallClock(_opens!).toIso8601String().substring(0, 10);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                o == null
                    ? l10n.ieltsOpeningsOpen
                    : l10n.ieltsOpeningsChangeTitle(o.batch),
                style: text.titleLarge,
              ),
              Text(l10n.ieltsOpeningsTimeZoneNote, style: text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              if (o == null)
                DropdownButtonFormField<String>(
                  key: const Key('opening-batch'),
                  initialValue: _section,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.ieltsOpeningsBatch,
                    hintText: l10n.ieltsOpeningsChooseBatch,
                  ),
                  items: [
                    for (final b in batches)
                      DropdownMenuItem(value: b.id, child: Text(b.label)),
                  ],
                  onChanged: (v) => setState(() => _section = v),
                ),
              const SizedBox(height: AppSpacing.sm),
              DateTimeField(
                key: const ValueKey('opening-opens'),
                dateLabel: l10n.ieltsOpeningsOpensOn,
                timeLabel: l10n.ieltsOpeningsOpensAt,
                value: _opens,
                onChanged: (v) => setState(() => _opens = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              DateTimeField(
                key: const ValueKey('opening-closes'),
                dateLabel: l10n.ieltsOpeningsClosesOn,
                timeLabel: l10n.ieltsOpeningsClosesAt,
                value: _closes,
                defaultHour: 17,
                min: openDay,
                onChanged: (v) => setState(() => _closes = v),
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.ieltsOpeningsCancel),
                  ),
                  FilledButton(
                    key: const Key('opening-save'),
                    onPressed: _ready && !_busy ? _save : null,
                    child: Text(l10n.ieltsOpeningsSave),
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

/// Each student of the batch with the band (and score out of 40) per
/// module, and the overall band once all four are marked.
class _Results extends ConsumerWidget {
  const _Results({required this.opening, required this.modules});

  final IeltsOpening opening;
  final List<String> modules;

  /// Starts (or resumes) a live Speaking session and opens the examiner.
  Future<void> _examine(
    BuildContext context,
    WidgetRef ref,
    String studentId,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post(
            '/ielts/assignments/${opening.id}/speaking',
            data: {'student_id': studentId},
          );
      final id = r.payload is Map ? (r.payload! as Map)['attempt_id'] : null;
      if (id != null) unawaited(router.push('/ielts/speaking/$id'));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  /// Examine, continue the live session, or mark a practice recording.
  Widget _speakingAction(
    BuildContext context,
    WidgetRef ref,
    IeltsResultRow r,
  ) {
    final l10n = context.l10n;
    final a = r.modules['SPEAKING'];
    if (a == null || (a.status == 'IN_PROGRESS' && a.mode == 'LIVE')) {
      return TextButton(
        key: Key('examine-${r.studentId}'),
        onPressed: () => _examine(context, ref, r.studentId),
        child: Text(
          a == null
              ? l10n.ieltsOpeningsExamine
              : l10n.ieltsOpeningsContinueExam,
          semanticsLabel: l10n.ieltsOpeningsExamineFor(r.name),
        ),
      );
    }
    if (a.status != 'IN_PROGRESS' && a.band == null) {
      return TextButton(
        key: Key('mark-speaking-${r.studentId}'),
        onPressed: () => context.push('/ielts/speaking/${a.attemptId}'),
        child: Text(l10n.ieltsOpeningsMarkNow),
      );
    }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    String cell(IeltsResultRow r, String m) {
      final a = r.modules[m];
      if (a == null) return l10n.ieltsOpeningsNotStarted;
      if (a.status == 'IN_PROGRESS') return l10n.ieltsOpeningsInProgress;
      if (a.band == null) return l10n.ieltsOpeningsWaitingForMarks;
      final raw = a.raw == null
          ? ''
          : ' (${OrgTime.number(a.raw!, lang)}/${OrgTime.number(a.rawTotal ?? 40, lang)})';
      return '${bandText(a.band, lang)}$raw';
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: ref
            .watch(ieltsResultsProvider(opening.id))
            .when(
              loading: () =>
                  LoadingView(semanticsLabel: l10n.ieltsOpeningsResultsCaption),
              error: (e, _) => ErrorView(
                title: l10n.ieltsOpeningsLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(ieltsResultsProvider(opening.id)),
              ),
              data: (rows) => ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    l10n.ieltsOpeningsResultsTitle(opening.batch),
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (rows.isEmpty)
                    Text(l10n.ieltsOpeningsNoStudents)
                  else
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: AppCard(
                          key: Key('result-${r.studentId}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      key: Key('report-${r.studentId}'),
                                      onTap: () => context.push(
                                        '/ielts/report/${opening.id}/${r.studentId}',
                                      ),
                                      child: Text(
                                        r.name,
                                        style: text.titleSmall?.copyWith(
                                          color: AppColors.of(context).primary,
                                        ),
                                        semanticsLabel: l10n
                                            .ieltsOpeningsReportFor(r.name),
                                      ),
                                    ),
                                  ),
                                  if (modules.length == 4)
                                    Text(
                                      '${l10n.ieltsOpeningsOverall} '
                                      '${bandText(r.overall, lang)}',
                                      style: text.titleSmall,
                                    ),
                                ],
                              ),
                              for (final m in modules)
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      '${ieltsModuleShort(l10n, m)}: ${cell(r, m)}',
                                      style: muted,
                                    ),
                                    if (m == 'SPEAKING')
                                      _speakingAction(context, ref, r),
                                    if (m == 'WRITING' &&
                                        r.modules['WRITING'] != null &&
                                        r.modules['WRITING']!.status !=
                                            'IN_PROGRESS' &&
                                        r.modules['WRITING']!.band == null)
                                      TextButton(
                                        key: Key('mark-writing-${r.studentId}'),
                                        onPressed: () => context.push(
                                          '/ielts/marking/${r.modules['WRITING']!.attemptId}',
                                        ),
                                        child: Text(l10n.ieltsOpeningsMarkNow),
                                      ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
      ),
    );
  }
}
