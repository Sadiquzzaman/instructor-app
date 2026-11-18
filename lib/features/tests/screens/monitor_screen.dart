import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';
import 'package:instructor_app/features/tests/data/monitor.dart';
import 'package:instructor_app/features/tests/screens/teacher_tests_screens.dart';

/// The web's words for a proctoring event ("tab-switch" → "Switched tab").
String monitorEventText(AppLocalizations l10n, String type) => switch (type) {
  'tab-switch' => l10n.monitorEventsTabSwitch,
  'window-blur' => l10n.monitorEventsWindowBlur,
  'fullscreen-exit' => l10n.monitorEventsFullscreenExit,
  'no-face' => l10n.monitorEventsNoFace,
  'multiple-faces' => l10n.monitorEventsMultipleFaces,
  'looking-away' => l10n.monitorEventsLookingAway,
  'phone-detected' => l10n.monitorEventsPhoneDetected,
  'paste-attempt' => l10n.monitorEventsPasteAttempt,
  'restricted-action' => l10n.monitorEventsRestrictedAction,
  'voice-detected' => l10n.monitorEventsVoiceDetected,
  'idle-too-long' => l10n.monitorEventsIdleTooLong,
  'devtools-open' => l10n.monitorEventsDevtoolsOpen,
  'screen-sharing' => l10n.monitorEventsScreenSharing,
  'camera-blocked' => l10n.monitorEventsCameraBlocked,
  'screen-share-stopped' => l10n.monitorEventsScreenShareStopped,
  'double-display' => l10n.monitorEventsDoubleDisplay,
  'monitoring-lost' => l10n.monitorEventsMonitoringLost,
  'monitoring-back' => l10n.monitorEventsMonitoringBack,
  'teacher-warning' => l10n.monitorEventsTeacherWarning,
  'teacher-ended' => l10n.monitorEventsTeacherEnded,
  _ => type,
};

String _status(AppLocalizations l10n, String s) => switch (s) {
  'SUBMITTED' => l10n.monitorStatusSUBMITTED,
  'ENDED' => l10n.monitorStatusENDED,
  'DISCONNECTED' => l10n.monitorStatusDISCONNECTED,
  'LOST' => l10n.monitorStatusLOST,
  _ => l10n.monitorStatusWRITING,
};

StatusTone _statusTone(String s) => switch (s) {
  'WRITING' => StatusTone.success,
  'DISCONNECTED' => StatusTone.warning,
  'ENDED' || 'LOST' => StatusTone.danger,
  _ => StatusTone.neutral,
};

/// The live monitor (the web's /tests/:id/monitor; plan §7.4: phones and
/// tablets): a tile per student taking the test with their status, time
/// left, flags and latest flag, its border coloured by risk; live through
/// the test connection, and read again every 30 seconds. A tile opens the
/// student's timeline, to warn them or end their test with a reason.
class MonitorScreen extends ConsumerStatefulWidget {
  const MonitorScreen({required this.examId, super.key});

  final String examId;

  @override
  ConsumerState<MonitorScreen> createState() => _MonitorScreenState();
}

