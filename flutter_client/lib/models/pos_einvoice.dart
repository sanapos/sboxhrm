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
    case 'Failed':
      return 'Lỗi xuất';
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
    case 'Failed':
      return 'HĐĐT lỗi';
    case 'Skipped':
      return 'Không xuất';
    default:
      return '—';
  }
}

bool posEInvoiceHasTag(String? status) {
  final st = (status ?? 'None').trim();
  return st == 'Issued' || st == 'Pending' || st == 'Failed';
}
