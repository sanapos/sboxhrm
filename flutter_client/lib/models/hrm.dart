// ==========================================
// lib/models/hrm.dart
// ==========================================

// ============ ENUMS ============
enum AllowanceType { fixed, daily, hourly, perEvent }

enum AdvanceRequestStatus { pending, approved, rejected, cancelled }

enum CorrectionAction { add, edit, delete }

enum CorrectionStatus { pending, approved, rejected }

enum ApprovalStatus { pending, approved, rejected, cancelled, expired }

enum ScheduleRegistrationStatus { pending, approved, rejected }

enum NotificationType {
  info,       // 0 - Backend: Info
  success,    // 1 - Backend: Success
  warning,    // 2 - Backend: Warning
  error,      // 3 - Backend: Error
  approvalRequired, // 4 - Backend: ApprovalRequired
  reminder,   // 5 - Backend: Reminder
  leaveRequest,
  advanceRequest,
  attendanceCorrection,
  scheduleRegistration,
  payslip,
  system
}

// ============ HELPER FUNCTIONS ============
String getAllowanceTypeLabel(AllowanceType type) {
  switch (type) {
    case AllowanceType.fixed:
      return 'Cố định';
    case AllowanceType.daily:
      return 'Theo ngày';
    case AllowanceType.hourly:
      return 'Theo giờ';
    case AllowanceType.perEvent:
      return 'Theo sự kiện';
  }
}

String getAdvanceStatusLabel(AdvanceRequestStatus status) {
  switch (status) {
    case AdvanceRequestStatus.pending:
      return 'Chờ duyệt';
    case AdvanceRequestStatus.approved:
      return 'Đã duyệt';
    case AdvanceRequestStatus.rejected:
      return 'Từ chối';
    case AdvanceRequestStatus.cancelled:
      return 'Đã hủy';
  }
}

String getCorrectionStatusLabel(CorrectionStatus status) {
  switch (status) {
    case CorrectionStatus.pending:
      return 'Chờ duyệt';
    case CorrectionStatus.approved:
      return 'Đã duyệt';
    case CorrectionStatus.rejected:
      return 'Từ chối';
  }
}

String getCorrectionActionLabel(CorrectionAction action) {
  switch (action) {
    case CorrectionAction.add:
      return 'Thêm mới';
    case CorrectionAction.edit:
      return 'Chỉnh sửa';
    case CorrectionAction.delete:
      return 'Xóa';
  }
}

String getNotificationTypeLabel(NotificationType type) {
  switch (type) {
    case NotificationType.info:
      return 'Thông tin';
    case NotificationType.success:
      return 'Thành công';
    case NotificationType.warning:
      return 'Cảnh báo';
    case NotificationType.error:
      return 'Lỗi';
    case NotificationType.approvalRequired:
      return 'Yêu cầu duyệt';
    case NotificationType.reminder:
      return 'Nhắc nhở';
    case NotificationType.leaveRequest:
      return 'Nghỉ phép';
    case NotificationType.advanceRequest:
      return 'Ứng lương';
    case NotificationType.attendanceCorrection:
      return 'Sửa chấm công';
    case NotificationType.scheduleRegistration:
      return 'Đăng ký lịch';
    case NotificationType.payslip:
      return 'Bảng lương';
    case NotificationType.system:
      return 'Hệ thống';
  }
}

// ============ ALLOWANCE MODEL ============
class Allowance {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String name;
  final String? description;
  final AllowanceType type;
  final double amount;
  final DateTime effectiveFrom;
  final DateTime? effectiveTo;
  final bool isActive;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Allowance({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    required this.name,
    this.description,
    required this.type,
    required this.amount,
    required this.effectiveFrom,
    this.effectiveTo,
    required this.isActive,
    required this.createdAt,
    this.updatedAt,
  });

