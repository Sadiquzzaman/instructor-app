import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_providers.dart';

typedef ReminderOffset = ({int minutes, String channel});

/// The person's reminders for one kind (CLASS, EXAM, EVENT).
@immutable
class ReminderSetting {
  const ReminderSetting(this.offsets, {required this.own});

  final List<ReminderOffset> offsets;

  /// False: the organisation's defaults apply.
  final bool own;
}

/// `GET /reminders`: shown read-only in the app (owner's decision 3 for
/// Stage 1); they are changed on the web.
final remindersProvider =
    FutureProvider.autoDispose<Map<String, ReminderSetting>>((ref) async {
      ref.watch(workspaceKeyProvider);
      final p = (await ref.read(apiClientProvider).get('/reminders')).payload;
      final mine = p is Map ? p['mine'] : null;
      List<ReminderOffset> offsets(Object? list) => [
        if (list is List)
          for (final o in list)
            if (o is Map && o['minutes'] is num)
              (
                minutes: (o['minutes'] as num).toInt(),
                channel: (o['channel'] as String?) ?? 'IN_APP',
              ),
      ];
      return {
        if (mine is Map)
          for (final MapEntry(:key, :value) in mine.entries)
            if (key is String && value is Map)
              key: ReminderSetting(
                offsets(value['offsets']),
                own: value['own'] == true,
              ),
      };
    }, retry: (retryCount, error) => null);
