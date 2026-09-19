import 'dart:math' as math;

import '../models/attendance.dart';
import '../models/device.dart';

/// Bán kính (m) để gán GPS vào chi nhánh gần nhất.
const double kNearbyBranchMeters = 350;

/// Nhãn nơi chấm trong ngày: GPS / vị trí máy / tên máy, ưu tiên tên chi nhánh.
String punchLocationsForDay({
  required Iterable<Attendance> punches,
  required List<Device> devices,
  List<Map<String, dynamic>>? branches,
}) {
  final devicesById = <String, Device>{
    for (final d in devices)
      if (d.id.isNotEmpty) d.id: d,
  };
  final branchNames = <String>[];
  final seen = <String>{};
  for (final b in branches ?? const <Map<String, dynamic>>[]) {
    final n = b['name']?.toString().trim() ?? '';
    if (n.isNotEmpty && seen.add(n.toLowerCase())) branchNames.add(n);
  }

  final labels = <String>[];
  final labelSeen = <String>{};
  for (final att in punches) {
    final label = punchLocationForAttendance(
      att: att,
      devicesById: devicesById,
      branchNames: branchNames,
      branches: branches,
    );
    if (label.isEmpty) continue;
    final key = label.toLowerCase();
    if (labelSeen.add(key)) labels.add(label);
  }
  return labels.join(' · ');
}

String punchLocationForAttendance({
  required Attendance att,
  required Map<String, Device> devicesById,
  List<String> branchNames = const [],
  List<Map<String, dynamic>>? branches,
}) {
  final device = (att.deviceId != null && att.deviceId!.isNotEmpty)
      ? devicesById[att.deviceId]
      : null;
  final candidates = <String>[];
  void add(String? raw) {
    final t = raw?.trim() ?? '';
    if (t.isEmpty) return;
    if (candidates.any((c) => c.toLowerCase() == t.toLowerCase())) return;
    candidates.add(t);
  }

  add(att.locationName);
  add(device?.location);
  add(att.deviceName);

  for (final name in branchNames) {
    final bl = name.trim();
    if (bl.isEmpty) continue;
    final blLower = bl.toLowerCase();
    for (final c in candidates) {
      final cl = c.toLowerCase();
      if (cl == blLower || cl.contains(blLower) || blLower.contains(cl)) {
        return bl;
      }
    }
  }

  if (att.hasGpsLocation && branches != null && branches.isNotEmpty) {
    final nearest = nearestBranchName(
      lat: att.latitude!,
      lng: att.longitude!,
      branches: branches,
    );
    if (nearest != null && nearest.isNotEmpty) return nearest;
  }

  return candidates.isEmpty ? '' : candidates.first;
}

String? nearestBranchName({
  required double lat,
  required double lng,
  required List<Map<String, dynamic>> branches,
  double maxMeters = kNearbyBranchMeters,
}) {
  String? best;
  var bestM = maxMeters;
  for (final b in branches) {
    final name = b['name']?.toString().trim() ?? '';
    final blat = _toDouble(b['latitude']);
    final blng = _toDouble(b['longitude']);
    if (name.isEmpty || blat == null || blng == null) continue;
    if (blat.abs() < 1e-5 && blng.abs() < 1e-5) continue;
    final d = _haversineMeters(lat, lng, blat, blng);
    if (d < bestM) {
      bestM = d;
      best = name;
    }
  }
  return best;
}

bool punchLocationDiffersFromAssigned(String punchLocation, String assignedBranch) {
  final p = punchLocation.trim();
  final a = assignedBranch.trim();
  if (p.isEmpty || a.isEmpty) return false;
  final pl = p.toLowerCase();
  final al = a.toLowerCase();
  return pl != al && !pl.contains(al) && !al.contains(pl);
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().trim());
}

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  final p1 = lat1 * math.pi / 180;
  final p2 = lat2 * math.pi / 180;
  final dp = (lat2 - lat1) * math.pi / 180;
  final dl = (lon2 - lon1) * math.pi / 180;
  final a = math.sin(dp / 2) * math.sin(dp / 2) +
      math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
  return 2 * r * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}
