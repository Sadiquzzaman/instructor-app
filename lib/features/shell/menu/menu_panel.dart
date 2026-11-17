import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/l10n/level_text.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/features/auth/data/auth_repository.dart';
import 'package:instructor_app/features/shell/data/entitlements.dart';
import 'package:instructor_app/features/shell/menu/menu_filter.dart';
import 'package:instructor_app/features/shell/menu/menu_icons.dart';
import 'package:instructor_app/features/shell/menu/menu_item.dart';
import 'package:instructor_app/features/shell/menu/menu_items.g.dart';

/// The menu the signed-in person may see, from the session and the plan.
final visibleMenuProvider = Provider<List<MenuSection>>((ref) {
  final session = ref.watch(sessionProvider);
  if (session == null) return const [];
  final plan = ref.watch(entitlementsProvider);
  return visibleMenu(
    webMenu,
    MenuViewer.of(session),
    order: navItemOrder,
    features: plan.value?.features,
    featuresLoading: plan.isLoading,
  );
});

/// The side menu (the web's Sidebar): sections with headings, groups that
/// open when they hold the current page, a "Setup" heading before settings,
/// and Sign out at the bottom. Used in the phone drawer and the tablet panel.
class MenuPanel extends ConsumerWidget {
  const MenuPanel({required this.currentRoute, this.onNavigate, super.key});

  final String currentRoute;

  /// Called after a link was followed (closes the phone drawer).
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final sections = ref.watch(visibleMenuProvider);

    void open(MenuItem item) {
      onNavigate?.call();
      if (item.route != currentRoute) context.go(item.route);
    }

    Widget link(MenuItem item, {bool indent = false}) => ListTile(
      key: Key('menu-${item.route}'),
      contentPadding: EdgeInsetsDirectional.only(
        start: indent ? AppSpacing.xxl : AppSpacing.lg,
        end: AppSpacing.lg,
      ),
      leading: indent ? null : Icon(menuIcon(item.icon)),
      title: Text(ref.levels(context, menuLabel(l10n, item.label))),
      selected: item.route == currentRoute,
      selectedColor: colors.primary,
      selectedTileColor: colors.primarySoft,
      onTap: () => open(item),
    );

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            children: [
              for (final section in sections) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Text(
                    menuCategoryLabel(l10n, section.category).toUpperCase(),
                    style: text.labelMedium?.copyWith(color: colors.inkMuted),
                  ),
                ),
                for (final entry in section.entries)
                  if (entry.item != null)
                    link(entry.item!)
                  else
                    Theme(
                      // No divider lines around an open group.
                      data: Theme.of(context)
                          .copyWith(dividerColor: colors.surface.withAlpha(0)),
                      child: ExpansionTile(
                        key: PageStorageKey('menu-group-${entry.group}'),
                        leading: Icon(menuGroupIcon(entry.group!)),
                        title: Text(menuGroupLabel(l10n, entry.group!)),
                        initiallyExpanded: entry.items.any(
                          (i) => i.route == currentRoute,
                        ),
                        children: [
                          for (final (index, item) in entry.items.indexed) ...[
                            if (item.setup &&
                                index > 0 &&
                                entry.items.indexWhere((i) => i.setup) == index)
                              Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  AppSpacing.xxl,
                                  AppSpacing.sm,
                                  AppSpacing.lg,
                                  AppSpacing.xs,
                                ),
                                child: Text(
                                  l10n.navGroupSetup,
                                  style: text.labelMedium?.copyWith(
                                    color: colors.inkMuted,
                                  ),
                                ),
                              ),
                            link(item, indent: true),
                          ],
                        ],
                      ),
                    ),
              ],
            ],
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: Text(l10n.shellSignOut),
          onTap: () {
            onNavigate?.call();
            signOut(ref);
          },
        ),
      ],
    );
  }
}
