import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

final ieltsStaffDashboardProvider =
    FutureProvider.autoDispose<IeltsStaffDashboard>((ref) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref.read(apiClientProvider).get('/ielts/dashboard');
      return IeltsStaffDashboard.fromJson(
        r.payload is Map ? (r.payload! as Map).cast() : const {},
      );
    }, retry: (retryCount, error) => null);

final ieltsStudentDashboardProvider =
    FutureProvider.autoDispose<IeltsStudentDashboard>((ref) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref.read(apiClientProvider).get('/ielts/dashboard/me');
      return IeltsStudentDashboard.fromJson(
        r.payload is Map ? (r.payload! as Map).cast() : const {},
      );
    }, retry: (retryCount, error) => null);

/// The web's /ielts/overview (P10-07): staff see the centre (batches,
/// students, marking waiting, mocks coming up, bands per batch); a student
/// sees their targets against their latest bands and the next test.
class IeltsOverviewScreen extends ConsumerWidget {
  const IeltsOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ieltsStudent(ref.watch(sessionProvider));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: student ? const _StudentOverview() : const _StaffOverview(),
      ),
    );
  }
}

Widget _failed(BuildContext context, Object e, VoidCallback retry) {
  final l10n = context.l10n;
  return ErrorView(
    title: e is ApiException && e.statusCode == 403
        ? l10n.ieltsTestsNotAvailable
        : l10n.ieltsOverviewLoadFailed,
    retryLabel: l10n.uiErrorRetry,
    onRetry: retry,
  );
}

