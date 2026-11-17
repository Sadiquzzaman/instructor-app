import 'package:intl/intl.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/time/org_time.dart';

/// "Wed 19 Nov 2026", or "19 Nov – 21 Nov 2026" (the web's `dates`).
String leaveDates(String from, String to, String language) {
  final locale = OrgTime.intlLocale(language);
  DateTime d(String s) => DateTime.parse('${s}T00:00:00Z');
  if (from == to) return DateFormat.yMMMEd(locale).format(d(from));
  return '${DateFormat.MMMd(locale).format(d(from))} – '
      '${DateFormat.yMMMd(locale).format(d(to))}';
}

String leaveStatus(AppLocalizations l10n, String status) => switch (status) {
  'APPROVED' => l10n.leaveStatusAPPROVED,
  'REJECTED' => l10n.leaveStatusREJECTED,
  'CANCELLED' => l10n.leaveStatusCANCELLED,
  _ => l10n.leaveStatusPENDING,
};

/// The web's sentence for a leave refusal, or null when it has none.
String? leaveErrorText(AppLocalizations l10n, ApiException e, String language) {
  final d = e.details is Map ? e.details! as Map : const <String, Object?>{};
  final days = (d['days'] as num?) ?? 0;
  String date(String k) => d[k] is String
      ? DateFormat.MMMd(OrgTime.intlLocale(language))
            .format(DateTime.parse('${d[k]}T00:00:00Z'))
      : '';
  return switch (e.code) {
    'ATTENDANCE_LEAVE_DATES_INVALID' =>
      l10n.leaveErrorsATTENDANCELEAVEDATESINVALID,
    'ATTENDANCE_LEAVE_TOO_LONG' => l10n.leaveErrorsATTENDANCELEAVETOOLONG(days),
    'ATTENDANCE_LEAVE_TOO_OLD' => l10n.leaveErrorsATTENDANCELEAVETOOOLD(days),
    'ATTENDANCE_LEAVE_TOO_FAR' => l10n.leaveErrorsATTENDANCELEAVETOOFAR(days),
    'ATTENDANCE_LEAVE_NO_SCHOOL_DAYS' =>
      l10n.leaveErrorsATTENDANCELEAVENOSCHOOLDAYS,
    'ATTENDANCE_LEAVE_OVERLAP' => l10n.leaveErrorsATTENDANCELEAVEOVERLAP(
      date('from_date'),
      date('to_date'),
    ),
    'ATTENDANCE_LEAVE_NOT_ALLOWED' => l10n.leaveErrorsATTENDANCELEAVENOTALLOWED,
    'ATTENDANCE_LEAVE_PERSON_NOT_FOUND' =>
      l10n.leaveErrorsATTENDANCELEAVEPERSONNOTFOUND,
    'ATTENDANCE_LEAVE_FILE_INVALID' =>
      l10n.leaveErrorsATTENDANCELEAVEFILEINVALID,
    'ATTENDANCE_LEAVE_NOT_PENDING' => l10n.leaveErrorsATTENDANCELEAVENOTPENDING,
    'ATTENDANCE_LEAVE_CANNOT_CANCEL' =>
      l10n.leaveErrorsATTENDANCELEAVECANNOTCANCEL,
    _ => null,
  };
}
