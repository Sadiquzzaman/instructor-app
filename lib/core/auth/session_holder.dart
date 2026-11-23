import 'package:flutter/foundation.dart';

import 'package:instructor_app/core/auth/session.dart';
import 'package:instructor_app/core/auth/session_store.dart';

/// The current session in memory, written through to [SessionStore].
///
/// The API client reads it synchronously for every request; the UI listens to
/// it (it is a [ValueListenable]). Signing out or a failed refresh sets it to
/// null, which is the app's cue to go to the login screen.
class SessionHolder extends ValueNotifier<Session?> {
  SessionHolder(this._store) : super(null);

  final SessionStore _store;

  Session? get current => value;

  /// Reads the stored session at start-up.
  Future<Session?> restore() async => value = await _store.read();

  /// Stores [session] first, then makes it current, so a new refresh token
  /// is never lost if the app is killed right after a refresh.
  Future<void> save(Session session) async {
    await _store.write(session);
    value = session;
  }

  Future<void> clear() async {
    value = null;
    await _store.clear();
  }
}
