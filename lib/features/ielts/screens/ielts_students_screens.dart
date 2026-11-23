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
import 'package:instructor_app/core/widgets/date_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/data/profiles.dart';
import 'package:instructor_app/features/ielts/screens/ielts_overview_screen.dart';

String _type(AppLocalizations l10n, String? t) => switch (t) {
  'ACADEMIC' => l10n.ieltsTypesACADEMIC,
  'GENERAL' => l10n.ieltsTypesGENERAL,
  _ => '—',
};

String ieltsModuleName(AppLocalizations l10n, String m) => switch (m) {
  'LISTENING' => l10n.ieltsModulesLISTENING,
  'READING' => l10n.ieltsModulesREADING,
  'WRITING' => l10n.ieltsModulesWRITING,
  _ => l10n.ieltsModulesSPEAKING,
};

String _date(String? d, String lang) =>
    d == null || d.isEmpty ? '—' : OrgTime.schoolDay(d, lang);

/// The centre's batches, named "course batch" as the web does.
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

/// The web's /ielts/students (P10-01): every student of the centre, or one
/// batch's, with test type, targets and the test date; staff set them.
class IeltsStudentsScreen extends ConsumerStatefulWidget {
  const IeltsStudentsScreen({super.key});

  @override
  ConsumerState<IeltsStudentsScreen> createState() =>
      _IeltsStudentsScreenState();
}

class _IeltsStudentsScreenState extends ConsumerState<IeltsStudentsScreen> {
  String? _batch;

