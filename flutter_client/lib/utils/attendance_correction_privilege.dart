import '../providers/permission_provider.dart';

bool _isElevatedAttendanceRole(String? role) {
  if (role == null || role.isEmpty) return false;
  const elevated = {'admin', 'director', 'superadmin', 'agent'};
  return elevated.contains(role.toLowerCase());
}

/// Sửa trực tiếp bản ghi chấm công thô (module Attendance).
bool canEditAttendanceRecord({
  required String? role,
  PermissionProvider? permissions,
}) {
  if (_isElevatedAttendanceRole(role)) return true;
  if (permissions == null) return false;
  return permissions.canEdit('Attendance');
}

/// Xóa trực tiếp bản ghi chấm công thô (module Attendance).
bool canDeleteAttendanceRecord({
  required String? role,
  PermissionProvider? permissions,
}) {
  if (_isElevatedAttendanceRole(role)) return true;
  if (permissions == null) return false;
  return permissions.canDelete('Attendance');
}

/// Đồng bộ dữ liệu từ máy chấm công vào bảng chấm công thô.
bool canSyncAttendanceFromDevice({
  required String? role,
  PermissionProvider? permissions,
}) {
  if (_isElevatedAttendanceRole(role)) return true;
  if (permissions == null) return false;
  return permissions.canCreate('Attendance');
}

/// Tài khoản có quyền **nhìn thấy và bấm** nút chỉnh công (tổng hợp / theo ca).
bool canShowCorrectionButtons({
  required String? role,
  required bool allowManualSetting,
  PermissionProvider? permissions,
}) {
  if (_isElevatedAttendanceRole(role)) return true;
  if (permissions == null) return false;
  if (permissions.canApprove('AttendanceCorrection') ||
      permissions.canApprove('AttendanceApproval')) {
    return true;
  }
  if (permissions.canEdit('Attendance') || permissions.canDelete('Attendance')) {
    return true;
  }
  if (permissions.canCreate('AttendanceCorrection')) {
    return allowManualSetting;
  }
  return false;
}

/// Tài khoản quyền cao / có quyền duyệt → backend tự động duyệt khi lưu.
bool canDirectAttendanceCorrection({
  required String? role,
  required bool allowManualSetting,
  PermissionProvider? permissions,
}) {
  if (_isElevatedAttendanceRole(role)) return true;
  if (permissions != null) {
    if (permissions.canApprove('AttendanceCorrection') ||
        permissions.canApprove('AttendanceApproval')) {
      return true;
    }
    if (permissions.canEdit('Attendance') || permissions.canDelete('Attendance')) {
      return true;
    }
  }
  // Không fallback allowManualSetting — setting cho phép gửi phiếu, không tự động duyệt
  return false;
}

bool isAttendanceCorrectionAutoApplied(Map<String, dynamic> apiResult) {
  if (apiResult['isSuccess'] != true) return false;
  if (apiResult['directDelete'] == true) return true;
  final data = apiResult['data'];
  if (data is! Map) return false;
  final status = data['status'];
  if (status == 1 ||
      status == 'Approved' ||
      status == 'approved' ||
      status == 'APPROVED') {
    return true;
  }
  return false;
}

String _mapLegacyAttendanceError(String msg) {
  final lower = msg.toLowerCase();
  if (lower.contains('attendance record not found') ||
      lower.contains('attendance not found')) {
    return 'Không tìm thấy bản ghi chấm công. Kiểm tra PIN/giờ hoặc tải lại dữ liệu rồi thử lại.';
  }
  if (lower == 'user not found') {
    return 'Không tìm thấy tài khoản nhân viên.';
  }
  if (lower.contains('correction request not found')) {
    return 'Không tìm thấy phiếu duyệt chấm công.';
  }
  if (lower.contains('saving the entity changes') ||
      lower.contains('dbupdateexception')) {
    return 'Lỗi lưu dữ liệu khi xóa chấm công (còn liên kết ca/ăn/phạt). Tải lại trang và thử lại.';
  }
  return msg;
}

String attendanceCorrectionErrorMessage(Map<String, dynamic> result) {
  final msg = result['message']?.toString();
  if (msg != null && msg.isNotEmpty) {
    return _mapLegacyAttendanceError(msg);
  }
  final errors = result['errors'];
  if (errors is List && errors.isNotEmpty) {
    return _mapLegacyAttendanceError(
      errors.map((e) => e.toString()).join('; '),
    );
  }
  return 'Gửi yêu cầu thất bại. Vui lòng thử lại.';
}

/// Duyệt tab Chấm công Mobile (gộp trong màn Duyệt chấm công).
bool canApproveMobileAttendance(PermissionProvider permissions) {
  return permissions.canApprove('MobileAttendanceApproval') ||
      permissions.canApprove('AttendanceApproval');
}

bool canViewMobileAttendanceApprovalTab(PermissionProvider permissions) {
  return canApproveMobileAttendance(permissions);
}

String attendanceCorrectionSuccessMessage(
  Map<String, dynamic> apiResult, {
  required bool expectedDirect,
}) {
  if (isAttendanceCorrectionAutoApplied(apiResult)) {
    return 'Đã áp dụng (tự động duyệt). Mở Duyệt chấm công → Tất cả hoặc Đã duyệt → lọc hành động Xóa.';
  }
  if (expectedDirect) {
    return 'Đã gửi yêu cầu — chờ duyệt (tài khoản chưa đủ quyền tự duyệt)';
  }
  return 'Đã gửi yêu cầu chấm công thành công';
}
