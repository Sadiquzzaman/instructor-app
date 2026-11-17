import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/auth/session_store.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/device/device_info.dart';

/// Where the session is stored (overridden in tests).
final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

/// The current session; null when signed out.
final sessionHolderProvider = Provider<SessionHolder>((ref) {
  final holder = SessionHolder(ref.watch(sessionStoreProvider));
  ref.onDispose(holder.dispose);
  return holder;
});

/// The current session, rebuilt whenever it changes (sign-in, refresh,
/// workspace switch, sign-out). Watch this, not [sessionHolderProvider], in
/// anything that must react.
final sessionProvider = Provider<Session?>((ref) {
  final holder = ref.watch(sessionHolderProvider);
  void changed() => ref.invalidateSelf();
  holder.addListener(changed);
  ref.onDispose(() => holder.removeListener(changed));
  return holder.current;
});

/// Which workspace the session is in, or null when signed out or signed in
/// without one (several to choose from). Everything that belongs to a
/// workspace watches this, so switching workspace or signing out drops it
/// (CLAUDE.md multi-tenancy rule). A token refresh keeps the same key.
final workspaceKeyProvider = Provider<String?>((ref) {
  final s = ref.watch(sessionProvider);
  if (s == null) return null;
  return switch (s.contextType) {
    'organization' when s.organizationId != null =>
      '${s.userId}/organization/${s.organizationId}',
    'personal_teacher' => '${s.userId}/personal_teacher',
    'individual_teacher' when s.teacherId != null =>
      '${s.userId}/individual_teacher/${s.teacherId}',
    _ => null,
  };
});

/// This phone, read once (overridden in tests).
final deviceInfoProvider = Provider<Future<DeviceInfo>>(
  (ref) => DeviceInfo.load(),
);

/// The API client. When a refresh is refused the session is cleared; the
/// router (PR 7) sends the user to the login screen.
final apiClientProvider = Provider<ApiClient>((ref) {
  final sessions = ref.watch(sessionHolderProvider);
  return ApiClient(
    baseUrl: AppConfig.apiBaseUrl,
    sessions: sessions,
    device: () => ref.read(deviceInfoProvider),
    onSessionExpired: sessions.clear,
  );
});
