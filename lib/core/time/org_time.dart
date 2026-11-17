import 'package:intl/intl.dart';

/// Times and numbers as the web shows them (frontend/i18n/format.ts):
/// in the organisation's time zone, day-month-year, 24-hour, and Bangla
/// digits in Bangla.
///
/// The API sends instants in UTC and school days as plain dates in the
/// organisation's time zone. No endpoint returns that zone yet, and the web
/// assumes Asia/Dhaka, so the app does too, here only. Dhaka is UTC+6 with no
/// daylight saving, so a fixed offset is exact; a time-zone package comes
/// when organisations outside Bangladesh do.
abstract final class OrgTime {
  static const timeZone = 'Asia/Dhaka';
  static const offset = Duration(hours: 6);

  /// intl locale per app language: day-month-year English, Bangla digits.
  static String intlLocale(String languageCode) =>
      languageCode == 'bn' ? 'bn' : 'en_GB';

  /// An instant (any zone) as the organisation's wall-clock time. The result
  /// is a UTC DateTime whose fields read as Dhaka time; only format it.
  static DateTime wallClock(DateTime instant) => instant.toUtc().add(offset);

  /// Today's date in the organisation, as the API's `YYYY-MM-DD`.
  static String today([DateTime? now]) =>
      DateFormat('yyyy-MM-dd').format(wallClock(now ?? DateTime.now()));

  /// "24 Oct 2026" / "২৪ অক্টো, ২০২৬".
  static String date(DateTime instant, String languageCode) =>
      DateFormat.yMMMd(intlLocale(languageCode)).format(wallClock(instant));

  /// A school day from the API ("2026-10-24") in the same style, without any
  /// time-zone shift.
  static String schoolDay(String yyyyMmDd, String languageCode) =>
      DateFormat.yMMMd(intlLocale(languageCode))
          .format(DateTime.parse('${yyyyMmDd}T00:00:00Z'));

  /// "24 Oct 2026, 15:30" / "২৪ অক্টো, ২০২৬ ১৫:৩০".
  static String dateTime(DateTime instant, String languageCode) {
    final l = intlLocale(languageCode);
    final w = wallClock(instant);
    return '${DateFormat.yMMMd(l).format(w)}, ${DateFormat('HH:mm', l).format(w)}';
  }

  /// "15:30" / "১৫:৩০" for an instant.
  static String time(DateTime instant, String languageCode) =>
      DateFormat('HH:mm', intlLocale(languageCode)).format(wallClock(instant));

  /// A time of day from the API ("16:00" or "16:00:00") as HH:MM.
  static String timeOfDay(String value, String languageCode) {
    final [h, m, ...] = value.split(':').map(int.parse).toList();
    return '${twoDigits(h, languageCode)}:${twoDigits(m, languageCode)}';
  }

  /// Seconds as MM:SS: 65 → "01:05" / "০১:০৫".
  static String clock(int totalSeconds, String languageCode) {
    final s = totalSeconds < 0 ? 0 : totalSeconds;
    return '${twoDigits(s ~/ 60, languageCode)}:${twoDigits(s % 60, languageCode)}';
  }

  /// A number in the language's digits with grouping: 1,250 / ১,২৫০.
  static String number(num value, String languageCode) =>
      NumberFormat.decimalPattern(intlLocale(languageCode)).format(value);

  /// Two digits: 7 → "07" / "০৭".
  static String twoDigits(int value, String languageCode) =>
      NumberFormat('00', intlLocale(languageCode)).format(value);
}
