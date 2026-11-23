import 'package:integration_test/integration_test.dart';

import '../test/flows/owner_flows.dart';

/// The owner flows on a real device or emulator, against the in-process
/// fake API. Run: `flutter test integration_test -d <device>` (it
/// reinstalls the app: use a device with no session you need).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  ownerFlows();
}
