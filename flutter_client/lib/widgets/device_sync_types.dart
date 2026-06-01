/// Loại dữ liệu tải từ máy chấm công (ZKTeco ADMS).

enum DeviceSyncKind {

  /// commandType 8 — danh sách USER trên máy → bảng DeviceUsers

  deviceUsers,



  /// commandType 7 — log chấm công → bảng Attendances

  attendances,

}



class DeviceSyncTarget {

  final String deviceId;

  final String deviceName;



  /// Khoảng thời gian tải chấm công (tùy chọn — dùng cho DATA QUERY ATTLOG).

  final DateTime? fromTime;

  final DateTime? toTime;



  const DeviceSyncTarget({

    required this.deviceId,

    required this.deviceName,

    this.fromTime,

    this.toTime,

  });

}



class DeviceSyncProgressResult {

  final bool success;



  /// true khi lệnh OK nhưng chưa thấy bản ghi mới (máy chậm / firmware).

  final bool partialSuccess;

  final int recordsAdded;

  final int totalRecords;

  final String message;



  const DeviceSyncProgressResult({

    required this.success,

    this.partialSuccess = false,

    this.recordsAdded = 0,

    this.totalRecords = 0,

    this.message = '',

  });

}


