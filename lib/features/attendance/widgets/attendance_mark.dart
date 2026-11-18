import 'package:material_ui/material_ui.dart';

import 'package:instructor_app/core/theme/app_colors.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/l10n/generated/app_localizations.dart';

/// A class status's name (the web's `myAttendance.status`).
String attendanceStatusName(AppLocalizations l10n, String status) =>
    switch (status) {
      'UPCOMING' => l10n.myAttendanceStatusUPCOMING,
      'OPEN' => l10n.myAttendanceStatusOPEN,
      'PRESENT' => l10n.myAttendanceStatusPRESENT,
      'LATE' => l10n.myAttendanceStatusLATE,
      'ABSENT' => l10n.myAttendanceStatusABSENT,
      'LEAVE' => l10n.myAttendanceStatusLEAVE,
      'CLOSED_DAY' => l10n.myAttendanceStatusCLOSEDDAY,
      'CANCELLED' => l10n.myAttendanceStatusCANCELLED,
      _ => l10n.myAttendanceStatusNOTRECORDED,
    };

/// A class status's letter, for its mark.
String attendanceLetter(AppLocalizations l10n, String status) =>
    switch (status) {
      'UPCOMING' => l10n.myAttendanceLetterUPCOMING,
      'OPEN' => l10n.myAttendanceLetterOPEN,
      'PRESENT' => l10n.myAttendanceLetterPRESENT,
      'LATE' => l10n.myAttendanceLetterLATE,
      'ABSENT' => l10n.myAttendanceLetterABSENT,
      'LEAVE' => l10n.myAttendanceLetterLEAVE,
      'CLOSED_DAY' => l10n.myAttendanceLetterCLOSEDDAY,
      'CANCELLED' => l10n.myAttendanceLetterCANCELLED,
      _ => l10n.myAttendanceLetterNOTRECORDED,
    };

/// A class status's colour, for a pill.
StatusTone attendanceTone(String status) => switch (status) {
  'OPEN' => StatusTone.primary,
  'PRESENT' => StatusTone.success,
  'LATE' => StatusTone.warning,
  'ABSENT' => StatusTone.danger,
  'LEAVE' => StatusTone.info,
  _ => StatusTone.neutral,
};

/// A status mark: its colour and letter (the web's `StatusMark`).
class AttendanceMark extends StatelessWidget {
  const AttendanceMark({
    required this.status,
    required this.letter,
    this.size = 22,
    super.key,
  });

  final String status;
  final String letter;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (fill, ink, border) = switch (status) {
      'OPEN' => (c.primarySoft, c.primary, c.primary),
      'PRESENT' => (c.success, c.inkInverse, null),
      'LATE' => (c.warning, c.inkInverse, null),
      'ABSENT' => (c.danger, c.inkInverse, null),
      'LEAVE' => (c.info, c.inkInverse, null),
      'NOT_RECORDED' => (c.surface, c.inkMuted, c.border),
      _ => (c.canvas, c.inkMuted, c.border),
    };
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border),
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: ink, fontWeight: FontWeight.w700, height: 1),
      ),
    );
  }
}
