import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';

const scoreParts = [
  'exams_pct',
  'homework_pct',
  'attendance_pct',
  'behaviour_pct',
];

typedef ClassWeights = ({
  String classId,
  String className,
  Map<String, int> weights,
  bool isDefault,
});

typedef SessionWeights = ({
  String sessionId,
  String sessionName,
  bool closed,
  List<ClassWeights> classes,
});

SessionWeights weightsFromJson(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  final s = j['session'] is Map
      ? j['session'] as Map
      : const <String, Object?>{};
  return (
    sessionId: (s['id'] as String?) ?? '',
    sessionName: (s['name'] as String?) ?? '',
    closed: s['closed'] == true,
    classes: [
      if (j['classes'] is List)
        for (final r in j['classes'] as List)
          if (r is Map && r['class'] is Map)
            (
              classId: ((r['class'] as Map)['id'] as String?) ?? '',
              className: ((r['class'] as Map)['name'] as String?) ?? '',
              weights: {
                for (final p in scoreParts)
                  p:
                      ((r['weights'] is Map ? (r['weights'] as Map)[p] : null)
                              as num?)
                          ?.toInt() ??
                      0,
              },
              isDefault: r['is_default'] == true,
            ),
    ],
  );
}

/// [sessionId] '' is the default session.
final weightsProvider = FutureProvider.autoDispose
    .family<SessionWeights, String>((ref, sessionId) async {
      ref.watch(workspaceKeyProvider);
      return weightsFromJson(
        (await ref
                .read(apiClientProvider)
                .get(
                  '/scores/weights',
                  query: {'session_id': sessionId.isEmpty ? null : sessionId},
                ))
            .payload,
      );
    }, retry: (retryCount, error) => null);

typedef PerformanceRules = ({
  int scoreBelow,
  int attendanceBelow,
  int missingHomework,
  bool showRank,
});

PerformanceRules rulesFromJson(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  final a = j['at_risk'] is Map
      ? j['at_risk'] as Map
      : const <String, Object?>{};
  return (
    scoreBelow: (a['score_pct'] as num?)?.toInt() ?? 40,
    attendanceBelow: (a['attendance_pct'] as num?)?.toInt() ?? 75,
    missingHomework: (a['missing_homework'] as num?)?.toInt() ?? 3,
    showRank: j['show_rank'] == true,
  );
}

final performanceRulesProvider = FutureProvider.autoDispose<PerformanceRules>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  return rulesFromJson(
    (await ref.read(apiClientProvider).get('/scores/settings')).payload,
  );
}, retry: (retryCount, error) => null);

/// The web's /performance-settings (Academic): how much exams, homework,
/// attendance and behaviour count in each class's score for a session
/// (adding up to 100), when a student is at risk, and whether students see
/// their position. Owners and admins change them; others read.
class PerformanceSettingsScreen extends ConsumerStatefulWidget {
  const PerformanceSettingsScreen({super.key});

  @override
  ConsumerState<PerformanceSettingsScreen> createState() =>
      _PerformanceSettingsScreenState();
}

