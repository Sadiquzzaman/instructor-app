import 'package:flutter/foundation.dart';

/// One link of the web's side menu (frontend/utils/sidebarList.tsx), as
/// generated into menu_items.g.dart by tool/import_menu.dart.
@immutable
class MenuItem {
  const MenuItem({
    required this.category,
    required this.label,
    required this.route,
    required this.roles,
    required this.icon,
    this.group,
    this.memberRoles,
    this.personalWorkspaceOnly = false,
    this.workspaces,
    this.features,
    this.setup = false,
  });

  /// `Admin`, `Platform`, `Organization` or `System`.
  final String category;

  /// Message key under `nav` (the translated name).
  final String label;

  /// The web's route; the app's screens use the same paths.
  final String route;

  /// The account roles (`STUDENT`, `TEACHER`, `ADMIN`, `SUPER_ADMIN`).
  final Set<String> roles;

  /// The web's icon component, as a short name (`dashboard`, `classes`, …).
  final String icon;

  /// The group it folds into (`attendance`, `academics`, …), if any.
  final String? group;

  /// In an organisation: the member roles that see it (null = all).
  final Set<String>? memberRoles;

  /// Only for a teacher's own workspace (or in an organisation).
  final bool personalWorkspaceOnly;

  /// `ACADEMIC` and/or `IELTS` (null = both).
  final Set<String>? workspaces;

  /// Hidden while none of these plan features is on (null = always shown).
  final List<String>? features;

  /// A settings page ("Setup" heading in its group).
  final bool setup;

  /// IELTS-only pages: the app shows "Use the web for IELTS for now" until
  /// stage 5 (owner's decision 6).
  bool get ieltsOnly =>
      workspaces != null &&
      workspaces!.length == 1 &&
      workspaces!.contains('IELTS');
}
