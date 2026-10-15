import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/models/downloaded_document.dart';
import 'package:zkteco_flutter_client/services/downloaded_documents_service.dart';

void main() {
  group('DownloadDocCategories', () {
    String c(String n) => DownloadDocCategories.inferFromFileName(n);

    test('normalize: bảng bỏ dấu có độ dài bằng nhau & bỏ dấu đúng', () {
      expect(DownloadDocCategories.normalize('Bảng Lương-Tháng 5.xlsx'), 'bang_luong_thang_5_xlsx');
      expect(DownloadDocCategories.normalize('Đỗ Hợp Đồng'), 'do_hop_dong');
    });

    test('tên có gạch ngang / gạch dưới / dấu đều nhận đúng nhóm', () {
      expect(c('bao-cao-thu-chi-2026.xlsx'), 'Báo cáo thu chi');
      expect(c('bao_cao_thu_chi.xlsx'), 'Báo cáo thu chi');
      expect(c('Báo cáo ứng lương.xlsx'), 'Báo cáo ứng lương');
      expect(c('cash_register_transactions.xlsx'), 'Báo cáo thu chi');
      expect(c('cham-cong-thang-5.xlsx'), 'Chấm công');
    });

    test('không khớp nhầm', () {
      expect(c('lich_su_thao_tac.xlsx'), 'Nhật ký hệ thống');
      expect(c('lich_lam_viec.xlsx'), 'Lịch làm việc');
      expect(c('phat_trien_san_pham.xlsx'), isNot('Báo cáo phạt'));
      expect(c('bao_cao_phat.xlsx'), 'Báo cáo phạt');
      expect(c('hop_dong_lao_dong.docx'), 'Hợp đồng');
      expect(c('abc.png'), 'Khác');
    });
  });

  group('DownloadedDocumentsService', () {
    late Directory tmp;
    late Directory pubDir;
    final svc = DownloadedDocumentsService.instance;
    var now = DateTime(2026, 10, 15, 10);

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('docs_test');
      pubDir = Directory('${tmp.path}/pub')..createSync();
      now = DateTime(2026, 10, 15, 10);
      svc
        ..rootOverride = '${tmp.path}/root'
        ..publicDirsOverride = [pubDir.path]
        ..androidOverride = true
        ..clock = () => now;
      svc.setOwner(null);
      svc.setOwner('1_10');
      await svc.ensureLoaded(force: true);
    });

    tearDown(() async {
      svc.setOwner(null);
      await tmp.delete(recursive: true);
    });

    Future<DownloadedDocument> add(String name, {List<int>? bytes, String? ext}) async {
      final d = await svc.register(bytes: bytes ?? [1, 2, 3], filename: name, mimeType: name.endsWith('.csv') ? 'text/csv' : 'application/pdf', externalUri: ext);
      return d!;
    }

    test('mỗi tài khoản một danh sách riêng', () async {
      await add('a.xlsx');
      expect(svc.items.length, 1);
      svc.setOwner('1_11');
      await svc.ensureLoaded();
      expect(svc.items, isEmpty);
      svc.setOwner('1_10');
      await svc.ensureLoaded();
      expect(svc.items.length, 1);
    });

    test('đổi tên không tạo bản trùng', () async {
      final d = await add('a.xlsx');
      expect(await svc.rename(d.id, 'moi'), isTrue);
      expect(svc.items.length, 1);
      expect(svc.items.first.fileName, 'moi.xlsx');
      expect(File(svc.items.first.localPath).existsSync(), isTrue);
    });

    test('xóa rồi không bị nhập lại từ thư mục công khai', () async {
      File('${pubDir.path}/b.xlsx').writeAsBytesSync([9, 9]);
      File('${pubDir.path}/b.xlsx').setLastModifiedSync(now);
      expect(await svc.importFromPublicFolders(), 1);
      expect(await svc.importFromPublicFolders(), 0);
      await svc.delete(svc.items.first.id);
      expect(svc.items, isEmpty);
      expect(await svc.importFromPublicFolders(), 0);
      // vẫn không nhập lại sau khi nạp lại từ đĩa
      await svc.ensureLoaded(force: true);
      expect(await svc.importFromPublicFolders(), 0);
      expect(File('${pubDir.path}/b.xlsx').existsSync(), isTrue);
    });

    test('tự dọn tệp quá hạn', () async {
      await add('old.xlsx');
      now = now.add(const Duration(days: DownloadedDocumentsService.retentionDays + 1));
      await svc.ensureLoaded(force: true);
      expect(svc.items, isEmpty);
    });

    test('cùng tên + dung lượng trong 2 phút thì thay bản cũ', () async {
      await add('x.xlsx');
      await add('x.xlsx');
      expect(svc.items.length, 1);
    });

    test('lọc theo loại + sắp xếp', () async {
      await add('a.pdf', bytes: [1]);
      await add('b.csv', bytes: [1, 2, 3]);
      expect(svc.filter(type: DownloadFileKinds.pdf).length, 1);
      expect(svc.filter(sort: DownloadSort.size).first.fileName, 'b.csv');
      expect(svc.filter(sort: DownloadSort.name).first.fileName, 'a.pdf');
      expect(svc.totalBytes, 4);
    });
  });
}
