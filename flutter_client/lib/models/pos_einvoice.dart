import 'package:flutter/material.dart';

class PosEInvoiceSettings {
  final bool enabled;
  final String provider;
  final String apiBaseUrl;
  final String username;
  final bool hasPassword;
  final String supplierTaxCode;
  final String templateCode;
  final String invoiceSeries;
  final String invoiceType;
  final bool askAtCheckout;
  final bool defaultIssueAtCheckout;
  final String taxMode;
  final double defaultTaxPercent;

  const PosEInvoiceSettings({
    this.enabled = false,
    this.provider = 'Viettel',
    this.apiBaseUrl = 'https://api-vinvoice.viettel.vn',
    this.username = '',
    this.hasPassword = false,
    this.supplierTaxCode = '',
    this.templateCode = '1/001',
    this.invoiceSeries = '',
    this.invoiceType = '1',
    this.askAtCheckout = true,
    this.defaultIssueAtCheckout = false,
    this.taxMode = 'included',
    this.defaultTaxPercent = 10,
  });

  bool get isViettel => provider.toLowerCase() == 'viettel';

  bool get showCheckoutChip => enabled && askAtCheckout;

  factory PosEInvoiceSettings.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 10;
    return PosEInvoiceSettings(
      enabled: json['enabled'] == true || json['Enabled'] == true,
      provider: (json['provider'] ?? json['Provider'] ?? 'Viettel').toString(),
      apiBaseUrl: (json['apiBaseUrl'] ??
              json['ApiBaseUrl'] ??
              'https://api-vinvoice.viettel.vn')
          .toString(),
      username: (json['username'] ?? json['Username'] ?? '').toString(),
      hasPassword: json['hasPassword'] == true || json['HasPassword'] == true,
      supplierTaxCode:
          (json['supplierTaxCode'] ?? json['SupplierTaxCode'] ?? '').toString(),
      templateCode:
          (json['templateCode'] ?? json['TemplateCode'] ?? '1/001').toString(),
      invoiceSeries:
          (json['invoiceSeries'] ?? json['InvoiceSeries'] ?? '').toString(),
      invoiceType:
          (json['invoiceType'] ?? json['InvoiceType'] ?? '1').toString(),
      askAtCheckout:
          json['askAtCheckout'] != false && json['AskAtCheckout'] != false,
      defaultIssueAtCheckout: json['defaultIssueAtCheckout'] == true ||
          json['DefaultIssueAtCheckout'] == true,
      taxMode: (json['taxMode'] ?? json['TaxMode'] ?? 'included').toString(),
      defaultTaxPercent: n(json['defaultTaxPercent'] ?? json['DefaultTaxPercent']),
    );
  }

  Map<String, dynamic> toSaveJson({String? password}) => {
        'enabled': enabled,
        'provider': provider,
        'apiBaseUrl': apiBaseUrl,
        'username': username,
        if (password != null && password.isNotEmpty) 'password': password,
        'supplierTaxCode': supplierTaxCode,
        'templateCode': templateCode,
        'invoiceSeries': invoiceSeries,
        'invoiceType': invoiceType,
        'askAtCheckout': askAtCheckout,
        'defaultIssueAtCheckout': defaultIssueAtCheckout,
        'taxMode': taxMode,
        'defaultTaxPercent': defaultTaxPercent,
      };
}

String posEInvoiceStatusLabel(String? status) {
  switch ((status ?? 'None').trim()) {
    case 'Issued':
      return 'Đã xuất';
    case 'Skipped':
      return 'Không xuất';
    case 'Pending':
      return 'Chờ ký';
    case 'Draft':
      return 'Nháp';
    case 'Failed':
      return 'Lỗi xuất';
    case 'Cancelled':
      return 'Đã hủy';
    default:
      return 'Chưa xuất';
  }
}

/// Nhãn thẻ ngắn trên danh sách đơn (gắn cạnh số HĐ / cột HĐĐT).
String posEInvoiceChipLabel(String? status, {String? provider, String? invoiceNo}) {
  final st = (status ?? 'None').trim();
  final prov = (provider ?? '').trim();
  final no = (invoiceNo ?? '').trim();
  switch (st) {
    case 'Issued':
      final head = prov.isEmpty ? 'HĐĐT' : 'HĐĐT $prov';
      return no.isEmpty ? head : '$head · $no';
    case 'Pending':
      return prov.isEmpty ? 'HĐĐT chờ ký' : 'HĐĐT $prov chờ ký';
    case 'Draft':
      return 'HĐĐT nháp';
    case 'Failed':
      return 'HĐĐT lỗi';
    case 'Cancelled':
      return 'HĐĐT đã hủy';
    case 'Skipped':
      return 'Không xuất';
    default:
      return '—';
  }
}

