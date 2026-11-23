import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/results/screens/section_performance_screen.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// A student's latest report card.
typedef CardVersion = ({
  String id,
  int version,
  DateTime? madeAt,
  String locale,
  String? teacherRemark,
  String? principalRemark,
  DateTime? sharedUntil,
});

typedef CardRow = ({
  String studentId,
  String name,
  String? rollNo,
  CardVersion? latest,
});

/// `GET /report-cards?section_id&term_id`.
typedef CardList = ({bool canWritePrincipal, List<CardRow> rows});

DateTime? _time(Object? v) => v is String ? DateTime.tryParse(v) : null;

CardList _list(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  return (
    canWritePrincipal: j['can_write_principal_remark'] == true,
    rows: [
      if (j['rows'] is List)
        for (final r in j['rows'] as List)
          if (r is Map && r['student'] is Map)
            (
              studentId: ((r['student'] as Map)['id'] as String?) ?? '',
              name: ((r['student'] as Map)['full_name'] as String?) ?? '',
              rollNo: (r['student'] as Map)['roll_no'] as String?,
              latest: r['latest'] is Map
                  ? (
                      id: ((r['latest'] as Map)['id'] as String?) ?? '',
                      version:
                          ((r['latest'] as Map)['version'] as num?)?.toInt() ??
                          1,
                      madeAt: _time((r['latest'] as Map)['generated_at']),
                      locale:
                          ((r['latest'] as Map)['locale'] as String?) ?? 'bn',
                      teacherRemark:
                          (r['latest'] as Map)['teacher_remark'] as String?,
                      principalRemark:
                          (r['latest'] as Map)['principal_remark'] as String?,
                      sharedUntil: _time(
                        (r['latest'] as Map)['share_expires_at'],
                      ),
                    )
                  : null,
            ),
    ],
  );
}

final sectionCardsProvider = FutureProvider.autoDispose
    .family<CardList, ({String sectionId, String? termId})>((ref, k) async {
      ref.watch(workspaceKeyProvider);
      final r = await ref
          .read(apiClientProvider)
          .get(
            '/report-cards',
            query: {'section_id': k.sectionId, 'term_id': ?k.termId},
          );
      return _list(r.payload);
    }, retry: (retryCount, error) => null);

/// The web's /report-cards for staff (Academic): a section, a term and the
/// card's language; each student's remarks (the principal's for owners and
/// admins); Make cards, and Share them with families. A card keeps the
/// scores it was made with; making it again adds a version. Printing stays
/// on the web.
class StaffReportCardsScreen extends ConsumerStatefulWidget {
  const StaffReportCardsScreen({super.key});

  @override
  ConsumerState<StaffReportCardsScreen> createState() =>
      _StaffReportCardsScreenState();
}

