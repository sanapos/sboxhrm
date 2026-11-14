import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zkteco_flutter_client/screens/ai_action_log_screen.dart';
import 'package:zkteco_flutter_client/screens/ai_settings_screen.dart';
import 'package:zkteco_flutter_client/widgets/ai_assistant_sheet.dart';

import 'guide_shot_kit.dart';

/// Ảnh cho bước hướng dẫn «Trợ lý ảo AI» (id: ai_assistant).
///
/// Hộp trợ lý gọi /api/ai/assistant/chat/stream trước, hỏng thì lùi về /chat —
/// ở đây stream trả 404 để luôn đi đường /chat, và /chat trả phản hồi mẫu có
/// ĐÚNG hình dạng máy chủ thật trả về (reply + charts + pendingActions + guides),
/// kiểm bằng cách gọi API QA thật ngày 14/11/2026. Số liệu thay bằng dữ liệu
/// quán Cơm Gà Nam cho khớp các ảnh hướng dẫn khác.

const _revenueReply = '''Doanh thu 7 ngày qua (từ 08/11/2026 đến 14/11/2026):

• Tổng doanh thu: 48.650.000đ với 412 đơn hàng (trung bình 118.000đ/đơn).
• Lợi nhuận gộp: 21.400.000đ (biên lãi 44%).
• So với kỳ trước: doanh thu tăng 12,4% (từ 43.280.000đ với 377 đơn).
• Ngày cao nhất là thứ Bảy 14/11 (9.120.000đ), thấp nhất là thứ Ba 10/11 (5.340.000đ).

Gợi ý hành động:
• Giữ mức nhân sự cuối tuần như hiện tại, thứ Ba và thứ Tư có thể xếp ít người hơn.
• Món Cơm gà xối mỡ chiếm 31% doanh thu — nên kiểm tra tồn nguyên liệu trước cuối tuần.''';

const _guideReply = '''• Hướng dẫn kết nối máy chấm công ZKTeco qua Internet (ADMS):
• Bước 1 — Trên máy ZKTeco: vào Thiết lập liên kết › Máy chủ đám mây.
• Bước 2 — Nhập địa chỉ máy chủ và cổng theo hướng dẫn.
• Bước 3 — Lưu và khởi động lại máy nếu máy yêu cầu. Máy phải gọi về máy chủ trước thì hệ thống mới nhận số serial.
• Bước 4 — Trên phần mềm: vào Thiết lập SBOX › Máy chấm công › Thêm thiết bị, nhập Serial Number, bấm Kiểm tra Serial và đặt tên máy.
• Bước 5 — Kiểm tra trạng thái Online trên danh sách máy, rồi cho nhân viên chấm thử và xem ở màn hình Chấm công thô.
Mẹo: máy đời cũ không có menu Máy chủ đám mây thì phải dùng Gateway WiFi.''';

Map<String, Object?> _ok(Map<String, Object?> data) => {'isSuccess': true, 'data': data};

Map<String, Object?> _answer(
  String reply, {
  List<Object?> charts = const [],
  List<Object?> pending = const [],
  List<String> guides = const [],
  List<String> reports = const [],
  List<String> actions = const [],
}) =>
    _ok({
      'reply': reply,
      'provider': 'gemini',
      'actions': actions,
      'creates': const [],
      'guides': guides,
      'reports': reports,
      'pendingActions': pending,
      'charts': charts,
      'exportId': null,
      'autoOpen': null,
    });

final _revenue = _answer(
  _revenueReply,
  reports: const ['Phân tích kinh doanh', 'Doanh thu'],
  actions: const ['nav_pos_reports'],
  charts: const [
    {
      'type': 'bar',
      'title': 'Doanh thu 7 ngày qua',
      'labels': ['08/11', '09/11', '10/11', '11/11', '12/11', '13/11', '14/11'],
      'values': [6480000, 6210000, 5340000, 5890000, 7260000, 8350000, 9120000],
      'openModule': 'PosSalesReport',
    }
  ],
);