  Future<void> _edit(IeltsProfile p) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ProfileForm(profile: p),
    );
    if (saved == true) ref.invalidate(ieltsProfilesProvider(_batch));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final batches = ref.watch(_batchesProvider).value ?? const [];
    final rows = ref.watch(ieltsProfilesProvider(_batch));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: RefreshIndicator(
          onRefresh: () => ref.refresh(ieltsProfilesProvider(_batch).future),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.ieltsStudentsTitle, style: text.headlineSmall),
              Text(l10n.ieltsStudentsDescription, style: muted),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String?>(
                key: const Key('ielts-batch'),
                initialValue: _batch,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.ieltsBatch),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.ieltsAllBatches),
                  ),
                  for (final b in batches)
                    DropdownMenuItem(value: b.id, child: Text(b.label)),
                ],
                onChanged: (v) => setState(() => _batch = v),
              ),
              const SizedBox(height: AppSpacing.md),
              ...rows.when(
                loading: () => [
                  SizedBox(
                    height: 160,
                    child: LoadingView(semanticsLabel: l10n.ieltsStudentsTitle),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 260,
                    child: ErrorView(
                      title: e is ApiException && e.statusCode == 403
                          ? l10n.ieltsNotAvailable
                          : l10n.ieltsLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () =>
                          ref.invalidate(ieltsProfilesProvider(_batch)),
                    ),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [
                        EmptyView(
                          icon: Icons.people_outline,
                          title: l10n.ieltsNoStudents,
                        ),
                      ]
                    : [
                        for (final p in list)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.sm,
                            ),
                            child: AppCard(
                              key: Key('ielts-student-${p.studentId}'),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(p.name, style: text.titleSmall),
                                        Text(
                                          '${p.batch ?? '—'} · ${_type(l10n, p.testType)}',
                                          style: muted,
                                        ),
                                        Text(
                                          '${l10n.ieltsTargetOverall}: '
                                          '${bandText(p.targetOverall, lang)}',
                                          style: text.bodySmall,
                                        ),
                                        Text(
                                          '${l10n.ieltsTargetsByModule}: '
                                          '${ieltsModules.map((m) => bandText(p.targets[m], lang)).join(' / ')}',
                                          style: text.bodySmall,
                                        ),
                                        Text(
                                          '${l10n.ieltsTestDate}: '
                                          '${_date(p.testDate, lang)}'
                                          '${p.daysToTest != null && p.daysToTest! >= 0 && p.testDate != null ? ' · ${l10n.ieltsDaysLeft(p.daysToTest!)}' : ''}',
                                          style: text.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    key: Key('ielts-progress-${p.studentId}'),
                                    onPressed: () => context.push(
                                      '/ielts/progress/${p.studentId}',
                                    ),
                                    child: Text(
                                      l10n.ieltsProgress,
                                      semanticsLabel: l10n.ieltsProgressFor(
                                        p.name,
                                      ),
                                    ),
                                  ),
                                  OutlinedButton(
                                    key: Key('ielts-edit-${p.studentId}'),
                                    onPressed: () => _edit(p),
                                    child: Text(
                                      l10n.ieltsEdit,
                                      semanticsLabel: l10n.ieltsEditFor(p.name),
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

/// Test type, target overall and per module, and the booked test date.
class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final IeltsProfile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
  late String? _type = widget.profile.testType;
  late num? _overall = widget.profile.targetOverall;
  late final _targets = <String, num?>{...widget.profile.targets};
  late String? _date = widget.profile.testDate;
  bool _saving = false;

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/ielts/profiles/${widget.profile.studentId}',
            data: profileBody(
              testType: _type,
              targetOverall: _overall,
              targets: _targets,
              testDate: _date,
            ),
          );
      messenger.showSnackBar(SnackBar(content: Text(l10n.ieltsSaved)));
      nav.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    Widget band(Key key, String label, num? value, ValueChanged<num?> set) =>
        DropdownButtonFormField<num?>(
          key: key,
          initialValue: ieltsBands.contains(value) ? value : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            DropdownMenuItem(value: null, child: Text(l10n.ieltsNoTarget)),
            for (final b in ieltsBands)
              DropdownMenuItem(value: b, child: Text(bandText(b, lang))),
          ],
          onChanged: set,
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
              Text(widget.profile.name, style: text.titleLarge),
              Text(l10n.ieltsProfileDescription, style: text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.ieltsTestType, style: text.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              SegmentedButton<String?>(
                key: const Key('ielts-type'),
                emptySelectionAllowed: true,
                segments: [
                  ButtonSegment(
                    value: 'ACADEMIC',
                    label: Text(l10n.ieltsTypesACADEMIC),
                  ),
                  ButtonSegment(
                    value: 'GENERAL',
                    label: Text(l10n.ieltsTypesGENERAL),
                  ),
                ],
                selected: {?_type},
                onSelectionChanged: (s) =>
                    setState(() => _type = s.isEmpty ? null : s.first),
              ),
              const SizedBox(height: AppSpacing.sm),
              band(
                const Key('ielts-overall'),
                l10n.ieltsTargetOverall,
                _overall,
                (v) => setState(() => _overall = v),
              ),
              for (final m in ieltsModules)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: band(
                    Key('ielts-target-$m'),
                    ieltsModuleName(l10n, m),
                    _targets[m],
                    (v) => setState(() => _targets[m] = v),
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              DateField(
                key: const Key('ielts-date'),
                label: l10n.ieltsTestDate,
                value: _date,
                onChanged: (v) => setState(() => _date = v),
              ),
              Text(l10n.ieltsTestDateHint, style: text.bodySmall),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.ieltsCancel),
                  ),
                  FilledButton(
                    key: const Key('ielts-profile-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(l10n.ieltsSave),
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

/// The web's /ielts/me: a student's own targets and the countdown.
class MyIeltsProfileScreen extends ConsumerWidget {
  const MyIeltsProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ref
            .watch(myIeltsProfileProvider)
            .when(
              loading: () => LoadingView(semanticsLabel: l10n.ieltsMyTitle),
              error: (e, _) => ErrorView(
                title: e is ApiException && e.statusCode == 403
                    ? l10n.ieltsNotAvailable
                    : l10n.ieltsLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(myIeltsProfileProvider),
              ),
              data: (p) {
                final empty =
                    p == null ||
                    (p.testType == null &&
                        p.targetOverall == null &&
                        p.testDate == null);
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(myIeltsProfileProvider.future),
                  child: ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      Text(l10n.ieltsMyTitle, style: text.headlineSmall),
                      if (p?.testType != null)
                        Text(_type(l10n, p!.testType), style: muted),
                      const SizedBox(height: AppSpacing.md),
                      if (empty)
                        EmptyView(
                          key: const Key('ielts-no-profile'),
                          icon: Icons.flag_outlined,
                          title: l10n.ieltsNoProfile,
                          message: l10n.ieltsNoProfileHint,
                        )
                      else ...[
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            IeltsStat(
                              l10n.ieltsTargetOverall,
                              bandText(p.targetOverall, lang),
                            ),
                            IeltsStat(
                              l10n.ieltsTestDate,
                              _date(p.testDate, lang),
                            ),
                            if (p.daysToTest != null && p.daysToTest! >= 0)
                              IeltsStat(
                                l10n.ieltsDaysToTest,
                                l10n.ieltsDaysLeft(p.daysToTest!),
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                l10n.ieltsModuleTargets,
                                style: text.titleSmall,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: AppSpacing.lg,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  for (final m in ieltsModules)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ieltsModuleName(l10n, m),
                                          style: muted,
                                        ),
                                        Text(
                                          bandText(p.targets[m], lang),
                                          style: text.titleMedium,
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }
}
