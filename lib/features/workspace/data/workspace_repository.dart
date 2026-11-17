import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';

/// One place a person can work (`GET /auth/contexts`): an organisation, their
/// own teaching workspace, or a teacher they learn from (API guide §3).
@immutable
class WorkspaceContext {
  const WorkspaceContext({
    required this.type,
    required this.key,
    required this.label,
    required this.actionable,
    this.roleLabel,
    this.organizationId,
    this.organizationStatus,
    this.teacherId,
  });

  /// `organization`, `personal_teacher` or `individual_teacher`.
  final String type;
  final String key;

  /// The organisation's or teacher's name, from the API (not translated).
  final String label;

  /// The role in English from the API; shown as it comes until the API sends
  /// a code for it.
  final String? roleLabel;
  final bool actionable;
  final String? organizationId;

  /// `approved`, `pending`, … (organisations only).
  final String? organizationStatus;
  final String? teacherId;

  bool get isPending => organizationStatus == 'pending';

  static WorkspaceContext? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = json['type'], key = json['key'];
    if (type is! String || key is! String) return null;
    return WorkspaceContext(
      type: type,
      key: key,
      label: (json['label'] as String?) ?? '',
      roleLabel: json['role_label'] as String?,
      actionable: json['actionable'] == true,
      organizationId: json['organization_id'] as String?,
      organizationStatus: json['organization_status'] as String?,
      teacherId: json['teacher_id'] as String?,
    );
  }

  /// Is [session] in this workspace?
  bool isCurrent(Session? session) {
    if (session == null) return false;
    return switch (type) {
      'organization' =>
        session.isOrganization && session.organizationId == organizationId,
      'personal_teacher' => session.contextType == 'personal_teacher',
      'individual_teacher' =>
        session.contextType == 'individual_teacher' &&
            session.teacherId == teacherId,
      _ => false,
    };
  }
}

class WorkspaceRepository {
  WorkspaceRepository({required this.api, required this.sessions});

  final ApiClient api;
  final SessionHolder sessions;

  Future<List<WorkspaceContext>> list() async {
    final r = await api.get('/auth/contexts');
    final payload = r.payload;
    if (payload is! List) return const [];
    return payload.map(WorkspaceContext.fromJson).nonNulls.toList();
  }

  /// `POST /auth/select-context`: new tokens for that workspace, on the same
  /// signed-in device. Only ids the API listed are sent.
  Future<Session> select(WorkspaceContext context) async {
    final r = await api.post(
      '/auth/select-context',
      data: {
        'type': context.type,
        if (context.type == 'organization')
          'organization_id': context.organizationId,
        if (context.type == 'individual_teacher')
          'teacher_id': context.teacherId,
      },
    );
    final session = Session.fromPayload(r.object);
    await sessions.save(session);
    return session;
  }
}

final workspaceRepositoryProvider = Provider<WorkspaceRepository>(
  (ref) => WorkspaceRepository(
    api: ref.watch(apiClientProvider),
    sessions: ref.watch(sessionHolderProvider),
  ),
);

/// The signed-in person's workspaces; loaded again for another person.
final workspaceContextsProvider = FutureProvider<List<WorkspaceContext>>(
  (ref) {
    final userId = ref.watch(sessionProvider.select((s) => s?.userId));
    if (userId == null) return const [];
    return ref.read(workspaceRepositoryProvider).list();
  },
  // No automatic retries: a failure shows "Try again" at once.
  retry: (retryCount, error) => null,
);

/// True when the person must choose a workspace first: signed in without one
/// (`context_type: individual`) and more than one to choose from. With one,
/// the API already put them in it at sign-in (`requires_context_selection`
/// is always false; PR 5 notes).
final needsWorkspaceChoiceProvider = Provider<AsyncValue<bool>>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null || session.contextType != 'individual') {
    return const AsyncData(false);
  }
  return ref
      .watch(workspaceContextsProvider)
      .whenData((all) => all.where((c) => c.actionable).length > 1);
});

/// Switches workspace. Everything that belongs to the old one is dropped by
/// itself (it watches [workspaceKeyProvider]). Without a language of their
/// own, the person sees the new organisation's default language.
Future<void> switchWorkspace(WidgetRef ref, WorkspaceContext context) async {
  final session = await ref.read(workspaceRepositoryProvider).select(context);
  final language = session.locale ?? session.organizationDefaultLocale;
  if (session.locale == null && (language == 'bn' || language == 'en')) {
    await ref
        .read(languageProvider.notifier)
        .choose(AppLanguages.from(language));
  }
}