final _reward = _answer(
  'Đã lập phiếu thưởng 100.000đ cho nhân viên Trần Thị Lan (mã NV02) với lý do vì làm tốt. '
  'Vui lòng bấm Xác nhận trên thẻ để hoàn tất.',
  pending: const [
    {
      'id': 'pa1',
      'kind': 'reward',
      'title': 'Phiếu thưởng',
      'lines': [
        {'label': 'Nhân viên', 'value': 'Trần Thị Lan'},
        {'label': 'Số tiền', 'value': '100.000đ'},
        {'label': 'Lý do', 'value': 'Vì làm tốt'},
        {'label': 'Ngày', 'value': '14/11/2026'},
        {'label': 'Tính vào lương', 'value': 'tháng 11/2026'},
      ],
      'warnings': [],
      'openModule': 'BonusPenalty',
      'risk': 'normal',
    }
  ],
);

final _guide = _answer(_guideReply, guides: const ['basic/device_connect']);

/// Câu trả lời cho lần gửi thứ n (theo thứ tự các test gọi).
Map<String, Object?>? _next;

final _aiConfig = _ok({
  'enabled': true,
  'model': 'gemini-flash-latest',
  'maxOutputTokens': 2048,
  'temperature': 0.7,
  'isConfigured': true,
  'sharedAllowed': true,
  'sharedAvailable': true,
  'apiKeys': ['AIza************7f3a', 'AIza************b19c'],
  'keyStatus': const [],
});

String _logTime(Duration ago) => DateTime.now().toUtc().subtract(ago).toIso8601String();

final _actionLog = _ok({
  'items': [
    {
      'id': 'a1', 'kind': 'reward', 'title': 'Phiếu thưởng — Trần Thị Lan 100.000đ', 'status': 'done',
      'createdAt': _logTime(const Duration(minutes: 8)), 'userName': 'Nguyễn Văn Hùng',
      'prompt': 'Thưởng 100 nghìn cho Trần Thị Lan vì làm tốt', 'resultMessage': 'Đã lưu phiếu thưởng',
      'docNo': 'TP-0042', 'highRisk': false,
    },
    {
      'id': 'a2', 'kind': 'penalty', 'title': 'Phiếu phạt đi trễ — Lê Văn Minh 50.000đ', 'status': 'done',
      'createdAt': _logTime(const Duration(hours: 3)), 'userName': 'Nguyễn Văn Hùng',
      'prompt': 'Phạt Minh 50k đi trễ hôm nay', 'resultMessage': 'Đã lưu phiếu phạt',
      'docNo': 'PP-0117', 'highRisk': false,
    },
    {
      'id': 'a3', 'kind': 'leave', 'title': 'Đơn nghỉ phép — Phạm Thị Hoa 15/11', 'status': 'undone',
      'createdAt': _logTime(const Duration(hours: 20)), 'userName': 'Phạm Thị Hoa',
      'prompt': 'Mai tôi xin nghỉ ca tối', 'resultMessage': 'Đã hoàn tác theo yêu cầu',
      'docNo': '', 'highRisk': false,
    },
    {
      'id': 'a4', 'kind': 'cancel', 'title': 'Hủy đơn hàng HD-0391', 'status': 'discarded',
      'createdAt': _logTime(const Duration(days: 1, hours: 2)), 'userName': 'Nguyễn Văn Hùng',
      'prompt': 'Hủy đơn HD-0391', 'resultMessage': 'Người dùng bỏ thẻ, không ghi',
      'docNo': 'HD-0391', 'highRisk': true,
    },
  ],
});

