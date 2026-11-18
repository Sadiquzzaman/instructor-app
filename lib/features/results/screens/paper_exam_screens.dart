import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/results/data/paper_exams.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

String _plain(num v) => v == v.roundToDouble() ? '${v.toInt()}' : '$v';

num? _num(String s) => num.tryParse(s.trim().replaceAll(',', '.'));

/// A paper-exam refusal in the web's words (`marks.errors`), or null.
String? paperExamError(AppLocalizations l10n, String? code) => switch (code) {
  'OFFLINE_EXAM_PARTS_INVALID' => l10n.marksErrorsOFFLINEEXAMPARTSINVALID,
  'OFFLINE_EXAM_TERM_INVALID' => l10n.marksErrorsOFFLINEEXAMTERMINVALID,
  'OFFLINE_EXAM_TOTAL_BELOW_MARKS' =>
    l10n.marksErrorsOFFLINEEXAMTOTALBELOWMARKS,
  'OFFLINE_EXAM_SESSION_CLOSED' => l10n.marksErrorsOFFLINEEXAMSESSIONCLOSED,
  'OFFLINE_EXAM_NOT_ALLOWED' => l10n.marksErrorsOFFLINEEXAMNOTALLOWED,
  'OFFLINE_EXAM_MARKS_INVALID' => l10n.marksErrorsOFFLINEEXAMMARKSINVALID,
  'OFFLINE_EXAM_STUDENT_NOT_IN_CLASS' =>
    l10n.marksErrorsOFFLINEEXAMSTUDENTNOTINCLASS,
  'OFFLINE_EXAM_NOT_FOUND' => l10n.marksErrorsOFFLINEEXAMNOTFOUND,
  'CLASS_REQUIRED' => l10n.marksErrorsCLASSREQUIRED,
  'NAME_REQUIRED' => l10n.marksErrorsNAMEREQUIRED,
  'TOTAL_REQUIRED' => l10n.marksErrorsTOTALREQUIRED,
  _ => null,
};

/// Opens the form over the whole screen; returns what was saved.
Future<PaperExam?> openPaperExamForm(BuildContext context, PaperExam? exam) =>
    Navigator.of(context, rootNavigator: true).push<PaperExam>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaperExamFormScreen(exam: exam),
      ),
    );

