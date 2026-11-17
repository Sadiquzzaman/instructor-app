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
import 'package:instructor_app/features/auth/data/signup_repository.dart';
import 'package:instructor_app/features/auth/data/signup_validation.dart';
import 'package:instructor_app/features/auth/widgets/auth_page.dart';
import 'package:instructor_app/features/auth/widgets/otp_entry.dart';

/// Step 2 of sign-up: the 6-digit SMS code (the web's VerifyCode). On success
/// it returns to the login screen with the web's message (teacher pending,
/// the organisation number, or "verified").
class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({required this.pending, super.key});

  final PendingSignUp pending;

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  final _otp = TextEditingController();
  String? _otpError;
  String? _formError;
  bool _loading = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading) return;
    final l10n = context.l10n;
    if (_otp.text.length != OtpField.length) {
      setState(() => _otpError = l10n.validationOtpIncomplete);
      return;
    }
    setState(() {
      _otpError = null;
      _formError = null;
      _loading = true;
    });
    try {
      final result = await ref
          .read(signUpRepositoryProvider)
          .verify(widget.pending, _otp.text);
      if (!mounted) return;
      final number = result.organizationNumber;
      ref
          .read(loginNoticeProvider.notifier)
          .show(
            number != null
                ? l10n.authSignupOrganizationNumber('$number')
                : result.kind == SignUpKind.teacher
                ? l10n.authSignupTeacherPending
                : l10n.authOtpVerifiedDescription,
          );
      context.go(AppRoutes.login);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _formError =
            e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout
            ? context.l10n.appNoConnection
            : context.l10n.authOtpFailedDescription,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    return AuthPage(
      title: l10n.authOtpTitle,
      intro: RichMessage(
        '${l10n.authOtpSentTo(SignUpValidation.mask(widget.pending.phone))} '
        '${l10n.authOtpCheckSms}',
        textAlign: TextAlign.center,
        styles: {
          'target': TextStyle(fontWeight: FontWeight.w600, color: colors.ink),
        },
      ),
      children: [
        if (_formError != null) ...[
          NoticeBox(message: _formError!),
          const SizedBox(height: AppSpacing.lg),
        ],
        OtpField(
          controller: _otp,
          errorText: _otpError,
          onSubmitted: (_) => _verify(),
        ),
        const SizedBox(height: AppSpacing.md),
        ResendTimer(
          onResend: () async {
            try {
              await ref.read(signUpRepositoryProvider).resend(widget.pending);
            } on ApiException {
              if (mounted) {
                setState(() => _formError = context.l10n.appSignupFailed);
              }
            }
          },
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: l10n.authOtpSubmit,
          onPressed: _verify,
          loading: _loading,
          expand: true,
        ),
      ],
    );
  }
}