class _PerformanceSettingsScreenState
    extends ConsumerState<PerformanceSettingsScreen> {
  String _session = '';
  final _drafts = <String, Map<String, TextEditingController>>{};
  String? _savingClass;
  PerformanceRules? _rules;
  PerformanceRules? _savedRules;
  final _score = TextEditingController();
  final _attendance = TextEditingController();
  final _missing = TextEditingController();
  bool _savingRules = false;

  @override
  void dispose() {
    for (final m in _drafts.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _score.dispose();
    _attendance.dispose();
    _missing.dispose();
    super.dispose();
  }

  void _fill(SessionWeights w) {
    for (final r in w.classes) {
      final d = _drafts.putIfAbsent(
        r.classId,
        () => {for (final p in scoreParts) p: TextEditingController()},
      );
      for (final p in scoreParts) {
        d[p]!.text = '${r.weights[p]}';
      }
    }
  }

  void _showRules(PerformanceRules r) {
    _rules = r;
    _savedRules = r;
    _score.text = '${r.scoreBelow}';
    _attendance.text = '${r.attendanceBelow}';
    _missing.text = '${r.missingHomework}';
  }

  int _sum(String classId) => scoreParts.fold(
    0,
    (s, p) => s + (int.tryParse(_drafts[classId]![p]!.text.trim()) ?? 0),
  );

  bool _valid(String classId) =>
      scoreParts.every((p) {
        final v = _drafts[classId]![p]!.text.trim();
        return RegExp(r'^\d{1,3}$').hasMatch(v) && int.parse(v) <= 100;
      }) &&
      _sum(classId) == 100;

  Future<void> _saveWeights(SessionWeights w, ClassWeights row) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingClass = row.classId);
    try {
      final r = await ref
          .read(apiClientProvider)
          .put(
            '/scores/weights',
            data: {
              'session_id': w.sessionId,
              'class_id': row.classId,
              for (final p in scoreParts)
                p: int.parse(_drafts[row.classId]![p]!.text.trim()),
            },
          );
      if (!mounted) return;
      final next = weightsFromJson(r.payload);
      setState(() => _fill(next));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.performanceSettingsWeightsSaved)),
      );
      ref.invalidate(weightsProvider(_session));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _savingClass = null);
    }
  }

  int? _whole(TextEditingController c, int min, int max) {
    final n = int.tryParse(c.text.trim());
    return n != null && n >= min && n <= max ? n : null;
  }

  Future<void> _saveRules() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingRules = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .put(
            '/scores/settings',
            data: {
              'at_risk': {
                'score_pct': _whole(_score, 0, 100),
                'attendance_pct': _whole(_attendance, 0, 100),
                'missing_homework': _whole(_missing, 1, 50),
              },
              'show_rank': _rules!.showRank,
            },
          );
      if (!mounted) return;
      setState(() => _showRules(rulesFromJson(r.payload)));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.performanceSettingsSettingsSaved)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _savingRules = false);
    }
  }

  String _partName(String p) {
    final l10n = context.l10n;
    return switch (p) {
      'exams_pct' => l10n.performanceSettingsPartsExamsPct,
      'homework_pct' => l10n.performanceSettingsPartsHomeworkPct,
      'attendance_pct' => l10n.performanceSettingsPartsAttendancePct,
      _ => l10n.performanceSettingsPartsBehaviourPct,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final canEdit = sessionRights(ref.watch(sessionProvider)).manage;
    final weights = ref.watch(weightsProvider(_session));
    final sessions = canEdit ? ref.watch(sessionsProvider).value : null;
    final rules = ref.watch(performanceRulesProvider);
    if (_savedRules == null && rules.value != null) _showRules(rules.value!);
    final w = weights.value;
    if (w != null) {
      for (final r in w.classes) {
        if (!_drafts.containsKey(r.classId)) _fill(w);
      }
    }
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final editable = canEdit && w != null && !w.closed;
    final rulesValid =
        _whole(_score, 0, 100) != null &&
        _whole(_attendance, 0, 100) != null &&
        _whole(_missing, 1, 50) != null;
    final rulesChanged =
        _rules != null &&
        (_rules != _savedRules ||
            _score.text.trim() != '${_savedRules!.scoreBelow}' ||
            _attendance.text.trim() != '${_savedRules!.attendanceBelow}' ||
            _missing.text.trim() != '${_savedRules!.missingHomework}');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.performanceSettingsTitle, style: text.headlineSmall),
            Text(
              ref.levels(
                context,
                canEdit
                    ? l10n.performanceSettingsIntro
                    : l10n.performanceSettingsReadOnly,
              ),
              style: muted,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(l10n.performanceSettingsWeightsTitle, style: text.titleMedium),
            Text(
              ref.levels(context, l10n.performanceSettingsWeightsIntro),
              style: muted,
            ),
            if (sessions != null && sessions.length > 1)
              DropdownButtonFormField<String>(
                key: const Key('perf-session'),
                initialValue: _session.isEmpty ? w?.sessionId : _session,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.performanceSettingsSession,
                ),
                items: [
                  for (final s in sessions)
                    DropdownMenuItem(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) => setState(() {
                  _session = v ?? '';
                  _drafts.clear();
                }),
              ),
            const SizedBox(height: AppSpacing.sm),
            if (w == null)
              weights.hasError
                  ? SizedBox(
                      height: 240,
                      child: ErrorView(
                        title: l10n.performanceSettingsLoadFailed,
                        retryLabel: l10n.uiErrorRetry,
                        onRetry: () =>
                            ref.invalidate(weightsProvider(_session)),
                      ),
                    )
                  : const LinearProgressIndicator()
            else if (w.classes.isEmpty)
              SizedBox(
                height: 200,
                child: EmptyView(
                  icon: Icons.class_outlined,
                  title: ref.levels(context, l10n.performanceSettingsNoClasses),
                  message: ref.levels(
                    context,
                    l10n.performanceSettingsNoClassesHint,
                  ),
                ),
              )
            else ...[
              if (w.closed)
                Text(
                  l10n.performanceSettingsSessionClosed,
                  key: const Key('perf-closed'),
                  style: muted,
                ),
              for (final row in w.classes) ...[
                const SizedBox(height: AppSpacing.sm),
                AppCard(
                  key: Key('weights-${row.classId}'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(row.className, style: text.titleSmall),
                          if (row.isDefault)
                            StatusPill(
                              label: l10n.performanceSettingsDefault,
                              tone: StatusTone.neutral,
                            ),
                        ],
                      ),
                      Wrap(
                        spacing: AppSpacing.sm,
                        children: [
                          for (final p in scoreParts)
                            SizedBox(
                              width: 140,
                              child: TextField(
                                key: Key('w-${row.classId}-$p'),
                                controller: _drafts[row.classId]![p],
                                enabled: editable,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: _partName(p),
                                  suffixText: '%',
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l10n.performanceSettingsTotal}: '
                              '${OrgTime.number(_sum(row.classId), language)}%',
                              key: Key('total-${row.classId}'),
                              style: _sum(row.classId) == 100
                                  ? text.bodyMedium
                                  : text.bodyMedium?.copyWith(
                                      color: colors.danger,
                                    ),
                            ),
                          ),
                          if (editable)
                            FilledButton(
                              key: Key('w-save-${row.classId}'),
                              onPressed:
                                  _savingClass == null &&
                                      _valid(row.classId) &&
                                      scoreParts.any(
                                        (p) =>
                                            _drafts[row.classId]![p]!.text
                                                .trim() !=
                                            '${row.weights[p]}',
                                      )
                                  ? () => _saveWeights(w, row)
                                  : null,
                              child: Text(l10n.performanceSettingsSave),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                w.classes.any((r) => _sum(r.classId) != 100)
                    ? l10n.performanceSettingsMustAddUp
                    : l10n.performanceSettingsWeightsHint,
                style: muted,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            if (_rules != null)
              AppCard(
                key: const Key('perf-rules'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.performanceSettingsAtRiskTitle,
                      style: text.titleMedium,
                    ),
                    Text(l10n.performanceSettingsAtRiskIntro, style: muted),
                    for (final (key, c, label) in [
                      (
                        'risk-score',
                        _score,
                        l10n.performanceSettingsScoreBelow,
                      ),
                      (
                        'risk-attendance',
                        _attendance,
                        l10n.performanceSettingsAttendanceBelow,
                      ),
                      (
                        'risk-missing',
                        _missing,
                        l10n.performanceSettingsMissingHomework,
                      ),
                    ])
                      TextField(
                        key: Key(key),
                        controller: c,
                        enabled: canEdit,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: label),
                        onChanged: (_) => setState(() {}),
                      ),
                    if (!rulesValid)
                      Text(
                        l10n.performanceSettingsLimitsInvalid,
                        style: text.bodySmall?.copyWith(color: colors.danger),
                      ),
                    CheckboxListTile(
                      key: const Key('show-rank'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _rules!.showRank,
                      title: Text(l10n.performanceSettingsShowRank),
                      subtitle: Text(
                        ref.levels(
                          context,
                          l10n.performanceSettingsShowRankHint,
                        ),
                      ),
                      onChanged: canEdit
                          ? (v) => setState(
                              () => _rules = (
                                scoreBelow: _rules!.scoreBelow,
                                attendanceBelow: _rules!.attendanceBelow,
                                missingHomework: _rules!.missingHomework,
                                showRank: v == true,
                              ),
                            )
                          : null,
                    ),
                    if (canEdit)
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.sm,
                        children: [
                          TextButton(
                            onPressed: rulesChanged && !_savingRules
                                ? () => setState(() => _showRules(_savedRules!))
                                : null,
                            child: Text(l10n.performanceSettingsUndo),
                          ),
                          FilledButton(
                            key: const Key('rules-save'),
                            onPressed:
                                rulesChanged && rulesValid && !_savingRules
                                ? _saveRules
                                : null,
                            child: Text(l10n.performanceSettingsSaveSettings),
                          ),
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

typedef GradeBand = ({double min, double max, String grade, double? gpa});

/// The first problem with the bands and its row (0-based), or null — the
/// web's `validateGradeBands`, the same as the API's.
({String code, int? band})? validateGradeBands(List<GradeBand> bands) {
  int h(double v) => (v * 100).round();
  bool two(double v) => (v * 100 - h(v)).abs() < 1e-6;
  if (bands.isEmpty) return (code: 'GRADING_SCALE_EMPTY', band: null);
  if (bands.length > 20) {
    return (code: 'GRADING_SCALE_TOO_MANY_BANDS', band: null);
  }
  for (final (i, b) in bands.indexed) {
    final g = b.grade.trim();
    final numbersOk = [
      b.min,
      b.max,
    ].every((v) => v.isFinite && v >= 0 && v <= 100 && two(v));
    final gpaOk =
        b.gpa == null ||
        (b.gpa!.isFinite && b.gpa! >= 0 && b.gpa! <= 9.99 && two(b.gpa!));
    if (g.isEmpty || g.length > 5 || !numbersOk || !gpaOk || b.min > b.max) {
      return (code: 'GRADING_SCALE_BAND_INVALID', band: i);
    }
  }
  final seen = <String>{};
  for (final (i, b) in bands.indexed) {
    if (!seen.add(b.grade.trim().toLowerCase())) {
      return (code: 'GRADING_SCALE_DUPLICATE_GRADE', band: i);
    }
  }
  final order = [...bands.indexed]
    ..sort((a, b) => a.$2.min.compareTo(b.$2.min));
  if (h(order.first.$2.min) != 0) {
    return (code: 'GRADING_SCALE_MUST_START_AT_0', band: order.first.$1);
  }
  if (h(order.last.$2.max) != 10000) {
    return (code: 'GRADING_SCALE_MUST_END_AT_100', band: order.last.$1);
  }
  for (var i = 1; i < order.length; i++) {
    if (h(order[i].$2.min) != h(order[i - 1].$2.max) + 1) {
      return (code: 'GRADING_SCALE_GAP_OR_OVERLAP', band: order[i].$1);
    }
  }
  return null;
}

typedef GradingScale = ({String name, bool custom, List<GradeBand> bands});

GradingScale scaleFromJson(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  double n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  return (
    name: (j['name'] as String?) ?? '',
    custom: j['is_custom'] == true,
    bands: [
      if (j['bands'] is List)
        for (final b in j['bands'] as List)
          if (b is Map)
            (
              min: n(b['min_pct']),
              max: n(b['max_pct']),
              grade: (b['grade'] as String?) ?? '',
              gpa: b['gpa'] == null ? null : n(b['gpa']),
            ),
    ],
  );
}

final gradingScaleProvider = FutureProvider.autoDispose<GradingScale>((
  ref,
) async {
  ref.watch(workspaceKeyProvider);
  return scaleFromJson(
    (await ref.read(apiClientProvider).get('/grading-scale')).payload,
  );
}, retry: (retryCount, error) => null);

/// The web's /grading-scale: percentage bands → grade and GPA, used on
/// every mark. Owners and admins edit the bands (checked as the API checks
/// them) or go back to the national default (asked first); others read.
class GradingScaleScreen extends ConsumerStatefulWidget {
  const GradingScaleScreen({super.key});

  @override
  ConsumerState<GradingScaleScreen> createState() => _GradingScaleScreenState();
}

class _Row {
  _Row(GradeBand? b)
    : min = TextEditingController(text: b == null ? '' : _fmt(b.min)),
      max = TextEditingController(text: b == null ? '' : _fmt(b.max)),
      grade = TextEditingController(text: b?.grade ?? ''),
      gpa = TextEditingController(text: b?.gpa == null ? '' : _fmt(b!.gpa!));

  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController grade;
  final TextEditingController gpa;

  static String _fmt(double v) =>
      v == v.roundToDouble() ? '${v.toInt()}' : '$v';

  GradeBand get band => (
    min: double.tryParse(min.text.trim()) ?? double.nan,
    max: double.tryParse(max.text.trim()) ?? double.nan,
    grade: grade.text,
    gpa: gpa.text.trim().isEmpty
        ? null
        : double.tryParse(gpa.text.trim()) ?? double.nan,
  );

  void dispose() {
    min.dispose();
    max.dispose();
    grade.dispose();
    gpa.dispose();
  }
}

class _GradingScaleScreenState extends ConsumerState<GradingScaleScreen> {
  List<_Row>? _rows;
  final _name = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    for (final r in _rows ?? const <_Row>[]) {
      r.dispose();
    }
    _name.dispose();
    super.dispose();
  }

  void _show(GradingScale s) {
    for (final r in _rows ?? const <_Row>[]) {
      r.dispose();
    }
    _rows = [for (final b in s.bands) _Row(b)];
    _name.text = s.custom ? s.name : '';
  }

  String _problemText(({String code, int? band}) p) {
    final l10n = context.l10n;
    final row = (p.band ?? 0) + 1;
    return switch (p.code) {
      'GRADING_SCALE_EMPTY' => l10n.gradingScaleErrorsGRADINGSCALEEMPTY,
      'GRADING_SCALE_TOO_MANY_BANDS' =>
        l10n.gradingScaleErrorsGRADINGSCALETOOMANYBANDS,
      'GRADING_SCALE_MUST_START_AT_0' =>
        l10n.gradingScaleErrorsGRADINGSCALEMUSTSTARTAT0(row),
      'GRADING_SCALE_MUST_END_AT_100' =>
        l10n.gradingScaleErrorsGRADINGSCALEMUSTENDAT100(row),
      'GRADING_SCALE_GAP_OR_OVERLAP' =>
        l10n.gradingScaleErrorsGRADINGSCALEGAPOROVERLAP(row),
      'GRADING_SCALE_DUPLICATE_GRADE' =>
        l10n.gradingScaleErrorsGRADINGSCALEDUPLICATEGRADE(row),
      _ => l10n.gradingScaleErrorsGRADINGSCALEBANDINVALID(row),
    };
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final bands = [for (final r in _rows!) r.band];
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .put(
            '/grading-scale',
            data: {
              if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
              'bands': [
                for (final b in bands)
                  {
                    'min_pct': b.min,
                    'max_pct': b.max,
                    'grade': b.grade.trim(),
                    'gpa': b.gpa,
                  },
              ],
            },
          );
      if (!mounted) return;
      setState(() => _show(scaleFromJson(r.payload)));
      messenger.showSnackBar(SnackBar(content: Text(l10n.gradingScaleSaved)));
      ref.invalidate(gradingScaleProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reset() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.gradingScaleResetTitle),
        content: Text(l10n.gradingScaleResetDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.uiCancel),
          ),
          FilledButton(
            key: const Key('scale-reset-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.gradingScaleReset),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      final r = await ref.read(apiClientProvider).delete('/grading-scale');
      if (!mounted) return;
      setState(() => _show(scaleFromJson(r.payload)));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.gradingScaleResetDone)),
      );
      ref.invalidate(gradingScaleProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final canEdit = sessionRights(ref.watch(sessionProvider)).manage;
    final scale = ref.watch(gradingScaleProvider);
    final s = scale.value;
    if (_rows == null && s != null) _show(s);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final rows = _rows;
    final problem = rows == null
        ? null
        : validateGradeBands([for (final r in rows) r.band]);
    String pct(double v) =>
        '${OrgTime.number(v == v.roundToDouble() ? v.toInt() : v, language)}%';
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(l10n.gradingScaleTitle, style: text.headlineSmall),
                if (s != null)
                  StatusPill(
                    label: s.custom ? s.name : l10n.gradingScaleDefaultName,
                    tone: s.custom ? StatusTone.primary : StatusTone.neutral,
                  ),
              ],
            ),
            Text(l10n.gradingScaleIntro, style: muted),
            const SizedBox(height: AppSpacing.md),
            if (s == null || rows == null)
              scale.hasError
                  ? SizedBox(
                      height: 240,
                      child: ErrorView(
                        title: l10n.gradingScaleLoadFailed,
                        retryLabel: l10n.uiErrorRetry,
                        onRetry: () => ref.invalidate(gradingScaleProvider),
                      ),
                    )
                  : const LinearProgressIndicator()
            else if (!canEdit)
              AppCard(
                key: const Key('scale-read'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.gradingScaleBands, style: text.titleMedium),
                    Text(l10n.gradingScaleReadOnly, style: muted),
                    for (final b in s.bands)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(b.grade),
                        subtitle: Text('${pct(b.min)} – ${pct(b.max)}'),
                        trailing: Text(
                          b.gpa == null
                              ? '—'
                              : OrgTime.number(b.gpa!, language),
                        ),
                      ),
                  ],
                ),
              )
            else
              AppCard(
                key: const Key('scale-edit'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.gradingScaleBands, style: text.titleMedium),
                    Text(l10n.gradingScaleEditHint, style: muted),
                    TextField(
                      key: const Key('scale-name'),
                      controller: _name,
                      maxLength: 60,
                      decoration: InputDecoration(
                        labelText: l10n.gradingScaleName,
                        helperText: l10n.gradingScaleNameHint,
                        helperMaxLines: 3,
                      ),
                    ),
                    for (final (i, r) in rows.indexed)
                      Padding(
                        key: Key('band-$i'),
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (k, c, label) in [
                              ('min', r.min, l10n.gradingScaleFromRow(i + 1)),
                              ('max', r.max, l10n.gradingScaleToRow(i + 1)),
                              (
                                'grade',
                                r.grade,
                                l10n.gradingScaleGradeRow(i + 1),
                              ),
                              ('gpa', r.gpa, l10n.gradingScaleGpaRow(i + 1)),
                            ]) ...[
                              Expanded(
                                child: Semantics(
                                  label: label,
                                  child: TextField(
                                    key: Key('band-$i-$k'),
                                    controller: c,
                                    keyboardType: k == 'grade'
                                        ? TextInputType.text
                                        : const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                    decoration: InputDecoration(
                                      labelText: switch (k) {
                                        'min' => l10n.gradingScaleFrom,
                                        'max' => l10n.gradingScaleTo,
                                        'grade' => l10n.gradingScaleGrade,
                                        _ => l10n.gradingScaleGpa,
                                      },
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                            ],
                            IconButton(
                              key: Key('band-$i-remove'),
                              tooltip: l10n.gradingScaleRemoveRow(i + 1),
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() {
                                rows.removeAt(i).dispose();
                              }),
                            ),
                          ],
                        ),
                      ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: TextButton.icon(
                        key: const Key('band-add'),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.gradingScaleAddBand),
                        onPressed: () => setState(() => rows.add(_Row(null))),
                      ),
                    ),
                    if (problem != null)
                      Text(
                        _problemText(problem),
                        key: const Key('scale-problem'),
                        style: text.bodySmall?.copyWith(color: colors.danger),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AppSpacing.sm,
                      children: [
                        if (s.custom)
                          TextButton(
                            key: const Key('scale-reset'),
                            onPressed: _saving ? null : _reset,
                            child: Text(l10n.gradingScaleReset),
                          ),
                        FilledButton(
                          key: const Key('scale-save'),
                          onPressed: problem == null && !_saving ? _save : null,
                          child: Text(l10n.gradingScaleSave),
                        ),
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
