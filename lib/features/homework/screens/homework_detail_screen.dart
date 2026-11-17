import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/attachment_field.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/text/html_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/homework/data/homework.dart';
import 'package:instructor_app/features/homework/homework_text.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// A homework's page for a student (the web's HomeworkDetail and
/// HomeworkMyWork): what to do, the teacher's files, then hand it in (a
/// typed answer and/or photos and files), every version handed in, and the
/// score once published. Paper homework is handed to the teacher instead.
class HomeworkDetailScreen extends ConsumerWidget {
  const HomeworkDetailScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    if (ref.watch(sessionProvider)?.role != 'STUDENT') {
      return EmptyView(
        icon: Icons.public,
        title: l10n.homeworkTitle,
        message: l10n.appNotYetBody,
      );
    }
    final homework = ref.watch(homeworkProvider(id));
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: homework.when(
          loading: () => LoadingView(semanticsLabel: l10n.homeworkTitle),
          error: (e, _) => e is ApiException && e.statusCode == 404
              ? EmptyView(
                  icon: Icons.assignment_late_outlined,
                  title: l10n.homeworkNotFound,
                )
              : ErrorView(
                  title: l10n.homeworkLoadFailed,
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () => ref.invalidate(homeworkProvider(id)),
                ),
          data: (h) {
            if (h == null) {
              return EmptyView(
                icon: Icons.assignment_late_outlined,
                title: l10n.homeworkNotFound,
              );
            }
            final (due, tone) = dueText(l10n, h.dueAt, language);
            final instructions = h.instructionsHtml == null
                ? ''
                : htmlToText(h.instructionsHtml!);
            final type = switch (h.type) {
              'TEXT' => l10n.homeworkEditorTypesTEXT,
              'PAPER' => l10n.homeworkEditorTypesPAPER,
              _ => l10n.homeworkEditorTypesFILE,
            };
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                Text(h.title, style: text.headlineSmall),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: StatusPill(label: due, tone: tone),
                ),
                const SizedBox(height: AppSpacing.md),
                for (final (label, value) in [
                  (l10n.homeworkDetailSubject, h.subject),
                  (l10n.homeworkDetailType, type),
                  (
                    l10n.homeworkDetailMarks,
                    h.totalMarks == null
                        ? l10n.homeworkDetailNotScored
                        : OrgTime.number(h.totalMarks!, language),
                  ),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 120,
                          child: Text(
                            label,
                            style: text.bodyMedium?.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ),
                        Expanded(child: Text(value, style: text.bodyMedium)),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.homeworkDetailInstructions,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SelectableText(
                        instructions.isEmpty
                            ? l10n.homeworkDetailNoInstructions
                            : instructions,
                        style: instructions.isEmpty
                            ? text.bodyMedium?.copyWith(color: colors.inkMuted)
                            : text.bodyMedium,
                      ),
                    ],
                  ),
                ),
                if (h.attachments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          l10n.homeworkDetailAttachments,
                          style: text.titleMedium,
                        ),
                        for (final f in h.attachments)
                          _FileTile(file: f, fallback: l10n.homeworkDetailFile),
                      ],
                    ),
                  ),
                ],
                if (h.status == 'PUBLISHED') ...[
                  const SizedBox(height: AppSpacing.md),
                  _MyWork(homework: h),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FileTile extends ConsumerWidget {
  const _FileTile({required this.file, required this.fallback});

  final HomeworkFile file;
  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      file.isImage ? Icons.image_outlined : Icons.insert_drive_file_outlined,
    ),
    title: Text(file.name ?? fallback),
    trailing: const Icon(Icons.open_in_new),
    onTap: () => openFile(context, ref, file.id),
  );
}

/// The student's side: hand in, the versions, the score.
class _MyWork extends ConsumerStatefulWidget {
  const _MyWork({required this.homework});

  final Homework homework;

  @override
  ConsumerState<_MyWork> createState() => _MyWorkState();
}

class _MyWorkState extends ConsumerState<_MyWork> {
  final _answer = TextEditingController();
  List<UploadedFile> _files = const [];
  bool _uploading = false;
  bool _sending = false;
  String? _error;

  /// Starts a new attachment list after a hand-in.
  int _round = 0;

