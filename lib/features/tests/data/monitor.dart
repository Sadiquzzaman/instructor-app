import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:instructor_app/core/api/api_client.dart';
import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/tests/data/exam_live.dart';

/// A student on the live monitor (`GET /exams/:id/proctoring/sessions`).
@immutable
class MonitorSession {
  const MonitorSession({
    required this.studentId,
    required this.name,
    required this.status,
    this.flagCount = 0,
    this.latestFlag,
    this.deadline,
  });

  final String studentId;
  final String name;

  /// WRITING, SUBMITTED, ENDED, DISCONNECTED or LOST.
  final String status;
  final int flagCount;

  /// The latest flag's type ("tab-switch", …).
  final String? latestFlag;

  /// When their time runs out.
  final DateTime? deadline;

  /// Still taking it (time left shows).
  bool get writing =>
      status == 'WRITING' || status == 'LOST' || status == 'DISCONNECTED';

  MonitorSession copyWith({
    String? status,
    int? flagCount,
    String? latestFlag,
  }) => MonitorSession(
    studentId: studentId,
    name: name,
    status: status ?? this.status,
    flagCount: flagCount ?? this.flagCount,
    latestFlag: latestFlag ?? this.latestFlag,
    deadline: deadline,
  );

  static MonitorSession? fromJson(Object? j) {
    if (j is! Map || j['studentId'] is! String) return null;
    final f = j['latestFlag'];
    return MonitorSession(
      studentId: j['studentId'] as String,
      name: (j['studentName'] as String?) ?? '',
      status: (j['liveStatus'] as String?) ?? 'WRITING',
      flagCount: (j['flagCount'] as num?)?.toInt() ?? 0,
      latestFlag: f is Map ? f['type'] as String? : null,
      deadline: j['deadline'] is String
          ? DateTime.tryParse(j['deadline'] as String)
          : null,
    );
  }
}

/// A flag or event on a student's timeline.
typedef TimelineEvent = ({
  String id,
  String type,
  DateTime? at,
  String? message,

  /// SERVER for the teacher's and the server's own events.
  String? source,
});

/// Risk by flag count, as the web colours a tile: none, some (1–4), high.
String riskOf(int flags) =>
    flags >= 5 ? 'high' : (flags >= 1 ? 'some' : 'none');

class MonitorRepository {
  MonitorRepository(this._api);

  final ApiClient _api;

  Future<List<MonitorSession>> sessions(String examId) async {
    final p = (await _api.get('/exams/$examId/proctoring/sessions')).payload;
    final s = p is Map ? p['sessions'] : null;
    return [
      if (s is List)
        for (final x in s) ?MonitorSession.fromJson(x),
    ];
  }

  String _student(String examId, String studentId) =>
      '/exams/$examId/proctoring/students/$studentId';

  Future<List<TimelineEvent>> timeline(String examId, String studentId) async {
    final p = (await _api.get('${_student(examId, studentId)}/timeline'))
        .payload;
    return [
      if (p is List)
        for (final e in p)
          if (e is Map)
            (
              id: '${e['id'] ?? ''}',
              type: (e['type'] as String?) ?? '',
              at: e['occurred_at'] is String
                  ? DateTime.tryParse(e['occurred_at'] as String)
                  : null,
              message: e['message'] as String?,
              source: e['source'] as String?,
            ),
    ];
  }

  Future<void> warn(String examId, String studentId, String message) =>
      _api.post(
        '${_student(examId, studentId)}/warn',
        data: {'message': message.trim()},
      );

  Future<void> end(String examId, String studentId, String reason) => _api.post(
    '${_student(examId, studentId)}/end',
    data: {'reason': reason.trim()},
  );
}

final monitorRepositoryProvider = Provider<MonitorRepository>(
  (ref) => MonitorRepository(ref.watch(apiClientProvider)),
);

/// What the monitor hears: a change to one student, someone new, an alert.
sealed class MonitorEvent {}

/// A student's tile changes ([status] and/or flags).
class SessionChanged extends MonitorEvent {
  SessionChanged(this.studentId, {this.status, this.flagCount, this.flag});
  final String studentId;
  final String? status;
  final int? flagCount;
  final String? flag;
}

/// Someone opened the test: read the list again.
class SessionJoined extends MonitorEvent {}

/// A student reached the test's alert level.
class MonitorAlert extends MonitorEvent {
  MonitorAlert(this.name, this.flagCount);
  final String name;
  final int flagCount;
}

/// The monitor's live connection (the web's useMonitorSocket): joins the
/// test's monitor room. A provider so tests stand in.
abstract class MonitorLive {
  Stream<MonitorEvent> get events;
  Stream<bool> get connected;
  void join(String examId);
  void dispose();
}

class SocketMonitorLive implements MonitorLive {
  SocketMonitorLive(this._token);

  final String Function() _token;
  final _events = StreamController<MonitorEvent>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  io.Socket? _socket;

  @override
  Stream<MonitorEvent> get events => _events.stream;

  @override
  Stream<bool> get connected => _connected.stream;

  @override
  void join(String examId) {
    final socket = io.io(
      SocketExamLive.origin,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .setAuthFn((cb) => cb({'token': _token()}))
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    String? id(Object? d) => d is Map ? d['studentId'] as String? : null;
    void change(Object? d, {String? status}) {
      final s = id(d);
      if (s != null) _events.add(SessionChanged(s, status: status));
    }

    socket
      ..onConnect((_) {
        _connected.add(true);
        socket.emit('exam:join', {'examId': examId, 'role': 'monitor'});
      })
      ..onDisconnect((_) => _connected.add(false))
      ..on('session:joined', (_) => _events.add(SessionJoined()))
      ..on('flag:update', (d) {
        final s = id(d);
        if (s == null || d is! Map) return;
        final f = d['flag'];
        _events.add(
          SessionChanged(
            s,
            status: 'WRITING',
            flagCount: (d['flagCount'] as num?)?.toInt(),
            flag: f is Map ? f['type'] as String? : null,
          ),
        );
      })
      ..on('session:lost', (d) => change(d, status: 'LOST'))
      ..on('session:back', (d) => change(d, status: 'WRITING'))
      ..on('session:left', (d) => change(d, status: 'DISCONNECTED'))
      ..on('session:ended', (d) => change(d, status: 'ENDED'))
      ..on('exam:submitted', (d) => change(d, status: 'SUBMITTED'))
      ..on('alert', (d) {
        if (d is Map) {
          _events.add(
            MonitorAlert(
              '${d['studentName'] ?? ''}',
              (d['flagCount'] as num?)?.toInt() ?? 0,
            ),
          );
        }
      })
      ..connect();
    _socket = socket;
  }

  @override
  void dispose() {
    _socket?.dispose();
    _events.close();
    _connected.close();
  }
}

final monitorLiveProvider = Provider.autoDispose<MonitorLive>((ref) {
  final sessions = ref.watch(sessionHolderProvider);
  final live = SocketMonitorLive(() => sessions.current?.accessToken ?? '');
  ref.onDispose(live.dispose);
  return live;
});
