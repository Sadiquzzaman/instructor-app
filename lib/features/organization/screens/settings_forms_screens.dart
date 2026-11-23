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
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';

/// `GET /homework/settings`.
typedef HomeworkSettings = ({
  bool lateAllowed,
  String penalty,
  int percent,
  int resubmissions,
  int maxFiles,
});

HomeworkSettings homeworkSettingsFromJson(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  final p = j['late_penalty'] is Map
      ? j['late_penalty'] as Map
      : const <String, Object?>{};
  return (
    lateAllowed: j['late_allowed'] == true,
    penalty: (p['type'] as String?) ?? 'NONE',
    percent: (p['percent'] as num?)?.toInt() ?? 0,
    resubmissions: (j['resubmissions'] as num?)?.toInt() ?? 0,
    maxFiles: (j['max_files'] as num?)?.toInt() ?? 5,
  );
}

final homeworkSettingsProvider = FutureProvider.autoDispose<HomeworkSettings>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  return homeworkSettingsFromJson(
    (await ref.read(apiClientProvider).get('/homework/settings')).payload,
  );
}, retry: (retryCount, error) => null);

/// The web's /homework-settings (owners and admins; others read): late
/// hand-ins and their penalty, how many changes, how many files.
class HomeworkSettingsScreen extends ConsumerStatefulWidget {
  const HomeworkSettingsScreen({super.key});

  @override
  ConsumerState<HomeworkSettingsScreen> createState() =>
      _HomeworkSettingsScreenState();
}

