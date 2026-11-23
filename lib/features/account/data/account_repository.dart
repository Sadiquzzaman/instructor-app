import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// `GET /auth/profile`: who is signed in. Shown read-only, as on the web.
@immutable
class Profile {
  const Profile({
    required this.fullName,
    required this.role,
    this.email,
    this.phone,
    this.verified = false,
    this.createdAt,
  });

  final String fullName;
  final String role;
  final String? email;
  final String? phone;
  final bool verified;
  final DateTime? createdAt;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
    fullName: (j['full_name'] as String?) ?? '',
    role: (j['role'] as String?) ?? '',
    email: j['email'] as String?,
    phone: j['phone'] as String?,
    verified: j['is_verified'] == true,
    createdAt: DateTime.tryParse((j['created_at'] as String?) ?? ''),
  );
}

/// One signed-in device (`GET /auth/sessions`, PM-01).
@immutable
class SignedInDevice {
  const SignedInDevice({
    required this.id,
    required this.platform,
    required this.current,
    this.name,
    this.appVersion,
    this.lastUsedAt,
  });

  final String id;

  /// WEB, ANDROID or IOS.
  final String platform;
  final String? name;
  final String? appVersion;
  final DateTime? lastUsedAt;

  /// This phone.
  final bool current;

  static SignedInDevice? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    return SignedInDevice(
      id: json['id'] as String,
      platform: (json['platform'] as String?) ?? 'WEB',
      name: json['device_name'] as String?,
      appVersion: json['app_version'] as String?,
      lastUsedAt: DateTime.tryParse(
        (json['last_used_at'] as String?) ??
            (json['created_at'] as String?) ??
            '',
      ),
      current: json['current'] == true,
    );
  }
}

/// How one kind of message reaches me (`GET /me/notification-prefs`,
/// FND-12). In-app (the bell) is always on; SMS and email are switchable
/// where [allowed] lists them.
@immutable
class NotificationPref {
  const NotificationPref({
    required this.eventType,
    required this.channels,
    required this.allowed,
  });

  /// "attendance.absent", "exam.scheduled" and so on.
  final String eventType;
  final List<String> channels;
  final List<String> allowed;

  static NotificationPref? fromJson(Object? json) {
    if (json is! Map || json['event_type'] is! String) return null;
    List<String> list(Object? v) =>
        v is List ? v.whereType<String>().toList() : const [];
    return NotificationPref(
      eventType: json['event_type'] as String,
      channels: list(json['channels']),
      allowed: list(json['allowed']),
    );
  }
}

/// A student's request to become a teacher (`/teacher-requests/me`).
@immutable
class TeacherRequest {
  const TeacherRequest({required this.status, this.createdAt});

  /// pending, approved or rejected.
  final String status;
  final DateTime? createdAt;

  static TeacherRequest? fromJson(Object? json) {
    if (json is! Map || json['status'] is! String) return null;
    return TeacherRequest(
      status: json['status'] as String,
      createdAt: DateTime.tryParse((json['created_at'] as String?) ?? ''),
    );
  }
}

class AccountRepository {
  AccountRepository(this.api);

  final ApiClient api;

  Future<Profile> profile() async =>
      Profile.fromJson((await api.get('/auth/profile')).object);

  /// Saves the language on the account (`PATCH /user/me/locale`), so emails,
  /// SMS and other devices use it too.
  Future<void> saveLocale(String languageCode) =>
      api.patch('/user/me/locale', data: {'locale': languageCode});

  /// `POST /auth/change-password`. Signs out the other devices; this one
  /// stays signed in. A wrong current password is a 400 without a code.
  Future<void> changePassword({
    required String current,
    required String next,
    required String confirm,
  }) => api.post(
    '/auth/change-password',
    data: {
      'current_password': current,
      'new_password': next,
      'confirm_password': confirm,
    },
  );

  Future<List<SignedInDevice>> devices() async {
    final payload = (await api.get('/auth/sessions')).payload;
    if (payload is! List) return const [];
    return payload.map(SignedInDevice.fromJson).nonNulls.toList();
  }

  Future<List<NotificationPref>> notificationPrefs() async {
    final payload = (await api.get('/me/notification-prefs')).payload;
    if (payload is! List) return const [];
    return payload.map(NotificationPref.fromJson).nonNulls.toList();
  }

  /// Saves the channels for one kind of message; returns them all again.
  Future<List<NotificationPref>> saveNotificationPref(
    String eventType,
    List<String> channels,
  ) async {
    final payload = (await api.put(
      '/me/notification-prefs',
      data: {'event_type': eventType, 'channels': channels},
    )).payload;
    if (payload is! List) return const [];
    return payload.map(NotificationPref.fromJson).nonNulls.toList();
  }

  /// My latest request to become a teacher, or null if I never asked.
  Future<TeacherRequest?> teacherRequest() async =>
      TeacherRequest.fromJson((await api.get('/teacher-requests/me')).payload);

  Future<TeacherRequest?> askToTeach() async => TeacherRequest.fromJson(
    (await api.post('/teacher-requests', data: <String, Object?>{})).payload,
  );

  Future<void> signOutDevice(String id) => api.delete('/auth/sessions/$id');

  /// Returns how many devices were signed out.
  Future<int> signOutOthers() async {
    final r = await api.post(
      '/auth/sessions/revoke-others',
      data: <String, Object?>{},
    );
    final p = r.payload;
    return p is Map ? ((p['signed_out'] as num?) ?? 0).toInt() : 0;
  }
}

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(apiClientProvider)),
);

final profileProvider = FutureProvider.autoDispose<Profile>((ref) {
  ref.watch(sessionProvider.select((s) => s?.userId));
  return ref.read(accountRepositoryProvider).profile();
}, retry: (retryCount, error) => null);

final notificationPrefsProvider =
    FutureProvider.autoDispose<List<NotificationPref>>((ref) {
      ref.watch(sessionProvider.select((s) => s?.userId));
      return ref.read(accountRepositoryProvider).notificationPrefs();
    }, retry: (retryCount, error) => null);

final teacherRequestProvider = FutureProvider.autoDispose<TeacherRequest?>((
  ref,
) {
  ref.watch(sessionProvider.select((s) => s?.userId));
  return ref.read(accountRepositoryProvider).teacherRequest();
}, retry: (retryCount, error) => null);

final devicesProvider = FutureProvider.autoDispose<List<SignedInDevice>>((ref) {
  ref.watch(sessionProvider.select((s) => s?.userId));
  return ref.read(accountRepositoryProvider).devices();
}, retry: (retryCount, error) => null);
