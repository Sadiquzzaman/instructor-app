import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/links/open_link.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';

/// `GET /organizations/:id`.
typedef OrganizationDetail = ({
  String name,
  int? number,
  String status,
  int? teachers,
  int? students,
  int? classes,
  int? exams,
});

/// `GET /organizations/:id/settings`.
typedef OrganizationSettings = ({
  bool classTeacher,
  bool branches,
  bool guardians,
  String language,
  String smsLanguage,
});

int? _int(Object? v) => (v as num?)?.toInt();

OrganizationSettings settingsFromJson(Object? json) {
  final j = json is Map ? json : const <String, Object?>{};
  return (
    classTeacher: j['class_teacher_enabled'] == true,
    branches: j['branches_enabled'] == true,
    guardians: j['guardians_enabled'] == true,
    language: (j['default_locale'] as String?) ?? 'bn',
    smsLanguage: (j['sms_locale'] as String?) ?? 'bn',
  );
}

/// Owners and admins manage; assistants see the numbers (the web's gate).
bool managesOrganization(String? memberRole) =>
    memberRole == 'OWNER' || memberRole == 'ADMIN';

bool _seesOverview(String? memberRole) =>
    managesOrganization(memberRole) || memberRole == 'ASSISTANT';

final organizationDetailProvider =
    FutureProvider.autoDispose<OrganizationDetail>((ref) async {
      ref.watch(workspaceKeyProvider);
      final id = ref.watch(sessionProvider)?.organizationId;
      final p = (await ref.read(apiClientProvider).get('/organizations/$id'))
          .payload;
      final j = p is Map ? p : const <String, Object?>{};
      return (
        name: (j['name'] as String?) ?? '',
        number: _int(j['organization_number']),
        status: (j['status'] as String?) ?? 'approved',
        teachers: _int(j['teachers_count']),
        students: _int(j['students_count']),
        classes: _int(j['classes_count']),
        exams: _int(j['exams_count']),
      );
    }, retry: (retryCount, error) => null);

final organizationSettingsProvider =
    FutureProvider.autoDispose<OrganizationSettings>((ref) async {
      ref.watch(workspaceKeyProvider);
      final id = ref.watch(sessionProvider)?.organizationId;
      return settingsFromJson(
        (await ref.read(apiClientProvider).get('/organizations/$id/settings'))
            .payload,
      );
    }, retry: (retryCount, error) => null);

/// Whether the academic setup is finished (`GET /setup`).
final setupDoneProvider =
    FutureProvider.autoDispose<({bool done, bool started})>((ref) async {
      ref.watch(workspaceKeyProvider);
      final p = (await ref.read(apiClientProvider).get('/setup')).payload;
      final j = p is Map ? p : const <String, Object?>{};
      return (
        done: j['setup_completed_at'] != null,
        started: j['classes'] is List && (j['classes'] as List).isNotEmpty,
      );
    }, retry: (retryCount, error) => null);

String _statusText(AppLocalizations l10n, String status) => switch (status) {
  'pending' => l10n.organizationStatusesPending,
  'rejected' => l10n.organizationStatusesRejected,
  'inactive' => l10n.organizationStatusesInactive,
  _ => l10n.organizationStatusesApproved,
};

StatusTone _statusTone(String status) => switch (status) {
  'pending' => StatusTone.warning,
  'rejected' => StatusTone.danger,
  'inactive' => StatusTone.neutral,
  _ => StatusTone.success,
};

String roleText(AppLocalizations l10n, String? role) => switch (role) {
  'OWNER' => l10n.organizationRolesOWNER,
  'ADMIN' => l10n.organizationRolesADMIN,
  'ASSISTANT' => l10n.organizationRolesASSISTANT,
  'BRANCH_MANAGER' => l10n.organizationRolesBRANCHMANAGER,
  'STUDENT' => l10n.organizationRolesSTUDENT,
  'TEACHER' => l10n.organizationRolesTEACHER,
  _ => '—',
};

