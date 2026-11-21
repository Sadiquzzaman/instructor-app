/// Route paths, named like the web's pages so deep links can map later.
abstract final class AppRoutes {
  static const home = '/';
  static const login = '/login';
  static const signUp = '/signup';
  static const signUpStudent = '/signup/student';
  static const signUpTeacher = '/signup/teacher';
  static const signUpOrganization = '/signup/organization';
  static const signUpVerify = '/signup/verify';
  static const forgotPassword = '/forgot-password';
  static const notifications = '/notifications';
  static const account = '/account';
  static const features = '/features';
  static const today = '/today';
  static const dashboard = '/dashboard';
  static const myAttendance = '/my-attendance';
  static const attendance = '/attendance';
  static const attendanceReports = '/attendance-reports';
  static const attendanceRegister = '/attendance-register';
  static const leave = '/leave';
  static const routine = '/routine';
  static const homework = '/homework';
  static const classes = '/classes';
  static const tests = '/tests';
  static const grading = '/grading';
  static const marks = '/marks';
  static const behaviour = '/behaviour';
  static const performance = '/performance';
  static const reportCards = '/report-cards';
  static const resources = '/resources';
  static const chat = '/chat';
  static const calendar = '/calendar';
  static const organization = '/organization';
  static const orgTeachers = '/organization/teachers';
  static const orgSetup = '/organization/setup';
  static const orgAssistants = '/organization/assistants';
  static const orgStudents = '/organization/students';
  static const orgSubjects = '/organization/subjects';
  static const orgClasses = '/organization/classes';
  static const orgAssignments = '/organization/assignments';
  static const sessions = '/sessions';
  static const attendanceSettings = '/attendance-settings';
  static const holidays = '/holidays';
  static const attendanceBranches = '/attendance-branches';
  static const attendanceSetup = '/attendance-setup';
  static const homeworkSettings = '/homework-settings';
  static const plagiarismSettings = '/plagiarism-settings';
  static const performanceSettings = '/performance-settings';
  static const gradingScale = '/grading-scale';
  static const chatAdmin = '/chat-admin';
  static const activityLog = '/activity-log';
  static const messageLog = '/message-log';
  static const billing = '/billing';
  static const ieltsOverview = '/ielts/overview';
  static const ieltsCourses = '/ielts/courses';
  static const ieltsMyCourses = '/ielts/my-courses';
  static const ieltsStudents = '/ielts/students';
  static const ieltsMe = '/ielts/me';
  static const ieltsTests = '/ielts/tests';
  static const ieltsBandTables = '/ielts/band-tables';
  static const ieltsMy = '/ielts/my';
  static const ieltsMarking = '/ielts/marking';

  /// Pages the app has really built (not "use the website for now"). A
  /// notification's link opens in the app only for these; each stage adds
  /// its pages here.
  static const built = {
    home,
    ieltsOverview,
    ieltsCourses,
    ieltsMyCourses,
    ieltsStudents,
    ieltsMe,
    ieltsTests,
    ieltsBandTables,
    ieltsMy,
    ieltsMarking,
    today,
    dashboard,
    myAttendance,
    attendance,
    attendanceReports,
    attendanceRegister,
    leave,
    routine,
    homework,
    classes,
    calendar,
    tests,
    grading,
    marks,
    behaviour,
    organization,
    orgTeachers,
    orgSetup,
    orgAssistants,
    orgStudents,
    orgSubjects,
    orgClasses,
    orgAssignments,
    sessions,
    attendanceSettings,
    holidays,
    attendanceBranches,
    attendanceSetup,
    homeworkSettings,
    plagiarismSettings,
    performanceSettings,
    gradingScale,
    chatAdmin,
    activityLog,
    messageLog,
    billing,
    performance,
    reportCards,
    resources,
    chat,
    notifications,
    account,
    features,
  };

  /// Built pages with an id at the end, as the web names them.
  static const builtWithId = {
    '/homework/',
    '/classes/details/',
    '/grading/details/',
    '/tests/create',
    '/marks/',
    '/performance/students/',
  };

  static bool isAppPage(String link) {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.hasScheme) return false;
    if (built.contains(uri.path)) return true;
    return builtWithId.any(
      (p) =>
          uri.path.startsWith(p) &&
          uri.path.length > p.length &&
          !uri.path.substring(p.length).contains('/'),
    );
  }

  /// The page home shows for an account [role]: the dashboard for teachers
  /// (as the web), Today for everyone else.
  static String homePage(String? role) => role == 'TEACHER' ? dashboard : today;

  /// Screens for people who are not signed in.
  static bool isSignedOutOnly(String location) =>
      location == login ||
      location == forgotPassword ||
      location == signUp ||
      location.startsWith('$signUp/');
}
