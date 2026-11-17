import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/device/secure_screen.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/tests/data/exam_live.dart';
import 'package:instructor_app/features/tests/data/take_test.dart';

/// Answers go to the server this long after the last change (PRO-09).
const saveAfter = Duration(seconds: 3);

/// A submit with no connection is tried again this often, this many times.
const submitRetryEvery = Duration(seconds: 5);
const submitRetries = 12;

/// Flag points (the web's PROCTORING_FLAG_POINTS) and their checks.
const _flagPoints = {'tab-switch': 1, 'paste-attempt': 2};
const _flagCheck = {
  'tab-switch': 'proctoring_tab_switch',
  'paste-attempt': 'proctoring_copy_paste',
};

enum _Stage {
  checking,
  closed,
  computer,
  rules,
  starting,
  writing,
  submitting,
  done,
  failed,
}

/// Taking a test (the web's /test, Off and Light proctoring): the
/// eligibility check, the rules, then the questions with a timer; answers
/// kept on the phone and sent as they change; submit (asked first, retried
/// while offline, automatic when time is up). Light proctoring: leaving the
/// app is flagged, paste is off, screenshots are blocked on Android. Strict
/// and IELTS tests say to use a computer (owner's decision 7).
class TakeTestScreen extends ConsumerStatefulWidget {
  const TakeTestScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<TakeTestScreen> createState() => _TakeTestScreenState();
}

