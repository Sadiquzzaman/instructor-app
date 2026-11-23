import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/files/file_picking.dart';
import 'package:instructor_app/core/files/file_uploader.dart';
import 'package:instructor_app/core/files/open_file.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/text/html_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/ielts/data/builder.dart';
import 'package:instructor_app/features/ielts/data/ielts.dart';
import 'package:instructor_app/features/ielts/data/ielts_tests.dart';
import 'package:instructor_app/features/ielts/screens/ielts_tests_screens.dart';
import 'package:instructor_app/features/ielts/screens/speaking_screens.dart';
import 'package:instructor_app/features/tests/data/exam_to_draft.dart';
import 'package:instructor_app/features/tests/data/test_draft.dart';

String groupTypeName(AppLocalizations l10n, String type) => switch (type) {
  'MCQ_SINGLE' => l10n.ieltsBuilderGroupTypesMCQSINGLE,
  'MCQ_MULTI' => l10n.ieltsBuilderGroupTypesMCQMULTI,
  'TFNG' => l10n.ieltsBuilderGroupTypesTFNG,
  'YNNG' => l10n.ieltsBuilderGroupTypesYNNG,
  'MATCH_HEADINGS' => l10n.ieltsBuilderGroupTypesMATCHHEADINGS,
  'MATCH_INFO' => l10n.ieltsBuilderGroupTypesMATCHINFO,
  'MATCH_FEATURES' => l10n.ieltsBuilderGroupTypesMATCHFEATURES,
  'MATCH_ENDINGS' => l10n.ieltsBuilderGroupTypesMATCHENDINGS,
  'SENTENCE_COMPLETION' => l10n.ieltsBuilderGroupTypesSENTENCECOMPLETION,
  'SUMMARY_COMPLETION' => l10n.ieltsBuilderGroupTypesSUMMARYCOMPLETION,
  'NOTE_COMPLETION' => l10n.ieltsBuilderGroupTypesNOTECOMPLETION,
  'TABLE_COMPLETION' => l10n.ieltsBuilderGroupTypesTABLECOMPLETION,
  'FLOWCHART_COMPLETION' => l10n.ieltsBuilderGroupTypesFLOWCHARTCOMPLETION,
  'FORM_COMPLETION' => l10n.ieltsBuilderGroupTypesFORMCOMPLETION,
  'DIAGRAM_LABEL' => l10n.ieltsBuilderGroupTypesDIAGRAMLABEL,
  _ => l10n.ieltsBuilderGroupTypesSHORTANSWER,
};

String _contentLabel(AppLocalizations l10n, String module) => switch (module) {
  'READING' => l10n.ieltsBuilderContentLabelREADING,
  'WRITING' => l10n.ieltsBuilderContentLabelWRITING,
  _ => l10n.ieltsBuilderContentLabelSPEAKING,
};

String _contentHint(AppLocalizations l10n, String module) => switch (module) {
  'READING' => l10n.ieltsBuilderContentHintREADING,
  'WRITING' => l10n.ieltsBuilderContentHintWRITING,
  _ => l10n.ieltsBuilderContentHintSPEAKING,
};

/// Picks one picture or recording and uploads it as an IELTS file.
Future<String?> _pickAndUpload(
  BuildContext context,
  WidgetRef ref, {
  required bool audio,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final picking = ref.read(filePickingProvider);
  final files = audio
      ? await picking.chooseFiles(['mp3', 'm4a', 'mp4', 'ogg', 'wav'])
      : await picking.choosePhotos(limit: 1);
  if (files.isEmpty) return null;
  final file = files.first;
  if (!FilePurpose.ielts.mimes.contains(file.mime)) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          audio ? l10n.ieltsBuilderAudioTypes : l10n.ieltsBuilderImageTypes,
        ),
      ),
    );
    return null;
  }
  try {
    final up = await ref
        .read(fileUploaderProvider)
        .upload(FilePurpose.ielts, file);
    return up.id;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    return null;
  }
}

/// The web's /ielts/tests/[id] (P10-03): one tab per module, a card per
/// part (title; the passage, task or Speaking questions; a Listening
/// recording; a Reading or Writing picture) and the Listening and Reading
/// question groups numbered 1–40. Publish lists what is missing. Published
/// or archived tests, and tests others made, are read-only.
class IeltsBuilderScreen extends ConsumerStatefulWidget {
  const IeltsBuilderScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<IeltsBuilderScreen> createState() => _IeltsBuilderScreenState();
}

