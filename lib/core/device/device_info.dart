import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What the app says about this phone when it signs in and refreshes:
/// `device: { platform, name, app_version }` (API guide §3, PM-01). It shows in
/// the user's list of signed-in devices.
@immutable
class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    required this.name,
    required this.appVersion,
  });

  /// ANDROID or IOS.
  final String platform;

  /// Make and model ("Google Pixel 8", "iPhone 15"); never the name the owner
  /// gave the phone, which often contains a person's name.
  final String name;
  final String appVersion;

  // The API's limits (device-info.dto.ts).
  static const maxName = 120;
  static const maxVersion = 30;

  Map<String, String> toJson() => {
    'platform': platform,
    'name': _cut(name, maxName),
    'app_version': _cut(appVersion, maxVersion),
  };

  static String _cut(String s, int max) =>
      s.length <= max ? s : s.substring(0, max);

  /// Reads this phone once; falls back to safe values if a plugin fails.
  static Future<DeviceInfo> load() async {
    var version = '0.0.0';
    try {
      version = (await PackageInfo.fromPlatform()).version;
    } on Object {
      // Keep the fallback.
    }
    final plugin = DeviceInfoPlugin();
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = await plugin.iosInfo;
        return DeviceInfo(
          platform: 'IOS',
          name: ios.modelName.isNotEmpty ? ios.modelName : ios.model,
          appVersion: version,
        );
      }
      final android = await plugin.androidInfo;
      final maker = android.manufacturer.trim();
      final model = android.model.trim();
      final name = model.toLowerCase().startsWith(maker.toLowerCase())
          ? model
          : '${_capital(maker)} $model'.trim();
      return DeviceInfo(platform: 'ANDROID', name: name, appVersion: version);
    } on Object {
      return DeviceInfo(
        platform: defaultTargetPlatform == TargetPlatform.iOS
            ? 'IOS'
            : 'ANDROID',
        name: defaultTargetPlatform == TargetPlatform.iOS
            ? 'iPhone'
            : 'Android',
        appVersion: version,
      );
    }
  }

  static String _capital(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
