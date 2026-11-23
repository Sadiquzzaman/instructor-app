import 'package:material_ui/material_ui.dart';

/// The web's sidebar icons (SidebarDashboardIconSVG, …) as Material icons.
IconData menuIcon(String webIcon) => switch (webIcon) {
  'dashboard' => Icons.space_dashboard_outlined,
  'classes' => Icons.class_outlined,
  'tests' => Icons.quiz_outlined,
  'grading' => Icons.grading_outlined,
  'results' => Icons.insights_outlined,
  'account' => Icons.person_outline,
  'help' => Icons.help_outline,
  _ => Icons.circle_outlined,
};

/// The groups' icons (the web shows a chevron; the app adds a hint).
IconData menuGroupIcon(String group) => switch (group) {
  'attendance' => Icons.how_to_reg_outlined,
  'academics' => Icons.school_outlined,
  'tests' => Icons.quiz_outlined,
  'results' => Icons.insights_outlined,
  'people' => Icons.groups_outlined,
  'billing' => Icons.receipt_long_outlined,
  'logs' => Icons.history_outlined,
  _ => Icons.folder_outlined,
};
