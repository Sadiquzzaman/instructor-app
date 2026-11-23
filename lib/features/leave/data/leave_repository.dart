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
    this.canDecide = false,
    this.className,
    this.personType,
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

  /// The caller may approve or reject it (approvals).
  final bool canDecide;

  /// "Class 6 A" for a student.
  final String? className;

  /// STUDENT or TEACHER.
  final String? personType;

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
      canDecide: j['can_decide'] == true,
      className: j['class_name'] as String?,
      personType: j['person_type'] as String?,
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
    this.canApprove = false,
  });

  final String today;
  final bool canApply;
  final List<LeaveRequest> requests;

  /// The caller approves others' leave (class teachers, teachers, admins,
  /// owners; the server decides).
  final bool canApprove;

  /// The web's rule: "My leave" shows unless the person only approves.
  bool get showsMine => canApply || requests.isNotEmpty || !canApprove;

  factory MyLeave.fromJson(Object? json) {
    final j = json is Map ? json : const <String, Object?>{};
    final r = j['requests'];
    return MyLeave(
      today: (j['today'] as String?) ?? '',
      canApply: j['can_apply'] == true,
      canApprove: j['can_approve'] == true,
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

  /// Requests the caller approves; [filter] PENDING, DECIDED or ALL.
  Future<List<LeaveRequest>> approvals(String filter) async {
    final p = (await _api.get(
      '/attendance/leave/approvals',
      query: {'status': filter},
    )).payload;
    return [
      if (p is List)
        for (final i in p) ?LeaveRequest.fromJson(i),
    ];
  }

  /// Approves (an optional note) or rejects (a note of 3 or more letters).
  Future<void> decide(String id, {required bool approve, String note = ''}) =>
      _api.post(
        '/attendance/leave/$id/${approve ? 'approve' : 'reject'}',
        data: {if (note.isNotEmpty) 'note': note},
      );
}

final leaveRepositoryProvider = Provider<LeaveRepository>(
  (ref) => LeaveRepository(ref.watch(apiClientProvider)),
);

final myLeaveProvider = FutureProvider.autoDispose<MyLeave>((ref) {
  ref.watch(workspaceKeyProvider);
  return ref.read(leaveRepositoryProvider).mine();
}, retry: (retryCount, error) => null);

/// `GET /attendance/leave/approvals?status=`, by filter.
final leaveApprovalsProvider = FutureProvider.autoDispose
    .family<List<LeaveRequest>, String>((ref, filter) {
      ref.watch(workspaceKeyProvider);
      return ref.read(leaveRepositoryProvider).approvals(filter);
    }, retry: (retryCount, error) => null);
