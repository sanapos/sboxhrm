/// Hồ sơ ngành + khu vực/bàn/phòng + phiên + gói buổi.
library;

enum PosSellProfile {
  retail,
  salon,
  roomHourly,
  restaurant,
  gym;

  static PosSellProfile parse(String? raw) {
    final t = (raw ?? '').trim().toLowerCase();
    switch (t) {
      case 'salon':
      case '1':
        return PosSellProfile.salon;
      case 'roomhourly':
      case '2':
        return PosSellProfile.roomHourly;
      case 'restaurant':
      case '3':
        return PosSellProfile.restaurant;
      case 'gym':
      case '4':
        return PosSellProfile.gym;
      case 'retail':
      case '0':
      default:
        return PosSellProfile.retail;
    }
  }

  String get apiValue => switch (this) {
        PosSellProfile.retail => 'Retail',
        PosSellProfile.salon => 'Salon',
        PosSellProfile.roomHourly => 'RoomHourly',
        PosSellProfile.restaurant => 'Restaurant',
        PosSellProfile.gym => 'Gym',
      };

  String get label => switch (this) {
        PosSellProfile.retail => 'Bán lẻ',
        PosSellProfile.salon => 'Salon / Nail',
        PosSellProfile.roomHourly => 'Bi-a / Karaoke',
        PosSellProfile.restaurant => 'F&B / Nhà hàng',
        PosSellProfile.gym => 'Gym / Fitness',
      };
}

enum PosServiceBillingMode {
  flat,
  perHour,
  perMinute,
  perSession;

  static PosServiceBillingMode parse(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'perhour':
        return PosServiceBillingMode.perHour;
      case 'perminute':
        return PosServiceBillingMode.perMinute;
      case 'persession':
        return PosServiceBillingMode.perSession;
      default:
        return PosServiceBillingMode.flat;
    }
  }

  String get apiValue => switch (this) {
        PosServiceBillingMode.flat => 'Flat',
        PosServiceBillingMode.perHour => 'PerHour',
        PosServiceBillingMode.perMinute => 'PerMinute',
        PosServiceBillingMode.perSession => 'PerSession',
      };

  String get label => switch (this) {
        PosServiceBillingMode.flat => 'Giá cố định',
        PosServiceBillingMode.perHour => 'Theo giờ',
        PosServiceBillingMode.perMinute => 'Theo phút',
        PosServiceBillingMode.perSession => 'Theo buổi',
      };

  bool get isTimed =>
      this == PosServiceBillingMode.perHour ||
      this == PosServiceBillingMode.perMinute;
}

enum PosResourceKind {
  chair,
  table,
  room,
  other;

  static PosResourceKind parse(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'chair':
        return PosResourceKind.chair;
      case 'room':
        return PosResourceKind.room;
      case 'other':
        return PosResourceKind.other;
      default:
        return PosResourceKind.table;
    }
  }

  String get apiValue => switch (this) {
        PosResourceKind.chair => 'Chair',
        PosResourceKind.table => 'Table',
        PosResourceKind.room => 'Room',
        PosResourceKind.other => 'Other',
      };

  String get label => switch (this) {
        PosResourceKind.chair => 'Ghế',
        PosResourceKind.table => 'Bàn',
        PosResourceKind.room => 'Phòng',
        PosResourceKind.other => 'Khác',
      };
}

class PosStoreSellSettingsDto {
  PosStoreSellSettingsDto({
    required this.id,
    required this.sellProfile,
    this.defaultSellMode = 'quick',
    this.enableResources = false,
    this.enableHourlyBilling = false,
    this.enableSessionPacks = false,
    this.requireResourceOnSale = false,
    this.showFloorPlan = false,
    this.allowProvisionalBill = false,
    this.extraJson,
  });

  final String id;
  final PosSellProfile sellProfile;
  final String defaultSellMode;
  final bool enableResources;
  final bool enableHourlyBilling;
  final bool enableSessionPacks;
  final bool requireResourceOnSale;
  final bool showFloorPlan;
  final bool allowProvisionalBill;
  final String? extraJson;

