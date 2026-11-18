import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_metrics.dart';
import 'package:instructor_app/core/time/org_time.dart';

/// A school day ("2026-11-19") as a field that opens the date picker.
/// [value] null shows nothing; [min] keeps an end on or after a start.
class DateField extends StatelessWidget {
  const DateField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.min,
    this.error,
    super.key,
  });

  final String label;
  final String? value;
  final String? min;
  final String? error;
  final ValueChanged<String> onChanged;

  static String format(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _pick(BuildContext context) async {
    final first = min != null
        ? DateTime.parse(min!)
        : DateTime(DateTime.now().year - 5);
    final current = value != null ? DateTime.parse(value!) : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(first) ? first : current,
      firstDate: first,
      lastDate: DateTime(DateTime.now().year + 6),
    );
    if (picked != null) onChanged(format(picked));
  }

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final v = value;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: AppRadius.inputAll,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          suffixIcon: const Icon(Icons.calendar_today_outlined),
        ),
        isEmpty: v == null || v.isEmpty,
        child: Text(
          v == null || v.isEmpty ? '' : OrgTime.schoolDay(v, language),
        ),
      ),
    );
  }
}