class _MonitorScreenState extends ConsumerState<MonitorScreen> {
  Map<String, MonitorSession>? _sessions;
  Object? _error;
  bool _connected = false;
  late final MonitorLive _live = ref.read(monitorLiveProvider);
  final _subs = <StreamSubscription<Object>>[];
  Timer? _reload;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _load();
    _subs
      ..add(_live.connected.listen((c) => setState(() => _connected = c)))
      ..add(_live.events.listen(_onEvent));
    _live.join(widget.examId);
    _reload = Timer.periodic(const Duration(seconds: 30), (_) => _load());
    // Time left counts down.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _reload?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await ref
          .read(monitorRepositoryProvider)
          .sessions(widget.examId);
      if (!mounted) return;
      setState(() {
        _sessions = {for (final s in list) s.studentId: s};
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _onEvent(MonitorEvent e) {
    if (!mounted) return;
    switch (e) {
      case SessionJoined():
        _load();
      case SessionChanged(:final studentId):
        final s = _sessions?[studentId];
        if (s == null) return;
        setState(
          () => _sessions![studentId] = s.copyWith(
            status: e.status,
            flagCount: e.flagCount,
            latestFlag: e.flag,
          ),
        );
      case MonitorAlert(:final name, :final flagCount):
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${l10n.monitorAlertTitle(name)}. ${l10n.monitorAlertDetail(flagCount)}',
            ),
          ),
        );
    }
  }

  Future<void> _open(MonitorSession s) async {
    final ended = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _StudentScreen(examId: widget.examId, session: s),
      ),
    );
    if (ended == true && mounted) {
      setState(() => _sessions![s.studentId] = s.copyWith(status: 'ENDED'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final name = ref.watch(teacherTestProvider(widget.examId)).value?.name;
    final sessions = _sessions?.values.toList();
    final e = _error;
    final body = sessions == null && e != null
        ? SizedBox(
            height: 320,
            child: ErrorView(
              title: e is ApiException && e.statusCode == 403
                  ? l10n.monitorNotAllowed
                  : l10n.monitorLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: _load,
            ),
          )
        : sessions == null
        ? SizedBox(
            height: 220,
            child: LoadingView(semanticsLabel: l10n.monitorTitle),
          )
        : sessions.isEmpty
        ? SizedBox(
            height: 280,
            child: EmptyView(
              icon: Icons.groups_outlined,
              title: l10n.monitorEmpty,
              message: l10n.monitorEmptyHint,
            ),
          )
        : _tiles(sessions);
    final counts = sessions == null
        ? null
        : (
            writing: sessions.where((s) => s.status == 'WRITING').length,
            lost: sessions.where((s) => s.status == 'LOST').length,
            done: sessions
                .where((s) => s.status == 'SUBMITTED' || s.status == 'ENDED')
                .length,
          );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(l10n.monitorTitle, style: text.headlineSmall),
                  ),
                  IconButton(
                    key: const Key('monitor-refresh'),
                    tooltip: l10n.monitorRefresh,
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
              Text(
                [
                  ?name,
                  _connected ? l10n.monitorLive : l10n.monitorConnecting,
                ].join(' · '),
                key: const Key('monitor-connection'),
                style: text.bodySmall?.copyWith(color: colors.inkMuted),
              ),
              if (counts != null && sessions!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  l10n.monitorSummary(counts.writing, counts.lost, counts.done),
                  style: text.bodyMedium,
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              body,
            ],
          ),
        ),
      ),
    );
  }

  Widget _tiles(List<MonitorSession> sessions) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    String left(DateTime? deadline) {
      if (deadline == null) return '—';
      final s = deadline.difference(DateTime.now()).inSeconds;
      return l10n.monitorTimeLeft(OrgTime.clock(s < 0 ? 0 : s, language));
    }

    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 900
            ? 3
            : (box.maxWidth >= AppSpacing.tabletBreakpoint ? 2 : 1);
        final width = (box.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final s in sessions)
              SizedBox(
                width: width,
                child: Semantics(
                  label: l10n.monitorTileLabel(
                    s.name,
                    _status(l10n, s.status),
                    s.flagCount,
                  ),
                  button: true,
                  excludeSemantics: true,
                  child: Material(
                    color: colors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.cardAll,
                      side: BorderSide(
                        width: 2,
                        color: switch (riskOf(s.flagCount)) {
                          'high' => colors.danger,
                          'some' => colors.warning,
                          _ => colors.border,
                        },
                      ),
                    ),
                    child: InkWell(
                      key: Key('tile-${s.studentId}'),
                      borderRadius: AppRadius.cardAll,
                      onTap: () => _open(s),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: text.titleSmall,
                                  ),
                                ),
                                StatusPill(
                                  label: _status(l10n, s.status),
                                  tone: _statusTone(s.status),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.writing ? left(s.deadline) : '—',
                                    style: text.bodySmall?.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                                ),
                                Text(
                                  l10n.monitorFlags(s.flagCount),
                                  style: text.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              s.latestFlag == null
                                  ? l10n.monitorNoFlags
                                  : monitorEventText(l10n, s.latestFlag!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.bodySmall?.copyWith(
                                color: colors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One student: the timeline of flags and events, a warning, or ending
/// their test with a reason. Returns true when it was ended.
class _StudentScreen extends ConsumerStatefulWidget {
  const _StudentScreen({required this.examId, required this.session});

  final String examId;
  final MonitorSession session;

  @override
  ConsumerState<_StudentScreen> createState() => _StudentScreenState();
}

class _StudentScreenState extends ConsumerState<_StudentScreen> {
  List<TimelineEvent>? _timeline;
  final _warning = TextEditingController();
  final _reason = TextEditingController();
  bool _ending = false;
  bool _busy = false;

  MonitorSession get s => widget.session;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _warning.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await ref
          .read(monitorRepositoryProvider)
          .timeline(widget.examId, s.studentId);
      if (mounted) setState(() => _timeline = t);
    } catch (_) {
      if (mounted) setState(() => _timeline = const []);
    }
  }

  Future<void> _send({required bool end}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final repo = ref.read(monitorRepositoryProvider);
      if (end) {
        await repo.end(widget.examId, s.studentId, _reason.text);
        messenger.showSnackBar(SnackBar(content: Text(l10n.monitorEnded)));
        navigator.pop(true);
        return;
      }
      await repo.warn(widget.examId, s.studentId, _warning.text);
      messenger.showSnackBar(SnackBar(content: Text(l10n.monitorWarned)));
      _warning.clear();
      await _load();
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
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.name)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: StatusPill(
                  label: _status(l10n, s.status),
                  tone: _statusTone(s.status),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.monitorTimeline, style: text.titleMedium),
              if (_timeline == null)
                const LinearProgressIndicator()
              else if (_timeline!.isEmpty)
                Text(
                  l10n.monitorNoFlags,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                )
              else
                for (final e in _timeline!)
                  Padding(
                    key: Key('event-${e.id}'),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 72,
                          child: Text(
                            e.at == null ? '' : OrgTime.time(e.at!, language),
                            style: text.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${monitorEventText(l10n, e.type)}'
                            '${e.type.startsWith('teacher-') && (e.message ?? '').isNotEmpty ? ': ${e.message}' : ''}',
                            style: e.source == 'SERVER'
                                ? text.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  )
                                : text.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
              if (s.writing) ...[
                const Divider(height: AppSpacing.xl),
                TextField(
                  key: const Key('warn-text'),
                  controller: _warning,
                  maxLength: 300,
                  minLines: 2,
                  maxLines: 4,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: l10n.monitorWarnLabel,
                    hintText: l10n.monitorWarnPlaceholder,
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton(
                    key: const Key('warn-send'),
                    onPressed: _busy || _warning.text.trim().isEmpty
                        ? null
                        : () => _send(end: false),
                    child: Text(l10n.monitorWarn),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (!_ending)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: const Key('end-open'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.danger,
                      ),
                      onPressed: () => setState(() => _ending = true),
                      child: Text(l10n.monitorEnd),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      border: Border.all(color: colors.danger),
                      borderRadius: AppRadius.cardAll,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          key: const Key('end-reason'),
                          controller: _reason,
                          maxLength: 300,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: l10n.monitorEndReason,
                            helperText: l10n.monitorEndHint,
                            helperMaxLines: 3,
                          ),
                        ),
                        Wrap(
                          alignment: WrapAlignment.end,
                          spacing: AppSpacing.sm,
                          children: [
                            TextButton(
                              onPressed: () => setState(() => _ending = false),
                              child: Text(l10n.monitorCancel),
                            ),
                            FilledButton(
                              key: const Key('end-confirm'),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.danger,
                              ),
                              onPressed: _busy || _reason.text.trim().isEmpty
                                  ? null
                                  : () => _send(end: true),
                              child: Text(l10n.monitorEndConfirm),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
