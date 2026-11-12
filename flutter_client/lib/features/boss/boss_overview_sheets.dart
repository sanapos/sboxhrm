import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../screens/pos_sale_order_editor_screen.dart';
import '../../screens/staff/staff_nav.dart';
import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/branch_switcher.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/reports/report_drill_sheet.dart';
import '../../widgets/sbox/sbox_basics.dart';
import '../../widgets/sbox/sbox_charts.dart';
import 'boss_end_of_day_screen.dart';
import 'boss_reports_screen.dart';

/// Mở một màn của BOSS (khung tiêu đề xanh + chọn chi nhánh như tab Báo cáo).
void bossPushPage(BuildContext context, String title, Widget body) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(
        backgroundColor: SboxColors.brand700,
        foregroundColor: SboxColors.white,
        title: Text(tr(title)),
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: SboxSpace.sm),
            child: Center(child: BranchSwitcher(compact: true, onDark: true)),
          ),
        ],
      ),
      body: body,
    ),
  ));
}

/// «Cuối ngày»: tiền két, thực thu, hủy đơn, món bán chạy.
void bossOpenEndOfDay(BuildContext context) => bossPushPage(context, 'Cuối ngày', const BossEndOfDayScreen());

/// Một báo cáo của tab Báo cáo (Kinh doanh, Sổ quỹ, Chi phí…).
void bossOpenReport(BuildContext context, BossReportType type) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => BossReportDetailScreen(type: type, startToday: true)));

/// Tên phương thức thanh toán lưu trên đơn («Cash», «BankTransfer», «Mixed»…) → chữ cho chủ quán.
String bossPaymentLabel(String raw) => switch (raw.trim()) {
      'Cash' => 'Tiền mặt',
      'BankTransfer' => 'Chuyển khoản',
      'VietQR' => 'VietQR',
      'Card' => 'Thẻ',
      'EWallet' => 'Ví điện tử',
      'Mixed' => 'Nhiều hình thức',
      'Debt' => 'Công nợ',
      final s => s,
    };

/// Danh sách đơn hôm nay (theo giờ / đơn hủy / đơn còn nợ). Bấm đơn → xem đơn (khi có quyền Đơn hàng).
Future<void> showBossOrdersSheet(
  BuildContext context, {
  required String title,
  int? hour,
  String? kind,
  ApiService? api,
}) {
  final canOpenOrder = staffCanOpen(context, 'PosSaleOrders', listen: false);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SboxColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (sheetCtx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (ctx, controller) => FutureBuilder<Map<String, dynamic>>(
        future: (api ?? ApiService()).getBossOrders(hour: hour, kind: kind),
        builder: (ctx, snap) {
          final r = snap.data;
          final data = r?['data'] is Map ? Map<String, dynamic>.from(r!['data'] as Map) : null;
          final items = [
            for (final e in (data?['items'] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e),
          ];
          double n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tr(title), style: SboxType.titleSmStyle()),
                  if (data != null)
                    Text(tr('${items.length} đơn · ${SboxFmt.money(n(data['total']))}'),
                        style: SboxType.captionStyle()),
                ]),
              ),
              IconButton(
                tooltip: tr('Đóng'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(sheetCtx).pop(),
              ),
            ]),
          );
          Widget body;
          if (snap.connectionState != ConnectionState.done) {
            body = const SboxLoading();
          } else if (r?['isSuccess'] != true) {
            body = Center(child: Text(tr(r?['message']?.toString() ?? 'Không tải được danh sách đơn')));
          } else if (items.isEmpty) {
            body = const SboxEmptyState(icon: Icons.receipt_long_rounded, title: 'Không có đơn');
          } else {
            body = ListView.separated(
              controller: controller,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final o = items[i];
                final unpaid = n(o['unpaid']);
                final who = [
                  if ('${o['customerName'] ?? ''}'.isNotEmpty) '${o['customerName']}',
                  if ('${o['soldBy'] ?? ''}'.isNotEmpty) tr('NV: ${o['soldBy']}'),
                  if ('${o['paymentMethod'] ?? ''}'.isNotEmpty) tr(bossPaymentLabel('${o['paymentMethod']}')),
                ].join(' · ');
                return ListTile(
                  dense: true,
                  onTap: canOpenOrder && '${o['id'] ?? ''}'.isNotEmpty
                      ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => PosHubScope.pushed(child: PosSaleOrderEditorScreen(orderId: '${o['id']}')),
                          ))
                      : null,
                  leading: Text('${o['time'] ?? ''}', style: SboxType.bodyStrong()),
                  title: Text('${o['orderNo'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: who.isEmpty ? null : Text(who, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(SboxFmt.money(n(o['total'])), style: SboxType.bodyStrong()),
                    if (unpaid > 0)
                      Text(tr('Còn nợ ${SboxFmt.money(unpaid)}'),
                          style: const TextStyle(fontSize: 11, color: SboxColors.dangerText, fontWeight: FontWeight.w600)),
                  ]),
                );
              },
            );
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(color: SboxColors.slate300, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            header,
            const Divider(height: 1),
            Expanded(child: body),
          ]);
        },
      ),
    ),
  );
}