class _TakeTestScreenState extends ConsumerState<TakeTestScreen>
    with WidgetsBindingObserver {
  _Stage _stage = _Stage.checking;
  String _closedCode = 'OK';
  Eligibility? _rules;
  bool _accepted = false;
  TestPaper? _paper;
  final _answers = <String, Object>{};
  final _unsaved = <String>{};
  final _text = <String, TextEditingController>{};
  final _flags = <ProctorFlag>[];
  bool _away = false;
  bool _saving = false;
  bool _savedToServer = true;
  int? _left;
  Timer? _clock;
  Timer? _saver;
  StreamSubscription<TeacherEvent>? _teacher;
  SubmitReason? _endedBy;
  String? _endNote;
  bool _offlineSubmit = false;

  TakeTestRepository get _repo => ref.read(takeTestRepositoryProvider);
  String get _storeKey =>
      'exam/${ref.read(sessionProvider)?.userId}/${widget.id}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _saver?.cancel();
    _teacher?.cancel();
    for (final c in _text.values) {
      c.dispose();
    }
    setSecureScreen(false);
    super.dispose();
  }

  bool _watches(String check) => _rules?.checks.contains(check) ?? false;
  bool get _light => _rules?.level == 'LIGHT';

  Future<void> _check() async {
    try {
      final e = await _repo.eligibility(widget.id);
      if (!mounted) return;
      setState(() {
        _rules = e;
        _stage = !e.canAccess
            ? _Stage.closed
            : e.needsComputer
            ? _Stage.computer
            : _Stage.rules;
        _closedCode = e.reasonCode;
      });
    } on ApiException {
      if (mounted) setState(() => _stage = _Stage.failed);
    }
  }

  Future<void> _start() async {
    setState(() => _stage = _Stage.starting);
    try {
      final device = await ref.read(deviceInfoProvider);
      await _repo.start(
        widget.id,
        userAgent: 'Instructor/${device.appVersion} (${device.platform})',
      );
      final paper = await _repo.paper(widget.id);
      if (!mounted) return;
      if (paper.hasSpokenAnswers) {
        setState(() => _stage = _Stage.computer);
        return;
      }
      _restore(paper);
      setState(() {
        _paper = paper;
        _left = paper.remainingSeconds;
        _stage = _Stage.writing;
      });
      if (_light) unawaited(setSecureScreen(true));
      _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      final live = ref.read(examLiveProvider);
      _teacher = live.events.listen(_onTeacher);
      live.join(widget.id);
    } on ApiException catch (e) {
      if (!mounted) return;
      // A refusal at start says why, as eligibility does.
      if (e.code != null && e.statusCode == 403) {
        setState(() {
          _closedCode = e.code == 'EXAM_FULL' ? 'EXAM_FULL' : 'ENDED';
          _stage = _Stage.closed;
        });
      } else {
        setState(() => _stage = _Stage.failed);
      }
    }
  }

  /// Empty answers, then what this phone kept for this attempt.
  void _restore(TestPaper paper) {
    for (final q in paper.questions) {
      _answers[q.id] = q.empty;
    }
    final saved = ref.read(sharedPreferencesProvider).getString(_storeKey);
    if (saved != null) {
      final j = jsonDecode(saved);
      if (j is Map) {
        for (final MapEntry(:key, :value) in j.entries) {
          if (key is String && _answers.containsKey(key)) {
            _answers[key] = value is List
                ? [for (final v in value) '$v']
                : '$value';
          }
        }
      }
    }
    for (final q in paper.questions.where((q) => q.mode == 'text')) {
      _text[q.id] = TextEditingController(
        text: _answers[q.id] as String? ?? '',
      );
    }
  }

  void _tick() {
    final left = _left;
    if (left == null || _stage != _Stage.writing) return;
    setState(() => _left = left - 1);
    if (left - 1 <= 0) _submit(SubmitReason.timeout);
  }

  void _set(String id, Object value) {
    setState(() {
      _answers[id] = value;
      _unsaved.add(id);
      _savedToServer = false;
    });
    ref
        .read(sharedPreferencesProvider)
        .setString(_storeKey, jsonEncode(_answers));
    _saver?.cancel();
    _saver = Timer(saveAfter, _save);
  }

  Future<void> _save() async {
    if (_unsaved.isEmpty || _stage != _Stage.writing) return;
    final changed = {for (final id in _unsaved) id: _answers[id]!};
    setState(() => _saving = true);
    try {
      await _repo.save(widget.id, changed);
      if (!mounted) return;
      setState(() {
        _unsaved.removeAll(changed.keys);
        _savedToServer = _unsaved.isEmpty;
      });
    } on ApiException {
      // Kept on the phone; sent with the next change or the submit.
      _saver = Timer(const Duration(seconds: 10), _save);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_stage != _Stage.writing ||
        !_light ||
        !_watches('proctoring_tab_switch')) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (_away) return;
      _away = true;
      _raise('tab-switch', 'Student left the app during the test.');
    } else if (state == AppLifecycleState.resumed && _away) {
      _away = false;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(context.l10n.appTestLeftApp)));
    }
  }

  void _raise(String type, String message) {
    final flag = ProctorFlag(
      id: '${DateTime.now().microsecondsSinceEpoch}-$type',
      type: type,
      message: message,
      points: _flagPoints[type] ?? 1,
      at: DateTime.now(),
    );
    setState(() => _flags.add(flag));
    ref.read(examLiveProvider).flag(widget.id, flag);
    if (type == 'tab-switch') {
      _repo.reportViolation(widget.id, 'TAB_SWITCH').catchError((Object _) {});
    }
    final auto = _rules?.autoDisqualify;
    if (auto != null && _counted >= auto.threshold) {
      _endNote = message;
      _submit(SubmitReason.disqualified);
    }
  }

  /// Points of the flags that count towards auto-disqualification.
  int get _counted {
    final auto = _rules?.autoDisqualify;
    if (auto == null) return 0;
    return _flags
        .where((f) => auto.checks.contains(_flagCheck[f.type]))
        .fold(0, (sum, f) => sum + f.points);
  }

  void _onTeacher(TeacherEvent e) {
    if (!mounted) return;
    switch (e) {
      case TeacherWarning(:final message):
        showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(dialog.l10n.examTeacherWarningTitle),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(),
                child: Text(dialog.l10n.examTeacherWarningOk),
              ),
            ],
          ),
        );
      case TestEnded(:final reason):
        _endNote = reason;
        _submit(SubmitReason.disqualified, byTeacher: true);
    }
  }

  int get _open => _answers.values.where(_isEmpty).length;
  static bool _isEmpty(Object v) =>
      v is String ? v.trim().isEmpty : (v is List && v.isEmpty);

  Future<void> _confirmSubmit() async {
    final l10n = context.l10n;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.examSubmitTitle),
        content: Text(l10n.examSubmitDetail(_open)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.examKeepWorking),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.examSubmitConfirm),
          ),
        ],
      ),
    );
    if (sure == true) await _submit(SubmitReason.manual);
  }

  Future<void> _submit(SubmitReason reason, {bool byTeacher = false}) async {
    if (_stage != _Stage.writing) return;
    _clock?.cancel();
    _saver?.cancel();
    setState(() {
      _stage = _Stage.submitting;
      _endedBy = reason;
    });
    final session = ref.read(sessionProvider);
    final answers = Map<String, Object>.of(_answers);
    ref
        .read(examLiveProvider)
        .submit(
          widget.id,
          studentId: session?.userId ?? '',
          studentName: session?.fullName ?? '',
          answers: answers,
          totalFlagPoints: _flags.fold(0, (s, f) => s + f.points),
        );
    for (var attempt = 0; ; attempt++) {
      try {
        await _repo.submit(
          widget.id,
          studentId: session?.userId ?? '',
          answers: answers,
          reason: reason,
          flags: _flags,
          disqualificationReason: reason == SubmitReason.disqualified
              ? _endNote
              : null,
        );
        break;
      } on ApiException catch (e) {
        if (!e.isTransient || attempt >= submitRetries) {
          // The server finalises with what was saved; say it is over.
          break;
        }
        if (mounted) setState(() => _offlineSubmit = true);
        await Future<void>.delayed(submitRetryEvery);
        if (!mounted) return;
      }
    }
    await ref.read(sharedPreferencesProvider).remove(_storeKey);
    unawaited(setSecureScreen(false));
    if (!mounted) return;
    setState(() {
      _offlineSubmit = false;
      _stage = _Stage.done;
      if (byTeacher) _endedBy = SubmitReason.disqualified;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      // No leaving by the back button while writing.
      canPop: _stage != _Stage.writing && _stage != _Stage.submitting,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading:
              _stage != _Stage.writing && _stage != _Stage.submitting,
          title: Text(_paper?.name ?? l10n.testsTitle),
          actions: [
            if (_stage == _Stage.writing && _left != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Center(
                  child: Semantics(
                    label: l10n.examTimeLeftLabel,
                    child: Text(
                      _clockText(context, _left!),
                      key: const Key('time-left'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
              ),
          ],
        ),
        body: SafeArea(child: _body(context)),
      ),
    );
  }

  String _clockText(BuildContext context, int seconds) {
    final language = Localizations.localeOf(context).languageCode;
    final s = seconds < 0 ? 0 : seconds;
    return context.l10n.examCountdown(
      OrgTime.number(s ~/ 60, language),
      OrgTime.twoDigits(s % 60, language),
    );
  }

  Widget _message(
    String title,
    String detail, {
    IconData icon = Icons.info_outline,
  }) => EmptyView(
    icon: icon,
    title: title,
    message: detail,
    actionLabel: context.l10n.examBackToTests,
    onAction: () => context.go(AppRoutes.tests),
  );

  Widget _body(BuildContext context) {
    final l10n = context.l10n;
    switch (_stage) {
      case _Stage.checking || _Stage.starting:
        return LoadingView(semanticsLabel: l10n.testsTitle);
      case _Stage.failed:
        return ErrorView(
          title: l10n.examUnableToLoad,
          retryLabel: l10n.examRetry,
          onRetry: () {
            setState(() => _stage = _Stage.checking);
            _check();
          },
        );
      case _Stage.computer:
        return _message(
          l10n.appTestUseComputer,
          l10n.appTestUseComputerDetail,
          icon: Icons.computer,
        );
      case _Stage.closed:
        final (title, detail) = switch (_closedCode) {
          'NOT_STARTED' => (
            l10n.examMessageNotStartedTitle,
            l10n.examMessageNotStartedDescription,
          ),
          'ALREADY_SUBMITTED' => (
            l10n.examMessageAlreadySubmittedTitle,
            l10n.examMessageAlreadySubmittedDescription,
          ),
          'DISQUALIFIED' => (
            l10n.examMessageDisqualifiedTitle,
            l10n.examMessageDisqualifiedDescription,
          ),
          'NOT_ASSIGNED' => (
            l10n.examMessageNotAssignedTitle,
            l10n.examMessageNotAssignedDescription,
          ),
          'EXAM_FULL' => (
            l10n.examMessageExamFullTitle,
            l10n.examMessageExamFullDescription,
          ),
          _ => (
            l10n.examMessageExamEndedTitle,
            l10n.examMessageExamEndedDescription,
          ),
        };
        return _message(title, detail);
      case _Stage.rules:
        return _rulesView(context);
      case _Stage.writing:
        return _paperView(context);
      case _Stage.submitting:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _offlineSubmit
                      ? l10n.examSubmitWaitingTitle
                      : l10n.examSubmitting,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                if (_offlineSubmit)
                  Text(
                    l10n.examSubmitWaitingDetail,
                    textAlign: TextAlign.center,
                  ),
              ],
            ),
          ),
        );
      case _Stage.done:
        return switch (_endedBy) {
          SubmitReason.timeout => _message(
            l10n.examMessageTimeUpTitle,
            l10n.examMessageTimeUpDescription,
          ),
          SubmitReason.disqualified => _message(
            l10n.examMessageDisqualifiedTitle,
            _endNote != null && _endNote!.isNotEmpty
                ? l10n.examEndedByTeacher(_endNote!)
                : l10n.examMessageDisqualifiedDescription,
          ),
          _ => _message(
            l10n.examMessageAlreadySubmittedTitle,
            l10n.examMessageAlreadySubmittedDescription,
            icon: Icons.check_circle_outline,
          ),
        };
    }
  }

  Widget _rulesView(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final auto = _rules?.autoDisqualify;
    final rules = [
      l10n.examPermissionsRulesRead,
      l10n.examPermissionsRulesTime,
      if (_light && _watches('proctoring_tab_switch')) l10n.appTestRuleLeaveApp,
      if (_light && _watches('proctoring_copy_paste')) l10n.appTestRuleNoPaste,
      if (_light) l10n.appTestRuleNoScreenshots,
      if (_light) l10n.examPermissionsRulesFlags,
      if (auto != null) ...[
        if (auto.warnAt > 0) l10n.examPermissionsRulesWarn(auto.warnAt),
        l10n.examPermissionsRulesLimit(auto.threshold),
      ] else if (_light)
        l10n.examPermissionsRulesReview,
    ];
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.examPermissionsRulesTitle, style: text.titleLarge),
            const SizedBox(height: AppSpacing.md),
            for (final r in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(r, style: text.bodyMedium)),
                  ],
                ),
              ),
            if (!_light)
              Text(l10n.examPermissionsWatchedNone, style: text.bodySmall),
            const SizedBox(height: AppSpacing.md),
            CheckboxListTile(
              key: const Key('accept-rules'),
              value: _accepted,
              onChanged: (v) => setState(() => _accepted = v ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(l10n.examPermissionsAccept),
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(
              key: const Key('start-test'),
              label: l10n.examPermissionsStartTest,
              onPressed: _accepted ? _start : null,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _paperView(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final paper = _paper!;
    final total = paper.questions.length;
    final answered = total - _open;
    final auto = _rules?.autoDisqualify;
    final noPaste = _light && _watches('proctoring_copy_paste');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.examNavigatorProgress(answered, total),
                    key: const Key('progress'),
                    style: text.bodyMedium,
                  ),
                ),
                Text(
                  _saving
                      ? l10n.examSaveStatusSaving
                      : _savedToServer
                      ? l10n.examSaveStatusServer
                      : l10n.examSaveStatusDevice,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
            Text(
              l10n.examTotalMarks(paper.totalMarks),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            if (auto != null && auto.warnAt > 0 && _counted >= auto.warnAt) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                key: const Key('flag-warning'),
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: colors.warningSoft,
                  borderRadius: AppRadius.inputAll,
                ),
                child: Text(l10n.appTestWarnLimit(_counted, auto.threshold)),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            for (final (i, q) in paper.questions.indexed) ...[
              if (q.passage != null &&
                  (i == 0 || paper.questions[i - 1].passage != q.passage))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: colors.canvas,
                      borderRadius: AppRadius.inputAll,
                    ),
                    child: Text(q.passage!, style: text.bodyMedium),
                  ),
                ),
              _QuestionView(
                key: Key('q-${q.id}'),
                question: q,
                value: _answers[q.id] ?? q.empty,
                controller: _text[q.id],
                noPaste: noPaste,
                language: language,
                onChanged: (v) => _set(q.id, v),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            AppButton(
              key: const Key('submit-test'),
              label: l10n.examSubmit,
              onPressed: _confirmSubmit,
              expand: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionView extends StatelessWidget {
  const _QuestionView({
    required this.question,
    required this.value,
    required this.onChanged,
    required this.noPaste,
    required this.language,
    this.controller,
    super.key,
  });

  final PaperQuestion question;
  final Object value;
  final ValueChanged<Object> onChanged;
  final TextEditingController? controller;
  final bool noPaste;
  final String language;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final q = question;
    final selected = value is List
        ? [for (final v in value as List) '$v']
        : const <String>[];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.examQuestionLabel(q.number),
                  style: text.labelMedium?.copyWith(color: colors.inkMuted),
                ),
              ),
              Text(
                l10n.examPoints(q.points),
                style: text.labelMedium?.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            q.text,
            style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (q.instruction != null && q.instruction!.isNotEmpty)
            Text(
              q.instruction!,
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
          const SizedBox(height: AppSpacing.sm),
          switch (q.mode) {
            'single-select' => RadioGroup<String>(
              groupValue: selected.firstOrNull,
              onChanged: (v) {
                if (v != null) onChanged([v]);
              },
              child: Column(
                children: [
                  for (final c in q.choices)
                    RadioListTile<String>(
                      key: Key('choice-${c.id}'),
                      value: c.id,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.text),
                    ),
                ],
              ),
            ),
            'multi-select' => Column(
              children: [
                for (final c in q.choices)
                  CheckboxListTile(
                    key: Key('choice-${c.id}'),
                    value: selected.contains(c.id),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(c.text),
                    onChanged: (on) => onChanged(
                      on == true
                          ? [...selected, c.id]
                          : [
                              for (final s in selected)
                                if (s != c.id) s,
                            ],
                    ),
                  ),
              ],
            ),
            'matching' => Column(
              children: [
                for (final l in q.left)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Row(
                      children: [
                        Expanded(child: Text(l.text, style: text.bodyMedium)),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: Key('match-${l.id}'),
                            initialValue: selected
                                .where((p) => p.startsWith('${l.id}::'))
                                .map((p) => p.substring(l.id.length + 2))
                                .firstOrNull,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: l10n.appTestChooseMatch,
                            ),
                            items: [
                              for (final r in q.right)
                                DropdownMenuItem(
                                  value: r.id,
                                  child: Text(r.text),
                                ),
                            ],
                            onChanged: (r) {
                              if (r == null) return;
                              // One pair per left item, in the left items' order.
                              final pairs = {
                                for (final p in selected)
                                  p.split('::').first: p,
                              }..[l.id] = '${l.id}::$r';
                              onChanged([
                                for (final left in q.left)
                                  if (pairs[left.id] != null) pairs[left.id]!,
                              ]);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            _ => TextField(
              key: Key('answer-${q.id}'),
              controller: controller,
              minLines: 3,
              maxLines: 10,
              // No copy and paste when the test watches it (Light).
              enableInteractiveSelection: !noPaste,
              contextMenuBuilder: noPaste ? null : _defaultMenu,
              decoration: InputDecoration(hintText: l10n.examWriteAnswer),
              onChanged: onChanged,
            ),
          },
        ],
      ),
    );
  }

  static Widget _defaultMenu(BuildContext context, EditableTextState state) =>
      AdaptiveTextSelectionToolbar.editableText(editableTextState: state);
}
