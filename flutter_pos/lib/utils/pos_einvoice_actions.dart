import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pos_einvoice.dart';
import '../models/pos_sale_order.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_pdf_preview_dialog.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Thông tin tối thiểu của 1 HĐĐT để xem / gửi (từ danh sách HĐĐT hoặc danh sách đơn).
class PosEInvoiceTarget {
  const PosEInvoiceTarget({
    required this.orderId,
    required this.orderNo,
    this.status,
    this.provider,
    this.invoiceNo,
    this.series,
    this.taxAuthorityCode,
    this.lookupCode,
    this.lookupUrl,
    this.buyerName,
  });

  final String orderId;
  final String orderNo;
  final String? status;
  final String? provider;
  final String? invoiceNo;
  final String? series;
  final String? taxAuthorityCode;
  final String? lookupCode;
  final String? lookupUrl;
  final String? buyerName;

  factory PosEInvoiceTarget.fromRow(PosEInvoiceRow r) => PosEInvoiceTarget(
        orderId: r.id,
        orderNo: r.orderNo,
        status: r.status,
        provider: r.provider,
        invoiceNo: r.invoiceNo,
        series: r.series,
        taxAuthorityCode: r.code,
        lookupCode: r.reservationCode,
        buyerName: r.buyerName ?? r.customerName,
      );

  factory PosEInvoiceTarget.fromOrder(PosSaleOrder o) => PosEInvoiceTarget(
        orderId: o.id,
        orderNo: o.orderNo,
        status: o.eInvoiceStatus,
        provider: o.eInvoiceProvider,
        invoiceNo: o.eInvoiceNo,
        series: o.eInvoiceSeries,
        taxAuthorityCode: o.eInvoiceCode,
        lookupCode: o.eInvoiceReservationCode,
        lookupUrl: o.eInvoiceLookupUrl,
        buyerName: o.eInvoiceBuyerName ?? o.customerName,
      );

  /// Đã phát hành (có số) → gửi bản chính thức; còn lại → gửi bản nháp.
  bool get isSigned => (status ?? '') == 'Issued' && (invoiceNo ?? '').isNotEmpty;
}

/// Thao tác HĐĐT dùng chung: xem lại hóa đơn, mở trang quản lý của hãng, hộp thoại thay thế.
class PosEInvoiceActions {
  PosEInvoiceActions._();

