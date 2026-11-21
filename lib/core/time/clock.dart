import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The device's clock, as a provider so tests can move time on (timers
/// that compare against "now", such as a test's countdown).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
