import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/language_switcher.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/features/shell/menu/menu_panel.dart';
import 'package:instructor_app/features/workspace/data/workspace_repository.dart';
import 'package:instructor_app/features/workspace/screens/workspace_gate.dart';

/// The frame around every signed-in screen (the web's AppShell): a top bar
/// with the workspace switcher and the language switch, and the side menu,
/// in a drawer on phones and always open on wide screens (tablets in
/// landscape, from [wideBreakpoint]).
class AppShell extends ConsumerWidget {
  const AppShell({required this.currentRoute, required this.child, super.key});

  final String currentRoute;
  final Widget child;

  static const wideBreakpoint = 840.0;
  static const menuWidth = 300.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppColors.of(context);
    final wide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final appBar = AppBar(
      automaticallyImplyLeading: !wide,
      titleSpacing: wide ? AppSpacing.lg : 0,
      title: const WorkspaceSwitcher(),
      actions: const [
        LanguageSwitcher(),
        SizedBox(width: AppSpacing.sm),
      ],
    );
    if (!wide) {
      return Scaffold(
        appBar: appBar,
        drawer: Drawer(
          backgroundColor: colors.surface,
          child: SafeArea(
            child: Builder(
              builder: (drawerContext) => MenuPanel(
                currentRoute: currentRoute,
                onNavigate: () => Navigator.of(drawerContext).pop(),
              ),
            ),
          ),
        ),
        body: child,
      );
    }
    return Row(
      children: [
        SizedBox(
          width: menuWidth,
          child: Material(
            color: colors.surface,
            child: SafeArea(child: MenuPanel(currentRoute: currentRoute)),
          ),
        ),
        VerticalDivider(width: 1, color: colors.border),
        Expanded(
          child: Scaffold(appBar: appBar, body: child),
        ),
      ],
    );
  }
}

/// The current workspace's name; opens the list when there is more than one.
class WorkspaceSwitcher extends ConsumerWidget {
  const WorkspaceSwitcher({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(sessionProvider);
    if (session == null) return const SizedBox.shrink();
    final contexts = ref.watch(workspaceContextsProvider).value ?? const [];
    final canSwitch = contexts.where((c) => c.actionable).length > 1;
    var label = switch (session.contextType) {
      'organization' => session.organizationName ?? l10n.shellOrganization,
      'personal_teacher' => l10n.shellWorkspaceMyTeaching,
      _ => l10n.shellWorkspaceFallback,
    };
    for (final c in contexts) {
      if (c.isCurrent(session) && c.label.isNotEmpty) label = c.label;
    }
    final text = Text(
      label,
      key: const Key('workspace-switcher'),
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.titleMedium,
    );
    if (!canSwitch) return text;
    return Semantics(
      button: true,
      child: InkWell(
        borderRadius: AppRadius.inputAll,
        onTap: () => showWorkspaceSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }
}
