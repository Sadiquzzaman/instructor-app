import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';

/// The plan and what is used (`GET /me/entitlements`).
typedef PlanUsage = ({
  String? plan,
  int examsThisMonth,
  int? examsPerMonth,
  int totalExams,
  int? maxTotalExams,
});

final planUsageProvider = FutureProvider.autoDispose<PlanUsage>((ref) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/me/entitlements')).payload;
  final j = p is Map ? p : const <String, Object?>{};
  final u = j['usage'] is Map ? j['usage'] as Map : const <String, Object?>{};
  final l = j['limits'] is Map ? j['limits'] as Map : const <String, Object?>{};
  int? limit(Object? v) => v is num && v > 0 ? v.toInt() : null;
  return (
    plan: j['plan'] is Map ? (j['plan'] as Map)['name'] as String? : null,
    examsThisMonth: (u['exams_used_this_month'] as num?)?.toInt() ?? 0,
    examsPerMonth: limit(l['max_exams_per_month']),
    totalExams: (u['total_exams_used'] as num?)?.toInt() ?? 0,
    maxTotalExams: limit(l['max_total_exams']),
  );
}, retry: (retryCount, error) => null);

typedef StorageUsage = ({
  int used,
  int? limit,
  int percent,
  bool warning,
  bool full,
  Map<String, int> byType,
});

final storageUsageProvider = FutureProvider.autoDispose<StorageUsage>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/files/usage')).payload;
  final j = p is Map ? p : const <String, Object?>{};
  return (
    used: (j['used_bytes'] as num?)?.toInt() ?? 0,
    limit: (j['limit_bytes'] as num?)?.toInt(),
    percent: (j['percent'] as num?)?.round() ?? 0,
    warning: j['warning'] == true,
    full: j['full'] == true,
    byType: {
      if (j['by_type'] is Map)
        for (final MapEntry(:key, :value) in (j['by_type'] as Map).entries)
          if (value is num) '$key': value.toInt(),
    },
  );
}, retry: (retryCount, error) => null);

typedef SmsCredits = ({
  int left,
  bool low,
  ({int left, int granted})? allowance,
  int topUp,
});

final smsCreditsProvider = FutureProvider.autoDispose<SmsCredits>((ref) async {
  ref.watch(workspaceKeyProvider);
  final p = (await ref.read(apiClientProvider).get('/sms-credits')).payload;
  final j = p is Map ? p : const <String, Object?>{};
  final a = j['allowance'];
  final t = j['top_up'];
  return (
    left: (j['total_left'] as num?)?.toInt() ?? 0,
    low: j['low'] == true,
    allowance: a is Map
        ? (
            left: (a['left'] as num?)?.toInt() ?? 0,
            granted: (a['granted'] as num?)?.toInt() ?? 0,
          )
        : null,
    topUp: t is Map ? (t['left'] as num?)?.toInt() ?? 0 : 0,
  );
}, retry: (retryCount, error) => null);

/// "1.5 MB" with the language's digits.
String fileSize(int bytes, String language) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final n = i == 0 || v >= 10 ? v.round() : (v * 10).round() / 10;
  return '${OrgTime.number(n, language)} ${units[i]}';
}