  factory Allowance.fromJson(Map<String, dynamic> json) {
    return Allowance(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeCode: json['employeeCode'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      type: AllowanceType.values[json['type'] ?? 0],
      amount: (json['amount'] ?? 0).toDouble(),
      effectiveFrom: DateTime.parse(json['effectiveFrom']),
      effectiveTo: json['effectiveTo'] != null ? DateTime.parse(json['effectiveTo']) : null,
      isActive: json['isActive'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'employeeId': employeeId,
    'name': name,
    'description': description,
    'type': type.index,
    'amount': amount,
    'effectiveFrom': effectiveFrom.toIso8601String(),
    'effectiveTo': effectiveTo?.toIso8601String(),
  };
}

// ============ ADVANCE REQUEST MODEL ============
class AdvanceRequest {
  final String id;
  final String employeeUserId;
  final String employeeName;
  final String employeeCode;
  final double amount;
  final String? reason;
  final DateTime requestDate;
  final int? forMonth;
  final int? forYear;
  final AdvanceRequestStatus status;
  final String? approvedById;
  final String? approvedByName;
  final DateTime? approvedDate;
  final String? rejectionReason;
  final String? note;
  final bool isPaid;
  final String? paymentMethod;
  final DateTime? paidDate;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final int totalApprovalLevels;
  final int currentApprovalStep;
  final List<ApprovalRecord> approvalRecords;

  AdvanceRequest({
    required this.id,
    required this.employeeUserId,
    required this.employeeName,
    required this.employeeCode,
    required this.amount,
    this.reason,
    required this.requestDate,
    this.forMonth,
    this.forYear,
    required this.status,
    this.approvedById,
    this.approvedByName,
    this.approvedDate,
    this.rejectionReason,
    this.note,
    required this.isPaid,
    this.paymentMethod,
    this.paidDate,
    required this.createdAt,
    this.updatedAt,
    this.totalApprovalLevels = 1,
    this.currentApprovalStep = 0,
    this.approvalRecords = const [],
  });

  factory AdvanceRequest.fromJson(Map<String, dynamic> json) {
    AdvanceRequestStatus parseStatus(dynamic value) {
      if (value == null) return AdvanceRequestStatus.pending;
      if (value is int) {
        if (value >= 0 && value < AdvanceRequestStatus.values.length) {
          return AdvanceRequestStatus.values[value];
        }
        return AdvanceRequestStatus.pending;
      }
      if (value is String) {
        switch (value.toLowerCase()) {
          case 'pending': return AdvanceRequestStatus.pending;
          case 'approved': return AdvanceRequestStatus.approved;
          case 'rejected': return AdvanceRequestStatus.rejected;
          case 'cancelled': return AdvanceRequestStatus.cancelled;
          default: return AdvanceRequestStatus.pending;
        }
      }
      return AdvanceRequestStatus.pending;
    }

    return AdvanceRequest(
      id: json['id'] ?? '',
      employeeUserId: json['employeeUserId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeCode: json['employeeCode'] ?? '',
      amount: (json['amount'] ?? 0).toDouble(),
      reason: json['reason'],
      requestDate: DateTime.parse(json['requestDate'] ?? DateTime.now().toIso8601String()),
      forMonth: json['forMonth'],
      forYear: json['forYear'],
      status: parseStatus(json['status']),
      approvedById: json['approvedById'],
      approvedByName: json['approvedByName'],
      approvedDate: json['approvedDate'] != null ? DateTime.parse(json['approvedDate']) : null,
      rejectionReason: json['rejectionReason'],
      note: json['note'],
      isPaid: json['isPaid'] ?? false,
      paymentMethod: json['paymentMethod'],
      paidDate: json['paidDate'] != null ? DateTime.parse(json['paidDate']) : null,
      createdAt: DateTime.parse(json['createdAt'] ?? DateTime.now().toIso8601String()),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      totalApprovalLevels: json['totalApprovalLevels'] ?? 1,
      currentApprovalStep: json['currentApprovalStep'] ?? 0,
      approvalRecords: json['approvalRecords'] != null
          ? (json['approvalRecords'] as List).map((e) => ApprovalRecord.fromJson(e)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'reason': reason,
    'note': note,
  };
}

// ============ PAYMENT TRANSACTION MODEL (Bonus/Penalty) ============
enum PaymentTransactionStatus { pending, completed, cancelled }

String getPaymentTransactionStatusLabel(PaymentTransactionStatus status) {
  switch (status) {
    case PaymentTransactionStatus.pending: return 'Chờ duyệt';
    case PaymentTransactionStatus.completed: return 'Đã duyệt';
    case PaymentTransactionStatus.cancelled: return 'Đã hủy';
  }
}

class PaymentTransaction {
  final String id;
  final String employeeUserId;
  final String employeeName;
  final String employeeCode;
  final String type; // Bonus, Penalty
  final int? forMonth;
  final int? forYear;
  final DateTime transactionDate;
  final double amount;
  final String? description;
  final String? paymentMethod;
  final PaymentTransactionStatus status;
  final String? performedById;
  final String? note;
  final String? advanceRequestId;
  final String? payslipId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  PaymentTransaction({
    required this.id,
    required this.employeeUserId,
    required this.employeeName,
    required this.employeeCode,
    required this.type,
    this.forMonth,
    this.forYear,
    required this.transactionDate,
    required this.amount,
    this.description,
    this.paymentMethod,
    required this.status,
    this.performedById,
    this.note,
    this.advanceRequestId,
    this.payslipId,
    required this.createdAt,
    this.updatedAt,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    PaymentTransactionStatus parseStatus(dynamic value) {
      if (value == null) return PaymentTransactionStatus.pending;
      final s = value.toString().toLowerCase();
      switch (s) {
        case 'completed': return PaymentTransactionStatus.completed;
        case 'cancelled': return PaymentTransactionStatus.cancelled;
        default: return PaymentTransactionStatus.pending;
      }
    }

    return PaymentTransaction(
      id: json['id']?.toString() ?? '',
      employeeUserId: json['employeeUserId']?.toString() ?? '',
      employeeName: json['employeeName']?.toString() ?? '',
      employeeCode: json['employeeCode']?.toString() ?? '',
      type: json['type']?.toString() ?? 'Bonus',
      forMonth: json['forMonth'] as int?,
      forYear: json['forYear'] as int?,
      transactionDate: DateTime.tryParse(json['transactionDate']?.toString() ?? '') ?? DateTime.now(),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      description: json['description']?.toString(),
      paymentMethod: json['paymentMethod']?.toString(),
      status: parseStatus(json['status']),
      performedById: json['performedById']?.toString(),
      note: json['note']?.toString(),
      advanceRequestId: json['advanceRequestId']?.toString(),
      payslipId: json['payslipId']?.toString(),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt'].toString()) : null,
    );
  }

  bool get isBonus => type == 'Bonus';
  bool get isPenalty => type == 'Penalty';
  double get absoluteAmount => amount.abs();

  String get statusLabel => getPaymentTransactionStatusLabel(status);
}

// ============ APPROVAL RECORD MODEL ============
class ApprovalRecord {
  final String id;
  final int stepOrder;
  final String? stepName;
  final String? assignedUserId;
  final String? assignedUserName;
  final String? actualUserId;
  final String? actualUserName;
  final ApprovalStatus status;
  final String? note;
  final DateTime? actionDate;

  ApprovalRecord({
    required this.id,
    required this.stepOrder,
    this.stepName,
    this.assignedUserId,
    this.assignedUserName,
    this.actualUserId,
    this.actualUserName,
    required this.status,
    this.note,
    this.actionDate,
  });

  factory ApprovalRecord.fromJson(Map<String, dynamic> json) {
    return ApprovalRecord(
      id: json['id']?.toString() ?? '',
      stepOrder: json['stepOrder'] ?? 0,
      stepName: json['stepName'],
      assignedUserId: json['assignedUserId'],
      assignedUserName: json['assignedUserName'],
      actualUserId: json['actualUserId'],
      actualUserName: json['actualUserName'],
      status: ApprovalStatus.values[json['status'] ?? 0],
      note: json['note'],
      actionDate: json['actionDate'] != null ? DateTime.parse(json['actionDate']) : null,
    );
  }
}

// ============ ATTENDANCE CORRECTION REQUEST MODEL ============
class AttendanceCorrectionRequest {
  final String id;
  final String employeeId;
  final String employeeName;
  final String employeeCode;
  final String? attendanceId;
  final CorrectionAction action;
  final DateTime correctionDate;
  final String? originalCheckIn;
  final String? originalCheckOut;
  final String? newCheckIn;
  final String? newCheckOut;
  final String? reason;
  final DateTime requestDate;
  final CorrectionStatus status;
  final String? approvedBy;
  final String? approvedByName;
  final DateTime? approvedAt;
  final String? rejectReason;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? employeeUserId;
  final String? newType;
  final String? approverId;
  final String? approverName;
  final int totalApprovalLevels;
  final int currentApprovalStep;
  final List<ApprovalRecord> approvalRecords;

  AttendanceCorrectionRequest({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.employeeCode,
    this.attendanceId,
    required this.action,
    required this.correctionDate,
    this.originalCheckIn,
    this.originalCheckOut,
    this.newCheckIn,
    this.newCheckOut,
    this.reason,
    required this.requestDate,
    required this.status,
    this.approvedBy,
    this.approvedByName,
    this.approvedAt,
    this.rejectReason,
    required this.createdAt,
    this.updatedAt,
    this.employeeUserId,
    this.newType,
    this.approverId,
    this.approverName,
    this.totalApprovalLevels = 1,
    this.currentApprovalStep = 0,
    this.approvalRecords = const [],
  });

  factory AttendanceCorrectionRequest.fromJson(Map<String, dynamic> json) {
    return AttendanceCorrectionRequest(
      id: json['id'] ?? '',
      employeeId: json['employeeId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeCode: json['employeeCode'] ?? '',
      attendanceId: json['attendanceId'],
      action: CorrectionAction.values[json['action'] ?? 0],
      correctionDate: DateTime.parse(json['correctionDate']),
      originalCheckIn: json['originalCheckIn'],
      originalCheckOut: json['originalCheckOut'],
      newCheckIn: json['newCheckIn'],
      newCheckOut: json['newCheckOut'],
      reason: json['reason'],
      requestDate: DateTime.parse(json['requestDate']),
      status: CorrectionStatus.values[json['status'] ?? 0],
      approvedBy: json['approvedBy'],
      approvedByName: json['approvedByName'],
      approvedAt: json['approvedAt'] != null ? DateTime.parse(json['approvedAt']) : null,
      rejectReason: json['rejectReason'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
      employeeUserId: json['employeeUserId'],
      newType: json['newType'],
      approverId: json['approverId'],
      approverName: json['approverName'],
      totalApprovalLevels: json['totalApprovalLevels'] ?? 1,
      currentApprovalStep: json['currentApprovalStep'] ?? 0,
      approvalRecords: json['approvalRecords'] != null
          ? (json['approvalRecords'] as List).map((e) => ApprovalRecord.fromJson(e)).toList()
          : [],
    );
  }

  Map<String, dynamic> toJson() => {
    'attendanceId': attendanceId,
    'action': action.index,
    'correctionDate': correctionDate.toIso8601String(),
    'newCheckIn': newCheckIn,
    'newCheckOut': newCheckOut,
    'reason': reason,
  };
}

// ============ NOTIFICATION MODEL ============
class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String message;
  final NotificationType type;
  final bool isRead;
  final DateTime? readAt;
  final String? actionUrl;
  final String? relatedEntityId;
  final String? relatedEntityType;
  final String? categoryCode;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    this.readAt,
    this.actionUrl,
    this.relatedEntityId,
    this.relatedEntityType,
    this.categoryCode,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? '',
      userId: json['userId']?.toString() ?? json['targetUserId']?.toString() ?? '',
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      type: _parseNotificationType(json['type']),
      isRead: json['isRead'] ?? false,
      readAt: json['readAt'] != null ? DateTime.parse(json['readAt']) : null,
      actionUrl: json['actionUrl'] ?? json['relatedUrl'],
      relatedEntityId: json['relatedEntityId']?.toString(),
      relatedEntityType: json['relatedEntityType'],
      categoryCode: json['categoryCode']?.toString(),
      createdAt: _parseDateTime(json['createdAt'] ?? json['timestamp']),
    );
  }
  
  static NotificationType _parseNotificationType(dynamic value) {
    if (value == null) return NotificationType.info;
    final intValue = value is int ? value : int.tryParse(value.toString()) ?? 0;
    // Explicit mapping from backend enum (0-5) to avoid index mismatch
    switch (intValue) {
      case 0: return NotificationType.info;
      case 1: return NotificationType.success;
      case 2: return NotificationType.warning;
      case 3: return NotificationType.error;
      case 4: return NotificationType.approvalRequired;
      case 5: return NotificationType.reminder;
      default: return NotificationType.info;
    }
  }
  
  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is DateTime) return value.isUtc ? value.toLocal() : value;
    
    final strValue = value.toString();
    // Server gửi UTC nhưng không có Z suffix, cần thêm Z để parse đúng UTC rồi chuyển local
    final parsed = DateTime.tryParse(strValue.endsWith('Z') ? strValue : '${strValue}Z');
    return parsed?.toLocal() ?? DateTime.now();
  }
}

// ============ SETTINGS MODELS ============
class PenaltySetting {
  final String id;
  final String name;
  final String? description;
  final bool isLatePolicy;
  final int level;
  final int minMinutes;
  final int maxMinutes;
  final double penaltyAmount;
  final bool isPercentage;
  final bool isActive;
  final DateTime createdAt;

  PenaltySetting({
    required this.id,
    required this.name,
    this.description,
    required this.isLatePolicy,
    required this.level,
    required this.minMinutes,
    required this.maxMinutes,
    required this.penaltyAmount,
    required this.isPercentage,
    required this.isActive,
    required this.createdAt,
  });

  factory PenaltySetting.fromJson(Map<String, dynamic> json) {
    return PenaltySetting(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      isLatePolicy: json['isLatePolicy'] ?? true,
      level: json['level'] ?? 1,
      minMinutes: json['minMinutes'] ?? 0,
      maxMinutes: json['maxMinutes'] ?? 0,
      penaltyAmount: (json['penaltyAmount'] ?? 0).toDouble(),
      isPercentage: json['isPercentage'] ?? false,
      isActive: json['isActive'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class InsuranceSetting {
  final String id;
  final String code;
  final String name;
  final String? description;
  final double employeeRate;
  final double employerRate;
  final double? maxSalaryBase;
  final bool isActive;
  final DateTime createdAt;

  InsuranceSetting({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    required this.employeeRate,
    required this.employerRate,
    this.maxSalaryBase,
    required this.isActive,
    required this.createdAt,
  });

  factory InsuranceSetting.fromJson(Map<String, dynamic> json) {
    return InsuranceSetting(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      employeeRate: (json['employeeRate'] ?? 0).toDouble(),
      employerRate: (json['employerRate'] ?? 0).toDouble(),
      maxSalaryBase: json['maxSalaryBase'] != null ? (json['maxSalaryBase']).toDouble() : null,
      isActive: json['isActive'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class TaxSetting {
  final String id;
  final String name;
  final String? description;
  final int level;
  final double minIncome;
  final double? maxIncome;
  final double taxRate;
  final double deductionAmount;
  final bool isActive;
  final DateTime createdAt;

  TaxSetting({
    required this.id,
    required this.name,
    this.description,
    required this.level,
    required this.minIncome,
    this.maxIncome,
    required this.taxRate,
    required this.deductionAmount,
    required this.isActive,
    required this.createdAt,
  });

  factory TaxSetting.fromJson(Map<String, dynamic> json) {
    return TaxSetting(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'],
      level: json['level'] ?? 1,
      minIncome: (json['minIncome'] ?? 0).toDouble(),
      maxIncome: json['maxIncome'] != null ? (json['maxIncome']).toDouble() : null,
      taxRate: (json['taxRate'] ?? 0).toDouble(),
      deductionAmount: (json['deductionAmount'] ?? 0).toDouble(),
      isActive: json['isActive'] ?? false,
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

// ============ WORK SCHEDULE MODEL ============
class WorkSchedule {
  final String id;
  final String employeeUserId;
  final String employeeName;
  final String employeeCode;
  final String? shiftId;
  final String shiftName;
  final String shiftStartTime;
  final String shiftEndTime;
  final DateTime date;
  final String? startTime;
  final String? endTime;
  final bool isDayOff;
  final String? note;
  final String? assignedById;
  final DateTime createdAt;
  final DateTime? updatedAt;

  WorkSchedule({
    required this.id,
    required this.employeeUserId,
    required this.employeeName,
    required this.employeeCode,
    this.shiftId,
    required this.shiftName,
    required this.shiftStartTime,
    required this.shiftEndTime,
    required this.date,
    this.startTime,
    this.endTime,
    required this.isDayOff,
    this.note,
    this.assignedById,
    required this.createdAt,
    this.updatedAt,
  });

  factory WorkSchedule.fromJson(Map<String, dynamic> json) {
    return WorkSchedule(
      id: json['id'] ?? '',
      employeeUserId: json['employeeUserId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeCode: json['employeeCode'] ?? '',
      shiftId: json['shiftId'],
      shiftName: json['shiftName'] ?? '',
      shiftStartTime: json['shiftStartTime'] ?? '00:00:00',
      shiftEndTime: json['shiftEndTime'] ?? '00:00:00',
      date: DateTime.parse(json['date']),
      startTime: json['startTime'],
      endTime: json['endTime'],
      isDayOff: json['isDayOff'] ?? false,
      note: json['note'],
      assignedById: json['assignedById'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'employeeUserId': employeeUserId,
    'shiftId': shiftId,
    'date': date.toIso8601String(),
    'startTime': startTime,
    'endTime': endTime,
    'isDayOff': isDayOff,
    'note': note,
  };
}

// ============ SCHEDULE REGISTRATION MODEL ============
class ScheduleRegistration {
  final String id;
  final String employeeUserId;
  final String employeeName;
  final String employeeCode;
  final DateTime date;
  final String? shiftId;
  final String shiftName;
  final bool isDayOff;
  final String? note;
  final ScheduleRegistrationStatus status;
  final String? approvedById;
  final String? approvedByName;
  final DateTime? approvedDate;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime? updatedAt;

  ScheduleRegistration({
    required this.id,
    required this.employeeUserId,
    required this.employeeName,
    required this.employeeCode,
    required this.date,
    this.shiftId,
    required this.shiftName,
    required this.isDayOff,
    this.note,
    required this.status,
    this.approvedById,
    this.approvedByName,
    this.approvedDate,
    this.rejectionReason,
    required this.createdAt,
    this.updatedAt,
  });

  factory ScheduleRegistration.fromJson(Map<String, dynamic> json) {
    ScheduleRegistrationStatus parseStatus(dynamic v) {
      if (v == null) return ScheduleRegistrationStatus.pending;
      if (v is int) return ScheduleRegistrationStatus.values[v];
      final s = v.toString().toLowerCase();
      if (s == 'approved' || s == '1') return ScheduleRegistrationStatus.approved;
      if (s == 'rejected' || s == '2') return ScheduleRegistrationStatus.rejected;
      return ScheduleRegistrationStatus.pending;
    }

    return ScheduleRegistration(
      id: json['id'] ?? '',
      employeeUserId: json['employeeUserId'] ?? '',
      employeeName: json['employeeName'] ?? '',
      employeeCode: json['employeeCode'] ?? '',
      date: DateTime.parse(json['date']),
      shiftId: json['shiftId'],
      shiftName: json['shiftName'] ?? '',
      isDayOff: json['isDayOff'] ?? false,
      note: json['note'],
      status: parseStatus(json['status']),
      approvedById: json['approvedById'],
      approvedByName: json['approvedByName'],
      approvedDate: json['approvedDate'] != null ? DateTime.parse(json['approvedDate']) : null,
      rejectionReason: json['rejectionReason'],
      createdAt: DateTime.parse(json['createdAt']),
      updatedAt: json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': date.toIso8601String(),
    'shiftId': shiftId,
    'isDayOff': isDayOff,
    'note': note,
  };
}

String getScheduleRegistrationStatusLabel(ScheduleRegistrationStatus status) {
  switch (status) {
    case ScheduleRegistrationStatus.pending:
      return 'Chờ duyệt';
    case ScheduleRegistrationStatus.approved:
      return 'Đã duyệt';
    case ScheduleRegistrationStatus.rejected:
      return 'Từ chối';
  }
}

// ============ SHIFT MODEL ============
class Shift {
  final String id;
  final String name;
  final String code;
  final String startTime;
  final String endTime;
  final int? breakMinutes;
  final String? description;
  final bool isActive;
  final DateTime createdAt;
  final int? earlyCheckInMinutes;
  final int? maximumAllowedLateMinutes;
  final int? maximumAllowedEarlyLeaveMinutes;
  final int? overtimeMinutesThreshold;
  final int? lateGraceMinutes;
  final int? earlyLeaveGraceMinutes;
  final String? shiftType;

  Shift({
    required this.id,
    required this.name,
    required this.code,
    required this.startTime,
    required this.endTime,
    this.breakMinutes,
    this.description,
    required this.isActive,
    required this.createdAt,
    this.earlyCheckInMinutes,
    this.maximumAllowedLateMinutes,
    this.maximumAllowedEarlyLeaveMinutes,
    this.overtimeMinutesThreshold,
    this.lateGraceMinutes,
    this.earlyLeaveGraceMinutes,
    this.shiftType,
  });

  factory Shift.fromJson(Map<String, dynamic> json) {
    // Handle TimeSpan format from backend (e.g., "08:00:00" or "8:00:00")
    String formatTime(dynamic time) {
      if (time == null) return '08:00:00';
      final timeStr = time.toString();
      // If it's already in HH:mm:ss format, return as is
      if (timeStr.contains(':')) {
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00';
        }
      }
      return timeStr;
    }

    return Shift(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      code: json['code'] ?? json['name'] ?? '',
      startTime: formatTime(json['startTime']),
      endTime: formatTime(json['endTime']),
      breakMinutes: json['breakTimeMinutes'] ?? json['breakMinutes'],
      description: json['description'],
      isActive: json['isActive'] ?? true,
      createdAt: json['createdAt'] != null 
        ? DateTime.parse(json['createdAt']) 
        : DateTime.now(),
      earlyCheckInMinutes: json['earlyCheckInMinutes'],
      maximumAllowedLateMinutes: json['maximumAllowedLateMinutes'],
      maximumAllowedEarlyLeaveMinutes: json['maximumAllowedEarlyLeaveMinutes'],
      overtimeMinutesThreshold: json['overtimeMinutesThreshold'],
      lateGraceMinutes: json['lateGraceMinutes'],
      earlyLeaveGraceMinutes: json['earlyLeaveGraceMinutes'],
      shiftType: json['shiftType'],
    );
  }
}
