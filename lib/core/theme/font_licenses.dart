import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Adds the bundled fonts' SIL Open Font Licences to Flutter's licence list,
/// as the licence requires when the fonts are shipped.
void registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (packages, asset) in const [
      (['Instrument Sans'], 'assets/fonts/InstrumentSans-OFL.txt'),
      (['Hind Siliguri'], 'assets/fonts/HindSiliguri-OFL.txt'),
    ]) {
      yield LicenseEntryWithLineBreaks(
        packages,
        await rootBundle.loadString(asset),
      );
    }
  });
}
