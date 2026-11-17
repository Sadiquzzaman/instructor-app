import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
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
