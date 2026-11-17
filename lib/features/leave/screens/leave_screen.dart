import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/leave/data/leave_repository.dart';
import 'package:instructor_app/features/leave/leave_text.dart';
import 'package:instructor_app/features/leave/screens/apply_leave_screen.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// The web's /leave (ATT-09, ATT-11): apply for leave with dates, a reason
/// and an optional photo or PDF, and "My leave" with the answers and
/// Withdraw; for those who approve (the server says, `can_approve`), "To
/// approve" with Approve and Don't approve and a comment.
class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  /// Null until chosen: the web opens "To approve" when there is no own
  /// leave to show.
  bool? _approvals;
  String _filter = 'PENDING';

  Future<void> _apply(BuildContext context, WidgetRef ref, MyLeave mine) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    // Over the whole screen, not inside the shell.
    final saved = await Navigator.of(context, rootNavigator: true)
        .push<LeaveRequest?>(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => ApplyLeaveScreen(today: mine.today),
          ),
        );
    if (saved == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          saved.status == 'APPROVED'
              ? l10n.leaveFormApprovedAtOnce
              : l10n.leaveFormApplied,
        ),
      ),
    );
    ref.invalidate(myLeaveProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final mine = ref.watch(myLeaveProvider);
    final approving = mine.value?.canApprove ?? false;
    final waiting = approving
        ? ref.watch(leaveApprovalsProvider('PENDING')).value?.length ?? 0
        : 0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: mine.when(
          loading: () => LoadingView(semanticsLabel: l10n.leaveTitle),
          error: (_, _) => ErrorView(
            title: l10n.leaveLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(myLeaveProvider),
          ),
          data: (mine) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myLeaveProvider);
              if (mine.canApprove) ref.invalidate(leaveApprovalsProvider);
              await ref
                  .read(myLeaveProvider.future)
                  .then<void>((_) {}, onError: (Object _) {});
            },
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(l10n.leaveTitle, style: text.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  l10n.leaveIntro,
                  style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                ),
                if (mine.canApply) ...[
                  const SizedBox(height: AppSpacing.md),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: AppButton(
                      key: const Key('apply-leave'),
                      label: l10n.leaveApply,
                      icon: Icons.add,
                      onPressed: () => _apply(context, ref, mine),
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (mine.canApprove && mine.showsMine) ...[
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      ChoiceChip(
                        key: const Key('tab-mine'),
                        label: Text(l10n.leaveTabsMine),
                        selected: !(_approvals ?? false),
                        onSelected: (_) => setState(() => _approvals = false),
                      ),
                      ChoiceChip(
                        key: const Key('tab-approvals'),
                        label: Text(
                          waiting > 0
                              ? '${l10n.leaveTabsApprovals} · '
                                    '${OrgTime.number(waiting, Localizations.localeOf(context).languageCode)}'
                              : l10n.leaveTabsApprovals,
                        ),
                        selected: _approvals ?? false,
                        onSelected: (_) => setState(() => _approvals = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (mine.canApprove && (_approvals ?? !mine.showsMine))
                  ..._approvalsList(context)
                else ...[
                  Text(l10n.leaveTabsMine, style: text.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  ..._mineList(context, mine),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _mineList(BuildContext context, MyLeave mine) {
    final l10n = context.l10n;
    return [
      if (mine.requests.isEmpty)
        SizedBox(
          height: 280,
          child: EmptyView(
            icon: Icons.beach_access_outlined,
            title: l10n.leaveEmptyMine,
            message: l10n.leaveEmptyMineHint,
          ),
        )
      else
        for (final r in mine.requests) ...[
          _RequestCard(request: r),
          const SizedBox(height: AppSpacing.sm),
        ],
    ];
  }

  List<Widget> _approvalsList(BuildContext context) {
    final l10n = context.l10n;
    final list = ref.watch(leaveApprovalsProvider(_filter));
    return [
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: DropdownButtonFormField<String>(
            key: const Key('approvals-filter'),
            initialValue: _filter,
            isExpanded: true,
            decoration: InputDecoration(labelText: l10n.leaveFilter),
            items: [
              DropdownMenuItem(
                value: 'PENDING',
                child: Text(l10n.leaveFiltersPENDING),
              ),
              DropdownMenuItem(
                value: 'DECIDED',
                child: Text(l10n.leaveFiltersDECIDED),
              ),
              DropdownMenuItem(value: 'ALL', child: Text(l10n.leaveFiltersALL)),
            ],
            onChanged: (v) => setState(() => _filter = v ?? 'PENDING'),
          ),
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      ...list.when(
        loading: () => [
          SizedBox(
            height: 200,
            child: LoadingView(semanticsLabel: l10n.leaveTabsApprovals),
          ),
        ],
        error: (_, _) => [
          SizedBox(
            height: 260,
            child: ErrorView(
              title: l10n.leaveLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(leaveApprovalsProvider(_filter)),
            ),
          ),
        ],
        data: (requests) => requests.isEmpty
            ? [
                SizedBox(
                  height: 260,
                  child: EmptyView(
                    icon: Icons.task_alt,
                    title: _filter == 'PENDING'
                        ? l10n.leaveEmptyApprovals
                        : l10n.leaveEmptyDecided,
                    message: _filter == 'PENDING'
                        ? l10n.leaveEmptyApprovalsHint
                        : null,
                  ),
                ),
              ]
            : [
                for (final r in requests) ...[
                  _RequestCard(request: r, approval: true),
                  const SizedBox(height: AppSpacing.sm),
                ],
              ],
      ),
    ];
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request, this.approval = false});

  final LeaveRequest request;

  /// In "To approve": who asked, and Approve / Don't approve.
  final bool approval;

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final done = await showDialog<bool>(
      context: context,
      builder: (_) => _DecisionDialog(request: request, approve: approve),
    );
    if (done != true) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(approve ? l10n.leaveApproved : l10n.leaveRejected),
      ),
    );
    ref.invalidate(leaveApprovalsProvider);
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final messenger = ScaffoldMessenger.of(context);
    final dates = leaveDates(request.fromDate, request.toDate, language);
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(l10n.leaveWithdrawTitle),
        content: Text(l10n.leaveWithdrawDescription(dates)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () => Navigator.of(dialog).pop(false),
            child: Text(l10n.leaveCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: Text(l10n.leaveWithdraw),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ref.read(leaveRepositoryProvider).withdraw(request.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.leaveWithdrawn)));
    } on ApiException catch (e) {
      if (!context.mounted) return;
      final known = leaveErrorText(l10n, e, language);
      if (known != null) {
        messenger.showSnackBar(SnackBar(content: Text(known)));
      } else if (!await handleCommonApiError(
        context,
        e,
        session: ref.read(sessionProvider),
      )) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      ref
        ..invalidate(myLeaveProvider)
        ..invalidate(leaveApprovalsProvider);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final r = request;
    final dates = leaveDates(r.fromDate, r.toDate, language);
    final answer = r.status == 'CANCELLED' && r.cancelledBy != null
        ? l10n.leaveWithdrawnBy(r.cancelledBy!.name)
        : r.status != 'PENDING' && r.decidedBy != null
        ? (r.decisionNote != null && r.decisionNote!.isNotEmpty
              ? l10n.leaveDecidedBy(r.decidedBy!.name, r.decisionNote!)
              : l10n.leaveDecidedByNoNote(r.decidedBy!.name))
        : null;
    final tone = switch (r.status) {
      'APPROVED' => StatusTone.success,
      'REJECTED' => StatusTone.danger,
      'CANCELLED' => StatusTone.neutral,
      _ => StatusTone.warning,
    };
    return AppCard(
      key: Key('leave-${r.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (approval && r.person != null)
            Text.rich(
              TextSpan(
                text: '${r.person!.name} ',
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                children: [
                  TextSpan(
                    text: r.className != null && r.className!.isNotEmpty
                        ? r.className
                        : r.personType == 'TEACHER'
                        ? l10n.leavePersonTypeTEACHER
                        : l10n.leavePersonTypeSTUDENT,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '$dates · ${l10n.leaveDays(r.schoolDays)}',
                  style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              StatusPill(label: leaveStatus(l10n, r.status), tone: tone),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(r.reason, style: text.bodyMedium),
          if (r.appliedBy != null &&
              r.person != null &&
              r.appliedBy!.id != r.person!.id)
            Text(
              l10n.leaveAppliedBy(r.appliedBy!.name),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
          if (answer != null)
            Text(
              answer,
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
          if (approval && r.canDecide) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                Semantics(
                  label: l10n.leaveApproveNamed(r.person?.name ?? ''),
                  button: true,
                  excludeSemantics: true,
                  child: AppButton(
                    key: Key('approve-${r.id}'),
                    label: l10n.leaveApprove,
                    onPressed: () => _decide(context, ref, approve: true),
                  ),
                ),
                Semantics(
                  label: l10n.leaveRejectNamed(r.person?.name ?? ''),
                  button: true,
                  excludeSemantics: true,
                  child: AppButton(
                    key: Key('reject-${r.id}'),
                    label: l10n.leaveReject,
                    variant: AppButtonVariant.secondary,
                    onPressed: () => _decide(context, ref, approve: false),
                  ),
                ),
              ],
            ),
          ],
          if (r.fileId != null || (r.canCancel && !r.canDecide))
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (r.fileId != null)
                  Semantics(
                    label: l10n.leaveOpenAttachment(
                      r.fileName ?? l10n.leaveAttachment,
                    ),
                    button: true,
                    excludeSemantics: true,
                    child: TextButton.icon(
                      icon: const Icon(Icons.attach_file),
                      onPressed: () => openFile(context, ref, r.fileId!),
                      label: Text(l10n.leaveAttachment),
                    ),
                  ),
                if (r.canCancel && !r.canDecide)
                  Semantics(
                    label: l10n.leaveWithdrawNamed(dates),
                    button: true,
                    excludeSemantics: true,
                    child: TextButton(
                      onPressed: () => _withdraw(context, ref),
                      child: Text(l10n.leaveWithdraw),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Approve (an optional comment) or Don't approve (a comment is needed), as
/// the web's dialog. Pops true once the server has it. Owns its text field,
/// so it is not disposed while the dialog is still closing.
class _DecisionDialog extends ConsumerStatefulWidget {
  const _DecisionDialog({required this.request, required this.approve});

  final LeaveRequest request;
  final bool approve;

  @override
  ConsumerState<_DecisionDialog> createState() => _DecisionDialogState();
}

class _DecisionDialogState extends ConsumerState<_DecisionDialog> {
  final _note = TextEditingController();
  String? _problem;
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final note = _note.text.trim();
    if (!widget.approve && note.length < 3) {
      setState(() => _problem = l10n.leaveNoteRequired);
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await ref
          .read(leaveRepositoryProvider)
          .decide(widget.request.id, approve: widget.approve, note: note);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _problem =
            leaveErrorText(l10n, e, language) ?? apiErrorText(l10n, e),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final colors = AppColors.of(context);
    final r = widget.request;
    final name = r.person?.name ?? '';
    return AlertDialog(
      title: Text(
        widget.approve
            ? l10n.leaveApproveTitle(name)
            : l10n.leaveRejectTitle(name),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.leaveDecisionHint(
                leaveDates(r.fromDate, r.toDate, language),
                l10n.leaveDays(r.schoolDays),
                r.reason,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const Key('decision-note'),
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: l10n.leaveNoteLabel(name),
                helperText: widget.approve
                    ? l10n.leaveNoteOptional
                    : l10n.leaveNoteRequired,
              ),
              onChanged: (_) {
                if (_problem != null) setState(() => _problem = null);
              },
            ),
            if (_problem != null)
              Text(
                _problem!,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colors.danger),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.leaveCancel),
        ),
        AppButton(
          key: const Key('decision-save'),
          label: widget.approve ? l10n.leaveApprove : l10n.leaveReject,
          variant: widget.approve
              ? AppButtonVariant.primary
              : AppButtonVariant.danger,
          loading: _saving,
          onPressed: _save,
        ),
      ],
    );
  }
}