  factory PosStoreSellSettingsDto.fromJson(Map<String, dynamic> json) =>
      PosStoreSellSettingsDto(
        id: (json['id'] ?? json['Id'] ?? '').toString(),
        sellProfile: PosSellProfile.parse(
            (json['sellProfile'] ?? json['SellProfile'])?.toString()),
        defaultSellMode:
            (json['defaultSellMode'] ?? json['DefaultSellMode'] ?? 'quick')
                .toString(),
        enableResources: json['enableResources'] == true ||
            json['EnableResources'] == true,
        enableHourlyBilling: json['enableHourlyBilling'] == true ||
            json['EnableHourlyBilling'] == true,
        enableSessionPacks: json['enableSessionPacks'] == true ||
            json['EnableSessionPacks'] == true,
        requireResourceOnSale: json['requireResourceOnSale'] == true ||
            json['RequireResourceOnSale'] == true,
        showFloorPlan:
            json['showFloorPlan'] == true || json['ShowFloorPlan'] == true,
        allowProvisionalBill: json['allowProvisionalBill'] == true ||
            json['AllowProvisionalBill'] == true,
        extraJson: (json['extraJson'] ?? json['ExtraJson'])?.toString(),
      );

  Map<String, dynamic> toSaveBody({bool applyProfileDefaults = true}) {
    // Luôn gửi đủ cờ + tên ngành (string) để server không phụ thuộc enum-bind.
    return {
      'sellProfile': sellProfile.apiValue,
      'defaultSellMode': defaultSellMode,
      'enableResources': enableResources,
      'enableHourlyBilling': enableHourlyBilling,
      'enableSessionPacks': enableSessionPacks,
      'requireResourceOnSale': requireResourceOnSale,
      'showFloorPlan': showFloorPlan,
      'allowProvisionalBill': allowProvisionalBill,
      if (extraJson != null) 'extraJson': extraJson,
      'applyProfileDefaults': applyProfileDefaults,
    };
  }

  /// Defaults client-side khớp server (UI phản hồi ngay khi đổi ngành).
  PosStoreSellSettingsDto withProfileDefaults(PosSellProfile profile) {
    switch (profile) {
      case PosSellProfile.retail:
        return copyWith(
          sellProfile: profile,
          enableResources: false,
          enableHourlyBilling: false,
          enableSessionPacks: false,
          requireResourceOnSale: false,
          showFloorPlan: false,
          allowProvisionalBill: false,
        );
      case PosSellProfile.salon:
        return copyWith(
          sellProfile: profile,
          enableResources: true,
          enableHourlyBilling: true,
          enableSessionPacks: false,
          requireResourceOnSale: false,
          showFloorPlan: true,
          allowProvisionalBill: true,
        );
      case PosSellProfile.roomHourly:
        return copyWith(
          sellProfile: profile,
          enableResources: true,
          enableHourlyBilling: true,
          enableSessionPacks: false,
          requireResourceOnSale: true,
          showFloorPlan: true,
          allowProvisionalBill: true,
        );
      case PosSellProfile.restaurant:
        return copyWith(
          sellProfile: profile,
          enableResources: true,
          enableHourlyBilling: false,
          enableSessionPacks: false,
          requireResourceOnSale: false,
          showFloorPlan: true,
          allowProvisionalBill: true,
        );
      case PosSellProfile.gym:
        return copyWith(
          sellProfile: profile,
          enableResources: false,
          enableHourlyBilling: false,
          enableSessionPacks: true,
          requireResourceOnSale: false,
          showFloorPlan: false,
          allowProvisionalBill: false,
        );
    }
  }

  PosStoreSellSettingsDto copyWith({
    PosSellProfile? sellProfile,
    String? defaultSellMode,
    bool? enableResources,
    bool? enableHourlyBilling,
    bool? enableSessionPacks,
    bool? requireResourceOnSale,
    bool? showFloorPlan,
    bool? allowProvisionalBill,
    String? extraJson,
  }) =>
      PosStoreSellSettingsDto(
        id: id,
        sellProfile: sellProfile ?? this.sellProfile,
        defaultSellMode: defaultSellMode ?? this.defaultSellMode,
        enableResources: enableResources ?? this.enableResources,
        enableHourlyBilling: enableHourlyBilling ?? this.enableHourlyBilling,
        enableSessionPacks: enableSessionPacks ?? this.enableSessionPacks,
        requireResourceOnSale:
            requireResourceOnSale ?? this.requireResourceOnSale,
        showFloorPlan: showFloorPlan ?? this.showFloorPlan,
        allowProvisionalBill: allowProvisionalBill ?? this.allowProvisionalBill,
        extraJson: extraJson ?? this.extraJson,
      );
}

