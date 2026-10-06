import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';

/// Hàng đợi in TOÀN CỬA HÀNG — mọi máy cùng thấy lệnh chờ / kẹt / lỗi (kể cả lệnh gửi từ điện thoại phục vụ)
/// và xử lý ngay: In lại · Chuyển máy in khác · Hủy. Trên cùng là tình trạng từng máy in + Agent đang phục vụ.
class PosPrintQueueScreen extends StatefulWidget {
  const PosPrintQueueScreen({super.key, this.embedded = false});

  /// Nằm trong tab / sheet (không tự vẽ AppBar).
  final bool embedded;

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PosPrintQueueScreen()),
      );

  @override
  State<PosPrintQueueScreen> createState() => _PosPrintQueueScreenState();
}

enum _QueueFilter { problems, waiting, all }

class _PosPrintQueueScreenState extends State<PosPrintQueueScreen> {
  final _api = ApiService();
  Timer? _timer;
  bool _loading = true;
  String? _error;
  _QueueFilter _filter = _QueueFilter.problems;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _printers = [];
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    // Tự làm mới khi màn đang mở — lệnh từ máy khác hiện ngay, không phải kéo.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    final res = await _api.getPosPrintQueue(includeCompleted: _filter == _QueueFilter.all);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final d = Map<String, dynamic>.from(res['data'] as Map);
      setState(() {
        _items = [for (final e in (d['items'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
        _printers = [for (final e in (d['printers'] as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
        _error = null;
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? 'Không tải được hàng đợi in';
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _visible => switch (_filter) {
        _QueueFilter.problems => _items.where((i) => (i['problem'] ?? '') != '' && i['problem'] != 'cancelled').toList(),
        _QueueFilter.waiting => _items.where((i) => const {'Queued', 'Claimed', 'Printing'}.contains(i['status'])).toList(),
        _QueueFilter.all => _items,
      };

  int get _problemCount => _items.where((i) => (i['problem'] ?? '') != '' && i['problem'] != 'cancelled').length;
  int get _waitingCount => _items.where((i) => const {'Queued', 'Claimed', 'Printing'}.contains(i['status'])).length;

  static String docLabel(String t) => switch (t) {
        'SaleInvoice' => 'Hóa đơn',
        'SaleOrder' => 'Phiếu tạm tính',
        'KitchenSlip' => 'Phiếu bếp',
        'KitchenVoid' => 'Phiếu hủy món',
        'KitchenLabel' => 'Tem ly / tem bếp',
        'BarcodeLabel' => 'Tem mã vạch',
        'StockIssue' => 'Phiếu xuất kho',
        'Delivery' => 'Phiếu giao hàng',
        'SaleReturn' => 'Phiếu trả hàng',
        'EndOfDayReport' => 'Báo cáo cuối ngày',
        'PurchaseReceipt' => 'Phiếu nhập',
        'CashReceipt' => 'Phiếu thu',
        'CashPayment' => 'Phiếu chi',
        'StockCount' => 'Phiếu kiểm kho',
        'Quote' => 'Báo giá',
        _ => t,
      };

  static IconData docIcon(String t) => switch (t) {
        'KitchenSlip' || 'KitchenVoid' => Icons.restaurant_menu,
        'KitchenLabel' || 'BarcodeLabel' => Icons.label_outline,
        'StockIssue' || 'PurchaseReceipt' || 'StockCount' => Icons.inventory_2_outlined,
        _ => Icons.receipt_long_outlined,
      };

  ({String label, Color color, Color bg}) _state(Map<String, dynamic> i) {
    final problem = (i['problem'] ?? '').toString();
    switch (problem) {
      case 'no_agent':
        return (label: 'Không có máy Agent', color: SboxColors.dangerText, bg: SboxColors.dangerSoft);
      case 'printer_removed':
        return (label: 'Máy in đã xóa', color: SboxColors.dangerText, bg: SboxColors.dangerSoft);
      case 'failed':
        return (label: 'Lỗi in', color: SboxColors.dangerText, bg: SboxColors.dangerSoft);
      case 'hung':
        return (label: 'Treo', color: SboxColors.warningText, bg: SboxColors.warningSoft);
    }
    return switch (i['status']) {
      'Queued' => (label: 'Chờ in', color: SboxColors.infoText, bg: SboxColors.infoSoft),
      'Claimed' => (label: 'Máy đã nhận', color: SboxColors.infoText, bg: SboxColors.infoSoft),
      'Printing' => (label: 'Đang in', color: SboxColors.infoText, bg: SboxColors.infoSoft),
      'Completed' => (label: 'Đã in', color: SboxColors.successText, bg: SboxColors.successSoft),
      'Cancelled' => (label: 'Đã hủy', color: SboxColors.textMuted, bg: SboxColors.slate100),
      _ => (label: '${i['status']}', color: SboxColors.textMuted, bg: SboxColors.slate100),
    };
  }

  String _ago(Map<String, dynamic> i) {
    final s = (i['ageSeconds'] as num?)?.toInt() ?? 0;
    if (s < 60) return '$s giây trước';
    if (s < 3600) return '${s ~/ 60} phút trước';
    return '${s ~/ 3600} giờ trước';
  }

  Future<void> _retry(Map<String, dynamic> i, {String? printerId}) async {
    final id = i['id'].toString();
    setState(() => _busy.add(id));
    final res = await _api.retryPosPrintJob(id, printerId: printerId);
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (res['isSuccess'] == true) {
      NotificationOverlayManager().showSuccess(
        title: printerId == null ? 'Đã gửi in lại' : 'Đã chuyển máy in',
        message: tr('${docLabel('${i['documentType']}')} ${i['referenceNo'] ?? ''}'.trim()),
      );
      await _load(silent: true);
    } else {
      NotificationOverlayManager().showError(title: 'Không in lại được', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _moveTo(Map<String, dynamic> i) async {
    final current = i['printerId']?.toString();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr('Chuyển «${docLabel('${i['documentType']}')}» sang máy in'),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final p in _printers)
              ListTile(
                enabled: p['id'].toString() != current,
                leading: _healthDot(p),
                title: Text(tr('${p['name']}')),
                subtitle: Text(tr(_printerSubtitle(p))),
                trailing: p['id'].toString() == current ? Text(tr('Đang gán')) : null,
                onTap: () => Navigator.pop(ctx, p['id'].toString()),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await _retry(i, printerId: picked);
  }

  Future<void> _cancel(Map<String, dynamic> i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy lệnh in?')),
        content: Text(tr('${docLabel('${i['documentType']}')} ${i['referenceNo'] ?? ''} — máy in sẽ không in phiếu này nữa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Hủy lệnh')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final id = i['id'].toString();
    setState(() => _busy.add(id));
    final res = await _api.cancelPosPrintJob(id);
    if (!mounted) return;
    setState(() => _busy.remove(id));
    if (res['isSuccess'] == true) {
      await _load(silent: true);
    } else {
      NotificationOverlayManager().showError(title: 'Không hủy được', message: res['message']?.toString() ?? '');
    }
  }

  String _printerSubtitle(Map<String, dynamic> p) {
    final agents = (p['agents'] as List? ?? const []).map((e) => '$e').toList();
    final conn = switch (p['connectionType']) {
      'Lan' => 'LAN',
      'Usb' => 'USB',
      'Bluetooth' => 'Bluetooth',
      'Sunmi' => 'Sunmi',
      final v => '$v',
    };
    if (p['requiresAgent'] == true) {
      return agents.isEmpty ? '$conn · chưa có máy Agent nào bật' : '$conn · Agent: ${agents.join(', ')}';
    }
    return conn;
  }

  Widget _healthDot(Map<String, dynamic> p) {
    final noAgent = p['requiresAgent'] == true && (p['agents'] as List? ?? const []).isEmpty;
    final c = noAgent
        ? SboxColors.danger
        : switch (p['health']) {
            'Online' || 'Busy' => SboxColors.success,
            'Error' || 'Offline' => SboxColors.danger,
            _ => SboxColors.slate400,
          };
    return Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle));
  }

  Widget _printerStrip() {
    if (_printers.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 84,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _printers.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, k) {
          final p = _printers[k];
          final problems = (p['problems'] as num?)?.toInt() ?? 0;
          final waiting = (p['waiting'] as num?)?.toInt() ?? 0;
          return Container(
            width: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: problems > 0 ? SboxColors.danger : SboxColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _healthDot(p),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(tr('${p['name']}'),
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text(tr(_printerSubtitle(p)),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: SboxColors.textMuted)),
                const Spacer(),
                Text(
                  tr(problems > 0 ? '$problems lệnh cần xử lý · $waiting đang chờ' : (waiting > 0 ? '$waiting đang chờ in' : 'Không có lệnh chờ')),
                  style: TextStyle(fontSize: 12, color: problems > 0 ? SboxColors.dangerText : SboxColors.textSecondary),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _jobTile(Map<String, dynamic> i) {
    final st = _state(i);
    final id = i['id'].toString();
    final busy = _busy.contains(id);
    final status = '${i['status']}';
    // Máy in của lệnh đã bị xóa → «In lại» trên máy cũ vô nghĩa, chỉ cho chuyển sang máy khác.
    final printerGone = i['problem'] == 'printer_removed' || !_printers.any((p) => p['id'] == i['printerId']);
    final canRetry = status != 'Printing' && !printerGone;
    final canMove = status != 'Printing' && _printers.isNotEmpty && (printerGone || _printers.length > 1);
    final canCancel = status != 'Completed' && status != 'Printing' && status != 'Cancelled';
    final created = parseApiUtcDateTime(i['createdAt']);
    final meta = [
      '${i['printerName']}',
      if ((i['requestedByName'] ?? '').toString().isNotEmpty) 'gửi bởi ${i['requestedByName']}',
      if (created != null) '${created.hour.toString().padLeft(2, '0')}:${created.minute.toString().padLeft(2, '0')} · ${_ago(i)}',
    ].join(' · ');
    final err = (i['errorMessage'] ?? '').toString();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: SboxColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(docIcon('${i['documentType']}'), color: PosTheme.kiotBlue),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('${docLabel('${i['documentType']}')} ${i['referenceNo'] ?? ''}'.trim()),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(tr(meta), style: const TextStyle(fontSize: 12, color: SboxColors.textMuted)),
                      if (err.isNotEmpty && status != 'Completed')
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(tr(err), style: const TextStyle(fontSize: 12, color: SboxColors.dangerText)),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: st.bg, borderRadius: BorderRadius.circular(999)),
                  child: Text(tr(st.label), style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: st.color)),
                ),
              ],
            ),
            if (busy)
              const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator())
            else
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  if (canRetry)
                    TextButton.icon(
                      onPressed: () => _retry(i),
                      icon: const Icon(Icons.print_outlined, size: 18),
                      label: Text(tr(status == 'Completed' ? 'In thêm bản' : 'In lại')),
                    ),
                  if (canMove)
                    TextButton.icon(
                      onPressed: () => _moveTo(i),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: Text(tr('Chuyển máy in')),
                    ),
                  if (canCancel)
                    TextButton.icon(
                      onPressed: () => _cancel(i),
                      style: TextButton.styleFrom(foregroundColor: SboxColors.danger),
                      icon: const Icon(Icons.close, size: 18),
                      label: Text(tr('Hủy')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading && _items.isEmpty) return const Center(child: CircularProgressIndicator());
    final list = _visible;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        children: [
          _printerStrip(),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<_QueueFilter>(
              segments: [
                ButtonSegment(value: _QueueFilter.problems, label: Text(tr('Cần xử lý ($_problemCount)'))),
                ButtonSegment(value: _QueueFilter.waiting, label: Text(tr('Đang chờ ($_waitingCount)'))),
                ButtonSegment(value: _QueueFilter.all, label: Text(tr('Tất cả 24h'))),
              ],
              selected: {_filter},
              showSelectedIcon: false,
              onSelectionChanged: (v) {
                setState(() => _filter = v.first);
                unawaited(_load(silent: true));
              },
            ),
          ),
          const SizedBox(height: 10),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(tr(_error!), style: const TextStyle(color: SboxColors.dangerText)),
            )
          else if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(children: [
                const Icon(Icons.check_circle_outline, size: 48, color: SboxColors.success),
                const SizedBox(height: 8),
                Text(tr(_filter == _QueueFilter.problems ? 'Không có lệnh in nào bị treo hay lỗi' : 'Không có lệnh in'),
                    textAlign: TextAlign.center),
              ]),
            )
          else
            for (final i in list) _jobTile(i),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded || !HrmPageChrome.showInPageAppBar(context)) {
      return ColoredBox(color: HrmPageChrome.background, child: _body());
    }
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: Text(tr('Hàng đợi in')),
        backgroundColor: Colors.white,
        foregroundColor: PosTheme.textPrimary,
        elevation: 0,
        actions: [
          IconButton(tooltip: tr('Làm mới'), onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _body(),
    );
  }
}
