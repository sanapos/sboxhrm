import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_einvoice_report_screen.dart';
import 'package:zkteco_flutter_client/screens/pos/pos_einvoice_settings_screen.dart';

import 'guide_shot_kit.dart';
import 'pos_guide_common.dart';

/// Ảnh cho bước «Hóa đơn điện tử: kết nối & xuất» (pos_einvoice) và
/// «Quản lý HĐĐT» (pos_einvoice_manage) — cửa hàng dùng Viettel SInvoice.

final _settings = {
  'enabled': true,
  'provider': 'Viettel',
  'apiBaseUrl': 'https://api-vinvoice.viettel.vn',
  'username': '0316789123',
  'hasPassword': true,
  'supplierTaxCode': '0316789123',
  'templateCode': '1/001',
  'invoiceSeries': 'C26TAA',
  'invoiceType': '1',
  'askAtCheckout': true,
  'defaultIssueAtCheckout': false,
  'taxMode': 'included',
  'defaultTaxPercent': 8,
  'printQrOnReceipt': true,
};

Map<String, Object?> _row(String id, String no, String status, num total, String day,
        {String? invNo, String? customer, String? taxCode, String? email, bool emailed = false, String? error}) =>
    {
      'id': id, 'orderNo': no, 'eInvoiceStatus': status, 'grandTotal': total,
      'saleDate': '2026-10-${day}T10:15:00', 'eInvoiceIssuedAt': invNo == null ? null : '2026-10-${day}T10:16:00',
      'eInvoiceNo': invNo, 'eInvoiceSeries': invNo == null ? null : 'C26TAA', 'eInvoiceProvider': 'Viettel',
      'customerName': customer, 'eInvoiceBuyerName': customer, 'eInvoiceBuyerTaxCode': taxCode,
      'eInvoiceBuyerEmail': email, 'eInvoiceEmailTo': emailed ? email : null,
      'eInvoiceEmailSentAt': emailed ? '2026-10-${day}T10:17:00' : null,
      'eInvoiceCode': invNo == null ? null : 'M1-26-A7F3K-0000${id.substring(1)}',
      'eInvoiceReservationCode': invNo == null ? null : 'TC${id.substring(1)}8K2Q',
      'eInvoiceError': error, 'orderStatus': 'Completed',
    };

final _rows = [
  _row('r1', 'HD000128', 'Issued', 1250000, '30', invNo: '00000128', customer: 'Công ty TNHH Gia Phát',
      taxCode: '0312345678', email: 'ketoan@giaphat.vn', emailed: true),
  _row('r2', 'HD000127', 'Issued', 186000, '30', invNo: '00000127', customer: 'Khách lẻ'),
  _row('r3', 'HD000126', 'Failed', 540000, '29', customer: 'Công ty CP Minh An', taxCode: '0109876543',
      error: 'Sai mã số thuế người mua'),
  _row('r4', 'HD000125', 'Draft', 320000, '29', customer: 'Chị Lan'),
  _row('r5', 'HD000124', 'Issued', 98000, '28', invNo: '00000124', customer: 'Khách lẻ'),
];

final _api = posGuideApi((req) {
  final p = req.url.path;
  if (p.endsWith('/api/pos/einvoice/settings')) return _settings;
  if (p.endsWith('/api/pos/einvoice/test')) {
    return {'ok': true, 'message': 'Kết nối Viettel SInvoice thành công (MST 0316789123)'};
  }
  if (p.endsWith('/api/pos/einvoice/summary')) {
    return {
      'issuedCount': 3, 'draftCount': 1, 'pendingCount': 0, 'failedCount': 1, 'cancelledCount': 0,
      'emailSentCount': 1, 'issuedAmount': 1534000, 'failedAmount': 540000, 'issuedVatAmount': 113630,
      'noneAmount': 320000,
    };
  }
  if (p.endsWith('/api/pos/einvoice/invoices')) return {'items': _rows, 'total': _rows.length};
  if (p.endsWith('/api/pos/einvoice/report')) {
    return {
      'revenue': 2394000, 'issuedAmount': 1534000, 'coveragePct': 64.1, 'replacementCount': 0,
      'byProvider': [
        {'providerName': 'Viettel SInvoice', 'count': 3, 'amount': 1534000},
      ],
      'daily': [
        {'date': '2026-10-28', 'revenue': 290000, 'issuedAmount': 98000},
        {'date': '2026-10-29', 'revenue': 558000, 'issuedAmount': 0},
        {'date': '2026-10-30', 'revenue': 1546000, 'issuedAmount': 1436000},
      ],
    };
  }
  if (p.endsWith('/api/pos/einvoice/portal')) {
    return {'provider': 'Viettel', 'url': 'https://vinvoice.viettel.vn', 'supportsDraft': true};
  }
  return null;
});