/// Bàn / phòng đang phục vụ: tên, khu, giờ mở, đã ngồi bao lâu, tạm tính.
Future<void> showBossOpenTablesSheet(BuildContext context, List<Map<String, dynamic>> items, double total) {
  double n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
  String dur(int m) => m >= 60 ? '${m ~/ 60} giờ ${m % 60} phút' : '$m phút';
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: SboxColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: items.length > 5 ? 0.7 : 0.45,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tr('Bàn đang mở (${items.length})'), style: SboxType.titleSmStyle()),
                Text(tr('Tạm tính ${SboxFmt.money(total)} · bàn mở lâu nhất ở trên'), style: SboxType.captionStyle()),
              ]),
            ),
            IconButton(icon: const Icon(Icons.close), tooltip: tr('Đóng'), onPressed: () => Navigator.of(ctx).pop()),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? const SboxEmptyState(icon: Icons.table_restaurant_rounded, title: 'Không có bàn đang mở')
              : ListView.separated(
                  controller: controller,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = items[i];
                    final minutes = n(t['minutes']).toInt();
                    final sub = [
                      if ('${t['area'] ?? ''}'.isNotEmpty) '${t['area']}',
                      tr('Mở ${t['startedAt'] ?? ''} · ${dur(minutes)}'),
                      if (n(t['guests']) > 1) tr('${n(t['guests']).toInt()} khách'),
                    ].join(' · ');
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.table_restaurant_rounded,
                          color: minutes >= 180 ? SboxColors.warning : SboxColors.brand600),
                      title: Text('${t['name'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(SboxFmt.money(n(t['amount'])), style: SboxType.bodyStrong()),
                        if (t['billRequested'] == true)
                          Text(tr('Đã gọi tính tiền'),
                              style: const TextStyle(fontSize: 11, color: SboxColors.warningText, fontWeight: FontWeight.w600)),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    ),
  );
}

/// Giải thích các số trên Tổng quan — chủ quán hay hỏi «doanh thu khác đã thu chỗ nào».
Future<void> showBossNumbersHelp(BuildContext context) {
  Widget item(String t, String d) => Padding(
        padding: const EdgeInsets.only(bottom: SboxSpace.md),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr(t), style: SboxType.bodyStrong()),
          const SizedBox(height: 2),
          Text(tr(d), style: SboxType.smallStyle(SboxColors.textMuted)),
        ]),
      );
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: SboxColors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(SboxSpace.lg, SboxSpace.lg, SboxSpace.lg, SboxSpace.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('Các số trên Tổng quan tính thế nào?'), style: SboxType.titleSmStyle()),
        const SizedBox(height: SboxSpace.md),
        item('Doanh thu', 'Tổng tiền các đơn đã thanh toán / chốt trong ngày kinh doanh (sau giảm giá). Bàn đang mở chưa tính.'),
        item('Đã thu', 'Tiền thực nhận từ bán hàng hôm nay theo phiếu thu (tiền mặt, chuyển khoản, thẻ…).'),
        item('Chưa thu', 'Phần khách còn nợ trên các đơn đã chốt hôm nay. Doanh thu − Đã thu thường bằng số này.'),
        item('Đã chi', 'Tổng phiếu chi hôm nay (nhập hàng trả tiền ngay, chi phí, hoàn tiền…).'),
        item('Thu − chi', 'Đã thu trừ Đã chi: tiền thực còn lại của ngày, chưa tính tồn quỹ đầu ngày.'),
        item('Cùng giờ tuần trước', 'Doanh thu cùng thứ tuần trước, tính từ đầu ngày tới đúng giờ hiện tại — so công bằng khi ngày chưa hết.'),
        item('Bàn đang mở', 'Bàn / phòng khách đang ngồi, tiền tạm tính chưa vào doanh thu.'),
        const SizedBox(height: SboxSpace.sm),
        Text(tr('Bấm vào từng số để xem chi tiết.'), style: SboxType.captionStyle()),
      ]),
    ),
  );
}


