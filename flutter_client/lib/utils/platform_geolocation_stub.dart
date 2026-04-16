import 'package:geolocator/geolocator.dart';

class GeoPosition {
  final double latitude;
  final double longitude;
  final double accuracy;
  GeoPosition({required this.latitude, required this.longitude, required this.accuracy});
}

class GeoError {
  final int code;
  final String message;
  GeoError(this.code, this.message);
  @override
  String toString() => 'GeoError($code): $message';
}

/// Ensure location permission is granted. Call once at startup.
Future<bool> ensureLocationPermission() async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return false;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) return false;
  }
  if (permission == LocationPermission.deniedForever) return false;
  return true;
}

/// Get last known position instantly (cached by OS). May return null.
Future<GeoPosition?> getLastKnownPosition() async {
  try {
    final position = await Geolocator.getLastKnownPosition();
    if (position == null) return null;
    return GeoPosition(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
    );
  } catch (_) {
    return null;
  }
}

Future<GeoPosition> getCurrentPosition({
  bool enableHighAccuracy = true,
  int timeout = 10000,
  int maximumAge = 0,
}) async {
  bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw GeoError(2, 'Location services are disabled');
  }

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw GeoError(1, 'Permission denied');
    }
  }
  if (permission == LocationPermission.deniedForever) {
    throw GeoError(1, 'Permission denied forever');
  }

  final position = await Geolocator.getCurrentPosition(
    locationSettings: LocationSettings(
      accuracy: enableHighAccuracy ? LocationAccuracy.high : LocationAccuracy.medium,
      timeLimit: Duration(milliseconds: timeout),
    ),
  );

  return GeoPosition(
    latitude: position.latitude,
    longitude: position.longitude,
    accuracy: position.accuracy,
  );
}
