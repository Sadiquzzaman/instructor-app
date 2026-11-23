import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/account/data/account_repository.dart';
import 'package:instructor_app/features/account/data/change_password_validation.dart';
import 'package:instructor_app/features/organization/data/log_names.g.dart';

/// The web's /account: the profile (read only, as on the web), change
/// password, and the signed-in devices. The language switch is in the top
/// bar and saves to the account.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            _ProfileCard(),
            SizedBox(height: AppSpacing.lg),
            _TeacherRequestCard(),
            _ChangePasswordCard(),
            SizedBox(height: AppSpacing.lg),
            _NotificationsCard(),
            SizedBox(height: AppSpacing.lg),
            _DevicesCard(),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.intro});

  final String title;
  final String? intro;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.titleLarge),
          if (intro != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              intro!,
              style: text.bodyMedium?.copyWith(
                color: AppColors.of(context).inkMuted,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    return _Section(
      title: l10n.accountTitle,
      child: ref
          .watch(profileProvider)
          .when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(
              title: l10n.accountLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(profileProvider),
            ),
            data: (p) {
              final created = p.createdAt;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // What the API holds about the person: not translated.
                  _Row(l10n.accountFullName, Text(p.fullName)),
                  _Row(l10n.accountRole, Text(_role(l10n, p.role))),
                  _Row(
                    l10n.accountEmail,
                    Text(p.email ?? l10n.accountNotProvided),
                  ),
                  _Row(
                    l10n.accountPhone,
                    Text(p.phone ?? l10n.accountNotProvided),
                  ),
                  _Row(
                    l10n.accountStatus,
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: StatusPill(
                        label: p.verified
                            ? l10n.accountVerified
                            : l10n.accountUnverified,
                        tone: p.verified
                            ? StatusTone.success
                            : StatusTone.warning,
                      ),
                    ),
                  ),
                  _Row(
                    l10n.accountMemberSince,
                    Text(
                      created == null ? '—' : OrgTime.date(created, language),
                    ),
                  ),
                ],
              );
            },
          ),
    );
  }

  static String _role(AppLocalizations l10n, String role) => switch (role) {
    'STUDENT' => l10n.accountRolesSTUDENT,
    'TEACHER' => l10n.accountRolesTEACHER,
    _ => role,
  };
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: text.bodyMedium?.copyWith(
                color: AppColors.of(context).inkMuted,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: DefaultTextStyle.merge(style: text.bodyLarge, child: value),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordCard extends ConsumerStatefulWidget {
  const _ChangePasswordCard();

  @override
  ConsumerState<_ChangePasswordCard> createState() =>
      _ChangePasswordCardState();
}

class _ChangePasswordCardState extends ConsumerState<_ChangePasswordCard> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  Map<String, String> _errors = const {};
  String? _formError;
  bool _loading = false;

  @override
  void dispose() {
    for (final c in [_current, _next, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final l10n = context.l10n;
    final errors = validateChangePassword(
      current: _current.text,
      next: _next.text,
      confirm: _confirm.text,
      l10n: l10n,
    );
    setState(() {
      _errors = errors;
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _loading = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .changePassword(
            current: _current.text,
            next: _next.text,
            confirm: _confirm.text,
          );
      if (!mounted) return;
      for (final c in [_current, _next, _confirm]) {
        c.clear();
      }
      // The other devices were signed out: show the list as it is now.
      ref.invalidate(devicesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.authChangePasswordDoneDescription)),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(
        () => _formError =
            e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout
            ? l10n.appNoConnection
            : l10n.appChangePasswordFailed,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    AppTextField field(
      String key,
      String label,
      String hint,
      TextEditingController c, {
      List<String> autofill = const [AutofillHints.newPassword],
    }) => AppTextField(
      key: Key('password-$key'),
      label: label,
      hint: hint,
      controller: c,
      errorText: _errors[key],
      obscure: true,
      showLabel: l10n.authShowPassword,
      hideLabel: l10n.authHidePassword,
      autofillHints: autofill,
    );
    return _Section(
      title: l10n.accountChangePasswordTitle,
      intro: l10n.accountChangePasswordIntro,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_formError != null) ...[
              Text(
                _formError!,
                style: TextStyle(color: AppColors.of(context).danger),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            field(
              'current',
              l10n.accountChangePasswordCurrent,
              l10n.accountChangePasswordCurrentPlaceholder,
              _current,
              autofill: const [AutofillHints.password],
            ),
            const SizedBox(height: AppSpacing.sm),
            field(
              'new',
              l10n.accountChangePasswordNew,
              l10n.accountChangePasswordNewPlaceholder,
              _next,
            ),
            const SizedBox(height: AppSpacing.sm),
            field(
              'confirm',
              l10n.accountChangePasswordConfirm,
              l10n.accountChangePasswordConfirmPlaceholder,
              _confirm,
            ),
            const SizedBox(height: AppSpacing.lg),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: AppButton(
                label: l10n.accountChangePasswordSubmit,
                onPressed: _submit,
                loading: _loading,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The web's "Notifications" card (FND-12): SMS or email for each kind of
/// message; the bell in the app always gets them.
class _NotificationsCard extends ConsumerStatefulWidget {
  const _NotificationsCard();

  @override
  ConsumerState<_NotificationsCard> createState() => _NotificationsCardState();
}

class _NotificationsCardState extends ConsumerState<_NotificationsCard> {
  /// Saved answers, shown until the list is read again.
  List<NotificationPref>? _saved;
  bool _saving = false;

  static const _optional = ['SMS', 'EMAIL'];

  Future<void> _toggle(NotificationPref p, String channel, bool on) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final channels = on
        ? [...p.channels, channel]
        : p.channels.where((c) => c != channel).toList();
    setState(() => _saving = true);
    try {
      final all = await ref
          .read(accountRepositoryProvider)
          .saveNotificationPref(p.eventType, channels);
      if (mounted && all.isNotEmpty) setState(() => _saved = all);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.notificationsPrefsSaved)),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return _Section(
      title: l10n.notificationsPrefsTitle,
      intro: l10n.notificationsPrefsIntro,
      child: ref
          .watch(notificationPrefsProvider)
          .when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(
              title: l10n.notificationsPrefsLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(notificationPrefsProvider),
            ),
            data: (loaded) {
              final prefs = _saved ?? loaded;
              final anySms = prefs.any((p) => p.allowed.contains('SMS'));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final p in prefs)
                    Padding(
                      key: Key('pref-${p.eventType}'),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xs,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            messageEventName(l10n, p.eventType) ?? p.eventType,
                            style: text.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            l10n.notificationsPrefsInAppAlways,
                            style: text.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                          Wrap(
                            spacing: AppSpacing.md,
                            children: [
                              for (final c in _optional)
                                if (p.allowed.contains(c))
                                  _ChannelBox(
                                    key: Key('pref-${p.eventType}-$c'),
                                    label: c == 'SMS'
                                        ? l10n.notificationsPrefsChannelsSMS
                                        : l10n.notificationsPrefsChannelsEMAIL,
                                    value: p.channels.contains(c),
                                    onChanged: _saving
                                        ? null
                                        : (on) => _toggle(p, c, on),
                                  ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (anySms)
                    Text(
                      l10n.notificationsPrefsSmsHint,
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                ],
              );
            },
          ),
    );
  }
}

/// A checkbox with its label, the whole row tappable.
class _ChannelBox extends StatelessWidget {
  const _ChannelBox({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        ),
        Text(label),
      ],
    ),
  );
}

/// The web's "Become a teacher" card, for students only.
class _TeacherRequestCard extends ConsumerStatefulWidget {
  const _TeacherRequestCard();

  @override
  ConsumerState<_TeacherRequestCard> createState() =>
      _TeacherRequestCardState();
}

class _TeacherRequestCardState extends ConsumerState<_TeacherRequestCard> {
  bool _sending = false;

  Future<void> _ask() async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(accountRepositoryProvider).askToTeach();
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.accountTeacherRequestDoneDetail)),
      );
      ref.invalidate(teacherRequestProvider);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = ref.watch(profileProvider).value?.role;
    if (role != 'STUDENT') return const SizedBox.shrink();
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final request = ref.watch(teacherRequestProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: _Section(
        title: l10n.accountTeacherRequestTitle,
        intro: l10n.accountTeacherRequestIntro,
        child: request.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => ErrorView(
            title: apiErrorText(l10n, e),
            retryLabel: l10n.uiErrorRetry,
            onRetry: () => ref.invalidate(teacherRequestProvider),
          ),
          data: (r) {
            final canAsk = r == null || r.status == 'rejected';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (r != null)
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        l10n.accountTeacherRequestStatusLabel,
                        style: text.bodySmall?.copyWith(color: colors.inkMuted),
                      ),
                      StatusPill(
                        key: const Key('teacher-request-status'),
                        label: switch (r.status) {
                          'approved' =>
                            l10n.accountTeacherRequestStatusApproved,
                          'rejected' =>
                            l10n.accountTeacherRequestStatusRejected,
                          _ => l10n.accountTeacherRequestStatusPending,
                        },
                        tone: switch (r.status) {
                          'approved' => StatusTone.success,
                          'rejected' => StatusTone.danger,
                          _ => StatusTone.warning,
                        },
                      ),
                      if (r.createdAt != null)
                        Text(
                          l10n.accountTeacherRequestSentOn(
                            OrgTime.date(r.createdAt!, language),
                          ),
                          style: text.bodySmall?.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                    ],
                  ),
                if (r?.status == 'pending')
                  Text(
                    l10n.accountTeacherRequestPendingNote,
                    style: text.bodySmall?.copyWith(color: colors.inkMuted),
                  ),
                if (r?.status == 'approved')
                  Text(
                    l10n.accountTeacherRequestApprovedNote,
                    style: text.bodySmall?.copyWith(color: colors.success),
                  ),
                if (canAsk)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: FilledButton(
                      key: const Key('teacher-request-ask'),
                      onPressed: _sending ? null : _ask,
                      child: Text(
                        r?.status == 'rejected'
                            ? l10n.accountTeacherRequestAgain
                            : l10n.accountTeacherRequestSubmit,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DevicesCard extends ConsumerWidget {
  const _DevicesCard();

  static String _platform(AppLocalizations l10n, String p) => switch (p) {
    'ANDROID' => l10n.accountDevicesPlatformANDROID,
    'IOS' => l10n.accountDevicesPlatformIOS,
    _ => l10n.accountDevicesPlatformWEB,
  };

  Future<bool> _confirm(BuildContext context, String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) {
          final l10n = dialog.l10n;
          return AlertDialog(
            title: Text(title),
            content: Text(l10n.accountDevicesConfirmDetail),
            actions: [
              // Starts on Cancel (design system: ConfirmDialog).
              TextButton(
                autofocus: true,
                onPressed: () => Navigator.of(dialog).pop(false),
                child: Text(l10n.uiCancel),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialog).pop(true),
                child: Text(l10n.accountDevicesSignOut),
              ),
            ],
          );
        },
      ) ??
      false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final language = Localizations.localeOf(context).languageCode;

    Future<void> act(Future<String> Function() action) async {
      final messenger = ScaffoldMessenger.of(context);
      try {
        final done = await action();
        messenger.showSnackBar(SnackBar(content: Text(done)));
      } on Object catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
      } finally {
        ref.invalidate(devicesProvider);
      }
    }

    return _Section(
      title: l10n.accountDevicesTitle,
      intro: l10n.accountDevicesIntro,
      child: ref
          .watch(devicesProvider)
          .when(
            loading: () => const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ErrorView(
              title: l10n.accountDevicesLoadFailed,
              retryLabel: l10n.uiErrorRetry,
              onRetry: () => ref.invalidate(devicesProvider),
            ),
            data: (devices) {
              final others = devices.where((d) => !d.current).toList();
              final repo = ref.read(accountRepositoryProvider);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final d in [
                    ...devices.where((d) => d.current),
                    ...others,
                  ])
                    Padding(
                      key: Key('device-${d.id}'),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            d.platform == 'WEB'
                                ? Icons.laptop
                                : Icons.smartphone,
                            color: colors.inkMuted,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: AppSpacing.sm,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(
                                      d.name ?? _platform(l10n, d.platform),
                                      style: text.titleSmall,
                                    ),
                                    if (d.current)
                                      StatusPill(
                                        label: l10n.accountDevicesThisDevice,
                                        tone: StatusTone.success,
                                      ),
                                  ],
                                ),
                                Text(
                                  [
                                    _platform(l10n, d.platform),
                                    if (d.appVersion != null)
                                      l10n.accountDevicesAppVersion(
                                        d.appVersion!,
                                      ),
                                  ].join(' · '),
                                  style: text.bodySmall?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                                if (d.lastUsedAt != null)
                                  Text(
                                    l10n.accountDevicesLastUsed(
                                      OrgTime.dateTime(d.lastUsedAt!, language),
                                    ),
                                    style: text.bodySmall?.copyWith(
                                      color: colors.inkMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (!d.current)
                            TextButton(
                              onPressed: () async {
                                final name =
                                    d.name ?? _platform(l10n, d.platform);
                                if (!await _confirm(
                                  context,
                                  l10n.accountDevicesOneConfirmTitle(name),
                                )) {
                                  return;
                                }
                                await act(() async {
                                  await repo.signOutDevice(d.id);
                                  return l10n.accountDevicesOneDone;
                                });
                              },
                              child: Text(l10n.accountDevicesSignOut),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  if (others.isEmpty)
                    Text(
                      l10n.accountDevicesOnlyThisOne,
                      style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                    )
                  else
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: AppButton(
                        label: l10n.accountDevicesSignOutOthers,
                        variant: AppButtonVariant.secondary,
                        onPressed: () async {
                          if (!await _confirm(
                            context,
                            l10n.accountDevicesOthersConfirmTitle(
                              others.length,
                            ),
                          )) {
                            return;
                          }
                          await act(() async {
                            final n = await repo.signOutOthers();
                            return l10n.accountDevicesOthersDone(n);
                          });
                        },
                      ),
                    ),
                ],
              );
            },
          ),
    );
  }
}
