import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/text/html_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/data/marking.dart';
import 'package:instructor_app/features/ielts/data/profiles.dart';
import 'package:instructor_app/features/ielts/screens/ielts_overview_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_take_screens.dart';

/// A row of `GET /ielts/marking`.
typedef IeltsMarkingRow = ({
  String attemptId,
  String module,
  String status,
  String studentName,
  String testTitle,
  String batch,
  DateTime? submittedAt,
  num? band,
});

final ieltsMarkingListProvider = FutureProvider.autoDispose
    .family<List<IeltsMarkingRow>, ({String state, String module})>((
      ref,
      f,
    ) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get(
                    '/ielts/marking',
                    query: {'state': f.state, 'module': f.module},
                  ))
              .payload;
      return [
        if (p is List)
          for (final r in p)
            if (r is Map)
              (
                attemptId: '${r['attempt_id']}',
                module: '${r['module'] ?? f.module}',
                status: '${r['status'] ?? ''}',
                studentName: '${(r['student'] as Map?)?['full_name'] ?? ''}',
                testTitle: '${(r['test'] as Map?)?['title'] ?? ''}',
                batch: '${r['batch'] ?? ''}',
                submittedAt: DateTime.tryParse('${r['submitted_at']}'),
                band: r['band'] as num?,
              ),
      ];
    }, retry: (retryCount, error) => null);

/// Where an attempt is marked: the examiner for Speaking, else Writing.
String markingRoute(String module, String attemptId) => module == 'SPEAKING'
    ? '/ielts/speaking/$attemptId'
    : '/ielts/marking/$attemptId';

/// The web's /ielts/marking (P10-05, P10-06): Writing or Speaking waiting
/// to be marked (oldest first) or marked, for the centre's staff.
class IeltsMarkingListScreen extends ConsumerStatefulWidget {
  const IeltsMarkingListScreen({super.key});

  @override
  ConsumerState<IeltsMarkingListScreen> createState() =>
      _IeltsMarkingListScreenState();
}