class _IeltsBuilderScreenState extends ConsumerState<IeltsBuilderScreen> {
  List<Map<dynamic, dynamic>> _problems = const [];
  bool _busy = false;

  Future<void> _run(String path, String done, {bool openCopy = false}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .post('/ielts/tests/${widget.id}/$path');
      setState(() => _problems = const []);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(ieltsTestsProvider);
      if (openCopy) {
        final id = r.payload is Map ? (r.payload! as Map)['id'] : null;
        if (id != null) unawaited(router.push(ieltsTestRoute('$id')));
      } else {
        ref.invalidate(ieltsTestProvider(widget.id));
      }
    } on ApiException catch (e) {
      final d = e.details;
      if (e.code == 'IELTS_TEST_INCOMPLETE' &&
          d is Map &&
          d['problems'] is List) {
        setState(
          () => _problems = [
            for (final p in d['problems'] as List)
              if (p is Map) p,
          ],
        );
      } else {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _problemText(AppLocalizations l10n, Map<dynamic, dynamic> p) {
    final module = '${p['module']}';
    final m = ieltsModuleShort(l10n, module);
    final no = (p['part_no'] as num?)?.toInt();
    if (no == null) {
      return l10n.ieltsBuilderProblemsNOT40(m, (p['count'] as num?) ?? 0);
    }
    final part = ieltsPartName(l10n, module, no);
    return switch ('${p['problem']}') {
      'NO_RECORDING' => l10n.ieltsBuilderProblemsNORECORDING(part, m),
      'NO_QUESTIONS' => l10n.ieltsBuilderProblemsNOQUESTIONS(part, m),
      'NO_PICTURE' => l10n.ieltsBuilderProblemsNOPICTURE(part, m),
      _ => l10n.ieltsBuilderProblemsNOTEXT(part, m),
    };
  }

  Future<void> _details(IeltsTest t) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _DetailsForm(test: t),
    );
    if (saved == true) ref.invalidate(ieltsTestProvider(widget.id));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return ref
        .watch(ieltsTestProvider(widget.id))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.ieltsTestsPageTitle),
          error: (e, _) => ErrorView(
            title: e is ApiException && e.statusCode == 404
                ? l10n.ieltsBuilderNotFound
                : e is ApiException && e.statusCode == 403
                ? l10n.ieltsTestsNotAvailable
                : l10n.ieltsBuilderLoadFailed,
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(ieltsTestProvider(widget.id)),
          ),
          data: (t) {
            if (t == null) {
              return EmptyView(
                icon: Icons.quiz_outlined,
                title: l10n.ieltsBuilderNotFound,
              );
            }
            final editable = t.canEdit && t.status == 'DRAFT';
            return DefaultTabController(
              length: t.modules.length,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: NestedScrollView(
                    headerSliverBuilder: (context, _) => [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          0,
                        ),
                        sliver: SliverList.list(
                          children: [
                            Text(t.title, style: text.headlineSmall),
                            Text(
                              '${ieltsPurpose(l10n, t.purpose)} · '
                              '${ieltsTestTypeName(l10n, t.testType)}',
                              style: muted,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                StatusPill(
                                  label: ieltsTestStatusName(l10n, t.status),
                                  tone: ieltsTestStatusTone(t.status),
                                ),
                                if (t.canEdit)
                                  OutlinedButton(
                                    key: const Key('builder-details'),
                                    onPressed: () => _details(t),
                                    child: Text(l10n.ieltsBuilderDetails),
                                  ),
                                if (editable)
                                  FilledButton(
                                    key: const Key('builder-publish'),
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            'publish',
                                            l10n.ieltsBuilderPublished,
                                          ),
                                    child: Text(l10n.ieltsBuilderPublish),
                                  ),
                                if (t.canEdit && t.status != 'DRAFT')
                                  OutlinedButton(
                                    key: const Key('builder-unpublish'),
                                    onPressed: _busy
                                        ? null
                                        : () => _run(
                                            'unpublish',
                                            l10n.ieltsBuilderMovedToDrafts,
                                          ),
                                    child: Text(l10n.ieltsBuilderMoveToDrafts),
                                  ),
                                if (t.status == 'PUBLISHED')
                                  OutlinedButton(
                                    key: const Key('builder-openings'),
                                    onPressed: () => context.push(
                                      '${ieltsTestRoute(t.id)}/openings',
                                    ),
                                    child: Text(l10n.ieltsBuilderOpenings),
                                  ),
                                TextButton(
                                  key: const Key('builder-copy'),
                                  onPressed: _busy
                                      ? null
                                      : () => _run(
                                          'duplicate',
                                          l10n.ieltsTestsCopied,
                                          openCopy: true,
                                        ),
                                  child: Text(l10n.ieltsTestsCopy),
                                ),
                              ],
                            ),
                            if (t.needsReview)
                              Text(
                                l10n.ieltsTestsNeedsReview,
                                style: text.bodySmall?.copyWith(
                                  color: colors.warning,
                                ),
                              ),
                            if (!editable)
                              Text(
                                t.canEdit
                                    ? l10n.ieltsBuilderLockedPublished
                                    : l10n.ieltsBuilderLockedNotYours,
                                key: const Key('builder-locked'),
                                style: muted,
                              ),
                            if (_problems.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: AppSpacing.sm,
                                ),
                                child: AppCard(
                                  key: const Key('builder-problems'),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        l10n.ieltsBuilderNotReady,
                                        style: text.titleSmall,
                                      ),
                                      for (final p in _problems)
                                        Text(
                                          '• ${_problemText(l10n, p)}',
                                          style: text.bodySmall?.copyWith(
                                            color: colors.danger,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: TabBar(
                          isScrollable: true,
                          // From the edge, so all four fit on a phone.
                          tabAlignment: TabAlignment.start,
                          tabs: [
                            for (final m in t.modules)
                              Tab(
                                key: Key('builder-tab-$m'),
                                text: ieltsModuleShort(l10n, m),
                              ),
                          ],
                        ),
                      ),
                    ],
                    body: TabBarView(
                      children: [
                        for (final m in t.modules)
                          ListView(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            children: [
                              for (final p in t.parts)
                                if (p.module == m)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: AppSpacing.md,
                                    ),
                                    child: _PartCard(
                                      key: ValueKey(
                                        '${p.id}-${p.title}-${p.content}',
                                      ),
                                      test: t,
                                      part: p,
                                      editable: editable,
                                    ),
                                  ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
  }
}

class _PartCard extends ConsumerStatefulWidget {
  const _PartCard({
    required this.test,
    required this.part,
    required this.editable,
    super.key,
  });

  final IeltsTest test;
  final IeltsPart part;
  final bool editable;

  @override
  ConsumerState<_PartCard> createState() => _PartCardState();
}

class _PartCardState extends ConsumerState<_PartCard> {
  late final _title = TextEditingController(text: widget.part.title ?? '');

  /// The part's text as plain text, or null when it has formatting the app
  /// can't edit (Stage 4 plan §7.1 A).
  late final String? _plain = htmlToPlain(widget.part.content);
  late final _content = TextEditingController(text: _plain ?? '');
  bool _busy = false;

  IeltsPart get p => widget.part;
  String get _base => '/ielts/tests/${widget.test.id}';

  @override
  void dispose() {
    _title.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _send(Future<void> Function() request, String done) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await request();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      ref.invalidate(ieltsTestProvider(widget.test.id));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePart(Map<String, Object?> change) => _send(
    () => ref.read(apiClientProvider).put('$_base/parts/${p.id}', data: change),
    context.l10n.ieltsBuilderPartSaved,
  );

  Future<void> _upload({required bool audio}) async {
    setState(() => _busy = true);
    final id = await _pickAndUpload(context, ref, audio: audio);
    if (mounted) setState(() => _busy = false);
    if (id == null) return;
    await _savePart(audio ? {'audio_file_id': id} : {'image_file_id': id});
  }

  Future<void> _move(int i, int by) {
    final ids = [for (final g in p.groups) g.id];
    final x = ids[i];
    ids[i] = ids[i + by];
    ids[i + by] = x;
    return _send(
      () => ref
          .read(apiClientProvider)
          .put('$_base/parts/${p.id}/groups/order', data: {'group_ids': ids}),
      context.l10n.ieltsBuilderOrderSaved,
    );
  }

  Future<void> _remove(IeltsGroup g) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.ieltsBuilderRemoveGroupTitle),
        content: Text(l10n.ieltsBuilderRemoveGroupDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.ieltsBuilderCancel),
          ),
          FilledButton(
            key: const Key('group-remove-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.of(d).danger,
            ),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.ieltsBuilderRemove),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _send(
      () => ref.read(apiClientProvider).delete('$_base/groups/${g.id}'),
      l10n.ieltsBuilderGroupRemoved,
    );
  }

  Future<void> _editGroup(IeltsGroup? g) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _GroupForm(test: widget.test, part: p, group: g),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.ieltsBuilderGroupSaved)),
      );
      ref.invalidate(ieltsTestProvider(widget.test.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final edit = widget.editable;
    final hasGroups = p.module == 'LISTENING' || p.module == 'READING';
    final hasPicture = p.module == 'READING' || p.module == 'WRITING';
    final hasText = p.module != 'LISTENING';
    final formatted = hasText && _plain == null;
    return AppCard(
      key: Key('part-${p.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ieltsPartName(l10n, p.module, p.partNo),
            style: text.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          if (edit) ...[
            TextField(
              key: Key('part-title-${p.id}'),
              controller: _title,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: l10n.ieltsBuilderPartTitle,
              ),
            ),
            if (hasText && !formatted)
              TextField(
                key: Key('part-content-${p.id}'),
                controller: _content,
                minLines: 4,
                maxLines: 16,
                decoration: InputDecoration(
                  labelText: _contentLabel(l10n, p.module),
                  hintText: _contentHint(l10n, p.module),
                  alignLabelWithHint: true,
                ),
              ),
            if (formatted) ...[
              Text(l10n.appIeltsPartFormatted, style: muted),
              Text(htmlToText(p.content ?? ''), style: text.bodyMedium),
            ],
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton(
                key: Key('part-save-${p.id}'),
                onPressed: _busy
                    ? null
                    : () => _savePart({
                        'title': _title.text.trim().isEmpty
                            ? null
                            : _title.text.trim(),
                        if (hasText && !formatted)
                          'content': _content.text.trim().isEmpty
                              ? null
                              : plainToHtml(_content.text),
                      }),
                child: Text(l10n.ieltsBuilderSavePart),
              ),
            ),
          ] else ...[
            if (p.title?.isNotEmpty ?? false)
              Text(p.title!, style: text.titleSmall),
            if (p.content?.isNotEmpty ?? false)
              Text(htmlToText(p.content!), style: text.bodyMedium),
          ],
          if (p.module == 'LISTENING') ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (p.audioFileId != null)
                  // Played here, not in the browser (the content link needs
                  // no sign-in, but a browser may not play it).
                  RecordingButton(
                    key: Key('part-recording-${p.id}'),
                    fileId: p.audioFileId!,
                    label: l10n.ieltsBuilderRecording,
                  )
                else
                  Text(l10n.ieltsBuilderNoRecording, style: muted),
                if (edit)
                  OutlinedButton.icon(
                    key: Key('part-add-recording-${p.id}'),
                    icon: const Icon(Icons.audio_file_outlined),
                    label: Text(
                      p.audioFileId == null
                          ? l10n.ieltsBuilderAddRecording
                          : l10n.ieltsBuilderReplaceRecording,
                    ),
                    onPressed: _busy ? null : () => _upload(audio: true),
                  ),
              ],
            ),
          ],
          if (hasPicture) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (p.imageFileId != null)
                  TextButton.icon(
                    key: Key('part-picture-${p.id}'),
                    icon: const Icon(Icons.image_outlined),
                    label: Text(l10n.ieltsBuilderPicture),
                    onPressed: () => openFile(context, ref, p.imageFileId!),
                  ),
                if (edit)
                  OutlinedButton.icon(
                    key: Key('part-add-picture-${p.id}'),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(
                      p.imageFileId == null
                          ? l10n.ieltsBuilderAddPicture
                          : l10n.ieltsBuilderReplacePicture,
                    ),
                    onPressed: _busy ? null : () => _upload(audio: false),
                  ),
                if (edit && p.imageFileId != null)
                  TextButton(
                    key: Key('part-remove-picture-${p.id}'),
                    onPressed: _busy
                        ? null
                        : () => _savePart({'image_file_id': null}),
                    child: Text(l10n.ieltsBuilderRemovePicture),
                  ),
              ],
            ),
          ],
          if (hasGroups) ...[
            const SizedBox(height: AppSpacing.md),
            Text(l10n.ieltsBuilderGroups, style: text.titleSmall),
            if (p.groups.isEmpty) Text(l10n.ieltsBuilderNoGroups, style: muted),
            for (final (i, g) in p.groups.indexed)
              Container(
                key: Key('group-${g.id}'),
                margin: const EdgeInsets.only(top: AppSpacing.sm),
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: AppRadius.cardAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      g.numberFrom == null || g.numberTo == null
                          ? l10n.ieltsBuilderNoQuestionsYet
                          : g.numberFrom == g.numberTo
                          ? l10n.ieltsBuilderQuestionNumber(g.numberFrom!)
                          : l10n.ieltsBuilderQuestionRange(
                              g.numberFrom!,
                              g.numberTo!,
                            ),
                      style: text.labelLarge,
                    ),
                    Text(groupTypeName(l10n, g.type), style: muted),
                    Text(g.instruction, style: text.bodySmall),
                    for (final q in g.questions)
                      Text(
                        '${numbersText(q.numberFrom, q.numberTo)}. '
                        '${q.prompt ?? ''} → '
                        '${q.keys.isNotEmpty ? q.keys.join(', ') : q.accepted.join(' / ')}',
                        style: text.bodySmall,
                      ),
                    if (edit)
                      Wrap(
                        spacing: AppSpacing.xs,
                        children: [
                          TextButton(
                            key: Key('group-up-${g.id}'),
                            onPressed: _busy || i == 0
                                ? null
                                : () => _move(i, -1),
                            child: Text(
                              l10n.ieltsBuilderUp,
                              semanticsLabel: l10n.ieltsBuilderMoveUp(i + 1),
                            ),
                          ),
                          TextButton(
                            key: Key('group-down-${g.id}'),
                            onPressed: _busy || i == p.groups.length - 1
                                ? null
                                : () => _move(i, 1),
                            child: Text(
                              l10n.ieltsBuilderDown,
                              semanticsLabel: l10n.ieltsBuilderMoveDown(i + 1),
                            ),
                          ),
                          TextButton(
                            key: Key('group-edit-${g.id}'),
                            onPressed: () => _editGroup(g),
                            child: Text(
                              l10n.ieltsBuilderEdit,
                              semanticsLabel: l10n.ieltsBuilderEditGroupN(
                                i + 1,
                              ),
                            ),
                          ),
                          TextButton(
                            key: Key('group-remove-${g.id}'),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.danger,
                            ),
                            onPressed: () => _remove(g),
                            child: Text(
                              l10n.ieltsBuilderRemove,
                              semanticsLabel: l10n.ieltsBuilderRemoveGroupN(
                                i + 1,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            if (edit)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: Key('group-add-${p.id}'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.ieltsBuilderAddGroup),
                  onPressed: () => _editGroup(null),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// One question group (the web's GroupDrawer): type, instruction, word
/// limit or word box, the shared list, the text with gaps, a picture, and
/// the questions with their answers. The server checks the paper's rules
/// and the 40-number limit; its message is shown as it comes.
class _GroupForm extends ConsumerStatefulWidget {
  const _GroupForm({required this.test, required this.part, this.group});

  final IeltsTest test;
  final IeltsPart part;
  final IeltsGroup? group;

  @override
  ConsumerState<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends ConsumerState<_GroupForm> {
  late final _types = groupTypesFor(widget.part.module);
  late String _type = widget.group?.type ?? _types.first;
  late final _instruction = TextEditingController(
    text: widget.group?.instruction ?? '',
  );
  late int? _wordLimit = widget.group?.wordLimit;
  late List<IeltsOption> _shared = [
    ...(widget.group?.sharedOptions ?? blankOptions()),
  ];
  late bool _wordBox =
      widget.group?.sharedOptions != null &&
      ieltsGroupRules[widget.group!.type]?.choices == IeltsChoices.text;
  late final _gapText = TextEditingController(
    text: widget.group?.sharedText ?? '',
  );
  late String? _image = widget.group?.imageFileId;
  late final List<QuestionDraft> _questions = widget.group == null
      ? [QuestionDraft()]
      : [
          for (final q in widget.group!.questions)
            QuestionDraft(
              id: q.id,
              prompt: q.prompt ?? '',
              options: q.options == null ? null : [...q.options!],
              keys: [...q.keys],
              accepted: [...q.accepted],
            ),
        ];
  bool _busy = false;

  @override
  void dispose() {
    _instruction.dispose();
    _gapText.dispose();
    super.dispose();
  }

  ({IeltsChoices choices, List<String> modules, List<String>? fixed})
  get _rule => ieltsGroupRules[_type]!;
  bool get _usesShared =>
      _rule.choices == IeltsChoices.shared ||
      (_rule.choices == IeltsChoices.text && _wordBox);
  bool get _writes => _rule.choices == IeltsChoices.text && !_wordBox;

  List<String> _choicesFor(QuestionDraft q) => switch (_rule.choices) {
    IeltsChoices.question => [for (final o in q.options) o.key],
    IeltsChoices.fixed => _rule.fixed ?? const [],
    _ => _usesShared ? [for (final o in _shared) o.key] : const [],
  };

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    final body = groupBody(
      type: _type,
      instruction: _instruction.text,
      wordLimit: _wordLimit,
      wordBox: _wordBox,
      sharedOptions: _shared,
      sharedText: _gapText.text,
      imageFileId: _image,
      questions: _questions,
    );
    final base = '/ielts/tests/${widget.test.id}';
    try {
      final api = ref.read(apiClientProvider);
      if (widget.group == null) {
        await api.post('$base/parts/${widget.part.id}/groups', data: body);
      } else {
        await api.put('$base/groups/${widget.group!.id}', data: body);
      }
      nav.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _optionList(
    String legend,
    List<IeltsOption> options,
    int max,
    ValueChanged<List<IeltsOption>> set,
    String keyPrefix,
  ) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(legend, style: text.bodyMedium),
        for (final (i, o) in options.indexed)
          Row(
            children: [
              SizedBox(
                width: 64,
                child: TextFormField(
                  key: Key('$keyPrefix-key-$i'),
                  initialValue: o.key,
                  maxLength: 8,
                  decoration: InputDecoration(
                    labelText: l10n.ieltsBuilderLetter,
                    counterText: '',
                  ),
                  onChanged: (v) => set([
                    for (final (j, x) in options.indexed)
                      j == i ? (key: v, text: x.text) : x,
                  ]),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextFormField(
                  key: Key('$keyPrefix-text-$i'),
                  initialValue: o.text,
                  decoration: InputDecoration(
                    labelText: l10n.ieltsBuilderOptionText,
                  ),
                  onChanged: (v) => set([
                    for (final (j, x) in options.indexed)
                      j == i ? (key: x.key, text: v) : x,
                  ]),
                ),
              ),
              IconButton(
                tooltip: l10n.ieltsBuilderRemoveOption(
                  o.key.isEmpty ? '${i + 1}' : o.key,
                ),
                icon: const Icon(Icons.close),
                onPressed: () => set([
                  for (final (j, x) in options.indexed)
                    if (j != i) x,
                ]),
              ),
            ],
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            key: Key('$keyPrefix-add'),
            onPressed: options.length >= max
                ? null
                : () => set([
                    ...options,
                    (key: nextKey(options.map((o) => o.key)), text: ''),
                  ]),
            child: Text(l10n.ieltsBuilderAddOption),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final rule = _rule;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.group == null
                    ? l10n.ieltsBuilderAddGroup
                    : l10n.ieltsBuilderEditGroup,
                style: text.titleLarge,
              ),
              Text(
                ieltsPartName(l10n, widget.part.module, widget.part.partNo),
                style: text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                key: const Key('group-type'),
                initialValue: _type,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.ieltsBuilderGroupType,
                ),
                items: [
                  for (final t in _types)
                    DropdownMenuItem(
                      value: t,
                      child: Text(groupTypeName(l10n, t)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _type = v!;
                  for (final q in _questions) {
                    q.keys = [];
                  }
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                key: const Key('group-instruction'),
                controller: _instruction,
                minLines: 2,
                maxLines: 5,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: l10n.ieltsBuilderInstruction,
                  hintText: l10n.ieltsBuilderInstructionHint,
                ),
              ),
              if (rule.choices == IeltsChoices.text) ...[
                CheckboxListTile(
                  key: const Key('group-word-box'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.ieltsBuilderUseWordBox),
                  value: _wordBox,
                  onChanged: (v) => setState(() {
                    _wordBox = v ?? false;
                    for (final q in _questions) {
                      q.keys = [];
                    }
                  }),
                ),
                if (!_wordBox)
                  DropdownButtonFormField<int?>(
                    key: const Key('group-word-limit'),
                    initialValue: _wordLimit,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.ieltsBuilderWordLimit,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(l10n.ieltsBuilderNoWordLimit),
                      ),
                      for (var n = 1; n <= 5; n++)
                        DropdownMenuItem(
                          value: n,
                          child: Text(l10n.ieltsBuilderWords(n)),
                        ),
                    ],
                    onChanged: (v) => setState(() => _wordLimit = v),
                  ),
              ],
              if (_usesShared) ...[
                const SizedBox(height: AppSpacing.sm),
                _optionList(
                  rule.choices == IeltsChoices.shared
                      ? l10n.ieltsBuilderSharedList
                      : l10n.ieltsBuilderWordBox,
                  _shared,
                  26,
                  (o) => setState(() => _shared = o),
                  'shared',
                ),
              ],
              if (isCompletion(_type)) ...[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  key: const Key('group-gap-text'),
                  controller: _gapText,
                  minLines: 3,
                  maxLines: 10,
                  decoration: InputDecoration(
                    labelText: l10n.ieltsBuilderGapText,
                    helperText: l10n.ieltsBuilderGapTextHint('[[1]], [[2]]…'),
                    helperMaxLines: 3,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    key: const Key('group-picture'),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(l10n.ieltsBuilderGroupPicture),
                    onPressed: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            final id = await _pickAndUpload(
                              context,
                              ref,
                              audio: false,
                            );
                            if (!mounted) return;
                            setState(() {
                              _busy = false;
                              if (id != null) _image = id;
                            });
                          },
                  ),
                  if (_image != null) ...[
                    Text(l10n.ieltsBuilderPictureAdded),
                    IconButton(
                      key: const Key('group-picture-remove'),
                      tooltip: l10n.ieltsBuilderRemove,
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _image = null),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(l10n.ieltsBuilderQuestions, style: text.titleSmall),
              for (final (i, q) in _questions.indexed)
                Container(
                  key: ObjectKey(q),
                  margin: const EdgeInsets.only(top: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.border),
                    borderRadius: AppRadius.cardAll,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              l10n.ieltsBuilderQuestionN(i + 1),
                              style: text.labelLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.ieltsBuilderRemoveQuestion(i + 1),
                            icon: const Icon(Icons.close),
                            onPressed: _questions.length == 1
                                ? null
                                : () => setState(() => _questions.removeAt(i)),
                          ),
                        ],
                      ),
                      TextFormField(
                        key: Key('question-prompt-$i'),
                        initialValue: q.prompt,
                        decoration: InputDecoration(
                          labelText: l10n.ieltsBuilderPrompt,
                        ),
                        onChanged: (v) => q.prompt = v,
                      ),
                      if (rule.choices == IeltsChoices.question)
                        _optionList(
                          l10n.ieltsBuilderOptions,
                          q.options,
                          10,
                          (o) => setState(() {
                            q.options = o;
                            q.keys = [
                              for (final k in q.keys)
                                if (o.any((x) => x.key == k)) k,
                            ];
                          }),
                          'q$i-option',
                        ),
                      if (_writes)
                        _Accepted(
                          key: Key('question-accepted-$i'),
                          values: q.accepted,
                          onChanged: (v) => setState(() => q.accepted = v),
                        )
                      else if (_type == 'MCQ_MULTI') ...[
                        Text(l10n.ieltsBuilderRightAnswers),
                        Wrap(
                          spacing: AppSpacing.sm,
                          children: [
                            for (final k in _choicesFor(q))
                              FilterChip(
                                key: Key('question-key-$i-$k'),
                                label: Text(k),
                                selected: q.keys.contains(k),
                                onSelected: (on) => setState(
                                  () => q.keys = on
                                      ? [...q.keys, k]
                                      : [
                                          for (final x in q.keys)
                                            if (x != k) x,
                                        ],
                                ),
                              ),
                          ],
                        ),
                      ] else
                        DropdownButtonFormField<String?>(
                          key: Key('question-answer-$i'),
                          initialValue:
                              _choicesFor(q).contains(q.keys.firstOrNull)
                              ? q.keys.first
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: l10n.ieltsBuilderRightAnswer,
                            hintText: l10n.ieltsBuilderChooseAnswer,
                          ),
                          items: [
                            for (final k in _choicesFor(q))
                              DropdownMenuItem(value: k, child: Text(k)),
                          ],
                          onChanged: (v) =>
                              setState(() => q.keys = v == null ? [] : [v]),
                        ),
                    ],
                  ),
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('group-add-question'),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.ieltsBuilderAddQuestion),
                  onPressed: _questions.length >= 40
                      ? null
                      : () => setState(() => _questions.add(QuestionDraft())),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${OrgTime.number(_questions.length, lang)} · '
                '${groupTypeName(l10n, _type)}',
                style: text.bodySmall,
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.ieltsBuilderCancel),
                  ),
                  FilledButton(
                    key: const Key('group-save'),
                    onPressed: _busy ? null : _save,
                    child: Text(l10n.ieltsBuilderSave),
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

/// Accepted spellings for a written answer, added one at a time.
class _Accepted extends StatefulWidget {
  const _Accepted({required this.values, required this.onChanged, super.key});

  final List<String> values;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_Accepted> createState() => _AcceptedState();
}

class _AcceptedState extends State<_Accepted> {
  final _draft = TextEditingController();

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _add() {
    final v = _draft.text.trim();
    if (v.isEmpty) return;
    widget.onChanged([...widget.values, v]);
    _draft.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('accepted-input'),
                controller: _draft,
                decoration: InputDecoration(
                  labelText: l10n.ieltsBuilderAcceptedAnswers,
                  helperText: l10n.ieltsBuilderAcceptedHint,
                  helperMaxLines: 3,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(
              key: const Key('accepted-add'),
              tooltip: l10n.ieltsBuilderAddOption,
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ],
        ),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final (i, a) in widget.values.indexed)
              InputChip(
                label: Text(a),
                onDeleted: () => widget.onChanged([
                  for (final (j, x) in widget.values.indexed)
                    if (j != i) x,
                ]),
              ),
          ],
        ),
      ],
    );
  }
}