MockClient _api() => MockClient((req) async {
      final p = req.url.path;
      Map<String, Object?> body;
      if (p.endsWith('/api/ai/assistant/chat/stream')) {
        // Máy chủ cũ không có luồng → hộp trợ lý lùi về /chat.
        return http.Response('{"isSuccess":false}', 404, headers: {'content-type': 'application/json; charset=utf-8'});
      } else if (p.endsWith('/api/ai/assistant/chat')) {
        body = _next ?? _ok({'reply': '', 'provider': 'gemini'});
      } else if (p.contains('/api/ai/assistant/store-profile')) {
        body = _ok({'profile': ''});
      } else if (p.contains('/api/communications/ai/config')) {
        body = _aiConfig;
      } else if (p.contains('/api/ai/assistant/actions/recent')) {
        body = _actionLog;
      } else {
        body = {'isSuccess': true, 'data': []};
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json; charset=utf-8'});
    });

/// speech_to_text / flutter_tts / record / audioplayers không có bản cho test —
/// trả lời rỗng để initState không ném MissingPluginException.
void _silencePlugins(WidgetTester t) {
  const names = [
    'plugin.csdcorp.com/speech_to_text',
    'flutter_tts',
    'com.llfbandit.record/messages',
    'xyz.luan/audioplayers',
    'xyz.luan/audioplayers.global',
  ];
  for (final n in names) {
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(n), (c) async {
      if (c.method == 'initialize' || c.method == 'has_permission') return false;
      if (c.method == 'getLanguages' || c.method == 'getVoices' || c.method == 'locales') return <Object?>[];
      return null;
    });
  }
  // audioplayers mở EventChannel theo playerId ngẫu nhiên — không đặt mock theo tên được,
  // nên bỏ qua lỗi thiếu plugin ngay tại nguồn (lỗi khác vẫn báo như thường).
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exception is MissingPluginException) return;
    // Màn «Nhật ký thao tác AI» bọc ExpansionTile trong Container có màu nền → Flutter cảnh báo
    // «ListTile background color or ink splashes may be invisible». Chỉ là hiệu ứng gợn sóng khi
    // bấm, ảnh chụp không đổi; đáng sửa trong app nhưng không chặn việc chụp ảnh hướng dẫn.
    if (d.exception.toString().contains('ListTile background color')) return;
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

/// Dựng lại đúng cảnh người dùng thấy: hộp trợ lý là bottom sheet trên nền mờ tối,
/// bề ngang tối đa như showAiAssistant (760) — để cả bề ngang màn thì bong bóng chat
/// kéo dài hết màn, không giống app thật.
Widget _sheet() => Scaffold(
      backgroundColor: const Color(0xFFE2E8F0),
      body: Stack(children: [
        const Positioned.fill(child: ColoredBox(color: Color(0x8A000000))),
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            // Màn hẹp (điện thoại) thì hộp chiếm cả bề ngang, máy tính dừng ở 760 như app.
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: const SizedBox.expand(child: AiAssistantSheet()),
            ),
          ),
        ),
      ]),
    );

/// Lần đầu mở trợ lý trên app (không phải web) có hộp thoại «Thông tin quyền riêng tư»
/// phủ lên — phải bấm «Đồng ý», nếu không nó che hộp trợ lý và chặn cả nút gửi.
Future<void> _consent(WidgetTester t) async {
  final ok = find.widgetWithText(ElevatedButton, 'Đồng ý');
  if (ok.evaluate().isEmpty) return;
  await t.tap(ok);
  for (var i = 0; i < 8; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 120));
  }
}

