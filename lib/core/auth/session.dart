import 'package:flutter/foundation.dart';

/// A signed-in device's session: the tokens and what they say about the
/// workspace, read from the sign-in, refresh and select-context answers
/// (API guide §3–4). Kept in secure storage, never logged.
@immutable
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.role,
    required this.sessionMode,
    required this.contextType,
    required this.workspaceType,
    this.fullName,
    this.locale,
    this.organizationId,
    this.organizationName,
    this.memberRole,
    this.organizationDefaultLocale,
    this.teacherId,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;

  /// The account type: STUDENT, TEACHER, ADMIN, SUPER_ADMIN.
  final String role;

  /// `organization` or `individual`.
  final String sessionMode;

  /// `organization`, `personal_teacher`, `individual_teacher` or `individual`
  /// (signed in with several workspaces and none chosen yet).
  final String contextType;

  /// ACADEMIC or IELTS.
  final String workspaceType;
  final String? fullName;

  /// The account's language (`bn` / `en`), if chosen.
  final String? locale;

  /// Only from the API, only in an organisation session (multi-tenancy rule).
  final String? organizationId;
  final String? organizationName;

  /// OWNER, ADMIN, ASSISTANT, TEACHER, STUDENT, BRANCH_MANAGER.
  final String? memberRole;
  final String? organizationDefaultLocale;
  final String? teacherId;

  bool get isOrganization =>
      sessionMode == 'organization' && organizationId != null;

  /// From an API answer's `payload` (login, refresh, select-context).
  /// Throws [FormatException] when the tokens or the user id are missing.
  factory Session.fromPayload(Map<String, dynamic> p) {
    String req(String key) {
      final v = p[key];
      if (v is String && v.isNotEmpty) return v;
      throw FormatException('The sign-in answer has no "$key".');
    }

    final org = p['organization'];
    final o = org is Map<String, dynamic> ? org : const <String, dynamic>{};
    final sessionMode = (p['session_mode'] as String?) ?? 'individual';
    final orgId = sessionMode == 'organization' ? o['id'] as String? : null;
    return Session(
      accessToken: req('access_token'),
      refreshToken: req('refresh_token'),
      userId: req('id'),
      role: (p['role'] as String?) ?? 'STUDENT',
      sessionMode: sessionMode,
      contextType: (p['context_type'] as String?) ?? 'individual',
      workspaceType:
          (p['workspace_type'] as String?) ??
          (o['workspace_type'] as String?) ??
          'ACADEMIC',
      fullName: p['full_name'] as String?,
      locale: p['locale'] as String?,
      organizationId: orgId,
      organizationName: orgId != null ? o['name'] as String? : null,
      memberRole: orgId != null ? o['role'] as String? : null,
      organizationDefaultLocale: orgId != null
          ? o['default_locale'] as String?
          : null,
      teacherId: p['teacher_id'] as String?,
    );
  }

  /// For secure storage.
  Map<String, dynamic> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'role': role,
    'session_mode': sessionMode,
    'context_type': contextType,
    'workspace_type': workspaceType,
    'full_name': fullName,
    'locale': locale,
    'organization_id': organizationId,
    'organization_name': organizationName,
    'member_role': memberRole,
    'organization_default_locale': organizationDefaultLocale,
    'teacher_id': teacherId,
  };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
    accessToken: j['access_token'] as String,
    refreshToken: j['refresh_token'] as String,
    userId: j['user_id'] as String,
    role: j['role'] as String,
    sessionMode: j['session_mode'] as String,
    contextType: j['context_type'] as String,
    workspaceType: j['workspace_type'] as String,
    fullName: j['full_name'] as String?,
    locale: j['locale'] as String?,
    organizationId: j['organization_id'] as String?,
    organizationName: j['organization_name'] as String?,
    memberRole: j['member_role'] as String?,
    organizationDefaultLocale: j['organization_default_locale'] as String?,
    teacherId: j['teacher_id'] as String?,
  );

  /// Never prints the tokens.
  @override
  String toString() =>
      'Session(user: $userId, mode: $sessionMode, context: $contextType, '
      'workspace: $workspaceType, organization: $organizationId, '
      'member: $memberRole)';
}
