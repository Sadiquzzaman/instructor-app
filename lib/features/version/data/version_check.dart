import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/device/device_info.dart';

/// What `GET /app/version` says about this build (PM-03).
enum UpdateNeed {
  /// Up to date, or the check could not be made.
  none,

  /// A newer version exists: suggest it.
  optional,

  /// Below the minimum: the app stops until it is updated.
  required,
}

@immutable
class VersionStatus {
  const VersionStatus({required this.need, this.latest, this.updateUrl});

  static const unknown = VersionStatus(need: UpdateNeed.none);

  final UpdateNeed need;
  final String? latest;

  /// Where to get the new version. Only https links are kept.
  final Uri? updateUrl;

  factory VersionStatus.fromPayload(Map<String, dynamic> p) {
    final url = Uri.tryParse((p['update_url'] as String?) ?? '');
    return VersionStatus(
      need: switch (p['update']) {
        'REQUIRED' => UpdateNeed.required,
        'OPTIONAL' => UpdateNeed.optional,
        _ => UpdateNeed.none,
      },
      latest: p['latest'] as String?,
      updateUrl: url != null && url.scheme == 'https' && url.host.isNotEmpty
          ? url
          : null,
    );
  }
}

/// Asks the API whether this build must or may be updated. Any failure
/// (no connection, a 502 during a deploy) counts as "no update": the check
/// never blocks the app by itself.
Future<VersionStatus> checkVersion(ApiClient api, DeviceInfo device) async {
  try {
    final r = await api.get(
      '/app/version',
      query: {'platform': device.platform, 'current': device.appVersion},
      auth: false,
    );
    return VersionStatus.fromPayload(r.object);
  } on Object {
    return VersionStatus.unknown;
  }
}

/// The current answer; [VersionController.recheck] asks again.
final versionStatusProvider =
    AsyncNotifierProvider<VersionController, VersionStatus>(
      VersionController.new,
    );

class VersionController extends AsyncNotifier<VersionStatus> {
  @override
  Future<VersionStatus> build() async => checkVersion(
    ref.watch(apiClientProvider),
    await ref.watch(deviceInfoProvider),
  );

  Future<void> recheck() async {
    final status = await checkVersion(
      ref.read(apiClientProvider),
      await ref.read(deviceInfoProvider),
    );
    // Keep showing the old answer until the new one is in.
    state = AsyncData(status);
  }
}

/// The optional-update banner was dismissed (until the app restarts).
final optionalUpdateDismissedProvider =
    NotifierProvider<OptionalUpdateDismissed, bool>(
      OptionalUpdateDismissed.new,
    );

class OptionalUpdateDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}
