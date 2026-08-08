import 'package:geolocator/geolocator.dart';

/// A location fix, or a plain-language reason there isn't one.
class LocationResult {
  const LocationResult.success(this.position) : reason = null;
  const LocationResult.failure(this.reason) : position = null;

  final Position? position;
  final String? reason;

  bool get ok => position != null;
}

/// Wraps geolocator so the attendance flow deals with one result type instead
/// of four different permission enums.
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  Future<LocationResult> currentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const LocationResult.failure(
        'Location is switched off. Turn it on to check in.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      return const LocationResult.failure(
        'Location permission is needed to record where you checked in.',
      );
    }
    if (permission == LocationPermission.deniedForever) {
      // Android will not show the dialog again; only Settings can undo this.
      return const LocationResult.failure(
        'Location permission is permanently denied. Enable it in Settings > '
        'Apps > Offixia > Permissions.',
      );
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      return LocationResult.success(position);
    } catch (e) {
      return LocationResult.failure(
        'Could not get a location fix: ${e.toString().split('\n').first}',
      );
    }
  }

  double metresBetween({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) => Geolocator.distanceBetween(fromLat, fromLng, toLat, toLng);
}
