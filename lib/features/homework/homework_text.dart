import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/time/org_time.dart';
import 'package:instructor_app/core/widgets/status_pill.dart';
import 'package:instructor_app/features/homework/data/homework.dart';

/// "Due Wed 19 Nov, 20:00" in its tone (the web's due pill).
(String, StatusTone) dueText(
  AppLocalizations l10n,
  DateTime? dueAt,
  String language,
) {
  final state = dueStateOf(dueAt);
  final when = dueAt == null ? '' : OrgTime.dateTime(dueAt, language);
  return switch (state) {
    'overdue' => (l10n.homeworkDueOverdue(when), StatusTone.danger),
    'soon' => (l10n.homeworkDueSoon(when), StatusTone.warning),
    'later' => (l10n.homeworkDueLater(when), StatusTone.success),
    _ => (l10n.homeworkDueNone, StatusTone.neutral),
  };
}

/// "8/10 · 80% (A)" (the web's `scoreLabel`), or null without a score.
String? scoreText(HomeworkScore s, String language) {
  if (s.finalScore == null) return null;
  String n(num v) => OrgTime.number(v, language);
  final marks = s.totalMarks == null
      ? n(s.finalScore!)
      : '${n(s.finalScore!)}/${n(s.totalMarks!)}';
  final percent = s.percent == null
      ? ''
      : ' · ${n(num.parse(s.percent!.toStringAsFixed(1)))}%';
  final grade = s.grade == null ? '' : ' (${s.grade})';
  return '$marks$percent$grade';
}

/// The web's sentence for a hand-in refusal, or null.
String? submitErrorText(
  AppLocalizations l10n,
  String? code, {
  int maxFiles = 0,
}) => switch (code) {
  'HOMEWORK_PAPER_NO_SUBMISSION' =>
    l10n.homeworkErrorsHOMEWORKPAPERNOSUBMISSION,
  'HOMEWORK_LATE_NOT_ALLOWED' => l10n.homeworkErrorsHOMEWORKLATENOTALLOWED,
  'HOMEWORK_NO_MORE_SUBMISSIONS' =>
    l10n.homeworkErrorsHOMEWORKNOMORESUBMISSIONS,
  'HOMEWORK_ALREADY_SCORED' => l10n.homeworkErrorsHOMEWORKALREADYSCORED,
  'HOMEWORK_SUBMISSION_EMPTY' => l10n.homeworkErrorsHOMEWORKSUBMISSIONEMPTY,
  'HOMEWORK_TOO_MANY_FILES' => l10n.homeworkErrorsHOMEWORKTOOMANYFILES(
    maxFiles,
  ),
  'HOMEWORK_FILE_INVALID' => l10n.homeworkErrorsHOMEWORKFILEINVALID,
  'HOMEWORK_SESSION_CLOSED' => l10n.homeworkErrorsHOMEWORKSESSIONCLOSED,
  _ => null,
};
