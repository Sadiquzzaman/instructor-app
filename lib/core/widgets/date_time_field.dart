import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/date_field.dart';

/// A school day and a clock time in the organisation's time zone, as an
/// instant.
DateTime fromWallClock(String day, int hour, int minute) {
  final p = day.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2], hour, minute).subtract(OrgTime.offset);
}

/// A date and a time picked in the organisation's time zone (Asia/Dhaka,
/// not the phone's), giving an instant.
class DateTimeField extends StatelessWidget {
  const DateTimeField({
    required this.dateLabel,
    required this.timeLabel,
    required this.value,
    required this.onChanged,
    this.defaultHour = 9,
    this.min,
    super.key,
  });

  final String dateLabel;
  final String timeLabel;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  /// The hour used when only the day has been picked.
  final int defaultHour;

  /// The earliest day (YYYY-MM-DD).
  final String? min;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final wall = value == null ? null : OrgTime.wallClock(value!);
    final day = wall == null ? null : DateField.format(wall);
    final k = key is ValueKey ? (key! as ValueKey).value : 'date-time';
    return Row(
      children: [
        Expanded(
          child: DateField(
            key: Key('$k-date'),
            label: dateLabel,
            value: day,
            min: min,
            onChanged: (v) => onChanged(
              fromWallClock(v, wall?.hour ?? defaultHour, wall?.minute ?? 0),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: OutlinedButton.icon(
            key: Key('$k-time'),
            icon: const Icon(Icons.schedule),
            label: Text(
              wall == null
                  ? timeLabel
                  : OrgTime.timeOfDay(
                      '${wall.hour}:${wall.minute.toString().padLeft(2, '0')}',
                      language,
                    ),
            ),
            onPressed: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: TimeOfDay(
                  hour: wall?.hour ?? defaultHour,
                  minute: wall?.minute ?? 0,
                ),
              );
              if (picked == null) return;
              onChanged(
                fromWallClock(
                  day ?? OrgTime.today(),
                  picked.hour,
                  picked.minute,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
