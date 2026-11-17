import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/leave/data/leave_repository.dart';
import 'package:instructor_app/features/leave/leave_text.dart';
import 'package:instructor_app/features/leave/screens/apply_leave_screen.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// The web's /leave for a student (ATT-09, ATT-11): apply for leave with
/// dates, a reason and an optional photo or PDF, and "My leave" with the
/// answers and Withdraw. Approving others' leave is Stage 2 (teachers).
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key});

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
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final mine = ref.watch(myLeaveProvider);
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
                Text(l10n.leaveTabsMine, style: text.titleMedium),
                const SizedBox(height: AppSpacing.sm),
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request});

  final LeaveRequest request;

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
      ref.invalidate(myLeaveProvider);
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
          if (r.fileId != null || r.canCancel)
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
                if (r.canCancel)
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
