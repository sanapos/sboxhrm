import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/pos_print_template.dart';
import 'package:zkteco_flutter_client/utils/pos_print_template_loader.dart';

PosPrintTemplate _t(String id, String paper, {bool isDefault = false}) => PosPrintTemplate.fromJson({
      'id': id,
      'name': id,
      'documentType': 'Invoice',
      'paperSize': paper,
      'htmlContent': '',
      'isDefault': isDefault,
      'isActive': true,
    });

/// Chọn mẫu khi in máy nhiệt: mẫu người dùng chọn phải được dùng nếu in vừa khổ máy.
void main() {
  final list = [_t('k80-def', 'K80', isDefault: true), _t('k80-b', 'K80'), _t('k58', 'K58')];

  test('mẫu đã chọn cùng khổ máy được dùng, không bị mẫu mặc định cùng khổ đè', () {
    expect(pickPosPrintTemplateForPaper(list, paperSize: 'K80', templateId: 'k80-b')!.id, 'k80-b');
  });

  test('mẫu K58 đã chọn in được trên máy 80 mm (C20: chọn «HĐ K58» mà vẫn ra K80)', () {
    expect(pickPosPrintTemplateForPaper(list, paperSize: 'K80', templateId: 'k58')!.id, 'k58');
  });

  test('mẫu K80 đã chọn không dùng cho máy 58 mm — lấy mẫu đúng khổ', () {
    expect(pickPosPrintTemplateForPaper(list, paperSize: 'K58', templateId: 'k80-b')!.id, 'k58');
  });

  test('chưa chọn mẫu: theo mặc định đúng khổ như cũ', () {
    expect(pickPosPrintTemplateForPaper(list, paperSize: 'K80')!.id, 'k80-def');
    expect(pickPosPrintTemplateForPaper(list, paperSize: 'K58')!.id, 'k58');
  });

  test('mẫu đã chọn bị xóa: quay về mặc định đúng khổ', () {
    expect(pickPosPrintTemplateForPaper(list, paperSize: 'K80', templateId: 'gone')!.id, 'k80-def');
  });
}
