import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';

/// A person in a leave request (who asked, who answered).
typedef LeavePerson = ({String id, String name});

LeavePerson? _person(Object? j) => j is Map && j['id'] is String
    ? (id: j['id'] as String, name: (j['full_name'] as String?) ?? '')
    : null;

/// One leave request (`/attendance/leave/*`).
@immutable
class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.fromDate,
    required this.toDate,
    required this.schoolDays,
    required this.reason,
    required this.status,
    this.person,
    this.appliedBy,
    this.decidedBy,
    this.decisionNote,
    this.cancelledBy,
    this.fileId,
    this.fileName,
    this.canCancel = false,
  });

  final String id;
  final String fromDate;
  final String toDate;

  /// Days in the range that are not a weekly off day or a holiday.
  final int schoolDays;
  final String reason;

  /// PENDING, APPROVED, REJECTED or CANCELLED.
  final String status;
  final LeavePerson? person;
  final LeavePerson? appliedBy;
  final LeavePerson? decidedBy;
  final String? decisionNote;
  final LeavePerson? cancelledBy;
  final String? fileId;
  final String? fileName;
  final bool canCancel;

  static LeaveRequest? fromJson(Object? j) {
    if (j is! Map || j['id'] is! String) return null;
    final file = j['file'];
    return LeaveRequest(
      id: j['id'] as String,
      fromDate: (j['from_date'] as String?) ?? '',
      toDate: (j['to_date'] as String?) ?? (j['from_date'] as String?) ?? '',
      schoolDays: (j['school_days'] as num?)?.toInt() ?? 0,
      reason: (j['reason'] as String?) ?? '',
      status: (j['status'] as String?) ?? 'PENDING',
      person: _person(j['person']),
      appliedBy: _person(j['applied_by']),
      decidedBy: _person(j['decided_by']),
      decisionNote: j['decision_note'] as String?,
      cancelledBy: _person(j['cancelled_by']),
      fileId: file is Map ? file['id'] as String? : null,
      fileName: file is Map ? file['name'] as String? : null,
      canCancel: j['can_cancel'] == true,
    );
  }
}

/// `GET /attendance/leave/mine`: what the person may do, and their requests.
@immutable
class MyLeave {
  const MyLeave({
    required this.today,
    required this.canApply,
    required this.requests,
  });

  final String today;
  final bool canApply;
  final List<LeaveRequest> requests;

  factory MyLeave.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final r = j['requests'];
    return MyLeave(
      today: (j['today'] as String?) ?? '',
      canApply: j['can_apply'] == true,
      requests: [
        if (r is List)
          for (final i in r) ?LeaveRequest.fromJson(i),
      ],
    );
  }
}

class LeaveRepository {
  LeaveRepository(this._api);

  final ApiClient _api;

  Future<MyLeave> mine() async =>
      MyLeave.fromJson((await _api.get('/attendance/leave/mine')).payload);

  /// Applies for the person's own leave; the answer says whether it was
  /// approved at once.
  Future<LeaveRequest?> apply({
    required String from,
    required String to,
    required String reason,
    String? fileId,
  }) async {
    final r = await _api.post(
      '/attendance/leave',
      data: {
        'from_date': from,
        'to_date': to,
        'reason': reason,
        'file_id': ?fileId,
      },
    );
    return LeaveRequest.fromJson(r.payload);
  }

  Future<void> withdraw(String id) =>
      _api.post('/attendance/leave/$id/cancel', data: const <String, Object>{});
}

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => LeaveRepository(ref.watch(apiClientProvider)),
);

final myLeaveProvider = FutureProvider.autoDispose<MyLeave>((ref) {
  ref.watch(workspaceKeyProvider);
  return ref.read(leaveRepositoryProvider).mine();
}, retry: (retryCount, error) => null);
