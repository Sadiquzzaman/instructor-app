import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/screens/ielts_builder_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_take_screens.dart';
import 'package:instructor_app/features/ielts/screens/ielts_tests_screens.dart';

num? _num(Object? v) => v is num ? v : null;

final ieltsProgressProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>?, String>((ref, who) async {
      ref.watch(workspaceKeyProvider);
      final p = (await ref.read(apiClientProvider).get('/ielts/progress/$who'))
          .payload;
      return p is Map ? p.cast<String, Object?>() : null;
    }, retry: (retryCount, error) => null);

final ieltsReportProvider = FutureProvider.autoDispose
    .family<Map<String, Object?>?, (String, String)>((ref, k) async {
      ref.watch(workspaceKeyProvider);
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get('/ielts/report/${k.$1}/${k.$2}'))
              .payload;
      return p is Map ? p.cast<String, Object?>() : null;
    }, retry: (retryCount, error) => null);

/// One module's bands over time, oldest first, against the target: small
/// bars from 0 to 9 with the target marked.
class _BandBars extends StatelessWidget {
  const _BandBars({required this.points, required this.target});

  final List<({num band, String test, DateTime? at})> points;
  final num? target;

  @override
  Widget build(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    const height = 96.0;
    return SizedBox(
      height: height + 36,
      child: Stack(
        children: [
          if (target != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 36 + height * target! / 9,
              child: Container(height: 1, color: colors.inkMuted),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final p in points)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Tooltip(
                      message: p.at == null
                          ? p.test
                          : '${p.test} · ${OrgTime.date(p.at!, lang)}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            width: 22,
                            height: height * p.band / 9,
                            decoration: BoxDecoration(
                              color: target != null && p.band >= target!
                                  ? colors.success
                                  : colors.primary,
                              borderRadius: AppRadius.inputAll,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(bandText(p.band, lang), style: text.labelSmall),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The web's /ielts/progress (P10-07): bands per module over time against
/// the target, complete mocks with the overall band, and the question
/// types by share right, weakest first. Staff open it for a student
/// ([studentId]); a student sees their own.
class IeltsProgressScreen extends ConsumerWidget {
  const IeltsProgressScreen({this.studentId, super.key});

  final String? studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final who = studentId ?? 'me';
    return ref
        .watch(ieltsProgressProvider(who))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.ieltsProgressTitle),
          error: (e, _) => ErrorView(
            title: e is ApiException && e.statusCode == 404
                ? l10n.ieltsProgressNotFound
                : l10n.ieltsProgressLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(ieltsProgressProvider(who)),
          ),
          data: (d) {
            if (d == null) {
              return EmptyView(
                icon: Icons.insights_outlined,
                title: l10n.ieltsProgressNotFound,
              );
            }
            final profile = d['profile'] is Map
                ? d['profile']! as Map
                : const <String, Object?>{};
            final student = profile['student'] is Map
                ? profile['student'] as Map
                : const <String, Object?>{};
            final overallTarget = _num(profile['target_overall']);
            final targets = profile['target_bands'] is Map
                ? profile['target_bands'] as Map
                : const <String, Object?>{};
            final modules = d['modules'] is Map
                ? d['modules']! as Map
                : const <String, Object?>{};
            final mocks = [
              for (final m in (d['mocks'] as List?) ?? const [])
                if (m is Map) m,
            ];
            final types = [
              for (final q in (d['question_types'] as List?) ?? const [])
                if (q is Map) q,
            ];
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(
                      studentId == null
                          ? l10n.ieltsProgressTitle
                          : l10n.ieltsProgressTitleFor(
                              '${student['full_name'] ?? ''}',
                            ),
                      style: text.headlineSmall,
                    ),
                    Text(
                      overallTarget == null
                          ? l10n.ieltsProgressNoTarget
                          : l10n.ieltsProgressTarget(
                              bandText(overallTarget, lang),
                            ),
                      style: muted,
                    ),
                    for (final m in ieltsModules)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.md),
                        child: AppCard(
                          key: Key('progress-$m'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                ieltsModuleShort(l10n, m),
                                style: text.titleSmall,
                              ),
                              () {
                                final pts = [
                                  for (final p
                                      in (modules[m] as List?) ?? const [])
                                    if (p is Map && p['band'] is num)
                                      (
                                        band: p['band'] as num,
                                        test: '${p['test_title'] ?? ''}',
                                        at: DateTime.tryParse('${p['at']}'),
                                      ),
                                ];
                                final target =
                                    _num(targets[m]) ?? overallTarget;
                                if (pts.isEmpty) {
                                  return Text(
                                    l10n.ieltsProgressNoBands,
                                    style: muted,
                                  );
                                }
                                return Semantics(
                                  label: l10n.ieltsProgressChartLabel(
                                    ieltsModuleShort(l10n, m),
                                    pts
                                        .map((p) => bandText(p.band, lang))
                                        .join(', '),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (target != null)
                                        Text(
                                          l10n.ieltsProgressTargetShort(
                                            bandText(target, lang),
                                          ),
                                          style: muted,
                                        ),
                                      _BandBars(points: pts, target: target),
                                    ],
                                  ),
                                );
                              }(),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.ieltsProgressMocksTitle,
                            style: text.titleSmall,
                          ),
                          Text(
                            l10n.ieltsProgressMocksDescription,
                            style: muted,
                          ),
                          if (mocks.isEmpty)
                            Text(l10n.ieltsProgressNoMocks)
                          else
                            for (final mk in mocks)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.sm,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${mk['test_title'] ?? ''} · '
                                      '${l10n.ieltsProgressOverall} '
                                      '${bandText(_num(mk['overall']), lang)}',
                                      style: text.bodyMedium,
                                    ),
                                    Text(
                                      [
                                        for (final m in ieltsModules)
                                          '${ieltsModuleShort(l10n, m)} ${bandText(_num((mk['bands'] as Map?)?[m]), lang)}',
                                      ].join(' · '),
                                      style: muted,
                                    ),
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            l10n.ieltsProgressTypesTitle,
                            style: text.titleSmall,
                          ),
                          Text(
                            l10n.ieltsProgressTypesDescription,
                            style: muted,
                          ),
                          if (types.isEmpty)
                            Text(l10n.ieltsProgressNoTypes)
                          else
                            for (final q in types)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        groupTypeName(l10n, '${q['type']}'),
                                        style: text.bodyMedium,
                                      ),
                                    ),
                                    Text(
                                      '${l10n.ieltsProgressRightOf(_num(q['right']) ?? 0, _num(q['total']) ?? 0)} · '
                                      '${OrgTime.number(_num(q['percent']) ?? 0, lang)}%',
                                      style: text.bodySmall,
                                    ),
                                  ],
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

/// The web's one-page band report (P10-07): module bands against the
/// targets, the overall band, Writing and Speaking criteria with comments,
/// and the test date. Shown in the app; printing stays on the web.
class IeltsBandReportScreen extends ConsumerWidget {
  const IeltsBandReportScreen({
    required this.assignmentId,
    required this.studentId,
    super.key,
  });

