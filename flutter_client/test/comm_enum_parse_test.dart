import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/comm_v2.dart';

/// Máy chủ trả enum dạng TÊN («Published»); bản cũ đọc số → mọi bài thành «Nháp», lưu xong văng lỗi.
void main() {
  test('commStatusOf đọc được cả tên lẫn số', () {
    expect(commStatusOf('Published'), CommStatus.published);
    expect(commStatusOf('PendingApproval'), CommStatus.pendingApproval);
    expect(commStatusOf('Scheduled'), CommStatus.scheduled);
    expect(commStatusOf('draft'), CommStatus.draft);
    expect(commStatusOf(2), CommStatus.published);
    expect(commStatusOf(null), CommStatus.draft);
    expect(commStatusOf('KhongCo'), CommStatus.draft);
  });

  test('CommPost.fromJson với enum dạng chuỗi', () {
    final p = CommPost.fromJson({
      'id': '1',
      'title': 'Thông báo',
      'content': '<p>x</p>',
      'type': 'Announcement',
      'priority': 'Urgent',
      'status': 'Published',
    });
    expect(p.status, CommStatus.published);
    expect(p.priority, 3);
  });
}
