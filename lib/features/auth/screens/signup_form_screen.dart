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
import 'package:instructor_app/features/auth/data/signup_repository.dart';
import 'package:instructor_app/features/auth/data/signup_validation.dart';
import 'package:instructor_app/features/auth/widgets/auth_page.dart';

/// Sign-up details (the web's SignUpInfoForm and OrganizationSignUpForm):
/// student, teacher (Academic or IELTS) or organisation (school or IELTS
/// centre). Then the SMS code (VerifyCodeScreen).
class SignUpFormScreen extends ConsumerStatefulWidget {
  const SignUpFormScreen({required this.kind, super.key});

  final SignUpKind kind;

  @override
  ConsumerState<SignUpFormScreen> createState() => _SignUpFormScreenState();
}

class _SignUpFormScreenState extends ConsumerState<SignUpFormScreen> {
  final _organization = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _agreed = false;
  String _workspaceType = 'ACADEMIC';
  String _orgKind = 'SCHOOL';
  Map<String, String> _errors = const {};
  String? _formError;
  bool _loading = false;

  bool get _isOrganization => widget.kind == SignUpKind.organization;

  @override
  void dispose() {
    for (final c in [
      _organization,
      _name,
      _phone,
      _email,
      _password,
      _confirm,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  SignUpForm get _form => SignUpForm(
    fullName: _name.text,
    phone: _phone.text,
    email: _email.text,
    password: _password.text,
    confirmPassword: _confirm.text,
    agreed: _agreed,
  );

  Future<void> _submit() async {
    if (_loading) return;
    final l10n = context.l10n;
    final errors = SignUpValidation.signUp(
      _form,
      l10n,
      organizationName: _isOrganization ? _organization.text : null,
    );
    setState(() {
      _errors = errors;
      _formError = null;
    });
    if (errors.isNotEmpty) return;

    setState(() => _loading = true);
    try {
      final repo = ref.read(signUpRepositoryProvider);
      final pending = _isOrganization
          ? await repo.registerOrganization(
              form: _form,
              organizationName: _organization.text,
              kind: _orgKind,
            )
          : await repo.register(
              form: _form,
              teacher: widget.kind == SignUpKind.teacher,
              workspaceType: _workspaceType,
            );
      if (!mounted) return;
      await context.push(AppRoutes.signUpVerify, extra: pending);
    } on ApiException catch (e) {
      if (!mounted) return;
      final l10n = context.l10n;
      setState(
        () => _formError = e.isTransient && e.kind != ApiErrorKind.server
            ? l10n.appNoConnection
            : _isOrganization
            ? l10n.authSignupOrganizationFailed
            : l10n.appSignupFailed,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _clear(String field) {
    if (_errors.containsKey(field)) {
      setState(() => _errors = {..._errors}..remove(field));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final title = switch (widget.kind) {
      SignUpKind.student => l10n.authSignupStudentTitle,
      SignUpKind.teacher => l10n.authSignupTeacherTitle,
      SignUpKind.organization => l10n.authSignupOrganizationTitle,
    };
    return AuthPage(
      title: title,
      intro: widget.kind == SignUpKind.teacher
          ? Text(l10n.authSignupTeacherNote)
          : null,
      children: [
        if (_formError != null) ...[
          NoticeBox(message: _formError!),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (widget.kind == SignUpKind.teacher)
          _ChoiceGroup(
            legend: l10n.authSignupTeachKind,
            value: _workspaceType,
            onChanged: (v) => setState(() => _workspaceType = v),
            options: [
              (
                'ACADEMIC',
                l10n.authSignupTeachAcademic,
                l10n.authSignupTeachAcademicHint,
              ),
              (
                'IELTS',
                l10n.authSignupTeachIelts,
                l10n.authSignupTeachIeltsHint,
              ),
            ],
          ),
        if (_isOrganization) ...[
          _ChoiceGroup(
            legend: l10n.authSignupKind,
            value: _orgKind,
            onChanged: (v) => setState(() => _orgKind = v),
            options: [
              (
                'SCHOOL',
                l10n.authSignupKindSchool,
                l10n.authSignupKindSchoolHint,
              ),
              (
                'IELTS_CENTRE',
                l10n.authSignupKindIelts,
                l10n.authSignupKindIeltsHint,
              ),
            ],
          ),
          AppTextField(
            key: const Key('signup-organization'),
            label: l10n.authFieldsOrganizationName,
            hint: l10n.authFieldsOrganizationNamePlaceholder,
            controller: _organization,
            errorText: _errors['organization_name'],
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.organizationName],
            onChanged: (_) => _clear('organization_name'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                key: const Key('signup-name'),
                label: _isOrganization
                    ? l10n.authFieldsOwnerFullName
                    : l10n.authFieldsFullName,
                hint: l10n.authFieldsFullNamePlaceholder,
                controller: _name,
                errorText: _errors['full_name'],
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.name],
                onChanged: (_) => _clear('full_name'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('signup-phone'),
                label: l10n.authFieldsPhone,
                hint: l10n.authFieldsPhonePlaceholder,
                controller: _phone,
                errorText: _errors['phone'],
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.telephoneNumber],
                onChanged: (_) => _clear('phone'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('signup-email'),
                label: l10n.authFieldsEmail,
                hint: l10n.authFieldsEmailPlaceholder,
                controller: _email,
                errorText: _errors['email'],
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                onChanged: (_) => _clear('email'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('signup-password'),
                label: l10n.authFieldsPassword,
                hint: l10n.authFieldsPasswordPlaceholder,
                controller: _password,
                errorText: _errors['password'],
                obscure: true,
                showLabel: l10n.authShowPassword,
                hideLabel: l10n.authHidePassword,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => _clear('password'),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppTextField(
                key: const Key('signup-confirm'),
                label: l10n.authFieldsConfirmPassword,
                hint: l10n.authFieldsConfirmPasswordPlaceholder,
                controller: _confirm,
                errorText: _errors['confirm_password'],
                obscure: true,
                showLabel: l10n.authShowPassword,
                hideLabel: l10n.authHidePassword,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => _clear('confirm_password'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          key: const Key('signup-terms'),
          value: _agreed,
          onChanged: (v) => setState(() {
            _agreed = v ?? false;
            _errors = {..._errors}..remove('terms');
          }),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: RichMessage(
            l10n.authAgreeTerms,
            styles: {
              'terms': TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
              'privacy': TextStyle(
                fontWeight: FontWeight.w600,
                color: colors.ink,
              ),
            },
          ),
          subtitle: _errors['terms'] == null
              ? null
              : Text(_errors['terms']!, style: TextStyle(color: colors.danger)),
        ),
        const SizedBox(height: AppSpacing.lg),
        AppButton(
          label: l10n.authSignUp,
          onPressed: _submit,
          loading: _loading,
          expand: true,
        ),
        const SizedBox(height: AppSpacing.lg),
        AuthFooterLink(
          text: l10n.authHaveAccount,
          label: l10n.authLogIn,
          onTap: () => context.go(AppRoutes.login),
        ),
      ],
    );
  }
}

/// A labelled set of radio choices with hints (the web's RadioGroup).
class _ChoiceGroup extends StatelessWidget {
  const _ChoiceGroup({
    required this.legend,
    required this.value,
    required this.onChanged,
    required this.options,
  });

  final String legend;
  final String value;
  final ValueChanged<String> onChanged;
  final List<(String value, String label, String hint)> options;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(legend, style: text.titleSmall),
          RadioGroup<String>(
            groupValue: value,
            onChanged: (v) => onChanged(v ?? value),
            child: Column(
              children: [
                for (final (v, label, hint) in options)
                  RadioListTile<String>(
                    value: v,
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: Text(
                      hint,
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
