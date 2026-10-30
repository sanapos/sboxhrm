import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/comm_v2.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_common.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_editor.dart';
import 'package:zkteco_flutter_client/screens/comm/comm_hub_screen.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Truyền thông nội bộ» (id: communication).
/// Dữ liệu mẫu giống test/comm_hub_test.dart.

final _now = DateTime.now().toUtc();
String _ago(int hours) => _now.subtract(Duration(hours: hours)).toIso8601String().replaceAll('Z', '');

final _channels = [
  {'id': 'c1', 'key': 'feed', 'name': 'Bảng tin', 'icon': 'home', 'color': '#158DC0', 'canPost': true, 'unread': 2, 'isSystem': true},
  {'id': 'c2', 'key': 'announcement', 'name': 'Thông báo', 'icon': 'campaign', 'color': '#DC2626', 'canPost': true, 'unread': 1, 'isSystem': true, 'postPolicy': 1},
  {'id': 'c3', 'key': 'policy', 'name': 'Nội quy & chính sách', 'icon': 'gavel', 'color': '#7C3AED', 'canPost': true, 'unread': 1, 'isSystem': true, 'postPolicy': 1},
  {'id': 'c4', 'key': 'hr', 'name': 'Nhân sự', 'icon': 'badge', 'color': '#0891B2', 'canPost': true, 'isSystem': true},
  {'id': 'c5', 'key': 'event', 'name': 'Sự kiện', 'icon': 'event', 'color': '#D97706', 'canPost': true, 'isSystem': true},
  {'id': 'c6', 'key': 'training', 'name': 'Đào tạo', 'icon': 'school', 'color': '#16A34A', 'canPost': true, 'isSystem': true},
  {'id': 'c7', 'key': 'culture', 'name': 'Văn hóa', 'icon': 'celebration', 'color': '#DB2777', 'canPost': true, 'isSystem': true},
  {'id': 'c8', 'key': 'docs', 'name': 'Tài liệu', 'icon': 'folder', 'color': '#475569', 'canPost': true, 'isSystem': true},
];

final _policy = {
  'id': 'p1', 'channelId': 'c3', 'channelName': 'Nội quy & chính sách', 'channelColor': '#7C3AED', 'type': 3,
  'title': 'Quy định chấm công và nghỉ phép 2026 (bản 3)',
  'summary': 'Đi trễ quá 15 phút tính nửa công; phép năm cộng dồn tối đa 5 ngày; xin nghỉ trước 48 giờ qua ứng dụng.',
  'contentHtml': '<h2>Phạm vi áp dụng</h2><p>Toàn bộ nhân viên chính thức và thử việc, hiệu lực từ <strong>01/10/2026</strong>.</p>'
      '<h2>Điểm chính</h2><ul><li>Đi trễ quá 15 phút tính <strong>nửa công</strong>.</li><li>Phép năm cộng dồn tối đa 5 ngày.</li><li>Xin nghỉ trước 48 giờ qua ứng dụng.</li></ul>'
      '<blockquote>Mọi thắc mắc liên hệ phòng Nhân sự – máy lẻ 102.</blockquote>',
  'contentFormat': 'html', 'priority': 2, 'status': 2, 'authorId': 'u1', 'authorName': 'Phòng Nhân sự', 'publishedAt': _ago(2),
  'createdAt': _ago(2), 'isPinned': true, 'requireAck': true, 'ackDeadline': _ago(-72), 'version': 3, 'allowComments': true,
  'attachments': [
    {'url': '/f/quy-dinh.pdf', 'name': 'Quy-dinh-cham-cong-2026.pdf', 'kind': 'pdf', 'size': 845000},
    {'url': '/f/bang-phat.xlsx', 'name': 'Bang-muc-phat.xlsx', 'kind': 'excel', 'size': 32000},
  ],
  'views': 31, 'reactionTotal': 12, 'reactions': {'0': 10, '4': 2}, 'comments': 3, 'ackCount': 18, 'audienceCount': 25,
  'myRead': true, 'myAcked': false, 'canEdit': true, 'isAiGenerated': true, 'tags': 'nội quy, chấm công',
};

final _event = {
  'id': 'p2', 'channelId': 'c5', 'channelName': 'Sự kiện', 'channelColor': '#D97706', 'type': 2,
  'title': 'Team building Vũng Tàu 2 ngày 1 đêm', 'summary': 'Cả công ty đi Vũng Tàu cuối tháng 10. Bình chọn hoạt động bạn thích nhất nhé!',
  'contentHtml': '<p>Cả công ty đi Vũng Tàu cuối tháng 10.</p>', 'contentFormat': 'html', 'priority': 1, 'status': 2,
  'authorId': 'u2', 'authorName': 'Nguyễn Lan', 'publishedAt': _ago(20), 'createdAt': _ago(20), 'allowComments': true,
  'eventAt': _ago(-24 * 30), 'eventLocation': 'Resort Lan Rừng, Vũng Tàu', 'version': 1,
  'poll': {
    'question': 'Hoạt động bạn thích nhất?', 'multiple': false, 'totalVoters': 17, 'myVotes': ['o1'],
    'options': [{'id': 'o1', 'text': 'Team games trên biển', 'votes': 9}, {'id': 'o2', 'text': 'Gala dinner', 'votes': 6}, {'id': 'o3', 'text': 'Tự do tắm biển', 'votes': 2}],
  },
  'views': 40, 'reactionTotal': 24, 'reactions': {'0': 14, '1': 6, '2': 4}, 'comments': 8, 'myReaction': 2, 'canEdit': false,
  'latestComments': [
    {'id': 'c1', 'userId': 'u7', 'userName': 'Phạm Tú', 'content': 'Đăng ký team games nhé mọi người!', 'createdAt': _ago(3), 'likeCount': 4},
    {'id': 'c2', 'userId': 'u8', 'userName': 'Lê Hà', 'content': 'Có cho mang người nhà không ạ?', 'createdAt': _ago(1), 'myLiked': true, 'likeCount': 1, 'edited': true},
  ],
};

