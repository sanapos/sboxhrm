import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/hrm.dart';
import 'package:zkteco_flutter_client/models/task_v2.dart';

/// API trả enum dạng tên. Đọc sai thành 0 thì dự án tạm dừng thành «đang chạy», mẫu lặp thành «không lặp»
/// và lưu lại sẽ ghi đè giá trị thật trên máy chủ.
void main() {
  test('dự án: trạng thái theo tên và theo số', () {
    TaskProjectStatus read(Object? v) => TaskProjectV2.fromJson({'id': 'p', 'name': 'A', 'status': v}).status;
    expect(read('OnHold'), TaskProjectStatus.onHold);
    expect(read('Archived'), TaskProjectStatus.archived);
    expect(read(2), TaskProjectStatus.completed);
    expect(read(null), TaskProjectStatus.active);
  });

  test('bước duyệt: tên và số đều ra đúng', () {
    expect(approvalStepStatusIndex('Approved'), 1);
    expect(approvalStepStatusIndex('Rejected'), 2);
    expect(approvalStepStatusIndex(3), 3);
    expect(approvalStepStatusIndex(null), 0);
  });

  test('thông báo: loại dạng tên không bị coi là Info', () {
    NotificationType read(Object? v) => AppNotification.fromJson({
          'id': 'n',
          'userId': 'u',
          'title': 't',
          'message': 'm',
          'type': v,
          'isRead': false,
          'createdAt': '2026-11-02T09:36:04.797',
        }).type;
    expect(read('Warning'), NotificationType.warning);
    expect(read('ApprovalRequired'), NotificationType.approvalRequired);
    expect(read('Announcement'), NotificationType.info);
    expect(read(3), NotificationType.error);
  });
}
