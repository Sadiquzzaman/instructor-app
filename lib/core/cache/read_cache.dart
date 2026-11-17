import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_exception.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/l10n/language_controller.dart';

const _prefix = 'cache/';

/// An answer, and when it was saved if it came from the phone.
@immutable
class Cached {
  const Cached(this.payload, {this.savedAt});
  final Object? payload;

  /// Set when there was no connection and this is the saved copy.
  final DateTime? savedAt;
  bool get isSaved => savedAt != null;
}

/// The read-only cache (owner's decision 5): a few answers the person needs
/// without a connection (today's classes, the timetable) are kept on the
/// phone, per user and workspace, and shown, marked as saved, only when the
/// network is down. Nothing is ever written from the cache. Everything is
/// removed when the person signs out; another workspace never sees them
/// (the key includes the workspace).
class ReadCache {
  ReadCache(this._prefs, this._api, this._workspace);

  final SharedPreferences _prefs;
  final ApiClient _api;
  final String? _workspace;

  /// GET [path]; on success the answer is saved under [name]. With no
  /// connection (or a timeout) the saved answer is returned instead, if
  /// there is one for this workspace; otherwise the error is thrown.
  Future<Cached> get(
    String name,
    String path, {
    Map<String, Object?>? query,
  }) async {
    final key = _workspace == null ? null : '$_prefix$_workspace/$name';
    try {
      final r = await _api.get(path, query: query);
      if (key != null) {
        await _prefs.setString(
          key,
          jsonEncode({
            'saved_at': DateTime.now().toUtc().toIso8601String(),
            'payload': r.payload,
          }),
        );
      }
      return Cached(r.payload);
    } on ApiException catch (e) {
      final offline =
          e.kind == ApiErrorKind.network || e.kind == ApiErrorKind.timeout;
      final saved = key == null ? null : _prefs.getString(key);
      if (!offline || saved == null) rethrow;
      final j = jsonDecode(saved) as Map<String, dynamic>;
      return Cached(
        j['payload'],
        savedAt: DateTime.tryParse(j['saved_at'] as String? ?? ''),
      );
    }
  }

  /// Removes every saved answer (sign-out).
  static Future<void> clearAll(SharedPreferences prefs) async {
    for (final k in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      await prefs.remove(k);
    }
  }
}

final readCacheProvider = Provider<ReadCache>(
  (ref) => ReadCache(
    ref.watch(sharedPreferencesProvider),
    ref.watch(apiClientProvider),
    ref.watch(workspaceKeyProvider),
  ),
);

/// Clears the cache when the person signs out. Kept alive by the app.
final readCacheJanitorProvider = Provider<void>((ref) {
  final signedIn = ref.watch(sessionProvider) != null;
  if (!signedIn) ReadCache.clearAll(ref.read(sharedPreferencesProvider));
});