class PosServiceAreaDto {
  PosServiceAreaDto({
    required this.id,
    required this.name,
    this.code,
    this.sortOrder = 0,
    this.areaType,
    this.isActive = true,
  });

  final String id;
  final String name;
  final String? code;
  final int sortOrder;
  final String? areaType;
  final bool isActive;

  factory PosServiceAreaDto.fromJson(Map<String, dynamic> json) =>
      PosServiceAreaDto(
        id: (json['id'] ?? json['Id'] ?? '').toString(),
        name: (json['name'] ?? json['Name'] ?? '').toString(),
        code: (json['code'] ?? json['Code'])?.toString(),
        sortOrder: (json['sortOrder'] ?? json['SortOrder'] as num?)?.toInt() ?? 0,
        areaType: (json['areaType'] ?? json['AreaType'])?.toString(),
        isActive: json['isActive'] != false && json['IsActive'] != false,
      );
}

class PosServiceResourceDto {
  PosServiceResourceDto({
    required this.id,
    required this.areaId,
    required this.areaName,
    required this.code,
    required this.name,
    required this.resourceKind,
    this.capacity = 1,
    this.sortOrder = 0,
    this.defaultHourlyRate,
    this.isActive = true,
    this.occupancyStatus = 'Free',
    this.openSessionId,
    this.openOrderId,
    this.sessionStartedAt,
    this.elapsedMinutes = 0,
    this.subtotal = 0,
    this.lineCount = 0,
    this.pendingKitchenCount = 0,
    this.guestCount = 0,
    this.billRequested = false,
    this.needsCleaning = false,
    this.orderNo,
    this.layoutX,
    this.layoutY,
    this.layoutW = 120,
    this.layoutH = 100,
    this.reservationId,
    this.reservationCustomerName,
    this.reservationPhone,
    this.reservationGuestCount = 0,
    this.reservationPreOrderCount = 0,
    this.reservationReservedUntil,
    this.lockedByDeviceId,
    this.lockedByDeviceName,
    this.lockedByDisplayName,
    this.lockExpiresAt,
    this.tableSessionOpen = false,
    this.hasParkedBill = false,
  });

  final String id;
  final String areaId;
  final String areaName;
  final String code;
  final String name;
  final PosResourceKind resourceKind;
  final int capacity;
  final int sortOrder;
  final double? defaultHourlyRate;
  final bool isActive;
  final String occupancyStatus;
  final String? openSessionId;
  final String? openOrderId;
  final DateTime? sessionStartedAt;
  final int elapsedMinutes;
  final double subtotal;
  final int lineCount;
  final int pendingKitchenCount;
  final int guestCount;
  final bool billRequested;
  final bool needsCleaning;
  final String? orderNo;
  final double? layoutX;
  final double? layoutY;
  final double layoutW;
  final double layoutH;
  final String? reservationId;
  final String? reservationCustomerName;
  final String? reservationPhone;
  final int reservationGuestCount;
  final int reservationPreOrderCount;
  final DateTime? reservationReservedUntil;
  final String? lockedByDeviceId;
  final String? lockedByDeviceName;
  final String? lockedByDisplayName;
  final DateTime? lockExpiresAt;
  /// Máy đang giữ khóa sửa đơn (đang mở bàn thật).
  final bool tableSessionOpen;
  /// Còn phiên/đơn nhưng đã nhả khóa (tạm rời sơ đồ).
  final bool hasParkedBill;

  bool get hasActiveLock => tableSessionOpen;

  bool isLockedByDevice(String? deviceId) {
    if (!hasActiveLock) return false;
    final mine = (deviceId ?? '').trim().toLowerCase();
    final theirs = (lockedByDeviceId ?? '').trim().toLowerCase();
    return mine.isNotEmpty && theirs.isNotEmpty && mine == theirs;
  }

