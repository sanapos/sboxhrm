import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/qr_order_lock_config.dart';
import '../../utils/image_source_picker.dart';
import '../../services/api_service.dart';
import '../../utils/pos_qr_table_print.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import 'pos_qr_online_orders_screen.dart';

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
  bool _enableOnline = false;
  bool _onlineAutoConfirm = false;
  bool _onlineAutoPrintKitchen = false;
  bool _onlineAutoPay = false;
  bool _onlineAutoPrintProvisional = false;
  bool _onlineAutoCreateShipment = false;
  String _onlineDefaultCarrierCode = '';
  String _storeZalo = '';
  String? _onlineUrl;
  late final TextEditingController _storeZaloCtrl;
  String _storePhone = '';
  String _storeAddress = '';
  String? _logoUrl;
  List<String> _banners = [];
  String? _error;
  String _storeName = '';
  List<_QrTable> _tables = [];
  double _pdfCellCm = kPosTableQrPdfCellCm;

  @override
  void initState() {
    super.initState();
    _storeZaloCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _storeZaloCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final cellCm = await loadPosQrTablePdfCellCm();
    final res = await _api.getPosQrOrderTables();
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không tải được QR bàn';
        _pdfCellCm = cellCm;
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
      _enableOnline =
          data['enableOnline'] == true || data['EnableOnline'] == true;
      _onlineAutoConfirm = data['onlineAutoConfirm'] == true ||
          data['OnlineAutoConfirm'] == true;
      _onlineAutoPrintKitchen = data['onlineAutoPrintKitchen'] == true ||
          data['OnlineAutoPrintKitchen'] == true;
      _onlineAutoPay =
          data['onlineAutoPay'] == true || data['OnlineAutoPay'] == true;
      _onlineAutoPrintProvisional = data['onlineAutoPrintProvisional'] == true ||
          data['OnlineAutoPrintProvisional'] == true;
      _onlineAutoCreateShipment = data['onlineAutoCreateShipment'] == true ||
          data['OnlineAutoCreateShipment'] == true;
      _onlineDefaultCarrierCode =
          (data['onlineDefaultCarrierCode'] ?? data['OnlineDefaultCarrierCode'] ?? '')
              .toString()
              .trim();
      _storeName = (data['storeName'] ?? data['StoreName'] ?? '').toString();
      _storePhone = (data['storePhone'] ?? data['StorePhone'] ?? '').toString();
      _storeZalo =
          (data['storeZalo'] ?? data['StoreZalo'] ?? _storePhone).toString();
      _storeZaloCtrl.text = _storeZalo;
      final onlineUrl = (data['onlineUrl'] ?? data['OnlineUrl'])?.toString();
      _onlineUrl = (onlineUrl == null || onlineUrl.trim().isEmpty)
          ? null
          : onlineUrl.trim();
      final addr = (data['storeAddress'] ?? data['StoreAddress'] ?? '').toString();
      final province =
          (data['storeProvince'] ?? data['StoreProvince'] ?? '').toString();
      _storeAddress = [addr, province]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(', ');
      final logo = (data['logoUrl'] ?? data['LogoUrl'])?.toString().trim();
      _logoUrl = (logo == null || logo.isEmpty) ? null : logo;
      final rawBanners = data['banners'] ?? data['Banners'];
      _banners = [];
      if (rawBanners is List) {
        for (final e in rawBanners) {
          final s = e.toString().trim();
          if (s.isNotEmpty) _banners.add(s);
        }
      }
      _tables = tables;
      _pdfCellCm = cellCm;
      _loading = false;
    });
  }

  List<PosQrTablePrintItem> _items(List<_QrTable> tables) => [
        for (final t in tables)
          PosQrTablePrintItem(label: t.label, url: t.url),
      ];

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

  Future<void> _setOnline(bool value, {bool rotate = false}) async {
    setState(() => _busy = true);
    final res = await _api.setPosQrOrderOnline(enabled: value, rotate: rotate);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: res['message']?.toString() ?? 'Thử lại',
      );
      return;
    }
    await _load();
  }

  Future<void> _printOnline() async {
    final url = _onlineUrl;
    if (url == null || url.isEmpty) return;
    final item = PosQrTablePrintItem(
      label: tr('Đặt hàng online'),
      url: url,
    );
    final printer = await pickPosQrLabelPrinter(context);
    if (printer == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await printPosQrTablesToLabelPrinter(
        tables: [item],
        storeName: _storeName,
        printer: printer,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareOnlinePdf() async {
    final url = _onlineUrl;
    if (url == null || url.isEmpty) return;
    setState(() => _busy = true);
    try {
      await sharePosQrTablePdf(
        tables: [
          PosQrTablePrintItem(label: tr('Đặt hàng online'), url: url),
        ],
        storeName: _storeName,
        cellCm: _pdfCellCm,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _patchBrand(
      QrOrderLockConfig Function(QrOrderLockConfig c) fn) async {
    setState(() => _busy = true);
    try {
      final helper = PosSellSettingsHelper(_api);
      final loaded = await helper.load();
      if (loaded.settings == null) {
        NotificationOverlayManager().showError(
          title: 'Không lưu được',
          message: loaded.error ?? 'Thiếu thiết lập POS',
        );
        return false;
      }
      final next =
          fn(QrOrderLockConfig.fromExtraJson(loaded.settings!.extraJson));
      final saved = await helper.save(
        loaded.settings!.copyWith(
          extraJson: next.mergeIntoExtraJson(loaded.settings!.extraJson),
        ),
        applyDefaults: false,
      );
      if (!mounted) return false;
      if (saved.settings == null) {
        NotificationOverlayManager().showError(
          title: 'Không lưu được',
          message: saved.error ?? 'Thử lại',
        );
        return false;
      }
      await _load();
      return true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _pickUploadQrImage() async {
    final picked = await pickSingleImageWithCamera(context, maxEdge: 1600);
    if (picked == null) return null;
    final name = picked.name.isNotEmpty
        ? picked.name
        : 'qr_${DateTime.now().millisecondsSinceEpoch}.jpg';
    setState(() => _busy = true);
    try {
      final res = await _api.uploadFile(
        picked.bytes,
        name,
        folder: 'uploads/qr-order',
      );
      if (!mounted) return null;
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        final path =
            (data['filePath'] ?? data['fileUrl'] ?? '').toString().trim();
        if (path.isNotEmpty) return path;
      }
      NotificationOverlayManager().showError(
        title: 'Upload ảnh',
        message: res['message']?.toString() ?? tr('Không tải được ảnh'),
      );
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setLogo() async {
    final path = await _pickUploadQrImage();
    if (path == null) return;
    await _patchBrand((c) => c.copyWith(logoUrl: path));
  }

  Future<void> _clearLogo() async {
    await _patchBrand((c) => c.copyWith(clearLogo: true));
  }

  Future<void> _addBanner() async {
    if (_banners.length >= 5) {
      NotificationOverlayManager().showError(
        title: 'Ảnh quảng cáo',
        message: tr('Tối đa 5 ảnh'),
      );
      return;
    }
    final path = await _pickUploadQrImage();
    if (path == null) return;
    await _patchBrand((c) => c.copyWith(banners: [...c.banners, path]));
  }

  Future<void> _removeBanner(int index) async {
    await _patchBrand((c) {
      if (index < 0 || index >= c.banners.length) return c;
      final next = [...c.banners]..removeAt(index);
      return c.copyWith(banners: next);
    });
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

  Future<void> _printLabel(List<_QrTable> tables) async {
    final printer = await pickPosQrLabelPrinter(context);
    if (printer == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await printPosQrTablesToLabelPrinter(
        tables: _items(tables),
        storeName: _storeName,
        printer: printer,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf(List<_QrTable> tables, {required bool share}) async {
    if (tables.isEmpty) return;
    setState(() => _busy = true);
    try {
      if (share) {
        await sharePosQrTablePdf(
          tables: _items(tables),
          storeName: _storeName,
          cellCm: _pdfCellCm,
        );
      } else {
        await layoutPosQrTablePdf(
          tables: _items(tables),
          storeName: _storeName,
          cellCm: _pdfCellCm,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPrintAllSheet() async {
    if (_tables.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        var cell = _pdfCellCm;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                4,
                16,
                16 + MediaQuery.viewInsetsOf(ctx).bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    tr('In tất cả QR (${_tables.length} bàn)'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (_storeName.trim().isNotEmpty)
                    Text(
                      _storeName,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    tr('Kích thước mỗi khung (PDF)'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr('Mặc định 6×6 cm — dùng khi xuất PDF để khách in.'),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: cell,
                          min: 4,
                          max: 10,
                          divisions: 12,
                          label: '${cell.toStringAsFixed(1)} cm',
                          onChanged: (v) => setLocal(() => cell = v),
                        ),
                      ),
                      SizedBox(
                        width: 72,
                        child: Text(
                          '${cell.toStringAsFixed(1)} cm',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      await savePosQrTablePdfCellCm(cell);
                      if (mounted) setState(() => _pdfCellCm = cell);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _exportPdf(_tables, share: false);
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(tr('Xuất PDF / In')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await savePosQrTablePdfCellCm(cell);
                      if (mounted) setState(() => _pdfCellCm = cell);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _exportPdf(_tables, share: true);
                    },
                    icon: const Icon(Icons.share_outlined),
                    label: Text(tr('Chia sẻ PDF')),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      await savePosQrTablePdfCellCm(cell);
                      if (mounted) setState(() => _pdfCellCm = cell);
                      if (ctx.mounted) Navigator.pop(ctx);
                      await _printLabel(_tables);
                    },
                    icon: const Icon(Icons.label_outline),
                    label: Text(tr('In tem 60×40 (chọn máy)')),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openSinglePrintSheet(_QrTable table) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                tr('In QR · ${table.label}'),
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            if (_storeName.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  _storeName,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
              ),
            ListTile(
              leading: const Icon(Icons.label_outline),
              title: Text(tr('In tem 60×40')),
              subtitle: Text(tr('Chọn máy in tem · thiết kế mã QR bàn')),
              onTap: () {
                Navigator.pop(ctx);
                _printLabel([table]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: Text(tr('Xuất PDF / In')),
              subtitle: Text(
                tr('Khung ${_pdfCellCm.toStringAsFixed(1)}×${_pdfCellCm.toStringAsFixed(1)} cm'),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _exportPdf([table], share: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: Text(tr('Chia sẻ PDF')),
              onTap: () {
                Navigator.pop(ctx);
                _exportPdf([table], share: true);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool get _hasLanUrl =>
      _tables.any((t) => _looksLan(t.url)) ||
      (_onlineUrl != null && _looksLan(_onlineUrl!));

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
                  _buildBrandCard(),
                  const SizedBox(height: 12),
                  _buildOnlineOrdersShortcut(),
                  const SizedBox(height: 12),
                  _buildOnlineCard(),
                  const SizedBox(height: 12),
                  if (!_enabled) _buildDisabled() else _buildEnabled(),
                ],
              ),
            ),
    );
  }

  Widget _buildOnlineOrdersShortcut() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        leading: const Icon(Icons.delivery_dining_outlined,
            color: PosTheme.kiotBlue),
        title: Text(
          tr('Đơn online'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(tr(
            'Theo dõi & đổi trạng thái: chờ xác nhận → chuẩn bị → giao hàng')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const PosHubScope(
                embeddedInHub: false,
                pushedSubPage: true,
                child: PosQrOnlineOrdersScreen(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _brandThumb(String url, {double size = 56}) {
    final src = _api.getPublicFileUrl(url);
    if (src.isEmpty) {
      return Container(
        width: size,
        height: size,
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.image_outlined),
      );
    }
    return Image.network(
      src,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => Container(
        width: size,
        height: size,
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.broken_image_outlined),
      ),
    );
  }

  Widget _buildBrandCard() {
    final logo = _logoUrl;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr('Thương hiệu trang đặt hàng'),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              tr(
                'Hiện khi khách mở link QR bàn hoặc đặt online: logo, tên quán, SĐT, địa chỉ. '
                'Ảnh quảng cáo: ảnh đầu làm nền trang, tất cả ảnh hiện popup (đóng là mất trong phiên). '
                'Cuối trang có dòng «Phần mềm SBOX POS».',
              ),
              style: TextStyle(color: Colors.grey.shade700, height: 1.35, fontSize: 13),
            ),
            const SizedBox(height: 12),
            if (_storeName.trim().isNotEmpty)
              Text(_storeName,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            if (_storePhone.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('☎ $_storePhone'),
              ),
            if (_storeAddress.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('⌖ $_storeAddress'),
              ),
            if (_storePhone.trim().isEmpty && _storeAddress.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr('Chưa có SĐT / địa chỉ — cập nhật thông tin cửa hàng.'),
                  style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: logo == null
                      ? Container(
                          width: 64,
                          height: 64,
                          color: const Color(0xFFF3F4F6),
                          child: const Icon(Icons.storefront_outlined),
                        )
                      : _brandThumb(logo, size: 64),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _setLogo,
                        child: Text(tr(logo == null ? 'Thêm logo' : 'Đổi logo')),
                      ),
                      if (logo != null)
                        TextButton(
                          onPressed: _busy ? null : _clearLogo,
                          child: Text(tr('Xóa logo')),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr('Ảnh quảng cáo (${_banners.length}/5)'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _banners.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: _brandThumb(_banners[i], size: 72),
                          ),
                          Positioned(
                            top: -8,
                            right: -8,
                            child: IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(28, 28),
                              ),
                              onPressed: _busy ? null : () => _removeBanner(i),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_banners.length < 5)
                    OutlinedButton(
                      onPressed: _busy ? null : _addBanner,
                      child: Text(tr('+ Ảnh')),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnlineCard() {
    final url = _onlineUrl;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              title: Text(tr('Đặt hàng online ngoài cửa hàng')),
              subtitle: Text(tr(
                'QR riêng cho khách ngoài quán. Khách nhập họ tên, SĐT, địa chỉ '
                'và xem liên hệ quán (gọi / Zalo) trên trang đặt hàng.',
              )),
              value: _enableOnline,
              onChanged: _busy ? null : (v) => _setOnline(v),
            ),
            if (_enableOnline) ...[
              SwitchListTile(
                title: Text(tr('Tự xác nhận đơn online')),
                subtitle: Text(tr(
                    'Khách gửi đơn → trạng thái «Đã xác nhận» ngay, không chờ gọi lại.')),
                value: _onlineAutoConfirm,
                onChanged: _busy
                    ? null
                    : (v) => _patchBrand((c) => c.copyWith(onlineAutoConfirm: v)),
              ),
              SwitchListTile(
                title: Text(tr('Tự in bếp khi đơn online được xác nhận')),
                subtitle: Text(tr(
                    'In phiếu bếp qua Agent khi đơn chuyển sang «Đã xác nhận» '
                    '(tự động hoặc thu ngân bấm xác nhận).')),
                value: _onlineAutoPrintKitchen,
                onChanged: _busy
                    ? null
                    : (v) =>
                        _patchBrand((c) => c.copyWith(onlineAutoPrintKitchen: v)),
              ),
              SwitchListTile(
                title: Text(tr('Tự hoàn thành COD khi xác nhận')),
                subtitle: Text(tr(
                    'Đơn xác nhận → hoàn thành bán hàng COD (trừ tồn), thu tiền khi giao.')),
                value: _onlineAutoPay,
                onChanged: _busy
                    ? null
                    : (v) => _patchBrand((c) => c.copyWith(onlineAutoPay: v)),
              ),
              SwitchListTile(
                title: Text(tr('Gợi ý in tạm tính sau xác nhận')),
                subtitle: Text(tr(
                    'Trên màn «Đơn online», tự in hóa đơn tạm tính khi bấm xác nhận.')),
                value: _onlineAutoPrintProvisional,
                onChanged: _busy
                    ? null
                    : (v) => _patchBrand(
                        (c) => c.copyWith(onlineAutoPrintProvisional: v)),
              ),
              SwitchListTile(
                title: Text(tr('Tự tạo vận đơn khi «Đang giao»')),
                subtitle: Text(tr(
                    'Chuyển trạng thái giao hàng → tạo AWB hãng mặc định hoặc giao nội bộ.')),
                value: _onlineAutoCreateShipment,
                onChanged: _busy
                    ? null
                    : (v) => _patchBrand(
                        (c) => c.copyWith(onlineAutoCreateShipment: v)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: DropdownButtonFormField<String>(
                  value: _onlineDefaultCarrierCode.isEmpty
                      ? null
                      : _onlineDefaultCarrierCode,
                  decoration: InputDecoration(
                    labelText: tr('Hãng vận chuyển mặc định'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: null,
                      child: Text(tr('— Chọn thủ công —')),
                    ),
                    DropdownMenuItem(
                      value: 'Internal',
                      child: Text(tr('Giao hàng nội bộ')),
                    ),
                    const DropdownMenuItem(value: 'Ghn', child: Text('GHN')),
                    const DropdownMenuItem(value: 'Ghtk', child: Text('GHTK')),
                    const DropdownMenuItem(
                        value: 'ViettelPost', child: Text('Viettel Post')),
                    const DropdownMenuItem(
                        value: 'Ahamove', child: Text('AhaMove')),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => _patchBrand((c) => v == null || v.isEmpty
                          ? c.copyWith(clearOnlineDefaultCarrier: true)
                          : c.copyWith(onlineDefaultCarrierCode: v)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: tr('SĐT / Zalo quán (hiển thị cho khách)'),
                    hintText: _storePhone.isNotEmpty ? _storePhone : '090…',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  controller: _storeZaloCtrl,
                  onSubmitted: _busy
                      ? null
                      : (v) => _patchBrand(
                          (c) => c.copyWith(storeZalo: v.trim())),
                ),
              ),
            ],
            if (_enableOnline && url != null && url.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SelectableText(
                  url,
                  style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () async {
                              await Clipboard.setData(ClipboardData(text: url));
                              NotificationOverlayManager().showSuccess(
                                title: 'Đã chép',
                                message: tr('Link đặt online'),
                              );
                            },
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(tr('Sao chép link')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _printOnline,
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: Text(tr('In tem QR')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _shareOnlinePdf,
                      icon: const Icon(Icons.share_outlined, size: 18),
                      label: Text(tr('Chia sẻ PDF')),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _setOnline(true, rotate: true),
                      child: Text(tr('Đổi mã QR')),
                    ),
                  ],
                ),
              ),
            ],
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
        if (_storeName.trim().isNotEmpty) ...[
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(
                _storeName,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(tr(kPosTableQrSboxIntro)),
            ),
          ),
          const SizedBox(height: 12),
        ],
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
            onPressed: _busy ? null : _openPrintAllSheet,
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
                    onPressed: _busy ? null : () => _openSinglePrintSheet(t),
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
