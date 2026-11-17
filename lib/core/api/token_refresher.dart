import 'package:dio/dio.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_response.dart';
import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_holder.dart';
import 'package:instructor_app/core/device/device_info.dart';

/// Exchanges the refresh token for a new pair: `POST /auth/refresh`
/// (API guide §3).
///
/// - **One at a time.** The refresh token rotates and the old one dies 60 s
///   later (reusing it after that signs the device out), so every request
///   that gets a 401 at the same moment waits for the same refresh.
/// - **Stored before use.** The new pair is saved before any request is
///   retried.
class TokenRefresher {
  TokenRefresher({
    required this.dio,
    required this.sessions,
    required this.device,
  });

  /// A Dio without the auth interceptor, so a refresh never refreshes.
  final Dio dio;
  final SessionHolder sessions;
  final Future<DeviceInfo> Function() device;

  Future<Session>? _inFlight;

  /// Number of refresh calls actually sent (for tests and logs).
  int calls = 0;

  Future<Session> refresh() => _inFlight ??= _refresh().whenComplete(() {
    _inFlight = null;
  });

  Future<Session> _refresh() async {
    final old = sessions.current;
    if (old == null) {
      throw const ApiException(kind: ApiErrorKind.unauthorized);
    }
    calls++;
    final Response<Object?> response;
    try {
      response = await dio.post<Object?>(
        '/auth/refresh',
        data: {
          'refreshToken': old.refreshToken,
          // Stay in the organisation workspace (only an id the API gave us).
          if (old.isOrganization) 'organization_id': old.organizationId,
          'device': (await device()).toJson(),
        },
      );
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
    final session = Session.fromPayload(
      ApiResponse.fromJson(response.data).object,
    );
    await sessions.save(session);
    return session;
  }
}
