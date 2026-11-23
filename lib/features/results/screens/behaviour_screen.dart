import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
import 'package:instructor_app/features/results/data/paper_exams.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// A behaviour criterion, in both languages.
typedef BehaviourCriterion = ({String id, String en, String bn});

/// A student's ratings (criterion id → 1–5) and remark for a day.
typedef BehaviourRow = ({
  String studentId,
  String name,
  String? rollNo,
  Map<String, int> ratings,
  String? remark,
});

/// `GET /behaviour/grid?offering_id&date`.
typedef BehaviourGrid = ({
  List<BehaviourCriterion> criteria,
  List<BehaviourRow> rows,
  bool canEdit,
});

BehaviourGrid _grid(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  return (
    criteria: [
      if (j['criteria'] is List)
        for (final c in j['criteria'] as List)
          if (c is Map && c['id'] is String)
            (
              id: c['id'] as String,
              en: (c['name_en'] as String?) ?? '',
              bn: (c['name_bn'] as String?) ?? '',
            ),
    ],
    rows: [
      if (j['rows'] is List)
        for (final r in j['rows'] as List)
          if (r is Map && r['student'] is Map)
            (
              studentId: ((r['student'] as Map)['id'] as String?) ?? '',
              name: ((r['student'] as Map)['full_name'] as String?) ?? '',
              rollNo: (r['student'] as Map)['roll_no'] as String?,
              ratings: {
                if (r['ratings'] is Map)
                  for (final MapEntry(:key, :value)
                      in (r['ratings'] as Map).entries)
                    if (key is String && value is num) key: value.toInt(),
              },
              remark: r['remark'] as String?,
            ),
    ],
    canEdit: j['can_edit'] == true,
  );
}

final behaviourGridProvider = FutureProvider.autoDispose
    .family<BehaviourGrid, ({String offeringId, String date})>((ref, k) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/behaviour/grid',
            query: {'offering_id': k.offeringId, 'date': k.date},
          );
      return _grid(r.payload);
    }, retry: (retryCount, error) => null);

/// A behaviour refusal in the web's words (`behaviour.errors`), or null.
String? _error(AppLocalizations l10n, String? code) => switch (code) {
  'RESULTS_NOT_ALLOWED' => l10n.behaviourErrorsRESULTSNOTALLOWED,
  'RESULTS_NOT_FOUND' => l10n.behaviourErrorsRESULTSNOTFOUND,
  'RESULTS_SESSION_CLOSED' => l10n.behaviourErrorsRESULTSSESSIONCLOSED,
  'RESULTS_CRITERIA_INVALID' => l10n.behaviourErrorsRESULTSCRITERIAINVALID,
  'RESULTS_RATING_INVALID' => l10n.behaviourErrorsRESULTSRATINGINVALID,
  'RESULTS_REMARK_NEEDS_RATING' => l10n.behaviourErrorsRESULTSREMARKNEEDSRATING,
  'RESULTS_STUDENT_NOT_IN_CLASS' =>
    l10n.behaviourErrorsRESULTSSTUDENTNOTINCLASS,
  _ => null,
};

/// Class behaviour (the web's /behaviour, Academic): choose a subject class
/// and a day, then rate each student 1–5 on each criterion, with a remark
/// if needed; only changed students are sent. Changing the criteria is the
/// owners' (Stage 3).
class BehaviourScreen extends ConsumerStatefulWidget {
  const BehaviourScreen({super.key});

  @override
  ConsumerState<BehaviourScreen> createState() => _BehaviourScreenState();
}

