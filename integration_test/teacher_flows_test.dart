import 'package:integration_test/integration_test.dart';

import '../test/flows/teacher_flows.dart';

/// The teacher flows on a real device or emulator, against the in-process
/// fake API. Run: `flutter test integration_test -d <device>`.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  teacherFlows();
}
