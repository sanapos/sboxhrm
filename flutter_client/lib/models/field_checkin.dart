/// Models cho chức năng Check-in điểm bán (Field Check-in) + Journey Tracking

import 'dart:convert';

class JourneyTracking {
  final String id;
  final DateTime journeyDate;
  final DateTime? startTime;
  final DateTime? endTime;
  final String status; // not_started, in_progress, paused, completed, reviewed
  final double totalDistanceKm;
  final int totalTravelMinutes;
  final int totalOnSiteMinutes;
  final int checkedInCount;
  final int assignedCount;
  final List<RoutePoint> routePoints;
  final String? note;
  final String? employeeId;
  final String? employeeName;

  JourneyTracking({
    required this.id,
    required this.journeyDate,
    this.startTime,
    this.endTime,
    this.status = 'not_started',
    this.totalDistanceKm = 0,
    this.totalTravelMinutes = 0,
    this.totalOnSiteMinutes = 0,
    this.checkedInCount = 0,
    this.assignedCount = 0,
    this.routePoints = const [],
    this.note,
    this.employeeId,
    this.employeeName,
  });

  factory JourneyTracking.fromJson(Map<String, dynamic> json) {
    List<RoutePoint> parseRoutePoints(dynamic rp) {
      if (rp == null) return [];
      if (rp is String) {
        try {
          final list = jsonDecode(rp) as List;
          return list.map((e) => RoutePoint.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {
          return [];
        }
      }
      if (rp is List) return rp.map((e) => RoutePoint.fromJson(e as Map<String, dynamic>)).toList();
      return [];
    }

    return JourneyTracking(
      id: json['id'] ?? '',
      journeyDate: DateTime.tryParse(json['journeyDate'] ?? '') ?? DateTime.now(),
      startTime: json['startTime'] != null ? DateTime.tryParse(json['startTime']) : null,
      endTime: json['endTime'] != null ? DateTime.tryParse(json['endTime']) : null,
      status: json['status'] ?? 'not_started',
      totalDistanceKm: (json['totalDistanceKm'] as num?)?.toDouble() ?? 0,
      totalTravelMinutes: json['totalTravelMinutes'] ?? 0,
      totalOnSiteMinutes: json['totalOnSiteMinutes'] ?? 0,
      checkedInCount: json['checkedInCount'] ?? 0,
      assignedCount: json['assignedCount'] ?? 0,
      routePoints: parseRoutePoints(json['routePoints']),
      note: json['note'],
      employeeId: json['employeeId'],
      employeeName: json['employeeName'],
    );
  }

  bool get isActive => status == 'in_progress';
  bool get isCompleted => status == 'completed' || status == 'reviewed';
  bool get isNotStarted => status == 'not_started';

  String get durationFormatted {
    if (startTime == null) return '--';
    final end = endTime ?? DateTime.now();
    final mins = end.difference(startTime!).inMinutes;
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0) return '${h}h${m > 0 ? '${m}p' : ''}';
    return '${m}p';
  }

  String get distanceFormatted {
    if (totalDistanceKm < 1) return '${(totalDistanceKm * 1000).toStringAsFixed(0)}m';
    return '${totalDistanceKm.toStringAsFixed(1)}km';
  }

  double get completionRate => assignedCount > 0 ? checkedInCount / assignedCount : 0;
}

class RoutePoint {
  final double lat;
  final double lng;
  final DateTime time;
  final double? speed;
  final int? dwellMinutes;
  final String? nearLocationName;

  RoutePoint({required this.lat, required this.lng, required this.time, this.speed, this.dwellMinutes, this.nearLocationName});