  String? lockBadgeForDevice(String? deviceId) {
    if (!hasActiveLock) return null;
    if (isLockedByDevice(deviceId)) return 'Bạn giữ';
    final device = (lockedByDeviceName ?? '').trim();
    if (device.isNotEmpty) return device;
    final who = (lockedByDisplayName ?? '').trim();
    if (who.isNotEmpty) return who;
    return 'Máy khác';
  }

  /// Đang có người sửa đơn (khóa còn hiệu lực).
  bool get isActivelyOpen => tableSessionOpen;

  /// Máy khác (không phải [deviceId]) đang giữ khóa sửa.
  bool isLockedByOtherDevice(String? deviceId) =>
      tableSessionOpen && !isLockedByDevice(deviceId);

  /// Còn đơn/phiên nhưng không ai đang sửa — đã về sơ đồ.
  bool get isParked =>
      hasParkedBill ||
      occupancyStatus.toLowerCase() == 'parked' ||
      (hasOpenSession && !tableSessionOpen && !isFree && !isReserved);

  /// Đang dùng thật: có món / tạm dừng / xin TT (và đang sửa hoặc có món).
  bool get isOccupied {
    final s = occupancyStatus.toLowerCase();
    return s == 'occupied' || s == 'paused' || s == 'billrequested';
  }

  /// Đã mở phiên, đang chọn món (có khóa).
  bool get isHolding => occupancyStatus.toLowerCase() == 'holding';

  bool get isReserved => occupancyStatus.toLowerCase() == 'reserved';

  bool get isFree => occupancyStatus.toLowerCase() == 'free';
  bool get isDirty => occupancyStatus.toLowerCase() == 'dirty' || needsCleaning;
  bool get isPaused => occupancyStatus.toLowerCase() == 'paused';
  bool get isBillRequested =>
      occupancyStatus.toLowerCase() == 'billrequested' || billRequested;

  bool get hasOpenSession =>
      openSessionId != null && openSessionId!.isNotEmpty;

  bool get hasFloorLayout => layoutX != null && layoutY != null;

  PosServiceResourceDto copyWithLayout({
    double? layoutX,
    double? layoutY,
    double? layoutW,
    double? layoutH,
  }) =>
      PosServiceResourceDto(
        id: id,
        areaId: areaId,
        areaName: areaName,
        code: code,
        name: name,
        resourceKind: resourceKind,
        capacity: capacity,
        sortOrder: sortOrder,
        defaultHourlyRate: defaultHourlyRate,
        isActive: isActive,
        occupancyStatus: occupancyStatus,
        openSessionId: openSessionId,
        openOrderId: openOrderId,
        sessionStartedAt: sessionStartedAt,
        elapsedMinutes: elapsedMinutes,
        subtotal: subtotal,
        lineCount: lineCount,
        pendingKitchenCount: pendingKitchenCount,
        guestCount: guestCount,
        billRequested: billRequested,
        needsCleaning: needsCleaning,
        orderNo: orderNo,
        layoutX: layoutX ?? this.layoutX,
        layoutY: layoutY ?? this.layoutY,
        layoutW: layoutW ?? this.layoutW,
        layoutH: layoutH ?? this.layoutH,
        reservationId: reservationId,
        reservationCustomerName: reservationCustomerName,
        reservationPhone: reservationPhone,
        reservationGuestCount: reservationGuestCount,
        reservationPreOrderCount: reservationPreOrderCount,
        reservationReservedUntil: reservationReservedUntil,
        lockedByDeviceId: lockedByDeviceId,
        lockedByDeviceName: lockedByDeviceName,
        lockedByDisplayName: lockedByDisplayName,
        lockExpiresAt: lockExpiresAt,
        tableSessionOpen: tableSessionOpen,
        hasParkedBill: hasParkedBill,
      );

