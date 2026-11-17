import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/device/device_info.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';
import 'package:instructor_app/core/l10n/level_labels.dart';
import 'package:instructor_app/features/auth/data/login_validation.dart';

/// Signing in and out (API guide §3, PM-01).
class AuthRepository {
  AuthRepository({
    required this.api,
    required this.sessions,
    required this.device,
  });

  final ApiClient api;
  final SessionHolder sessions;
  final Future<DeviceInfo> Function() device;

  /// `POST /auth/login` with an email or a phone number, the password and
  /// this device. Stores the session. A wrong password is a 401 without a
  /// code ([ApiErrorKind.unauthorized]).
  Future<Session> login({
    required String identifier,
    required String password,
  }) async {
    final r = await api.post(
      '/auth/login',
      auth: false,
      data: {
        ...LoginValidation.identifierField(identifier),
        'password': password,
        'device': (await device()).toJson(),
      },
    );
    final session = Session.fromPayload(r.object);
    await sessions.save(session);
    return session;
  }

  /// Ends this device's session on the server (`POST /auth/logout`, always
  /// 200), then forgets it here even if the server could not be reached.
  Future<void> logout() async {
    final current = sessions.current;
    if (current != null) {
      try {
        await api.post(
          '/auth/logout',
          data: {'refreshToken': current.refreshToken},
        );
      } on ApiException {
        // Signed out here anyway; the token expires on its own.
      }
    }
    await sessions.clear();
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    api: ref.watch(apiClientProvider),
    sessions: ref.watch(sessionHolderProvider),
    device: () => ref.read(deviceInfoProvider),
  ),
);

/// Signs in and applies the account's language: the account's own choice,
/// else the organisation's default (web: lib/authSession.ts). Without either
/// the language chosen on this phone stays.
Future<Session> signIn(
  WidgetRef ref, {
  required String identifier,
  required String password,
}) async {
  final session = await ref
      .read(authRepositoryProvider)
      .login(identifier: identifier, password: password);
  final language = session.locale ?? session.organizationDefaultLocale;
  if (language == 'bn' || language == 'en') {
    await ref
        .read(languageProvider.notifier)
        .choose(AppLanguages.from(language));
  }
  return session;
}

/// Signs out and drops everything that belonged to the session's workspace.
Future<void> signOut(WidgetRef ref) async {
  await ref.read(authRepositoryProvider).logout();
  ref.invalidate(levelLabelsProvider);
}