/// Gõ [ask] rồi bấm gửi, chờ trả lời [reply] hiện ra.
Future<void> _ask(WidgetTester t, String ask, Map<String, Object?> reply) async {
  await _consent(t);
  _next = reply;
  await t.enterText(find.byType(TextField).last, ask);
  await t.pump();
  await t.tap(find.byIcon(Icons.send_rounded));
  for (var i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await t.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    testWidgets('ai-assistant-1$suffix: mở trợ lý', (t) async {
      AiAssistantSheet.resetSession();
      _silencePlugins(t);
      await guideShot(
        t,
        name: 'ai-assistant-1$suffix',
        screen: _sheet(),
        api: _api(),
        size: size,
        act: _consent,
        marks: [
          GuideMark(1, [find.byType(TextField).last], pad: 6),
          GuideMark(2, [find.byIcon(Icons.mic_none_rounded)], pad: 4),
          GuideMark(3, [find.byIcon(Icons.more_vert_rounded)], pad: 4),
        ],
      );
    });

    testWidgets('ai-assistant-2$suffix: hỏi số liệu', (t) async {
      AiAssistantSheet.resetSession();
      _silencePlugins(t);
      await guideShot(
        t,
        name: 'ai-assistant-2$suffix',
        screen: _sheet(),
        api: _api(),
        size: size,
        act: (t) async => _ask(t, 'Doanh thu 7 ngày qua thế nào?', _revenue),
        marks: [
          GuideMark(1, [find.textContaining('Tổng doanh thu')], pad: 8),
          // Cả khung biểu đồ: tiêu đề ở trên, cột cuối cùng ở dưới.
          GuideMark(2, [find.text('Doanh thu 7 ngày qua'), find.text('14/11')], pad: 10),
          GuideMark(3, [find.textContaining('Báo cáo POS')], pad: 6),
        ],
      );
    });

    testWidgets('ai-assistant-3$suffix: thẻ chờ xác nhận', (t) async {
      AiAssistantSheet.resetSession();
      _silencePlugins(t);
      await guideShot(
        t,
        name: 'ai-assistant-3$suffix',
        screen: _sheet(),
        api: _api(),
        size: size,
        act: (t) async => _ask(t, 'Thưởng 100 nghìn cho Trần Thị Lan vì làm tốt', _reward),
        marks: [
          // Cả thẻ chờ xác nhận: tên phiếu ở trên, dòng cuối cùng ở dưới.
          GuideMark(1, [find.text('Phiếu thưởng'), find.text('tháng 11/2026')], pad: 10),
          GuideMark(2, [find.text('Xác nhận'), find.text('Bỏ')], pad: 6),
        ],
      );
    });

    testWidgets('ai-assistant-5$suffix: thiết lập trợ lý', (t) async {
      _silencePlugins(t);
      await guideShot(
        t,
        name: 'ai-assistant-5$suffix',
        screen: const AiSettingsScreen(canEditOverride: true),
        api: _api(),
        crumbs: const ['Thiết lập SBOX', 'Trợ lý AI'],
        size: size,
        marks: [
          GuideMark(1, [find.textContaining('khóa riêng của cửa hàng')], pad: 8),
          GuideMark(2, [find.textContaining('Hồ sơ cửa hàng')], pad: 8),
        ],
      );
    });

    testWidgets('ai-assistant-6$suffix: nhật ký thao tác', (t) async {
      _silencePlugins(t);
      await guideShot(
        t,
        name: 'ai-assistant-6$suffix',
        screen: const AiActionLogScreen(),
        api: _api(),
        crumbs: const ['Trợ lý ảo', 'Nhật ký thao tác AI'],
        size: size,
        marks: [
          GuideMark(1, [find.textContaining('Phiếu thưởng — Trần Thị Lan')], pad: 8),
          GuideMark(2, [find.textContaining('Hủy đơn hàng')], pad: 8),
        ],
      );
    });

    testWidgets('ai-assistant-4$suffix: hỏi cách dùng', (t) async {
      AiAssistantSheet.resetSession();
      _silencePlugins(t);
      await guideShot(
        t,
        name: 'ai-assistant-4$suffix',
        screen: _sheet(),
        api: _api(),
        size: size,
        act: (t) async => _ask(t, 'Cách kết nối máy chấm công ZKTeco?', _guide),
        marks: [
          GuideMark(1, [find.textContaining('Bước 1')], pad: 8),
          GuideMark(2, [find.textContaining('Kết nối máy chấm công')], pad: 6),
        ],
      );
    });
  }
}
