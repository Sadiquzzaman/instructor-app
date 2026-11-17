import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

/// Route paths, named like the web's pages so deep links can map later.
abstract final class AppRoutes {
  static const home = '/';
  static const login = '/login';
}

/// The app's routes. One redirect decides where a person may be:
/// signed out → the login screen; signed in on the login screen → home.
/// It re-runs whenever the session changes (sign-in, sign-out, a refused
/// refresh). The version gate sits above the router (app.dart).
final routerProvider = Provider<GoRouter>((ref) {
  final sessions = ref.watch(sessionHolderProvider);
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: sessions,
    redirect: (context, state) {
      final signedIn = sessions.current != null;
      final atLogin = state.matchedLocation == AppRoutes.login;
      if (!signedIn) return atLogin ? null : AppRoutes.login;
      if (atLogin) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const PlaceholderHome(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
