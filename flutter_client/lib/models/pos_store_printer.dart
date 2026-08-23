class PosStorePrinter {
  const PosStorePrinter({
    required this.id,
    required this.name,
    required this.connectionType,
    this.printerBrand,
    this.paperSize = 'K80',
    this.textMode,
    this.bluetoothAddress,
    this.bluetoothName,
    this.lanHost,
    this.lanPort = 9100,
    this.usbDeviceName,
    this.feedBeforeCut = 8,
    this.partialCut = true,
    this.cutPerItem = false,
    this.openCashDrawer = false,
    this.openDrawerCashOnly = true,
    this.beepOnPrint = false,
    this.isDefault = false,
    this.requiresAgent = false,
    this.isDeviceLocal = false,
    this.ownerDeviceId,
    this.healthStatus = 'Unknown',
    this.lastSeenAt,
    this.lastErrorMessage,
    this.sortOrder = 0,
    this.isActive = true,
    this.documentTypes = const [],
    this.defaultCopies = 1,
  });

  final String id;
  final String name;
  final String connectionType;
  final String? printerBrand;
  final String paperSize;
  final String? textMode;
  final String? bluetoothAddress;
  final String? bluetoothName;
  final String? lanHost;
  final int lanPort;
  final String? usbDeviceName;
  final int feedBeforeCut;
  final bool partialCut;
  final bool cutPerItem;
  final bool openCashDrawer;
  final bool openDrawerCashOnly;
  final bool beepOnPrint;
  final bool isDefault;
  final bool requiresAgent;
  /// Máy in nội bộ trên thiết bị POS (không gán cho Print Agent).
  final bool isDeviceLocal;
  final String? ownerDeviceId;
  final String healthStatus;
  final DateTime? lastSeenAt;
  final String? lastErrorMessage;
  final int sortOrder;
  final bool isActive;
  final List<String> documentTypes;
  final int defaultCopies;

  bool get isLan => connectionType == 'Lan';
  bool get isBluetooth => connectionType == 'Bluetooth';
  bool get isSunmi => connectionType == 'Sunmi';
  bool get isUsb => connectionType == 'Usb';
  bool get isLabelPrinter => printerBrand == 'label';
  /// Agent cloud: cần Print Agent. Máy nội bộ thiết bị: không.
  bool get needsPrintAgent => !isDeviceLocal && requiresAgent;
  /// Danh sách «cloud / Agent» — máy nội bộ sync luôn RequiresAgent=false.
  bool get isCloudAgentPrinter => !isDeviceLocal && requiresAgent;

  /// Online/Busy chỉ còn hiệu lực ~90s kể từ lastSeenAt (tránh Zywell/tem Offline vẫn Online).
  bool get isOnline {
    if (healthStatus != 'Online' && healthStatus != 'Busy') return false;
    final seen = lastSeenAt;
    if (seen == null) return false;
    final age = DateTime.now().toUtc().difference(seen.toUtc());
    return age.inSeconds <= 90;
  }

  static bool _jsonBool(dynamic v) =>
      v == true || v == 1 || v?.toString().toLowerCase() == 'true';

  factory PosStorePrinter.fromJson(Map<String, dynamic> json) => PosStorePrinter(
        id: (json['id'] ?? json['Id'])?.toString() ?? '',
        name: (json['name'] ?? json['Name'])?.toString() ?? '',
        connectionType:
            (json['connectionType'] ?? json['ConnectionType'])?.toString() ??
                'Lan',
        printerBrand:
            (json['printerBrand'] ?? json['PrinterBrand'])?.toString(),
        paperSize:
            (json['paperSize'] ?? json['PaperSize'])?.toString() ?? 'K80',
        textMode: (json['textMode'] ?? json['TextMode'])?.toString(),
        bluetoothAddress:
            (json['bluetoothAddress'] ?? json['BluetoothAddress'])?.toString(),
        bluetoothName:
            (json['bluetoothName'] ?? json['BluetoothName'])?.toString(),
        lanHost: (json['lanHost'] ?? json['LanHost'])?.toString(),
        lanPort: (json['lanPort'] as num?)?.toInt() ??
            (json['LanPort'] as num?)?.toInt() ??
            9100,
        usbDeviceName:
            (json['usbDeviceName'] ?? json['UsbDeviceName'])?.toString(),
        feedBeforeCut: (json['feedBeforeCut'] as num?)?.toInt() ??
            (json['FeedBeforeCut'] as num?)?.toInt() ??
            8,
        partialCut: _jsonBool(json['partialCut'] ?? json['PartialCut']),
        cutPerItem: _jsonBool(json['cutPerItem'] ?? json['CutPerItem']),
        openCashDrawer:
            _jsonBool(json['openCashDrawer'] ?? json['OpenCashDrawer']),
        openDrawerCashOnly: json['openDrawerCashOnly'] != false &&
            json['OpenDrawerCashOnly'] != false,
        beepOnPrint: _jsonBool(json['beepOnPrint'] ?? json['BeepOnPrint']),
        isDefault: _jsonBool(json['isDefault'] ?? json['IsDefault']),
        requiresAgent:
            _jsonBool(json['requiresAgent'] ?? json['RequiresAgent']),
        isDeviceLocal:
            _jsonBool(json['isDeviceLocal'] ?? json['IsDeviceLocal']),
        ownerDeviceId:
            (json['ownerDeviceId'] ?? json['OwnerDeviceId'])?.toString(),
        healthStatus:
            (json['healthStatus'] ?? json['HealthStatus'])?.toString() ??
                'Unknown',
        lastSeenAt: json['lastSeenAt'] != null || json['LastSeenAt'] != null
            ? DateTime.tryParse(
                (json['lastSeenAt'] ?? json['LastSeenAt']).toString())
            : null,
        lastErrorMessage:
            (json['lastErrorMessage'] ?? json['LastErrorMessage'])?.toString(),
        sortOrder: (json['sortOrder'] as num?)?.toInt() ??
            (json['SortOrder'] as num?)?.toInt() ??
            0,
        isActive: json['isActive'] != false && json['IsActive'] != false,
        documentTypes: (json['documentTypes'] as List? ??
                    json['DocumentTypes'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        defaultCopies: (json['defaultCopies'] as num?)?.toInt() ??
            (json['DefaultCopies'] as num?)?.toInt() ??
            1,
      );

  Map<String, dynamic> toSaveJson() => {
        'name': name,
        'connectionType': connectionType,
        'printerBrand': printerBrand,
        'paperSize': paperSize,
        'textMode': textMode,
        'bluetoothAddress': bluetoothAddress,
        'bluetoothName': bluetoothName,
        'lanHost': lanHost,
        'lanPort': lanPort,
        'usbDeviceName': usbDeviceName,
        'feedBeforeCut': feedBeforeCut,
        'partialCut': partialCut,
        'cutPerItem': cutPerItem,
        'openCashDrawer': openCashDrawer,
        'openDrawerCashOnly': openDrawerCashOnly,
        'beepOnPrint': beepOnPrint,
        'isDefault': isDefault,
        'sortOrder': sortOrder,
        'isActive': isActive,
      };
}

class PosPrinterRoute {
  const PosPrinterRoute({
    required this.documentType,
    required this.printerId,
    this.defaultCopies = 1,
  });

  final String documentType;
  final String printerId;
  final int defaultCopies;

  factory PosPrinterRoute.fromJson(Map<String, dynamic> json) => PosPrinterRoute(
        documentType: json['documentType']?.toString() ?? '',
        printerId: json['printerId']?.toString() ?? '',
        defaultCopies: (json['defaultCopies'] as num?)?.toInt() ?? 1,
      );

  Map<String, dynamic> toJson() => {
        'documentType': documentType,
        'printerId': printerId,
        'defaultCopies': defaultCopies,
      };
}

class PosPrintJobInfo {
  const PosPrintJobInfo({
    required this.jobId,
    required this.printerId,
    required this.printerName,
    required this.status,
    this.requiresAgent = false,
    this.connectionType,
    this.referenceNo,
    this.errorMessage,
  });

  final String jobId;
  final String printerId;
  final String printerName;
  final String status;
  final bool requiresAgent;
  final String? connectionType;
  final String? referenceNo;
  final String? errorMessage;

  factory PosPrintJobInfo.fromJson(Map<String, dynamic> json) => PosPrintJobInfo(
        jobId: json['jobId']?.toString() ?? json['id']?.toString() ?? '',
        printerId: json['printerId']?.toString() ?? '',
        printerName: json['printerName']?.toString() ?? '',
        status: json['status']?.toString() ?? 'Queued',
        requiresAgent: json['requiresAgent'] == true,
        connectionType: json['connectionType']?.toString(),
        referenceNo: json['referenceNo']?.toString(),
        errorMessage: json['errorMessage']?.toString(),
      );
}

/// Loại chứng từ in cloud (khớp server PosPrintDocumentType).
abstract final class PosCloudDocumentTypes {
  static const saleInvoice = 'SaleInvoice';
  static const saleOrder = 'SaleOrder';
  static const delivery = 'Delivery';
  static const saleReturn = 'SaleReturn';
  static const purchaseReceipt = 'PurchaseReceipt';
  static const purchaseReturn = 'PurchaseReturn';
  static const stockIssue = 'StockIssue';
  static const endOfDayReport = 'EndOfDayReport';
  static const barcodeLabel = 'BarcodeLabel';
  static const stockCount = 'StockCount';
  static const cashReceipt = 'CashReceipt';
  static const cashPayment = 'CashPayment';
  static const kitchenSlip = 'KitchenSlip';
  static const kitchenVoid = 'KitchenVoid';
  static const kitchenLabel = 'KitchenLabel';

  static const labels = <String, String>{
    saleInvoice: 'Hóa đơn bán hàng',
    saleOrder: 'Đặt hàng',
    delivery: 'Giao hàng',
    saleReturn: 'Trả hàng',
    purchaseReceipt: 'Phiếu nhập hàng',
    purchaseReturn: 'Trả hàng nhập',
    stockIssue: 'Phiếu xuất kho',
    endOfDayReport: 'Tổng kết cuối ngày',
    barcodeLabel: 'Tem sản phẩm',
    kitchenLabel: 'Tem báo bếp',
    kitchenSlip: 'Phiếu chế biến',
    kitchenVoid: 'Phiếu hủy bếp',
    stockCount: 'Kiểm kho',
    cashReceipt: 'Phiếu thu',
    cashPayment: 'Phiếu chi',
  };
}
