import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/dashboard/data/teacher_dashboard.dart';

/// How many top students show, as on the web.
const _topShown = 10;

/// A teacher's home (the web's `/dashboard`): what needs action now (to mark,
/// live tests, the next test), then upcoming tests, students, classes and top
/// students. Today is one tap away. The calendar and activity charts stay on
/// the web.
class TeacherDashboardScreen extends ConsumerWidget {
  const TeacherDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final name = ref.watch(sessionProvider)?.fullName ?? '';
    final data = ref.watch(teacherDashboardProvider);

    Future<void> reload() async {
      ref.invalidate(teacherDashboardProvider);
      await ref
          .read(teacherDashboardProvider.future)
          .catchError((Object _) => const TeacherDashboard());
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(
                name.isEmpty
                    ? l10n.dashboardWelcomeFallback
                    : l10n.dashboardWelcome(name),
                style: text.headlineSmall,
              ),
              Text(
                l10n.dashboardTeacherIntro,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.of(context).inkMuted,
                ),
              ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('open-today'),
                  onPressed: () => context.go(AppRoutes.today),
                  icon: const Icon(Icons.today_outlined),
                  label: Text(l10n.navToday),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              ...data.when(
                loading: () => [
                  SizedBox(
                    height: 240,
                    child: LoadingView(semanticsLabel: l10n.navDashboard),
                  ),
                ],
                error: (_, _) => [
                  SizedBox(
                    height: 320,
                    child: ErrorView(
                      title: l10n.dashboardLoadFailed,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () => ref.invalidate(teacherDashboardProvider),
                    ),
                  ),
                ],
                data: (d) => [_Body(d)],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body(this.d);

  final TeacherDashboard d;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= AppSpacing.tabletBreakpoint;
        // Side by side on tablets, one above the other on phones.
        Widget row(List<Widget> children) => wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (i, c) in children.indexed) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.lg),
                    Expanded(child: c),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (i, c) in children.indexed) ...[
                    if (i > 0) const SizedBox(height: AppSpacing.lg),
                    c,
                  ],
                ],
              );
        const gap = SizedBox(height: AppSpacing.lg);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            row([
              _NeedsMarking(d.toMark),
              _LiveNow(d.live),
              _StartingSoon(d.upcoming.firstOrNull),
            ]),
            gap,
            row([_Upcoming(d.upcoming), _Students(d.students)]),
            gap,
            row([_Classes(d.classes), _TopStudents(d.topStudents)]),
          ],
        );
      },
    );
  }
}

/// One tile of the "Today" strip: a label, the big value, a detail and the
/// one thing to do next. Highlighted when something needs doing.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.label,
    this.value,
    this.detail,
    this.action,
    this.onAction,
    this.emphasis = false,
    this.children = const [],
    super.key,
  });

  final String label;
  final String? value;
  final String? detail;
  final String? action;
  final VoidCallback? onAction;
  final bool emphasis;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final ink = emphasis ? colors.inkInverse : colors.ink;
    final muted = emphasis ? colors.inkInverse : colors.inkMuted;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasis ? colors.primary : colors.surface,
        borderRadius: AppRadius.cardAll,
        border: Border.all(color: emphasis ? colors.primary : colors.border),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: text.bodySmall?.copyWith(color: muted)),
            const SizedBox(height: AppSpacing.sm),
            if (value != null)
              Text(
                value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.headlineSmall?.copyWith(color: ink),
              ),
            if (detail != null)
              Text(detail!, style: text.bodySmall?.copyWith(color: muted)),
            ...children,
            if (action != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.sm),
              emphasis
                  ? FilledButton.tonal(
                      onPressed: onAction,
                      child: Text(action!),
                    )
                  : TextButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NeedsMarking extends StatelessWidget {
  const _NeedsMarking(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return _Tile(
      key: const Key('tile-marking'),
      label: l10n.dashboardTodayNeedsMarking,
      emphasis: count > 0,
      value: OrgTime.number(count, language),
      detail: l10n.dashboardTodayNeedsMarkingDetail(count),
      action: count > 0 ? l10n.dashboardTodayGoToMarking : null,
      onAction: () => context.go('/grading'),
    );
  }
}

/// Tests running now, one at a time, counting down each second.
class _LiveNow extends ConsumerStatefulWidget {
  const _LiveNow(this.tests);

  final List<LiveTest> tests;

  @override
  ConsumerState<_LiveNow> createState() => _LiveNowState();
}

class _LiveNowState extends ConsumerState<_LiveNow> {
  int _index = 0;

