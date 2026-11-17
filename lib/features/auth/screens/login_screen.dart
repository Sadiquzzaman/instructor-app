import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_switcher.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/features/auth/data/auth_repository.dart';
import 'package:instructor_app/features/auth/data/login_validation.dart';

/// Log in with an email or phone number and a password (the web's /login).
/// Google sign-in waits for the server (PM-02); forgot password and sign-up
/// come in the next pull request. On success the router moves on by itself.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  String? _identifierError;
  String? _passwordError;
  String? _formError;
  bool _loading = false;

  @override
  void dispose() {
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final l10n = context.l10n;
    final identifierError = LoginValidation.identifier(_identifier.text, l10n);
    // As on the web: the password is checked once the identifier is fine.
    final passwordError = identifierError == null
        ? LoginValidation.password(_password.text, l10n)
        : null;
    setState(() {
      _identifierError = identifierError;
      _passwordError = passwordError;
      _formError = null;
    });
    if (identifierError != null || passwordError != null) return;

    setState(() => _loading = true);
    try {
      await signIn(ref, identifier: _identifier.text, password: _password.text);
      TextInput.finishAutofillContext();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _formError = _messageFor(e, context.l10n));
    } on FormatException {
      if (!mounted) return;
      setState(() => _formError = context.l10n.authLoginFailedDescription);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static String _messageFor(ApiException e, AppLocalizations l10n) =>
      switch (e.kind) {
        // No code on sign-in errors: 401 is a wrong identifier or password.
        ApiErrorKind.unauthorized => l10n.appLoginInvalid,
        ApiErrorKind.network || ApiErrorKind.timeout => l10n.appNoConnection,
        _ => l10n.authLoginFailedDescription,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: LanguageSwitcher(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      AppConfig.appName,
                      textAlign: TextAlign.center,
                      style: text.headlineMedium?.copyWith(
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      l10n.authLoginTitle,
                      style: text.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    if (_formError != null) ...[
                      _ErrorBox(message: _formError!),
                      const SizedBox(height: AppSpacing.lg),
                    ],
                    AppTextField(
                      key: const Key('login-identifier'),
                      label: l10n.authFieldsEmailOrPhone,
                      hint: l10n.authFieldsEmailOrPhonePlaceholder,
                      controller: _identifier,
                      errorText: _identifierError,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [
                        AutofillHints.username,
                        AutofillHints.email,
                        AutofillHints.telephoneNumber,
                      ],
                      onChanged: (_) {
                        if (_identifierError != null) {
                          setState(() => _identifierError = null);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      key: const Key('login-password'),
                      label: l10n.authFieldsPassword,
                      hint: l10n.authFieldsPasswordPlaceholder,
                      controller: _password,
                      errorText: _passwordError,
                      obscure: true,
                      showLabel: l10n.authShowPassword,
                      hideLabel: l10n.authHidePassword,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onChanged: (_) {
                        if (_passwordError != null) {
                          setState(() => _passwordError = null);
                        }
                      },
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AppButton(
                      label: l10n.authLoginSubmit,
                      onPressed: _submit,
                      loading: _loading,
                      expand: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.dangerSoft,
          borderRadius: AppRadius.inputAll,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline, color: colors.danger),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.danger),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
