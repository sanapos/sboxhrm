import 'dart:async';

import '../../../widgets/pos/pos_unit_qty_convert.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/pos_stock_count.dart';
import '../../../services/api_service.dart';
import '../../../utils/number_formatter.dart';
import '../../../utils/pos_doc_status.dart';
import '../../../utils/pos_mutation_result.dart';
import '../../../utils/pos_purchase_product_lookup.dart';
import '../../../utils/pos_scanner_config.dart';
import '../../../widgets/loading_widget.dart';
import '../../../widgets/notification_overlay.dart';
import '../../../widgets/pos/pos_bulk_scan_listener.dart';
import '../../../widgets/pos/pos_purchase_product_search_bar.dart';
import '../../../widgets/pos_barcode_scanner.dart';
import '../../../widgets/pos/pos_unsaved_changes.dart';
import '../../../widgets/warehouse/wh_mobile_components.dart';
import '../../../widgets/warehouse/wh_mobile_theme.dart';
import '../../main_layout.dart' show ScreenRefreshNotifier;
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class WhMobileStockCountEditor extends StatefulWidget {
  const WhMobileStockCountEditor({super.key, this.countId});

  final String? countId;

  @override
  State<WhMobileStockCountEditor> createState() => _WhMobileStockCountEditorState();
}

class _CountLine {
  _CountLine({
    required this.lineId,
    required this.productId,
    required this.name,
    this.code,
    this.unit,
    this.variantId,
    this.systemQty = 0,
    double? countedQty,
  }) : countedQty = countedQty;

  final String? variantId;

  final String lineId;
  final String productId;
  final String name;
  final String? code;
  final String? unit;
  final double systemQty;
  double? countedQty;

  double get diff => (countedQty ?? systemQty) - systemQty;
  bool get isUnchecked => countedQty == null;
}

class _WhMobileStockCountEditorState extends State<WhMobileStockCountEditor> {
  final _api = ApiService();
  final _noteCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _countId;
  String _countNo = '';
  String _status = 'InProgress';
  final List<_CountLine> _lines = [];

  bool get _readOnly => _status != 'InProgress';

  // ---------- Quét hàng loạt (máy kiểm kho / súng quét / đầu đọc RFID) ----------
  bool _bulkMode = false;
  /// RFID: đầu đọc đọc lặp thẻ liên tục → mỗi thẻ chỉ tính một lần trong lượt quét.
  bool _rfidMode = false;
  final List<String> _scanQueue = [];
  final Set<String> _seenTags = {};
  int _scanTotal = 0;
  int _scanCounted = 0;
  int _scanDupTags = 0;
  final Map<String, int> _unknown = {};
  final Map<String, int> _notTracked = {};
  String? _lastScanLabel;
  String? _scanError;
  bool _flushing = false;
  Timer? _flushTimer;
  DateTime? _lastBeep;

  /// Gom mã rồi gửi theo lô: 100 mã gửi ngay, ít hơn thì đợi 0,4s yên lặng.
  static const _flushBatch = 100;
  static const _flushDelay = Duration(milliseconds: 400);

  /// SL đếm + ghi chú lúc nạp / vừa lưu. Dòng chưa kiểm (null) đã nằm trên server
  /// nên không tính là chưa lưu.
  String? _cleanSig;
  bool get _isDirty =>
      !_loading &&
      !_readOnly &&
      (_scanQueue.isNotEmpty || (_cleanSig != null && _sig() != _cleanSig));
  String _sig() => [
        _noteCtrl.text.trim(),
        for (final l in _lines)
          if (l.countedQty != null) '${l.lineId}=${l.countedQty}',
      ].join('|');

  @override
  void initState() {
    super.initState();
    _countId = widget.countId;
    _bootstrap();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _noteCtrl.dispose();
    super.dispose();
  }

