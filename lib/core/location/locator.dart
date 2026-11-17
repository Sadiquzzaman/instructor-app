import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// Why there is no position.
enum LocationProblem {
  /// The phone's location is switched off.
  serviceOff,

  /// The person said no; asking again may work.
  denied,

  /// Said no for good; only the phone's settings can change it.
  deniedForever,

  /// No fix in time (indoors, weak signal).
  unavailable,
}

class LocationException implements Exception {
  const LocationException(this.problem);
  final LocationProblem problem;
}

typedef LocationFix = ({double latitude, double longitude, double accuracy});

/// One accurate, fresh position while the app is open (never in the
/// background, never cached), for checking in to an in-person class. A
/// provider so tests can stand in for the phone.
abstract class Locator {
  /// Asks for permission when needed. Throws [LocationException].
  Future<LocationFix> currentFix();

  /// Opens the app's settings (after "denied for good") or the phone's
  /// location settings.
  Future<void> openSettings(LocationProblem problem);
}

class DeviceLocator implements Locator {
  @override
  Future<LocationFix> currentFix() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationException(LocationProblem.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const LocationException(LocationProblem.denied);
      case LocationPermission.deniedForever:
        throw const LocationException(LocationProblem.deniedForever);
      case LocationPermission.whileInUse ||
          LocationPermission.always ||
          LocationPermission.unableToDetermine:
        break;
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return (
        latitude: p.latitude,
        longitude: p.longitude,
        accuracy: p.accuracy,
      );
    } on LocationServiceDisabledException {
      throw const LocationException(LocationProblem.serviceOff);
    } on PermissionDeniedException {
      throw const LocationException(LocationProblem.denied);
    } on Exception {
      throw const LocationException(LocationProblem.unavailable);
    }
  }

  @override
  Future<void> openSettings(LocationProblem problem) async {
    if (problem == LocationProblem.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}

final locatorProvider = Provider<Locator>((ref) => DeviceLocator());