/// Title any time; test type and minutes per module while a draft.
class _DetailsForm extends ConsumerStatefulWidget {
  const _DetailsForm({required this.test});

  final IeltsTest test;

  @override
  ConsumerState<_DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends ConsumerState<_DetailsForm> {
  late final _title = TextEditingController(text: widget.test.title);
  late String _type = widget.test.testType;
  late final _minutes = {
    for (final m in widget.test.modules)
      m: TextEditingController(
        text: '${((widget.test.durations[m] ?? 0) / 60).round()}',
      ),
  };
  bool _busy = false;

  bool get _draft => widget.test.status == 'DRAFT';

  @override
  void dispose() {
    _title.dispose();
    for (final c in _minutes.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiClientProvider)
          .patch(
            '/ielts/tests/${widget.test.id}',
            data: {
              'title': _title.text.trim(),
              if (_draft) ...{
                'test_type': _type,
                'durations': {
                  for (final m in widget.test.modules)
                    m: (int.tryParse(_minutes[m]!.text.trim()) ?? 0) * 60,
                },
              },
            },
          );
      ref.invalidate(ieltsTestsProvider);
      nav.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.ieltsBuilderDetails, style: text.titleLarge),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('details-title'),
                controller: _title,
                maxLength: 200,
                decoration: InputDecoration(labelText: l10n.ieltsTestsTitle),
                onChanged: (_) => setState(() {}),
              ),
              if (_draft) ...[
                SegmentedButton<String>(
                  key: const Key('details-type'),
                  segments: [
                    for (final t in ['ACADEMIC', 'GENERAL'])
                      ButtonSegment(
                        value: t,
                        label: Text(ieltsTestTypeName(l10n, t)),
                      ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
                for (final m in widget.test.modules)
                  TextField(
                    key: Key('details-minutes-$m'),
                    controller: _minutes[m],
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.ieltsBuilderMinutesFor(
                        ieltsModuleShort(l10n, m),
                      ),
                      helperText: m == 'LISTENING'
                          ? l10n.ieltsBuilderListeningReview
                          : null,
                      helperMaxLines: 3,
                    ),
                  ),
              ] else
                Text(
                  [
                    for (final m in widget.test.modules)
                      '${ieltsModuleShort(l10n, m)} '
                          '${OrgTime.number(((widget.test.durations[m] ?? 0) / 60).round(), lang)}',
                  ].join(' · '),
                  style: text.bodySmall,
                ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(l10n.ieltsBuilderCancel),
                  ),
                  FilledButton(
                    key: const Key('details-save'),
                    onPressed: _busy || _title.text.trim().isEmpty
                        ? null
                        : _save,
                    child: Text(l10n.ieltsBuilderSave),
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
