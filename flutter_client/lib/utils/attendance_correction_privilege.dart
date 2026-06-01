import '../providers/permission_provider.dart';

bool _isElevatedAttendanceRole(String? role) {
  if (role == null || role.isEmpty) return false;
  const elevated = {'admin', 'director', 'superadmin', 'agent'};
  return elevated.contains(role.toLowerCase());
}

/// Tài khoản có quyền **nhìn thấy và bấm** nút chỉnh công.
/// = setting allow_manual_correction bật, HOẶC tài khoản quyền cao luôn được phép.
bool canShowCorrectionButtons({
  required String? role,
  required bool allowManualSetting,
  PermissionProvider? permissions,
}) {
  if (_isElevatedAttendanceRole(role)) return true;
  if (permissions != null) {
    if (permissions.canApprove('AttendanceCorrection') ||
        permissions.canApprove('AttendanceApproval') ||
        permissions.canCreate('AttendanceCorrection')) {
      return true;
    }
  }
  return allowManualSetting;
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
    if (permissions.canEdit('Attendance') && permissions.canDelete('Attendance')) {
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
  return permissions.canView('MobileAttendanceApproval') ||
      permissions.canView('AttendanceApproval') ||
      permissions.canApprove('AttendanceApproval') ||
      permissions.canApprove('MobileAttendanceApproval');
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
