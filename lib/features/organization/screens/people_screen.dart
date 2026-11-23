import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/organization/screens/organization_overview_screen.dart';

/// The three people pages of the web's Organisation menu.
enum PeopleKind {
  /// Owners, admins, teachers and branch managers; adds teachers.
  teachers(
    {'OWNER', 'ADMIN', 'TEACHER', 'BRANCH_MANAGER'},
    'TEACHER',
    {'OWNER', 'ADMIN', 'ASSISTANT'},
  ),
  assistants({'ASSISTANT'}, 'ASSISTANT', {'OWNER', 'ADMIN'}),
  students({'STUDENT'}, 'STUDENT', {'OWNER', 'ADMIN', 'ASSISTANT'});

  const PeopleKind(this.roles, this.adds, this.seenBy);

  final Set<String> roles;
  final String adds;
  final Set<String> seenBy;
}

/// Roles an owner or admin can give on the Teachers page.
const staffRoles = ['ADMIN', 'TEACHER', 'BRANCH_MANAGER'];

@immutable
class Member {
  const Member({
    required this.id,
    required this.role,
    required this.name,
    this.email,
    this.phone,
    this.teacherId,
    this.studentId,
    this.publicId,
    this.branchId,
    this.joined,
  });

  final String id;
  final String role;
  final String name;
  final String? email;
  final String? phone;
  final String? teacherId;
  final String? studentId;
  final String? publicId;
  final String? branchId;
  final DateTime? joined;

  static Member? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final u = j['user'] is Map ? j['user'] as Map : const <String, Object?>{};
    return Member(
      id: j['id'] as String,
      role: (j['role'] as String?) ?? 'TEACHER',
      name: (u['full_name'] as String?) ?? '',
      email: u['email'] as String?,
      phone: u['phone'] as String?,
      teacherId: u['teacher_public_id'] as String?,
      studentId: u['student_public_id'] as String?,
      publicId: u['public_id'] as String?,
      branchId: j['branch_id'] as String?,
      joined: j['created_at'] is String
          ? DateTime.tryParse(j['created_at'] as String)
          : null,
    );
  }

  /// The id shown for this page's kind of person.
  String shownId(PeopleKind kind) =>
      (kind == PeopleKind.students
              ? [studentId, teacherId, publicId]
              : [teacherId, studentId, publicId])
          .firstWhere((v) => v != null && v.isNotEmpty, orElse: () => null) ??
      '—';

  bool matches(String q) => [
    name,
    email,
    phone,
    teacherId,
    studentId,
  ].any((v) => (v ?? '').toLowerCase().contains(q));
}

final membersProvider = FutureProvider.autoDispose<List<Member>>((ref) async {
  ref.watch(workspaceKeyProvider);
  final id = ref.watch(sessionProvider)?.organizationId;
  final p =
      (await ref.read(apiClientProvider).get('/organizations/$id/members'))
          .payload;
  return [
    if (p is List)
      for (final m in p) ?Member.fromJson(m),
  ];
}, retry: (retryCount, error) => null);

/// The sections a new student can go into (the default session), in
/// natural order: `GET /sections` named with `GET /classes`.
final sectionChoicesProvider =
    FutureProvider.autoDispose<List<({String id, String label})>>((ref) async {
      ref.watch(workspaceKeyProvider);
      final api = ref.read(apiClientProvider);
      final (sections, classes) = await (
        api.get('/sections'),
        api.get('/classes'),
      ).wait;
      final names = {
        if (classes.payload is List)
          for (final c in classes.payload as List)
            if (c is Map && c['id'] is String)
              c['id'] as String: (c['class_name'] as String?) ?? '',
      };
      final out = [
        if (sections.payload is List)
          for (final s in sections.payload as List)
            if (s is Map && s['id'] is String)
              (
                id: s['id'] as String,
                label: '${names[s['class_id']] ?? ''} ${s['name'] ?? ''}'
                    .trim(),
              ),
      ];
      out.sort((a, b) => _natural(a.label, b.label));
      return out;
    }, retry: (retryCount, error) => null);