/// The web's /organization: headline counts, the organisation's number,
/// status and the viewer's role; for owners and admins, the academic setup
/// banner (the wizard is on the web until Stage 4) and the organisation
/// settings.
class OrganizationOverviewScreen extends ConsumerWidget {
  const OrganizationOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    final role = session?.memberRole;
    if (session?.organizationId == null) {
      return EmptyView(
        icon: Icons.apartment_outlined,
        title: l10n.organizationGateNoWorkspaceTitle,
        message: l10n.organizationGateNoWorkspace,
      );
    }
    if (!_seesOverview(role)) {
      return EmptyView(
        icon: Icons.lock_outline,
        title: l10n.organizationGateNoAccessTitle,
        message: l10n.organizationGateNoAccess,
      );
    }
    final detail = ref.watch(organizationDetailProvider);
    final d = detail.value;
    final manages = managesOrganization(role);
    final status = d?.status ?? 'approved';
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(organizationDetailProvider)
          ..invalidate(organizationSettingsProvider)
          ..invalidate(setupDoneProvider);
        await ref
            .read(organizationDetailProvider.future)
            .then<void>((_) {}, onError: (Object _) {});
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              Text(l10n.organizationOverviewTitle, style: text.headlineSmall),
              Text(
                d?.name ?? session?.organizationName ?? '',
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              if (detail.hasError && d == null)
                SizedBox(
                  height: 280,
                  child: ErrorView(
                    title: l10n.organizationOverviewLoadFailed,
                    retryLabel: l10n.uiErrorRetry,
                    onRetry: () => ref.invalidate(organizationDetailProvider),
                  ),
                )
              else ...[
                if (status == 'pending')
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: AppCard(
                      key: const Key('org-pending'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.organizationGatePendingTitle,
                            style: text.titleSmall,
                          ),
                          Text(
                            l10n.organizationGatePending,
                            style: text.bodySmall?.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (manages) const _SetupBanner(),
                _Tiles(detail: d, loading: detail.isLoading),
                const SizedBox(height: AppSpacing.md),
                AppCard(
                  key: const Key('org-details'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.organizationOverviewDetails,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xl,
                        runSpacing: AppSpacing.md,
                        children: [
                          _Fact(
                            label: l10n.organizationOverviewNumber,
                            child: Text(
                              d?.number?.toString() ?? '—',
                              style: text.titleSmall?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          ),
                          _Fact(
                            label: l10n.organizationOverviewStatus,
                            child: StatusPill(
                              label: _statusText(l10n, status),
                              tone: _statusTone(status),
                            ),
                          ),
                          _Fact(
                            label: l10n.organizationOverviewYourRole,
                            child: StatusPill(
                              label: roleText(l10n, role),
                              tone: StatusTone.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (manages) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _SettingsCard(),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: text.bodySmall?.copyWith(
            color: AppColors.of(context).inkMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        child,
      ],
    );
  }
}

class _Tiles extends ConsumerWidget {
  const _Tiles({required this.detail, required this.loading});

  final OrganizationDetail? detail;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final d = detail;
    final tiles = [
      ('teachers', l10n.organizationOverviewTeachers, d?.teachers),
      ('students', l10n.organizationOverviewStudents, d?.students),
      (
        'classes',
        ref.levels(context, l10n.organizationOverviewClasses),
        d?.classes,
      ),
      ('exams', l10n.organizationOverviewExams, d?.exams),
    ];
    String number(int? n) => n == null ? '—' : OrgTime.number(n, language);

    return LayoutBuilder(
      builder: (context, box) {
        final columns = box.maxWidth >= 720 ? 4 : 2;
        final width = (box.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final (key, label, value) in tiles)
              SizedBox(
                key: Key('tile-$key'),
                width: width,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: text.bodySmall?.copyWith(color: colors.inkMuted),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      loading && d == null
                          ? const LinearProgressIndicator()
                          : Text(number(value), style: text.headlineSmall),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Until the academic setup is finished, a banner leads to the wizard
/// (on the website until Stage 4).
class _SetupBanner extends ConsumerWidget {
  const _SetupBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final setup = ref.watch(setupDoneProvider).value;
    if (setup == null || setup.done) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        key: const Key('setup-banner'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.academicsSetupBannerTitle, style: text.titleSmall),
            Text(
              ref.levels(context, l10n.academicsSetupBannerDetail),
              style: text.bodySmall?.copyWith(color: colors.inkMuted),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const Key('setup-open'),
              icon: const Icon(Icons.open_in_new),
              label: Text(l10n.appOpenOnWebsite),
              onPressed: () => ref.read(openLinkProvider)(
                Uri.parse('${AppConfig.webBaseUrl}/organization/setup'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Organisation settings (owners and admins): class teachers, branches,
/// guardians, the language for members who haven't chosen one, and the
/// guardian SMS language. Each change saves at once, as on the web.
class _SettingsCard extends ConsumerStatefulWidget {
  const _SettingsCard();

  @override
  ConsumerState<_SettingsCard> createState() => _SettingsCardState();
}

class _SettingsCardState extends ConsumerState<_SettingsCard> {
  OrganizationSettings? _saved;
  bool _saving = false;

  Future<void> _update(Map<String, Object?> change) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final id = ref.read(sessionProvider)?.organizationId;
    setState(() => _saving = true);
    try {
      final r = await ref
          .read(apiClientProvider)
          .patch('/organizations/$id/settings', data: change);
      if (!mounted) return;
      setState(() => _saved = settingsFromJson(r.payload));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.academicsSettingsSaved)),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorText(l10n, e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final loaded = ref.watch(organizationSettingsProvider);
    final s = _saved ?? loaded.value;
    final languages = {
      'bn': l10n.academicsSettingsLanguagesBn,
      'en': l10n.academicsSettingsLanguagesEn,
    };
    return AppCard(
      key: const Key('org-settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.academicsSettingsTitle, style: text.titleMedium),
          if (s == null)
            loaded.hasError
                ? Text(apiErrorText(l10n, loaded.error!))
                : const LinearProgressIndicator()
          else ...[
            SwitchListTile(
              key: const Key('setting-class-teacher'),
              contentPadding: EdgeInsets.zero,
              title: Text(
                ref.levels(context, l10n.academicsSettingsClassTeacher),
              ),
              subtitle: Text(
                ref.levels(context, l10n.academicsSettingsClassTeacherHint),
              ),
              value: s.classTeacher,
              onChanged: _saving
                  ? null
                  : (v) => _update({'class_teacher_enabled': v}),
            ),
            SwitchListTile(
              key: const Key('setting-branches'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.academicsSettingsBranches),
              subtitle: Text(l10n.academicsSettingsBranchesHint),
              value: s.branches,
              onChanged: _saving
                  ? null
                  : (v) => _update({'branches_enabled': v}),
            ),
            SwitchListTile(
              key: const Key('setting-guardians'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.academicsSettingsGuardians),
              subtitle: Text(l10n.academicsSettingsGuardiansHint),
              value: s.guardians,
              onChanged: _saving
                  ? null
                  : (v) => _update({'guardians_enabled': v}),
            ),
            const SizedBox(height: AppSpacing.sm),
            DropdownButtonFormField<String>(
              key: const Key('setting-language'),
              initialValue: s.language,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.academicsSettingsLanguage,
                helperText: l10n.academicsSettingsLanguageHint,
                helperMaxLines: 3,
              ),
              items: [
                for (final MapEntry(:key, :value) in languages.entries)
                  DropdownMenuItem(value: key, child: Text(value)),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v != null && v != s.language) {
                        _update({'default_locale': v});
                      }
                    },
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              key: const Key('setting-sms-language'),
              initialValue: s.smsLanguage,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.academicsSettingsSmsLanguage,
                helperText: l10n.academicsSettingsSmsLanguageHint,
                helperMaxLines: 3,
              ),
              items: [
                for (final MapEntry(:key, :value) in languages.entries)
                  DropdownMenuItem(value: key, child: Text(value)),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v != null && v != s.smsLanguage) {
                        _update({'sms_locale': v});
                      }
                    },
            ),
          ],
        ],
      ),
    );
  }
}