  /// Seconds since the answer came, counted as the web does.
  int _gone = 0;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.tests.isNotEmpty) {
      _tick = Timer.periodic(
        const Duration(seconds: 1),
        (_) => setState(() => _gone++),
      );
    }
  }

  @override
  void didUpdateWidget(_LiveNow old) {
    super.didUpdateWidget(old);
    // A reload brings new times: count from them again.
    if (!identical(old.tests, widget.tests)) {
      _gone = 0;
      if (old.tests.length != widget.tests.length) _index = 0;
      _tick?.cancel();
      _tick = widget.tests.isEmpty
          ? null
          : Timer.periodic(
              const Duration(seconds: 1),
              (_) => setState(() => _gone++),
            );
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final tests = widget.tests;
    if (tests.isEmpty) {
      return _Tile(
        key: const Key('tile-live'),
        label: l10n.dashboardTodayLiveNow,
        value: OrgTime.number(0, language),
        detail: l10n.dashboardTodayNoLive,
      );
    }
    final i = _index % tests.length;
    final t = tests[i];
    final left = (t.remainingSeconds - _gone).clamp(0, t.remainingSeconds);
    void step(int by) =>
        setState(() => _index = (i + by + tests.length) % tests.length);
    return _Tile(
      key: const Key('tile-live'),
      label: l10n.dashboardTodayLiveNow,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: colors.successSoft,
            borderRadius: AppRadius.pill,
          ),
          child: Text(
            l10n.dashboardTodayTimeLeft(OrgTime.clock(left, language)),
            key: const Key('live-time-left'),
            style: text.bodySmall?.copyWith(color: colors.success),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          t.name ?? l10n.dashboardUntitledTest,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.titleMedium,
        ),
        Text(
          t.className ?? ref.levels(context, l10n.dashboardNoClass),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(color: colors.inkMuted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${l10n.dashboardTodayParticipants(t.participants)} · '
          '${l10n.dashboardTodaySubmitted(t.submitted)}',
          style: text.bodySmall,
        ),
        // More than one live test: previous and next.
        if (tests.length > 1) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('live-previous'),
                tooltip: l10n.dashboardTodayPreviousLive,
                onPressed: () => step(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  l10n.dashboardTodayLiveOf(i + 1, tests.length),
                  textAlign: TextAlign.center,
                  style: text.bodySmall?.copyWith(color: colors.inkMuted),
                ),
              ),
              IconButton(
                key: const Key('live-next'),
                tooltip: l10n.dashboardTodayNextLive,
                onPressed: () => step(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _StartingSoon extends ConsumerWidget {
  const _StartingSoon(this.next);

  final UpcomingTest? next;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final n = next;
    return _Tile(
      key: const Key('tile-soon'),
      label: l10n.dashboardTodayStartingSoon,
      value: n == null ? null : (n.name ?? l10n.dashboardUntitledTest),
      detail: n == null
          ? l10n.dashboardTodayNothingScheduled
          : '${OrgTime.dateTime(n.startsAt, language)} · '
                '${n.className ?? ref.levels(context, l10n.dashboardNoClass)}',
      action: n == null ? null : l10n.dashboardTodayViewTests,
      onAction: () => context.go(AppRoutes.tests),
    );
  }
}

/// A card with a title and an optional "View all ›" link.
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.link,
    this.onLink,
    super.key,
  });

  final String title;
  final String? link;
  final VoidCallback? onLink;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              // At the card's right edge; a long label (Bangla) wraps
              // instead of pushing the title out.
              if (link != null)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 200),
                  child: TextButton(
                    key: Key('link-$link'),
                    onPressed: onLink,
                    child: Text('$link ›', textAlign: TextAlign.end),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// A small empty state inside a card.
class _Empty extends StatelessWidget {
  const _Empty(this.title, this.detail);

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Column(
        children: [
          Text(title, style: text.titleSmall, textAlign: TextAlign.center),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(
              color: AppColors.of(context).inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

String _duration(BuildContext context, int? minutes) {
  final l10n = context.l10n;
  if (minutes == null || minutes <= 0) return '—';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return l10n.dashboardDurationMinutes(m);
  if (m == 0) return l10n.dashboardDurationHours(h);
  return l10n.dashboardDurationHoursMinutes(h, m);
}

class _Upcoming extends StatelessWidget {
  const _Upcoming(this.tests);

  final List<UpcomingTest> tests;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return _Section(
      key: const Key('section-upcoming'),
      title: l10n.dashboardUpcomingTitle,
      link: l10n.dashboardViewAll,
      onLink: () => context.go(AppRoutes.tests),
      child: tests.isEmpty
          ? _Empty(
              l10n.dashboardUpcomingEmpty,
              l10n.dashboardUpcomingEmptyDetail,
            )
          : Column(
              children: [
                for (final t in tests)
                  ListTile(
                    key: Key('upcoming-${t.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.name ?? l10n.dashboardUntitledTest),
                    subtitle: Text(
                      [
                        t.className ?? '—',
                        OrgTime.dateTime(t.startsAt, language),
                        _duration(context, t.durationMinutes),
                      ].join(' · '),
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                    trailing: Text(
                      l10n.dashboardClassesTooltip(t.students),
                      style: text.bodySmall,
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Students extends ConsumerWidget {
  const _Students(this.s);

  final ({int total, int active, int pending}) s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget figure(String key, String label, int value) => Expanded(
      child: Container(
        key: Key('students-$key'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.canvas,
          borderRadius: AppRadius.inputAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            Text(OrgTime.number(value, language), style: text.titleMedium),
          ],
        ),
      ),
    );
    return _Section(
      key: const Key('section-students'),
      title: l10n.dashboardStudentsTitle,
      link: l10n.dashboardStudentsAdd,
      onLink: () => context.go(AppRoutes.classes),
      child: s.total == 0
          ? _Empty(
              l10n.dashboardStudentsEmpty,
              ref.levels(context, l10n.dashboardStudentsEmptyDetail),
            )
          : Row(
              children: [
                figure('total', l10n.dashboardStudentsTotal, s.total),
                const SizedBox(width: AppSpacing.sm),
                figure('active', l10n.dashboardStudentsActive, s.active),
                const SizedBox(width: AppSpacing.sm),
                figure('pending', l10n.dashboardStudentsPending, s.pending),
              ],
            ),
    );
  }
}

/// Students in each class, as a list (the web draws bars).
class _Classes extends ConsumerWidget {
  const _Classes(this.classes);

  final List<ClassSummary> classes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final most = classes.fold(1, (m, c) => c.students > m ? c.students : m);
    final colors = AppColors.of(context);
    return _Section(
      key: const Key('section-classes'),
      title: ref.levels(context, l10n.dashboardClassesTitle),
      link: l10n.dashboardViewAll,
      onLink: () => context.go(AppRoutes.classes),
      child: classes.isEmpty
          ? _Empty(
              ref.levels(context, l10n.dashboardClassesEmpty),
              ref.levels(context, l10n.dashboardClassesEmptyDetail),
            )
          : Column(
              children: [
                for (final c in classes)
                  ListTile(
                    key: Key('class-${c.id}'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(c.name),
                    subtitle: ClipRRect(
                      borderRadius: AppRadius.pill,
                      child: LinearProgressIndicator(
                        value: c.students / most,
                        minHeight: AppSpacing.xs,
                        color: colors.primary,
                        backgroundColor: colors.primarySoft,
                      ),
                    ),
                    trailing: Text(l10n.dashboardClassesTooltip(c.students)),
                  ),
              ],
            ),
    );
  }
}

/// The best average scores in one class at a time, searchable.
class _TopStudents extends ConsumerStatefulWidget {
  const _TopStudents(this.classes);

  final List<TopStudentsOfClass> classes;

  @override
  ConsumerState<_TopStudents> createState() => _TopStudentsState();
}

class _TopStudentsState extends ConsumerState<_TopStudents> {
  String? _classId;
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final classes = widget.classes;
    final chosen =
        classes.where((c) => c.classId == _classId).firstOrNull ??
        classes.firstOrNull;
    final students = chosen?.students ?? const <TopStudent>[];
    if (students.isEmpty) {
      return _Section(
        key: const Key('section-top'),
        title: l10n.dashboardTopTitle,
        child: _Empty(l10n.dashboardTopEmpty, l10n.dashboardTopEmptyDetail),
      );
    }
    final needle = _search.text.trim().toLowerCase();
    final matching =
        students
            .where(
              (s) => needle.isEmpty || s.name.toLowerCase().contains(needle),
            )
            .toList()
          ..sort(
            (a, b) =>
                (b.averagePercent ?? -1).compareTo(a.averagePercent ?? -1),
          );
    final hidden = matching.length - _topShown;
    return _Section(
      key: const Key('section-top'),
      title: l10n.dashboardTopTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (classes.length > 1)
            DropdownButtonFormField<String>(
              key: const Key('top-class'),
              initialValue: chosen!.classId,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: ref.levels(context, l10n.dashboardTopClass),
              ),
              items: [
                for (final c in classes)
                  DropdownMenuItem(value: c.classId, child: Text(c.className)),
              ],
              onChanged: (v) => setState(() {
                _classId = v;
                _search.clear();
              }),
            ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const Key('top-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.dashboardTopSearch,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (matching.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(
                l10n.dashboardTopNoMatch,
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final s in matching.take(_topShown))
              ListTile(
                key: Key('top-${s.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                subtitle: Text(
                  '${l10n.dashboardTopTests}: '
                  '${OrgTime.number(s.testsTaken, language)}',
                  style: text.bodySmall,
                ),
                trailing: Text(
                  s.averagePercent == null
                      ? '—'
                      : '${OrgTime.number(s.averagePercent!.round(), language)}%',
                  style: text.titleSmall,
                ),
              ),
          if (hidden > 0)
            Text(
              l10n.dashboardTopMore(hidden),
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
        ],
      ),
    );
  }
}