/// "Class 2" before "Class 10".
int _natural(String a, String b) {
  final re = RegExp(r'(\d+)|(\D+)');
  final x = re.allMatches(a).toList();
  final y = re.allMatches(b).toList();
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i][0]!;
    final q = y[i][0]!;
    final c = x[i][1] != null && y[i][1] != null
        ? int.parse(p).compareTo(int.parse(q))
        : p.toLowerCase().compareTo(q.toLowerCase());
    if (c != 0) return c;
  }
  return x.length.compareTo(y.length);
}

String _title(AppLocalizations l10n, PeopleKind kind) => switch (kind) {
  PeopleKind.teachers => l10n.organizationMembersTeachers,
  PeopleKind.assistants => l10n.organizationMembersAssistants,
  PeopleKind.students => l10n.organizationMembersStudents,
};

String _addLabel(AppLocalizations l10n, PeopleKind kind) => switch (kind) {
  PeopleKind.teachers => l10n.organizationMembersAddTEACHER,
  PeopleKind.assistants => l10n.organizationMembersAddASSISTANT,
  PeopleKind.students => l10n.organizationMembersAddSTUDENT,
};

/// The web's /organization/teachers, /assistants and /students: the list
/// with search; owners and admins add people (find by phone or email, or a
/// list of phone numbers), change a staff member's role and remove people
/// (asked first). Importing a CSV file stays on the website.
class PeopleScreen extends ConsumerStatefulWidget {
  const PeopleScreen({required this.kind, super.key});

  final PeopleKind kind;

