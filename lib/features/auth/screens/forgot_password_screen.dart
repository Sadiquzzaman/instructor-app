import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/rich_message.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/features/auth/data/auth_error_text.dart';
import 'package:instructor_app/features/auth/data/login_validation.dart';
import 'package:instructor_app/features/auth/data/signup_repository.dart';
import 'package:instructor_app/features/auth/data/signup_validation.dart';
import 'package:instructor_app/features/auth/widgets/auth_page.dart';
import 'package:instructor_app/features/auth/widgets/otp_entry.dart';

enum _Step { request, code, reset }

/// Reset a forgotten password in three steps (the web's ForgotPasswordForm):
/// send a code to the email or phone, enter it, set a new password. A reset
/// signs out every device (PM-01).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _identifier = TextEditingController();
  final _otp = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  _Step _step = _Step.request;
  ResetCodeSent _sent = const ResetCodeSent();
  Map<String, String> _errors = const {};
  String? _formError;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_identifier, _otp, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  SignUpRepository get _repo => ref.read(signUpRepositoryProvider);

  String _failure(ApiException e) =>
      authErrorText(e, context.l10n) ??
      (e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout
          ? context.l10n.appNoConnection
          : context.l10n.appResetFailed);

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() {
      _formError = null;
      _loading = true;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _formError = _failure(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    final error = LoginValidation.identifier(_identifier.text, context.l10n);
    setState(() => _errors = {'identifier': ?error});
    if (error != null) return;
    await _run(() async {
      final sent = await _repo.requestReset(_identifier.text);
      if (mounted) {
        setState(() {
          _sent = sent;
          _step = _Step.code;
        });
      }
    });
  }

  Future<void> _checkCode() async {
    if (_otp.text.length != OtpField.length) {
      setState(() => _errors = {'otp': context.l10n.validationOtpIncomplete});
      return;
    }
    setState(() => _errors = const {});
    await _run(() async {
      await _repo.verifyReset(_identifier.text, _otp.text);
      if (mounted) setState(() => _step = _Step.reset);
    });
  }

  Future<void> _reset() async {
    final l10n = context.l10n;
    final errors = SignUpValidation.reset(_password.text, _confirm.text, l10n);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;
    await _run(() async {
      await _repo.resetPassword(
        identifier: _identifier.text,
        otp: _otp.text,
        password: _password.text,
        confirmPassword: _confirm.text,
      );
      if (!mounted) return;
      ref
          .read(loginNoticeProvider.notifier)
          .show(l10n.authForgotUpdatedDescription);
      context.go(AppRoutes.login);
    });
  }

  /// "We've sent a 6-digit code to 017****678." plus where to look.
  String _sentText(AppLocalizations l10n) {
    final target = switch (_sent.channel) {
      'email' => _sent.maskedEmail,
      'sms' => _sent.maskedPhone,
      _ => [
        _sent.maskedPhone,
        _sent.maskedEmail,
      ].whereType<String>().join(' ${l10n.authForgotAnd} '),
    };
    final hint = switch (_sent.channel) {
      'email' => l10n.authOtpCheckEmail,
      'sms' => l10n.authOtpCheckSms,
      _ => l10n.authOtpCheckInbox,
    };
    final sent = target == null || target.isEmpty
        ? l10n.authOtpSent
        : l10n.authOtpSentTo(target);
    return '$sent $hint';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final error = _formError == null
        ? const <Widget>[]
        : [
            NoticeBox(message: _formError!),
            const SizedBox(height: AppSpacing.lg),
          ];
    return switch (_step) {
      _Step.request => AuthPage(
        title: l10n.authForgotTitle,
        intro: Text(l10n.authForgotIntro),
        children: [
          ...error,
          AppTextField(
            key: const Key('forgot-identifier'),
            label: l10n.authFieldsEmailOrPhone,
            hint: l10n.authFieldsEnterEmailOrPhone,
            controller: _identifier,
            errorText: _errors['identifier'],
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.username],
            onSubmitted: (_) => _sendCode(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: l10n.authForgotSend,
            onPressed: _sendCode,
            loading: _loading,
            expand: true,
          ),
          const SizedBox(height: AppSpacing.lg),
          AuthFooterLink(
            text: l10n.authForgotRemember,
            label: l10n.authLogIn,
            onTap: () => context.go(AppRoutes.login),
          ),
        ],
      ),
      _Step.code => AuthPage(
        title: l10n.authOtpTitle,
        intro: RichMessage(
          _sentText(l10n),
          textAlign: TextAlign.center,
          styles: {
            'target': TextStyle(fontWeight: FontWeight.w600, color: colors.ink),
          },
        ),
        children: [
          ...error,
          OtpField(
            controller: _otp,
            errorText: _errors['otp'],
            onSubmitted: (_) => _checkCode(),
          ),
          const SizedBox(height: AppSpacing.md),
          ResendTimer(
            onResend: () async {
              try {
                final sent = await _repo.requestReset(_identifier.text);
                if (mounted) setState(() => _sent = sent);
              } on ApiException catch (e) {
                if (mounted) setState(() => _formError = _failure(e));
              }
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: l10n.authOtpSubmit,
            onPressed: _checkCode,
            loading: _loading,
            expand: true,
          ),
        ],
      ),
      _Step.reset => AuthPage(
        title: l10n.authForgotResetTitle,
        children: [
          ...error,
          AppTextField(
            key: const Key('forgot-password'),
            label: l10n.authFieldsNewPassword,
            hint: l10n.authFieldsNewPasswordPlaceholder,
            controller: _password,
            errorText: _errors['password'],
            obscure: true,
            showLabel: l10n.authShowPassword,
            hideLabel: l10n.authHidePassword,
            autofillHints: const [AutofillHints.newPassword],
          ),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const Key('forgot-confirm'),
            label: l10n.authFieldsConfirmPassword,
            hint: l10n.authFieldsConfirmNewPasswordPlaceholder,
            controller: _confirm,
            errorText: _errors['confirm_password'],
            obscure: true,
            showLabel: l10n.authShowPassword,
            hideLabel: l10n.authHidePassword,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _reset(),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppButton(
            label: l10n.authForgotReset,
            onPressed: _reset,
            loading: _loading,
            expand: true,
          ),
        ],
      ),
    };
  }
}