class _StaffReportCardsScreenState
    extends ConsumerState<StaffReportCardsScreen> {
  String? _sectionId;
  String? _termId;
  late String _locale = Localizations.localeOf(context).languageCode == 'en'
      ? 'en'
      : 'bn';

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final visible = ref.watch(visibleSectionsProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.reportCardsTitle, style: text.headlineSmall),
            Text(
              l10n.reportCardsIntro,
              style: text.bodyMedium?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.md),
            ...visible.when(
              loading: () => [
                SizedBox(
                  height: 200,
                  child: LoadingView(semanticsLabel: l10n.reportCardsTitle),
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
                          title: l10n.reportCardsLoadFailed,
                          retryLabel: l10n.uiErrorRetry,
                          onRetry: () =>
                              ref.invalidate(visibleSectionsProvider),
                        ),
                ),
              ],
              data: (v) {
                if (v.sections.isEmpty) {
                  return [
                    SizedBox(
                      height: 260,
                      child: EmptyView(
                        icon: Icons.article_outlined,
                        title: ref.levels(context, l10n.reportCardsNoSections),
                        message: ref.levels(
                          context,
                          l10n.reportCardsNoSectionsHint,
                        ),
                      ),
                    ),
                  ];
                }
                final section = v.sections.any((s) => s.id == _sectionId)
                    ? _sectionId!
                    : v.sections.first.id;
                final term = v.terms.any((t) => t.id == _termId)
                    ? _termId
                    : null;
                return [
                  DropdownButtonFormField<String>(
                    key: const Key('cards-section'),
                    initialValue: section,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: ref.levels(context, l10n.reportCardsSection),
                    ),
                    items: [
                      for (final s in v.sections)
                        DropdownMenuItem(value: s.id, child: Text(s.name)),
                    ],
                    onChanged: (x) => setState(() => _sectionId = x),
                  ),
                  if (v.terms.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<String?>(
                      key: const Key('cards-term'),
                      initialValue: term,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: l10n.reportCardsTerm,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          child: Text(l10n.reportCardsWholeSession),
                        ),
                        for (final t in v.terms)
                          DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(t.name),
                          ),
                      ],
                      onChanged: (x) => setState(() => _termId = x),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    key: const Key('cards-language'),
                    initialValue: _locale,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.reportCardsLanguage,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'bn',
                        child: Text(l10n.reportCardsLanguagesBn),
                      ),
                      DropdownMenuItem(
                        value: 'en',
                        child: Text(l10n.reportCardsLanguagesEn),
                      ),
                    ],
                    onChanged: (x) => setState(() => _locale = x ?? _locale),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _SectionCards(
                    key: ValueKey('$section/$term'),
                    sectionId: section,
                    termId: term,
                    locale: _locale,
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

class _SectionCards extends ConsumerStatefulWidget {
  const _SectionCards({
    required this.sectionId,
    required this.termId,
    required this.locale,
    super.key,
  });

  final String sectionId;
  final String? termId;
  final String locale;

  @override
  ConsumerState<_SectionCards> createState() => _SectionCardsState();
}

class _SectionCardsState extends ConsumerState<_SectionCards> {
  late final _key = (sectionId: widget.sectionId, termId: widget.termId);
  CardList? _latest;
  final _teacher = <String, TextEditingController>{};
  final _principal = <String, TextEditingController>{};
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [..._teacher.values, ..._principal.values]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(CardList l) {
    for (final c in [..._teacher.values, ..._principal.values]) {
      c.dispose();
    }
    _teacher.clear();
    _principal.clear();
    for (final r in l.rows) {
      _teacher[r.studentId] = TextEditingController(
        text: r.latest?.teacherRemark ?? '',
      );
      _principal[r.studentId] = TextEditingController(
        text: r.latest?.principalRemark ?? '',
      );
    }
  }

  Future<void> _run(Future<void> Function() call) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await call();
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

  Future<void> _make(CardList l) => _run(() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final before = {
      for (final r in l.rows) r.studentId: r.latest?.version ?? 0,
    };
    final res = await ref
        .read(apiClientProvider)
        .post(
          '/report-cards/generate',
          data: {
            'section_id': widget.sectionId,
            'term_id': ?widget.termId,
            'locale': widget.locale,
            'rows': [
              for (final r in l.rows)
                {
                  'student_id': r.studentId,
                  'teacher_remark': _teacher[r.studentId]!.text,
                  if (l.canWritePrincipal)
                    'principal_remark': _principal[r.studentId]!.text,
                },
            ],
          },
        );
    if (!mounted) return;
    final next = _list(res.payload);
    final changed = next.rows
        .where((r) => (r.latest?.version ?? 0) != before[r.studentId])
        .length;
    setState(() {
      _latest = next;
      _fill(next);
    });
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.reportCardsMadeToast(changed))),
    );
  });

  Future<void> _share(int made) async {
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(l10n.reportCardsShareTitle),
        content: Text(l10n.reportCardsShareDetail(made)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.uiCancel),
          ),
          FilledButton(
            key: const Key('share-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.reportCardsShare),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    await _run(() async {
      final messenger = ScaffoldMessenger.of(context);
      final res = await ref
          .read(apiClientProvider)
          .post(
            '/report-cards/share',
            data: {'section_id': widget.sectionId, 'term_id': ?widget.termId},
          );
      final p = res.payload is Map
          ? res.payload as Map
          : const <String, Object?>{};
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '${l10n.reportCardsSharedToast((p['cards'] as num?) ?? 0)} '
            '${l10n.reportCardsSharedSms((p['guardian_sms'] as num?) ?? 0)}',
          ),
        ),
      );
      setState(() => _latest = null);
      _fill(const (canWritePrincipal: false, rows: <CardRow>[]));
      ref.invalidate(sectionCardsProvider(_key));
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loaded = ref.watch(sectionCardsProvider(_key));
    final l = _latest ?? loaded.value;
    if (l != null && _teacher.isEmpty && l.rows.isNotEmpty) _fill(l);
    if (l == null) {
      return loaded.hasError
          ? SizedBox(
              height: 260,
              child: ErrorView(
                title: l10n.reportCardsLoadFailed,
                retryLabel: l10n.uiErrorRetry,
                onRetry: () => ref.invalidate(sectionCardsProvider(_key)),
              ),
            )
          : const LinearProgressIndicator();
    }
    return _page(l);
  }

  Widget _page(CardList l) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    if (l.rows.isEmpty) {
      return Text(
        ref.levels(context, l10n.reportCardsNoStudents),
        style: text.bodyMedium?.copyWith(color: colors.inkMuted),
      );
    }
    final made = l.rows.where((r) => r.latest != null).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.reportCardsMadeCount(made, l.rows.length),
          style: text.bodyMedium,
        ),
        Text(
          l10n.reportCardsMakeHint,
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            FilledButton(
              key: const Key('cards-make'),
              onPressed: _busy ? null : () => _make(l),
              child: Text(l10n.reportCardsMake),
            ),
            OutlinedButton(
              key: const Key('cards-share'),
              onPressed: _busy || made == 0 ? null : () => _share(made),
              child: Text(l10n.reportCardsShare),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        for (final r in l.rows) ...[
          AppCard(
            key: Key('card-row-${r.studentId}'),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  r.rollNo == null ? r.name : '${r.rollNo}. ${r.name}',
                  style: text.titleSmall,
                ),
                if (r.latest == null)
                  Text(
                    l10n.reportCardsNotMade,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  )
                else ...[
                  Text(
                    l10n.reportCardsVersion(
                      OrgTime.number(r.latest!.version, language),
                      r.latest!.madeAt == null
                          ? ''
                          : OrgTime.date(r.latest!.madeAt!, language),
                    ),
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                  if (r.latest!.sharedUntil != null &&
                      r.latest!.sharedUntil!.isAfter(DateTime.now()))
                    Text(
                      l10n.reportCardsSharedUntil(
                        OrgTime.date(r.latest!.sharedUntil!, language),
                      ),
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton(
                      key: Key('card-open-${r.studentId}'),
                      onPressed: () => context.push(
                        '${AppRoutes.reportCards}/${r.latest!.id}',
                      ),
                      child: Text(l10n.reportCardsOpenFor(r.name)),
                    ),
                  ),
                ],
                TextField(
                  key: Key('teacher-remark-${r.studentId}'),
                  controller: _teacher[r.studentId],
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.reportCardsTeacherRemarkFor(r.name),
                  ),
                ),
                if (l.canWritePrincipal)
                  TextField(
                    key: Key('principal-remark-${r.studentId}'),
                    controller: _principal[r.studentId],
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: l10n.reportCardsPrincipalRemarkFor(r.name),
                    ),
                  )
                else
                  Text(
                    (r.latest?.principalRemark ?? '').isNotEmpty
                        ? l10n.reportCardsPrincipalSaid(
                            r.latest!.principalRemark!,
                          )
                        : l10n.reportCardsPrincipalLater,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