void main() {
  for (final (suffix, size) in [('', desktopSize), ('-mobile', mobileSize)]) {
    final mobile = suffix.isNotEmpty;
    const crumbs = ['Thiết lập SBOX', 'Hóa đơn điện tử'];

    testWidgets('pos-einvoice-1$suffix: chọn hãng, nhập tài khoản', (t) async {
      await guideShot(
        t,
        name: 'pos-einvoice-1$suffix',
        screen: withPosPackage(const PosEInvoiceSettingsScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Nhà cung cấp'), alignment: mobile ? 0.05 : 0.1),
        marks: [
          GuideMark(1, [find.text('Nhà cung cấp'), find.byType(DropdownButton<String>).first]),
          GuideMark(2, [find.textContaining('Tài khoản Viettel')]),
          if (!mobile)
            GuideMark(3, [GuideMark.within(find.text('MST người bán'), 'TextField'),
              GuideMark.within(find.text('Ký hiệu mẫu (templateCode)'), 'TextField')]),
        ],
      );
    });

    testWidgets('pos-einvoice-2$suffix: mẫu số, ký hiệu, kiểm tra kết nối', (t) async {
      await guideShot(
        t,
        name: 'pos-einvoice-2$suffix',
        screen: withPosPackage(const PosEInvoiceSettingsScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('Kiểm tra'), alignment: 0.6);
          await t.tap(GuideMark.button(find.text('Kiểm tra')));
          await t.pump(const Duration(milliseconds: 300));
          await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
          await t.pump(const Duration(milliseconds: 300));
          await guideScrollTo(t, find.text('Kiểm tra'), alignment: 0.6);
        },
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Kiểm tra'))]),
          GuideMark(2, [find.textContaining('thành công (MST')]),
        ],
      );
    });

    testWidgets('pos-einvoice-3$suffix: hỏi thu ngân, mặc định xuất, in QR', (t) async {
      await guideShot(
        t,
        name: 'pos-einvoice-3$suffix',
        screen: withPosPackage(const PosEInvoiceSettingsScreen()),
        api: _api,
        crumbs: crumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('Xuất hóa đơn điện tử'), alignment: 0.05),
        marks: [
          GuideMark(1, [find.text('Xuất hóa đơn điện tử')]),
          GuideMark(2, [find.text('Hỏi thu ngân lúc thanh toán'), find.text('Mặc định xuất hóa đơn')]),
          GuideMark(3, [find.text('In mã tra cứu + QR trên hóa đơn bán hàng')]),
        ],
      );
    });

    const mCrumbs = ['Báo cáo POS', 'Hóa đơn điện tử'];

    testWidgets('pos-einvoice-manage-1$suffix: danh sách, lọc trạng thái', (t) async {
      await guideShot(
        t,
        name: 'pos-einvoice-manage-1$suffix',
        screen: withPosPackage(const PosEInvoiceReportScreen()),
        api: _api,
        crumbs: mCrumbs,
        size: size,
        act: (t) async => guideScrollTo(t, find.text('HD000128'), alignment: 0.5),
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Tất cả')), GuideMark.button(find.text('Cần xử lý'))]),
          GuideMark(2, [find.ancestor(of: find.text('HD000128'), matching: find.byType(Card)).first]),
        ],
      );
    });

    testWidgets('pos-einvoice-manage-2$suffix: xem, gửi, thay thế, hủy', (t) async {
      await guideShot(
        t,
        name: 'pos-einvoice-manage-2$suffix',
        screen: withPosPackage(const PosEInvoiceReportScreen()),
        api: _api,
        crumbs: mCrumbs,
        size: size,
        act: (t) async {
          await guideScrollTo(t, find.text('HD000128'), alignment: 0.5);
          await t.tap(find.text('HD000128'));
          await t.pump(const Duration(milliseconds: 600));
        },
        marks: [
          GuideMark(1, [find.text('Xem lại hóa đơn (PDF)')]),
          GuideMark(2, [find.textContaining('Gửi HĐĐT qua ứng dụng khác')]),
          GuideMark(3, [find.text('Thay thế hóa đơn')]),
          GuideMark(4, [find.text('Hủy hóa đơn')]),
        ],
      );
    });

    testWidgets('pos-einvoice-manage-3$suffix: đồng bộ, tải từ hãng, portal', (t) async {
      await guideShot(
        t,
        name: 'pos-einvoice-manage-3$suffix',
        screen: withPosPackage(const PosEInvoiceReportScreen()),
        api: _api,
        crumbs: mCrumbs,
        size: size,
        // Điện thoại: hàng chip cuộn ngang — kéo sang trái cho thấy «Đồng bộ hàng loạt».
        act: mobile
            ? (t) async {
                await t.drag(find.text('Tải danh sách từ hãng'), const Offset(-260, 0));
                await t.pump(const Duration(milliseconds: 400));
              }
            : null,
        marks: [
          GuideMark(1, [GuideMark.button(find.text('Đồng bộ hàng loạt'))]),
          GuideMark(2, [GuideMark.button(find.text('Tải danh sách từ hãng'))]),
          // Điện thoại: chip trang quản lý đã cuộn khỏi khung để lộ «Đồng bộ hàng loạt».
          if (!mobile) GuideMark(3, [GuideMark.button(find.textContaining('Trang quản lý'))]),
        ],
      );
    });
  }
}
