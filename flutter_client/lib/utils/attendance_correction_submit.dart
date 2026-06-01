import '../services/api_service.dart';

import 'attendance_correction_privilege.dart';

import 'attendance_correction_dates.dart';

import 'attendance_record_resolver.dart';



/// Xóa chấm công: luôn tạo phiếu trước (kể cả admin tự duyệt) để hiện trong Duyệt chấm công.

/// Không xóa thẳng log khi tạo phiếu thất bại (tránh lỗi GUID cũ / message tiếng Anh từ API cũ).

/// [attendanceId] có thể thiếu — API resolve theo PIN + oldDate/oldTime.

Future<Map<String, dynamic>> submitAttendanceDelete({

  required ApiService api,

  required bool expectedDirect,

  required String? attendanceId,

  required Future<Map<String, dynamic>> Function() createCorrection,

}) async {
  // Admin / áp dụng ngay: xóa thẳng theo GUID trước (tránh lệch giờ hiển thị vs DB).
  if (expectedDirect && isValidAttendanceGuid(attendanceId)) {
    final direct = await api.deleteAttendanceResult(attendanceId!);
    if (direct['isSuccess'] == true) {
      return {...direct, 'directDelete': true};
    }
  }

  final correction = await createCorrection();

  final correctionId = extractCorrectionRequestId(correction);



  if (correction['isSuccess'] == true) {

    return correction;

  }



  if (correctionId != null) {
    await api.deleteAttendanceCorrection(correctionId);
  }

  // Phiếu thất bại nhưng có GUID hợp lệ → thử xóa trực tiếp (admin / quyền Delete Attendance).
  if (isValidAttendanceGuid(attendanceId)) {
    final direct = await api.deleteAttendanceResult(attendanceId!);
    if (direct['isSuccess'] == true) {
      return {...direct, 'directDelete': true};
    }
  }

  return correction;

}


