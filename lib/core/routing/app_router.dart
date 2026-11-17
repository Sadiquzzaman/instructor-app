import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:instructor_app/core/api/api_providers.dart';
import 'package:instructor_app/core/routing/app_routes.dart';
import 'package:instructor_app/features/auth/data/signup_repository.dart';
import 'package:instructor_app/features/auth/screens/forgot_password_screen.dart';
import 'package:instructor_app/features/auth/screens/login_screen.dart';
import 'package:instructor_app/features/auth/screens/signup_choice_screen.dart';
import 'package:instructor_app/features/auth/screens/signup_form_screen.dart';
import 'package:instructor_app/features/auth/screens/verify_code_screen.dart';
import 'package:instructor_app/features/shell/screens/placeholder_home.dart';

export 'package:instructor_app/core/routing/app_routes.dart';

/// The app's routes. One redirect decides where a person may be:
/// signed out → only the signed-out screens (login, sign-up, forgot
/// password); signed in on one of those → home. It re-runs whenever the
/// session changes (sign-in, sign-out, a refused refresh). The version gate
/// sits above the router (app.dart).
final routerProvider = Provider<GoRouter>((ref) {
  final sessions = ref.watch(sessionHolderProvider);
  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: sessions,
    redirect: (context, state) {
      final signedIn = sessions.current != null;
      final signedOutScreen = AppRoutes.isSignedOutOnly(state.matchedLocation);
      if (!signedIn) return signedOutScreen ? null : AppRoutes.login;
      if (signedOutScreen) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        builder: (context, state) => const SignUpChoiceScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUpStudent,
        builder: (context, state) =>
            const SignUpFormScreen(kind: SignUpKind.student),
      ),
      GoRoute(
        path: AppRoutes.signUpTeacher,
        builder: (context, state) =>
            const SignUpFormScreen(kind: SignUpKind.teacher),
      ),
      GoRoute(
        path: AppRoutes.signUpOrganization,
        builder: (context, state) =>
            const SignUpFormScreen(kind: SignUpKind.organization),
      ),
      GoRoute(
        path: AppRoutes.signUpVerify,
        // Reached only from a sign-up form, which passes what was sent.
        redirect: (context, state) =>
            state.extra is PendingSignUp ? null : AppRoutes.signUp,
        builder: (context, state) =>
            VerifyCodeScreen(pending: state.extra! as PendingSignUp),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
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
