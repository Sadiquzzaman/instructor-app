import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// One plan feature from `GET /subscriptions/feature-catalog`.
@immutable
class CatalogFeature {
  const CatalogFeature({
    required this.key,
    required this.group,
    required this.label,
    this.description,
  });

  final String key;
  final String group;

  /// The API's English name, used when the messages do not know [key].
  final String label;
  final String? description;

  /// Null when the item has no key.
  static CatalogFeature? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    if (key is! String || key.isEmpty) return null;
    final group = json['group'];
    final label = json['label'];
    final description = json['description'];
    return CatalogFeature(
      key: key,
      group: group is String && group.isNotEmpty ? group : '',
      label: label is String && label.isNotEmpty ? label : key,
      description: description is String && description.isNotEmpty
          ? description
          : null,
    );
  }
}

/// The catalog's features grouped in the API's order (the web's MoreFeatures).
List<(String group, List<CatalogFeature> features)> groupFeatures(
  List<CatalogFeature> features,
) {
  final byGroup = <String, List<CatalogFeature>>{};
  for (final f in features) {
    (byGroup[f.group] ??= []).add(f);
  }
  return [for (final MapEntry(:key, :value) in byGroup.entries) (key, value)];
}

/// The plan features and "Request this feature" (FND-08).
class FeatureCatalogRepository {
  FeatureCatalogRepository(this._api);

  final ApiClient _api;

  Future<List<CatalogFeature>> catalog() async {
    final r = await _api.get('/subscriptions/feature-catalog');
    final payload = r.payload;
    final list = payload is Map ? payload['features'] : null;
    return [
      if (list is List)
        for (final item in list) ?CatalogFeature.fromJson(item),
    ];
  }

  /// Asks the platform for [featureKey] in the current workspace. Asking
  /// again while a request is open is fine: the server keeps the first.
  Future<void> request(String featureKey, {String? note}) async {
    final trimmed = note?.trim() ?? '';
    await _api.post(
      '/me/feature-requests',
      data: {
        'feature_key': featureKey,
        if (trimmed.isNotEmpty) 'note': trimmed,
      },
    );
  }
}

final featureCatalogRepositoryProvider = Provider<FeatureCatalogRepository>(
  (ref) => FeatureCatalogRepository(ref.watch(apiClientProvider)),
);

/// The feature catalog; the same for every workspace.
final featureCatalogProvider = FutureProvider.autoDispose<List<CatalogFeature>>(
  (ref) => ref.watch(featureCatalogRepositoryProvider).catalog(),
  retry: (retryCount, error) => null,
);
