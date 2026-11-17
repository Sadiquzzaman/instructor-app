import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/config/app_config.dart';

/// Stands in for the app shell until sign-in and the menu exist (Stage 0,
/// PRs 7 and 10). It shows only the brand name, which is not translated.
class PlaceholderHome extends StatelessWidget {
  const PlaceholderHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Text(
            AppConfig.appName,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        ),
      ),
    );
  }
}