  String get elapsedLabel {
    final mins = liveElapsedMinutes;
    if (mins <= 0) return '';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m}p';
  }

  /// Thời gian sử dụng thực — tính từ [sessionStartedAt], chỉ khi đã có món.
  int get liveElapsedMinutes {
    if (sessionStartedAt == null || lineCount <= 0) return 0;
    return PosServiceBillingCalc.elapsedMinutes(sessionStartedAt!, null);
  }

  factory PosServiceResourceDto.fromJson(Map<String, dynamic> json) {
    DateTime? dt(dynamic v) {
      if (v == null) return null;
      final d = DateTime.tryParse(v.toString());
      if (d == null) return null;
      if (d.isUtc) return d;
      // API Postgres thường trả UTC không kèm Z — giữ wall-clock là UTC.
      return DateTime.utc(
        d.year,
        d.month,
        d.day,
        d.hour,
        d.minute,
        d.second,
        d.millisecond,
      );
    }

    double? d(dynamic v) =>
        v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
    int i(dynamic v, [int def = 0]) =>
        v == null ? def : (v is num ? v.toInt() : int.tryParse('$v') ?? def);

    return PosServiceResourceDto(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      areaId: (json['areaId'] ?? json['AreaId'] ?? '').toString(),
      areaName: (json['areaName'] ?? json['AreaName'] ?? '').toString(),
      code: (json['code'] ?? json['Code'] ?? '').toString(),
      name: (json['name'] ?? json['Name'] ?? '').toString(),
      resourceKind: PosResourceKind.parse(
          (json['resourceKind'] ?? json['ResourceKind'])?.toString()),
      capacity: i(json['capacity'] ?? json['Capacity'], 1),
      sortOrder: i(json['sortOrder'] ?? json['SortOrder']),
      defaultHourlyRate:
          d(json['defaultHourlyRate'] ?? json['DefaultHourlyRate']),
      isActive: json['isActive'] != false && json['IsActive'] != false,
      occupancyStatus:
          (json['occupancyStatus'] ?? json['OccupancyStatus'] ?? 'Free')
              .toString(),
      openSessionId:
          (json['openSessionId'] ?? json['OpenSessionId'])?.toString(),
      openOrderId: (json['openOrderId'] ?? json['OpenOrderId'])?.toString(),
      sessionStartedAt:
          dt(json['sessionStartedAt'] ?? json['SessionStartedAt']),
      elapsedMinutes: i(json['elapsedMinutes'] ?? json['ElapsedMinutes']),
      subtotal: d(json['subtotal'] ?? json['Subtotal']) ?? 0,
      lineCount: i(json['lineCount'] ?? json['LineCount']),
      pendingKitchenCount:
          i(json['pendingKitchenCount'] ?? json['PendingKitchenCount']),
      guestCount: i(json['guestCount'] ?? json['GuestCount']),
      billRequested:
          json['billRequested'] == true || json['BillRequested'] == true,
      needsCleaning:
          json['needsCleaning'] == true || json['NeedsCleaning'] == true,
      orderNo: (json['orderNo'] ?? json['OrderNo'])?.toString(),
      layoutX: d(json['layoutX'] ?? json['LayoutX']),
      layoutY: d(json['layoutY'] ?? json['LayoutY']),
      layoutW: d(json['layoutW'] ?? json['LayoutW']) ?? 120,
      layoutH: d(json['layoutH'] ?? json['LayoutH']) ?? 100,
      reservationId:
          (json['reservationId'] ?? json['ReservationId'])?.toString(),
      reservationCustomerName: (json['reservationCustomerName'] ??
              json['ReservationCustomerName'])
          ?.toString(),
      reservationPhone:
          (json['reservationPhone'] ?? json['ReservationPhone'])?.toString(),
      reservationGuestCount:
          i(json['reservationGuestCount'] ?? json['ReservationGuestCount']),
      reservationPreOrderCount: i(
          json['reservationPreOrderCount'] ?? json['ReservationPreOrderCount']),
      reservationReservedUntil: dt(json['reservationReservedUntil'] ??
          json['ReservationReservedUntil']),
      lockedByDeviceId:
          (json['lockedByDeviceId'] ?? json['LockedByDeviceId'])?.toString(),
      lockedByDeviceName:
          (json['lockedByDeviceName'] ?? json['LockedByDeviceName'])
              ?.toString(),
      lockedByDisplayName:
          (json['lockedByDisplayName'] ?? json['LockedByDisplayName'])
              ?.toString(),
      lockExpiresAt: dt(json['lockExpiresAt'] ?? json['LockExpiresAt']),
      tableSessionOpen: json['tableSessionOpen'] == true ||
          json['TableSessionOpen'] == true,
      hasParkedBill:
          json['hasParkedBill'] == true || json['HasParkedBill'] == true,
    );
  }
}