class _StaffOverview extends ConsumerWidget {
  const _StaffOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    String n(num v) => OrgTime.number(v, lang);
    return ref
        .watch(ieltsStaffDashboardProvider)
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.ieltsOverviewTitle),
          error: (e, _) => _failed(
            context,
            e,
            () => ref.invalidate(ieltsStaffDashboardProvider),
          ),
          data: (d) => RefreshIndicator(
            onRefresh: () => ref.refresh(ieltsStaffDashboardProvider.future),
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(l10n.ieltsOverviewTitle, style: text.headlineSmall),
                Text(l10n.ieltsOverviewStaffDescription, style: muted),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    IeltsStat(l10n.ieltsOverviewBatches, n(d.batches)),
                    IeltsStat(l10n.ieltsOverviewStudents, n(d.students)),
                    IeltsStat(
                      l10n.ieltsOverviewWritingWaiting,
                      n(d.writingWaiting),
                    ),
                    IeltsStat(
                      l10n.ieltsOverviewSpeakingWaiting,
                      n(d.speakingWaiting),
                    ),
                  ],
                ),
                if (d.writingWaiting + d.speakingWaiting > 0)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('ielts-go-marking'),
                      onPressed: () => context.go('/ielts/marking'),
                      child: Text(l10n.ieltsOverviewGoToMarking),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.ieltsOverviewUpcomingTitle,
                        style: text.titleSmall,
                      ),
                      Text(l10n.ieltsOverviewUpcomingDescription, style: muted),
                      if (d.upcoming.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(l10n.ieltsOverviewNoUpcoming),
                        )
                      else
                        for (final u in d.upcoming)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('${u.title} · ${u.batch}'),
                            subtitle: Text(_window(u.opens, u.closes, lang)),
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
                        l10n.ieltsOverviewBatchBandsTitle,
                        style: text.titleSmall,
                      ),
                      Text(
                        l10n.ieltsOverviewBatchBandsDescription,
                        style: muted,
                      ),
                      if (d.batchBands.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(l10n.ieltsOverviewNoBands),
                        )
                      else
                        _BandTable(
                          header: [
                            l10n.ieltsOverviewBatch,
                            for (final m in ieltsModules)
                              ieltsModuleShort(l10n, m),
                          ],
                          rows: [
                            for (final b in d.batchBands)
                              [
                                b.batch,
                                for (final m in ieltsModules)
                                  bandText(b.bands[m], lang),
                              ],
                          ],
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

String _window(DateTime? from, DateTime? to, String lang) =>
    '${from == null ? '—' : OrgTime.dateTime(from, lang)} – '
    '${to == null ? '—' : OrgTime.dateTime(to, lang)}';

class _StudentOverview extends ConsumerWidget {
  const _StudentOverview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    return ref
        .watch(ieltsStudentDashboardProvider)
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.ieltsOverviewTitle),
          error: (e, _) => _failed(
            context,
            e,
            () => ref.invalidate(ieltsStudentDashboardProvider),
          ),
          data: (d) {
            final days = d.daysToTest;
            String gap(String m) {
              final t = d.targetFor(m);
              final l = d.latest[m];
              if (t == null || l == null) return '—';
              return l >= t
                  ? l10n.ieltsOverviewReached
                  : l10n.ieltsOverviewToGo(bandText(t - l, lang));
            }

            return RefreshIndicator(
              onRefresh: () =>
                  ref.refresh(ieltsStudentDashboardProvider.future),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(l10n.ieltsOverviewTitle, style: text.headlineSmall),
                  Text(l10n.ieltsOverviewStudentDescription, style: muted),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      IeltsStat(
                        l10n.ieltsOverviewTargetOverall,
                        bandText(d.targetOverall, lang),
                      ),
                      IeltsStat(
                        l10n.ieltsOverviewDaysToTest,
                        days == null || days < 0
                            ? '—'
                            : OrgTime.number(days, lang),
                      ),
                      IeltsStat(
                        l10n.ieltsOverviewOpenNow,
                        OrgTime.number(d.openNow, lang),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.ieltsOverviewNextTitle,
                          style: text.titleSmall,
                        ),
                        if (d.next case final next?) ...[
                          Text(
                            '${next.title} · ${ieltsPurpose(l10n, next.purpose)}',
                            key: const Key('ielts-next'),
                            style: text.bodyMedium,
                          ),
                          Text(
                            _window(next.opens, next.closes, lang),
                            style: muted,
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              key: const Key('ielts-go-tests'),
                              onPressed: () => context.go('/ielts/my'),
                              child: Text(l10n.ieltsOverviewGoToTests),
                            ),
                          ),
                        ] else
                          Text(l10n.ieltsOverviewNoNext),
                      ],
                    ),
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
                                l10n.ieltsOverviewTargetsTitle,
                                style: text.titleSmall,
                              ),
                            ),
                            TextButton(
                              key: const Key('ielts-see-progress'),
                              onPressed: () => context.push('/ielts/progress'),
                              child: Text(l10n.ieltsOverviewSeeProgress),
                            ),
                          ],
                        ),
                        _BandTable(
                          header: [
                            l10n.ieltsOverviewModule,
                            l10n.ieltsOverviewTarget,
                            l10n.ieltsOverviewLatest,
                            l10n.ieltsOverviewGap,
                          ],
                          rows: [
                            for (final m in ieltsModules)
                              [
                                ieltsModuleShort(l10n, m),
                                bandText(d.targetFor(m), lang),
                                bandText(d.latest[m], lang),
                                gap(m),
                              ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
  }
}

/// A small figure with its label (the web's StatTile).
class IeltsStat extends StatelessWidget {
  const IeltsStat(this.label, this.value, {super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.cardAll,
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.bodySmall?.copyWith(color: colors.inkMuted)),
          Text(value, style: text.titleLarge),
        ],
      ),
    );
  }
}

/// A simple table: the first column takes the room, the rest are figures.
class _BandTable extends StatelessWidget {
  const _BandTable({required this.header, required this.rows});

  final List<String> header;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    TableRow row(List<String> cells, TextStyle? style) => TableRow(
      children: [
        for (final (i, c) in cells.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text(
              c,
              style: style,
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
            ),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(2)},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          row(header, muted),
          for (final r in rows) row(r, text.bodyMedium),
        ],
      ),
    );
  }
}
