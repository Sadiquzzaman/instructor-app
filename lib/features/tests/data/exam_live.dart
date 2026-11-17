import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/config/app_config.dart';
import 'package:instructor_app/features/tests/data/take_test.dart';

/// A sign of life this often: the teacher sees "Monitoring lost" after 60 s
/// without one (P8-02).
const heartbeatEvery = Duration(seconds: 15);

/// Something the teacher did on the live monitor.
sealed class TeacherEvent {}

class TeacherWarning extends TeacherEvent {
  TeacherWarning(this.message, this.from);
  final String message;
  final String from;
}

class TestEnded extends TeacherEvent {
  TestEnded(this.reason);
  final String reason;
}

/// The test's live connection (Socket.IO, default namespace; API guide §7):
/// joins the test, sends a heartbeat, reports flags and the submit, and
/// hears the teacher's warning or "ended". A provider so tests stand in.
abstract class ExamLive {
  Stream<TeacherEvent> get events;
  void join(String examId);
  void flag(String examId, ProctorFlag flag);
  void submit(
    String examId, {
    required String studentId,
    required String studentName,
    required Map<String, Object> answers,
    required int totalFlagPoints,
  });
  void dispose();
}

class SocketExamLive implements ExamLive {
  SocketExamLive(this._token);

  final String Function() _token;
  final _events = StreamController<TeacherEvent>.broadcast();
  io.Socket? _socket;
  Timer? _beat;
  String? _examId;

  @override
  Stream<TeacherEvent> get events => _events.stream;

  /// The API host without /api/v1.
  static String get origin {
    final u = Uri.parse(AppConfig.apiBaseUrl);
    return '${u.scheme}://${u.authority}';
  }

  @override
  void join(String examId) {
    _examId = examId;
    final socket = io.io(
      origin,
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          // A fresh token on every (re)connection, after any refresh.
          .setAuthFn((cb) => cb({'token': _token()}))
          .disableAutoConnect()
          .enableReconnection()
          .build(),
    );
    socket
      ..onConnect(
        (_) => socket.emit('exam:join', {'examId': examId, 'role': 'student'}),
      )
      ..on('proctor:warning', (data) {
        if (data is Map) {
          _events.add(
            TeacherWarning('${data['message'] ?? ''}', '${data['from'] ?? ''}'),
          );
        }
      })
      ..on('exam:ended', (data) {
        _events.add(TestEnded(data is Map ? '${data['reason'] ?? ''}' : ''));
      })
      ..connect();
    _socket = socket;
    _beat = Timer.periodic(heartbeatEvery, (_) {
      if (socket.connected) socket.emit('heartbeat');
    });
  }

  @override
  void flag(String examId, ProctorFlag flag) => _socket?.emit('flag:report', {
    'examId': examId,
    'id': flag.id,
    'kind': flag.type,
    'type': switch (flag.type) {
      'tab-switch' => 'TAB_SWITCH',
      'paste-attempt' => 'PASTE',
      _ => flag.type.toUpperCase(),
    },
    'message': flag.message,
    'points': flag.points,
  });

  @override
  void submit(
    String examId, {
    required String studentId,
    required String studentName,
    required Map<String, Object> answers,
    required int totalFlagPoints,
  }) {
    if (_socket?.connected != true || examId != _examId) return;
    _socket!.emit('exam:submit', {
      'examId': examId,
      'studentId': studentId,
      'studentName': studentName,
      'answers': answers,
      'totalFlagPoints': totalFlagPoints,
    });
  }

  @override
  void dispose() {
    _beat?.cancel();
    _socket?.dispose();
    _events.close();
  }
}

final examLiveProvider = Provider.autoDispose<ExamLive>((ref) {
  final sessions = ref.watch(sessionHolderProvider);
  final live = SocketExamLive(() => sessions.current?.accessToken ?? '');
  ref.onDispose(live.dispose);
  return live;
});
