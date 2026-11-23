import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_error_text.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/widgets/app_card.dart';
import 'package:instructor_app/core/widgets/app_text_field.dart';
import 'package:instructor_app/core/widgets/state_views.dart';
import 'package:instructor_app/features/join/data/join_links.dart';

/// The web's messages break lines with `<br></br>`; the app uses new lines.
String _lines(String s) => s.replaceAll('<br></br>', '\n');

/// A page with a title, some lines and actions, centred like the web's
/// invite pages.
class _JoinPage extends StatelessWidget {
  const _JoinPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    ),
  );
}

/// `/join/class/:id`: the class a teacher invited you to; students join it.
class JoinClassScreen extends ConsumerStatefulWidget {
  const JoinClassScreen({required this.id, super.key});

  final String id;

  @override
  ConsumerState<JoinClassScreen> createState() => _JoinClassScreenState();
}

class _JoinClassScreenState extends ConsumerState<JoinClassScreen> {
  bool _busy = false;

  /// null until joined; then whether the teacher still has to approve.
  bool? _pending;
  Object? _failed;

  Future<void> _join() async {
    setState(() {
      _busy = true;
      _failed = null;
    });
    try {
      final pending = await ref
          .read(joinRepositoryProvider)
          .joinClass(widget.id);
      if (mounted) setState(() => _pending = pending);
    } on Object catch (e) {
      if (mounted) setState(() => _failed = e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final session = ref.watch(sessionProvider);
    final student = session?.role == 'STUDENT';
    return ref
        .watch(joinClassSummaryProvider(widget.id))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.joinLoadingTitle),
          error: (e, _) => EmptyView(
            icon: Icons.link_off,
            title: l10n.classesJoinUnavailable,
            message: apiErrorText(l10n, e),
          ),
          data: (c) {
            final teacher = c.teacher ?? '';
            final name = session?.fullName ?? '';
            if (_pending != null) {
              return _JoinPage(
                children: [
                  Text(
                    _pending!
                        ? l10n.joinPendingTitle(name)
                        : l10n.joinWelcomeTitle(name),
                    key: const Key('join-result'),
                    style: text.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _lines(
                      _pending!
                          ? l10n.joinPendingDescription(c.name, teacher)
                          : l10n.joinJoinedDescription(c.name, teacher),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    key: const Key('join-done'),
                    onPressed: () => context.go(AppRoutes.classes),
                    child: Text(l10n.joinContinue),
                  ),
                ],
              );
            }
            return _JoinPage(
              children: [
                Text(
                  l10n.classesJoinTitle(c.name, teacher),
                  style: text.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  (c.description?.trim().isNotEmpty ?? false)
                      ? c.description!
                      : l10n.classesJoinNoDescription,
                  style: text.bodyMedium?.copyWith(color: colors.inkMuted),
                ),
                const SizedBox(height: AppSpacing.md),
                if (_failed != null) ...[
                  Text(
                    l10n.joinClassJoinFailedTitle,
                    style: text.titleSmall?.copyWith(color: colors.danger),
                  ),
                  Text(
                    apiErrorText(l10n, _failed!),
                    key: const Key('join-failed'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                if (student)
                  FilledButton(
                    key: const Key('join-class'),
                    onPressed: _busy ? null : _join,
                    child: Text(l10n.joinContinue),
                  )
                else
                  Text(l10n.appJoinStudentsOnly),
              ],
            );
          },
        );
  }
}

/// `/join/test/:id`: a test a teacher shared; students open it.
class JoinTestScreen extends ConsumerWidget {
  const JoinTestScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    final student = ref.watch(sessionProvider)?.role == 'STUDENT';
    return ref
        .watch(joinTestSummaryProvider(id))
        .when(
          loading: () => LoadingView(semanticsLabel: l10n.joinLoadingTitle),
          error: (e, _) => EmptyView(
            icon: Icons.link_off,
            title: l10n.testsJoinUnavailable,
            message: apiErrorText(l10n, e),
          ),
          data: (t) => _JoinPage(
            children: [
              Text(
                l10n.testsJoinTitle(t.name, t.teacher ?? ''),
                style: text.titleLarge,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (t.minutes != null) Text(l10n.testsJoinDuration(t.minutes!)),
              Text(
                t.private ? l10n.testsJoinPrivate : l10n.testsJoinPublic,
                style: text.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              const SizedBox(height: AppSpacing.md),
              if (student)
                FilledButton(
                  key: const Key('join-test'),
                  onPressed: () => context.go('${AppRoutes.tests}/$id/take'),
                  child: Text(l10n.joinStartTest),
                )
              else
                Text(l10n.appJoinStudentsOnly),
            ],
          ),
        );
  }
}

/// "Join with a link": paste a link a teacher shared and open its page.
Future<void> showJoinWithLink(BuildContext context) async {
  final link = await showDialog<JoinLink>(
    context: context,
    builder: (_) => const _JoinWithLinkDialog(),
  );
  if (link != null && context.mounted) {
    await GoRouter.of(context).push(joinRoute(link));
  }
}

class _JoinWithLinkDialog extends StatefulWidget {
  const _JoinWithLinkDialog();

  @override
  State<_JoinWithLinkDialog> createState() => _JoinWithLinkDialogState();
}

class _JoinWithLinkDialogState extends State<_JoinWithLinkDialog> {
  final _field = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _open() {
    final link = parseJoinLink(_field.text);
    if (link == null) {
      setState(() => _error = context.l10n.appJoinLinkInvalid);
      return;
    }
    Navigator.of(context).pop(link);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.appJoinWithLink),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.appJoinWithLinkHint),
          const SizedBox(height: AppSpacing.sm),
          AppTextField(
            key: const Key('join-link-field'),
            label: l10n.appJoinLinkField,
            controller: _field,
            errorText: _error,
            keyboardType: TextInputType.url,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.uiCancel),
        ),
        FilledButton(
          key: const Key('join-link-open'),
          onPressed: _open,
          child: Text(l10n.appJoinOpen),
        ),
      ],
    );
  }
}