final _culture = {
  'id': 'p3', 'channelId': 'c7', 'channelName': 'Văn hóa', 'channelColor': '#DB2777', 'type': 5,
  'title': '', 'summary': 'Chúc mừng sinh nhật 3 bạn tháng 9! Cảm ơn cả team đã cùng về đích doanh số quý 3.',
  'contentHtml': '<p>Chúc mừng sinh nhật 3 bạn tháng 9! Cảm ơn cả team đã cùng về đích doanh số quý 3.</p>', 'contentFormat': 'html',
  'priority': 1, 'status': 2, 'authorId': 'u3', 'authorName': 'Trần Minh', 'publishedAt': _ago(30), 'createdAt': _ago(30),
  'images': ['/img/1.jpg', '/img/2.jpg', '/img/3.jpg', '/img/4.jpg'], 'allowComments': true, 'version': 1,
  'views': 28, 'reactionTotal': 31, 'reactions': {'1': 20, '2': 11}, 'comments': 12, 'canEdit': false,
};

final _api = guideApi({
  '/v2/channels': _channels,
  '/v2/feed': {'items': [_policy, _event, _culture], 'totalCount': 3},
  '/v2/sidebar': {
    'requiredPending': 2,
    'required': [{'id': 'p1', 'title': 'Quy định chấm công và nghỉ phép 2026'}, {'id': 'p9', 'title': 'Chính sách bảo mật thông tin khách hàng'}],
    'openPolls': 1,
    'events': [{'id': 'p2', 'title': 'Team building Vũng Tàu', 'at': _ago(-24 * 30)}, {'id': 'p8', 'title': 'Đào tạo an toàn thực phẩm', 'at': _ago(-24 * 8)}],
    'birthdays': [{'name': 'Lê Hà', 'date': _ago(-24)}, {'name': 'Phạm Tú', 'date': _ago(-72)}],
    'pendingApproval': 1,
  },
});

final _ctx = CommContext(
  isManager: true,
  channels: _channels.map(CommChannel.fromJson).toList(),
  myName: 'Trần Quân',
  people: const [CommPerson(employeeId: 'e1', userId: 'u5', name: 'Lê Tú', position: 'Thu ngân')],
);

/// Màn soạn bài dùng quill — khung app của kit không có bản địa hóa quill nên bổ sung tại chỗ.
Widget _editor() => Builder(
      builder: (c) => Localizations.override(
        context: c,
        delegates: const [quill.FlutterQuillLocalizations.delegate],
        child: CommEditorPage(ctx: _ctx, initialChannelId: 'c2'),
      ),
    );

const _crumbs = ['Truyền thông'];

/// Cả dòng thiết lập (ListTile / SwitchListTile) chứa chữ [label].
Finder _tile(String label) => find
    .ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ListTile || w is SwitchListTile || w is CheckboxListTile))
    .first;

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = size.width < 600;

    testWidgets('communication-1$suffix: bảng tin, kênh, viết bài', (t) async {
      await guideShot(
        t,
        name: 'communication-1$suffix',
        screen: CommHubScreen(debugContext: _ctx),
        api: _api,
        crumbs: _crumbs,
        size: size,
        marks: [
          GuideMark(1, [mobile ? find.byTooltip('Viết bài').first : find.text('Chia sẻ điều gì đó với mọi người…')], pad: 10),
          GuideMark(2, mobile
              ? [find.widgetWithText(ChoiceChip, 'Tất cả').first, find.textContaining('Thông báo ·').first]
              : [find.text('Kênh').first, find.text('Tài liệu').first]),
        ],
      );
    });

    testWidgets('communication-2$suffix: soạn bài, chọn người nhận, ghim', (t) async {
      await guideShot(
        t,
        name: 'communication-2$suffix',
        screen: _editor(),
        api: _api,
        crumbs: [..._crumbs, 'Tạo bài viết'],
        size: size,
        act: (t) async {
          await t.enterText(find.byType(TextField).first, 'Lịch nghỉ Tết Dương lịch 2027');
          // Bỏ chọn ô tiêu đề — còn chọn thì khung tự cuộn ngược về con trỏ.
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pump();
          // Kéo «Thiết lập đăng» lên gần đầu màn.
          final pos = Scrollable.of(t.element(find.text('Thiết lập đăng'))).position;
          final top = t.getTopLeft(find.text('Thiết lập đăng')).dy;
          pos.jumpTo((pos.pixels + top - 140).clamp(0.0, pos.maxScrollExtent));
          await t.pump();
        },
        marks: [
          GuideMark(1, [_tile('Người nhận')]),
          GuideMark(2, [_tile('Bắt buộc đọc và xác nhận')]),
          GuideMark(3, [_tile('Ghim lên đầu bảng tin')]),

        ],
      );
    });

    testWidgets('communication-3$suffix: nhân viên đọc và xác nhận', (t) async {
      await guideShot(
        t,
        name: 'communication-3$suffix',
        screen: CommHubScreen(debugContext: _ctx),
        api: _api,
        crumbs: _crumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Tôi đã đọc và cam kết'), alignment: 0.6);
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tôi đã đọc và cam kết'))]),
          if (!mobile) GuideMark(2, [find.text('Cần bạn xử lý')]),
        ],
      );
    });
  }
}
