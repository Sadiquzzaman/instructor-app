import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:instructor_app/core/time/org_time.dart';

/// Mirrors the web's frontend/i18n/format.test.ts where it applies.
void main() {
  setUpAll(initializeDateFormatting);

  // 23:30 UTC on 23 Oct is 05:30 on 24 Oct in Dhaka.
  final lateUtc = DateTime.utc(2026, 10, 23, 23, 30);

  test('instants are shown in Dhaka time, not the phone\'s', () {
    expect(OrgTime.date(lateUtc, 'en'), '24 Oct 2026');
    expect(OrgTime.time(lateUtc, 'en'), '05:30');
    expect(OrgTime.dateTime(lateUtc, 'en'), '24 Oct 2026, 05:30');
    // The same instant given in another zone gives the same answer.
    expect(OrgTime.time(lateUtc.toLocal(), 'en'), '05:30');
  });

  test('Bangla uses Bangla digits and month names', () {
    final bn = OrgTime.date(lateUtc, 'bn');
    expect(bn, contains('২৪'));
    expect(bn, contains('২০২৬'));
    expect(bn, isNot(contains('24')));
    expect(OrgTime.time(lateUtc, 'bn'), '০৫:৩০');
  });

  test('today is the Dhaka date', () {
    expect(OrgTime.today(lateUtc), '2026-10-24');
  });

  test('school days are not shifted', () {
    expect(OrgTime.schoolDay('2026-10-24', 'en'), '24 Oct 2026');
  });

  test('times of day from the API', () {
    expect(OrgTime.timeOfDay('16:00', 'en'), '16:00');
    expect(OrgTime.timeOfDay('09:05:00', 'en'), '09:05');
    expect(OrgTime.timeOfDay('16:00', 'bn'), '১৬:০০');
  });

  test('clocks, numbers and two digits', () {
    expect(OrgTime.clock(65, 'en'), '01:05');
    expect(OrgTime.clock(65, 'bn'), '০১:০৫');
    expect(OrgTime.clock(-3, 'en'), '00:00');
    expect(OrgTime.number(1250, 'en'), '1,250');
    expect(OrgTime.number(1250, 'bn'), '১,২৫০');
    expect(OrgTime.twoDigits(7, 'bn'), '০৭');
  });
}
