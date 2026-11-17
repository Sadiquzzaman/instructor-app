import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/core/theme/app_theme.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

/// The root widget. Languages (PR 4) and routing (PR 7) are added here by the
/// following Stage 0 pull requests; the theme follows the language then.
class InstructorApp extends StatelessWidget {
  const InstructorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(bangla: false),
      home: const PlaceholderHome(),
    );
  }
}