  void _toggleBulk() {
    if (_readOnly) return;
    // Bỏ focus ô tìm / ô SL để súng quét gõ phím không đổ mã vào ô chữ.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _bulkMode = !_bulkMode;
      if (_bulkMode) {
        _seenTags.clear();
        _scanTotal = 0;
        _scanCounted = 0;
        _scanDupTags = 0;
        _unknown.clear();
        _notTracked.clear();
        _lastScanLabel = null;
        _scanError = null;
      }
    });
  }

  void _onScanCode(String raw) {
    if (!_bulkMode || _readOnly) return;
    final code = raw.trim();
    if (code.isEmpty) return;
    if (_rfidMode) {
      final key = code.toUpperCase();
      if (!_seenTags.add(key)) {
        setState(() => _scanDupTags++);
        return;
      }
    }
    setState(() {
      _scanQueue.add(code);
      _scanTotal++;
    });
    final now = DateTime.now();
    if (_lastBeep == null || now.difference(_lastBeep!) > const Duration(milliseconds: 120)) {
      _lastBeep = now;
      SystemSound.play(SystemSoundType.click);
    }
    _flushTimer?.cancel();
    if (_scanQueue.length >= _flushBatch) {
      unawaited(_flushScans());
    } else {
      _flushTimer = Timer(_flushDelay, () => unawaited(_flushScans()));
    }
  }

  Future<void> _flushScans() async {
    if (_flushing || _scanQueue.isEmpty || !mounted) return;
    _flushing = true;
    try {
      final id = await _ensureId();
      if (id == null || !mounted) return;
      // SL đang sửa tay chưa lưu → lưu trước, server cộng tiếp trên số đó.
      if (_cleanSig != null && _sig() != _cleanSig) {
        if (!await _persist() || !mounted) return;
      }
      final batch = List<String>.from(_scanQueue.take(500));
      final res = await _api.scanPosStockCountCodes(id, batch, deviceName: 'POS');
      if (!mounted) return;
      if (res['isSuccess'] != true || res['data'] is! Map) {
        setState(() => _scanError =
            'Chưa gửi được ${_scanQueue.length} mã — ${res['message'] ?? 'mất mạng'}. Tự thử lại…');
        _flushTimer?.cancel();
        _flushTimer = Timer(const Duration(seconds: 3), () => unawaited(_flushScans()));
        return;
      }
      final d = Map<String, dynamic>.from(res['data'] as Map);
      final count = d['count'] ?? d['Count'];
      setState(() {
        _scanQueue.removeRange(0, batch.length);
        _scanError = null;
        if (count is Map) {
          _apply(PosStockCount.fromJson(Map<String, dynamic>.from(count)));
          _cleanSig = _sig();
        }
        _scanCounted += ((d['matchedCodes'] ?? d['MatchedCodes']) as num?)?.toInt() ?? 0;
        void merge(Map<String, int> into, Object? m) {
          if (m is! Map) return;
          m.forEach((k, v) => into['$k'] = (into['$k'] ?? 0) + ((v as num?)?.toInt() ?? 0));
        }
        merge(_unknown, d['unknown'] ?? d['Unknown']);
        merge(_notTracked, d['notTracked'] ?? d['NotTracked']);
        final matches = (d['matches'] ?? d['Matches']) as List? ?? const [];
        if (matches.isNotEmpty && matches.last is Map) {
          final m = matches.last as Map;
          final added = (m['added'] ?? m['Added']) as num? ?? 0;
          final total = (m['countedQty'] ?? m['CountedQty']) as num? ?? 0;
          _lastScanLabel =
              '+${formatViQty(added)} ${m['productName'] ?? m['ProductName'] ?? ''} → ${formatViQty(total)}';
        }
      });
      if (((d['unknown'] ?? d['Unknown']) as Map?)?.isNotEmpty == true) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      }
    } finally {
      _flushing = false;
      if (mounted && _scanQueue.isNotEmpty && _scanError == null) {
        _flushTimer?.cancel();
        _flushTimer = Timer(_flushDelay, () => unawaited(_flushScans()));
      }
    }
  }

  Future<void> _showCodes(String title, Map<String, int> codes) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(title)),
        content: SizedBox(
          width: 420,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final e in codes.entries)
                ListTile(
                  dense: true,
                  title: SelectableText(e.key),
                  trailing: Text('×${e.value}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => codes.clear());
              Navigator.pop(ctx);
            },
            child: Text(tr('Xóa danh sách')),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('Đóng'))),
        ],
      ),
    );
  }

  Future<void> _openScannerSetup() async {
    final cur = await PosScannerConfig.load();
    if (!mounted) return;
    final actionCtrl = TextEditingController(text: cur.action);
    final extraCtrl = TextEditingController(text: cur.extra);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Cài máy quét / máy kiểm kho')),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Đã nhận sẵn (để máy ở chế độ Broadcast / Intent):'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                for (final d in PosScannerConfig.supportedDevices)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('• ${tr(d)}', style: const TextStyle(fontSize: 13)),
                  ),
                const SizedBox(height: 14),
                Text(tr('Máy khác: nhập Intent action và tên extra chứa mã (xem trong app cài đặt '
                    'máy quét / DataWedge).')),
                const SizedBox(height: 8),
                TextField(
                  controller: actionCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Intent action'),
                    hintText: PosScannerConfig.standardAction,
                  ),
                ),
                TextField(
                  controller: extraCtrl,
                  decoration: InputDecoration(
                    labelText: tr('Tên extra chứa mã'),
                    hintText: PosScannerConfig.standardExtra,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Lưu'))),
        ],
      ),
    );
    if (ok == true) {
      await PosScannerConfig.save(action: actionCtrl.text, extra: extraCtrl.text);
      if (mounted) {
        NotificationOverlayManager().showSuccess(title: 'Đã lưu cài đặt máy quét', message: '');
      }
    }
    actionCtrl.dispose();
    extraCtrl.dispose();
  }

  Widget _statChip(String label, {Color? color, VoidCallback? onTap}) {
    final c = color ?? WhMobileTheme.primary;
    return ActionChip(
      onPressed: onTap,
      label: Text(tr(label), style: TextStyle(color: c, fontWeight: FontWeight.w700)),
      backgroundColor: c.withOpacity(0.08),
      side: BorderSide(color: c.withOpacity(0.25)),
    );
  }

  Widget _bulkPanel() {
    final pending = _scanQueue.length;
    final unknown = _unknown.values.fold<int>(0, (a, b) => a + b);
    final notTracked = _notTracked.values.fold<int>(0, (a, b) => a + b);
    return WhGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code_scanner_rounded, color: WhMobileTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr('Đang quét hàng loạt'),
                    style: WhMobileTheme.titleLarge.copyWith(fontSize: 17)),
              ),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(tr('Mã vạch / QR'))),
                  ButtonSegment(value: true, label: Text(tr('RFID'))),
                ],
                selected: {_rfidMode},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() {
                  _rfidMode = v.first;
                  _seenTags.clear();
                }),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            tr(_rfidMode
                ? 'Bóp cò đầu đọc RFID và quét quanh kệ. Mỗi thẻ chỉ tính 1 lần trong lượt này; '
                    'thẻ SGTIN-96 tự ra mã vạch hàng, thẻ gắn seri ra đúng máy.'
                : 'Bấm nút quét trên máy kiểm kho / bóp cò súng quét. Mỗi lần quét = +1; quét mã '
                    'thùng = + số lượng quy đổi. Mã lạ báo bíp dài.'),
            style: WhMobileTheme.caption,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _statChip('Đã quét $_scanTotal'),
              _statChip('Đã cộng $_scanCounted', color: WhMobileTheme.accent),
              if (pending > 0) _statChip('Chờ gửi $pending', color: WhMobileTheme.warning),
              if (_rfidMode && _scanDupTags > 0)
                _statChip('Thẻ đọc lặp bỏ qua $_scanDupTags', color: WhMobileTheme.textSecondary),
              if (unknown > 0)
                _statChip('Mã lạ $unknown', color: WhMobileTheme.danger,
                    onTap: () => _showCodes('Mã không khớp hàng nào', _unknown)),
              if (notTracked > 0)
                _statChip('Không quản lý tồn $notTracked', color: WhMobileTheme.textSecondary,
                    onTap: () => _showCodes('Hàng không quản lý tồn (dịch vụ…)', _notTracked)),
            ],
          ),
          if (_lastScanLabel != null) ...[
            const SizedBox(height: 8),
            Text(_lastScanLabel!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
          if (_scanError != null) ...[
            const SizedBox(height: 8),
            Text(tr(_scanError!), style: TextStyle(color: WhMobileTheme.danger)),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton.icon(
                onPressed: _openScannerSetup,
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(tr('Cài máy quét')),
              ),
              const Spacer(),
              FilledButton(
                onPressed: pending > 0 ? null : _toggleBulk,
                child: Text(tr(pending > 0 ? 'Đang gửi…' : 'Xong quét')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _bootstrap() async {
    if (_countId != null && _countId!.isNotEmpty) {
      final res = await _api.getPosStockCount(_countId!);
      if (mounted && res['isSuccess'] == true) {
        _apply(PosStockCount.fromJson(res['data'] as Map<String, dynamic>));
      }
    }
    _cleanSig = _sig();
    if (mounted) setState(() => _loading = false);
  }

  void _apply(PosStockCount c) {
    _countId = c.id.isEmpty ? null : c.id;
    _countNo = c.countNo;
    _status = normalizePosDocStatus(c.status, fallback: 'InProgress');
    _noteCtrl.text = c.note ?? '';
    _lines
      ..clear()
      ..addAll(c.lines.map((l) => _CountLine(
            lineId: l.id,
            productId: l.productId,
            name: l.productName,
            code: l.productCode,
            unit: l.unitName,
            variantId: l.variantId,
            systemQty: l.systemQty,
            countedQty: l.countedQty,
          )));
  }

  Future<String?> _ensureId() async {
    if (_countId != null && _countId!.isNotEmpty) return _countId;
    final res = await _api.createPosStockCount({
      'note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    });
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không tạo được phiếu');
      return null;
    }
    final c = PosStockCount.fromJson(res['data'] as Map<String, dynamic>);
    setState(() => _apply(c));
    return c.id;
  }

  /// [scanned]: quét mã / gõ đúng mã = đếm thêm 1 cái. Chọn từ danh sách tìm thì chỉ
  /// thêm dòng ở trạng thái «chưa kiểm» — trước đây đặt SL thực tế = 1 khiến tồn 42
  /// thành lệch -41 và «Cân bằng kho» kéo tồn về 1.
  Future<void> _pickProduct(PosPurchaseLookupPick pick, {bool scanned = false}) async {
    if (_readOnly) return;
    final double? addQty = (pick.qty != null && pick.qty! > 0)
        ? pick.qty!
        : (scanned ? 1.0 : null);
    bool sameLine(_CountLine l) =>
        l.productId == pick.product.id && (l.variantId ?? '') == (pick.variantId ?? '');
    final existing = _lines.where(sameLine).toList();
    if (existing.isNotEmpty) {
      if (addQty == null) {
        NotificationOverlayManager().showInfo(
          title: 'Đã có trong phiếu',
          message: tr('«${existing.first.name}» đã có — nhập SL thực tế ở dòng hàng'),
        );
        return;
      }
      setState(() {
        existing.first.countedQty = (existing.first.countedQty ?? 0) + addQty;
      });
      return;
    }
    final id = await _ensureId();
    if (id == null || !mounted) return;
    final res = await _api.addPosStockCountLines(id, [
      {
        'productId': pick.product.id,
        if (pick.variantId != null) 'variantId': pick.variantId,
      },
    ]);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      // Giữ SL đã đếm (chưa lưu) của các dòng khác — _apply nạp lại từ server.
      final pending = {for (final l in _lines) l.lineId: l.countedQty};
      setState(() {
        _apply(PosStockCount.fromJson(res['data'] as Map<String, dynamic>));
        for (final line in _lines) {
          if (pending.containsKey(line.lineId)) {
            line.countedQty = pending[line.lineId];
          } else if (sameLine(line)) {
            line.countedQty = addQty;
          }
        }
      });
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: res['message']?.toString() ?? 'Không thêm được hàng');
    }
  }

  Future<void> _scan() async {
    final code = await scanBarcodeWithCamera(context);
    if (code == null || !mounted) return;
    final pick = await lookupOrPickPosProduct(context, _api, code);
    if (pick != null && mounted) await _pickProduct(pick, scanned: true);
  }

  Future<void> _removeLine(_CountLine line) async {
    if (_readOnly || _countId == null) return;
    final res = await _api.removePosStockCountLine(_countId!, line.lineId);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      final pending = {for (final l in _lines) l.lineId: l.countedQty};
      setState(() {
        _apply(PosStockCount.fromJson(res['data'] as Map<String, dynamic>));
        for (final l in _lines) {
          if (pending.containsKey(l.lineId)) l.countedQty = pending[l.lineId];
        }
      });
    }
  }

  Future<bool> _persist() async {
    if (_lines.isEmpty && (_countId == null || _countId!.isEmpty)) return false;
    final id = await _ensureId();
    if (id == null) return false;

    if (_lines.isNotEmpty) {
      final lineRes = await _api.updatePosStockCountLines(
        id,
        _lines
            .map((l) => {
                  'lineId': l.lineId,
                  if (l.countedQty != null) 'countedQty': l.countedQty,
                })
            .toList(),
      );
      if (lineRes['isSuccess'] != true) {
        NotificationOverlayManager().showError(
            title: 'Lỗi', message: lineRes['message']?.toString() ?? 'Không lưu được dòng');
        return false;
      }
      _apply(PosStockCount.fromJson(lineRes['data'] as Map<String, dynamic>));
    }

    final noteRes = await _api.updatePosStockCount(id, {'note': _noteCtrl.text.trim()});
    if (noteRes['isSuccess'] != true) return false;
    _cleanSig = _sig();
    return true;
  }

  Future<void> _saveDraft() async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Phiếu trống', message: tr('Thêm hàng trước khi lưu'));
      return;
    }
    setState(() => _saving = true);
    final ok = await _persist();
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) NotificationOverlayManager().showSuccess(title: 'Đã lưu nháp', message: _countNo);
  }

  Future<void> _complete() async {
    if (_lines.isEmpty) {
      NotificationOverlayManager().showWarning(title: 'Phiếu trống', message: tr('Thêm hàng trước'));
      return;
    }
    if (!await _confirmBalance()) return;
    setState(() => _saving = true);
    final saved = await _persist();
    if (!saved || !mounted) {
      setState(() => _saving = false);
      return;
    }
    final res = await _api.completePosStockCount(_countId!);
    if (!mounted) return;
    setState(() => _saving = false);
    final result = PosDocMutationResult.parse(
      Map<String, dynamic>.from(res),
      expectedStatus: 'Completed',
      statusFallback: 'InProgress',
      completedLabel: 'Cân bằng kho',
    );
    if (result.ok) {
      NotificationOverlayManager().showSuccess(title: 'Cân bằng kho', message: _countNo);
      ScreenRefreshNotifier.refreshPosAfterStockChange();
      if (mounted) Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(
          title: 'Lỗi', message: result.errorMessage ?? res['message']?.toString() ?? '');
    }
  }

  int get _unchecked => _lines.where((l) => l.isUnchecked).length;

  /// Lệch lớn: từ 5 đơn vị và quá nửa tồn hệ thống (vd. tồn 42 đếm 1).
  bool _bigDiff(_CountLine l) =>
      l.diff.abs() >= 5 && l.diff.abs() > l.systemQty.abs() * 0.5;

  Widget _lineList(List<_CountLine> lines, String Function(_CountLine) detail,
      {Color? color}) {
    const maxShow = 6;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final l in lines.take(maxShow))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '• ${l.name}: ${detail(l)}',
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        if (lines.length > maxShow)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tr('… và ${lines.length - maxShow} dòng khác'),
                style: const TextStyle(fontSize: 13)),
          ),
      ],
    );
  }

  /// Trước «Cân bằng kho»: dòng chưa kiểm phải xử lý (máy chủ từ chối), dòng lệch được
  /// liệt kê để người dùng xác nhận — lệch lớn tô đỏ.
  Future<bool> _confirmBalance() async {
    final unchecked = _lines.where((l) => l.isUnchecked).toList();
    if (unchecked.isNotEmpty) {
      final markMatched = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Còn ${unchecked.length} dòng chưa kiểm')),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(tr('Các dòng này chưa nhập SL thực tế:')),
                _lineList(unchecked, (l) => 'tồn hệ thống ${formatViQty(l.systemQty)}'),
                const SizedBox(height: 12),
                Text(tr('Nếu đã đếm và thấy đúng bằng tồn hệ thống, chọn «Khớp tồn». '
                    'Nếu chưa đếm, quay lại nhập SL.')),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Quay lại kiểm')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('Khớp tồn')),
            ),
          ],
        ),
      );
      if (markMatched != true || !mounted) return false;
      setState(() {
        for (final l in unchecked) {
          l.countedQty = l.systemQty;
        }
      });
    }

    final diffs = _lines.where((l) => l.diff != 0).toList();
    final big = diffs.where(_bigDiff).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xác nhận cân bằng kho')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (diffs.isEmpty)
                Text(tr('Tất cả ${_lines.length} dòng khớp tồn hệ thống — tồn kho không đổi.'))
              else ...[
                Text(tr('Tồn kho sẽ được cập nhật theo SL thực tế cho ${diffs.length} dòng lệch:')),
                _lineList(
                  diffs,
                  (l) => '${formatViQty(l.systemQty)} → ${formatViQty(l.countedQty ?? l.systemQty)}'
                      ' (${l.diff > 0 ? '+' : ''}${formatViQty(l.diff)})',
                ),
              ],
              if (big.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  tr('⚠ ${big.length} dòng lệch lớn — kiểm tra lại trước khi cân bằng:'),
                  style: TextStyle(color: WhMobileTheme.danger, fontWeight: FontWeight.w600),
                ),
                _lineList(
                  big,
                  (l) => 'tồn ${formatViQty(l.systemQty)}, đếm ${formatViQty(l.countedQty ?? l.systemQty)}',
                  color: WhMobileTheme.danger,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Kiểm lại')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Cân bằng kho')),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    return PosBulkScanListener(
      enabled: _bulkMode && !_readOnly,
      onCode: _onScanCode,
      child: UnsavedChangesScope(
      isDirty: () => _isDirty,
      child: WhMobileScaffold(
      title: _countNo.isEmpty ? 'Tạo phiếu kiểm kho' : _countNo,
      subtitle: _unchecked > 0 ? 'Còn $_unchecked dòng chưa kiểm' : 'Kiểm kho',
      actions: [
        if (!_readOnly)
          TextButton.icon(
            onPressed: _toggleBulk,
            icon: Icon(_bulkMode ? Icons.stop_circle_outlined : Icons.document_scanner_outlined),
            label: Text(tr(_bulkMode ? 'Dừng quét' : 'Quét hàng loạt')),
          ),
        if (!_readOnly)
          IconButton(
            tooltip: tr('Quét bằng camera'),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            color: WhMobileTheme.primary,
            onPressed: _scan,
          ),
      ],
      bottomBar: WhMobileBottomBar(
        readOnly: _readOnly,
        loading: _saving,
        onSaveDraft: _readOnly ? null : _saveDraft,
        onComplete: _readOnly ? null : _complete,
        completeLabel: 'Cân bằng kho',
      ),
      body: _loading
          ? const Center(child: LoadingWidget())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                WhMobileTheme.padH,
                WhMobileTheme.gap,
                WhMobileTheme.padH,
                24,
              ),
              children: [
                if (_bulkMode && !_readOnly) ...[
                  _bulkPanel(),
                  const SizedBox(height: WhMobileTheme.gap),
                ] else if (!_readOnly)
                  PosPurchaseProductSearchBar(
                    api: _api,
                    hintText: tr('Tìm hoặc quét mã hàng…'),
                    onPick: _pickProduct,
                    onBarcodePick: (p) => _pickProduct(p, scanned: true),
                  ),
                const SizedBox(height: WhMobileTheme.gap),
                WhSectionHeader(title: 'Kiểm đếm (${_lines.length})'),
                if (_lines.isEmpty)
                  const WhEmptyState(
                    icon: Icons.fact_check_rounded,
                    title: 'Chưa có hàng',
                    subtitle: 'Thêm sản phẩm cần kiểm kho',
                  )
                else
                  ...List.generate(_lines.length, (i) {
                    final l = _lines[i];
                    final counted = l.countedQty ?? l.systemQty;
                    return WhLineCard(
                      index: i + 1,
                      name: l.name,
                      code: l.code,
                      unit: l.unit,
                      readOnly: _readOnly,
                      onRemove: () => _removeLine(l),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          WhSummaryRow(
                            label: 'Tồn hệ thống',
                            value: formatViQty(l.systemQty),
                          ),
                          const SizedBox(height: 8),
                          if (l.isUnchecked && !_readOnly)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      tr('Chưa kiểm — nhập SL thực tế hoặc'),
                                      style: WhMobileTheme.caption,
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        setState(() => l.countedQty = l.systemQty),
                                    child: Text(tr('Khớp tồn (${formatViQty(l.systemQty)})')),
                                  ),
                                ],
                              ),
                            ),
                          WhQtyStepper(
                            label: 'SL thực tế',
                            value: counted,
                            readOnly: _readOnly,
                            onChanged: (v) => setState(() => l.countedQty = v),
                          ),
                          if (!_readOnly && l.variantId == null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: PosUnitConvertButton(
                                api: _api,
                                productId: l.productId,
                                productName: l.name,
                                baseUnit: l.unit ?? '',
                                onQty: (v) => setState(() => l.countedQty = v),
                              ),
                            ),
                        ],
                      ),
                      trailing: l.isUnchecked
                          ? Text(tr('Chưa kiểm'),
                              style: TextStyle(color: WhMobileTheme.warning, fontWeight: FontWeight.w600))
                          : l.diff != 0
                          ? Text(tr('Lệch: ${l.diff > 0 ? '+' : ''}${formatViQty(l.diff)}'),
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: l.diff > 0 ? WhMobileTheme.accent : WhMobileTheme.danger,
                              ),
                            )
                          : Text(tr('Khớp ✓'), style: TextStyle(color: WhMobileTheme.accent, fontWeight: FontWeight.w600)),
                    );
                  }),
                const SizedBox(height: WhMobileTheme.gap),
                WhGlassCard(
                  child: TextField(
                    controller: _noteCtrl,
                    readOnly: _readOnly,
                    maxLines: 2,
                    decoration: WhMobileTheme.fieldDecoration(label: 'Ghi chú'),
                  ),
                ),
              ],
            ),
    ),
    ),
    );
  }
}
