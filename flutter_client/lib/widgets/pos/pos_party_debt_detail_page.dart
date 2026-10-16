import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../utils/api_datetime.dart';
import '../../utils/pos_report_open.dart';
import '../sbox/sbox_ui.dart';
import 'pos_customer_purchase_history_sheet.dart';
import 'pos_debt_statement.dart';

/// Chi tiết công nợ một khách / nhà cung cấp mở từ báo cáo: nợ từ những chứng từ nào (bấm mở hóa đơn / phiếu nhập),
/// nợ đầu kỳ / điều chỉnh, và sổ đối chiếu (mỗi dòng cũng bấm mở được chứng từ gốc).
Future<void> showPosPartyDebtDetail(
  BuildContext context, {
  required bool isCustomer,
  required String id,
  required String name,
  String? phone,
  double? debt,
}) {
  return Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => _PartyDebtPage(isCustomer: isCustomer, id: id, name: name, phone: phone, debt: debt),
  ));
}

class _PartyDebtPage extends StatefulWidget {
  const _PartyDebtPage({required this.isCustomer, required this.id, required this.name, this.phone, this.debt});

  final bool isCustomer;
  final String id;
  final String name;
  final String? phone;
  final double? debt;

  @override
  State<_PartyDebtPage> createState() => _PartyDebtPageState();
}

class _PartyDebtPageState extends State<_PartyDebtPage> {
  final _api = ApiService();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _open = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  static double _n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  static String _dmy(dynamic v) {
    final d = parseApiUtcDateTime(v)?.toLocal();
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final rows = <Map<String, dynamic>>[];
    String? err;
    if (widget.isCustomer) {
      final res = await _api.getPosCustomerHistory(widget.id, take: 100);
      if (res['isSuccess'] == true && res['data'] is Map) {
        for (final o in ((res['data'] as Map)['orders'] as List? ?? const []).whereType<Map>()) {
          final due = _n(o['balanceDue']);
          final st = '${o['status']}'.toLowerCase();
          if (due > 0 && st != '2' && st != 'cancelled' && st != '0' && st != 'draft') {
            rows.add({
              'id': '${o['id']}',
              'no': '${o['orderNo'] ?? ''}',
              'date': o['saleDate'] ?? o['createdAt'],
              'total': _n(o['payableTotal'] ?? o['total']),
              'paid': _n(o['paidAmount']),
              'due': due,
            });
          }
        }
      } else {
        err = res['message']?.toString() ?? 'Không tải được đơn còn nợ';
      }
    } else {
      final res = await _api.getPosPurchaseReceipts(supplierId: widget.id, status: 'Completed', pageSize: 200);
      final data = res['data'];
      final items = data is Map ? (data['items'] as List? ?? const []) : (data is List ? data : const []);
      if (res['isSuccess'] == true) {
        for (final r in items.whereType<Map>()) {
          final grand = _n(r['grandTotal']) != 0 ? _n(r['grandTotal']) : _n(r['totalCost']) + _n(r['totalVat']) - _n(r['discountAmount']);
          final due = _n(r['balanceDue']) != 0 ? _n(r['balanceDue']) : grand - _n(r['paidAmount']);
          if (due > 0) {
            rows.add({
              'id': '${r['id']}',
              'no': '${r['receiptNo'] ?? ''}',
              'date': r['importDate'] ?? r['createdAt'],
              'total': grand,
              'paid': _n(r['paidAmount']),
              'due': due,
            });
          }
        }
      } else {
        err = res['message']?.toString() ?? 'Không tải được phiếu nhập còn nợ';
      }
    }
    rows.sort((a, b) => '${a['date']}'.compareTo('${b['date']}')); // cũ nhất trước = quá hạn lâu nhất
    if (!mounted) return;
    setState(() {
      _open = rows;
      _error = err;
      _loading = false;
    });
  }

