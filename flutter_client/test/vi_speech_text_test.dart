import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/utils/vi_speech_text.dart';

void main() {
  test('Tiền, giờ, ngày, %, viết tắt đọc thành chữ', () {
    expect(ViSpeechText.normalize('Doanh thu 1.500.000đ'), 'Doanh thu 1 triệu 500 nghìn đồng');
    expect(ViSpeechText.normalize('Vào ca 08:00, ra 17:30'), 'Vào ca 8 giờ, ra 17 giờ 30');
    expect(ViSpeechText.normalize('Ngày 03/10/2026'), 'Ngày 3 tháng 10 năm 2026');
    expect(ViSpeechText.normalize('Hạn 05/11'), 'Hạn ngày 5 tháng 11');
    expect(ViSpeechText.normalize('Đạt 85%'), 'Đạt 85 phần trăm');
    expect(ViSpeechText.normalize('Có 3 NV đi trễ'), 'Có 3 nhân viên đi trễ');
    expect(ViSpeechText.normalize('NVA giữ nguyên'), 'NVA giữ nguyên');
  });
}
