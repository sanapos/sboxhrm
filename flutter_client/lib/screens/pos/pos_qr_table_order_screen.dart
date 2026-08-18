import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../models/qr_order_lock_config.dart';
import '../../services/api_service.dart';
import '../../utils/pos_pdf_fonts.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// In / quản lý QR order tại bàn. Tắt mặc định trong thiết lập ngành hàng.
class PosQrTableOrderScreen extends StatefulWidget {
  const PosQrTableOrderScreen({super.key});

  @override
  State<PosQrTableOrderScreen> createState() => _PosQrTableOrderScreenState();
}

class _PosQrTableOrderScreenState extends State<PosQrTableOrderScreen> {
  final _api = ApiService();
  bool _loading = true;
  bool _busy = false;
  bool _enabled = false;
  bool _autoPrint = true;
  bool _requireOpenSession = false;
  bool _requireGeofence = false;
  bool _requireOrderConfirmation = false;
  bool _geoConfigured = false;
  String? _error;
  List<_QrTable> _tables = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosQrOrderTables();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được QR bàn';
      });
      return;
    }
    final data = Map<String, dynamic>.from(res['data'] as Map);
    final raw = data['tables'] ?? data['Tables'];
    final tables = <_QrTable>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is! Map) continue;
        tables.add(_QrTable.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    setState(() {
      _enabled = data['enabled'] == true || data['Enabled'] == true;
      _autoPrint = data['autoPrintKitchen'] != false &&
          data['AutoPrintKitchen'] != false;
      _requireOpenSession = data['requireOpenSession'] == true ||
          data['RequireOpenSession'] == true;
      _requireGeofence =
          data['requireGeofence'] == true || data['RequireGeofence'] == true;
      _requireOrderConfirmation =
          data['requireOrderConfirmation'] == true ||
          data['RequireOrderConfirmation'] == true;
      _geoConfigured =
          data['geoConfigured'] == true || data['GeoConfigured'] == true;
      _tables = tables;
      _loading = false;
    });
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final helper = PosSellSettingsHelper(_api);
    final loaded = await helper.load();
    if (loaded.settings == null) {
      if (mounted) setState(() => _busy = false);
      NotificationOverlayManager().showError(
        title: 'Không bật được',
        message: loaded.error ?? 'Thiếu thiết lập POS',
      );
      return;
    }
    final saved = await helper.save(
      loaded.settings!.copyWith(enableQrTableOrder: true),
      applyDefaults: false,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved.settings == null) {
      NotificationOverlayManager().showError(
        title: 'Không bật được',
        message: saved.error ?? 'Thử lại',
      );
      return;
    }
    await _load();
  }

  Future<void> _setAutoPrint(bool value) async {
    setState(() => _busy = true);
    final helper = PosSellSettingsHelper(_api);
    final loaded = await helper.load();
    if (loaded.settings == null) {
      if (mounted) setState(() => _busy = false);
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: loaded.error ?? 'Thiếu thiết lập POS',
      );
      return;
    }
    final saved = await helper.save(
      loaded.settings!.copyWith(enableQrOrderAutoPrint: value),
      applyDefaults: false,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved.settings == null) {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: saved.error ?? 'Thử lại',
      );
      return;
    }
    setState(() => _autoPrint = value);
  }

  Future<void> _setLock({
    bool? requireOpenSession,
    bool? requireGeofence,
    bool? requireOrderConfirmation,
  }) async {
    setState(() => _busy = true);
    final helper = PosSellSettingsHelper(_api);
    final loaded = await helper.load();
    if (loaded.settings == null) {
      if (mounted) setState(() => _busy = false);
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: loaded.error ?? 'Thiếu thiết lập POS',
      );
      return;
    }
    final next = QrOrderLockConfig.fromExtraJson(loaded.settings!.extraJson)
        .copyWith(
      requireOpenSession: requireOpenSession,
      requireGeofence: requireGeofence,
      requireOrderConfirmation: requireOrderConfirmation,
    );
    final saved = await helper.save(
      loaded.settings!.copyWith(
        extraJson: next.mergeIntoExtraJson(loaded.settings!.extraJson),
      ),
      applyDefaults: false,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (saved.settings == null) {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: saved.error ?? 'Thử lại',
      );
      return;
    }
    setState(() {
      _requireOpenSession = next.requireOpenSession;
      _requireGeofence = next.requireGeofence;
      _requireOrderConfirmation = next.requireOrderConfirmation;
    });
  }

  Future<void> _printTables(List<_QrTable> tables) async {
    if (tables.isEmpty) return;
    final fonts = await loadPosPdfFonts();
    final title = pw.TextStyle(font: fonts.bold, fontSize: 14);
    final hint = pw.TextStyle(font: fonts.regular, fontSize: 10);
    final urlStyle = pw.TextStyle(font: fonts.regular, fontSize: 8, color: PdfColors.grey700);
    final badge = pw.TextStyle(font: fonts.bold, fontSize: 9, color: PdfColors.white);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
    );
    const perPage = 6;
    for (var i = 0; i < tables.length; i += perPage) {
      final chunk = tables.skip(i).take(perPage).toList();
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          theme: pw.ThemeData.withFont(base: fonts.regular, bold: fonts.bold),
          build: (_) => pw.Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final t in chunk)
                pw.Container(
                  width: 240,
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.orange200),
                    borderRadius: pw.BorderRadius.circular(12),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.symmetric(vertical: 8),
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.orange800,
                          borderRadius: pw.BorderRadius.vertical(
                            top: pw.Radius.circular(11),
                          ),
                        ),
                        child: pw.Text(
                          tr('GỌI MÓN TẠI BÀN'),
                          style: badge,
                          textAlign: pw.TextAlign.center,
                        ),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: pw.Column(
                          children: [
                            pw.Text(
                              t.label,
                              style: title,
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 8),
                            pw.BarcodeWidget(
                              barcode: Barcode.qrCode(),
                              data: t.url,
                              width: 160,
                              height: 160,
                              drawText: false,
                            ),
                            pw.SizedBox(height: 8),
                            pw.Text(
                              tr('Quét để gọi món'),
                              style: hint,
                              textAlign: pw.TextAlign.center,
                            ),
                            pw.SizedBox(height: 4),
                            pw.Text(
                              _displayUrl(t.url),
                              style: urlStyle,
                              textAlign: pw.TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    }
    await Printing.layoutPdf(
      onLayout: (_) async => doc.save(),
      name: 'qr-order-ban.pdf',
    );
  }

  bool get _hasLanUrl => _tables.any((t) => _looksLan(t.url));

  static bool _looksLan(String url) {
    final uri = Uri.tryParse(url);
    final host = (uri?.host ?? '').toLowerCase();
    if (host.isEmpty) return true;
    if (host == 'localhost' || host == '127.0.0.1') return true;
    if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
    if (RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(host)) return true;
    final port = uri?.port ?? 0;
    return port == 7070 || port == 3000;
  }

  static String _displayUrl(String url) {
    return url.replaceFirst(RegExp(r'^https?://'), '');
  }

  @override
  Widget build(BuildContext context) {
    final pushed = PosHubScope.pushedSubPageOf(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: pushed,
        title: Text(tr('QR order tại bàn')),
        actions: [
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    const SizedBox(height: 12),
                  ],
                  if (!_enabled) _buildDisabled() else _buildEnabled(),
                ],
              ),
            ),
    );
  }

  Widget _buildDisabled() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('Chưa bật QR order tại bàn'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              tr(
                'Tắt mặc định. Bật để in QR dán bàn: khách chọn món (kể cả topping / biến thể) trên điện thoại. '
                'Máy POS đọc loa khi có đơn. Thanh toán vẫn tại quầy.',
              ),
              style: TextStyle(color: Colors.grey.shade700, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _enable,
              icon: const Icon(Icons.qr_code_2),
              label: Text(tr(_busy ? 'Đang bật…' : 'Bật QR order')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnabled() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: SwitchListTile(
            title: Text(tr('Tự in phiếu bếp')),
            subtitle: Text(tr(_autoPrint
                ? 'Khách gửi món là in phiếu qua Agent'
                : 'Tắt: thu ngân bấm Báo bếp để in thủ công')),
            value: _autoPrint,
            onChanged: _busy ? null : _setAutoPrint,
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: Column(
            children: [
              SwitchListTile(
                title: Text(tr('Chỉ gọi món khi đã mở bàn')),
                subtitle: Text(tr(
                    'Khóa mạnh nhất: khách ngoài quán quét QR cũ cũng không tự mở đơn. '
                    'Thu ngân mở bàn trên sơ đồ rồi khách mới đặt được.')),
                value: _requireOpenSession,
                onChanged: _busy
                    ? null
                    : (v) => _setLock(requireOpenSession: v),
              ),
              SwitchListTile(
                title: Text(tr('Chỉ gọi món trong phạm vi quán (GPS)')),
                subtitle: Text(tr(_geoConfigured
                    ? 'Dùng vùng chấm công (geofence) của cửa hàng. Khách phải bật vị trí.'
                    : 'Chưa có vùng GPS — vào Chấm công → Vùng chấm công, tạo vòng 80–150m quanh quán rồi bật lại.')),
                value: _requireGeofence,
                onChanged: _busy
                    ? null
                    : (v) => _setLock(requireGeofence: v),
              ),
              SwitchListTile(
                title: Text(tr('Bật xác nhận order (QR)')),
                subtitle: Text(tr(_requireOrderConfirmation
                    ? 'Món không in thẳng xuống bếp — có âm thanh + thông báo để thu ngân xác nhận (Báo bếp).'
                    : 'Mặc định tắt: không cần xác nhận — theo «Tự in phiếu bếp».')),
                value: _requireOrderConfirmation,
                onChanged: _busy
                    ? null
                    : (v) => _setLock(requireOrderConfirmation: v),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_hasLanUrl)
          Material(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                tr(
                  'Link QR đang trỏ máy nội bộ / LAN. Khách dùng 4G sẽ không mở được menu. '
                  'Cần trỏ về https://sbox.sana.vn rồi in lại.',
                ),
                style: TextStyle(color: Colors.orange.shade900, height: 1.35),
              ),
            ),
          ),
        if (_hasLanUrl) const SizedBox(height: 12),
        if (_tables.isNotEmpty)
          FilledButton.icon(
            onPressed: () => _printTables(_tables),
            icon: const Icon(Icons.print_outlined),
            label: Text(tr('In tất cả QR (${_tables.length} bàn)')),
          ),
        const SizedBox(height: 12),
        if (_tables.isEmpty)
          Text(tr('Chưa có bàn — thêm bàn trong sơ đồ rồi quay lại.'),
              style: TextStyle(color: Colors.grey.shade700)),
        for (final t in _tables)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(t.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(t.url, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Wrap(
                spacing: 0,
                children: [
                  IconButton(
                    tooltip: tr('Sao chép link'),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: t.url));
                      NotificationOverlayManager().showSuccess(
                        title: 'Đã chép',
                        message: t.label,
                      );
                    },
                    icon: const Icon(Icons.copy),
                  ),
                  IconButton(
                    tooltip: tr('In QR'),
                    onPressed: () => _printTables([t]),
                    icon: const Icon(Icons.print_outlined),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _QrTable {
  const _QrTable({
    required this.id,
    required this.name,
    required this.url,
    this.areaName,
  });

  final String id;
  final String name;
  final String url;
  final String? areaName;

  String get label =>
      (areaName ?? '').isEmpty ? name : '$areaName · $name';

  factory _QrTable.fromJson(Map<String, dynamic> json) => _QrTable(
        id: (json['id'] ?? json['Id'] ?? '').toString(),
        name: (json['name'] ?? json['Name'] ?? '').toString(),
        url: (json['url'] ?? json['Url'] ?? '').toString(),
        areaName: (json['areaName'] ?? json['AreaName'])?.toString(),
      );
}
