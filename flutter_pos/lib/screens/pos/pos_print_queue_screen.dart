import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_print_orchestrator.dart';
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

/// Nhóm loại phiếu cho bộ lọc.
enum _DocGroup { all, bill, kitchen, label, other }

class _PosPrintQueueScreenState extends State<PosPrintQueueScreen> {
  final _api = ApiService();
  Timer? _timer;
  bool _loading = true;
  String? _error;
  _QueueFilter _filter = _QueueFilter.problems;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _printers = [];
  final Set<String> _busy = {};
  /// null = mọi máy in.
  String? _printerFilter;
  _DocGroup _docFilter = _DocGroup.all;
  /// Đang In lại / Chuyển / Hủy hàng loạt — khóa các nút.
  String? _bulkBusy;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(PosPrintOrchestrator.instance.refreshConfig().then((_) {
      if (mounted) setState(() {});
    }));
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

  static bool _isProblem(Map<String, dynamic> i) => (i['problem'] ?? '') != '' && i['problem'] != 'cancelled';
  static bool _isWaiting(Map<String, dynamic> i) => const {'Queued', 'Claimed', 'Printing'}.contains(i['status']);

  /// Theo tab trạng thái (chưa lọc máy / loại) — dùng đếm số trên chip máy in.
  List<Map<String, dynamic>> get _byStatus => switch (_filter) {
        _QueueFilter.problems => _items.where(_isProblem).toList(),
        _QueueFilter.waiting => _items.where(_isWaiting).toList(),
        _QueueFilter.all => _items,
      };

  static _DocGroup _groupOf(Map<String, dynamic> i) => switch ('${i['documentType']}') {
        'SaleInvoice' || 'SaleOrder' || 'SaleReturn' || 'Delivery' => _DocGroup.bill,
        'KitchenSlip' || 'KitchenVoid' => _DocGroup.kitchen,
        'KitchenLabel' || 'BarcodeLabel' => _DocGroup.label,
        _ => _DocGroup.other,
      };

  static bool _isLabelDoc(Map<String, dynamic> i) => _groupOf(i) == _DocGroup.label;

  List<Map<String, dynamic>> get _visible => _byStatus
      .where((i) => _printerFilter == null || '${i['printerId']}' == _printerFilter)
      .where((i) => _docFilter == _DocGroup.all || _groupOf(i) == _docFilter)
      .toList();

  Map<String, dynamic>? _printerById(String? id) =>
      id == null ? null : _printers.where((p) => '${p['id']}' == id).firstOrNull;

  /// Máy cần Agent mà chưa có Agent nào bật → in lại sẽ lỗi tiếp.
  bool _printerOffline(Map<String, dynamic>? p) =>
      p == null ||
      (p['requiresAgent'] == true && (p['agents'] as List? ?? const []).isEmpty) ||
      p['health'] == 'Offline' ||
      p['health'] == 'Error';

  bool _printerIsLabel(Map<String, dynamic> p) {
    if (p.containsKey('isLabel')) return p['isLabel'] == true;
    final id = '${p['id']}'.toLowerCase();
    return PosPrintOrchestrator.instance.printers
        .any((x) => x.id.toLowerCase() == id && x.isLabelPrinter);
  }

  /// «ksend|HD111020260007|<phiên>~<mã>» (khóa chống trùng nội bộ) → «HD111020260007».
  static String refLabel(Object? raw) {
    final ref = '${raw ?? ''}'.trim();
    if (!ref.contains('|')) return ref;
    final parts = ref.split('|').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    final order = parts.where((e) => RegExp(r'^[A-Z]{1,5}\d{6,}$').hasMatch(e)).firstOrNull;
    return order ?? (parts.length > 1 ? parts[1].split('~').first : parts.first);
  }