// ─── Chi tiết số liệu báo cáo BOSS («số này từ đâu ra») ───────────────────────

String _bossDrillTime(Object? raw) {
  var d = DateTime.tryParse('${raw ?? ''}');
  if (d == null) return '';
  if (d.isUtc) d = d.toLocal();
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

String _bossDrillDate(Object? raw) {
  final s = _bossDrillTime(raw);
  return s.isEmpty ? '' : s.split(' ').first;
}

double _bossDrillNum(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

List<Map<String, dynamic>> _bossDrillList(Object? v) =>
    [for (final e in (v is List ? v : const [])) if (e is Map) Map<String, dynamic>.from(e)];

/// Tải dữ liệu trước (vòng quay giữa màn) rồi mới mở sheet — để dòng «Tổng» / ghi chú cắt bớt lấy đúng số API.
Future<T?> bossDrillFetch<T>(BuildContext context, Future<T> Function() fetch) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.maybeOf(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  try {
    final v = await fetch();
    nav.pop();
    return v;
  } catch (e) {
    nav.pop();
    messenger?.showSnackBar(SnackBar(content: Text(tr('Không tải được dữ liệu'))));
    return null;
  }
}

/// Mở một đơn bán (khi có quyền Đơn hàng) — cùng cách mở như danh sách đơn hôm nay.
VoidCallback? bossSaleOrderTap(BuildContext context, Object? id, {bool? canOpen}) {
  final sid = '${id ?? ''}';
  if (sid.isEmpty || !(canOpen ?? staffCanOpen(context, 'PosSaleOrders', listen: false))) return null;
  return () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PosHubScope.pushed(child: PosSaleOrderEditorScreen(orderId: sid)),
      ));
}

/// Đơn hoàn thành trong kỳ (báo cáo bán hàng sales/orders — cùng bộ lọc cửa hàng / chi nhánh / người xem / kỳ
/// với Kinh doanh, Lãi theo món, Nhân viên). Tải tối đa [maxRows] đơn mới nhất; dòng tổng = Σ tiền hàng chưa VAT
/// (= doanh thu) của các đơn đã tải.
Future<void> showBossSalesOrdersDrill(
  BuildContext context, {
  required String title,
  required DateTime from,
  required DateTime to,
  String? staffKey,
  String? productId,
  String? subtitle,
  String? note,
  bool showTotal = true,
  int maxRows = 600,
}) async {
  final canOpen = staffCanOpen(context, 'PosSaleOrders', listen: false);
  final res = await bossDrillFetch(context, () async {
    final api = ApiService();
    final out = <Map<String, dynamic>>[];
    var count = 0;
    var page = 1;
    while (true) {
      final r = await api.getPosSalesReportOrders(from: from, to: to, page: page, pageSize: 200, staffKey: staffKey, productId: productId);
      if (r['isSuccess'] != true || r['data'] is! Map) throw Exception(r['message'] ?? 'Không tải được danh sách đơn');
      final data = Map<String, dynamic>.from(r['data'] as Map);
      count = _bossDrillNum(data['total']).toInt();
      final items = _bossDrillList(data['items']);
      out.addAll(items);
      if (items.isEmpty || out.length >= count || out.length >= maxRows) break;
      page++;
    }
    return (out, count);
  });
  if (res == null || !context.mounted) return;
  final (items, count) = res;
  final sum = items.fold<double>(0, (a, o) => a + _bossDrillNum(o['total']));
  await showReportDrillSheet(
    context,
    title: title,
    subtitle: subtitle,
    note: note,
    countLabel: SboxFmt.number(count),
    emptyText: 'Không có đơn trong kỳ',
    total: showTotal ? 'Tổng ${SboxFmt.money(sum)}' : null,
    footer: items.length < count
        ? 'Hiện ${items.length} / ${SboxFmt.number(count)} đơn mới nhất; dòng tổng chỉ cộng các đơn đang hiện.'
        : null,
    rows: [
      for (final o in items)
        ReportDrillRow(
          title: '${o['orderNo'] ?? ''}',
          icon: Icons.receipt_long_rounded,
          subtitle: [
            _bossDrillTime(o['saleDate'] ?? o['createdAt']),
            if ('${o['customerName'] ?? ''}'.isNotEmpty) '${o['customerName']}',
            if ('${o['soldByName'] ?? o['soldBy'] ?? ''}'.isNotEmpty) 'NV: ${o['soldByName'] ?? o['soldBy']}',
            if ('${o['paymentMethod'] ?? ''}'.isNotEmpty) bossPaymentLabel('${o['paymentMethod']}'),
          ].where((s) => s.isNotEmpty).join(' · '),
          trailing: SboxFmt.money(_bossDrillNum(o['total'])),
          onTap: bossSaleOrderTap(context, o['id'], canOpen: canOpen),
        ),
    ],
  );
}

