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
import 'package:instructor_app/features/chat/screens/chat_screens.dart';
import 'package:instructor_app/features/classes/screens/classes_screen.dart';
import 'package:instructor_app/features/homework/screens/homework_detail_screen.dart';
import 'package:instructor_app/features/homework/screens/homework_list_screen.dart';
import 'package:instructor_app/features/homework/screens/plagiarism_screens.dart';
import 'package:instructor_app/features/leave/screens/leave_screen.dart';
import 'package:instructor_app/features/resources/resources_screen.dart';
import 'package:instructor_app/features/results/screens/results_screens.dart';
import 'package:instructor_app/features/routine/screens/routine_screen.dart';
import 'package:instructor_app/features/notifications/screens/inbox_screen.dart';
import 'package:instructor_app/features/plan/screens/more_features_screen.dart';
import 'package:instructor_app/features/shell/menu/menu_items.g.dart';
import 'package:instructor_app/features/shell/screens/app_shell.dart';
import 'package:instructor_app/features/tests/screens/take_test_screen.dart';
import 'package:instructor_app/features/tests/screens/test_result_screen.dart';
import 'package:instructor_app/features/organization/screens/assignments_screen.dart';
import 'package:instructor_app/features/organization/screens/attendance_settings_screen.dart';
import 'package:instructor_app/features/organization/screens/branches_screen.dart';
import 'package:instructor_app/features/organization/screens/chat_review_screen.dart';
import 'package:instructor_app/features/organization/screens/class_setup_screen.dart';
import 'package:instructor_app/features/organization/screens/logs_screens.dart';
import 'package:instructor_app/features/plan/screens/plan_usage_screen.dart';
import 'package:instructor_app/features/organization/screens/holidays_screen.dart';
import 'package:instructor_app/features/organization/screens/organization_overview_screen.dart';
import 'package:instructor_app/features/organization/screens/people_screen.dart';
import 'package:instructor_app/features/organization/screens/perf_grading_screens.dart';
import 'package:instructor_app/features/organization/screens/sessions_screen.dart';
import 'package:instructor_app/features/organization/screens/setup_wizard_screen.dart';
import 'package:instructor_app/features/organization/screens/settings_forms_screens.dart';
import 'package:instructor_app/features/organization/screens/subjects_classes_screens.dart';
import 'package:instructor_app/features/results/screens/behaviour_screen.dart';
import 'package:instructor_app/features/results/screens/paper_exam_screens.dart';
import 'package:instructor_app/features/tests/screens/grading_screens.dart';
import 'package:instructor_app/features/tests/screens/integrity_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_builder_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_courses_screens.dart';
import 'package:instructor_app/features/ielts/screens/ielts_openings_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_overview_screen.dart';
import 'package:instructor_app/features/ielts/screens/ielts_students_screens.dart';
import 'package:instructor_app/features/ielts/screens/ielts_tests_screens.dart';
import 'package:instructor_app/features/tests/screens/create_test_screen.dart';
import 'package:instructor_app/features/tests/screens/edit_test_screen.dart';
import 'package:instructor_app/features/tests/screens/monitor_screen.dart';
import 'package:instructor_app/features/tests/screens/teacher_tests_screens.dart';
import 'package:instructor_app/features/tests/screens/tests_screen.dart';
import 'package:instructor_app/features/today/screens/today_screen.dart';
import 'package:instructor_app/features/dashboard/screens/teacher_dashboard_screen.dart';
import 'package:instructor_app/features/attendance/screens/class_attendance_screen.dart';
import 'package:instructor_app/features/attendance/screens/attendance_reports_screen.dart';
import 'package:instructor_app/features/attendance/screens/paper_register_screen.dart';
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
      // Taking a test: the whole screen, outside the shell's menu.
      GoRoute(
        path: '${AppRoutes.tests}/:id/take',
        builder: (context, state) =>
            TakeTestScreen(id: state.pathParameters['id']!),
      ),
      // Everything signed in: the workspace picker first when needed, then
      // the shell (menu, switcher) around the page.
      ShellRoute(
        builder: (context, state, child) => WorkspaceGate(
          child: AppShell(
            // Home is Today or, for teachers, the dashboard: its menu item.
            currentRoute: state.matchedLocation == AppRoutes.home
                ? AppRoutes.homePage(sessions.current?.role)
                : state.matchedLocation,
            child: child,
          ),
        ),
        routes: [
          // Home: the dashboard for teachers (as the web), Today for others.
          GoRoute(
            path: AppRoutes.home,
            builder: (context, state) =>
                AppRoutes.homePage(sessions.current?.role) ==
                    AppRoutes.dashboard
                ? const TeacherDashboardScreen()
                : const TodayScreen(),
          ),
          // The web's links to home's own page open home.
          GoRoute(
            path: AppRoutes.today,
            redirect: (context, state) =>
                AppRoutes.homePage(sessions.current?.role) == AppRoutes.today
                ? AppRoutes.home
                : null,
            builder: (context, state) => const TodayScreen(),
          ),
          GoRoute(
            path: AppRoutes.dashboard,
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
            path: AppRoutes.attendance,
            builder: (context, state) => const ClassAttendanceScreen(),
            routes: [
              GoRoute(
                path: ':slotId/:date',
                builder: (context, state) => ClassSessionScreen(
                  slotId: state.pathParameters['slotId']!,
                  date: state.pathParameters['date']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.attendanceReports,
            builder: (context, state) => const AttendanceReportsScreen(),
          ),
          GoRoute(
            path: AppRoutes.attendanceRegister,
            builder: (context, state) => const PaperRegisterScreen(),
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
                routes: [
                  GoRoute(
                    path: 'similarity',
                    builder: (context, state) => SimilarityScreen(
                      homeworkId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/integrity/matches/:id',
            builder: (context, state) =>
                MatchScreen(id: state.pathParameters['id']!),
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
            path: AppRoutes.tests,
            builder: (context, state) => const TestsScreen(),
            routes: [
              // Before ':id', so "create" is not taken for an id.
              GoRoute(
                path: 'create',
                builder: (context, state) => const CreateTestScreen(),
              ),
              // A teacher's test (students open a test to take it, or its
              // result).
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    TeacherTestScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/edit',
                builder: (context, state) =>
                    EditTestScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/monitor',
                builder: (context, state) =>
                    MonitorScreen(examId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/integrity',
                builder: (context, state) =>
                    IntegrityScreen(examId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/results',
                builder: (context, state) =>
                    TestResultScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.grading,
            builder: (context, state) => const GradingListScreen(),
            routes: [
              GoRoute(
                path: 'details/:id',
                builder: (context, state) =>
                    GradingDetailScreen(examId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.behaviour,
            builder: (context, state) => const BehaviourScreen(),
          ),
          GoRoute(
            path: AppRoutes.organization,
            builder: (context, state) => const OrganizationOverviewScreen(),
          ),
          GoRoute(
            path: AppRoutes.orgSetup,
            builder: (context, state) => const SetupWizardScreen(),
          ),
          for (final (path, kind) in [
            (AppRoutes.orgTeachers, PeopleKind.teachers),
            (AppRoutes.orgAssistants, PeopleKind.assistants),
            (AppRoutes.orgStudents, PeopleKind.students),
          ])
            GoRoute(
              path: path,
              builder: (context, state) => PeopleScreen(kind: kind),
            ),
          GoRoute(
            path: AppRoutes.orgSubjects,
            builder: (context, state) => const OrgSubjectsScreen(),
          ),
          GoRoute(
            path: AppRoutes.orgClasses,
            builder: (context, state) => const OrgClassesScreen(),
          ),
          GoRoute(
            path: AppRoutes.orgAssignments,
            builder: (context, state) => const AssignmentsScreen(),
          ),
          GoRoute(
            path: AppRoutes.sessions,
            builder: (context, state) => const SessionsScreen(),
          ),
          GoRoute(
            path: AppRoutes.attendanceSettings,
            builder: (context, state) => const AttendanceSettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.holidays,
            builder: (context, state) => const HolidaysScreen(),
          ),
          GoRoute(
            path: AppRoutes.attendanceBranches,
            builder: (context, state) => const BranchesScreen(),
          ),
          GoRoute(
            path: AppRoutes.attendanceSetup,
            builder: (context, state) => const ClassSetupScreen(),
          ),
          GoRoute(
            path: AppRoutes.homeworkSettings,
            builder: (context, state) => const HomeworkSettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.plagiarismSettings,
            builder: (context, state) => const PlagiarismSettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.performanceSettings,
            builder: (context, state) => const PerformanceSettingsScreen(),
          ),
          GoRoute(
            path: AppRoutes.gradingScale,
            builder: (context, state) => const GradingScaleScreen(),
          ),
          GoRoute(
            path: AppRoutes.chatAdmin,
            builder: (context, state) => const ChatReviewScreen(),
          ),
          GoRoute(
            path: AppRoutes.activityLog,
            builder: (context, state) => const ActivityLogScreen(),
          ),
          GoRoute(
            path: AppRoutes.messageLog,
            builder: (context, state) => const MessageLogScreen(),
          ),
          GoRoute(
            path: AppRoutes.billing,
            builder: (context, state) => const PlanUsageScreen(),
          ),
          GoRoute(
            path: AppRoutes.marks,
            builder: (context, state) => const MarksScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    PaperMarksScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.performance,
            builder: (context, state) => const PerformanceScreen(),
            routes: [
              GoRoute(
                path: 'students/:id',
                builder: (context, state) =>
                    PerformanceScreen(studentId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.reportCards,
            builder: (context, state) => const ReportCardsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    ReportCardScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.resources,
            builder: (context, state) => const ResourcesScreen(),
          ),
          GoRoute(
            path: AppRoutes.chat,
            builder: (context, state) => const ChatScreen(),
          ),
          GoRoute(
            path: AppRoutes.ieltsCourses,
            builder: (context, state) => const IeltsCoursesScreen(),
          ),
          GoRoute(
            path: AppRoutes.ieltsMyCourses,
            builder: (context, state) => const MyIeltsCoursesScreen(),
          ),
          GoRoute(
            path: AppRoutes.ieltsStudents,
            builder: (context, state) => const IeltsStudentsScreen(),
          ),
          GoRoute(
            path: AppRoutes.ieltsMe,
            builder: (context, state) => const MyIeltsProfileScreen(),
          ),
          GoRoute(
            path: AppRoutes.ieltsTests,
            builder: (context, state) => const IeltsTestsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (context, state) =>
                    IeltsBuilderScreen(id: state.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id/openings',
                builder: (context, state) =>
                    IeltsOpeningsScreen(testId: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: AppRoutes.ieltsBandTables,
            builder: (context, state) => const IeltsBandTablesScreen(),
          ),
          GoRoute(
            path: AppRoutes.ieltsOverview,
            builder: (context, state) => const IeltsOverviewScreen(),
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
