import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// What the workspace's plan includes (`GET /me/entitlements`, design §8.3):
/// feature switches and limits. The menu hides what is off.
@immutable
class Entitlements {
  const Entitlements({
    required this.features,
    required this.limits,
    this.planName,
  });

  final Map<String, bool> features;
  final Map<String, num> limits;

  /// The plan's name as the API sends it (not translated).
  final String? planName;

  bool has(String feature) => features[feature] == true;

  factory Entitlements.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final f = j['features'];
    final l = j['limits'];
    final plan = j['plan'];
    return Entitlements(
      features: {
        if (f is Map)
          for (final MapEntry(:key, :value) in f.entries)
            if (key is String) key: value == true,
      },
      limits: {
        if (l is Map)
          for (final MapEntry(:key, :value) in l.entries)
            if (key is String && value is num) key: value,
      },
      planName: plan is Map ? plan['name'] as String? : null,
    );
  }
}

/// The current workspace's plan; null without a workspace or when the call
/// fails (403 before a workspace is chosen). Reloaded when the workspace
/// changes. Students may call it too (API guide §4).
final entitlementsProvider = FutureProvider<Entitlements?>((ref) async {
  final workspace = ref.watch(workspaceKeyProvider);
  if (workspace == null) return null;
  try {
    final r = await ref.read(apiClientProvider).get('/me/entitlements');
    return Entitlements.fromJson(r.payload);
  } on ApiException {
    return null;
  }
}, retry: (retryCount, error) => null);
