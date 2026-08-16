/// Hồ sơ ngành + khu vực/bàn/phòng + phiên + gói buổi.
library;

enum PosSellProfile {
  retail,
  salon,
  roomHourly,
  restaurant,
  gym,
  hotel;

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
      case 'hotel':
      case '5':
      case 'khachsan':
      case 'homestay':
      case 'luutru':
        return PosSellProfile.hotel;
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
        PosSellProfile.hotel => 'Hotel',
      };

  String get label => switch (this) {
        PosSellProfile.retail => 'Bán lẻ / Siêu thị',
        PosSellProfile.salon => 'Salon / Spa / Nail',
        PosSellProfile.roomHourly => 'Karaoke / Bi-a / Phòng giờ',
        PosSellProfile.restaurant => 'Nhà hàng / Cafe',
        PosSellProfile.gym => 'Gym / Yoga',
        PosSellProfile.hotel => 'Khách sạn / Lưu trú',
      };

  /// Gợi ý ngắn khi chọn ngành — hệ quả UI (sơ đồ, tính giờ, gói buổi).
  String get description => switch (this) {
        PosSellProfile.retail =>
          'Quầy bán: trái hàng hóa, phải hóa đơn. Quét mã, xuất kho, tạm tính.',
        PosSellProfile.salon =>
          'Sơ đồ ghế, dịch vụ. Tính giờ, tạm tính trước khi thanh toán.',
        PosSellProfile.roomHourly =>
          'Sơ đồ phòng, tính giờ theo phòng. Bắt buộc chọn phòng khi bán.',
        PosSellProfile.restaurant =>
          'Sơ đồ bàn, thực đơn, báo bếp. Tạm tính, hỏi số khách.',
        PosSellProfile.gym =>
          'Bán gói buổi, check-in trừ buổi. Không dùng sơ đồ bàn.',
        PosSellProfile.hotel =>
          'Sơ đồ phòng, nhận/trả phòng, folio tạm tính, dịch vụ kèm (minibar, giặt ủi).',
      };

  List<String> get featureHints => switch (this) {
        PosSellProfile.retail => const [
            'Hàng hóa + hóa đơn',
            'Quét mã vạch',
            'Xuất kho / tạm tính',
          ],
        PosSellProfile.salon => const [
            'Sơ đồ ghế',
            'Gói liệu trình',
            'Tạm tính',
          ],
        PosSellProfile.roomHourly => const [
            'Sơ đồ phòng',
            'Phí mở + block phút',
            'Tạm tính',
          ],
        PosSellProfile.restaurant => const [
            'Sơ đồ bàn',
            'Báo bếp',
            'Tạm tính',
          ],
        PosSellProfile.gym => const [
            'Thẻ tập / gói buổi',
            'Check-in trừ buổi',
            'Không sơ đồ',
          ],
        PosSellProfile.hotel => const [
            'Sơ đồ phòng',
            'Theo giờ / theo ngày',
            'Folio tạm tính',
          ],
      };

  /// Bàn / ghế / phòng — rỗng với bán lẻ và gym.
  String get resourceNoun => switch (this) {
        PosSellProfile.salon => 'ghế',
        PosSellProfile.roomHourly => 'phòng',
        PosSellProfile.hotel => 'phòng',
        PosSellProfile.restaurant => 'bàn',
        _ => '',
      };

  String get resourceNounPlural => switch (this) {
        PosSellProfile.salon => 'ghế',
        PosSellProfile.roomHourly => 'phòng',
        PosSellProfile.hotel => 'phòng',
        PosSellProfile.restaurant => 'bàn',
        _ => '',
      };

  String get floorTabLabel => switch (this) {
        PosSellProfile.salon => 'Sơ đồ ghế',
        PosSellProfile.roomHourly => 'Sơ đồ phòng',
        PosSellProfile.hotel => 'Sơ đồ phòng',
        PosSellProfile.restaurant => 'Sơ đồ bàn',
        _ => 'Sơ đồ',
      };

  /// Màn lịch đặt / hẹn theo ngành.
  String get bookingCalendarTitle => switch (this) {
        PosSellProfile.salon => 'Lịch hẹn',
        PosSellProfile.restaurant => 'Lịch đặt bàn',
        PosSellProfile.hotel => 'Lịch đặt phòng',
        PosSellProfile.roomHourly => 'Lịch phòng',
        _ => 'Lịch đặt',
      };

  String get bookActionLabel => switch (this) {
        PosSellProfile.salon => 'Đặt lịch',
        PosSellProfile.restaurant => 'Đặt bàn',
        PosSellProfile.hotel => 'Đặt phòng',
        PosSellProfile.roomHourly => 'Đặt phòng',
        _ => 'Đặt chỗ',
      };

  String get catalogTabLabel => switch (this) {
        PosSellProfile.salon => 'Dịch vụ',
        PosSellProfile.roomHourly => 'Dịch vụ',
        PosSellProfile.hotel => 'Dịch vụ',
        PosSellProfile.restaurant => 'Thực đơn',
        PosSellProfile.gym => 'Gói / dịch vụ',
        _ => 'Hàng hóa',
      };

  String get searchHint => switch (this) {
        PosSellProfile.salon => 'Tìm dịch vụ (F3)',
        PosSellProfile.roomHourly => 'Tìm dịch vụ (F3)',
        PosSellProfile.hotel => 'Tìm phòng / dịch vụ (F3)',
        PosSellProfile.gym => 'Tìm gói / dịch vụ (F3)',
        PosSellProfile.restaurant => 'Tìm món (F3)',
        _ => 'Tìm hàng (F3)',
      };

  String get floorSearchHint => switch (this) {
        PosSellProfile.salon => 'Tìm ghế',
        PosSellProfile.roomHourly => 'Tìm phòng',
        PosSellProfile.hotel => 'Tìm phòng',
        PosSellProfile.restaurant => 'Tìm bàn',
        _ => 'Tìm',
      };

  /// Tiêu đề cột phải trên màn bán (không gắn bàn/ghế/phòng).
  String get invoiceTitle => switch (this) {
        PosSellProfile.salon => 'Phiếu dịch vụ',
        PosSellProfile.roomHourly => 'Phiếu phòng',
        PosSellProfile.hotel => 'Folio phòng',
        PosSellProfile.restaurant => 'Phiếu bàn',
        _ => 'Hóa đơn',
      };

  /// Đơn vị đếm dòng trên giỏ: hàng / món / dịch vụ.
  String get lineUnit => switch (this) {
        PosSellProfile.salon => 'dịch vụ',
        PosSellProfile.roomHourly => 'dịch vụ',
        PosSellProfile.hotel => 'dịch vụ',
        PosSellProfile.restaurant => 'món',
        _ => 'hàng',
      };

  String get pickCatalogLabel => switch (this) {
        PosSellProfile.salon => 'Chọn dịch vụ',
        PosSellProfile.roomHourly => 'Chọn dịch vụ',
        PosSellProfile.hotel => 'Chọn dịch vụ',
        PosSellProfile.restaurant => 'Chọn món',
        PosSellProfile.gym => 'Chọn gói / dịch vụ',
        _ => 'Chọn hàng',
      };

  /// Cột trái trên bảng giỏ hàng.
  String get catalogColumnLabel => switch (this) {
        PosSellProfile.salon => 'Dịch vụ',
        PosSellProfile.roomHourly => 'Dịch vụ',
        PosSellProfile.hotel => 'Dịch vụ',
        PosSellProfile.restaurant => 'Món',
        PosSellProfile.gym => 'Gói / dịch vụ',
        _ => 'Sản phẩm',
      };

  String get emptyCartHint => switch (this) {
        PosSellProfile.salon => 'Tìm và thêm dịch vụ vào phiếu',
        PosSellProfile.roomHourly => 'Tìm và thêm dịch vụ vào phiếu phòng',
        PosSellProfile.hotel => 'Tìm và thêm dịch vụ vào folio',
        PosSellProfile.restaurant => 'Tìm và thêm món vào phiếu bàn',
        PosSellProfile.gym => 'Tìm và thêm gói / dịch vụ vào hóa đơn',
        _ => 'Tìm và thêm hàng hóa vào hóa đơn',
      };

  bool get usesFloorPlan =>
      this == PosSellProfile.restaurant ||
      this == PosSellProfile.salon ||
      this == PosSellProfile.roomHourly ||
      this == PosSellProfile.hotel;

  bool get usesKitchenNotify => this == PosSellProfile.restaurant;

  bool get usesWarehouseSlip =>
      this == PosSellProfile.retail || this == PosSellProfile.gym;

  PosResourceKind get defaultResourceKind => switch (this) {
        PosSellProfile.salon => PosResourceKind.chair,
        PosSellProfile.roomHourly => PosResourceKind.room,
        PosSellProfile.hotel => PosResourceKind.room,
        PosSellProfile.restaurant => PosResourceKind.table,
        _ => PosResourceKind.other,
      };
}