class _IeltsMarkingListScreenState
    extends ConsumerState<IeltsMarkingListScreen> {
  String _state = 'WAITING';
  String _module = 'WRITING';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final filter = (state: _state, module: _module);
    final rows = ref.watch(ieltsMarkingListProvider(filter));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(ieltsMarkingListProvider(filter).future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.ieltsMarkingTitle, style: text.headlineSmall),
              Text(
                _module == 'SPEAKING'
                    ? l10n.ieltsMarkingDescriptionSpeaking
                    : l10n.ieltsMarkingDescription,
                style: muted,
              ),
              const SizedBox(height: AppSpacing.sm),
              SegmentedButton<String>(
                key: const Key('marking-module'),
                segments: [
                  ButtonSegment(
                    value: 'WRITING',
                    label: Text(l10n.ieltsMarkingModulesWRITING),
                  ),
                  ButtonSegment(
                    value: 'SPEAKING',
                    label: Text(l10n.ieltsMarkingModulesSPEAKING),
                  ),
                ],
                selected: {_module},
                onSelectionChanged: (s) => setState(() => _module = s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final s in ['WAITING', 'MARKED'])
                    ChoiceChip(
                      key: Key('marking-state-$s'),
                      label: Text(
                        s == 'WAITING'
                            ? l10n.ieltsMarkingWaiting
                            : l10n.ieltsMarkingMarked,
                      ),
                      selected: _state == s,
                      onSelected: (_) => setState(() => _state = s),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              ...rows.when(
                loading: () => [
                  SizedBox(
                    height: 160,
                    child: LoadingView(semanticsLabel: l10n.ieltsMarkingTitle),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 260,
                    child: ErrorView(
                      title: e is ApiException && e.statusCode == 403
                          ? l10n.ieltsTestsNotAvailable
                          : l10n.ieltsMarkingLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () =>
                          ref.invalidate(ieltsMarkingListProvider(filter)),
                    ),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [
                        EmptyView(
                          icon: Icons.fact_check_outlined,
                          title: _state == 'WAITING'
                              ? l10n.ieltsMarkingNoneWaiting
                              : l10n.ieltsMarkingNoneMarked,
                        ),
                      ]
                    : [
                        for (final r in list)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AppCard(
                              key: Key('marking-${r.attemptId}'),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          r.studentName,
                                          style: text.titleSmall,
                                        ),
                                        Text(
                                          '${r.testTitle} · ${r.batch}',
                                          style: muted,
                                        ),
                                        Text(
                                          '${l10n.ieltsMarkingHandedIn}: '
                                          '${r.submittedAt == null ? '—' : OrgTime.dateTime(r.submittedAt!, lang)}'
                                          ' · ${l10n.ieltsMarkingBand}: ${bandText(r.band, lang)}',
                                          style: text.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    key: Key('marking-open-${r.attemptId}'),
                                    onPressed: () async {
                                      await context.push(
                                        markingRoute(r.module, r.attemptId),
                                      );
                                      ref.invalidate(ieltsMarkingListProvider);
                                    },
                                    child: Text(
                                      r.status == 'MARKED'
                                          ? l10n.ieltsMarkingChange
                                          : l10n.ieltsMarkingMark,
                                      semanticsLabel: r.module == 'SPEAKING'
                                          ? l10n.ieltsMarkingMarkSpeakingFor(
                                              r.studentName,
                                            )
                                          : l10n.ieltsMarkingMarkFor(
                                              r.studentName,
                                            ),
                                    ),
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

/// The web's /ielts/marking/[attemptId] (P10-05): each Writing task with
/// the script and its word count, a band per criterion, the task band
/// worked out as the server does, a comment per task and feedback.
class IeltsMarkWritingScreen extends ConsumerStatefulWidget {
  const IeltsMarkWritingScreen({required this.attemptId, super.key});

  final String attemptId;

  @override
  ConsumerState<IeltsMarkWritingScreen> createState() =>
      _IeltsMarkWritingScreenState();
}

class _IeltsMarkWritingScreenState
    extends ConsumerState<IeltsMarkWritingScreen> {
  Map<String, Map<String, num?>>? _given;
  final _comments = <String, TextEditingController>{};
  TextEditingController? _feedback;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _comments.values) {
      c.dispose();
    }
    _feedback?.dispose();
    super.dispose();
  }

  Future<void> _save(
    IeltsMarkingView v,
    Map<String, Map<String, num?>> g,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/ielts/marking/${widget.attemptId}/writing',
            data: {
              'tasks': [
                for (final t in v.tasks)
                  {
                    'part_id': t.partId,
                    'criteria': {
                      for (final k in writingCriteria(t.partNo))
                        k: g[t.partId]![k],
                    },
                    if (_comments[t.partId]!.text.trim().isNotEmpty)
                      'comment': _comments[t.partId]!.text.trim(),
                  },
              ],
              if (_feedback!.text.trim().isNotEmpty)
                'feedback': _feedback!.text.trim(),
            },
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.ieltsMarkingSaved)));
      ref.invalidate(ieltsMarkingProvider(widget.attemptId));
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
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return ref
        .watch(ieltsMarkingProvider(widget.attemptId))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.ieltsMarkingTitle),
          error: (e, _) => ErrorView(
            title: e is ApiException && e.statusCode == 409
                ? l10n.ieltsMarkingNotHandedIn
                : l10n.ieltsMarkingLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () =>
                ref.invalidate(ieltsMarkingProvider(widget.attemptId)),
          ),
          data: (v) {
            if (v == null) {
              return EmptyView(
                icon: Icons.fact_check_outlined,
                title: l10n.ieltsMarkingLoadFailed,
              );
            }
            final g =
                _given ??
                {
                  for (final t in v.tasks)
                    t.partId: <String, num?>{
                      ...?v.marks
                          .where((m) => m.partId == t.partId)
                          .firstOrNull
                          ?.criteria,
                    },
                };
            for (final t in v.tasks) {
              _comments.putIfAbsent(
                t.partId,
                () => TextEditingController(
                  text:
                      v.marks
                          .where((m) => m.partId == t.partId)
                          .firstOrNull
                          ?.comment ??
                      '',
                ),
              );
            }
            _feedback ??= TextEditingController(text: v.feedback ?? '');
            num? taskBand(MarkingTask t) => criteriaBand(
              g[t.partId] ?? const {},
              writingCriteria(t.partNo),
            );
            final ready = v.tasks.every((t) => taskBand(t) != null);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(
                      l10n.ieltsMarkingMarkTitle(v.studentName),
                      style: text.headlineSmall,
                    ),
                    Text('${v.testTitle} · ${v.batch}', style: muted),
                    if (v.band != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      IeltsStat(
                        l10n.ieltsMarkingWritingBand,
                        bandText(v.band, lang),
                      ),
                    ],
                    for (final t in v.tasks)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: AppCard(
                          key: Key('mark-task-${t.partId}'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.ieltsMarkingTaskN(t.partNo),
                                style: text.titleMedium,
                              ),
                              if (t.content?.isNotEmpty ?? false)
                                Text(
                                  htmlToText(t.content!),
                                  style: text.bodyMedium,
                                ),
                              if (t.imageFileId != null)
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.image_outlined),
                                    label: Text(l10n.ieltsTakePicture),
                                    onPressed: () =>
                                        openFile(context, ref, t.imageFileId!),
                                  ),
                                ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                t.words < t.minWords
                                    ? '${l10n.ieltsTakeWordCount(t.words)} · ${l10n.ieltsTakeUnderMinimum(t.minWords)}'
                                    : l10n.ieltsTakeWordCount(t.words),
                                style: text.bodySmall?.copyWith(
                                  color: t.words < t.minWords
                                      ? colors.warning
                                      : colors.inkMuted,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.sm),
                                decoration: BoxDecoration(
                                  color: colors.canvas,
                                  border: Border.all(color: colors.border),
                                  borderRadius: AppRadius.cardAll,
                                ),
                                child: SelectableText(
                                  t.script.isEmpty ? '—' : t.script,
                                  style: text.bodyMedium,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: AppSpacing.sm,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  for (final k in writingCriteria(t.partNo))
                                    SizedBox(
                                      width: 200,
                                      child: DropdownButtonFormField<num>(
                                        key: Key('criterion-${t.partId}-$k'),
                                        initialValue:
                                            ieltsBands.contains(g[t.partId]?[k])
                                            ? g[t.partId]![k]
                                            : null,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          labelText: criterionName(l10n, k),
                                        ),
                                        items: [
                                          for (final b in ieltsBands)
                                            DropdownMenuItem(
                                              value: b,
                                              child: Text(bandText(b, lang)),
                                            ),
                                        ],
                                        onChanged: (b) => setState(
                                          () => _given = {
                                            ...g,
                                            t.partId: {...?g[t.partId], k: b},
                                          },
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                taskBand(t) == null
                                    ? l10n.ieltsMarkingTaskBandPending
                                    : l10n.ieltsTakeTaskBand(
                                        bandText(taskBand(t), lang),
                                      ),
                                key: Key('task-band-${t.partId}'),
                                style: text.titleSmall,
                              ),
                              TextField(
                                key: Key('comment-${t.partId}'),
                                controller: _comments[t.partId],
                                minLines: 2,
                                maxLines: 6,
                                decoration: InputDecoration(
                                  labelText: l10n.ieltsMarkingComment,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            key: const Key('writing-feedback'),
                            controller: _feedback,
                            minLines: 3,
                            maxLines: 8,
                            decoration: InputDecoration(
                              labelText: l10n.ieltsTakeFeedback,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(l10n.ieltsMarkingRule, style: muted),
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: FilledButton(
                              key: const Key('writing-save'),
                              onPressed: _busy || !ready
                                  ? null
                                  : () => _save(v, g),
                              child: Text(l10n.ieltsMarkingSaveMarks),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
  }
}