  String _jobTitle(Map<String, dynamic> i) =>
      '${docLabel('${i['documentType']}')} ${refLabel(i['referenceNo'])}'.trim();

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
        message: tr(_jobTitle(i)),
      );
      await _load(silent: true);
    } else {
      NotificationOverlayManager().showError(title: 'Không in lại được', message: res['message']?.toString() ?? '');
    }
  }

  /// Máy in nhận được loại phiếu này: tem chỉ sang máy tem, phiếu thường không sang máy tem.
  /// Server cũ chưa trả `isLabel` → không lọc.
  List<Map<String, dynamic>> _compatiblePrinters({required bool label}) {
    final known = _printers.any((p) => p.containsKey('isLabel')) ||
        PosPrintOrchestrator.instance.printers.isNotEmpty;
    if (!known) return _printers;
    return _printers.where((p) => _printerIsLabel(p) == label).toList();
  }

  Future<String?> _pickPrinter({
    required String title,
    required bool label,
    String? current,
  }) {
    final list = _compatiblePrinters(label: label);
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(tr(label ? 'Cửa hàng chưa có máy in tem nào khác' : 'Chưa có máy in phù hợp')),
              ),
            for (final p in list)
              ListTile(
                enabled: p['id'].toString() != current,
                leading: _healthDot(p),
                title: Text(tr('${p['name']}')),
                subtitle: Text(tr(_printerOffline(p)
                    ? '${_printerSubtitle(p)} · đang mất kết nối'
                    : _printerSubtitle(p))),
                trailing: p['id'].toString() == current ? Text(tr('Đang gán')) : null,
                onTap: () => Navigator.pop(ctx, p['id'].toString()),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _moveTo(Map<String, dynamic> i) async {
    final picked = await _pickPrinter(
      title: 'Chuyển «${docLabel('${i['documentType']}')}» sang máy in',
      label: _isLabelDoc(i),
      current: i['printerId']?.toString(),
    );
    if (picked != null) await _retry(i, printerId: picked);
  }

  // ---------- Xử lý hàng loạt ----------

  /// Lệnh cần xử lý trong danh sách đang lọc (bỏ lệnh đang in / đã in / đã hủy).
  List<Map<String, dynamic>> get _bulkTargets => _visible
      .where((i) => _isProblem(i) || (i['status'] == 'Queued' || i['status'] == 'Claimed'))
      .toList();

  static const _staleKitchenSeconds = 30 * 60;

  bool _isStaleKitchen(Map<String, dynamic> i) {
    final g = _groupOf(i);
    return (g == _DocGroup.kitchen || g == _DocGroup.label) &&
        ((i['ageSeconds'] as num?)?.toInt() ?? 0) > _staleKitchenSeconds;
  }

  Future<void> _runBulk(
    String action,
    List<Map<String, dynamic>> jobs, {
    String? printerId,
    required String doneTitle,
  }) async {
    if (jobs.isEmpty) return;
    setState(() => _bulkBusy = action);
    final res = await _api.bulkPosPrintJobs(
      [for (final j in jobs) '${j['id']}'],
      action: action,
      printerId: printerId,
    );
    if (!mounted) return;
    setState(() => _bulkBusy = null);
    if (res['isSuccess'] != true || res['data'] is! Map) {
      NotificationOverlayManager().showError(title: 'Không xử lý được', message: res['message']?.toString() ?? '');
      return;
    }
    final d = res['data'] as Map;
    final ok = (d['ok'] as num?)?.toInt() ?? 0;
    final failed = (d['failed'] as num?)?.toInt() ?? 0;
    final firstErr = (d['errors'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => '${e['message'] ?? ''}')
        .firstWhere((m) => m.isNotEmpty, orElse: () => '');
    if (failed == 0) {
      NotificationOverlayManager().showSuccess(title: doneTitle, message: tr('$ok lệnh'));
    } else {
      NotificationOverlayManager().showWarning(
        title: tr('$doneTitle: $ok / ${ok + failed} lệnh'),
        message: tr(firstErr.isEmpty ? '$failed lệnh không xử lý được' : '$failed lệnh lỗi — $firstErr'),
      );
    }
    await _load(silent: true);
  }

  Future<void> _retryAll() async {
    final targets = _bulkTargets.where((i) {
      final gone = i['problem'] == 'printer_removed' || _printerById('${i['printerId']}') == null;
      return !gone && i['status'] != 'Printing';
    }).toList();
    if (targets.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Không có lệnh in lại được',
        message: tr('Máy in của các lệnh đã bị xóa — dùng «Chuyển tất cả»'),
      );
      return;
    }
    final stale = targets.where(_isStaleKitchen).length;
    final offline = {
      for (final i in targets)
        if (_printerOffline(_printerById('${i['printerId']}'))) '${i['printerName']}'
    };
    var skipStale = stale > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('In lại ${targets.length} lệnh?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Gửi lại đúng máy in ban đầu của từng lệnh.')),
              if (offline.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  tr('Máy đang mất kết nối: ${offline.join(', ')} — in lại sẽ lỗi tiếp. '
                      'Nên dùng «Chuyển tất cả» sang máy đang chạy.'),
                  style: const TextStyle(color: SboxColors.dangerText, fontSize: 13),
                ),
              ],
              if (stale > 0)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: skipStale,
                  onChanged: (v) => setD(() => skipStale = v ?? true),
                  title: Text(tr('Bỏ qua $stale phiếu bếp / tem cũ hơn 30 phút'),
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(tr('Tránh bếp nhận phiếu cũ rồi làm trùng món'),
                      style: const TextStyle(fontSize: 12)),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('In lại'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final send = skipStale ? targets.where((i) => !_isStaleKitchen(i)).toList() : targets;
    await _runBulk('retry', send, doneTitle: 'Đã gửi in lại');
  }

  Future<void> _moveAll() async {
    final targets = _bulkTargets.where((i) => i['status'] != 'Printing').toList();
    if (targets.isEmpty) return;
    final labels = targets.where(_isLabelDoc).length;
    // Lẫn tem + phiếu thường: chuyển nhóm đông hơn, nhóm kia giữ nguyên (máy tem ≠ máy phiếu).
    final label = labels * 2 > targets.length;
    final group = targets.where((i) => _isLabelDoc(i) == label).toList();
    final currents = {for (final i in group) '${i['printerId']}'};
    final picked = await _pickPrinter(
      title: label
          ? 'Chuyển ${group.length} tem sang máy in tem'
          : 'Chuyển ${group.length} lệnh sang máy in',
      label: label,
      current: currents.length == 1 ? currents.first : null,
    );
    if (picked == null || !mounted) return;
    var send = group.where((i) => '${i['printerId']}' != picked).toList();
    final stale = send.where(_isStaleKitchen).length;
    if (stale > 0) {
      // Chuyển = in ra giấy ngay trên máy mới → hỏi trước với phiếu bếp / tem đã cũ.
      final skip = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('$stale phiếu bếp / tem đã cũ hơn 30 phút')),
          content: Text(tr('In lại phiếu cũ dễ làm bếp làm trùng món. Bỏ qua các phiếu này?')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Vẫn in hết'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Bỏ qua phiếu cũ'))),
          ],
        ),
      );
      if (skip == null || !mounted) return;
      if (skip) send = send.where((i) => !_isStaleKitchen(i)).toList();
    }
    if (send.isEmpty) return;
    final left = targets.length - group.length;
    await _runBulk('retry', send, printerId: picked, doneTitle: 'Đã chuyển máy in');
    if (left > 0 && mounted) {
      NotificationOverlayManager().showInfo(
        title: 'Còn $left lệnh khác loại',
        message: tr(label ? 'Phiếu thường không in trên máy tem — chuyển riêng' : 'Tem cần máy in tem — chuyển riêng'),
      );
    }
  }

  Future<void> _cancelAll() async {
    final targets = _bulkTargets.where((i) => i['status'] != 'Printing').toList();
    if (targets.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy ${targets.length} lệnh in?')),
        content: Text(tr('Các phiếu này sẽ không được in nữa (vẫn xem lại được ở «Tất cả 24h»).')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: SboxColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Hủy tất cả')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _runBulk('cancel', targets, doneTitle: 'Đã hủy lệnh in');
  }

  Future<void> _cancel(Map<String, dynamic> i) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Hủy lệnh in?')),
        content: Text(tr('${_jobTitle(i)} — máy in sẽ không in phiếu này nữa.')),
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
          final selected = _printerFilter == '${p['id']}';
          return GestureDetector(
            onTap: () => setState(() => _printerFilter = selected ? null : '${p['id']}'),
            child: Container(
            width: 220,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: selected ? SboxColors.brand50 : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? SboxColors.primary
                    : (problems > 0 ? SboxColors.danger : SboxColors.border),
                width: selected ? 2 : 1,
              ),
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
    final compatible = _compatiblePrinters(label: _isLabelDoc(i));
    final canMove = status != 'Printing' &&
        compatible.isNotEmpty &&
        (printerGone || compatible.any((p) => '${p['id']}' != '${i['printerId']}'));
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
                      Text(tr(_jobTitle(i)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
            if (busy || _bulkBusy != null)
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

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Widget? leading,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          if (leading != null) ...[leading, const SizedBox(width: 6)],
          Text(tr(label)),
        ]),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: SboxColors.brand50,
        side: BorderSide(color: selected ? SboxColors.primary : SboxColors.border),
        labelStyle: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? SboxColors.primary : SboxColors.textSecondary,
        ),
      ),
    );
  }

  /// Lọc theo máy in (máy có lệnh trong tab hiện tại) và loại phiếu.
  Widget _filterChips() {
    final byStatus = _byStatus;
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final i in byStatus) {
      final id = '${i['printerId']}';
      counts[id] = (counts[id] ?? 0) + 1;
      names[id] = '${i['printerName']}';
    }
    // Máy đang chọn nhưng hết lệnh → vẫn giữ chip để bỏ chọn được.
    if (_printerFilter != null && !counts.containsKey(_printerFilter)) {
      counts[_printerFilter!] = 0;
      names[_printerFilter!] = '${_printerById(_printerFilter)?['name'] ?? 'Máy in'}';
    }
    final ids = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    int docCount(_DocGroup g) => byStatus
        .where((i) => _printerFilter == null || '${i['printerId']}' == _printerFilter)
        .where((i) => _groupOf(i) == g)
        .length;
    const docLabels = {
      _DocGroup.bill: 'Hóa đơn',
      _DocGroup.kitchen: 'Phiếu bếp',
      _DocGroup.label: 'Tem',
      _DocGroup.other: 'Khác',
    };
    // Một hàng: lọc theo máy | lọc theo loại phiếu — trước đây 2 hàng chồng nhau, mỗi hàng chỉ 1 nút
    // khi chưa có lệnh, bỏ trống gần hết bề ngang tablet.
    return SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            _chip(
              label: 'Tất cả máy (${byStatus.length})',
              selected: _printerFilter == null,
              onTap: () => setState(() => _printerFilter = null),
            ),
            for (final id in ids)
              _chip(
                label: '${names[id]} (${counts[id]})',
                selected: _printerFilter == id,
                leading: _printerById(id) == null
                    ? const Icon(Icons.block, size: 14, color: SboxColors.danger)
                    : _healthDot(_printerById(id)!),
                onTap: () => setState(() => _printerFilter = _printerFilter == id ? null : id),
              ),
            Container(
              width: 1,
              margin: const EdgeInsets.fromLTRB(4, 12, 10, 12),
              color: SboxColors.border,
            ),
            _chip(
              label: 'Mọi loại phiếu',
              selected: _docFilter == _DocGroup.all,
              onTap: () => setState(() => _docFilter = _DocGroup.all),
            ),
            for (final g in docLabels.keys)
              if (docCount(g) > 0 || _docFilter == g)
                _chip(
                  label: '${docLabels[g]} (${docCount(g)})',
                  selected: _docFilter == g,
                  onTap: () => setState(() => _docFilter = _docFilter == g ? _DocGroup.all : g),
                ),
          ],
        ),
      );
  }

  Widget _bulkBar() {
    final n = _bulkTargets.length;
    if (n < 2 && _bulkBusy == null) return const SizedBox.shrink();
    if (_bulkBusy != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(tr(_bulkBusy == 'cancel' ? 'Đang hủy lệnh in…' : 'Đang gửi lệnh in…')),
        ]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          FilledButton.icon(
            onPressed: _retryAll,
            icon: const Icon(Icons.print_outlined, size: 18),
            label: Text(tr('In lại tất cả ($n)')),
          ),
          OutlinedButton.icon(
            onPressed: _printers.length > 1 ? _moveAll : null,
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: Text(tr('Chuyển tất cả…')),
          ),
          OutlinedButton.icon(
            onPressed: _cancelAll,
            style: OutlinedButton.styleFrom(
              foregroundColor: SboxColors.danger,
              side: const BorderSide(color: SboxColors.dangerSoft),
            ),
            icon: const Icon(Icons.close, size: 18),
            label: Text(tr('Hủy tất cả ($n)')),
          ),
        ],
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
          const SizedBox(height: 8),
          _filterChips(),
          _bulkBar(),
          const SizedBox(height: 6),
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
                Text(
                    tr(_printerFilter != null || _docFilter != _DocGroup.all
                        ? 'Không có lệnh nào khớp bộ lọc'
                        : _filter == _QueueFilter.problems
                            ? 'Không có lệnh in nào bị treo hay lỗi'
                            : 'Không có lệnh in'),
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
        title: Text(tr('Hàng đợi in'),
            style: const TextStyle(color: PosTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 18)),
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
