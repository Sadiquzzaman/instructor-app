import 'package:intl/intl.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/l10n/l10n.dart';
import 'package:instructor_app/core/time/org_time.dart';

/// The four IELTS modules, in test order (the web's `IELTS_MODULES`).
const ieltsModules = ['LISTENING', 'READING', 'WRITING', 'SPEAKING'];

/// The web's short name for a module.
String ieltsModuleShort(AppLocalizations l10n, String module) =>
    switch (module) {
      'LISTENING' => l10n.ieltsTestsModulesShortLISTENING,
      'READING' => l10n.ieltsTestsModulesShortREADING,
      'WRITING' => l10n.ieltsTestsModulesShortWRITING,
      _ => l10n.ieltsTestsModulesShortSPEAKING,
    };

/// MOCK or PRACTICE, as the web names it.
String ieltsPurpose(AppLocalizations l10n, String purpose) => purpose == 'MOCK'
    ? l10n.ieltsTestsPurposesMOCK
    : l10n.ieltsTestsPurposesPRACTICE;

/// A band with one decimal (6.5, 7.0), or "—"; in the language's digits.
String bandText(num? band, String languageCode) => band == null
    ? '—'
    : NumberFormat('0.0', OrgTime.intlLocale(languageCode)).format(band);

/// Whether the person sees IELTS as a student (an IELTS centre's student,
/// or a solo trainer's).
bool ieltsStudent(Session? s) =>
    s?.memberRole == 'STUDENT' ||
    (s?.memberRole == null && s?.role == 'STUDENT');

num? _num(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

Map<String, num> _bands(Object? raw) => {
  if (raw is Map)
    for (final e in raw.entries) '${e.key}': ?_num(e.value),
};

/// `GET /ielts/dashboard` (staff).
class IeltsStaffDashboard {
  const IeltsStaffDashboard({
    required this.batches,
    required this.students,
    required this.writingWaiting,
    required this.speakingWaiting,
    required this.upcoming,
    required this.batchBands,
  });

  factory IeltsStaffDashboard.fromJson(Map<String, Object?> j) {
    final waiting = j['waiting'] is Map
        ? j['waiting']! as Map
        : const <String, Object?>{};
    return IeltsStaffDashboard(
      batches: _num(j['batches'])?.toInt() ?? 0,
      students: _num(j['students'])?.toInt() ?? 0,
      writingWaiting: _num(waiting['writing'])?.toInt() ?? 0,
      speakingWaiting: _num(waiting['speaking'])?.toInt() ?? 0,
      upcoming: [
        for (final u in (j['upcoming'] as List?) ?? const [])
          if (u is Map)
            (
              id: '${u['assignment_id']}',
              title: '${u['test_title'] ?? ''}',
              batch: '${u['batch'] ?? ''}',
              opens: DateTime.tryParse('${u['opens_at']}'),
              closes: DateTime.tryParse('${u['closes_at']}'),
            ),
      ],
      batchBands: [
        for (final b in (j['batch_bands'] as List?) ?? const [])
          if (b is Map)
            (
              id: '${b['section_id']}',
              batch: '${b['batch'] ?? ''}',
              bands: _bands(b['bands']),
            ),
      ],
    );
  }

  final int batches;
  final int students;
  final int writingWaiting;
  final int speakingWaiting;
  final List<
    ({String id, String title, String batch, DateTime? opens, DateTime? closes})
  >
  upcoming;
  final List<({String id, String batch, Map<String, num> bands})> batchBands;
}

/// `GET /ielts/dashboard/me` (a student).
class IeltsStudentDashboard {
  const IeltsStudentDashboard({
    required this.targetOverall,
    required this.targets,
    required this.daysToTest,
    required this.latest,
    required this.openNow,
    required this.next,
  });

  factory IeltsStudentDashboard.fromJson(Map<String, Object?> j) {
    final p = j['profile'] is Map
        ? j['profile']! as Map
        : const <String, Object?>{};
    final n = j['next'] is Map ? j['next']! as Map : null;
    return IeltsStudentDashboard(
      targetOverall: _num(p['target_overall']),
      targets: _bands(p['target_bands']),
      daysToTest: _num(p['days_to_test'])?.toInt(),
      latest: _bands(j['latest']),
      openNow: _num(j['open_now'])?.toInt() ?? 0,
      next: n == null
          ? null
          : (
              title: '${n['test_title'] ?? ''}',
              purpose: '${n['purpose'] ?? 'PRACTICE'}',
              opens: DateTime.tryParse('${n['opens_at']}'),
              closes: DateTime.tryParse('${n['closes_at']}'),
            ),
    );
  }

  final num? targetOverall;
  final Map<String, num> targets;
  final int? daysToTest;
  final Map<String, num> latest;
  final int openNow;
  final ({String title, String purpose, DateTime? opens, DateTime? closes})?
  next;

  /// A module's target: its own, else the overall one (as the web).
  num? targetFor(String module) => targets[module] ?? targetOverall;
}
