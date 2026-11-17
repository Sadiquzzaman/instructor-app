import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/links/open_link.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/features/version/data/version_check.dart';

/// Wraps the app (PM-03): a required update replaces everything with
/// [UpdateRequiredScreen]; an optional one shows a banner above [child]. The
/// app starts at once and the check runs alongside; it runs again when the app
/// comes back after an hour or more.
class VersionGate extends ConsumerStatefulWidget {
  const VersionGate({required this.child, super.key});

  final Widget child;

  static const recheckAfter = Duration(hours: 1);

  @override
  ConsumerState<VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends ConsumerState<VersionGate> {
  late final AppLifecycleListener _lifecycle;
  DateTime _lastCheck = DateTime.now();

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  void _onResume() {
    if (DateTime.now().difference(_lastCheck) < VersionGate.recheckAfter) {
      return;
    }
    _lastCheck = DateTime.now();
    ref.read(versionStatusProvider.notifier).recheck();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status =
        ref.watch(versionStatusProvider).value ?? VersionStatus.unknown;
    final dismissed = ref.watch(optionalUpdateDismissedProvider);
    switch (status.need) {
      case UpdateNeed.required:
        return UpdateRequiredScreen(status: status);
      case UpdateNeed.optional when !dismissed:
        return Column(
          children: [
            _UpdateBanner(status: status),
            Expanded(child: widget.child),
          ],
        );
      case _:
        return widget.child;
    }
  }
}

/// Full screen: this version may not be used any more.
class UpdateRequiredScreen extends ConsumerWidget {
  const UpdateRequiredScreen({required this.status, super.key});

  final VersionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final url = status.updateUrl;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update_outlined,
                    size: AppSpacing.xxxl,
                    color: colors.primary,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    l10n.appUpdateRequiredTitle,
                    style: text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l10n.appUpdateRequiredBody,
                    style: text.bodyLarge?.copyWith(color: colors.inkMuted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (url != null)
                    AppButton(
                      label: l10n.appUpdateNow,
                      icon: Icons.open_in_new,
                      expand: true,
                      onPressed: () => ref.read(openLinkProvider)(url),
                    )
                  else
                    Text(
                      l10n.appUpdateNoLink,
                      style: text.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateBanner extends ConsumerWidget {
  const _UpdateBanner({required this.status});

  final VersionStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final url = status.updateUrl;
    return Material(
      color: colors.infoSoft,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(Icons.system_update_outlined, color: colors.info),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  l10n.appUpdateAvailable,
                  style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: colors.ink),
                ),
              ),
              if (url != null)
                AppButton(
                  label: l10n.appUpdateNow,
                  variant: AppButtonVariant.text,
                  onPressed: () => ref.read(openLinkProvider)(url),
                ),
              AppButton(
                label: l10n.appUpdateLater,
                variant: AppButtonVariant.text,
                onPressed: () => ref
                    .read(optionalUpdateDismissedProvider.notifier)
                    .dismiss(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