class _BehaviourScreenState extends ConsumerState<BehaviourScreen> {
  String? _offeringId;
  String _date = OrgTime.today();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final classes = ref.watch(paperClassChoicesProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.behaviourTitle, style: text.headlineSmall),
            Text(
              l10n.behaviourIntro,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ...classes.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(semanticsLabel: l10n.behaviourTitle),
                ),
              ],
              error: (e, _) => [
                SizedBox(
                  height: 300,
                  child: e is ApiException && e.isFeatureLocked
                      ? EmptyView(
                          icon: Icons.lock_outline,
                          title: l10n.featuresLockedTitle,
                        )
                      : ErrorView(
                          title: l10n.behaviourLoadFailed,
                          retryLabel: l10n.uiErrorRetry,
                          onRetry: () =>
                              ref.invalidate(paperClassChoicesProvider),
                        ),
                ),
              ],
              data: (list) {
                if (list.isEmpty) {
                  return [
                    SizedBox(
                      height: 260,
                      child: EmptyView(
                        icon: Icons.emoji_people_outlined,
                        title: l10n.behaviourNoClasses,
                        message: l10n.behaviourNoClassesHint,
                      ),
                    ),
                  ];
                }
                final current = list.any((c) => c.offeringId == _offeringId)
                    ? _offeringId!
                    : list.first.offeringId;
                return [
                  DropdownButtonFormField<String>(
                    key: const Key('behaviour-class'),
                    initialValue: current,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.behaviourSubjectClass,
                    ),
                    items: [
                      for (final c in list)
                        DropdownMenuItem(
                          value: c.offeringId,
                          child: Text(c.label),
                        ),
                    ],
                    onChanged: (v) => setState(() => _offeringId = v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton.icon(
                      key: const Key('behaviour-date'),
                      onPressed: () async {
                        DateTime d(String s) => DateTime.parse('${s}T00:00:00');
                        final today = OrgTime.today();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: d(_date),
                          firstDate: d(today)
                              .subtract(const Duration(days: 365)),
                          // No later than today, as the web.
                          lastDate: d(today),
                        );
                        if (picked != null) {
                          setState(
                            () =>
                                _date = DateFormat('yyyy-MM-dd').format(picked),
                          );
                        }
                      },
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        '${l10n.behaviourDate}: ${OrgTime.schoolDay(_date, language)}',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _Ratings(
                    key: ValueKey('$current/$_date'),
                    offeringId: current,
                    date: _date,
                  ),
                ];
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Ratings extends ConsumerStatefulWidget {
  const _Ratings({required this.offeringId, required this.date, super.key});

  final String offeringId;
  final String date;

  @override
  ConsumerState<_Ratings> createState() => _RatingsState();
}

class _RatingsState extends ConsumerState<_Ratings> {
  late final _key = (offeringId: widget.offeringId, date: widget.date);
  BehaviourGrid? _latest;
  final _ratings = <String, Map<String, int?>>{};
  final _remarks = <String, TextEditingController>{};
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in _remarks.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(BehaviourGrid g) {
    for (final c in _remarks.values) {
      c.dispose();
    }
    _remarks.clear();
    _ratings.clear();
    for (final r in g.rows) {
      _ratings[r.studentId] = {...r.ratings};
      _remarks[r.studentId] = TextEditingController(text: r.remark ?? '');
    }
  }

  bool _changed(BehaviourRow r) {
    final now = _ratings[r.studentId]!;
    final ratingsChanged = {
      ...now.keys,
      ...r.ratings.keys,
    }.any((k) => now[k] != r.ratings[k]);
    return ratingsChanged ||
        _remarks[r.studentId]!.text.trim() != (r.remark ?? '').trim();
  }

  Future<void> _save(BehaviourGrid g) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final rows = [
      for (final r in g.rows)
        if (_changed(r))
          {
            'student_id': r.studentId,
            'ratings': {
              for (final c in g.criteria)
                if (_ratings[r.studentId]!.containsKey(c.id))
                  c.id: _ratings[r.studentId]![c.id],
            },
            'remark': _remarks[r.studentId]!.text.trim().isEmpty
                ? null
                : _remarks[r.studentId]!.text.trim(),
          },
    ];
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final res = await ref
          .read(apiClientProvider)
          .put(
            '/behaviour/grid',
            data: {
              'offering_id': widget.offeringId,
              'date': widget.date,
              'rows': rows,
            },
          );
      if (!mounted) return;
      final next = _grid(res.payload);
      setState(() {
        _latest = next;
        _fill(next);
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.behaviourSaved)));
    } catch (e) {
      if (!mounted) return;
      final known = e is ApiException ? _error(l10n, e.code) : null;
      if (known != null) {
        setState(() => _problem = known);
      } else if (!await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          ) &&
          mounted) {
        setState(() => _problem = apiErrorText(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = ref.watch(behaviourGridProvider(_key));
    final g = _latest ?? loaded.value;
    if (g != null && _ratings.isEmpty && g.rows.isNotEmpty) _fill(g);
    if (g == null) {
      return loaded.hasError
          ? SizedBox(
              height: 260,
              child: ErrorView(
                title: l10n.behaviourLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(behaviourGridProvider(_key)),
              ),
            )
          : const LinearProgressIndicator();
    }
    return _page(g);
  }

  Widget _page(BehaviourGrid g) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    String name(BehaviourCriterion c) => language == 'bn' ? c.bn : c.en;
    final changed = g.rows.where(_changed).length;
    if (g.rows.isEmpty) {
      return Text(
        l10n.behaviourNoStudents,
        style: text.bodyMedium?.copyWith(color: colors.inkMuted),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          g.canEdit ? l10n.behaviourScale : l10n.behaviourReadOnly,
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final r in g.rows) ...[
          AppCard(
            key: Key('behaviour-${r.studentId}'),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.rollNo == null ? r.name : '${r.rollNo}. ${r.name}',
                  style: text.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final c in g.criteria)
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<int?>(
                          key: Key('rating-${r.studentId}-${c.id}'),
                          initialValue: _ratings[r.studentId]![c.id],
                          isExpanded: true,
                          decoration: InputDecoration(labelText: name(c)),
                          items: [
                            const DropdownMenuItem<int?>(child: Text('—')),
                            for (var v = 1; v <= 5; v++)
                              DropdownMenuItem<int?>(
                                value: v,
                                child: Text(OrgTime.number(v, language)),
                              ),
                          ],
                          onChanged: g.canEdit
                              ? (v) => setState(
                                  () => _ratings[r.studentId]![c.id] = v,
                                )
                              : null,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                TextField(
                  key: Key('remark-${r.studentId}'),
                  controller: _remarks[r.studentId],
                  enabled: g.canEdit,
                  maxLength: 500,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.behaviourRemark,
                    counterText: '',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (_problem != null)
          Text(
            _problem!,
            key: const Key('behaviour-problem'),
            style: text.bodySmall?.copyWith(color: colors.danger),
          ),
        if (g.canEdit)
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              if (changed > 0)
                Text(l10n.behaviourUnsaved(changed), style: text.bodySmall),
              FilledButton(
                key: const Key('behaviour-save'),
                onPressed: _busy || changed == 0 ? null : () => _save(g),
                child: Text(l10n.behaviourSave),
              ),
            ],
          ),
      ],
    );
  }
}
