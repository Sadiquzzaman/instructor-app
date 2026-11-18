import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';

typedef _Subject = ({String id, String name, String? code});

String _label(_Subject s) =>
    (s.code ?? '').isNotEmpty ? '${s.name} — ${s.code}' : s.name;

_Subject _subjectOf(Object? j) {
  final m = j is Map ? j : const <String, Object?>{};
  return (
    id: (m['id'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    code: m['code'] as String?,
  );
}

typedef _ClassSubject = ({String id, _Subject subject});
typedef _Class = ({String id, String name, List<_ClassSubject> subjects});
typedef _Section = ({String id, String name, String classId});
typedef _Offering = ({
  String id,
  String sectionId,
  _Subject subject,
  List<({String id, String name})> teachers,
});
typedef _Teacher = ({String id, String name});
typedef _Session = ({String id, String name, bool isDefault, bool closed});

/// What the page needs (the web's `fetchAll`): classes, the subject
/// catalogue, the teachers who can be given classes, the sessions, and the
/// sections and subject classes of the chosen session.
typedef AssignmentData = ({
  List<_Class> classes,
  List<_Subject> catalog,
  List<_Teacher> teachers,
  List<_Session> sessions,
  List<_Section> sections,
  List<_Offering> offerings,
  String sessionId,
});

List<Object?> _list(Object? p) => p is List ? p : const [];

/// [sessionId] '' is the default session.
final assignmentDataProvider = FutureProvider.autoDispose
    .family<AssignmentData, String>((ref, sessionId) async {
      ref.watch(workspaceKeyProvider);
      final org = ref.watch(sessionProvider)?.organizationId;
      final api = ref.read(apiClientProvider);
      final (classes, catalog, teachers, sessions) = await (
        api.get('/classes'),
        api.get('/organizations/$org/subjects'),
        api.get('/organizations/$org/assignable-teachers'),
        api.get('/sessions'),
      ).wait;
      final sessionList = [
        for (final s in _list(sessions.payload))
          if (s is Map && s['id'] is String)
            (
              id: s['id'] as String,
              name: (s['name'] as String?) ?? '',
              isDefault: s['is_default'] == true,
              closed: s['status'] == 'CLOSED',
            ),
      ];
      final chosen = sessionId.isNotEmpty
          ? sessionId
          : (sessionList.where((s) => s.isDefault).firstOrNull ??
                        sessionList.firstOrNull)
                    ?.id ??
                '';
      final q = {'session_id': chosen.isEmpty ? null : chosen};
      final (sections, offerings) = await (
        api.get('/sections', query: q),
        api.get('/offerings', query: q),
      ).wait;
      return (
        classes: [
          for (final c in _list(classes.payload))
            if (c is Map && c['id'] is String)
              (
                id: c['id'] as String,
                name: (c['class_name'] as String?) ?? '',
                subjects: [
                  for (final r in _list(c['classSubjects']))
                    if (r is Map && r['id'] is String)
                      (
                        id: r['id'] as String,
                        subject: _subjectOf({
                          ...(r['subject'] is Map
                              ? r['subject'] as Map
                              : const <String, Object?>{}),
                          'id':
                              r['subject_id'] ??
                              (r['subject'] is Map
                                  ? (r['subject'] as Map)['id']
                                  : null),
                        }),
                      ),
                ],
              ),
        ],
        catalog: [
          for (final s in _list(catalog.payload))
            if (s is Map && s['id'] is String) _subjectOf(s),
        ],
        teachers: [
          for (final m in _list(teachers.payload))
            if (m is Map &&
                m['user'] is Map &&
                (m['user'] as Map)['id'] is String)
              (
                id: (m['user'] as Map)['id'] as String,
                name:
                    ((m['user'] as Map)['full_name'] as String?) ??
                    ((m['user'] as Map)['phone'] as String?) ??
                    '',
              ),
        ],
        sessions: sessionList,
        sections: [
          for (final s in _list(sections.payload))
            if (s is Map && s['id'] is String)
              (
                id: s['id'] as String,
                name: (s['name'] as String?) ?? '',
                classId: (s['class_id'] as String?) ?? '',
              ),
        ],
        offerings: [
          for (final o in _list(offerings.payload))
            if (o is Map && o['id'] is String)
              (
                id: o['id'] as String,
                sectionId: (o['section_id'] as String?) ?? '',
                subject: _subjectOf(o['subject']),
                teachers: [
                  for (final t in _list(o['teachers']))
                    if (t is Map && t['id'] is String)
                      (
                        id: t['id'] as String,
                        name: (t['full_name'] as String?) ?? '',
                      ),
                ],
              ),
        ],
        sessionId: chosen,
      );
    }, retry: (retryCount, error) => null);

typedef _Row = ({
  String key,
  _Class klass,
  _Section section,
  _Offering offering,
  String? teacherId,
  String teacherName,
});

const _allSections = 'all';

/// The web's /organization/assignments (owners, admins, assistants), in
/// three steps: 1. which subjects each class has; 2. who teaches a subject
/// in a section (or in every section of the class at once); 3. every
/// subject class with its teachers, filterable, to change or remove a
/// teacher or fill an empty one. A closed session is read-only.
class AssignmentsScreen extends ConsumerStatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  ConsumerState<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends ConsumerState<AssignmentsScreen> {
  String _session = '';
  String? _class;
  String? _attach;
  String? _section;
  String? _subject;
  String? _teacher;
  _Row? _replacing;
  String _filterClass = 'all';
  String _filterSubject = 'all';
  String _filterTeacher = 'all';
  bool _saving = false;

  void _clearStep2() {
    _section = null;
    _subject = null;
    _teacher = null;
    _replacing = null;
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<bool> _run(Future<void> Function() call, String done) async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await call();
      _snack(done);
      ref.invalidate(assignmentDataProvider(_session));
      await ref.read(assignmentDataProvider(_session).future);
      return true;
    } on ApiException catch (e) {
      _snack(apiErrorText(l10n, e));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Sets a subject class's teachers: everyone there, minus [remove], plus
  /// [add].
  Future<void> _setTeachers(_Offering o, {String? add, String? remove}) {
    final ids = [
      for (final t in o.teachers)
        if (t.id != remove) t.id,
    ];
    if (add != null && !ids.contains(add)) ids.add(add);
    return ref
        .read(apiClientProvider)
        .put('/offerings/${o.id}/teachers', data: {'teacher_ids': ids});
  }

  Future<bool> _confirm(String title, String detail) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(detail),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(d).pop(false),
              child: Text(context.l10n.uiCancel),
            ),
            FilledButton(
              key: const Key('assignments-confirm'),
              onPressed: () => Navigator.of(d).pop(true),
              child: Text(context.l10n.organizationAssignmentsRemove),
            ),
          ],
        ),
      ) ==
      true;

  Future<void> _attachSubject() async {
    final l10n = context.l10n;
    final classId = _class;
    final subjectId = _attach;
    if (classId == null || subjectId == null) {
      _snack(ref.levels(context, l10n.organizationAssignmentsNeedClassSubject));
      return;
    }
    if (await _run(
      () => ref
          .read(apiClientProvider)
          .post('/classes/$classId/subjects', data: {'subject_id': subjectId}),
      l10n.organizationAssignmentsSubjectAddedTitle,
    )) {
      // Continue in step 2 with the new subject in every section.
      setState(() {
        _attach = null;
        _clearStep2();
        _section = _allSections;
        _subject = subjectId;
      });
    }
  }

  Future<void> _removeSubject(_Class c, _ClassSubject cs) async {
    final l10n = context.l10n;
    if (!await _confirm(
      l10n.organizationAssignmentsRemoveSubjectTitle(
        _label(cs.subject),
        c.name,
      ),
      ref.levels(context, l10n.organizationAssignmentsRemoveSubjectDetail),
    )) {
      return;
    }
    if (await _run(
      () => ref
          .read(apiClientProvider)
          .delete('/classes/${c.id}/subjects/${cs.id}'),
      l10n.organizationAssignmentsSubjectRemovedTitle,
    )) {
      setState(_clearStep2);
    }
  }

  Future<void> _assign(List<_Offering> targets) async {
    final l10n = context.l10n;
    final teacher = _teacher;
    if (teacher == null || targets.isEmpty) {
      _snack(ref.levels(context, l10n.organizationAssignmentsNeedAll));
      return;
    }
    final replacing = _replacing;
    if (replacing != null && replacing.teacherId == teacher) {
      setState(_clearStep2);
      return;
    }
    if (await _run(
      () async {
        for (final o in targets) {
          await _setTeachers(o, add: teacher, remove: replacing?.teacherId);
        }
      },
      replacing != null
          ? l10n.organizationAssignmentsReplacedTitle
          : l10n.organizationAssignmentsAssignedTitle,
    )) {
      setState(_clearStep2);
    }
  }

  Future<void> _unassign(_Row r) async {
    final l10n = context.l10n;
    if (!await _confirm(
      l10n.organizationAssignmentsUnassignTitle(
        r.teacherName,
        _label(r.offering.subject),
      ),
      ref.levels(
        context,
        l10n.organizationAssignmentsUnassignDetail(
          '${r.klass.name} · ${r.section.name}',
        ),
      ),
    )) {
      return;
    }
    if (await _run(
      () => _setTeachers(r.offering, remove: r.teacherId),
      l10n.organizationAssignmentsUnassignedTitle,
    )) {
      if (_replacing?.key == r.key) setState(_clearStep2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    if (!{'OWNER', 'ADMIN', 'ASSISTANT'}.contains(session?.memberRole)) {
      return EmptyView(
        icon: Icons.lock_outline,
        title: l10n.organizationGateNoAccessTitle,
        message: l10n.organizationGateNoAccess,
      );
    }
    final data = ref.watch(assignmentDataProvider(_session));
    final d = data.value;
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(l10n.organizationAssignmentsTitle, style: text.headlineSmall),
            Text(
              ref.levels(context, l10n.organizationAssignmentsIntro),
              style: muted,
            ),
            const SizedBox(height: AppSpacing.md),
            if (d == null)
              data.hasError
                  ? SizedBox(
                      height: 280,
                      child: ErrorView(
                        title: data.error is ApiException
                            ? apiErrorText(l10n, data.error!)
                            : l10n.uiErrorTitle,
                        retryLabel: l10n.uiErrorRetry,
                        onRetry: () =>
                            ref.invalidate(assignmentDataProvider(_session)),
                      ),
                    )
                  : SizedBox(
                      height: 200,
                      child: LoadingView(
                        semanticsLabel: l10n.organizationAssignmentsTitle,
                      ),
                    )
            else
              ..._body(d),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(AssignmentData d) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final muted = text.bodySmall?.copyWith(color: colors.inkMuted);
    final sessionOpen =
        !(d.sessions.where((s) => s.id == d.sessionId).firstOrNull?.closed ??
            false);
    final classById = {for (final c in d.classes) c.id: c};
    final sectionById = {for (final s in d.sections) s.id: s};
    final klass = classById[_class];
    final attachable = [
      for (final s in d.catalog)
        if (klass != null && !klass.subjects.any((cs) => cs.subject.id == s.id))
          s,
    ];
    final classSections = [
      for (final s in d.sections)
        if (s.classId == _class) s,
    ]..sort((a, b) => a.name.compareTo(b.name));
    final targetSections = _section == _allSections
        ? classSections.map((s) => s.id).toSet()
        : {?_section};
    final subjectChoices = <String, String>{
      for (final o in d.offerings)
        if (targetSections.contains(o.sectionId))
          o.subject.id: _label(o.subject),
    };
    final targets = _replacing != null
        ? [_replacing!.offering]
        : [
            for (final o in d.offerings)
              if (targetSections.contains(o.sectionId) &&
                  o.subject.id == _subject)
                o,
          ];
    final teacherChoices = [
      for (final t in d.teachers)
        if (_replacing != null ||
            !targets.every((o) => o.teachers.any((p) => p.id == t.id)))
          t,
    ];
    final rows = <_Row>[
      for (final o in d.offerings)
        if (sectionById[o.sectionId] case final section?)
          if (classById[section.classId] case final c?)
            if (o.teachers.isEmpty)
              (
                key: 'unassigned-${o.id}',
                klass: c,
                section: section,
                offering: o,
                teacherId: null,
                teacherName: l10n.organizationAssignmentsUnassigned,
              )
            else
              for (final t in o.teachers)
                (
                  key: '${o.id}-${t.id}',
                  klass: c,
                  section: section,
                  offering: o,
                  teacherId: t.id,
                  teacherName: t.name.isNotEmpty
                      ? t.name
                      : l10n.organizationAssignmentsTeacher,
                ),
    ];
    final shown = [
      for (final r in rows)
        if ((_filterClass == 'all' || r.klass.id == _filterClass) &&
            (_filterSubject == 'all' ||
                r.offering.subject.id == _filterSubject) &&
            (_filterTeacher == 'all' ||
                (_filterTeacher == 'unassigned'
                    ? r.teacherId == null
                    : r.teacherId == _filterTeacher)))
          r,
    ];
    DropdownMenuItem<String> item(String v, String label) =>
        DropdownMenuItem(value: v, child: Text(label));

    return [
      if (d.sessions.isNotEmpty) ...[
        DropdownButtonFormField<String>(
          key: const Key('assign-session'),
          initialValue: d.sessionId.isEmpty ? null : d.sessionId,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: l10n.organizationAssignmentsSession,
          ),
          items: [for (final s in d.sessions) item(s.id, s.name)],
          onChanged: (v) => setState(() {
            _session = v ?? '';
            _clearStep2();
          }),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      // Step 1: a class's subjects.
      AppCard(
        key: const Key('assign-step1'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ref.levels(context, l10n.organizationAssignmentsStep1),
              style: text.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: const Key('assign-class'),
              initialValue: _class,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: ref.levels(
                  context,
                  l10n.organizationAssignmentsClass,
                ),
                hintText: ref.levels(
                  context,
                  l10n.organizationAssignmentsSelectClass,
                ),
              ),
              items: [for (final c in d.classes) item(c.id, c.name)],
              onChanged: _replacing != null
                  ? null
                  : (v) => setState(() {
                      _class = v;
                      _attach = null;
                      _clearStep2();
                    }),
            ),
            if (klass != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.organizationAssignmentsSubjectsIn(klass.name),
                style: text.labelLarge,
              ),
              if (klass.subjects.isEmpty)
                Text(
                  ref.levels(context, l10n.organizationAssignmentsNoSubjects),
                  style: muted,
                ),
              for (final cs in klass.subjects)
                Row(
                  children: [
                    Expanded(child: Text(_label(cs.subject))),
                    TextButton(
                      key: Key('subject-remove-${cs.id}'),
                      style: TextButton.styleFrom(
                        foregroundColor: colors.danger,
                      ),
                      onPressed: _saving
                          ? null
                          : () => _removeSubject(klass, cs),
                      child: Text(l10n.organizationAssignmentsRemove),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: const Key('assign-attach'),
              initialValue: _attach,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.organizationAssignmentsSubject,
                hintText: klass == null
                    ? ref.levels(
                        context,
                        l10n.organizationAssignmentsClassFirst,
                      )
                    : attachable.isEmpty
                    ? ref.levels(
                        context,
                        l10n.organizationAssignmentsAllAttached,
                      )
                    : l10n.organizationAssignmentsSelectSubject,
              ),
              items: [for (final s in attachable) item(s.id, _label(s))],
              onChanged: klass == null
                  ? null
                  : (v) => setState(() => _attach = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                key: const Key('assign-attach-add'),
                onPressed: _saving ? null : _attachSubject,
                child: Text(l10n.organizationAssignmentsAddSubject),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      // Step 2: a teacher for a subject in a section (or all).
      AppCard(
        key: const Key('assign-step2'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.organizationAssignmentsStep2, style: text.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (!sessionOpen)
              Text(
                ref.levels(context, l10n.organizationAssignmentsSessionClosed),
                key: const Key('assign-closed'),
                style: muted,
              )
            else ...[
              DropdownButtonFormField<String>(
                key: ValueKey('assign-section-$_class-${_replacing?.key}'),
                initialValue: _section,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: ref.levels(
                    context,
                    l10n.organizationAssignmentsSection,
                  ),
                  hintText: ref.levels(
                    context,
                    _class == null
                        ? l10n.organizationAssignmentsClassFirst
                        : classSections.isEmpty
                        ? l10n.organizationAssignmentsNoSections
                        : l10n.organizationAssignmentsSelectSection,
                  ),
                ),
                items: [
                  if (classSections.length > 1)
                    item(
                      _allSections,
                      ref.levels(
                        context,
                        l10n.organizationAssignmentsAllSections,
                      ),
                    ),
                  for (final s in classSections) item(s.id, s.name),
                ],
                onChanged: _replacing != null || classSections.isEmpty
                    ? null
                    : (v) => setState(() {
                        _section = v;
                        _subject = null;
                        _teacher = null;
                      }),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                key: ValueKey('assign-subject-$_section-${_replacing?.key}'),
                initialValue: subjectChoices.containsKey(_subject)
                    ? _subject
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.organizationAssignmentsSubject,
                  hintText: ref.levels(
                    context,
                    _section == null
                        ? l10n.organizationAssignmentsSectionFirst
                        : subjectChoices.isEmpty
                        ? l10n.organizationAssignmentsAddSubjectFirst
                        : l10n.organizationAssignmentsSelectSubject,
                  ),
                ),
                items: [
                  for (final MapEntry(:key, :value) in subjectChoices.entries)
                    item(key, value),
                ],
                onChanged: _replacing != null || subjectChoices.isEmpty
                    ? null
                    : (v) => setState(() {
                        _subject = v;
                        _teacher = null;
                      }),
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                key: ValueKey('assign-teacher-$_subject-${_replacing?.key}'),
                initialValue: teacherChoices.any((t) => t.id == _teacher)
                    ? _teacher
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: l10n.organizationAssignmentsTeacher,
                  hintText: _subject == null
                      ? l10n.organizationAssignmentsSubjectFirst
                      : l10n.organizationAssignmentsSelectTeacher,
                ),
                items: [for (final t in teacherChoices) item(t.id, t.name)],
                onChanged: _subject == null
                    ? null
                    : (v) => setState(() => _teacher = v),
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  FilledButton(
                    key: const Key('assign-save'),
                    onPressed: _saving ? null : () => _assign(targets),
                    child: Text(
                      _replacing != null
                          ? l10n.organizationAssignmentsReplace
                          : l10n.organizationAssignmentsAssign,
                    ),
                  ),
                  if (_replacing != null)
                    TextButton(
                      onPressed: () => setState(_clearStep2),
                      child: Text(l10n.organizationAssignmentsCancelEdit),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      // Step 3: every subject class and its teachers.
      Text(l10n.organizationAssignmentsStep3, style: text.titleMedium),
      const SizedBox(height: AppSpacing.sm),
      Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          for (final (key, label, value, options, onChanged) in [
            (
              'filter-class',
              ref.levels(context, l10n.organizationAssignmentsFilterClass),
              _filterClass,
              {
                'all': ref.levels(
                  context,
                  l10n.organizationAssignmentsAllClasses,
                ),
                for (final c in d.classes) c.id: c.name,
              },
              (String v) => setState(() => _filterClass = v),
            ),
            (
              'filter-subject',
              l10n.organizationAssignmentsFilterSubject,
              _filterSubject,
              {
                'all': l10n.organizationAssignmentsAllSubjects,
                for (final r in rows)
                  r.offering.subject.id: _label(r.offering.subject),
              },
              (String v) => setState(() => _filterSubject = v),
            ),
            (
              'filter-teacher',
              l10n.organizationAssignmentsFilterTeacher,
              _filterTeacher,
              {
                'all': l10n.organizationAssignmentsAllTeachers,
                for (final r in rows)
                  r.teacherId ?? 'unassigned': r.teacherName,
              },
              (String v) => setState(() => _filterTeacher = v),
            ),
          ])
            SizedBox(
              width: 280,
              child: DropdownButtonFormField<String>(
                key: Key(key),
                initialValue: options.containsKey(value) ? value : 'all',
                isExpanded: true,
                decoration: InputDecoration(labelText: label),
                items: [
                  for (final MapEntry(:key, :value) in options.entries)
                    item(key, value),
                ],
                onChanged: (v) => onChanged(v ?? 'all'),
              ),
            ),
        ],
      ),
      const SizedBox(height: AppSpacing.sm),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            ref.levels(context, l10n.organizationAssignmentsEmpty),
            textAlign: TextAlign.center,
            style: muted,
          ),
        ),
      for (final r in shown) ...[
        AppCard(
          key: Key('row-${r.key}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${r.klass.name} ${r.section.name} · ${_label(r.offering.subject)}',
                style: text.titleSmall,
              ),
              Text(
                r.teacherName,
                style: r.teacherId == null
                    ? text.bodyMedium?.copyWith(color: colors.danger)
                    : text.bodyMedium,
              ),
              if (sessionOpen)
                r.teacherId == null
                    ? DropdownButtonFormField<String>(
                        key: Key('quick-${r.offering.id}'),
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: l10n
                              .organizationAssignmentsAssignTeacherFor(
                                _label(r.offering.subject),
                                '${r.klass.name} ${r.section.name}',
                              ),
                          hintText: l10n.organizationAssignmentsChooseTeacher,
                        ),
                        items: [for (final t in d.teachers) item(t.id, t.name)],
                        onChanged: _saving
                            ? null
                            : (v) {
                                if (v == null) return;
                                _run(
                                  () => _setTeachers(r.offering, add: v),
                                  l10n.organizationAssignmentsAssignedTitle,
                                );
                              },
                      )
                    : Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.xs,
                        children: [
                          TextButton(
                            key: Key('edit-${r.key}'),
                            onPressed: _saving
                                ? null
                                : () => setState(() {
                                    _class = r.klass.id;
                                    _attach = null;
                                    _section = r.section.id;
                                    _subject = r.offering.subject.id;
                                    _teacher = r.teacherId;
                                    _replacing = r;
                                  }),
                            child: Text(l10n.organizationAssignmentsEdit),
                          ),
                          TextButton(
                            key: Key('unassign-${r.key}'),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.danger,
                            ),
                            onPressed: _saving ? null : () => _unassign(r),
                            child: Text(l10n.organizationAssignmentsRemove),
                          ),
                        ],
                      ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
    ];
  }
}