enum PosServiceBillingMode {
  flat,
  perHour,
  perMinute,
  perSession,
  perBlock,
  perDay;

  static PosServiceBillingMode parse(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'perhour':
        return PosServiceBillingMode.perHour;
      case 'perminute':
        return PosServiceBillingMode.perMinute;
      case 'persession':
        return PosServiceBillingMode.perSession;
      case 'perblock':
        return PosServiceBillingMode.perBlock;
      case 'perday':
        return PosServiceBillingMode.perDay;
      default:
        return PosServiceBillingMode.flat;
    }
  }

  String get apiValue => switch (this) {
        PosServiceBillingMode.flat => 'Flat',
        PosServiceBillingMode.perHour => 'PerHour',
        PosServiceBillingMode.perMinute => 'PerMinute',
        PosServiceBillingMode.perSession => 'PerSession',
        PosServiceBillingMode.perBlock => 'PerBlock',
        PosServiceBillingMode.perDay => 'PerDay',
      };

  String get label => switch (this) {
        PosServiceBillingMode.flat => 'Giá cố định',
        PosServiceBillingMode.perHour => 'Theo giờ',
        PosServiceBillingMode.perMinute => 'Theo phút',
        PosServiceBillingMode.perSession => 'Theo buổi / liệu trình',
        PosServiceBillingMode.perBlock => 'Theo block (karaoke / bi-a)',
        PosServiceBillingMode.perDay => 'Theo ngày (khách sạn)',
      };

  bool get isTimed =>
      this == PosServiceBillingMode.perHour ||
      this == PosServiceBillingMode.perMinute ||
      this == PosServiceBillingMode.perBlock ||
      this == PosServiceBillingMode.perDay;
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
    this.enableMultiDeviceDraftLock = false,
    this.promptGuestCountOnOpen = false,
    this.allowNegativeStock = false,
    this.enableCashierShift = false,
    this.enableQrTableOrder = false,
    this.enableQrOrderAutoPrint = true,
    this.reportDayStartHour = 0,
    this.defaultHourlyProductId,
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
  /// Khóa draft / «Lấy quyền» khi nhiều máy POS song song.
  final bool enableMultiDeviceDraftLock;
  /// Hỏi số khách khi mở bàn trống.
  final bool promptGuestCountOnOpen;
  /// Cho phép bán khi tồn khả dụng &lt; số cần (OnHand có thể âm).
  final bool allowNegativeStock;
  /// Ca thu ngân (mở/đóng két). Tắt mặc định.
  final bool enableCashierShift;
  /// QR order tại bàn. Tắt mặc định.
  final bool enableQrTableOrder;
  /// QR: tự in phiếu bếp khi khách gửi món. Tắt = thu ngân in thủ công.
  final bool enableQrOrderAutoPrint;
  /// Giờ bắt đầu ngày KD VN (0=nửa đêm UTC+7; &gt;0=ngày qua đêm).
  final int reportDayStartHour;
  bool get overnightReportEnabled => reportDayStartHour > 0;
  /// SP dịch vụ tính giờ mặc định khi mở bàn.
  final String? defaultHourlyProductId;
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
        enableMultiDeviceDraftLock:
            json['enableMultiDeviceDraftLock'] == true ||
                json['EnableMultiDeviceDraftLock'] == true,
        promptGuestCountOnOpen: json['promptGuestCountOnOpen'] == true ||
            json['PromptGuestCountOnOpen'] == true,
        allowNegativeStock: json['allowNegativeStock'] == true ||
            json['AllowNegativeStock'] == true,
        enableCashierShift: json['enableCashierShift'] == true ||
            json['EnableCashierShift'] == true,
        enableQrTableOrder: json['enableQrTableOrder'] == true ||
            json['EnableQrTableOrder'] == true,
        enableQrOrderAutoPrint: json['enableQrOrderAutoPrint'] != false &&
            json['EnableQrOrderAutoPrint'] != false,
        reportDayStartHour: () {
          final v = json['reportDayStartHour'] ?? json['ReportDayStartHour'];
          if (v is int) return v.clamp(0, 23);
          return int.tryParse('$v')?.clamp(0, 23) ?? 0;
        }(),
        defaultHourlyProductId: (json['defaultHourlyProductId'] ??
                json['DefaultHourlyProductId'])
            ?.toString(),
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
      'enableMultiDeviceDraftLock': enableMultiDeviceDraftLock,
      'promptGuestCountOnOpen': promptGuestCountOnOpen,
      'allowNegativeStock': allowNegativeStock,
      'enableCashierShift': enableCashierShift,
      'enableQrTableOrder': enableQrTableOrder,
      'enableQrOrderAutoPrint': enableQrOrderAutoPrint,
      'reportDayStartHour': reportDayStartHour.clamp(0, 23),
      'defaultHourlyProductId': defaultHourlyProductId,
      'setDefaultHourlyProductId': true,
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
          allowProvisionalBill: true,
          enableMultiDeviceDraftLock: false,
          promptGuestCountOnOpen: false,
        );
      case PosSellProfile.salon:
        return copyWith(
          sellProfile: profile,
          enableResources: true,
          enableHourlyBilling: true,
          enableSessionPacks: true,
          requireResourceOnSale: false,
          showFloorPlan: true,
          allowProvisionalBill: true,
          enableMultiDeviceDraftLock: true,
          promptGuestCountOnOpen: false,
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
          enableMultiDeviceDraftLock: true,
          promptGuestCountOnOpen: false,
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
          enableMultiDeviceDraftLock: true,
          promptGuestCountOnOpen: false,
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
          enableMultiDeviceDraftLock: false,
          promptGuestCountOnOpen: false,
        );
      case PosSellProfile.hotel:
        return copyWith(
          sellProfile: profile,
          enableResources: true,
          enableHourlyBilling: true,
          enableSessionPacks: false,
          requireResourceOnSale: true,
          showFloorPlan: true,
          allowProvisionalBill: true,
          enableMultiDeviceDraftLock: true,
          promptGuestCountOnOpen: true,
          reportDayStartHour: 12,
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
    bool? enableMultiDeviceDraftLock,
    bool? promptGuestCountOnOpen,
    bool? allowNegativeStock,
    bool? enableCashierShift,
    bool? enableQrTableOrder,
    bool? enableQrOrderAutoPrint,
    int? reportDayStartHour,
    String? defaultHourlyProductId,
    bool clearDefaultHourlyProductId = false,
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
        enableMultiDeviceDraftLock:
            enableMultiDeviceDraftLock ?? this.enableMultiDeviceDraftLock,
        promptGuestCountOnOpen:
            promptGuestCountOnOpen ?? this.promptGuestCountOnOpen,
        allowNegativeStock: allowNegativeStock ?? this.allowNegativeStock,
        enableCashierShift: enableCashierShift ?? this.enableCashierShift,
        enableQrTableOrder: enableQrTableOrder ?? this.enableQrTableOrder,
        enableQrOrderAutoPrint:
            enableQrOrderAutoPrint ?? this.enableQrOrderAutoPrint,
        reportDayStartHour: reportDayStartHour ?? this.reportDayStartHour,
        defaultHourlyProductId: clearDefaultHourlyProductId
            ? null
            : (defaultHourlyProductId ?? this.defaultHourlyProductId),
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
    this.defaultServiceProductId,
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
    this.accumulatedPauseMinutes = 0,
    this.pausedAt,
    this.reservationDepositPaid = 0,
    this.reservationDepositAmount = 0,
    this.reservationDepositStatus,
    this.draftBillCount = 1,
    this.draftBills = const [],
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
  final String? defaultServiceProductId;
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
  /// Tổng phút tạm dừng đã chốt (resume).
  final int accumulatedPauseMinutes;
  /// Đang pause — mốc bắt đầu khoảng pause hiện tại.
  final DateTime? pausedAt;
  final double reservationDepositPaid;
  final double reservationDepositAmount;
  final String? reservationDepositStatus;
  final int draftBillCount;
  final List<PosResourceDraftBillDto> draftBills;

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
        defaultServiceProductId: defaultServiceProductId,
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
        accumulatedPauseMinutes: accumulatedPauseMinutes,
        pausedAt: pausedAt,
        reservationDepositPaid: reservationDepositPaid,
        reservationDepositAmount: reservationDepositAmount,
        reservationDepositStatus: reservationDepositStatus,
      );

  String get elapsedLabel {
    final mins = liveElapsedMinutes;
    if (mins <= 0) return '';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    return '${m}p';
  }

  /// Thời gian sử dụng thực — trừ pause; đóng băng khi đang tạm dừng.
  int get liveElapsedMinutes {
    if (sessionStartedAt == null || lineCount <= 0) return 0;
    if (isPaused && pausedAt == null && elapsedMinutes > 0) {
      return elapsedMinutes;
    }
    return PosServiceBillingCalc.elapsedMinutes(
      sessionStartedAt!,
      null,
      accumulatedPauseMinutes: accumulatedPauseMinutes,
      pausedAt: isPaused ? pausedAt : null,
    );
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
      defaultServiceProductId: (json['defaultServiceProductId'] ??
              json['DefaultServiceProductId'])
          ?.toString(),
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
      accumulatedPauseMinutes: i(
          json['accumulatedPauseMinutes'] ?? json['AccumulatedPauseMinutes']),
      pausedAt: dt(json['pausedAt'] ?? json['PausedAt']),
      reservationDepositPaid: d(json['reservationDepositPaid'] ??
              json['ReservationDepositPaid']) ??
          0,
      reservationDepositAmount: d(json['reservationDepositAmount'] ??
              json['ReservationDepositAmount']) ??
          0,
      reservationDepositStatus: (json['reservationDepositStatus'] ??
              json['ReservationDepositStatus'])
          ?.toString(),
      draftBillCount: i(json['draftBillCount'] ?? json['DraftBillCount'], 1),
      draftBills: _parseDraftBills(json['draftBills'] ?? json['DraftBills']),
    );
  }
}

