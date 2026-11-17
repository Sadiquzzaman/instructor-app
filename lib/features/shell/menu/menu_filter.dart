import 'package:flutter/foundation.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/features/shell/menu/menu_item.dart';

/// Who is looking at the menu, from the session.
@immutable
class MenuViewer {
  const MenuViewer({
    required this.role,
    required this.sessionMode,
    required this.workspaceType,
    this.memberRole,
    this.personalTeacherEnabled = false,
  });

  factory MenuViewer.of(Session s) => MenuViewer(
    role: s.role,
    sessionMode: s.sessionMode,
    workspaceType: s.workspaceType == 'IELTS' ? 'IELTS' : 'ACADEMIC',
    memberRole: s.isOrganization ? s.memberRole : null,
    personalTeacherEnabled: s.personalTeacherEnabled,
  );

  final String role;
  final String sessionMode;
  final String workspaceType;
  final String? memberRole;
  final bool personalTeacherEnabled;

  bool get isPlatformAdmin => role == 'ADMIN' || role == 'SUPER_ADMIN';
}

/// A menu section: a category heading and its entries in the web's order.
@immutable
class MenuSection {
  const MenuSection(this.category, this.entries);
  final String category;
  final List<MenuEntry> entries;
}

/// An entry: one link, or a group of links ([group] set).
@immutable
class MenuEntry {
  const MenuEntry.item(MenuItem this.item) : group = null, items = const [];
  const MenuEntry.group(String this.group, this.items) : item = null;

  final MenuItem? item;
  final String? group;
  final List<MenuItem> items;
}

/// The menu a person sees: the web's rules (component/Dashboard/Sidebar.tsx
/// and SidebarNav.tsx), with the Admin section left out (web only).
///
/// - Section by session: a student in an organisation → Platform; anyone else
///   in an organisation → Organization; a platform admin → Admin (web only, so
///   nothing); otherwise Platform. System (account, help) always.
/// - An item needs the account role; "personal workspace only" items need an
///   organisation session or personal teaching on; workspace-type items need
///   that type; member-role items need that member role.
/// - Plan features: shown when one of the item's features is on; while the
///   plan is unknown, shown only if it is not loading (as the web).
/// - Order (the web's navEntries, utils/sidebarGroups.ts): items are sorted by
///   [order] (NAV_ITEM_ORDER; labels not in it go last, ties keep the list's
///   order); a group sits where its first item is; a group with a single item
///   is shown as that item's own link.
List<MenuSection> visibleMenu(
  List<MenuItem> all,
  MenuViewer v, {
  required List<String> order,
  Map<String, bool>? features,
  bool featuresLoading = false,
}) {
  int position(MenuItem i) {
    final p = order.indexOf(i.label);
    return p < 0 ? order.length : p;
  }

  final inOrganization = v.sessionMode == 'organization';
  final orgStudent = inOrganization && v.memberRole == 'STUDENT';
  final categories = orgStudent
      ? ['Platform', 'System']
      : inOrganization
      ? ['Organization', 'System']
      : v.isPlatformAdmin
      ? ['System']
      : ['Platform', 'System'];

  bool featureOn(MenuItem i) {
    final keys = i.features;
    if (keys == null) return true;
    if (features != null) return keys.any((k) => features[k] == true);
    return !featuresLoading;
  }

  bool visible(MenuItem i) {
    if (!i.roles.contains(v.role)) return false;
    if (i.personalWorkspaceOnly &&
        !inOrganization &&
        !v.personalTeacherEnabled) {
      return false;
    }
    if (i.workspaces != null && !i.workspaces!.contains(v.workspaceType)) {
      return false;
    }
    if (i.memberRoles != null &&
        (v.memberRole == null || !i.memberRoles!.contains(v.memberRole))) {
      return false;
    }
    return featureOn(i);
  }

  final sections = <MenuSection>[];
  for (final category in categories) {
    final entries = <MenuEntry>[];
    final groups = <String, List<MenuItem>>{};
    // A stable sort: by menu position, then by place in the list.
    final items =
        all.indexed
            .where((e) => e.$2.category == category && visible(e.$2))
            .toList()
          ..sort((a, b) {
            final byOrder = position(a.$2).compareTo(position(b.$2));
            return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
          });
    for (final (_, i) in items) {
      final g = i.group;
      if (g == null) {
        entries.add(MenuEntry.item(i));
      } else if (groups.containsKey(g)) {
        groups[g]!.add(i);
      } else {
        groups[g] = [i];
        entries.add(MenuEntry.group(g, groups[g]!));
      }
    }
    if (entries.isNotEmpty) {
      sections.add(
        MenuSection(category, [
          // A group of one is that item's own link.
          for (final e in entries)
            if (e.group != null && e.items.length == 1)
              MenuEntry.item(e.items.single)
            else
              e,
        ]),
      );
    }
  }
  return sections;
}
