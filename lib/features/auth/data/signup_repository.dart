import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/auth/data/signup_validation.dart';

/// A sign-up waiting for its SMS code. Keeping the request lets "Resend code"
/// send it again: the API sends a new code when an unverified phone number
/// registers again (auth.controller.ts, POST /auth/register).
class PendingSignUp {
  const PendingSignUp({
    required this.kind,
    required this.phone,
    required this.request,
  });

  final SignUpKind kind;
  final String phone;

  /// The exact body that was sent (with the password; kept in memory only).
  final Map<String, Object?> request;

  String get path => kind == SignUpKind.organization
      ? '/auth/register/organization'
      : '/auth/register';
}

enum SignUpKind { student, teacher, organization }

/// The result of a verified sign-up, for the message on the login screen.
class VerifiedSignUp {
  const VerifiedSignUp({required this.kind, this.organizationNumber});

  final SignUpKind kind;

  /// Shown to an organisation's owner (they need it later).
  final Object? organizationNumber;
}

/// Where the reset code went (`POST /auth/forgot-password`).
class ResetCodeSent {
  const ResetCodeSent({this.channel, this.maskedPhone, this.maskedEmail});

  /// `email`, `sms` or null.
  final String? channel;
  final String? maskedPhone;
  final String? maskedEmail;
}

/// Sign-up, OTP and password reset (API guide §3). None of these needs a
/// session, so every call is sent without Authorization.
class SignUpRepository {
  SignUpRepository(this.api);

  final ApiClient api;

  /// Students and teachers: `POST /auth/register`. A teacher signs up as a
  /// student with `request_teacher` and their workspace type; an admin
  /// approves them later.
  Future<PendingSignUp> register({
    required SignUpForm form,
    required bool teacher,
    String workspaceType = 'ACADEMIC',
  }) async {
    final request = <String, Object?>{
      'full_name': form.fullName.trim(),
      'phone': form.phone.trim(),
      'email': form.email.trim().toLowerCase(),
      'password': form.password,
      'confirm_password': form.confirmPassword,
      'role': 'STUDENT',
      'request_teacher': teacher,
      if (teacher) 'workspace_type': workspaceType,
    };
    final pending = PendingSignUp(
      kind: teacher ? SignUpKind.teacher : SignUpKind.student,
      phone: form.phone.trim(),
      request: request,
    );
    await api.post(pending.path, data: request, auth: false);
    return pending;
  }

  /// Organisations: `POST /auth/register/organization` (School or IELTS
  /// centre). A platform admin approves the organisation later.
  Future<PendingSignUp> registerOrganization({
    required SignUpForm form,
    required String organizationName,
    required String kind,
  }) async {
    final request = <String, Object?>{
      'kind': kind,
      'organization_name': organizationName.trim(),
      'full_name': form.fullName.trim(),
      'phone': form.phone.trim(),
      'email': form.email.trim().toLowerCase(),
      'password': form.password,
      'confirm_password': form.confirmPassword,
    };
    final pending = PendingSignUp(
      kind: SignUpKind.organization,
      phone: form.phone.trim(),
      request: request,
    );
    await api.post(pending.path, data: request, auth: false);
    return pending;
  }

  /// Sends the same sign-up again, which sends a new code.
  Future<void> resend(PendingSignUp pending) =>
      api.post(pending.path, data: pending.request, auth: false);

  /// `POST /auth/register/verify-otp` with the phone and the 6-digit code.
  Future<VerifiedSignUp> verify(PendingSignUp pending, String otp) async {
    final r = await api.post(
      '/auth/register/verify-otp',
      data: {'phone': pending.phone, 'otp': otp},
      auth: false,
    );
    final payload = r.payload;
    Object? number;
    if (payload is Map) {
      final data = payload['data'];
      if (data is Map && data['organization'] is Map) {
        number = (data['organization'] as Map)['organization_number'];
      }
    }
    return VerifiedSignUp(kind: pending.kind, organizationNumber: number);
  }

  /// `POST /auth/forgot-password`: a code by email or SMS.
  Future<ResetCodeSent> requestReset(String identifier) async {
    final r = await api.post(
      '/auth/forgot-password',
      data: {'identifier': _identifier(identifier)},
      auth: false,
    );
    final payload = r.payload;
    final data = payload is Map ? payload['data'] : null;
    if (data is! Map) return const ResetCodeSent();
    return ResetCodeSent(
      channel: data['channel'] as String?,
      maskedPhone: data['maskedPhone'] as String?,
      maskedEmail: data['maskedEmail'] as String?,
    );
  }

  /// `POST /auth/reset-password/verify-otp`.
  Future<void> verifyReset(String identifier, String otp) => api.post(
    '/auth/reset-password/verify-otp',
    data: {'identifier': _identifier(identifier), 'otp': otp},
    auth: false,
  );

  /// `POST /auth/reset-password`. Signs out every device (PM-01).
  Future<void> resetPassword({
    required String identifier,
    required String otp,
    required String password,
    required String confirmPassword,
  }) => api.post(
    '/auth/reset-password',
    data: {
      'identifier': _identifier(identifier),
      'otp': otp,
      'password': password,
      'confirm_password': confirmPassword,
    },
    auth: false,
  );

  /// As the API's transform: trimmed; emails lower-cased.
  static String _identifier(String raw) {
    final v = raw.trim();
    return v.contains('@') ? v.toLowerCase() : v;
  }
}

final signUpRepositoryProvider = Provider<SignUpRepository>(
  (ref) => SignUpRepository(ref.watch(apiClientProvider)),
);

/// A one-time message for the login screen after a verified sign-up or a
/// password reset (the web shows it as a toast before going to /login).
final loginNoticeProvider = NotifierProvider<LoginNotice, String?>(
  LoginNotice.new,
);

class LoginNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void show(String message) => state = message;

  void clear() => state = null;
}