class PosResourceDraftBillDto {
  const PosResourceDraftBillDto({
    required this.id,
    required this.orderNo,
    this.subtotal = 0,
    this.lineCount = 0,
    this.isSplit = false,
  });

  final String id;
  final String orderNo;
  final double subtotal;
  final int lineCount;
  final bool isSplit;

  factory PosResourceDraftBillDto.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    int i(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
    return PosResourceDraftBillDto(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      orderNo: (json['orderNo'] ?? json['OrderNo'] ?? '').toString(),
      subtotal: n(json['subtotal'] ?? json['Subtotal']),
      lineCount: i(json['lineCount'] ?? json['LineCount']),
      isSplit: json['isSplit'] == true || json['IsSplit'] == true,
    );
  }
}

List<PosResourceDraftBillDto> _parseDraftBills(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final e in raw)
      if (e is Map)
        PosResourceDraftBillDto.fromJson(Map<String, dynamic>.from(e)),
  ];
}

/// Đặt trước bàn/phòng (list API).
class PosResourceReservationDto {
  PosResourceReservationDto({
    required this.id,
    required this.resourceId,
    required this.resourceCode,
    required this.resourceName,
    this.areaName,
    required this.customerName,
    this.phone,
    this.customerId,
    this.guestCount = 1,
    this.reservedAt,
    this.reservedUntil,
    this.status = 'Booked',
    this.note,
    this.preOrderCount = 0,
    this.depositAmount = 0,
    this.depositPaid = 0,
    this.depositStatus = 'None',
    this.depositPaymentMethod,
    this.durationMinutes,
    this.serviceProductId,
    this.serviceProductName,
    this.assignedEmployeeId,
    this.assignedEmployeeName,
    this.isTimedSlot = false,
    this.preOrderValue = 0,
    this.resourceKind,
  });

