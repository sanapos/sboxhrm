import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/hrm.dart';

/// Phiếu sửa chấm công đọc đúng dữ liệu API thật: enum dạng tên, mỗi phiếu là một lần chấm.
void main() {
  Map<String, dynamic> api(Map<String, dynamic> over) => {
        'id': 'c1',
        'employeeUserId': 'u1',
        'employeeName': 'Ngân',
        'employeeCode': 'NV1',
        'attendanceId': 'a1',
        'action': 'Add',
        'oldDate': null,
        'oldTime': null,
        'oldType': null,
        'newDate': '2026-10-11T00:00:00.000',
        'newTime': '13:05:00',
        'newPunchType': 'CheckIn',
        'status': 'Approved',
        'createdAt': '2026-11-02T09:36:04.797',
        'approvalRecords': [
          {'id': 'r1', 'stepOrder': 1, 'status': 'Approved'},
        ],
        ...over,
      };

  test('thêm giờ vào: enum dạng tên, ngày và giờ theo phiếu', () {
    final r = AttendanceCorrectionRequest.fromJson(api({}));
    expect(r.action, CorrectionAction.add);
    expect(r.status, CorrectionStatus.approved);
    expect(r.correctionDate, DateTime(2026, 10, 11));
    expect(r.newCheckIn, '13:05');
    expect(r.newCheckOut, isNull);
    expect(r.newType, 'CheckIn');
    expect(r.approvalRecords.single.status, ApprovalStatus.approved);
  });

  test('sửa giờ ra: giờ cũ và giờ mới vào đúng cột', () {
    final r = AttendanceCorrectionRequest.fromJson(api({
      'action': 'Edit',
      'oldDate': '2026-10-10T00:00:00.000',
      'oldTime': '17:30:00',
      'oldType': 'CheckOut',
      'newDate': '2026-10-10T00:00:00.000',
      'newTime': '18:00:00',
      'newPunchType': 'CheckOut',
    }));
    expect(r.action, CorrectionAction.edit);
    expect(r.originalCheckOut, '17:30');
    expect(r.originalCheckIn, isNull);
    expect(r.newCheckOut, '18:00');
  });

  test('xóa không có ngày mới vẫn lấy ngày cũ; từ chối đọc lý do', () {
    final r = AttendanceCorrectionRequest.fromJson(api({
      'action': 'Delete',
      'status': 'Rejected',
      'oldDate': '2026-10-09T00:00:00.000',
      'oldTime': '08:00:00',
      'newDate': null,
      'newTime': null,
      'newPunchType': null,
      'approverNote': 'Sai giờ',
    }));
    expect(r.action, CorrectionAction.delete);
    expect(r.correctionDate, DateTime(2026, 10, 9));
    expect(r.rejectReason, 'Sai giờ');
  });

  test('dữ liệu cũ dạng số vẫn đọc được, giá trị lạ không làm vỡ màn', () {
    final old = AttendanceCorrectionRequest.fromJson(api({'action': 1, 'status': 2}));
    expect(old.action, CorrectionAction.edit);
    expect(old.status, CorrectionStatus.rejected);
    final odd = AttendanceCorrectionRequest.fromJson(api({'action': 'Khac', 'status': 9}));
    expect(odd.action, CorrectionAction.add);
    expect(odd.status, CorrectionStatus.pending);
  });
}
