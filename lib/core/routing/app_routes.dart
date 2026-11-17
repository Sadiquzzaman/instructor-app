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
  static const myAttendance = '/my-attendance';
  static const leave = '/leave';
  static const routine = '/routine';
  static const homework = '/homework';
  static const calendar = '/calendar';
  static const organization = '/organization';

  /// Pages the app has really built (not "use the website for now"). A
  /// notification's link opens in the app only for these; each stage adds
  /// its pages here.
  static const built = {home, today, notifications, account, features};

  static bool isAppPage(String link) {
    final uri = Uri.tryParse(link);
    return uri != null && !uri.hasScheme && built.contains(uri.path);
  }

  /// Screens for people who are not signed in.
  static bool isSignedOutOnly(String location) =>
      location == login ||
      location == forgotPassword ||
      location == signUp ||
      location.startsWith('$signUp/');
}