  factory RoutePoint.fromJson(Map<String, dynamic> json) {
    return RoutePoint(
      lat: (json['lat'] ?? json['Lat'] as num?)?.toDouble() ?? 0,
      lng: (json['lng'] ?? json['Lng'] as num?)?.toDouble() ?? 0,
      time: DateTime.tryParse(json['time'] ?? json['Time'] ?? '') ?? DateTime.now(),
      speed: ((json['speed'] ?? json['Speed']) as num?)?.toDouble(),
      dwellMinutes: json['dwellMinutes'] ?? json['DwellMinutes'],
      nearLocationName: json['nearLocationName'] ?? json['NearLocationName'],
    );
  }

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'time': time.toIso8601String(),
    if (speed != null) 'speed': speed,
  };

  bool get isDwell => (dwellMinutes ?? 0) >= 2;
}

class FieldLocationAssignment {
  final String id;
  final String employeeId;
  final String employeeName;
  final String locationId;
  final AssignedLocation? location;
  final int? dayOfWeek;
  final int sortOrder;
  final String? note;
  final bool isActive;

  FieldLocationAssignment({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.locationId,
    this.location,
    this.dayOfWeek,
    this.sortOrder = 1,
    this.note,
    this.isActive = true,
  });

  factory FieldLocationAssignment.fromJson(Map<String, dynamic> json) {
    return FieldLocationAssignment(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      locationId: json['locationId'] ?? '',
      location: json['location'] != null
          ? AssignedLocation.fromJson(json['location'])
          : null,
      dayOfWeek: json['dayOfWeek'],
      sortOrder: json['sortOrder'] ?? 1,
      note: json['note'],
      isActive: json['isActive'] ?? true,
    );
  }

  String get dayOfWeekLabel {
    switch (dayOfWeek) {
      case 1: return 'Thứ 2';
      case 2: return 'Thứ 3';
      case 3: return 'Thứ 4';
      case 4: return 'Thứ 5';
      case 5: return 'Thứ 6';
      case 6: return 'Thứ 7';
      case 7: return 'Chủ nhật';
      default: return 'Tất cả';
    }
  }
}

class AssignedLocation {
  final String name;
  final String? address;
  final double latitude;
  final double longitude;
  final int radius;

  AssignedLocation({
    required this.name,
    this.address,
    required this.latitude,
    required this.longitude,
    this.radius = 100,
  });

  factory AssignedLocation.fromJson(Map<String, dynamic> json) {
    return AssignedLocation(
      name: json['name'] ?? '',
      address: json['address'],
      latitude: (json['latitude'] ?? 0).toDouble(),
      longitude: (json['longitude'] ?? 0).toDouble(),
      radius: json['radius'] ?? 100,
    );
  }
}

class FieldLocation {
  final String id;
  final String name;
  final String? address;
  final String? contactName;
  final String? contactPhone;
  final String? contactEmail;
  final String? note;
  final double latitude;
  final double longitude;
  final double radius;
  final List<String> photos;
  final String? category;
  final String? registeredBy;
  final bool isApproved;
  final bool isActive;
  final DateTime? createdAt;

  FieldLocation({
    required this.id,
    required this.name,
    this.address,
    this.contactName,
    this.contactPhone,
    this.contactEmail,
    this.note,
    required this.latitude,
    required this.longitude,
    this.radius = 200,
    this.photos = const [],
    this.category,
    this.registeredBy,
    this.isApproved = true,
    this.isActive = true,
    this.createdAt,
  });

