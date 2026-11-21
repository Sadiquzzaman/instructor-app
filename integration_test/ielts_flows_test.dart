import 'package:integration_test/integration_test.dart';

import '../test/flows/ielts_flows.dart';

/// The IELTS flows on a real device or emulator, against the
/// in-process fake API. Run: `flutter test integration_test -d <device>`
/// (it reinstalls the app: use a device with no session you need).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ieltsFlows();
}