  static Future<bool> openUrl(String? url) async {
    final u = (url ?? '').trim();
    if (u.isEmpty) return false;
    final uri = Uri.tryParse(u);
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  /// Mở trang quản lý HĐĐT của hãng (Viettel / Easy / MISA / VNPT).
  static Future<void> openPortal(Map<String, dynamic>? portal) async {
    final url = portal?['portalUrl']?.toString();
    final ok = await openUrl(url);
    if (!ok) {
      NotificationOverlayManager().showError(
        title: 'Không mở được trang quản lý',
        message: tr((url ?? '').isEmpty
            ? 'Chưa cấu hình link trang quản lý của hãng'
            : 'Không mở được $url'),
      );
    }
  }

  /// Xem lại hóa đơn (đã phát hành → PDF có chữ ký; chưa phát hành → bản nháp xem trước).
  static Future<void> view(
    BuildContext context,
    ApiService api,
    PosEInvoiceRow row,
  ) =>
      viewTarget(context, api, PosEInvoiceTarget.fromRow(row));

  static Future<Map<String, dynamic>?> _fetchView(
    BuildContext context,
    ApiService api,
    String orderId,
  ) async {
    final nav = Navigator.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: PosTheme.kiotBlue),
      ),
    );
    final res = await api.getPosEInvoiceView(orderId);
    nav.pop();
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(
        title: 'Không lấy được hóa đơn',
        message: res['message']?.toString() ?? 'Nhà cung cấp không trả hóa đơn',
      );
      return null;
    }
    return Map<String, dynamic>.from(res['data'] as Map);
  }

  static Future<void> viewTarget(
    BuildContext context,
    ApiService api,
    PosEInvoiceTarget t,
  ) async {
    final data = await _fetchView(context, api, t.orderId);
    if (data == null || !context.mounted) return;
    final kind = (data['kind'] ?? data['Kind'] ?? '').toString();
    final draft = data['isDraft'] == true || data['IsDraft'] == true;
    final title = '${draft ? 'HĐĐT NHÁP' : 'HĐĐT'} ${t.invoiceNo ?? t.orderNo}'
        '${t.provider == null ? '' : ' · ${posEInvoiceProviderName(t.provider)}'}';
    switch (kind) {
      case 'pdf':
        final b64 = (data['base64'] ?? data['Base64'] ?? '').toString();
        try {
          await showPosPdfPreviewDialog(
            context,
            bytes: base64Decode(b64),
            title: title,
          );
        } catch (e) {
          NotificationOverlayManager().showError(
            title: 'File hóa đơn lỗi',
            message: e.toString(),
          );
        }
        return;
      case 'url':
        if (!await openUrl((data['url'] ?? data['Url'])?.toString())) {
          NotificationOverlayManager().showError(
            title: 'Không mở được link hóa đơn',
            message: (data['url'] ?? '').toString(),
          );
        }
        return;
      case 'html':
        final html = (data['html'] ?? data['Html'] ?? '').toString();
        await openUrl(Uri.dataFromString(html,
                mimeType: 'text/html', encoding: utf8)
            .toString());
        return;
      default:
        await openUrl((data['lookupUrl'] ?? data['LookupUrl'])?.toString());
    }
  }

  /// Nội dung tin nhắn kèm theo khi gửi HĐĐT.
  static String shareMessage(
    PosEInvoiceTarget t, {
    required bool draft,
    String? lookupUrl,
  }) {
    final b = StringBuffer();
    if (draft) {
      b.writeln('HÓA ĐƠN ĐIỆN TỬ (BẢN NHÁP) — đơn ${t.orderNo}');
      b.writeln('Bản nháp chưa ký số, chưa có giá trị pháp lý. '
          'Quý khách vui lòng kiểm tra tên, MST, địa chỉ và phản hồi nếu cần sửa.');
    } else {
      final series = (t.series ?? '').trim();
      b.writeln('HÓA ĐƠN ĐIỆN TỬ ${series.isEmpty ? '' : 'ký hiệu $series '}số ${t.invoiceNo ?? ''}');
      b.writeln('Đơn hàng: ${t.orderNo}');
      if ((t.taxAuthorityCode ?? '').trim().isNotEmpty) {
        b.writeln('Mã CQT: ${t.taxAuthorityCode}');
      }
      if ((t.lookupCode ?? '').trim().isNotEmpty) {
        b.writeln('Mã tra cứu: ${t.lookupCode}');
      }
      final url = (lookupUrl ?? t.lookupUrl ?? '').trim();
      if (url.isNotEmpty) b.writeln('Tra cứu: $url');
    }
    if ((t.buyerName ?? '').trim().isNotEmpty) b.writeln('Người mua: ${t.buyerName}');
    return b.toString().trim();
  }

  /// Gửi HĐĐT (bản nháp hoặc đã ký) qua ứng dụng khác: Zalo, Messenger, Gmail, Telegram…
  /// Đính kèm PDF khi hãng trả file; nếu chỉ có link thì gửi link + thông tin tra cứu.
  static Future<void> share(
    BuildContext context,
    ApiService api,
    PosEInvoiceTarget t,
  ) async {
    final data = await _fetchView(context, api, t.orderId);
    if (data == null || !context.mounted) return;
    final kind = (data['kind'] ?? data['Kind'] ?? '').toString();
    final draft = data['isDraft'] == true || data['IsDraft'] == true;
    final lookup = (data['lookupUrl'] ?? data['LookupUrl'])?.toString();
    var text = shareMessage(t, draft: draft, lookupUrl: lookup);
    final subject = draft
        ? 'Hóa đơn điện tử (nháp) — ${t.orderNo}'
        : 'Hóa đơn điện tử số ${t.invoiceNo ?? t.orderNo}';
    try {
      if (kind == 'pdf') {
        final bytes = base64Decode((data['base64'] ?? data['Base64'] ?? '').toString());
        final base = (data['fileName'] ?? data['FileName'] ?? '').toString().trim();
        final name = base.isEmpty
            ? '${draft ? 'HDDT_NHAP' : 'HDDT'}_${t.invoiceNo ?? t.orderNo}.pdf'
            : (base.toLowerCase().endsWith('.pdf') ? base : '$base.pdf');
        await Share.shareXFiles(
          [XFile.fromData(Uint8List.fromList(bytes), name: name, mimeType: 'application/pdf')],
          text: text,
          subject: subject,
        );
        return;
      }
      final url = (data['url'] ?? data['Url'])?.toString();
      if ((url ?? '').isNotEmpty) text = '$text\nXem hóa đơn: $url';
      await Share.share(text, subject: subject);
    } catch (e) {
      NotificationOverlayManager().showError(
        title: 'Không gửi được hóa đơn',
        message: e.toString(),
      );
    }
  }

  /// Hộp thoại thay thế: lý do + sửa thông tin người mua (lý do thay thế phổ biến nhất).
  /// Trả về body gửi API hoặc null nếu hủy.
  static Future<({String reason, Map<String, dynamic> buyer})?> askReplace(
    BuildContext context,
    PosEInvoiceRow row,
  ) async {
    final reason = TextEditingController(text: 'Sai thông tin hóa đơn');
    final name = TextEditingController(text: row.buyerName ?? '');
    final company = TextEditingController();
    final tax = TextEditingController(text: row.buyerTaxCode ?? '');
    final address = TextEditingController();
    final email = TextEditingController(text: row.buyerEmail ?? '');
    InputDecoration dec(String l, {String? h}) => InputDecoration(
          labelText: tr(l),
          hintText: h == null ? null : tr(h),
          isDense: true,
          border: const OutlineInputBorder(),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Thay thế hóa đơn ${row.invoiceNo ?? row.orderNo}')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr('Hệ thống lập hóa đơn mới thay thế hóa đơn gốc trên hãng. '
                      'Để trống ô nào thì giữ thông tin cũ.'),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(controller: reason, decoration: dec('Lý do thay thế')),
                const SizedBox(height: 10),
                TextField(controller: name, decoration: dec('Tên người mua')),
                const SizedBox(height: 10),
                TextField(
                    controller: company,
                    decoration: dec('Tên đơn vị / công ty')),
                const SizedBox(height: 10),
                TextField(controller: tax, decoration: dec('MST người mua')),
                const SizedBox(height: 10),
                TextField(controller: address, decoration: dec('Địa chỉ')),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: dec('Email nhận hóa đơn'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
            child: Text(tr('Lập hóa đơn thay thế')),
          ),
        ],
      ),
    );
    String v(TextEditingController c) => c.text.trim();
    final result = ok == true
        ? (
            reason: v(reason),
            buyer: <String, dynamic>{
              if (v(name).isNotEmpty) 'name': v(name),
              if (v(company).isNotEmpty) 'companyName': v(company),
              if (v(tax).isNotEmpty) 'taxCode': v(tax),
              if (v(address).isNotEmpty) 'address': v(address),
              if (v(email).isNotEmpty) 'email': v(email),
            },
          )
        : null;
    for (final c in [reason, name, company, tax, address, email]) {
      c.dispose();
    }
    return result;
  }
}
