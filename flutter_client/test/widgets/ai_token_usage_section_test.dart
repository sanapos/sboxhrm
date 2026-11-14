import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/ai_token_usage_section.dart';
import 'package:zkteco_flutter_client/services/ai_token_usage_api.dart';

/// «Token AI đã dùng»: chủ quán phải thấy ngay tốn bao nhiêu và tính năng nào ngốn nhất,
/// với tên tính năng đọc được chứ không phải đường dẫn API.
class _FakeApi extends AiTokenUsageApi {
  _FakeApi(this.payload);

  final Map<String, dynamic> payload;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> report({int days = 30}) async {
    calls++;
    return {'isSuccess': true, 'data': payload};
  }
}

Map<String, dynamic> _payload() => {
      'totals': {
        'calls': 3,
        'promptTokens': 7184,
        'answerTokens': 11,
        'thoughtTokens': 114,
        'totalTokens': 7309,
      },
      'byDay': [
        {'key': '2026-11-13', 'calls': 1, 'totalTokens': 124},
        {'key': '2026-11-14', 'calls': 2, 'totalTokens': 7185},
      ],
      'byFeature': [
        {'key': '/api/ai/assistant/chat', 'calls': 2, 'totalTokens': 7185},
        {'key': '/api/pos/ai/menu/scan', 'calls': 1, 'totalTokens': 124},
      ],
      'byModel': [
        {'key': 'gemini-3.8-flash', 'calls': 2, 'totalTokens': 7185},
        {'key': 'gemini-flash-lite-latest', 'calls': 1, 'totalTokens': 124},
      ],
    };

Future<_FakeApi> _pump(WidgetTester tester, Map<String, dynamic> payload) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _FakeApi(payload);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(child: AiTokenUsageSection(api: api)),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('Hiện tổng token, phần suy nghĩ và tên tính năng đọc được', (tester) async {
    final api = await _pump(tester, _payload());

    expect(api.calls, 1);
    // Tổng và số lượt.
    expect(find.text('7.309'), findsOneWidget);
    expect(find.textContaining('3 lượt gọi'), findsOneWidget);
    // Token suy nghĩ hiện riêng — đây là phần tốn tiền mà không thấy trong câu trả lời.
    expect(find.text('Suy nghĩ'), findsOneWidget);
    expect(find.text('114'), findsOneWidget);
    // Đường dẫn API phải được đổi thành tên tính năng.
    expect(find.text('Trợ lý AI'), findsOneWidget);
    expect(find.text('Thêm menu bằng ảnh'), findsOneWidget);
    expect(find.textContaining('/api/ai/assistant/chat'), findsNothing);
    // Ngày hiện dạng ngắn.
    expect(find.text('14/11'), findsOneWidget);
    expect(find.text('gemini-3.8-flash'), findsOneWidget);
  });

  testWidgets('Đổi khoảng ngày thì tải lại số liệu', (tester) async {
    final api = await _pump(tester, _payload());

    await tester.tap(find.text('7 ngày'));
    await tester.pumpAndSettle();
    expect(api.calls, 2);
  });

  testWidgets('Chưa gọi AI lần nào: nói rõ chưa có số liệu', (tester) async {
    await _pump(tester, {
      'totals': {'calls': 0, 'promptTokens': 0, 'answerTokens': 0, 'thoughtTokens': 0, 'totalTokens': 0},
      'byDay': [],
      'byFeature': [],
      'byModel': [],
    });

    expect(find.textContaining('Chưa có lượt gọi AI nào'), findsOneWidget);
    expect(find.text('Suy nghĩ'), findsNothing);
  });
}
