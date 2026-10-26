import 'package:flutter/material.dart';

import '../../models/pos_store_printer.dart';
import '../../utils/pos_kitchen_print.dart';
import '../../utils/pos_pending_print_store.dart';
import '../../utils/pos_print_orchestrator.dart';
import '../../utils/pos_printer_transport.dart';
import '../../utils/pos_sale_order_print.dart';
import '../pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
/// Bottom sheet phiếu in treo (HD / kho / bếp / tem) — thử lại / chọn máy / bỏ qua.
Future<void> showPendingWarehousePrintSheet({
  required BuildContext context,
  required List<PendingWarehousePrintJob> jobs,
  List<PendingSalePrintJob> saleJobs = const [],
  List<PendingKitchenPrintJob> kitchenJobs = const [],
  List<PendingCupLabelPrintJob> cupJobs = const [],
  required List<PosStorePrinter> printers,
  required Future<WarehouseSlipPrintResult> Function(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) onRetry,
  required void Function(PendingWarehousePrintJob job) onDismiss,
  Future<bool> Function(
    PendingSalePrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetrySale,
  void Function(PendingSalePrintJob job)? onDismissSale,
  Future<bool> Function(
    PendingKitchenPrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetryKitchen,
  void Function(PendingKitchenPrintJob job)? onDismissKitchen,
  Future<bool> Function(PendingCupLabelPrintJob job)? onRetryCup,
  void Function(PendingCupLabelPrintJob job)? onDismissCup,
  VoidCallback? onDismissAll,
  /// Lệnh lỗi / treo của CẢ cửa hàng (server) — hiện lối sang «Hàng đợi in».
  int storeProblemCount = 0,
  VoidCallback? onOpenStoreQueue,
}) async {
  if (jobs.isEmpty &&
      saleJobs.isEmpty &&
      kitchenJobs.isEmpty &&
      cupJobs.isEmpty) {
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    useSafeArea: true,
    builder: (ctx) {
      return _PendingWarehousePrintSheetBody(
        jobs: jobs,
        saleJobs: saleJobs,
        kitchenJobs: kitchenJobs,
        cupJobs: cupJobs,
        printers: printers,
        onRetry: onRetry,
        onDismiss: onDismiss,
        onRetrySale: onRetrySale,
        onDismissSale: onDismissSale,
        onRetryKitchen: onRetryKitchen,
        onDismissKitchen: onDismissKitchen,
        onRetryCup: onRetryCup,
        onDismissCup: onDismissCup,
        onDismissAll: onDismissAll,
        storeProblemCount: storeProblemCount,
        onOpenStoreQueue: onOpenStoreQueue,
      );
    },
  );
}

class _PendingWarehousePrintSheetBody extends StatefulWidget {
  const _PendingWarehousePrintSheetBody({
    required this.jobs,
    required this.saleJobs,
    required this.kitchenJobs,
    required this.cupJobs,
    required this.printers,
    required this.onRetry,
    required this.onDismiss,
    this.onRetrySale,
    this.onDismissSale,
    this.onRetryKitchen,
    this.onDismissKitchen,
    this.onRetryCup,
    this.onDismissCup,
    this.onDismissAll,
    this.storeProblemCount = 0,
    this.onOpenStoreQueue,
  });

  final List<PendingWarehousePrintJob> jobs;
  final List<PendingSalePrintJob> saleJobs;
  final List<PendingKitchenPrintJob> kitchenJobs;
  final List<PendingCupLabelPrintJob> cupJobs;
  final List<PosStorePrinter> printers;
  final Future<WarehouseSlipPrintResult> Function(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) onRetry;
  final void Function(PendingWarehousePrintJob job) onDismiss;
  final Future<bool> Function(
    PendingSalePrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetrySale;
  final void Function(PendingSalePrintJob job)? onDismissSale;
  final Future<bool> Function(
    PendingKitchenPrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  })? onRetryKitchen;
  final void Function(PendingKitchenPrintJob job)? onDismissKitchen;
  final Future<bool> Function(PendingCupLabelPrintJob job)? onRetryCup;
  final void Function(PendingCupLabelPrintJob job)? onDismissCup;
  final VoidCallback? onDismissAll;
  final int storeProblemCount;
  final VoidCallback? onOpenStoreQueue;

  @override
  State<_PendingWarehousePrintSheetBody> createState() =>
      _PendingWarehousePrintSheetBodyState();
}

class _PendingWarehousePrintSheetBodyState
    extends State<_PendingWarehousePrintSheetBody> {
  String? _busyJobId;
  String? _statusMessage;
  late List<PendingWarehousePrintJob> _localJobs;
  late List<PendingSalePrintJob> _localSaleJobs;
  late List<PendingKitchenPrintJob> _localKitchenJobs;
  late List<PendingCupLabelPrintJob> _localCupJobs;

  @override
  void initState() {
    super.initState();
    _localJobs = List.from(widget.jobs);
    _localSaleJobs = List.from(widget.saleJobs);
    _localKitchenJobs = List.from(widget.kitchenJobs);
    _localCupJobs = List.from(widget.cupJobs);
  }

  int get _totalCount =>
      _localJobs.length +
      _localSaleJobs.length +
      _localKitchenJobs.length +
      _localCupJobs.length;

  // ---------- Lọc theo máy in ----------
  static const _cupGroup = 'Tem ly';
  static const _saleGroup = 'Hóa đơn';

  /// null = mọi máy.
  String? _groupFilter;
  /// «Đang in lại 2/6…» khi chạy hàng loạt.
  String? _bulkProgress;

  String _kitchenGroup(PendingKitchenPrintJob j) =>
      (j.printerName ?? '').trim().isNotEmpty ? j.printerName!.trim() : 'Máy bếp';
  String _warehouseGroup(PendingWarehousePrintJob j) =>
      j.printerName.trim().isNotEmpty ? j.printerName.trim() : 'Xuất kho';

  bool _show(String group) => _groupFilter == null || _groupFilter == group;

  List<PendingKitchenPrintJob> get _visKitchen =>
      _localKitchenJobs.where((j) => _show(_kitchenGroup(j))).toList();
  List<PendingCupLabelPrintJob> get _visCups =>
      _show(_cupGroup) ? _localCupJobs : const [];
  List<PendingSalePrintJob> get _visSales =>
      _show(_saleGroup) ? _localSaleJobs : const [];
  List<PendingWarehousePrintJob> get _visWarehouse =>
      _localJobs.where((j) => _show(_warehouseGroup(j))).toList();

  int get _visibleCount =>
      _visKitchen.length + _visCups.length + _visSales.length + _visWarehouse.length;

  Map<String, int> get _groupCounts {
    final m = <String, int>{};
    void add(String g) => m[g] = (m[g] ?? 0) + 1;
    for (final j in _localKitchenJobs) {
      add(_kitchenGroup(j));
    }
    for (final _ in _localCupJobs) {
      add(_cupGroup);
    }
    for (final _ in _localSaleJobs) {
      add(_saleGroup);
    }
    for (final j in _localJobs) {
      add(_warehouseGroup(j));
    }
    return m;
  }

  /// Máy LAN vừa không kết nối được (app đánh dấu mất kết nối 60s) → in lại sẽ lỗi tiếp.
  bool _printerDown(String? printerId) {
    if ((printerId ?? '').isEmpty) return false;
    final p = widget.printers.where((x) => x.id == printerId).firstOrNull;
    if (p == null || !p.isLan || (p.lanHost ?? '').trim().isEmpty) return false;
    return PosPrinterTransport.isLanMarkedDown(p.lanHost!.trim(), p.lanPort <= 0 ? 9100 : p.lanPort);
  }

  static const _staleMinutes = 30;
  bool _isStale(DateTime at) => DateTime.now().difference(at).inMinutes > _staleMinutes;

  void _closeIfEmpty() {
    if (_totalCount == 0 && mounted) Navigator.pop(context);
  }

  /// In lại mọi phiếu đang hiện (theo bộ lọc), lần lượt — phiếu in được thì gỡ khỏi danh sách.
  Future<void> _retryAllVisible({PosStorePrinter? kitchenTarget}) async {
    final kitchen = _visKitchen;
    final cups = kitchenTarget == null ? _visCups : <PendingCupLabelPrintJob>[];
    final sales = kitchenTarget == null ? _visSales : <PendingSalePrintJob>[];
    final warehouse = kitchenTarget == null
        ? _visWarehouse.where((j) => j.reason != PendingWarehousePrintReason.noPrinterAssignment).toList()
        : <PendingWarehousePrintJob>[];
    final total = kitchen.length + cups.length + sales.length + warehouse.length;
    if (total == 0) return;

    final staleKitchen = kitchen.where((j) => _isStale(j.sentAt)).length +
        cups.where((j) => _isStale(j.createdAt)).length;
    final down = kitchenTarget == null
        ? {for (final j in kitchen) if (_printerDown(j.printerId)) _kitchenGroup(j)}
        : <String>{};
    var skipStale = staleKitchen > 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr(kitchenTarget == null
              ? 'In lại $total phiếu?'
              : 'In ${kitchen.length} phiếu bếp trên «${kitchenTarget.name}»?')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (down.isNotEmpty)
                Text(
                  tr('Máy đang mất kết nối: ${down.join(', ')} — in lại sẽ lỗi tiếp. '
                      'Nên dùng «Chuyển phiếu bếp» sang máy đang chạy.'),
                  style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                ),
              if (staleKitchen > 0)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: skipStale,
                  onChanged: (v) => setD(() => skipStale = v ?? true),
                  title: Text(tr('Bỏ qua $staleKitchen phiếu bếp / tem cũ hơn $_staleMinutes phút'),
                      style: const TextStyle(fontSize: 14)),
                  subtitle: Text(tr('Tránh bếp nhận phiếu cũ rồi làm trùng món'),
                      style: const TextStyle(fontSize: 12)),
                ),
              if (down.isEmpty && staleKitchen == 0)
                Text(tr('Gửi lại lần lượt từng phiếu.')),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('In lại'))),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final runKitchen = skipStale ? kitchen.where((j) => !_isStale(j.sentAt)).toList() : kitchen;
    final runCups = skipStale ? cups.where((j) => !_isStale(j.createdAt)).toList() : cups;
    final n = runKitchen.length + runCups.length + sales.length + warehouse.length;
    var done = 0;
    var printed = 0;
    void tick() => setState(() => _bulkProgress = 'Đang in lại ${++done}/$n…');

    for (final job in runKitchen) {
      if (!mounted) return;
      tick();
      final good = await widget.onRetryKitchen?.call(
            job,
            overridePrinterId: kitchenTarget?.id,
            overridePrinter: kitchenTarget,
          ) ??
          false;
      if (good) {
        printed++;
        widget.onDismissKitchen?.call(job);
        _localKitchenJobs.removeWhere((j) => j.id == job.id);
      }
    }
    for (final job in runCups) {
      if (!mounted) return;
      tick();
      if (await widget.onRetryCup?.call(job) ?? false) {
        printed++;
        widget.onDismissCup?.call(job);
        _localCupJobs.removeWhere((j) => j.id == job.id);
      }
    }
    for (final job in sales) {
      if (!mounted) return;
      tick();
      if (await widget.onRetrySale?.call(job) ?? false) {
        printed++;
        widget.onDismissSale?.call(job);
        _localSaleJobs.removeWhere((j) => j.id == job.id);
      }
    }
    for (final job in warehouse) {
      if (!mounted) return;
      tick();
      final r = await widget.onRetry(job, WarehouseSlipPrintMethod.assigned);
      if (r.anySuccess && !r.hasFailures) {
        printed++;
        widget.onDismiss(job);
        _localJobs.removeWhere((j) => j.id == job.id);
      }
    }
    if (!mounted) return;
    setState(() {
      _bulkProgress = null;
      _statusMessage = printed == n
          ? 'Đã in lại $printed phiếu'
          : 'In lại được $printed/$n phiếu — phiếu còn lại thử «Chuyển phiếu bếp» sang máy khác';
      if (_groupFilter != null && !_groupCounts.containsKey(_groupFilter)) _groupFilter = null;
    });
    _closeIfEmpty();
  }

  Future<void> _moveKitchenVisible() async {
    final p = await _pickPrinter(title: 'Chuyển phiếu bếp sang máy', kitchenOnly: true);
    if (p == null || !mounted) return;
    await _retryAllVisible(kitchenTarget: p);
  }

  /// Bỏ các phiếu đang hiện (theo bộ lọc). Không lọc → giống «Bỏ hết» cũ.
  Future<void> _dismissVisible() async {
    final n = _visibleCount;
    if (n == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Bỏ $n phiếu chưa in?')),
        content: Text(tr('Các phiếu này sẽ không được in nữa.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Không'))),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Bỏ')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_groupFilter == null && widget.onDismissAll != null) {
      widget.onDismissAll!.call();
      setState(() {
        _localJobs.clear();
        _localSaleJobs.clear();
        _localKitchenJobs.clear();
        _localCupJobs.clear();
      });
    } else {
      for (final j in _visKitchen) {
        widget.onDismissKitchen?.call(j);
      }
      for (final j in _visCups) {
        widget.onDismissCup?.call(j);
      }
      for (final j in _visSales) {
        widget.onDismissSale?.call(j);
      }
      for (final j in _visWarehouse) {
        widget.onDismiss(j);
      }
      final g = _groupFilter;
      setState(() {
        _localKitchenJobs.removeWhere((j) => _kitchenGroup(j) == g);
        if (g == _cupGroup) _localCupJobs.clear();
        if (g == _saleGroup) _localSaleJobs.clear();
        _localJobs.removeWhere((j) => _warehouseGroup(j) == g);
        _groupFilter = null;
      });
    }
    _closeIfEmpty();
  }

  Widget _groupChips() {
    final counts = _groupCounts;
    if (counts.length < 2) return const SizedBox.shrink();
    Widget chip(String label, bool selected, VoidCallback onTap, {bool down = false}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [
              if (down) ...[
                Icon(Icons.link_off, size: 14, color: Colors.red.shade700),
                const SizedBox(width: 4),
              ],
              Text(tr(label)),
            ]),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(),
            selectedColor: SboxColors.brand50,
            side: BorderSide(color: selected ? SboxColors.primary : SboxColors.border),
            labelStyle: TextStyle(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? SboxColors.primary : PosTheme.textSecondary,
            ),
          ),
        );
    final downGroups = {
      for (final j in _localKitchenJobs)
        if (_printerDown(j.printerId)) _kitchenGroup(j)
    };
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          chip('Tất cả máy ($_totalCount)', _groupFilter == null, () => setState(() => _groupFilter = null)),
          for (final e in counts.entries)
            chip(
              '${e.key} (${e.value})',
              _groupFilter == e.key,
              () => setState(() => _groupFilter = _groupFilter == e.key ? null : e.key),
              down: downGroups.contains(e.key),
            ),
        ],
      ),
    );
  }

  Widget _bulkActions() {
    if (_bulkProgress != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Row(children: [
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(tr(_bulkProgress!)),
        ]),
      );
    }
    final n = _visibleCount;
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          FilledButton.icon(
            onPressed: _busyJobId == null ? () => _retryAllVisible() : null,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(tr('In lại tất cả ($n)')),
          ),
          if (_visKitchen.isNotEmpty && widget.onRetryKitchen != null)
            OutlinedButton.icon(
              onPressed: _busyJobId == null ? _moveKitchenVisible : null,
              icon: const Icon(Icons.print_outlined, size: 18),
              label: Text(tr('Chuyển phiếu bếp (${_visKitchen.length})…')),
            ),
          OutlinedButton.icon(
            onPressed: _busyJobId == null ? _dismissVisible : null,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade700,
              side: BorderSide(color: Colors.red.shade200),
            ),
            icon: const Icon(Icons.close, size: 18),
            label: Text(tr(_groupFilter == null ? 'Bỏ tất cả ($n)' : 'Bỏ $n phiếu')),
          ),
        ],
      ),
    );
  }

  /// Lệnh lỗi do máy khác gửi / đã đẩy lên server — xem & xử lý ở hàng đợi cả cửa hàng.
  Widget _storeQueueLink() {
    final open = widget.onOpenStoreQueue;
    if (open == null) return const SizedBox.shrink();
    final n = widget.storeProblemCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Material(
        color: SboxColors.slate100,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            Navigator.pop(context);
            open();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              const Icon(Icons.queue_outlined, size: 20, color: PosTheme.kiotBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tr(n > 0
                      ? 'Hàng đợi in cả cửa hàng · $n lệnh lỗi / treo (mọi máy gửi)'
                      : 'Hàng đợi in cả cửa hàng'),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const Icon(Icons.chevron_right, color: PosTheme.textSecondary),
            ]),
          ),
        ),
      ),
    );
  }

  String _pickerKind(PosStorePrinter p) {
    if (p.isLabelPrinter) return 'Tem';
    if (p.isSunmi) return 'Sunmi';
    return p.connectionType;
  }

  Future<PosStorePrinter?> _pickPrinter({
    required String title,
    bool kitchenOnly = false,
  }) async {
    final deviceId = await PosPrintOrchestrator.stableDeviceId();
    var list = PosPrintOrchestrator.uniquePrintersForPicker(
      widget.printers,
      deviceId: deviceId,
    );
    if (kitchenOnly) {
      // Máy bếp + máy hóa đơn — khi máy bếp hỏng vẫn in phiếu ra Sunmi/USB hóa đơn.
      final kitchen = list.where((p) => p.canPrintKitchenSlip).toList();
      if (kitchen.isNotEmpty) {
        list = kitchen;
      } else {
        list = list.where((p) => !p.isLabelPrinter).toList();
      }
    }
    if (list.isEmpty) {
      setState(() => _statusMessage =
          'Chưa có máy in cloud/cửa hàng — mở Máy in cửa hàng rồi thử lại');
      return null;
    }
    return showDialog<PosStorePrinter>(
      context: context,
      builder: (dlgCtx) => SimpleDialog(
        title: Text(tr(title)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              tr(
                kitchenOnly
                    ? '${list.length} máy nhiệt — bếp hoặc hóa đơn (khi máy bếp hỏng). '
                        'In ép lên máy chọn, chỉ món đang treo.'
                    : '${list.length} máy cửa hàng',
              ),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
            ),
          ),
          for (final p in list)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dlgCtx, p),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  tr('${p.name} · ${_pickerKind(p)}'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _retry(
    PendingWarehousePrintJob job,
    WarehouseSlipPrintMethod method, {
    String? overridePrinterId,
  }) async {
    setState(() {
      _busyJobId = job.id;
      _statusMessage = null;
    });
    final result = await widget.onRetry(
      job,
      method,
      overridePrinterId: overridePrinterId,
    );
    if (!mounted) return;
    if (result.anySuccess && !result.hasFailures) {
      widget.onDismiss(job);
      setState(() => _localJobs.removeWhere((j) => j.id == job.id));
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    if (result.anySuccess) {
      setState(() {
        _localJobs.removeWhere((j) => j.id == job.id);
        _statusMessage = result.summaryMessage(lineCount: job.lines.length);
        _busyJobId = null;
      });
      return;
    }
    setState(() {
      _statusMessage = result.summaryMessage(lineCount: job.lines.length);
      _busyJobId = null;
    });
  }

  Future<void> _retrySale(
    PendingSalePrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  }) async {
    final retry = widget.onRetrySale;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'sale:${job.id}';
      _statusMessage = null;
    });
    PosPrinterTransport.lastSunmiError = null;
    final ok = await retry(
      job,
      overridePrinterId: overridePrinterId,
      overridePrinter: overridePrinter,
    );
    if (!mounted) return;
    if (ok) {
      widget.onDismissSale?.call(job);
      setState(() {
        _localSaleJobs.removeWhere((j) => j.id == job.id);
        _statusMessage = overridePrinter == null && overridePrinterId == null
            ? 'In lại hóa đơn thành công'
            : 'In lại hóa đơn trên máy đã chọn';
        _busyJobId = null;
      });
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    final sunmi = PosPrinterTransport.lastSunmiError;
    setState(() {
      _statusMessage = sunmi != null
          ? 'Máy in Sunmi: $sunmi — xử lý rồi bấm In lại'
          : 'In lại hóa đơn thất bại — thử chọn máy khác';
      _busyJobId = null;
    });
  }

  Future<void> _retryKitchen(
    PendingKitchenPrintJob job, {
    String? overridePrinterId,
    PosStorePrinter? overridePrinter,
  }) async {
    final retry = widget.onRetryKitchen;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'kitchen:${job.id}';
      _statusMessage = null;
    });
    final ok = await retry(
      job,
      overridePrinterId: overridePrinterId,
      overridePrinter: overridePrinter,
    );
    if (!mounted) return;
    if (ok) {
      widget.onDismissKitchen?.call(job);
      setState(() {
        _localKitchenJobs.removeWhere((j) => j.id == job.id);
        _statusMessage = overridePrinter == null && overridePrinterId == null
            ? 'In lại phiếu bếp thành công'
            : 'In lại phiếu bếp trên máy đã chọn';
        _busyJobId = null;
      });
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _statusMessage = 'In lại phiếu bếp thất bại — thử chọn máy khác';
      _busyJobId = null;
    });
  }

  Future<void> _retryCup(PendingCupLabelPrintJob job) async {
    final retry = widget.onRetryCup;
    if (retry == null) return;
    setState(() {
      _busyJobId = 'cup:${job.id}';
      _statusMessage = null;
    });
    final ok = await retry(job);
    if (!mounted) return;
    if (ok) {
      widget.onDismissCup?.call(job);
      setState(() => _localCupJobs.removeWhere((j) => j.id == job.id));
      if (_totalCount == 0 && mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _statusMessage = 'In lại tem ly thất bại';
      _busyJobId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.86;
    return SafeArea(
      child: SizedBox(
        height: maxH,
        child: Material(
          color: Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.print_disabled_outlined,
                        size: 22, color: Colors.orange.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        tr('Phiếu chưa in ($_totalCount)'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              _storeQueueLink(),
              _groupChips(),
              _bulkActions(),
              if (_statusMessage != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Text(
                    tr(_statusMessage!),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.orange.shade900, fontSize: 13),
                  ),
                ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                  children: [
                    if (_visKitchen.isNotEmpty) ...[
                      _sectionLabel('Bếp / hủy'),
                      for (final job in _visKitchen)
                        _buildKitchenRow(job),
                    ],
                    if (_visCups.isNotEmpty) ...[
                      _sectionLabel('Tem ly'),
                      for (final job in _visCups) _buildCupRow(job),
                    ],
                    if (_visSales.isNotEmpty) ...[
                      _sectionLabel('Hóa đơn'),
                      for (final job in _visSales) _buildSaleRow(job),
                    ],
                    if (_visWarehouse.isNotEmpty) ...[
                      _sectionLabel('Xuất kho'),
                      for (final job in _visWarehouse) _buildWarehouseRow(job),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Text(
          tr(text),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: PosTheme.textSecondary,
          ),
        ),
      );

  Widget _denseRow({
    required Color bg,
    required String title,
    required String subtitle,
    required String? error,
    required bool busy,
    required List<Widget> actions,
    required VoidCallback? onDismiss,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            height: 1.2,
                          ),
                        ),
                        if (subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            tr(subtitle),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: PosTheme.textSecondary,
                              height: 1.2,
                            ),
                          ),
                        ],
                        if ((error ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            tr(error!),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(left: 8, top: 2),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                ],
              ),
              if (!busy) ...[
                const SizedBox(height: 8),
                _actionBar([...actions, _pillBtn(
                  icon: Icons.close,
                  label: 'Bỏ',
                  onPressed: onDismiss,
                  fg: Colors.red.shade700,
                  bg: Colors.white,
                  border: Colors.red.shade200,
                )]),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionBar(List<Widget> buttons) {
    if (buttons.length <= 3) {
      return Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: buttons[i]),
          ],
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: buttons[0]),
            const SizedBox(width: 8),
            Expanded(child: buttons[1]),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 2; i < buttons.length; i++) ...[
              if (i > 2) const SizedBox(width: 8),
              Expanded(child: buttons[i]),
            ],
          ],
        ),
      ],
    );
  }

  Widget _action({
    required IconData icon,
    required String tip,
    required VoidCallback onPressed,
    Color? color,
  }) {
    final c = color ?? PosTheme.kiotBlue;
    return _pillBtn(
      icon: icon,
      label: tip,
      onPressed: onPressed,
      fg: c,
      bg: c.withOpacity(0.12),
    );
  }

  Widget _pillBtn({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color fg,
    required Color bg,
    Color? border,
  }) {
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 40,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: border == null ? null : Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  tr(label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKitchenRow(PendingKitchenPrintJob job) {
    final busy = _busyJobId == 'kitchen:${job.id}' || _bulkProgress != null;
    final printer = (job.printerName ?? '').trim().isNotEmpty
        ? ' · ${job.printerName}'
        : '';
    return _denseRow(
      bg: SboxColors.warningSoft,
      title: '${job.title} · ${job.tableName}$printer',
      subtitle: job.lineSummary,
      error: job.errorMessage ?? 'In phiếu bếp thất bại',
      busy: busy,
      onDismiss: () {
        widget.onDismissKitchen?.call(job);
        setState(() => _localKitchenJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        _action(
          icon: Icons.refresh,
          tip: 'In lại',
          onPressed: () => _retryKitchen(job),
        ),
        _action(
          icon: Icons.print_outlined,
          tip: 'Máy khác',
          onPressed: () async {
            final p = await _pickPrinter(
              title: 'Chọn máy in phiếu bếp',
              kitchenOnly: true,
            );
            if (p == null || !mounted) return;
            await _retryKitchen(
              job,
              overridePrinterId: p.id,
              overridePrinter: p,
            );
          },
        ),
      ],
    );
  }

  Widget _buildCupRow(PendingCupLabelPrintJob job) {
    final busy = _busyJobId == 'cup:${job.id}' || _bulkProgress != null;
    final table = (job.tableLabel ?? '').trim();
    return _denseRow(
      bg: SboxColors.successSoft,
      title: 'Tem ly × ${job.tickets.length}${table.isNotEmpty ? ' · $table' : ''}',
      subtitle: job.lineSummary,
      error: job.errorMessage ?? 'In tem ly thất bại',
      busy: busy,
      onDismiss: () {
        widget.onDismissCup?.call(job);
        setState(() => _localCupJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        _action(
          icon: Icons.refresh,
          tip: 'In lại',
          onPressed: () => _retryCup(job),
        ),
      ],
    );
  }

  Widget _buildSaleRow(PendingSalePrintJob job) {
    final busy = _busyJobId == 'sale:${job.id}' || _bulkProgress != null;
    return _denseRow(
      bg: SboxColors.brand50,
      title: job.orderLabel,
      subtitle: job.lineSummary,
      error: job.errorMessage ?? 'In hóa đơn thất bại',
      busy: busy,
      onDismiss: () {
        widget.onDismissSale?.call(job);
        setState(() => _localSaleJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        _action(
          icon: Icons.refresh,
          tip: 'In lại',
          onPressed: () => _retrySale(job),
        ),
        _action(
          icon: Icons.print_outlined,
          tip: 'Máy khác',
          onPressed: () async {
            final p = await _pickPrinter(title: 'Chọn máy in hóa đơn');
            if (p == null || !mounted) return;
            await _retrySale(
              job,
              overridePrinterId: p.id,
              overridePrinter: p,
            );
          },
        ),
      ],
    );
  }

  Widget _buildWarehouseRow(PendingWarehousePrintJob job) {
    final busy = _busyJobId == job.id || _bulkProgress != null;
    final printer = job.printerName.isNotEmpty ? ' · ${job.printerName}' : '';
    return _denseRow(
      bg: SboxColors.warningSoft,
      title: '${job.orderLabel}$printer',
      subtitle: job.lineSummary,
      error: job.errorMessage ?? job.reason.label,
      busy: busy,
      onDismiss: () {
        widget.onDismiss(job);
        setState(() => _localJobs.removeWhere((j) => j.id == job.id));
        if (_totalCount == 0 && context.mounted) Navigator.pop(context);
      },
      actions: [
        if (job.reason != PendingWarehousePrintReason.noPrinterAssignment)
          _action(
            icon: Icons.refresh,
            tip: 'In lại',
            onPressed: () =>
                _retry(job, WarehouseSlipPrintMethod.assigned),
          ),
        _action(
          icon: Icons.print_outlined,
          tip: 'Máy khác',
          onPressed: () async {
            final p = await _pickPrinter(title: 'Chọn máy in xuất kho');
            if (p == null || !mounted) return;
            await _retry(
              job,
              WarehouseSlipPrintMethod.pickPrinter,
              overridePrinterId: p.id,
            );
          },
        ),
        _action(
          icon: Icons.settings_ethernet,
          tip: 'Cục bộ',
          onPressed: () =>
              _retry(job, WarehouseSlipPrintMethod.localThermal),
        ),
      ],
    );
  }
}

/// Nút máy in có badge phiếu treo trên header thu ngân.
class PosPendingPrintIconButton extends StatelessWidget {
  const PosPendingPrintIconButton({
    super.key,
    required this.pendingCount,
    required this.onTap,
    this.iconColor = Colors.white,
    this.compact = false,
  });

  final int pendingCount;
  final VoidCallback onTap;
  final Color iconColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tooltip = tr(pendingCount > 0
        ? 'Phiếu chưa in ($pendingCount)'
        : 'Phiếu in treo');
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Icon(
                  pendingCount > 0
                      ? Icons.print_disabled_outlined
                      : Icons.receipt_long_outlined,
                  size: compact ? 24 : 26,
                  color: pendingCount > 0 ? Colors.orange.shade200 : iconColor,
                ),
                if (pendingCount > 0)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white, width: 1),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        tr(pendingCount > 99 ? '99+' : '$pendingCount'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
