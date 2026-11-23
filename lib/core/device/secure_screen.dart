import 'package:flutter/services.dart';

const _channel = MethodChannel('academy.instructor.app/secure');

/// Blocks screenshots and screen recording (Android `FLAG_SECURE`) while a
/// test is open (Light proctoring, owner's decision for Stage 1). iOS cannot
/// block them; there the call does nothing.
Future<void> setSecureScreen(bool on) async {
  try {
    await _channel.invokeMethod<void>('setSecure', on);
  } on MissingPluginException {
    // iOS, tests: nothing to do.
  } on PlatformException {
    // Never let this stop a test.
  }
}
