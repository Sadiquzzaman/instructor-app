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
import 'package:instructor_app/features/account/screens/account_screen.dart';
import 'package:instructor_app/features/attendance/screens/my_attendance_screen.dart';
import 'package:instructor_app/features/calendar/screens/calendar_screen.dart';
import 'package:instructor_app/features/classes/screens/classes_screen.dart';
import 'package:instructor_app/features/homework/screens/homework_detail_screen.dart';
import 'package:instructor_app/features/homework/screens/homework_list_screen.dart';
import 'package:instructor_app/features/leave/screens/leave_screen.dart';
import 'package:instructor_app/features/routine/screens/routine_screen.dart';
import 'package:instructor_app/features/notifications/screens/inbox_screen.dart';
import 'package:instructor_app/features/plan/screens/more_features_screen.dart';
import 'package:instructor_app/features/shell/menu/menu_items.g.dart';
import 'package:instructor_app/features/shell/screens/app_shell.dart';
import 'package:instructor_app/features/today/screens/today_screen.dart';
import 'package:instructor_app/features/shell/screens/not_yet_screen.dart';
import 'package:instructor_app/features/workspace/screens/workspace_gate.dart';

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
      // Everything signed in: the workspace picker first when needed, then
      // the shell (menu, switcher) around the page.
      ShellRoute(
        builder: (context, state, child) => WorkspaceGate(
          child: AppShell(currentRoute: state.matchedLocation, child: child),
        ),
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) => const TodayScreen(),
          ),
          // Today is home; the web's /today link opens it.
          GoRoute(
            path: AppRoutes.today,
            redirect: (context, state) => AppRoutes.home,
          ),
          GoRoute(
            path: AppRoutes.notifications,
            builder: (context, state) => const InboxScreen(),
          ),
          GoRoute(
            path: AppRoutes.myAttendance,
            builder: (context, state) => const MyAttendanceScreen(),
          ),
          GoRoute(
            path: AppRoutes.leave,
            builder: (context, state) => const LeaveScreen(),
          ),
          GoRoute(
            path: AppRoutes.routine,
            builder: (context, state) => const RoutineScreen(),
          ),
          GoRoute(
            path: AppRoutes.homework,
            builder: (context, state) => const HomeworkListScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    HomeworkDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.classes,
            builder: (context, state) => const ClassesScreen(),
            routes: [
              GoRoute(
                // The web's address for a class.
                path: 'details/:id',
                builder: (context, state) =>
                    ClassDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.calendar,
            builder: (context, state) => const CalendarScreen(),
          ),
          GoRoute(
            path: AppRoutes.account,
            builder: (context, state) => const AccountScreen(),
          ),
          GoRoute(
            path: AppRoutes.features,
            builder: (context, state) => const MoreFeaturesScreen(),
          ),
          // Every page of the web's menu: "use the website for now" until its
          // stage builds it.
          for (final item in appMenuPages)
            GoRoute(
              path: item.route,
              builder: (context, state) => NotYetScreen(item: item),
            ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

/// One page per route of the web's menu, without the web-only Admin pages.
final appMenuPages = [
  for (final (index, item) in webMenu.indexed)
    if (item.category != 'Admin' &&
        !AppRoutes.built.contains(item.route) &&
        webMenu.indexWhere((i) => i.route == item.route) == index)
      item,
];
