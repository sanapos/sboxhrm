import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/shift_hub/schedule_board_data.dart';

/// Một người làm nhiều ca / ngày: các ca không được chồng giờ — cùng quy tắc máy chủ (WorkScheduleDuplicateHelper).
void main() {
  Map<String, dynamic> t(String id, String start, String end) => {'id': id, 'name': id, 'start': start, 'end': end};

  test('ca trùng giờ tính cả ca qua đêm, ca nối liền không trùng', () {
    final sang = t('sang', '07:00', '11:00');
    final chieu = t('chieu', '13:00', '21:00');
    final trua = t('trua', '10:30', '14:00');
    final noi = t('noi', '11:00', '13:00');
    final dem = t('dem', '22:00', '06:00');
    final som = t('som', '05:00', '08:00');
    final linhHoat = t('lh', '00:00', '00:00');

    expect(BoardData.shiftsOverlap(sang, chieu), isFalse);
    expect(BoardData.shiftsOverlap(sang, trua), isTrue);
    expect(BoardData.shiftsOverlap(sang, noi), isFalse);
    expect(BoardData.shiftsOverlap(dem, som), isTrue);
    expect(BoardData.shiftsOverlap(dem, sang), isFalse);
    expect(BoardData.shiftsOverlap(linhHoat, sang), isFalse);
    expect(BoardData.shiftsOverlap(sang, sang), isTrue);
  });
}
