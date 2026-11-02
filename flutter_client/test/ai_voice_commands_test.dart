import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/ai_voice_commands.dart';

void main() {
  AiVoiceCommandKind? kind(String s) => AiVoiceCommand.parse(s)?.kind;

  test('xác nhận bằng nhiều cách nói', () {
    for (final s in ['Xác nhận', 'ừ xác nhận đi em', 'Đồng ý', 'ok', 'Lưu đi', 'đúng rồi', 'Dạ', 'chốt luôn', 'xac nhan']) {
      expect(kind(s), AiVoiceCommandKind.confirm, reason: s);
    }
  });

  test('bỏ / hoàn tác / dừng', () {
    expect(kind('Bỏ đi'), AiVoiceCommandKind.discard);
    expect(kind('không, bỏ qua'), AiVoiceCommandKind.discard);
    expect(kind('ok bỏ đi'), isNull, reason: 'vừa đồng ý vừa bỏ → để AI hiểu');
    expect(kind('Không'), AiVoiceCommandKind.discard);
    expect(kind('Hoàn tác'), AiVoiceCommandKind.undo);
    expect(kind('Dừng lại'), AiVoiceCommandKind.stop);
    expect(kind('tạm biệt'), AiVoiceCommandKind.stop);
  });

  test('«dừng» không bị hiểu thành «đúng»', () {
    expect(kind('dừng'), AiVoiceCommandKind.stop);
    expect(kind('đúng'), AiVoiceCommandKind.confirm);
  });

  test('chọn thẻ theo số', () {
    expect(AiVoiceCommand.parse('xác nhận thẻ 2')?.index, 2);
    expect(AiVoiceCommand.parse('xác nhận cái thứ hai')?.index, 2);
    expect(AiVoiceCommand.parse('bỏ phiếu đầu tiên')?.index, 1);
    expect(AiVoiceCommand.parse('xác nhận')?.index, isNull);
  });

  test('chắc chắn cho thẻ rủi ro cao', () {
    expect(AiVoiceCommand.parse('chắc chắn xác nhận')?.sure, isTrue);
    expect(AiVoiceCommand.parse('xác nhận')?.sure, isFalse);
  });

  test('câu có nội dung vẫn gửi AI', () {
    for (final s in ['ừ, 500k thôi', 'xác nhận giúp tôi doanh thu hôm nay bao nhiêu', 'Phạt An 50k đi trễ', 'không phải An, là Bình',
      'đồng ý nhưng đổi thành 3 ngày']) {
      expect(AiVoiceCommand.parse(s), isNull, reason: s);
    }
  });
}
