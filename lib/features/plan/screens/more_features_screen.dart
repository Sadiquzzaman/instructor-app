import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_button.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/plan/data/feature_catalog.dart';
import 'package:instructor_app/features/plan/data/feature_names.g.dart';
import 'package:instructor_app/features/shell/data/entitlements.dart';
import 'package:instructor_app/features/shell/widgets/api_error_handling.dart';

/// The web's /features ("More features", FND-08): every plan feature with a
/// short description, what this workspace has, and "Request this feature" for
/// the locked ones. Only the workspace's owner or an admin (a solo teacher in
/// their own) sees it; everyone else is told who to ask. Unlike the web there
/// is no upgrade button (CLAUDE.md "Payments").
class MoreFeaturesScreen extends ConsumerStatefulWidget {
  const MoreFeaturesScreen({super.key});

  @override
  ConsumerState<MoreFeaturesScreen> createState() => _MoreFeaturesScreenState();
}

class _MoreFeaturesScreenState extends ConsumerState<MoreFeaturesScreen> {
  /// Asked for on this visit (the web keeps it the same way).
  final _requested = <String>{};

  String _name(CatalogFeature f) => featureName(context.l10n, f.key) ?? f.label;

  Future<void> _request(CatalogFeature feature) async {
    final name = _name(feature);
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => _RequestDialog(feature: feature, name: name),
    );
    if (sent != true || !mounted) return;
    setState(() => _requested.add(feature.key));
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${l10n.featuresPageSentTitle}. ${l10n.featuresPageSent(name)}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!canManagePlan(ref.watch(sessionProvider))) {
      return EmptyView(
        icon: Icons.lock_outline,
        title: l10n.featuresPageMembersTitle,
        message: l10n.featuresPageMembersDetail,
      );
    }
    final catalog = ref.watch(featureCatalogProvider);
    final entitlements = ref.watch(entitlementsProvider);
    void retry() {
      ref.invalidate(featureCatalogProvider);
      ref.invalidate(entitlementsProvider);
    }

    // The entitlements provider answers null when its call failed.
    if (catalog.hasError ||
        (entitlements.hasValue && entitlements.value == null)) {
      return ErrorView(
        title: l10n.featuresPageLoadFailed,
        retryLabel: l10n.uiErrorRetry,
        onRetry: retry,
      );
    }
    final features = catalog.value;
    final plan = entitlements.value;
    if (features == null || plan == null) {
      return LoadingView(semanticsLabel: l10n.featuresPageTitle);
    }

    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        retry();
        await ref.read(featureCatalogProvider.future);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.featuresPagePlanTitle(
                        plan.planName ?? l10n.featuresPageFree,
                      ),
                      style: text.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.featuresPageIntro,
                      style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              for (final (group, items) in groupFeatures(features)) ...[
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  key: Key('feature-group-$group'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        featureGroupName(l10n, group) ?? group,
                        style: text.titleMedium,
                      ),
                      for (final (i, f) in items.indexed) ...[
                        if (i > 0) const Divider(height: AppSpacing.lg),
                        if (i == 0) const SizedBox(height: AppSpacing.md),
                        _FeatureRow(
                          key: Key('feature-${f.key}'),
                          name: _name(f),
                          description:
                              featureDescription(l10n, f.key) ?? f.description,
                          included: plan.has(f.key),
                          requested: _requested.contains(f.key),
                          onRequest: () => _request(f),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.name,
    required this.description,
    required this.included,
    required this.requested,
    required this.onRequest,
    super.key,
  });

  final String name;
  final String? description;
  final bool included;
  final bool requested;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final status = included
        ? StatusPill(label: l10n.featuresPageIncluded, tone: StatusTone.success)
        : requested
        ? StatusPill(label: l10n.featuresPageRequested, tone: StatusTone.info)
        : StatusPill(label: l10n.featuresPageLocked);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                name,
                style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            status,
          ],
        ),
        if (description != null) ...[
          const SizedBox(height: AppSpacing.xs / 2),
          Text(
            description!,
            style: text.bodyMedium?.copyWith(color: colors.inkMuted),
          ),
        ],
        if (!included && !requested) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Semantics(
              label: l10n.featuresPageRequestFor(name),
              excludeSemantics: true,
              button: true,
              child: AppButton(
                label: l10n.featuresPageRequest,
                variant: AppButtonVariant.secondary,
                onPressed: onRequest,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// "Request {name}" with an optional note. Pops true once the request is sent.
class _RequestDialog extends ConsumerStatefulWidget {
  const _RequestDialog({required this.feature, required this.name});

  final CatalogFeature feature;
  final String name;

  @override
  ConsumerState<_RequestDialog> createState() => _RequestDialogState();
}

class _RequestDialogState extends ConsumerState<_RequestDialog> {
  final _note = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(featureCatalogRepositoryProvider)
          .request(widget.feature.key, note: _note.text);
      if (mounted) Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (mounted) setState(() => _error = apiErrorText(context.l10n, e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.featuresPageRequestTitle(widget.name)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.featuresPageRequestDetail, style: text.bodyMedium),
            const SizedBox(height: AppSpacing.lg),
            AppTextField(
              key: const Key('feature-request-note'),
              label: l10n.featuresPageNote,
              hint: l10n.featuresPageNoteHint,
              controller: _note,
              maxLines: 4,
              maxLength: 1000,
              enabled: !_sending,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _error!,
                style: text.bodyMedium?.copyWith(
                  color: AppColors.of(context).danger,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.featuresPageCancel),
        ),
        AppButton(
          label: l10n.featuresPageSend,
          onPressed: _send,
          loading: _sending,
        ),
      ],
    );
  }
}