  void _openDoc(Map<String, dynamic> r) {
    final id = '${r['id']}';
    if (widget.isCustomer) {
      PosReportOpen.sale(context, id);
    } else {
      PosReportOpen.purchaseReceipt(context, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final openSum = _open.fold<double>(0, (s, r) => s + _n(r['due']));
    final debt = widget.debt;
    final other = debt == null ? 0.0 : debt - openSum;
    final docLabel = widget.isCustomer ? 'Đơn bán còn nợ' : 'Phiếu nhập còn nợ';
    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(title: Text(tr(widget.isCustomer ? 'Chi tiết công nợ khách' : 'Chi tiết công nợ NCC'))),
      body: ListView(padding: const EdgeInsets.all(SboxSpace.md), children: [
        SboxPageHeader(
          title: widget.name,
          subtitle: [
            if ((widget.phone ?? '').isNotEmpty) widget.phone!,
            if (debt != null) 'Công nợ hiện tại ${SboxFmt.money(debt)}',
          ].join(' · '),
          actions: [
            if (widget.isCustomer)
              OutlinedButton.icon(
                onPressed: () => showPosCustomerPurchaseHistory(
                  context,
                  customerId: widget.id,
                  customerName: widget.name,
                  phone: widget.phone,
                ),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: Text(tr('Lịch sử mua hàng')),
              ),
          ],
        ),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          title: docLabel,
          subtitle: 'Bấm một dòng để mở ${widget.isCustomer ? 'hóa đơn' : 'phiếu nhập'}',
          padding: EdgeInsets.zero,
          child: _loading
              ? const Padding(padding: EdgeInsets.all(SboxSpace.lg), child: SboxLoading())
              : _error != null
                  ? SboxEmptyState(icon: Icons.error_outline, title: 'Không tải được', message: _error)
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      SboxDataTable<Map<String, dynamic>>(
                        rows: _open,
                        pageSize: 20,
                        onRowTap: _openDoc,
                        emptyTitle: 'Không có chứng từ còn nợ',
                        columns: [
                          SboxColumn(
                            label: widget.isCustomer ? 'Mã đơn' : 'Mã phiếu',
                            primary: true,
                            minWidth: 150,
                            cell: (r) => Row(mainAxisSize: MainAxisSize.min, children: [
                              Flexible(
                                child: Text('${r['no']}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SboxType.bodyStyle(SboxColors.primary)),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.open_in_new_rounded, size: 13, color: SboxColors.primary),
                            ]),
                          ),
                          SboxColumn(label: 'Ngày', minWidth: 100, text: (r) => _dmy(r['date'])),
                          SboxColumn(label: 'Tổng tiền', numeric: true, minWidth: 120, hideOnMobile: true, text: (r) => SboxFmt.money(_n(r['total']))),
                          SboxColumn(label: 'Đã trả', numeric: true, minWidth: 120, hideOnMobile: true, text: (r) => SboxFmt.money(_n(r['paid']))),
                          SboxColumn(
                            label: 'Còn nợ',
                            numeric: true,
                            minWidth: 120,
                            cell: (r) => Text(SboxFmt.money(_n(r['due'])),
                                textAlign: TextAlign.right, style: SboxType.bodyStyle(SboxColors.dangerText)),
                          ),
                        ],
                      ),
                      if (other.abs() >= 1)
                        Padding(
                          padding: const EdgeInsets.all(SboxSpace.md),
                          child: Text(
                            tr('Còn ${SboxFmt.money(other)} nợ không thuộc chứng từ nào ở trên (nợ đầu kỳ / điều chỉnh tay hoặc chứng từ cũ) — xem sổ đối chiếu bên dưới.'),
                            style: SboxType.smallStyle(SboxColors.warningText),
                          ),
                        ),
                    ]),
        ),
        const SizedBox(height: SboxSpace.md),
        SboxCard(
          title: 'Sổ đối chiếu công nợ',
          subtitle: 'Bấm dòng có biểu tượng mở ra để xem chứng từ',
          padding: EdgeInsets.zero,
          child: PosDebtStatementView(
            loader: (from, to) => widget.isCustomer
                ? _api.getPosCustomerStatement(widget.id, from, to)
                : _api.getPosSupplierStatement(widget.id, from, to),
            increaseLabel: widget.isCustomer ? 'Phát sinh nợ' : 'Nhập hàng',
            decreaseLabel: widget.isCustomer ? 'Đã thu / trả hàng' : 'Đã trả / trả hàng',
          ),
        ),
      ]),
    );
  }
}