  final String assignmentId;

  /// A student id, or "me".
  final String studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final key = (assignmentId, studentId);
    return ref
        .watch(ieltsReportProvider(key))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.ieltsReportTitle),
          error: (e, _) => ErrorView(
            title: e is ApiException && e.statusCode == 404
                ? l10n.ieltsReportNotFound
                : l10n.ieltsReportLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(ieltsReportProvider(key)),
          ),
          data: (d) {
            if (d == null) {
              return EmptyView(
                icon: Icons.description_outlined,
                title: l10n.ieltsReportNotFound,
              );
            }
            final student = d['student'] is Map
                ? d['student']! as Map
                : const <String, Object?>{};
            final test = d['test'] is Map
                ? d['test']! as Map
                : const <String, Object?>{};
            final window = d['window'] is Map
                ? d['window']! as Map
                : const <String, Object?>{};
            final modules = d['modules'] is Map
                ? d['modules']! as Map
                : const <String, Object?>{};
            final targets = d['targets'] is Map
                ? d['targets']! as Map
                : const <String, Object?>{};
            final tBands = targets['bands'] is Map
                ? targets['bands'] as Map
                : const <String, Object?>{};
            final opens = DateTime.tryParse('${window['opens_at']}');
            final testDate = d['test_date'] as String?;
            String criteriaRow(Map<dynamic, dynamic> c) => [
              for (final e in orderedCriteria(c))
                '${criterionName(l10n, e.key)} ${bandText(e.value, lang)}',
            ].join(' · ');
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Text(l10n.ieltsReportTitle, style: text.headlineSmall),
                    Text(
                      '${student['full_name'] ?? ''}'
                      '${student['batch'] == null ? '' : ' · ${student['batch']}'}',
                      style: muted,
                    ),
                    Text(
                      '${test['title'] ?? ''} · '
                      '${ieltsTestTypeName(l10n, '${test['test_type'] ?? 'ACADEMIC'}')}'
                      '${opens == null ? '' : ' · ${OrgTime.date(opens, lang)}'}',
                      style: muted,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.ieltsReportModule,
                                  style: muted,
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  l10n.ieltsReportBand,
                                  style: muted,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  l10n.ieltsReportTarget,
                                  style: muted,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                          for (final m in ieltsModules)
                            if (modules[m] is Map)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.xs,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        [
                                          ieltsModuleShort(l10n, m),
                                          if (_num(
                                                (modules[m]
                                                    as Map)['raw_score'],
                                              ) !=
                                              null)
                                            l10n.ieltsTakeScoreOutOf(
                                              _num(
                                                (modules[m]
                                                    as Map)['raw_score'],
                                              )!,
                                              _num(
                                                    (modules[m]
                                                        as Map)['raw_total'],
                                                  ) ??
                                                  40,
                                            ),
                                          if ((modules[m] as Map)['band'] ==
                                              null)
                                            l10n.ieltsReportNotMarked,
                                        ].join(' · '),
                                        style: text.bodyMedium,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        bandText(
                                          _num((modules[m] as Map)['band']),
                                          lang,
                                        ),
                                        key: Key('report-band-$m'),
                                        style: text.titleSmall,
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                                    SizedBox(
                                      width: 72,
                                      child: Text(
                                        bandText(
                                          _num(tBands[m]) ??
                                              _num(targets['overall']),
                                          lang,
                                        ),
                                        style: muted,
                                        textAlign: TextAlign.end,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          const Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  l10n.ieltsReportOverall,
                                  style: text.titleSmall,
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  bandText(_num(d['overall']), lang),
                                  key: const Key('report-overall'),
                                  style: text.titleMedium,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  bandText(_num(targets['overall']), lang),
                                  style: muted,
                                  textAlign: TextAlign.end,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    for (final m in ['WRITING', 'SPEAKING'])
                      if (modules[m] is Map &&
                          (modules[m] as Map)['criteria'] is Map)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.md),
                          child: AppCard(
                            child: () {
                              final row = modules[m] as Map;
                              final c = row['criteria'] as Map;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    ieltsModuleShort(l10n, m),
                                    style: text.titleSmall,
                                  ),
                                  for (final t
                                      in (c['tasks'] as List?) ?? const [])
                                    if (t is Map) ...[
                                      Text(
                                        '${l10n.ieltsTakeTaskBand(bandText(_num(t['band']), lang))} · '
                                        '${ieltsPartName(l10n, 'WRITING', (_num(t['part_no']) ?? 1).toInt())}',
                                        style: text.bodyMedium,
                                      ),
                                      if (t['criteria'] is Map)
                                        Text(
                                          criteriaRow(t['criteria'] as Map),
                                          style: muted,
                                        ),
                                      if ((t['comment'] as String?)
                                              ?.isNotEmpty ??
                                          false)
                                        Text(t['comment'] as String),
                                    ],
                                  if (c['speaking'] is Map)
                                    Text(
                                      criteriaRow(c['speaking'] as Map),
                                      style: muted,
                                    ),
                                  if ((row['feedback'] as String?)
                                          ?.isNotEmpty ??
                                      false)
                                    Text(row['feedback'] as String),
                                ],
                              );
                            }(),
                          ),
                        ),
                    if (testDate != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        l10n.ieltsReportTestDate(
                          OrgTime.schoolDay(testDate, lang),
                        ),
                        style: muted,
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
  }
}