/// The web's /billing, view only (CLAUDE.md "Payments": no buying in the
/// app and no buttons or links to buy elsewhere): the plan, tests used
/// against its limits, storage by type and SMS credits.
class PlanUsageScreen extends ConsumerWidget {
  const PlanUsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final plan = ref.watch(planUsageProvider);
    final storage = ref.watch(storageUsageProvider);
    final sms = ref.watch(smsCreditsProvider);
    String usage(int used, int? limit) => limit != null
        ? l10n.billingUsageOf(used, limit)
        : OrgTime.number(used, language);
    Widget fact(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: muted),
          Text(value, key: key, style: text.titleSmall),
        ],
      ),
    );
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(planUsageProvider)
          ..invalidate(storageUsageProvider)
          ..invalidate(smsCreditsProvider);
        await ref
            .read(planUsageProvider.future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.billingTitle, style: text.headlineSmall),
              Text(l10n.billingIntro, style: muted),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const Key('plan-card'),
                child: plan.when(
                  loading: () => const LinearProgressIndicator(),
                  error: (e, _) => ErrorView(
                    title: l10n.billingLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(planUsageProvider),
                  ),
                  data: (p) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.billingCurrentPlan(p.plan ?? l10n.billingFree),
                        style: text.titleMedium,
                      ),
                      fact(
                        l10n.billingExamsThisMonth,
                        usage(p.examsThisMonth, p.examsPerMonth),
                        key: const Key('plan-month'),
                      ),
                      fact(
                        l10n.billingTotalExams,
                        usage(p.totalExams, p.maxTotalExams),
                        key: const Key('plan-total'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const Key('storage-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.storageTitle, style: text.titleMedium),
                    Text(l10n.storageIntro, style: muted),
                    const SizedBox(height: AppSpacing.sm),
                    ...storage.when(
                      loading: () => [const LinearProgressIndicator()],
                      error: (e, _) => [
                        Text(l10n.storageLoadFailed, style: muted),
                      ],
                      data: (s) => [
                        Wrap(
                          spacing: AppSpacing.sm,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              s.limit != null
                                  ? l10n.storageUsed(
                                      fileSize(s.used, language),
                                      fileSize(s.limit!, language),
                                    )
                                  : l10n.storageUsedNoLimit(
                                      fileSize(s.used, language),
                                    ),
                            ),
                            if (s.full || s.warning)
                              StatusPill(
                                label: l10n.storagePercentUsed(s.percent),
                                tone: s.full
                                    ? StatusTone.danger
                                    : StatusTone.warning,
                              ),
                          ],
                        ),
                        if (s.limit != null)
                          Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: LinearProgressIndicator(
                              value: (s.percent / 100).clamp(0, 1).toDouble(),
                              color: s.full
                                  ? colors.danger
                                  : s.warning
                                  ? colors.warning
                                  : colors.primary,
                            ),
                          ),
                        if (s.full || s.warning)
                          Text(
                            s.full ? l10n.storageFull : l10n.storageWarning,
                            key: const Key('storage-warning'),
                            style: text.bodySmall?.copyWith(
                              color: s.full ? colors.danger : colors.warning,
                            ),
                          ),
                        for (final (key, label) in [
                          ('homework', l10n.storageByTypeHomework),
                          ('resources', l10n.storageByTypeResources),
                          ('video', l10n.storageByTypeVideo),
                          ('other', l10n.storageByTypeOther),
                        ])
                          if (s.byType.containsKey(key))
                            fact(label, fileSize(s.byType[key]!, language)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                key: const Key('sms-card'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.smsCreditsTitle, style: text.titleMedium),
                    Text(l10n.smsCreditsIntro, style: muted),
                    ...sms.when(
                      loading: () => [const LinearProgressIndicator()],
                      error: (e, _) => [
                        Text(l10n.smsCreditsLoadFailed, style: muted),
                      ],
                      data: (c) => [
                        const SizedBox(height: AppSpacing.sm),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            Text(
                              l10n.smsCreditsTotalLeft(c.left),
                              style: text.titleSmall,
                            ),
                            if (c.low)
                              StatusPill(
                                label: l10n.smsCreditsLow,
                                tone: StatusTone.warning,
                              ),
                          ],
                        ),
                        fact(
                          l10n.smsCreditsAllowance,
                          c.allowance != null
                              ? l10n.smsCreditsAllowanceLeft(
                                  c.allowance!.left,
                                  c.allowance!.granted,
                                )
                              : l10n.smsCreditsNoAllowance,
                        ),
                        Text(l10n.smsCreditsAllowanceHint, style: muted),
                        fact(
                          l10n.smsCreditsTopUp,
                          l10n.smsCreditsCredits(c.topUp),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton(
                            key: const Key('sms-log'),
                            onPressed: () => context.push('/message-log'),
                            child: Text(l10n.smsCreditsOpenLog),
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
    );
  }
}
