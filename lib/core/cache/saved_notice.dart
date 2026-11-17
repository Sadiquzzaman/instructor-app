import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';

/// "No internet connection. This was saved on your phone at …": above
/// anything shown from the read-only cache.
class SavedNotice extends StatelessWidget {
  const SavedNotice({required this.savedAt, super.key});

  final DateTime savedAt;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final colors = AppColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const Key('saved-copy'),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.warningSoft,
          borderRadius: AppRadius.inputAll,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.cloud_off_outlined, color: colors.warning),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                context.l10n.appSavedCopy(OrgTime.dateTime(savedAt, language)),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
