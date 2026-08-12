import 'package:intl/intl.dart';

import '../../models/pos_purchase.dart';
import '../../models/pos_stock_count.dart';
import '../../models/pos_stock_issue_doc.dart';
import '../../services/api_service.dart';
import 'wh_doc_type.dart';

/// Tải danh sách phiếu kho theo loại — tách khỏi UI.
class WhMobileDocService {
  WhMobileDocService([ApiService? api]) : _api = api ?? ApiService();

  final ApiService _api;
  final _moneyFmt = NumberFormat('#,##0', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'vi_VN');

  String formatMoney(num v) => '${_moneyFmt.format(v)} đ';
  String formatDate(DateTime? d) => d != null ? _dateFmt.format(d.toLocal()) : '—';

  Future<({List<WhDocListItem> items, int total})> loadList(
    WhDocType type, {
    String? search,
    List<String>? statuses,
    int page = 1,
    int pageSize = 30,
  }) async {
    final st = statuses ?? ['Draft', 'InProgress', 'Completed', 'Cancelled'];
    switch (type) {
      case WhDocType.purchaseReceipt:
        return _loadPurchaseReceipts(search: search, statuses: st, page: page, pageSize: pageSize);
      case WhDocType.purchaseReturn:
        return _loadPurchaseReturns(search: search, statuses: st, page: page, pageSize: pageSize);
      case WhDocType.stockCount:
        return _loadStockCounts(search: search, statuses: st, page: page, pageSize: pageSize);
      case WhDocType.damageIssue:
      case WhDocType.internalUseIssue:
        return _loadStockIssues(type, search: search, statuses: st, page: page, pageSize: pageSize);
    }
  }

  Future<({List<WhDocListItem> items, int total})> _loadPurchaseReceipts({
    String? search,
    required List<String> statuses,
    required int page,
    required int pageSize,
  }) async {
    final res = await _api.getPosPurchaseReceipts(
      search: search,
      statuses: statuses.where((s) => s != 'InProgress').toList(),
      page: page,
      pageSize: pageSize,
    );
    if (res['isSuccess'] != true || res['data'] is! Map) {
      return (items: <WhDocListItem>[], total: 0);
    }
    final data = res['data'] as Map;
    final items = ((data['items'] as List?) ?? [])
        .map((e) => PosPurchaseReceipt.fromJson(e as Map<String, dynamic>))
        .map((r) => WhDocListItem(
              id: r.id,
              docNo: r.receiptNo,
              status: r.status,
              amount: r.grandTotal,
              lineCount: r.lines.length,
              subtitle: r.supplierName,
              meta: '${r.lines.length} dòng · ${formatDate(r.importDate ?? r.createdAt)}',
              createdAt: r.createdAt,
              createdBy: r.createdBy,
              note: r.note,
            ))
        .toList();
    return (items: items, total: (data['total'] as num?)?.toInt() ?? items.length);
  }

  Future<({List<WhDocListItem> items, int total})> _loadPurchaseReturns({
    String? search,
    required List<String> statuses,
    required int page,
    required int pageSize,
  }) async {
    final res = await _api.getPosPurchaseReturns(
      search: search,
      statuses: statuses.where((s) => s != 'InProgress').toList(),
      page: page,
      pageSize: pageSize,
    );
    if (res['isSuccess'] != true || res['data'] is! Map) {
      return (items: <WhDocListItem>[], total: 0);
    }
    final data = res['data'] as Map;
    final items = ((data['items'] as List?) ?? [])
        .map((e) => PosPurchaseReturn.fromJson(e as Map<String, dynamic>))
        .map((r) => WhDocListItem(
              id: r.id,
              docNo: r.returnNo,
              status: r.status,
              amount: r.totalAmount,
              lineCount: r.lines.length,
              subtitle: r.supplierName,
              meta: '${r.lines.length} dòng · ${formatDate(r.returnDate)}',
              createdAt: r.returnDate,
              createdBy: r.createdBy,
              note: r.note,
            ))
        .toList();
    return (items: items, total: (data['total'] as num?)?.toInt() ?? items.length);
  }

  Future<({List<WhDocListItem> items, int total})> _loadStockCounts({
    String? search,
    required List<String> statuses,
    required int page,
    required int pageSize,
  }) async {
    final normalized = statuses.map((s) => s == 'Draft' ? 'InProgress' : s).toSet().toList();
    final res = await _api.getPosStockCounts(
      search: search,
      statuses: normalized,
      page: page,
      pageSize: pageSize,
    );
    if (res['isSuccess'] != true || res['data'] is! Map) {
      return (items: <WhDocListItem>[], total: 0);
    }
    final data = res['data'] as Map;
    final items = ((data['items'] as List?) ?? [])
        .map((e) => PosStockCount.fromJson(e as Map<String, dynamic>))
        .map((c) => WhDocListItem(
              id: c.id,
              docNo: c.countNo,
              status: c.status,
              amount: c.totalDiffValue.abs(),
              lineCount: c.lineCount,
              subtitle: c.name,
              meta: '${c.checkedCount}/${c.lineCount} đã kiểm · ${formatDate(c.createdAt)}',
              createdAt: c.createdAt,
              createdBy: c.createdBy,
              note: c.note,
            ))
        .toList();
    return (items: items, total: (data['total'] as num?)?.toInt() ?? items.length);
  }

  Future<({List<WhDocListItem> items, int total})> _loadStockIssues(
    WhDocType type, {
    String? search,
    required List<String> statuses,
    required int page,
    required int pageSize,
  }) async {
    final kind = type.stockIssueConfig!.kind;
    final res = await _api.getPosStockIssueDocs(
      kind,
      search: search,
      statuses: statuses.where((s) => s != 'InProgress').toList(),
      page: page,
      pageSize: pageSize,
    );
    if (res['isSuccess'] != true || res['data'] is! Map) {
      return (items: <WhDocListItem>[], total: 0);
    }
    final data = res['data'] as Map;
    final items = ((data['items'] as List?) ?? [])
        .map((e) => PosStockIssueDoc.fromJson(e as Map<String, dynamic>))
        .map((d) => WhDocListItem(
              id: d.id,
              docNo: d.issueNo,
              status: d.status,
              amount: d.totalValue,
              lineCount: d.lines.length,
              subtitle: d.recipientName ?? d.categoryName,
              meta: '${d.lines.length} dòng · ${formatDate(d.createdAt)}',
              createdAt: d.createdAt,
              createdBy: d.createdBy,
              note: d.note,
            ))
        .toList();
    return (items: items, total: (data['total'] as num?)?.toInt() ?? items.length);
  }
}