  Homework get _h => widget.homework;

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  Future<void> _submit(MySubmissions mine) async {
    final l10n = context.l10n;
    final empty = _h.type == 'FILE'
        ? _files.isEmpty
        : _h.type == 'TEXT' && _answer.text.trim().isEmpty;
    if (empty) {
      setState(() => _error = l10n.homeworkErrorsHOMEWORKSUBMISSIONEMPTY);
      return;
    }
    setState(() {
      _error = null;
      _sending = true;
    });
    try {
      final saved = await ref
          .read(homeworkRepositoryProvider)
          .submit(
            _h.id,
            text: _answer.text,
            fileIds: [for (final f in _files) f.id],
          );
      if (!mounted) return;
      _answer.clear();
      setState(() {
        _files = const [];
        _round++;
      });
      ref
        ..invalidate(mySubmissionsProvider(_h.id))
        ..invalidate(myHomeworkProvider);
      if (saved.handIns.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.homeworkMyWorkHandedIn)));
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      final known = submitErrorText(l10n, e.code, maxFiles: mine.maxFiles);
      if (known != null) {
        setState(() => _error = known);
      } else if (!await handleCommonApiError(
        context,
        e,
        session: ref.read(sessionProvider),
      )) {
        if (mounted) setState(() => _error = apiErrorText(l10n, e));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final mine = ref.watch(mySubmissionsProvider(_h.id));
    return AppCard(
      key: const Key('my-work'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.homeworkMyWorkTitle, style: text.titleMedium),
          const SizedBox(height: AppSpacing.md),
          ...mine.when(
            loading: () => [
              SizedBox(
                height: 120,
                child: LoadingView(semanticsLabel: l10n.homeworkMyWorkTitle),
              ),
            ],
            error: (_, _) => [
              SizedBox(
                height: 240,
                child: ErrorView(
                  title: l10n.homeworkLoadFailed,
                  retryLabel: l10n.uiErrorRetry,
                  onRetry: () => ref.invalidate(mySubmissionsProvider(_h.id)),
                ),
              ),
            ],
            data: (mine) => [
              if (_h.type == 'PAPER')
                Text(l10n.homeworkMyWorkPaper, style: text.bodyMedium)
              else if (mine.canSubmit)
                ..._form(mine)
              else if (submitErrorText(
                    l10n,
                    mine.blockedBy,
                    maxFiles: mine.maxFiles,
                  )
                  case final why?)
                Text(why, style: text.bodyMedium),
              if (mine.score != null) ...[
                const SizedBox(height: AppSpacing.md),
                _Score(score: mine.score!),
              ],
              if (mine.handIns.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.lg),
                Text(l10n.homeworkMyWorkHandedIn, style: text.titleSmall),
                for (final v in mine.handIns) _Version(handIn: v),
              ],
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: text.bodyMedium?.copyWith(color: colors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _form(MySubmissions mine) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return [
      if (mine.lateNow)
        Text(
          l10n.homeworkMyWorkLateWarning,
          style: text.bodyMedium?.copyWith(color: colors.warning),
        ),
      if (_h.type == 'TEXT') ...[
        AppTextField(
          key: const Key('homework-answer'),
          label: l10n.homeworkMyWorkAnswer,
          controller: _answer,
          maxLines: 8,
          maxLength: 20000,
          enabled: !_sending,
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      AttachmentField(
        key: ValueKey('attach-$_round'),
        label: _h.type == 'TEXT'
            ? l10n.homeworkMyWorkFilesOptional
            : l10n.homeworkMyWorkFiles,
        purpose: FilePurpose.homework,
        maxFiles: mine.maxFiles,
        enabled: !_sending,
        onChanged: (files) => setState(() => _files = files),
        onBusyChanged: (busy) => setState(() => _uploading = busy),
      ),
      Text(
        l10n.homeworkMyWorkFilesAccept(mine.maxFiles),
        style: text.bodySmall?.copyWith(color: colors.inkMuted),
      ),
      const SizedBox(height: AppSpacing.md),
      AppButton(
        key: const Key('homework-submit'),
        label: mine.handIns.isEmpty
            ? l10n.homeworkMyWorkSubmit
            : l10n.homeworkMyWorkSubmitAgain,
        onPressed: _uploading ? null : () => _submit(mine),
        loading: _sending,
        expand: true,
      ),
      if (mine.handIns.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: Text(
            l10n.homeworkMyWorkLeft(mine.submissionsLeft),
            style: text.bodySmall?.copyWith(color: colors.inkMuted),
          ),
        ),
    ];
  }
}

class _Version extends ConsumerWidget {
  const _Version({required this.handIn});

  final HandIn handIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final status = switch (handIn.status) {
      'RETURNED' => l10n.homeworkMyWorkStatusesRETURNED,
      'SCORED' => l10n.homeworkMyWorkStatusesSCORED,
      _ => l10n.homeworkMyWorkStatusesSUBMITTED,
    };
    return Padding(
      key: Key('version-${handIn.version}'),
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                l10n.homeworkMyWorkVersion(handIn.version),
                style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (handIn.submittedAt != null)
                Text(
                  OrgTime.dateTime(handIn.submittedAt!, language),
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              StatusPill(label: status),
              if (handIn.isLate)
                StatusPill(
                  label: l10n.homeworkMyWorkLate(handIn.lateMinutes ?? 0),
                  tone: StatusTone.warning,
                ),
            ],
          ),
          if (handIn.text != null && handIn.text!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: SelectableText(handIn.text!, style: text.bodyMedium),
            ),
          for (final f in handIn.files)
            _FileTile(file: f, fallback: l10n.homeworkMyWorkFile),
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({required this.score});

  final HomeworkScore score;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final label = scoreText(score, language);
    String rating(String key) => switch (key) {
      'neatness' => l10n.homeworkSubmissionsRatingsNeatness,
      'effort' => l10n.homeworkSubmissionsRatingsEffort,
      _ => l10n.homeworkSubmissionsRatingsOnTime,
    };
    return Container(
      key: const Key('homework-score'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.canvas,
        borderRadius: AppRadius.inputAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.homeworkMyWorkScore, style: text.titleSmall),
          if (score.isMissing)
            StatusPill(
              label: l10n.homeworkMyWorkNotHandedIn,
              tone: StatusTone.danger,
            ),
          if (label != null) Text(label, style: text.titleLarge),
          if (score.penalty > 0 && score.rawScore != null)
            Text(
              l10n.homeworkMyWorkPenalty(score.rawScore!, score.penalty),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
          if (score.feedback != null && score.feedback!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(score.feedback!, style: text.bodyMedium),
            ),
          if (score.ratings.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final MapEntry(:key, :value) in score.ratings.entries)
                  StatusPill(
                    label: l10n.homeworkMyWorkRating(rating(key), value),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