/// Phiếu thu / chi từ các endpoint `/api/pos/reports/drill-boss/...` (sổ quỹ, chi phí, dòng lãi lỗ).
/// Tổng và số phiếu do API tính trên mọi phiếu (danh sách cắt 500 dòng mới nhất).
Future<void> showBossCashDrill(
  BuildContext context, {
  required String title,
  required String path,
  required Map<String, String> query,
  String? subtitle,
  String? note,
}) async {
  final data = await bossDrillFetch(context, () async {
    final r = await ApiService().getReportJson(path, query: query);
    if (r['isSuccess'] != true || r['data'] is! Map) throw Exception(r['message'] ?? 'Không tải được danh sách phiếu');
    return Map<String, dynamic>.from(r['data'] as Map);
  });
  if (data == null || !context.mounted) return;
  final items = _bossDrillList(data['items']);
  final count = _bossDrillNum(data['count']);
  await showReportDrillSheet(
    context,
    title: title,
    subtitle: subtitle,
    note: note,
    countLabel: SboxFmt.number(count),
    emptyText: 'Không có phiếu trong kỳ',
    total: 'Tổng ${SboxFmt.money(_bossDrillNum(data['total']))}',
    footer: data['truncated'] == true
        ? 'Hiện ${items.length} / ${SboxFmt.number(count)} phiếu mới nhất; tổng tính trên mọi phiếu.'
        : null,
    rows: [
      for (final c in items)
        ReportDrillRow(
          title: '${c['description'] ?? ''}'.trim().isEmpty ? '${c['transactionCode'] ?? ''}' : '${c['description']}',
          icon: '${c['type']}' == 'Income' ? Icons.south_west_rounded : Icons.north_east_rounded,
          subtitle: [
            '${c['transactionCode'] ?? ''}',
            _bossDrillTime(c['transactionDate']),
            if ('${c['category'] ?? ''}'.isNotEmpty) '${c['category']}',
            if ('${c['paymentMethod'] ?? ''}'.isNotEmpty) bossPaymentLabel('${c['paymentMethod']}'),
            if ('${c['contactName'] ?? ''}'.isNotEmpty) '${c['contactName']}',
          ].where((s) => s.isNotEmpty).join(' · '),
          trailing: SboxFmt.money(_bossDrillNum(c['amount'])),
          trailingColor: _bossDrillNum(c['amount']) < 0 ? SboxColors.successText : null,
        ),
    ],
  );
}

/// Hàng tồn kho theo trạng thái (stock/products: filter OutOfStock / BelowMin / null = mọi mặt hàng)
/// — cùng nguồn với ô Kho.
Future<void> showBossStockProductsDrill(
  BuildContext context, {
  required String title,
  String? filter,
  bool sortValue = false,
  bool showValue = true,
  String? note,
}) async {
  final res = await bossDrillFetch(context, () async {
    final api = ApiService();
    final out = <Map<String, dynamic>>[];
    var count = 0;
    var totalValue = 0.0;
    var page = 1;
    while (true) {
      final r = await api.getPosStockReportProducts(
          filter: filter, page: page, pageSize: 200, sort: sortValue ? 'value' : null);
      if (r['isSuccess'] != true || r['data'] is! Map) throw Exception(r['message'] ?? 'Không tải được tồn kho');
      final data = Map<String, dynamic>.from(r['data'] as Map);
      count = _bossDrillNum(data['total']).toInt();
      totalValue = _bossDrillNum(data['totalValue']);
      final items = _bossDrillList(data['items']);
      out.addAll(items);
      if (items.isEmpty || out.length >= count || out.length >= 1000) break;
      page++;
    }
    return (out, count, totalValue);
  });
  if (res == null || !context.mounted) return;
  final (items, count, totalValue) = res;
  await showReportDrillSheet(
    context,
    title: title,
    note: note,
    countLabel: SboxFmt.number(count),
    total: showValue ? 'Tổng giá trị tồn ${SboxFmt.money(totalValue)}' : null,
    footer: items.length < count ? 'Hiện ${items.length} / ${SboxFmt.number(count)} mặt hàng.' : null,
    rows: [
      for (final p in items)
        ReportDrillRow(
          title: '${p['name'] ?? ''}',
          icon: Icons.inventory_2_rounded,
          subtitle: [
            if ('${p['productCode'] ?? ''}'.isNotEmpty) '${p['productCode']}',
            'Tồn ${SboxFmt.qty(_bossDrillNum(p['onHandQty']))} ${p['baseUnitName'] ?? ''}'.trim(),
            if (_bossDrillNum(p['minStockQty']) > 0) 'tối thiểu ${SboxFmt.qty(_bossDrillNum(p['minStockQty']))}',
          ].join(' · '),
          trailing: showValue ? SboxFmt.money(_bossDrillNum(p['stockValue'])) : null,
          trailingColor: _bossDrillNum(p['onHandQty']) <= 0 ? SboxColors.dangerText : null,
        ),
    ],
  );
}