class PosSessionBalanceDto {
  PosSessionBalanceDto({
    required this.id,
    required this.customerId,
    required this.customerName,
    this.productId,
    required this.packageName,
    required this.totalSessions,
    required this.remainingSessions,
    this.expiresAt,
  });

  final String id;
  final String customerId;
  final String customerName;
  final String? productId;
  final String packageName;
  final int totalSessions;
  final int remainingSessions;
  final DateTime? expiresAt;

  factory PosSessionBalanceDto.fromJson(Map<String, dynamic> json) =>
      PosSessionBalanceDto(
        id: (json['id'] ?? json['Id'] ?? '').toString(),
        customerId: (json['customerId'] ?? json['CustomerId'] ?? '').toString(),
        customerName:
            (json['customerName'] ?? json['CustomerName'] ?? '').toString(),
        productId: (json['productId'] ?? json['ProductId'])?.toString(),
        packageName:
            (json['packageName'] ?? json['PackageName'] ?? '').toString(),
        totalSessions:
            (json['totalSessions'] ?? json['TotalSessions'] as num?)?.toInt() ??
                0,
        remainingSessions: (json['remainingSessions'] ??
                    json['RemainingSessions'] as num?)
                ?.toInt() ??
            0,
        expiresAt: DateTime.tryParse(
            (json['expiresAt'] ?? json['ExpiresAt'] ?? '').toString()),
      );
}

/// Parse timestamp API (UTC không kèm Z) thành DateTime UTC.
DateTime? parsePosApiUtc(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final d = DateTime.tryParse(raw.trim());
  if (d == null) return null;
  if (d.isUtc) return d;
  return DateTime.utc(
    d.year,
    d.month,
    d.day,
    d.hour,
    d.minute,
    d.second,
    d.millisecond,
  );
}

/// Tính phút / qty phía client (đồng bộ helper server).
class PosServiceBillingCalc {
  static int elapsedMinutes(DateTime startedAt, DateTime? endedAt) {
    final end = endedAt?.toUtc() ?? DateTime.now().toUtc();
    // JSON không có Z → parse thành local; chuyển UTC trước khi trừ.
    final start = startedAt.isUtc ? startedAt : startedAt.toUtc();
    // Nếu server lưu UTC nhưng client parse local (VN +7), toUtc lùi 7h → giờ ảo.
    // Heuristic: nếu start lệch quá xa so với now theo hướng quá khứ > 6h
    // nhưng giá trị "cùng giờ đồng hồ" với now local → coi start là UTC wall-clock.
    var startUtc = start;
    final drift = end.difference(startUtc);
    if (!startedAt.isUtc && drift.inHours >= 6 && drift.inHours <= 8) {
      startUtc = DateTime.utc(
        startedAt.year,
        startedAt.month,
        startedAt.day,
        startedAt.hour,
        startedAt.minute,
        startedAt.second,
        startedAt.millisecond,
      );
    }
    if (end.isBefore(startUtc)) return 0;
    return end.difference(startUtc).inMinutes +
        (end.difference(startUtc).inSeconds % 60 > 0 ? 1 : 0);
  }

  static int billableMinutes({
    required int elapsed,
    required PosServiceBillingMode mode,
    int? minBillMinutes,
    int? billRoundMinutes,
  }) {
    if (!mode.isTimed) return elapsed.clamp(0, 999999);
    var minutes = elapsed.clamp(0, 999999);
    final min = minBillMinutes ?? 0;
    if (min > 0 && minutes < min) minutes = min;
    final round = billRoundMinutes ?? 0;
    if (round > 0 && minutes > 0) {
      final blocks = (minutes / round).ceil();
      minutes = blocks * round;
    }
    return minutes;
  }

  static double billableQty({
    required PosServiceBillingMode mode,
    required int billableMinutes,
    required double fallbackQty,
  }) {
    switch (mode) {
      case PosServiceBillingMode.perHour:
        return double.parse((billableMinutes / 60).toStringAsFixed(4));
      case PosServiceBillingMode.perMinute:
        return billableMinutes.toDouble();
      default:
        return fallbackQty;
    }
  }
}