bool posEInvoiceHasTag(String? status) {
  final st = (status ?? 'None').trim();
  return st == 'Issued' ||
      st == 'Pending' ||
      st == 'Draft' ||
      st == 'Failed' ||
      st == 'Cancelled';
}

bool posEInvoiceCanIssue(String? status) {
  final st = (status ?? 'None').trim();
  return st != 'Issued';
}

bool posEInvoiceCanDraft(String? status) {
  final st = (status ?? 'None').trim();
  return st == 'None' || st == 'Skipped' || st == 'Failed' || st == 'Cancelled';
}

bool posEInvoiceCanCancel(String? status) {
  final st = (status ?? 'None').trim();
  return st == 'Issued' || st == 'Pending' || st == 'Draft';
}

bool posEInvoiceCanReplace(String? status) => (status ?? '').trim() == 'Issued';

bool posEInvoiceCanEmail(String? status) => (status ?? '').trim() == 'Issued';

bool posEInvoiceCanSync(String? status) {
  final st = (status ?? 'None').trim();
  return st == 'Issued' || st == 'Pending' || st == 'Draft' || st == 'Failed';
}

Color posEInvoiceStatusColor(String? status) {
  switch ((status ?? 'None').trim()) {
    case 'Issued':
      return const Color(0xFF166534);
    case 'Pending':
    case 'Draft':
      return const Color(0xFFB45309);
    case 'Failed':
      return const Color(0xFFB91C1C);
    case 'Cancelled':
      return const Color(0xFF6B7280);
    default:
      return const Color(0xFF475569);
  }
}

class PosEInvoiceRow {
  final String id;
  final String orderNo;
  final DateTime? saleDate;
  final double total;
  final String? customerName;
  final String status;
  final String? provider;
  final String? invoiceNo;
  final String? series;
  final String? code;
  final String? error;
  final String? kind;
  final String? originalNo;
  final DateTime? issuedAt;
  final DateTime? emailSentAt;
  final String? emailTo;
  final String? buyerName;
  final String? buyerEmail;
  final DateTime? cancelledAt;
  final String? cancelReason;

  const PosEInvoiceRow({
    required this.id,
    required this.orderNo,
    this.saleDate,
    this.total = 0,
    this.customerName,
    this.status = 'None',
    this.provider,
    this.invoiceNo,
    this.series,
    this.code,
    this.error,
    this.kind,
    this.originalNo,
    this.issuedAt,
    this.emailSentAt,
    this.emailTo,
    this.buyerName,
    this.buyerEmail,
    this.cancelledAt,
    this.cancelReason,
  });

  bool get emailSent => emailSentAt != null;
  bool get isReplacement => (kind ?? '') == 'Replacement';

  factory PosEInvoiceRow.fromJson(Map<String, dynamic> json) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    DateTime? d(dynamic v) {
      if (v == null) return null;
      return DateTime.tryParse(v.toString());
    }

    return PosEInvoiceRow(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      orderNo: (json['orderNo'] ?? json['OrderNo'] ?? '').toString(),
      saleDate: d(json['saleDate'] ?? json['SaleDate']),
      total: n(json['total'] ?? json['Total']),
      customerName:
          (json['customerName'] ?? json['CustomerName'])?.toString(),
      status: (json['eInvoiceStatus'] ?? json['EInvoiceStatus'] ?? 'None')
          .toString(),
      provider: (json['eInvoiceProvider'] ?? json['EInvoiceProvider'])
          ?.toString(),
      invoiceNo: (json['eInvoiceNo'] ?? json['EInvoiceNo'])?.toString(),
      series: (json['eInvoiceSeries'] ?? json['EInvoiceSeries'])?.toString(),
      code: (json['eInvoiceCode'] ?? json['EInvoiceCode'])?.toString(),
      error: (json['eInvoiceError'] ?? json['EInvoiceError'])?.toString(),
      kind: (json['eInvoiceKind'] ?? json['EInvoiceKind'])?.toString(),
      originalNo:
          (json['eInvoiceOriginalNo'] ?? json['EInvoiceOriginalNo'])?.toString(),
      issuedAt: d(json['eInvoiceIssuedAt'] ?? json['EInvoiceIssuedAt']),
      emailSentAt:
          d(json['eInvoiceEmailSentAt'] ?? json['EInvoiceEmailSentAt']),
      emailTo: (json['eInvoiceEmailTo'] ?? json['EInvoiceEmailTo'])?.toString(),
      buyerName:
          (json['eInvoiceBuyerName'] ?? json['EInvoiceBuyerName'])?.toString(),
      buyerEmail:
          (json['eInvoiceBuyerEmail'] ?? json['EInvoiceBuyerEmail'])?.toString(),
      cancelledAt:
          d(json['eInvoiceCancelledAt'] ?? json['EInvoiceCancelledAt']),
      cancelReason: (json['eInvoiceCancelReason'] ?? json['EInvoiceCancelReason'])
          ?.toString(),
    );
  }
}