  factory FieldLocation.fromJson(Map<String, dynamic> json) {
    List<String> parsePhotos(dynamic p) {
      if (p == null) return [];
      if (p is List) return p.map((e) => e.toString()).toList();
      return [];
    }

    return FieldLocation(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      address: json['address'],
      contactName: json['contactName'],
      contactPhone: json['contactPhone'],
      contactEmail: json['contactEmail'],
      note: json['note'],
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      radius: (json['radius'] as num?)?.toDouble() ?? 200,
      photos: parsePhotos(json['photos']),
      category: json['category'],
      registeredBy: json['registeredBy'],
      isApproved: json['isApproved'] ?? true,
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (address != null) 'address': address,
    if (contactName != null) 'contactName': contactName,
    if (contactPhone != null) 'contactPhone': contactPhone,
    if (contactEmail != null) 'contactEmail': contactEmail,
    if (note != null) 'note': note,
    'latitude': latitude,
    'longitude': longitude,
    'radius': radius,
    if (category != null) 'category': category,
  };
}

class VisitReport {
  final String id;
  final String? employeeId;
  final String? employeeName;
  final String locationId;
  final String? locationName;
  final DateTime visitDate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final int? timeSpentMinutes;
  final double? checkInDistance;
  final double? checkOutDistance;
  final double? checkInLatitude;
  final double? checkInLongitude;
  final List<String> photos;
  final String? reportNote;
  final Map<String, dynamic>? reportData;
  final String status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final String? journeyId;
  final bool outsideRadius;

  VisitReport({
    required this.id,
    this.employeeId,
    this.employeeName,
    required this.locationId,
    this.locationName,
    required this.visitDate,
    this.checkInTime,
    this.checkOutTime,
    this.timeSpentMinutes,
    this.checkInDistance,
    this.checkOutDistance,
    this.checkInLatitude,
    this.checkInLongitude,
    this.photos = const [],
    this.reportNote,
    this.reportData,
    this.status = 'draft',
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.journeyId,
    this.outsideRadius = false,
  });

  factory VisitReport.fromJson(Map<String, dynamic> json) {
    List<String> parsePhotos(dynamic p) {
      if (p == null) return [];
      if (p is List) return p.map((e) => e.toString()).toList();
      return [];
    }

    return VisitReport(
      id: json['id'] ?? '',
      employeeId: json['employeeId'],
      employeeName: json['employeeName'],
      locationId: json['locationId'] ?? '',
      locationName: json['locationName'],
      visitDate: DateTime.tryParse(json['visitDate'] ?? '') ?? DateTime.now(),
      checkInTime: json['checkInTime'] != null
          ? DateTime.tryParse(json['checkInTime'])
          : null,
      checkOutTime: json['checkOutTime'] != null
          ? DateTime.tryParse(json['checkOutTime'])
          : null,
      timeSpentMinutes: json['timeSpentMinutes'],
      checkInDistance: (json['checkInDistance'] as num?)?.toDouble(),
      checkOutDistance: (json['checkOutDistance'] as num?)?.toDouble(),
      checkInLatitude: (json['checkInLatitude'] as num?)?.toDouble(),
      checkInLongitude: (json['checkInLongitude'] as num?)?.toDouble(),
      photos: parsePhotos(json['photos']),
      reportNote: json['reportNote'],
      reportData: json['reportData'] is Map<String, dynamic>
          ? json['reportData']
          : null,
      status: json['status'] ?? 'draft',
      reviewedBy: json['reviewedBy'],
      reviewedAt: json['reviewedAt'] != null
          ? DateTime.tryParse(json['reviewedAt'])
          : null,
      reviewNote: json['reviewNote'],
      journeyId: json['journeyId'],
      outsideRadius: json['outsideRadius'] ?? false,
    );
  }

  bool get isCheckedIn => status == 'checked_in';
  bool get isCheckedOut => status == 'checked_out' || status == 'submitted' || status == 'reviewed';
  bool get isReviewed => status == 'reviewed';

  String get statusLabel {
    switch (status) {
      case 'checked_in': return 'Đang ở điểm';
      case 'checked_out': return 'Đã rời điểm';
      case 'submitted': return 'Đã gửi báo cáo';
      case 'reviewed': return 'Đã duyệt';
      default: return 'Nháp';
    }
  }

  String get timeSpentFormatted {
    if (timeSpentMinutes == null) return '--';
    final hours = timeSpentMinutes! ~/ 60;
    final mins = timeSpentMinutes! % 60;
    if (hours > 0) return '${hours}h${mins > 0 ? '${mins}p' : ''}';
    return '${mins}p';
  }
}