  @override
  ConsumerState<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends ConsumerState<PeopleScreen> {
  String _q = '';

  Future<void> _add() async {
    final added = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AddPeopleScreen(kind: widget.kind),
      ),
    );
    if (added == true) ref.invalidate(membersProvider);
  }

  Future<void> _remove(Member m) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(
          l10n.organizationMembersRemoveTitle(
            m.name.isNotEmpty ? m.name : (m.phone ?? ''),
          ),
        ),
        content: Text(l10n.organizationMembersRemoveDetail),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: Text(l10n.uiCancel),
          ),
          FilledButton(
            key: const Key('remove-confirm'),
            onPressed: () => Navigator.of(d).pop(true),
            child: Text(l10n.organizationMembersRemove),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    final id = ref.read(sessionProvider)?.organizationId;
    try {
      await ref
          .read(apiClientProvider)
          .delete('/organizations/$id/members/${m.id}');
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.organizationMembersRemovedTitle)),
      );
      ref.invalidate(membersProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    }
  }

  Future<void> _changeRole(Member m) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => ChangeRoleDialog(member: m),
    );
    if (changed == true) ref.invalidate(membersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    final role = session?.memberRole;
    if (session?.organizationId == null) {
      return EmptyView(
        icon: Icons.apartment_outlined,
        title: l10n.organizationGateNoWorkspaceTitle,
        message: l10n.organizationGateNoWorkspace,
      );
    }
    if (!widget.kind.seenBy.contains(role)) {
      return EmptyView(
        icon: Icons.lock_outline,
        title: l10n.organizationGateNoAccessTitle,
        message: l10n.organizationGateNoAccess,
      );
    }
    final manages = managesOrganization(role);
    final members = ref.watch(membersProvider);
    final q = _q.trim().toLowerCase();
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(membersProvider);
        await ref
            .read(membersProvider.future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(_title(l10n, widget.kind), style: text.headlineSmall),
              Text(
                session?.organizationName ?? '',
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              if (manages) ...[
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilledButton.icon(
                    key: const Key('people-add'),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(_addLabel(l10n, widget.kind)),
                    onPressed: _add,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const Key('people-search'),
                decoration: InputDecoration(
                  hintText: l10n.organizationMembersSearch,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: AppSpacing.md),
              ...members.when(
                loading: () => [
                  SizedBox(
                    height: 200,
                    child: LoadingView(
                      semanticsLabel: _title(l10n, widget.kind),
                    ),
                  ),
                ],
                error: (e, _) => [
                  SizedBox(
                    height: 280,
                    child: ErrorView(
                      title: e is ApiException
                          ? apiErrorText(l10n, e)
                          : l10n.uiErrorTitle,
                      retryLabel: l10n.uiErrorRetry,
                      onRetry: () => ref.invalidate(membersProvider),
                    ),
                  ),
                ],
                data: (all) {
                  final list = [
                    for (final m in all)
                      if (widget.kind.roles.contains(m.role) &&
                          (q.isEmpty || m.matches(q)))
                        m,
                  ];
                  if (list.isEmpty) {
                    return [
                      SizedBox(
                        height: 200,
                        child: EmptyView(
                          icon: Icons.people_outline,
                          title: l10n.organizationMembersEmpty,
                        ),
                      ),
                    ];
                  }
                  return [
                    for (final m in list) ...[
                      _MemberCard(
                        key: Key('member-${m.id}'),
                        member: m,
                        kind: widget.kind,
                        manages: manages,
                        onRemove: () => _remove(m),
                        onChangeRole: () => _changeRole(m),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ];
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.kind,
    required this.manages,
    required this.onRemove,
    required this.onChangeRole,
    super.key,
  });

  final Member member;
  final PeopleKind kind;
  final bool manages;
  final VoidCallback onRemove;
  final VoidCallback onChangeRole;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final muted = text.bodySmall?.copyWith(
      color: AppColors.of(context).inkMuted,
    );
    final m = member;
    final idLabel = switch (kind) {
      PeopleKind.teachers => l10n.organizationMembersIdColumnTEACHER,
      PeopleKind.assistants => l10n.organizationMembersIdColumnASSISTANT,
      PeopleKind.students => l10n.organizationMembersIdColumnSTUDENT,
    };
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  m.name.isNotEmpty ? m.name : '—',
                  style: text.titleSmall,
                ),
              ),
              StatusPill(
                label: roleText(l10n, m.role),
                tone: StatusTone.neutral,
              ),
            ],
          ),
          Text('$idLabel: ${m.shownId(kind)}', style: muted),
          Text(
            [
              m.phone,
              m.email,
              if (m.joined != null)
                '${l10n.organizationMembersJoined}: ${OrgTime.date(m.joined!, language)}',
            ].whereType<String>().where((s) => s.isNotEmpty).join(' · '),
            style: muted,
          ),
          if (manages && m.role != 'OWNER')
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              children: [
                if (staffRoles.contains(m.role))
                  TextButton(
                    key: Key('role-${m.id}'),
                    onPressed: onChangeRole,
                    child: Text(l10n.organizationMembersChangeRoleAction),
                  ),
                TextButton(
                  key: Key('remove-${m.id}'),
                  onPressed: onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.of(context).danger,
                  ),
                  child: Text(l10n.organizationMembersRemove),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Change a staff member's role; a branch manager also gets the branch
/// they run. Pops true when saved.
class ChangeRoleDialog extends ConsumerStatefulWidget {
  const ChangeRoleDialog({required this.member, super.key});

  final Member member;

  @override
  ConsumerState<ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends ConsumerState<ChangeRoleDialog> {
  late String _role = widget.member.role;
  late String? _branch = widget.member.branchId;
  List<({String id, String? name})>? _branches;
  bool _saving = false;

  Future<void> _loadBranches() async {
    if (_branches != null) return;
    try {
      final p = (await ref.read(apiClientProvider).get('/attendance/branches'))
          .payload;
      if (!mounted) return;
      setState(
        () => _branches = [
          if (p is List)
            for (final b in p)
              if (b is Map && b['id'] is String)
                (id: b['id'] as String, name: b['name'] as String?),
        ],
      );
    } on ApiException {
      if (mounted) setState(() => _branches = const []);
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final id = ref.read(sessionProvider)?.organizationId;
    setState(() => _saving = true);
    try {
      await ref
          .read(apiClientProvider)
          .patch(
            '/organizations/$id/members/${widget.member.id}',
            data: {
              'role': _role,
              if (_role == 'BRANCH_MANAGER') 'branch_id': _branch,
            },
          );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.organizationMembersChangeRoleDone(roleText(l10n, _role)),
          ),
        ),
      );
      navigator.pop(true);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final m = widget.member;
    final needsBranch = _role == 'BRANCH_MANAGER';
    if (needsBranch) _loadBranches();
    return AlertDialog(
      title: Text(
        l10n.organizationMembersChangeRoleTitle(
          m.name.isNotEmpty ? m.name : (m.phone ?? ''),
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.organizationMembersChangeRoleIntro),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: const Key('role-choice'),
              initialValue: _role,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.organizationMembersChangeRoleRole,
              ),
              items: [
                for (final r in staffRoles)
                  DropdownMenuItem(value: r, child: Text(roleText(l10n, r))),
              ],
              onChanged: (v) => setState(() => _role = v ?? _role),
            ),
            if (needsBranch) ...[
              const SizedBox(height: AppSpacing.md),
              if (_branches == null)
                const LinearProgressIndicator()
              else
                DropdownButtonFormField<String>(
                  key: const Key('branch-choice'),
                  initialValue: _branches!.any((b) => b.id == _branch)
                      ? _branch
                      : null,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.organizationMembersChangeRoleBranch,
                    hintText: l10n.organizationMembersChangeRoleChooseBranch,
                    helperText:
                        l10n.organizationMembersChangeRoleBranchManagerHint,
                    helperMaxLines: 3,
                  ),
                  items: [
                    for (final b in _branches!)
                      DropdownMenuItem(
                        value: b.id,
                        child: Text(
                          (b.name ?? '').isNotEmpty
                              ? b.name!
                              : l10n.organizationMembersChangeRoleMainBranch,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _branch = v),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.organizationMembersChangeRoleCancel),
        ),
        FilledButton(
          key: const Key('role-save'),
          onPressed: _saving || (needsBranch && _branch == null) ? null : _save,
          child: Text(l10n.organizationMembersChangeRoleSave),
        ),
      ],
    );
  }
}

typedef _Lookup = ({
  bool found,
  String? message,
  String? userId,
  String? name,
  String? email,
  String? phone,
  String? teacherId,
  String? studentId,
  bool verified,
  bool member,
  bool activeMember,
});

/// Adding people (the web's drawer): find one by phone or email and add or
/// invite them (students optionally straight into a section), or add a list
/// of phone numbers. Pops true when someone was added.
class AddPeopleScreen extends ConsumerStatefulWidget {
  const AddPeopleScreen({required this.kind, super.key});

  final PeopleKind kind;

  @override
  ConsumerState<AddPeopleScreen> createState() => _AddPeopleScreenState();
}

class _AddPeopleScreenState extends ConsumerState<AddPeopleScreen> {
  final _query = TextEditingController();
  final _phones = TextEditingController();
  _Lookup? _lookup;
  String? _section;
  bool _busy = false;
  bool _added = false;
  ({
    num imported,
    num already,
    num notFound,
    num invalid,
    num invited,
    num duplicate,
  })?
  _summary;

  String? get _orgId => ref.read(sessionProvider)?.organizationId;

  @override
  void dispose() {
    _query.dispose();
    _phones.dispose();
    super.dispose();
  }

  void _snack(String s) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> _find() async {
    final l10n = context.l10n;
    final q = _query.text.trim();
    if (q.isEmpty) {
      _snack(l10n.organizationMembersMissingQuery);
      return;
    }
    setState(() {
      _busy = true;
      _lookup = null;
    });
    try {
      final p =
          (await ref
                  .read(apiClientProvider)
                  .get(
                    '/organizations/$_orgId/members/lookup',
                    query: {'q': q},
                  ))
              .payload;
      final j = p is Map ? p : const <String, Object?>{};
      final u = j['user'] is Map ? j['user'] as Map : const <String, Object?>{};
      final m = j['membership'] is Map ? j['membership'] as Map : null;
      if (!mounted) return;
      setState(
        () => _lookup = (
          found: j['found'] == true,
          message: j['message'] as String?,
          userId: u['id'] as String?,
          name: u['full_name'] as String?,
          email: u['email'] as String?,
          phone: u['phone'] as String?,
          teacherId: u['teacher_public_id'] as String?,
          studentId: u['student_public_id'] as String?,
          verified: u['is_otp_verified'] == true,
          member: m != null,
          activeMember: m != null && (m['is_active'] as num?)?.toInt() == 1,
        ),
      );
    } on ApiException catch (e) {
      if (mounted) _snack(apiErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _sectionLabel(List<({String id, String label})> sections) =>
      sections.where((s) => s.id == _section).firstOrNull?.label ?? '';

  Future<void> _addOrInvite(List<({String id, String label})> sections) async {
    final l10n = context.l10n;
    final q = _query.text.trim();
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      if (widget.kind == PeopleKind.students && _section != null) {
        final l = _lookup;
        final r = await api.post(
          '/sections/$_section/enrolments',
          data: l != null && l.found && l.userId != null
              ? {'student_id': l.userId}
              : q.contains('@')
              ? {'email': q}
              : {'phone': q},
        );
        final outcome = r.payload is Map ? (r.payload as Map)['outcome'] : null;
        final section = _sectionLabel(sections);
        _snack(switch (outcome) {
          'INVITED' => l10n.organizationMembersInvitedToSection(section),
          'PENDING' => l10n.organizationMembersPendingInSection,
          _ => l10n.organizationMembersAddedToSection(section),
        });
      } else {
        final r = await api.post(
          '/organizations/$_orgId/members',
          data: {'query': q, 'role': widget.kind.adds},
        );
        final status = r.payload is Map ? (r.payload as Map)['status'] : null;
        _snack(
          status == 'invited'
              ? l10n.organizationMembersInvitedDetail
              : l10n.organizationMembersAddedDetail,
        );
      }
      navigator.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        _snack(apiErrorText(l10n, e));
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _addPhones() async {
    final l10n = context.l10n;
    final list = [
      for (final v in _phones.text.split(RegExp(r'[\n,;]+')))
        if (v.trim().isNotEmpty) v.trim(),
    ];
    if (list.isEmpty) {
      _snack(l10n.organizationMembersNoPhones);
      return;
    }
    setState(() => _busy = true);
    try {
      final p =
          (await ref
                  .read(apiClientProvider)
                  .post(
                    '/organizations/$_orgId/members/import',
                    data: {
                      'identifiers': list,
                      'role': widget.kind.adds,
                      'invite_missing': false,
                    },
                  ))
              .payload;
      final j = p is Map ? p : const <String, Object?>{};
      num n(String k) => (j[k] as num?) ?? 0;
      if (!mounted) return;
      setState(() {
        _added = true;
        _summary = (
          imported: n('imported'),
          already: n('already_member'),
          notFound: n('user_not_found'),
          invalid: n('invalid'),
          invited: n('invitation_sent'),
          duplicate: n('duplicate'),
        );
      });
      _snack(l10n.organizationMembersPhonesDone);
    } on ApiException catch (e) {
      if (mounted) _snack(apiErrorText(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final kind = widget.kind;
    final students = kind == PeopleKind.students;
    final sections = students
        ? ref.watch(sectionChoicesProvider).value ??
              const <({String id, String label})>[]
        : const <({String id, String label})>[];
    final chosen = students && _section != null
        ? _sectionLabel(sections)
        : null;
    final l = _lookup;
    final lookupLabel = switch (kind) {
      PeopleKind.teachers => l10n.organizationMembersLookupLabelTEACHER,
      PeopleKind.assistants => l10n.organizationMembersLookupLabelASSISTANT,
      PeopleKind.students => l10n.organizationMembersLookupLabelSTUDENT,
    };
    final phoneHint = switch (kind) {
      PeopleKind.teachers => l10n.organizationMembersPhoneListHintTEACHER,
      PeopleKind.assistants => l10n.organizationMembersPhoneListHintASSISTANT,
      PeopleKind.students => l10n.organizationMembersPhoneListHintSTUDENT,
    };
    final s = _summary;
    return PopScope(
      canPop: !_added,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(true);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_addLabel(l10n, kind))),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  Text(
                    l10n.organizationMembersAddIntro,
                    style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('lookup-query'),
                          controller: _query,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(labelText: lookupLabel),
                          onChanged: (_) => setState(() => _lookup = null),
                          onSubmitted: (_) => _find(),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      OutlinedButton(
                        key: const Key('lookup-find'),
                        onPressed: _busy ? null : _find,
                        child: Text(l10n.organizationMembersFind),
                      ),
                    ],
                  ),
                  if (students) ...[
                    const SizedBox(height: AppSpacing.md),
                    DropdownButtonFormField<String?>(
                      key: const Key('add-section'),
                      initialValue: _section,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: ref.levels(
                          context,
                          l10n.organizationMembersSectionLabel,
                        ),
                        helperText: ref.levels(
                          context,
                          l10n.organizationMembersSectionHint,
                        ),
                        helperMaxLines: 3,
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          child: Text(
                            ref.levels(
                              context,
                              l10n.organizationMembersSectionLater,
                            ),
                          ),
                        ),
                        for (final o in sections)
                          DropdownMenuItem<String?>(
                            value: o.id,
                            child: Text(o.label),
                          ),
                      ],
                      onChanged: (v) => setState(() => _section = v),
                    ),
                  ],
                  if (l != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    AppCard(
                      key: const Key('lookup-result'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!l.found) ...[
                            Text(
                              l10n.organizationMembersNotFoundTitle,
                              style: text.titleSmall,
                            ),
                            if (l.message != null)
                              Text(
                                l.message!,
                                style: text.bodySmall?.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                            const SizedBox(height: AppSpacing.sm),
                            FilledButton(
                              key: const Key('lookup-add'),
                              onPressed: _busy
                                  ? null
                                  : () => _addOrInvite(sections),
                              child: Text(l10n.organizationMembersSendInvite),
                            ),
                          ] else ...[
                            Text(
                              (l.name ?? '').isNotEmpty
                                  ? l.name!
                                  : l10n.organizationMembersUnnamed,
                              style: text.titleSmall,
                            ),
                            Text(
                              [
                                l10n.organizationMembersTeacherId(
                                  l.teacherId ?? '—',
                                ),
                                if (l.studentId != null)
                                  l10n.organizationMembersStudentId(
                                    l.studentId!,
                                  ),
                              ].join(' · '),
                              style: text.bodySmall,
                            ),
                            Text(
                              '${l10n.organizationMembersEmail}: ${l.email ?? '—'}',
                              style: text.bodySmall,
                            ),
                            Text(
                              '${l10n.organizationMembersPhone}: ${l.phone ?? '—'}',
                              style: text.bodySmall,
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            if (l.activeMember && chosen == null)
                              Text(
                                l10n.organizationMembersAlreadyMember,
                                style: text.bodySmall?.copyWith(
                                  color: colors.danger,
                                ),
                              )
                            else
                              FilledButton(
                                key: const Key('lookup-add'),
                                onPressed:
                                    _busy || (!l.verified && !l.activeMember)
                                    ? null
                                    : () => _addOrInvite(sections),
                                child: Text(
                                  chosen != null
                                      ? l10n.organizationMembersAddToSection(
                                          chosen,
                                        )
                                      : l.member
                                      ? l10n.organizationMembersRestore
                                      : l10n.organizationMembersAddToOrg,
                                ),
                              ),
                            if (!l.verified)
                              Text(
                                l10n.organizationMembersNotVerified,
                                style: text.bodySmall?.copyWith(
                                  color: colors.danger,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const Divider(height: AppSpacing.xl * 2),
                  Text(
                    l10n.organizationMembersPhoneListTitle,
                    style: text.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    key: const Key('phone-list'),
                    controller: _phones,
                    minLines: 4,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    decoration: InputDecoration(
                      labelText: l10n.organizationMembersPhoneListLabel,
                      helperText: phoneHint,
                      helperMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: OutlinedButton(
                      key: const Key('phone-list-add'),
                      onPressed: _busy ? null : _addPhones,
                      child: Text(l10n.organizationMembersAddPhones),
                    ),
                  ),
                  if (s != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      l10n.organizationMembersSummary(
                        s.imported,
                        s.already,
                        s.notFound,
                        s.invalid,
                        s.invited,
                        s.duplicate,
                      ),
                      key: const Key('phone-summary'),
                      style: text.bodyMedium,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