class _HomeworkSettingsScreenState
    extends ConsumerState<HomeworkSettingsScreen> {
  HomeworkSettings? _draft;
  HomeworkSettings? _saved;
  final _percent = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  void _show(HomeworkSettings s) {
    _saved = s;
    _draft = s;
    _percent.text = s.percent > 0 ? '${s.percent}' : '';
  }

  HomeworkSettings _with({
    bool? lateAllowed,
    String? penalty,
    int? resubmissions,
    int? maxFiles,
  }) {
    final d = _draft!;
    return (
      lateAllowed: lateAllowed ?? d.lateAllowed,
      penalty: penalty ?? d.penalty,
      percent: d.percent,
      resubmissions: resubmissions ?? d.resubmissions,
      maxFiles: maxFiles ?? d.maxFiles,
    );
  }

  int? get _percentValue {
    final n = int.tryParse(_percent.text.trim());
    return n != null && n >= 1 && n <= 100 ? n : null;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final d = _draft!;
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .patch(
            '/homework/settings',
            data: {
              'late_allowed': d.lateAllowed,
              'late_penalty': {
                'type': d.penalty,
                'percent': d.penalty == 'NONE' ? 0 : _percentValue,
              },
              'resubmissions': d.resubmissions,
              'max_files': d.maxFiles,
            },
          );
      if (!mounted) return;
      setState(() => _show(homeworkSettingsFromJson(r.payload)));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.homeworkSettingsSavedTitle)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final canEdit = sessionRights(ref.watch(sessionProvider)).manage;
    final loaded = ref.watch(homeworkSettingsProvider);
    if (_saved == null && loaded.value != null) _show(loaded.value!);
    final d = _draft;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final penaltyInvalid =
        d != null && d.penalty != 'NONE' && _percentValue == null;
    final changed =
        d != null &&
        (d != _saved ||
            (d.penalty != 'NONE' && _percentValue != _saved!.percent));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.homeworkSettingsTitle, style: text.headlineSmall),
            Text(
              canEdit
                  ? l10n.homeworkSettingsIntro
                  : l10n.homeworkSettingsReadOnly,
              style: muted,
            ),
            const SizedBox(height: AppSpacing.md),
            if (d == null)
              loaded.hasError
                  ? SizedBox(
                      height: 280,
                      child: ErrorView(
                        title: l10n.homeworkSettingsLoadFailed,
                        retryLabel: l10n.uiErrorRetry,
                        onRetry: () => ref.invalidate(homeworkSettingsProvider),
                      ),
                    )
                  : const LinearProgressIndicator()
            else
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      key: const Key('hw-late'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: d.lateAllowed,
                      title: Text(l10n.homeworkSettingsLateAllowed),
                      subtitle: Text(l10n.homeworkSettingsLateAllowedHint),
                      onChanged: canEdit
                          ? (v) => setState(
                              () => _draft = _with(lateAllowed: v == true),
                            )
                          : null,
                    ),
                    if (d.lateAllowed) ...[
                      DropdownButtonFormField<String>(
                        key: const Key('hw-penalty'),
                        initialValue: d.penalty,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n.homeworkSettingsPenalty,
                        ),
                        items: [
                          for (final (v, label) in [
                            ('NONE', l10n.homeworkSettingsPenaltiesNONE),
                            ('PER_DAY', l10n.homeworkSettingsPenaltiesPERDAY),
                            ('FIXED', l10n.homeworkSettingsPenaltiesFIXED),
                          ])
                            DropdownMenuItem(value: v, child: Text(label)),
                        ],
                        onChanged: canEdit
                            ? (v) => setState(() {
                                _draft = _with(penalty: v);
                                if (v != 'NONE' && _percent.text.isEmpty) {
                                  _percent.text = '1';
                                }
                              })
                            : null,
                      ),
                      if (d.penalty != 'NONE')
                        TextField(
                          key: const Key('hw-percent'),
                          controller: _percent,
                          enabled: canEdit,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.homeworkSettingsPercent,
                            suffixText: '%',
                            errorText: penaltyInvalid
                                ? l10n.homeworkSettingsPercentInvalid
                                : null,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<int>(
                      key: const Key('hw-resubmissions'),
                      initialValue: d.resubmissions,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.homeworkSettingsResubmissions,
                        helperText: l10n.homeworkSettingsResubmissionsHint,
                        helperMaxLines: 3,
                      ),
                      items: [
                        for (final n in {0, 1, 2, 3, d.resubmissions})
                          DropdownMenuItem(
                            value: n,
                            child: Text(
                              n == 0
                                  ? l10n.homeworkSettingsNoResubmission
                                  : OrgTime.number(n, language),
                            ),
                          ),
                      ],
                      onChanged: canEdit
                          ? (v) =>
                                setState(() => _draft = _with(resubmissions: v))
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<int>(
                      key: const Key('hw-files'),
                      initialValue: d.maxFiles,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.homeworkSettingsMaxFiles,
                        helperText: l10n.homeworkSettingsMaxFilesHint,
                        helperMaxLines: 3,
                      ),
                      items: [
                        for (final n in {
                          for (var i = 1; i <= 10; i++) i,
                          d.maxFiles,
                        })
                          DropdownMenuItem(
                            value: n,
                            child: Text(OrgTime.number(n, language)),
                          ),
                      ],
                      onChanged: canEdit
                          ? (v) => setState(() => _draft = _with(maxFiles: v))
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.homeworkSettingsSummary(d.resubmissions, d.maxFiles),
                      key: const Key('hw-summary'),
                    ),
                    if (canEdit) ...[
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.sm,
                        children: [
                          TextButton(
                            onPressed: changed && !_saving
                                ? () => setState(() => _show(_saved!))
                                : null,
                            child: Text(l10n.homeworkSettingsUndo),
                          ),
                          FilledButton(
                            key: const Key('hw-save'),
                            onPressed: changed && !_saving && !penaltyInvalid
                                ? _save
                                : null,
                            child: Text(l10n.homeworkSettingsSave),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// `GET /integrity/settings`.
typedef PlagiarismThresholds = ({int high, int medium, int minWords});

final plagiarismSettingsProvider =
    FutureProvider.autoDispose<PlagiarismThresholds>((ref) async {
      ref.watch(workspaceKeyProvider);
      final p = (await ref.read(apiClientProvider).get('/integrity/settings'))
          .payload;
      final j = p is Map ? p : const <String, Object?>{};
      return (
        high: (j['high'] as num?)?.toInt() ?? 70,
        medium: (j['medium'] as num?)?.toInt() ?? 40,
        minWords: (j['min_words'] as num?)?.toInt() ?? 50,
      );
    }, retry: (retryCount, error) => null);

/// The web's /plagiarism-settings: from what similarity a match counts as
/// high or medium, and how many words a hand-in needs to be checked.
class PlagiarismSettingsScreen extends ConsumerStatefulWidget {
  const PlagiarismSettingsScreen({super.key});

  @override
  ConsumerState<PlagiarismSettingsScreen> createState() =>
      _PlagiarismSettingsScreenState();
}

class _PlagiarismSettingsScreenState
    extends ConsumerState<PlagiarismSettingsScreen> {
  final _high = TextEditingController();
  final _medium = TextEditingController();
  final _minWords = TextEditingController();
  bool _filled = false;
  bool _saving = false;

  @override
  void dispose() {
    _high.dispose();
    _medium.dispose();
    _minWords.dispose();
    super.dispose();
  }

  int? _whole(TextEditingController c, int min, int max) {
    final n = int.tryParse(c.text.trim());
    return n != null && n >= min && n <= max ? n : null;
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .put(
            '/integrity/settings',
            data: {
              'high': _whole(_high, 1, 100),
              'medium': _whole(_medium, 1, 99),
              'min_words': _whole(_minWords, 0, 1000),
            },
          );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.plagiarismSettingsSaved)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final loaded = ref.watch(plagiarismSettingsProvider);
    final v = loaded.value;
    if (!_filled && v != null) {
      _filled = true;
      _high.text = '${v.high}';
      _medium.text = '${v.medium}';
      _minWords.text = '${v.minWords}';
    }
    final valid =
        _whole(_high, 1, 100) != null &&
        _whole(_medium, 1, 99) != null &&
        _whole(_minWords, 0, 1000) != null;
    Widget field(String key, TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        key: Key(key),
        controller: c,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.plagiarismSettingsTitle, style: text.headlineSmall),
            Text(
              l10n.plagiarismSettingsDescription,
              style: text.bodySmall?.copyWith(
                color: AppColors.of(context).inkMuted,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (v == null)
              loaded.hasError
                  ? SizedBox(
                      height: 280,
                      child: ErrorView(
                        title:
                            loaded.error is ApiException &&
                                (loaded.error! as ApiException).statusCode ==
                                    403
                            ? l10n.plagiarismNotAvailable
                            : l10n.plagiarismLoadFailed,
                        retryLabel: l10n.uiErrorRetry,
                        onRetry: () =>
                            ref.invalidate(plagiarismSettingsProvider),
                      ),
                    )
                  : const LinearProgressIndicator()
            else
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    field('pl-high', _high, l10n.plagiarismHighFrom),
                    field('pl-medium', _medium, l10n.plagiarismMediumFrom),
                    field('pl-words', _minWords, l10n.plagiarismMinWords),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: FilledButton(
                        key: const Key('pl-save'),
                        onPressed: valid && !_saving ? _save : null,
                        child: Text(l10n.plagiarismSave),
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
