import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

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

/// On web, location permission is handled by the browser.
Future<bool> ensureLocationPermission() async {
  return true;
}

/// On web, there's no cached last-known position API.
Future<GeoPosition?> getLastKnownPosition() async {
  return null;
}

Future<GeoPosition> getCurrentPosition({
  bool enableHighAccuracy = true,
  int timeout = 10000,
  int maximumAge = 0,
}) async {
  final completer = Completer<GeoPosition>();
  web.window.navigator.geolocation.getCurrentPosition(
    ((web.GeolocationPosition position) {
      completer.complete(GeoPosition(
        latitude: position.coords.latitude.toDouble(),
        longitude: position.coords.longitude.toDouble(),
        accuracy: position.coords.accuracy.toDouble(),
      ));
    }).toJS,
    ((web.GeolocationPositionError error) {
      String msg;
      switch (error.code) {
        case 1:
          msg = 'Permission denied';
          break;
        case 2:
          msg = 'Position unavailable';
          break;
        case 3:
          msg = 'Timeout';
          break;
        default:
          msg = error.message;
      }
      completer.completeError(GeoError(error.code, msg));
    }).toJS,
    web.PositionOptions(
      enableHighAccuracy: enableHighAccuracy,
      timeout: timeout,
      maximumAge: maximumAge,
    ),
  );
  return completer.future;
}