/// Lô theo hạn dùng (stock/lots: filter expired / expiring) — cùng ngưỡng với ô «Hạn sử dụng».
Future<void> showBossStockLotsDrill(BuildContext context, {required String title, required String filter}) async {
  final data = await bossDrillFetch(context, () async {
    final r = await ApiService().getPosStockLotReport(filter: filter, pageSize: 500);
    if (r['isSuccess'] != true || r['data'] is! Map) throw Exception(r['message'] ?? 'Không tải được lô hàng');
    return Map<String, dynamic>.from(r['data'] as Map);
  });
  if (data == null || !context.mounted) return;
  final items = _bossDrillList(data['items']);
  final count = _bossDrillNum(data['total']);
  await showReportDrillSheet(
    context,
    title: title,
    countLabel: SboxFmt.number(count),
    total: 'Tổng giá trị ${SboxFmt.money(_bossDrillNum(data['totalValue']))}',
    footer: items.length < count ? 'Hiện ${items.length} / ${SboxFmt.number(count)} lô.' : null,
    rows: [
      for (final l in items)
        ReportDrillRow(
          title: '${l['productName'] ?? ''}',
          icon: Icons.event_busy_rounded,
          subtitle: [
            if ('${l['lotNo'] ?? ''}'.isNotEmpty) 'Lô ${l['lotNo']}',
            if (l['expiryDate'] != null) 'HSD ${_bossDrillDate(l['expiryDate'])}',
            if (l['daysUntilExpiry'] is num)
              (l['daysUntilExpiry'] as num) < 0
                  ? 'quá hạn ${-(l['daysUntilExpiry'] as num)} ngày'
                  : 'còn ${l['daysUntilExpiry']} ngày',
            'SL ${SboxFmt.qty(_bossDrillNum(l['qtyOnHand']))} ${l['unitName'] ?? ''}'.trim(),
          ].join(' · '),
          trailing: SboxFmt.money(_bossDrillNum(l['stockValue'])),
        ),
    ],
  );
}

/// Hàng theo tốc độ bán (stock/health mode=hot / slow / dead) — cùng mặc định kỳ / ngưỡng với ô «Tốc độ bán».
Future<void> showBossStockHealthDrill(BuildContext context, {required String title, required String mode, String? note}) async {
  final data = await bossDrillFetch(context, () async {
    final r = await ApiService().getPosStockHealthReport(mode: mode, limit: 1000);
    if (r['isSuccess'] != true || r['data'] is! Map) throw Exception(r['message'] ?? 'Không tải được báo cáo');
    return Map<String, dynamic>.from(r['data'] as Map);
  });
  if (data == null || !context.mounted) return;
  final items = _bossDrillList(data['items']);
  final count = _bossDrillNum(data['total']);
  await showReportDrillSheet(
    context,
    title: title,
    note: note,
    countLabel: SboxFmt.number(count),
    total: 'Tổng giá trị tồn ${SboxFmt.money(_bossDrillNum(data['totalValue']))}',
    footer: items.length < count ? 'Hiện ${items.length} / ${SboxFmt.number(count)} mặt hàng.' : null,
    rows: [
      for (final p in items)
        ReportDrillRow(
          title: '${p['name'] ?? ''}',
          icon: Icons.speed_rounded,
          subtitle: [
            'Tồn ${SboxFmt.qty(_bossDrillNum(p['onHandQty']))} ${p['baseUnitName'] ?? ''}'.trim(),
            'đã bán ${SboxFmt.qty(_bossDrillNum(p['qtySold']))}',
            if (p['coverDays'] is num) 'đủ bán ${SboxFmt.decimal(p['coverDays'] as num)} ngày',
            if (p['daysIdle'] is num) '${p['daysIdle']} ngày chưa bán',
          ].join(' · '),
          trailing: SboxFmt.money(_bossDrillNum(p['stockValue'])),
        ),
    ],
  );
}