/// The web's /marks for staff (Academic): the paper exams they manage,
/// newest first, with marks entered and whether published; Add paper exam.
/// Each opens its marks.
class StaffMarksScreen extends ConsumerWidget {
  const StaffMarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final exams = ref.watch(paperExamsProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(paperExamsProvider);
            await ref
                .read(paperExamsProvider.future)
                .then<void>((_) {}, onError: (Object _) {});
          },
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.marksTitle, style: text.headlineSmall),
                  ),
                  FilledButton.icon(
                    key: const Key('paper-add'),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      final saved = await openPaperExamForm(context, null);
                      if (saved == null) return;
                      ref.invalidate(paperExamsProvider);
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(l10n.marksCreatedHint(saved.name)),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: Text(l10n.marksAdd),
                  ),
                ],
              ),
              Text(
                l10n.marksIntro,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              ...exams.when(
                loading: () => [
                  SizedBox(
                    height: 220,
                    child: LoadingView(semanticsLabel: l10n.marksTitle),
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
                            title: l10n.marksLoadFailed,
                            retryLabel: l10n.uiErrorRetry,
                            onRetry: () => ref.invalidate(paperExamsProvider),
                          ),
                  ),
                ],
                data: (list) => list.isEmpty
                    ? [
                        SizedBox(
                          height: 260,
                          child: EmptyView(
                            icon: Icons.grading_outlined,
                            title: l10n.marksEmpty,
                            message: l10n.marksEmptyHint,
                          ),
                        ),
                      ]
                    : [
                        for (final e in list) ...[
                          AppCard(
                            key: Key('paper-${e.id}'),
                            onTap: () =>
                                context.push('${AppRoutes.marks}/${e.id}'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        e.name,
                                        style: text.titleMedium,
                                      ),
                                    ),
                                    StatusPill(
                                      label: e.publishedAt != null
                                          ? l10n.marksPublished
                                          : l10n.marksNotPublished,
                                      tone: e.publishedAt != null
                                          ? StatusTone.success
                                          : StatusTone.neutral,
                                    ),
                                  ],
                                ),
                                Text(
                                  [
                                    e.subject,
                                    e.section,
                                    if (e.date.isNotEmpty)
                                      OrgTime.schoolDay(e.date, language),
                                    l10n.marksOutOf(e.total),
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                  style: text.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                                Text(
                                  l10n.marksEntered(e.entered, e.students),
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds or changes a paper exam (the web's PaperExamDrawer): the subject
/// class (new only), name, date, total, optionally its parts (they must add
/// up to the total) and a term.
class PaperExamFormScreen extends ConsumerStatefulWidget {
  const PaperExamFormScreen({this.exam, super.key});

  final PaperExam? exam;

  @override
  ConsumerState<PaperExamFormScreen> createState() =>
      _PaperExamFormScreenState();
}

class _PaperExamFormScreenState extends ConsumerState<PaperExamFormScreen> {
  late final PaperExam? _e = widget.exam;
  String? _offeringId;
  late final _name = TextEditingController(text: _e?.name ?? '');
  late String _date = _e?.date ?? OrgTime.today();
  late final _total = TextEditingController(text: _plain(_e?.total ?? 100));
  late bool _withParts = (_e?.parts ?? const []).isNotEmpty;
  late final List<(TextEditingController, TextEditingController)> _parts = [
    for (final p in _e?.parts ?? const <PaperPart>[])
      (
        TextEditingController(text: p.name),
        TextEditingController(text: _plain(p.marks)),
      ),
  ];
  late String? _termId = _e?.termId;
  String? _problem;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _total.dispose();
    for (final (a, b) in _parts) {
      a.dispose();
      b.dispose();
    }
    super.dispose();
  }

  void _toggleParts(bool on) {
    final l10n = context.l10n;
    setState(() {
      _withParts = on;
      if (on && _parts.isEmpty) {
        _parts
          ..add((
            TextEditingController(text: l10n.marksPartMcq),
            TextEditingController(),
          ))
          ..add((
            TextEditingController(text: l10n.marksPartWritten),
            TextEditingController(),
          ));
      }
    });
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    String? local;
    if (_e == null && _offeringId == null) {
      local = 'CLASS_REQUIRED';
    } else if (_name.text.trim().isEmpty) {
      local = 'NAME_REQUIRED';
    } else if ((_num(_total.text) ?? 0) <= 0) {
      local = 'TOTAL_REQUIRED';
    }
    if (local != null) {
      setState(() => _problem = paperExamError(l10n, local));
      return;
    }
    setState(() {
      _problem = null;
      _saving = true;
    });
    try {
      final saved = await ref
          .read(paperExamsRepositoryProvider)
          .save(
            id: _e?.id,
            offeringId: _offeringId,
            name: _name.text.trim(),
            date: _date,
            total: _num(_total.text)!,
            parts: _withParts
                ? [
                    for (final (n, m) in _parts)
                      (name: n.text.trim(), marks: _num(m.text) ?? 0),
                  ]
                : null,
            termId: _termId,
          );
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      final known = e is ApiException ? paperExamError(l10n, e.code) : null;
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
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final choices = ref.watch(paperClassChoicesProvider).value ?? const [];
    final classId = _e?.offeringId ?? _offeringId;
    final terms =
        choices.where((c) => c.offeringId == classId).firstOrNull?.terms ??
        [if (_e?.termId != null) (id: _e!.termId!, name: _e.termName ?? '')];
    final sum = _parts.fold<num>(0, (s, p) => s + (_num(p.$2.text) ?? 0));
    final total = _num(_total.text) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_e == null ? l10n.marksAddTitle : l10n.marksEditTitle),
        leading: IconButton(
          tooltip: l10n.marksCancel,
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                l10n.marksFormIntro,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_e != null)
                Text('${_e.subject} · ${_e.section}', style: text.titleSmall)
              else
                DropdownButtonFormField<String>(
                  key: const Key('paper-class'),
                  initialValue: _offeringId,
                  isExpanded: true,
                  hint: Text(l10n.marksChooseSubjectClass),
                  decoration: InputDecoration(
                    labelText: l10n.marksSubjectClass,
                    helperText: choices.isEmpty
                        ? l10n.marksNoSubjectClasses
                        : null,
                  ),
                  items: [
                    for (final c in choices)
                      DropdownMenuItem(
                        value: c.offeringId,
                        child: Text(c.label),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    _offeringId = v;
                    _termId = null;
                  }),
                ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('paper-name'),
                controller: _name,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: l10n.marksName,
                  hintText: l10n.marksNamePlaceholder,
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('paper-date'),
                      onPressed: () async {
                        DateTime d(String s) => DateTime.parse('${s}T00:00:00');
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: d(_date),
                          firstDate: d(OrgTime.today())
                              .subtract(const Duration(days: 730)),
                          lastDate: d(OrgTime.today())
                              .add(const Duration(days: 365)),
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
                        '${l10n.marksDate}: ${OrgTime.schoolDay(_date, language)}',
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      key: const Key('paper-total'),
                      controller: _total,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(labelText: l10n.marksTotal),
                    ),
                  ),
                ],
              ),
              if (terms.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                DropdownButtonFormField<String?>(
                  key: const Key('paper-term'),
                  initialValue: _termId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.marksTerm),
                  items: [
                    DropdownMenuItem<String?>(child: Text(l10n.marksNoTerm)),
                    for (final t in terms)
                      DropdownMenuItem<String?>(
                        value: t.id,
                        child: Text(t.name),
                      ),
                  ],
                  onChanged: (v) => setState(() => _termId = v),
                ),
              ],
              CheckboxListTile(
                key: const Key('paper-with-parts'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _withParts,
                onChanged: (v) => _toggleParts(v ?? false),
                title: Text(l10n.marksWithParts),
                subtitle: Text(l10n.marksWithPartsHint),
              ),
              if (_withParts) ...[
                for (final (i, (n, m)) in _parts.indexed)
                  Padding(
                    key: Key('part-$i'),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: n,
                            decoration: InputDecoration(
                              labelText: l10n.marksPartName(i + 1),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        SizedBox(
                          width: 96,
                          child: TextField(
                            key: Key('part-marks-$i'),
                            controller: m,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: l10n.marksPartMarks(i + 1),
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.marksRemovePart(i + 1),
                          onPressed: _parts.length <= 1
                              ? null
                              : () => setState(() {
                                  final (a, b) = _parts.removeAt(i);
                                  a.dispose();
                                  b.dispose();
                                }),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    if (_parts.length < 6)
                      TextButton.icon(
                        key: const Key('part-add'),
                        onPressed: () => setState(
                          () => _parts.add((
                            TextEditingController(),
                            TextEditingController(),
                          )),
                        ),
                        icon: const Icon(Icons.add),
                        label: Text(l10n.marksAddPart),
                      ),
                    const Spacer(),
                    Text(
                      l10n.marksPartsSum(sum, total),
                      style: text.bodySmall?.copyWith(
                        color: sum == total ? colors.inkMuted : colors.danger,
                      ),
                    ),
                  ],
                ),
              ],
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    _problem!,
                    key: const Key('paper-problem'),
                    style: text.bodySmall?.copyWith(color: colors.danger),
                  ),
                ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(l10n.marksCancel),
                  ),
                  FilledButton(
                    key: const Key('paper-save'),
                    onPressed: _saving ? null : _save,
                    child: Text(l10n.marksSave),
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

/// A paper exam's marks (the web's MarksGrid): a line per student, marks
/// per part (the total is their sum) or out of the total, or absent; Save
/// marks sends the changed lines; Publish and Delete after asking; Edit the
/// exam. The CSV sheet stays on the web.
class PaperMarksScreen extends ConsumerStatefulWidget {
  const PaperMarksScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<PaperMarksScreen> createState() => _PaperMarksScreenState();
}

class _PaperMarksScreenState extends ConsumerState<PaperMarksScreen> {
  PaperMarksGrid? _latest;

  /// Per student: the typed values (per part, or "marks") and absent.
  final _values = <String, Map<String, TextEditingController>>{};
  final _absent = <String, bool>{};
  String? _problem;
  bool _busy = false;

  @override
  void dispose() {
    for (final m in _values.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  List<String> _keys(PaperExam e) =>
      e.parts.isEmpty ? const ['marks'] : [for (final p in e.parts) p.name];

  String _saved(PaperMarkRow r, String key) => key == 'marks'
      ? (r.marks == null ? '' : _plain(r.marks!))
      : (r.partMarks[key] == null ? '' : _plain(r.partMarks[key]!));

  void _fill(PaperMarksGrid g) {
    for (final m in _values.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _values.clear();
    _absent.clear();
    for (final r in g.rows) {
      _values[r.studentId] = {
        for (final k in _keys(g.exam))
          k: TextEditingController(text: _saved(r, k)),
      };
      _absent[r.studentId] = r.absent;
    }
  }

  bool _changed(PaperMarksGrid g, PaperMarkRow r) =>
      _absent[r.studentId] != r.absent ||
      _keys(g.exam)
          .any((k) => _values[r.studentId]![k]!.text.trim() != _saved(r, k));

  Map<String, Object?> _row(PaperMarksGrid g, PaperMarkRow r) {
    if (_absent[r.studentId] == true) {
      return {'student_id': r.studentId, 'is_absent': true};
    }
    final v = _values[r.studentId]!;
    if (g.exam.parts.isNotEmpty) {
      return {
        'student_id': r.studentId,
        'part_marks': {
          for (final p in g.exam.parts)
            if (v[p.name]!.text.trim().isNotEmpty)
              p.name: _num(v[p.name]!.text),
        },
        'is_absent': false,
      };
    }
    final t = v['marks']!.text.trim();
    return {
      'student_id': r.studentId,
      'marks': t.isEmpty ? null : _num(t),
      'is_absent': false,
    };
  }

  Future<void> _save(PaperMarksGrid g) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final changed = [
      for (final r in g.rows)
        if (_changed(g, r)) r,
    ];
    final rows = [for (final r in changed) _row(g, r)];
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      final next = await ref
          .read(paperExamsRepositoryProvider)
          .saveMarks(widget.id, rows);
      if (!mounted) return;
      setState(() {
        _latest = next;
        _fill(next);
      });
      messenger.showSnackBar(SnackBar(content: Text(l10n.marksSaved)));
      ref.invalidate(paperExamsProvider);
    } catch (e) {
      if (!mounted) return;
      final known = e is ApiException ? paperExamError(l10n, e.code) : null;
      if (known != null) {
        // Which student, when the server says.
        final d = (e as ApiException).details;
        final i = d is Map ? (d['index'] as num?)?.toInt() : null;
        final who = i != null && i < changed.length ? changed[i].name : null;
        setState(
          () => _problem = who == null ? known : l10n.marksErrorFor(who, known),
        );
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

  Future<bool> _ask(
    String title,
    String detail,
    String yes, {
    bool danger = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(context.l10n.marksCancel),
            ),
            FilledButton(
              key: const Key('confirm'),
              style: danger
                  ? FilledButton.styleFrom(
                      backgroundColor: AppColors.of(d).danger,
                    )
                  : null,
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(yes),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _act(
    Future<void> Function() call,
    String done, {
    bool leave = false,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(paperExamsProvider);
      if (leave) {
        router.go(AppRoutes.marks);
      } else {
        setState(() => _latest = null);
        ref.invalidate(paperMarksProvider(widget.id));
      }
    } catch (e) {
      if (mounted &&
          !await handleCommonApiError(
            context,
            e,
            session: ref.read(sessionProvider),
          )) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = ref.watch(paperMarksProvider(widget.id));
    final g = _latest ?? loaded.value;
    if (g != null && _values.isEmpty && g.rows.isNotEmpty) _fill(g);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: g != null
            ? _page(g)
            : loaded.hasError
            ? ErrorView(
                title: l10n.marksLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(paperMarksProvider(widget.id)),
              )
            : LoadingView(semanticsLabel: l10n.marksTitle),
      ),
    );
  }

  Widget _page(PaperMarksGrid g) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final e = g.exam;
    final readOnly = !e.canEdit;
    String n(num v) => OrgTime.number(v, language);
    final columns = e.parts.isEmpty
        ? [(key: 'marks', label: l10n.marksMarksColumn, max: e.total)]
        : [for (final p in e.parts) (key: p.name, label: p.name, max: p.marks)];
    final changed = g.rows.where((r) => _changed(g, r)).length;
    bool tooMuch(PaperMarkRow r, ({String key, String label, num max}) c) {
      final v = _num(_values[r.studentId]?[c.key]?.text ?? '');
      return v != null && (v < 0 || v > c.max);
    }

    final invalid = g.rows.any((r) => columns.any((c) => tooMuch(r, c)));
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(e.name, style: text.headlineSmall),
        Text(
          [
            e.subject,
            e.section,
            if (e.date.isNotEmpty) OrgTime.schoolDay(e.date, language),
            l10n.marksOutOf(e.total),
            ?e.termName,
          ].where((s) => s.isNotEmpty).join(' · '),
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            StatusPill(
              label: e.publishedAt != null
                  ? l10n.marksPublished
                  : l10n.marksNotPublished,
              tone: e.publishedAt != null
                  ? StatusTone.success
                  : StatusTone.neutral,
            ),
            Text(
              l10n.marksEntered(e.entered, e.students),
              style: text.bodySmall,
            ),
            if (e.parts.isNotEmpty)
              Text(
                l10n.marksPartsOf(
                  e.parts.map((p) => '${p.name} ${n(p.marks)}').join(' + '),
                ),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
            if (readOnly)
              Text(
                l10n.marksReadOnly,
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
          ],
        ),
        if (!readOnly) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton(
                key: const Key('paper-edit'),
                onPressed: _busy
                    ? null
                    : () async {
                        final saved = await openPaperExamForm(context, e);
                        if (saved == null || !mounted) return;
                        await _act(() async {}, l10n.marksExamSaved);
                      },
                child: Text(l10n.marksEdit),
              ),
              if (e.publishedAt == null)
                FilledButton(
                  key: const Key('paper-publish'),
                  onPressed: _busy
                      ? null
                      : () async {
                          if (await _ask(
                            l10n.marksPublishTitle,
                            l10n.marksPublishDetail(e.students - e.entered),
                            l10n.marksPublish,
                          )) {
                            await _act(
                              () => ref
                                  .read(paperExamsRepositoryProvider)
                                  .publish(widget.id),
                              l10n.marksPublishedToast,
                            );
                          }
                        },
                  child: Text(l10n.marksPublish),
                ),
              TextButton(
                key: const Key('paper-remove'),
                style: TextButton.styleFrom(foregroundColor: colors.danger),
                onPressed: _busy
                    ? null
                    : () async {
                        if (await _ask(
                          l10n.marksRemoveTitle,
                          l10n.marksRemoveDetail,
                          l10n.marksRemove,
                          danger: true,
                        )) {
                          await _act(
                            () => ref
                                .read(paperExamsRepositoryProvider)
                                .remove(widget.id),
                            l10n.marksRemoved,
                            leave: true,
                          );
                        }
                      },
                child: Text(l10n.marksRemove),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final r in g.rows)
          AppCard(
            key: Key('mark-row-${r.studentId}'),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        r.rollNo == null ? r.name : '${r.rollNo}. ${r.name}',
                        style: text.titleSmall,
                      ),
                    ),
                    Text(
                      r.absent
                          ? l10n.marksAbsent
                          : (r.marks == null
                                ? '—'
                                : '${n(r.marks!)}/${n(e.total)}'
                                      '${r.grade == null ? '' : ' (${r.grade})'}'),
                      style: text.bodySmall,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in columns)
                      SizedBox(
                        width: 120,
                        child: TextField(
                          key: Key('mark-${r.studentId}-${c.key}'),
                          controller: _values[r.studentId]![c.key],
                          enabled: !readOnly && _absent[r.studentId] != true,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: c.label,
                            suffixText: '/ ${n(c.max)}',
                            errorText: tooMuch(r, c) ? '0–${n(c.max)}' : null,
                          ),
                        ),
                      ),
                    FilterChip(
                      key: Key('absent-${r.studentId}'),
                      label: Text(l10n.marksAbsent),
                      selected: _absent[r.studentId] == true,
                      onSelected: readOnly
                          ? null
                          : (v) => setState(() => _absent[r.studentId] = v),
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              _problem!,
              key: const Key('marks-problem'),
              style: text.bodySmall?.copyWith(color: colors.danger),
            ),
          ),
        if (!readOnly) ...[
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            children: [
              if (changed > 0)
                Text(l10n.marksUnsaved(changed), style: text.bodySmall),
              FilledButton(
                key: const Key('marks-save'),
                onPressed: _busy || invalid || changed == 0
                    ? null
                    : () => _save(g),
                child: Text(l10n.marksSaveMarks),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