  final String id;
  final String resourceId;
  final String resourceCode;
  final String resourceName;
  final String? areaName;
  final String customerName;
  final String? phone;
  final String? customerId;
  final int guestCount;
  final DateTime? reservedAt;
  final DateTime? reservedUntil;
  final String status;
  final String? note;
  final int preOrderCount;
  final double depositAmount;
  final double depositPaid;
  final String depositStatus;
  final String? depositPaymentMethod;
  final int? durationMinutes;
  final String? serviceProductId;
  final String? serviceProductName;
  final String? assignedEmployeeId;
  final String? assignedEmployeeName;
  final bool isTimedSlot;
  final double preOrderValue;
  final String? resourceKind;

  bool get isBooked => status.toLowerCase() == 'booked';
  bool get isSeated => status.toLowerCase() == 'seated';
  bool get isCancelled => status.toLowerCase() == 'cancelled';
  bool get isNoShow => status.toLowerCase() == 'noshow';
  bool get hasDepositHeld =>
      depositStatus.toLowerCase() == 'held' && depositPaid > 0;

  /// Tạm tính ngày đặt: món đặt trước + cọc đang giữ (chỉ Booked).
  double get expectedRevenue {
    if (!isBooked) return 0;
    return preOrderValue + (hasDepositHeld ? depositPaid : 0);
  }

