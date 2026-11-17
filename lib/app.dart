import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

/// The root widget. Theme (PR 3), languages (PR 4) and routing (PR 7) are
/// added here by the following Stage 0 pull requests.
class InstructorApp extends StatelessWidget {
  const InstructorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      home: PlaceholderHome(),
    );
  }
}