  factory PosResourceReservationDto.fromJson(Map<String, dynamic> json) {
    DateTime? dt(dynamic v) => parsePosApiUtc(v?.toString());
    double d(dynamic v) =>
        v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
    int i(dynamic v, [int def = 0]) =>
        v == null ? def : (v is num ? v.toInt() : int.tryParse('$v') ?? def);
    int? iNull(dynamic v) =>
        v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));

    final duration = iNull(json['durationMinutes'] ?? json['DurationMinutes']);
    final timedFlag = json['isTimedSlot'] ?? json['IsTimedSlot'];
    final timed = timedFlag is bool
        ? timedFlag
        : timedFlag?.toString().toLowerCase() == 'true' ||
            (duration != null && duration > 0);

    return PosResourceReservationDto(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      resourceId: (json['resourceId'] ?? json['ResourceId'] ?? '').toString(),
      resourceCode:
          (json['resourceCode'] ?? json['ResourceCode'] ?? '').toString(),
      resourceName:
          (json['resourceName'] ?? json['ResourceName'] ?? '').toString(),
      areaName: (json['areaName'] ?? json['AreaName'])?.toString(),
      customerName:
          (json['customerName'] ?? json['CustomerName'] ?? '').toString(),
      phone: (json['phone'] ?? json['Phone'])?.toString(),
      customerId: (json['customerId'] ?? json['CustomerId'])?.toString(),
      guestCount: i(json['guestCount'] ?? json['GuestCount'], 1),
      reservedAt: dt(json['reservedAt'] ??
          json['ReservedAt'] ??
          json['slotStart'] ??
          json['SlotStart']),
      reservedUntil: dt(json['reservedUntil'] ??
          json['ReservedUntil'] ??
          json['slotEnd'] ??
          json['SlotEnd']),
      status: (json['status'] ?? json['Status'] ?? 'Booked').toString(),
      note: (json['note'] ?? json['Note'])?.toString(),
      preOrderCount: i(json['preOrderCount'] ?? json['PreOrderCount']),
      depositAmount: d(json['depositAmount'] ?? json['DepositAmount']),
      depositPaid: d(json['depositPaid'] ?? json['DepositPaid']),
      depositStatus:
          (json['depositStatus'] ?? json['DepositStatus'] ?? 'None').toString(),
      depositPaymentMethod: (json['depositPaymentMethod'] ??
              json['DepositPaymentMethod'])
          ?.toString(),
      durationMinutes: duration,
      serviceProductId:
          (json['serviceProductId'] ?? json['ServiceProductId'])?.toString(),
      serviceProductName: (json['serviceProductName'] ??
              json['ServiceProductName'])
          ?.toString(),
      assignedEmployeeId: (json['assignedEmployeeId'] ??
              json['AssignedEmployeeId'])
          ?.toString(),
      assignedEmployeeName: (json['assignedEmployeeName'] ??
              json['AssignedEmployeeName'])
          ?.toString(),
      isTimedSlot: timed,
      preOrderValue: d(json['preOrderValue'] ?? json['PreOrderValue']),
      resourceKind: (json['resourceKind'] ?? json['ResourceKind'])?.toString(),
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
  static int elapsedMinutes(
    DateTime startedAt,
    DateTime? endedAt, {
    int accumulatedPauseMinutes = 0,
    DateTime? pausedAt,
  }) {
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
    var raw = end.difference(startUtc).inMinutes +
        (end.difference(startUtc).inSeconds % 60 > 0 ? 1 : 0);
    var pause = accumulatedPauseMinutes < 0 ? 0 : accumulatedPauseMinutes;
    if (pausedAt != null) {
      final p = pausedAt.isUtc ? pausedAt : pausedAt.toUtc();
      if (!end.isBefore(p)) {
        pause += end.difference(p).inMinutes;
      }
    }
    final net = raw - pause;
    return net < 0 ? 0 : net;
  }

  static String formatDurationLabel(int minutes) {
    if (minutes <= 0) return '0p';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h${m.toString().padLeft(2, '0')}';
    if (h > 0) return '${h}h';
    return '${m}p';
  }

  static int billableMinutes({
    required int elapsed,
    required PosServiceBillingMode mode,
    int? minBillMinutes,
    int? billRoundMinutes,
    int? graceMinutes,
    int? roundAfterMinutes,
  }) {
    if (!mode.isTimed) return elapsed.clamp(0, 999999);
    final raw = elapsed.clamp(0, 999999);
    final grace = graceMinutes ?? 0;
    var minutes = (raw - (grace > 0 ? grace : 0)).clamp(0, 999999);
    final min = minBillMinutes ?? 0;
    if (min > 0 && minutes < min) minutes = min;
    var round = billRoundMinutes ?? 0;
    if (mode == PosServiceBillingMode.perDay && round < 60) round = 1440;
    if (mode == PosServiceBillingMode.perBlock && round <= 0) round = 5;
    final roundAfter = roundAfterMinutes ?? 0;
    final applyRound =
        round > 0 && minutes > 0 && (roundAfter <= 0 || raw > roundAfter);
    if (applyRound) {
      final blocks = (minutes / round).ceil();
      minutes = blocks * round;
    }
    return minutes;
  }

  static double billableQty({
    required PosServiceBillingMode mode,
    required int billableMinutes,
    required double fallbackQty,
    int? billRoundMinutes,
  }) {
    switch (mode) {
      case PosServiceBillingMode.perHour:
        return double.parse((billableMinutes / 60).toStringAsFixed(4));
      case PosServiceBillingMode.perMinute:
        return billableMinutes.toDouble();
      case PosServiceBillingMode.perBlock:
        final block = (billRoundMinutes ?? 0) > 0 ? billRoundMinutes! : 5;
        if (billableMinutes <= 0) return 0;
        return double.parse((billableMinutes / block).toStringAsFixed(4));
      case PosServiceBillingMode.perDay:
        if (billableMinutes <= 0) return 1;
        return (billableMinutes / 1440).ceil().toDouble().clamp(1, 999999);
      default:
        return fallbackQty;
    }
  }

  /// Qty phần vượt OpeningMinutes (phí mở không nằm trong qty).
  static double extraQty({
    required PosServiceBillingMode mode,
    required int billableMinutes,
    int? openingMinutes,
    int? billRoundMinutes,
    double fallbackQty = 0,
  }) {
    final included = openingMinutes ?? 0;
    final extra = billableMinutes - (included > 0 ? included : 0);
    if (extra <= 0) return 0;
    return billableQty(
      mode: mode,
      billableMinutes: extra,
      fallbackQty: fallbackQty,
      billRoundMinutes: billRoundMinutes,
    );
  }

  static double timedLineCharge({
    required PosServiceBillingMode mode,
    required int billableMinutes,
    required double unitPrice,
    double openingFee = 0,
    int? openingMinutes,
    int? billRoundMinutes,
    double toppingExtraPerUnit = 0,
  }) {
    final qty = extraQty(
      mode: mode,
      billableMinutes: billableMinutes,
      openingMinutes: openingMinutes,
      billRoundMinutes: billRoundMinutes,
    );
    final fee = openingFee < 0 ? 0.0 : openingFee;
    return fee + qty * (unitPrice + toppingExtraPerUnit);
  }

  static List<({int elapsed, int billable, double qty, double total})> preview({
    required PosServiceBillingMode mode,
    required double unitPrice,
    int? minBillMinutes,
    int? billRoundMinutes,
    int? graceMinutes,
    int? roundAfterMinutes,
    double openingFee = 0,
    int? openingMinutes,
    List<int> elapsedSamples = const [1, 5, 6, 10, 12, 15, 30, 60],
  }) {
    final fee = openingFee < 0 ? 0.0 : openingFee;
    final rows = <({int elapsed, int billable, double qty, double total})>[];
    for (final elapsed in elapsedSamples) {
      final billable = billableMinutes(
        elapsed: elapsed,
        mode: mode,
        minBillMinutes: minBillMinutes,
        billRoundMinutes: billRoundMinutes,
        graceMinutes: graceMinutes,
        roundAfterMinutes: roundAfterMinutes,
      );
      final qty = extraQty(
        mode: mode,
        billableMinutes: billable,
        openingMinutes: openingMinutes,
        billRoundMinutes: billRoundMinutes,
      );
      rows.add((
        elapsed: elapsed,
        billable: billable,
        qty: qty,
        total: fee + qty * unitPrice,
      ));
    }
    return rows;
  }
}
