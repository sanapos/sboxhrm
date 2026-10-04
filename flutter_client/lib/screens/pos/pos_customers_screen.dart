import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/pos_customer.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/api_datetime.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_customer_debt_collect_dialog.dart';
import '../../widgets/pos/pos_customer_form_dialog.dart';
import '../../widgets/sbox/sbox_ui.dart';
import 'pos_session_redeem_sheet.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Khách hàng POS — thanh lọc + số liệu + bảng (điện thoại tự thành thẻ), phân trang theo máy chủ.
class PosCustomersScreen extends StatefulWidget {
  const PosCustomersScreen({super.key});

  @override
  State<PosCustomersScreen> createState() => _PosCustomersScreenState();
}

class _PosCustomersScreenState extends State<PosCustomersScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  List<PosCustomer> _items = [];
  bool _loading = true;
  String _debt = 'all';
  int _page = 1;
  int _pageSize = 50;
  int _total = 0;
  double _sumDebt = 0;
  double _sumPurchase = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosCustomers(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      hasDebt: _debt == 'debt' ? true : null,
      page: _page,
      pageSize: _pageSize,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = Map<String, dynamic>.from(res['data'] as Map);
      setState(() {
        _items = (data['items'] as List? ?? [])
            .map((e) => PosCustomer.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        _total = (data['total'] as num?)?.toInt() ?? _items.length;
        _sumDebt = _d(data['sumDebt']);
        _sumPurchase = _d(data['sumPurchase']);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: res['message']?.toString() ?? 'Không tải được khách hàng',
      );
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      _page = 1;
      _load();
    });
  }

  Future<void> _openAdd() async {
    final created = await showDialog<dynamic>(context: context, builder: (_) => const PosCustomerFormDialog());
    if (created != null) _load();
  }

  Future<void> _openDetail(PosCustomer c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PosCustomerDetailScreen(customer: c, onChanged: _load)),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    if (!perm.canView('PosCustomers') && !perm.canView('PosProducts')) {
      return const Scaffold(body: SboxEmptyState(icon: Icons.lock_outline, title: 'Không có quyền xem khách hàng'));
    }
    final canCreate = perm.canCreate('PosCustomers') || perm.canCreate('PosProducts');
    return Scaffold(
      backgroundColor: SboxColors.page,
      body: SboxReportLayout(
        onRefresh: _load,
        filters: SboxFilterBar(
          searchHint: 'Tìm tên, SĐT, mã khách',
          searchController: _searchCtrl,
          onSearch: _onSearch,
          filters: [
            SboxFilterChip<String>(
              label: 'Công nợ',
              value: _debt,
              options: const {'all': 'Tất cả', 'debt': 'Đang nợ'},
              onChanged: (v) {
                setState(() {
                  _debt = v;
                  _page = 1;
                });
                _load();
              },
            ),
          ],
          actions: [
            if (canCreate) SboxButton(label: 'Thêm khách', icon: Icons.person_add_alt_1_outlined, onPressed: _openAdd),
          ],
        ),
        kpis: [
          SboxKpi(label: 'Khách hàng', value: SboxFmt.number(_total), icon: Icons.groups_outlined),
          SboxKpi(label: 'Tổng mua', value: SboxFmt.money(_sumPurchase), icon: Icons.shopping_bag_outlined, tone: SboxTone.success),
          SboxKpi(
            label: 'Tổng công nợ',
            value: SboxFmt.money(_sumDebt),
            icon: Icons.account_balance_wallet_outlined,
            tone: _sumDebt > 0 ? SboxTone.danger : SboxTone.neutral,
            onTap: _debt == 'debt'
                ? null
                : () {
                    setState(() {
                      _debt = 'debt';
                      _page = 1;
                    });
                    _load();
                  },
          ),
        ],
        maxKpiColumns: 3,
        table: SboxCard(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SboxDataTable<PosCustomer>(
              loading: _loading,
              paginate: false,
              rows: _items,
              onRowTap: _openDetail,
              emptyTitle: _debt == 'debt' ? 'Không có khách đang nợ' : 'Chưa có khách hàng',
              emptyMessage: canCreate ? 'Thêm khách để tích điểm, theo dõi công nợ và lịch sử mua.' : null,
              columns: [
                SboxColumn(
                  label: 'Khách hàng',
                  primary: true,
                  flex: 3,
                  minWidth: 220,
                  cell: (c) => Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                    Text(c.customerCode, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.textMuted)),
                  ]),
                  sortValue: (c) => c.name.toLowerCase(),
                ),
                SboxColumn(label: 'Điện thoại', minWidth: 130, text: (c) => c.phone ?? '—'),
                SboxColumn(label: 'Tổng mua', numeric: true, minWidth: 130, text: (c) => SboxFmt.money(c.totalPurchase), sortValue: (c) => c.totalPurchase),
                SboxColumn(
                  label: 'Công nợ',
                  numeric: true,
                  minWidth: 130,
                  cell: (c) => Text(
                    c.currentDebt > 0 ? SboxFmt.money(c.currentDebt) : '—',
                    textAlign: TextAlign.right,
                    style: SboxType.bodyStyle(c.currentDebt > 0 ? SboxColors.dangerText : SboxColors.textMuted)
                        .copyWith(fontWeight: c.currentDebt > 0 ? SboxType.semibold : null),
                  ),
                  sortValue: (c) => c.currentDebt,
                ),
                SboxColumn(label: 'Điểm', numeric: true, minWidth: 90, hideOnMobile: true, text: (c) => SboxFmt.number(c.pointBalance), sortValue: (c) => c.pointBalance),
              ],
            ),
            if (_total > _pageSize)
              SboxPager(
                page: _page,
                pageSize: _pageSize,
                total: _total,
                onPage: (p) {
                  setState(() => _page = p);
                  _load();
                },
                onPageSize: (s) {
                  setState(() {
                    _pageSize = s;
                    _page = 1;
                  });
                  _load();
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _PosCustomerDetailScreen extends StatefulWidget {
  const _PosCustomerDetailScreen({required this.customer, required this.onChanged});

  final PosCustomer customer;
  final VoidCallback onChanged;

  @override
  State<_PosCustomerDetailScreen> createState() => _PosCustomerDetailScreenState();
}

class _PosCustomerDetailScreenState extends State<_PosCustomerDetailScreen> {
  final _api = ApiService();
  late PosCustomer _customer;
  bool _loading = true;
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _sessionBalances = [];
  List<Map<String, dynamic>> _sessionTxns = [];

  @override
  void initState() {
    super.initState();
    _customer = widget.customer;
    _loadHistory();
  }

  static List<Map<String, dynamic>> _maps(dynamic v) =>
      (v as List? ?? []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
  static String _date(dynamic v) {
    final d = parseApiUtcDateTime(v);
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _loadHistory() async {
    setState(() => _loading = true);
    final res = await _api.getPosCustomerHistory(_customer.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final data = res['data'] as Map;
      setState(() {
        _orders = _maps(data['orders']);
        _payments = _maps(data['payments']);
        _sessionBalances = _maps(data['sessionBalances']);
        _sessionTxns = _maps(data['sessionTxns']);
        _loading = false;
      });
    } else {
      setState(() => _loading = false);
    }
  }

  /// Tải lại đúng khách này theo mã (trước đây tìm theo tên → có thể lấy nhầm khách trùng tên).
  Future<void> _reloadCustomer() async {
    final res = await _api.getPosCustomerById(_customer.id);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() => _customer = PosCustomer.fromJson(Map<String, dynamic>.from(res['data'] as Map)));
    }
  }

  Future<void> _collectDebt() async {
    final ok = await showPosCustomerDebtCollectDialog(context, customer: _customer);
    if (ok == true) {
      widget.onChanged();
      await _reloadCustomer();
      _loadHistory();
    }
  }

  Future<void> _edit() async {
    final updated = await showDialog<dynamic>(context: context, builder: (_) => PosCustomerFormDialog(customer: _customer));
    if (updated is Map<String, dynamic>) {
      setState(() => _customer = PosCustomer.fromJson(updated));
      widget.onChanged();
    }
  }

  Future<void> _openSessions() async {
    await showPosSessionRedeemSheet(
      context,
      customerId: _customer.id,
      customerName: _customer.name,
      enableRedeem: true,
      initialTab: 0,
    );
    _loadHistory();
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canEdit = perm.canEdit('PosCustomers') || perm.canEdit('PosProducts');
    final c = _customer;
    final info = [
      c.customerCode,
      if ((c.phone ?? '').isNotEmpty) c.phone!,
      if ((c.email ?? '').isNotEmpty) c.email!,
      if ((c.companyName ?? '').isNotEmpty) c.companyName!,
    ].join(' · ');

    return Scaffold(
      backgroundColor: SboxColors.page,
      appBar: AppBar(title: Text(tr('Chi tiết khách hàng'))),
      body: SboxReportLayout(
        onRefresh: () async {
          await _reloadCustomer();
          await _loadHistory();
        },
        header: SboxPageHeader(
          title: c.name,
          subtitle: info,
          leading: CircleAvatar(
            backgroundColor: SboxColors.brand50,
            child: Text(c.name.isNotEmpty ? c.name[0].toUpperCase() : 'K',
                style: const TextStyle(color: SboxColors.brand700, fontWeight: FontWeight.w800)),
          ),
          actions: [
            if (canEdit) SboxButton.secondary(label: 'Sửa', icon: Icons.edit_outlined, onPressed: _edit),
            if (canEdit && c.currentDebt > 0)
              SboxButton(label: 'Thu nợ', icon: Icons.payments_outlined, onPressed: _collectDebt),
          ],
        ),
        kpis: [
          SboxKpi(label: 'Tổng mua', value: SboxFmt.money(c.totalPurchase), icon: Icons.shopping_bag_outlined, tone: SboxTone.success),
          SboxKpi(label: 'Công nợ', value: SboxFmt.money(c.currentDebt), icon: Icons.account_balance_wallet_outlined,
              tone: c.currentDebt > 0 ? SboxTone.danger : SboxTone.neutral),
          SboxKpi(label: 'Điểm tích lũy', value: SboxFmt.number(c.pointBalance), icon: Icons.stars_outlined, tone: SboxTone.violet),
        ],
        maxKpiColumns: 3,
        children: [
          if (_loading) const SboxLoading(),
          if (!_loading) ...[
            _section(
              'Đơn bán gần đây',
              SboxDataTable<Map<String, dynamic>>(
                rows: _orders,
                pageSize: 10,
                emptyTitle: 'Chưa có đơn',
                columns: [
                  SboxColumn(label: 'Mã đơn', primary: true, minWidth: 150, text: (o) => '${o['orderNo'] ?? '—'}'),
                  SboxColumn(label: 'Ngày', minWidth: 140, text: (o) => _date(o['saleDate'] ?? o['createdAt'])),
                  SboxColumn(
                    label: 'Trạng thái',
                    minWidth: 120,
                    cell: (o) {
                      final st = '${o['status']}';
                      final cancelled = st == '2' || st.toLowerCase() == 'cancelled';
                      final draft = st == '0' || st.toLowerCase() == 'draft';
                      return Align(
                        alignment: Alignment.centerLeft,
                        child: SboxStatusChip(
                          label: cancelled ? 'Đã hủy' : (draft ? 'Đơn tạm' : 'Hoàn thành'),
                          tone: cancelled ? SboxTone.danger : (draft ? SboxTone.warning : SboxTone.success),
                        ),
                      );
                    },
                  ),
                  SboxColumn(label: 'Phải trả', numeric: true, minWidth: 120,
                      text: (o) => SboxFmt.money(_d(o['payableTotal'] ?? o['total']))),
                  SboxColumn(label: 'Đã trả', numeric: true, minWidth: 120, text: (o) => SboxFmt.money(_d(o['paidAmount']))),
                  SboxColumn(
                    label: 'Còn nợ',
                    numeric: true,
                    minWidth: 110,
                    cell: (o) {
                      final due = _d(o['balanceDue']);
                      return Text(due > 0 ? SboxFmt.money(due) : '—',
                          textAlign: TextAlign.right,
                          style: SboxType.bodyStyle(due > 0 ? SboxColors.dangerText : SboxColors.textMuted));
                    },
                  ),
                ],
              ),
            ),
            _section(
              'Lịch sử thu nợ',
              SboxDataTable<Map<String, dynamic>>(
                rows: _payments,
                pageSize: 10,
                emptyTitle: 'Chưa có phiếu thu nợ',
                columns: [
                  SboxColumn(label: 'Số phiếu', primary: true, minWidth: 140, text: (p) => '${p['paymentNo'] ?? '—'}'),
                  SboxColumn(label: 'Ngày', minWidth: 140, text: (p) => _date(p['paidAt'])),
                  SboxColumn(label: 'Hình thức', minWidth: 120, text: (p) => '${p['paymentMethod'] ?? ''}'),
                  SboxColumn(label: 'Số tiền', numeric: true, minWidth: 120, text: (p) => SboxFmt.money(_d(p['amount']))),
                ],
              ),
            ),
            _section(
              'Gói buổi / thẻ tập',
              _sessionBalances.isEmpty
                  ? const SboxEmptyState(icon: Icons.card_membership_outlined, title: 'Chưa có gói buổi')
                  : SboxDataTable<Map<String, dynamic>>(
                      rows: _sessionBalances,
                      paginate: false,
                      columns: [
                        SboxColumn(label: 'Gói', primary: true, flex: 2, minWidth: 180, text: (b) => '${b['packageName'] ?? '—'}'),
                        SboxColumn(
                          label: 'Còn / Tổng',
                          numeric: true,
                          minWidth: 120,
                          text: (b) {
                            final total = (b['totalSessions'] as num?)?.toInt() ?? 0;
                            final remain = (b['remainingSessions'] as num?)?.toInt() ?? 0;
                            return total >= 9999 ? 'Không giới hạn' : '$remain / $total buổi';
                          },
                        ),
                        SboxColumn(
                          label: 'Hạn dùng',
                          minWidth: 140,
                          cell: (b) {
                            final exp = parseApiUtcDateTime(b['expiresAt']);
                            if (exp == null) return const Text('—');
                            final expired = exp.isBefore(DateTime.now());
                            return Align(
                              alignment: Alignment.centerLeft,
                              child: SboxStatusChip(
                                label: '${exp.day.toString().padLeft(2, '0')}/${exp.month.toString().padLeft(2, '0')}/${exp.year}${expired ? ' · hết hạn' : ''}',
                                tone: expired ? SboxTone.danger : SboxTone.neutral,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
              action: SboxButton.ghost(label: 'Sổ buổi / trừ buổi', icon: Icons.event_available_outlined, onPressed: _openSessions),
            ),
            if (_sessionTxns.isNotEmpty)
              _section(
                'Lượt dùng gần đây',
                SboxDataTable<Map<String, dynamic>>(
                  rows: _sessionTxns,
                  pageSize: 8,
                  columns: [
                    SboxColumn(label: 'Gói', primary: true, minWidth: 160, text: (t) => '${t['packageName'] ?? '—'}'),
                    SboxColumn(label: 'Loại', minWidth: 100, text: (t) => '${t['type'] ?? ''}'),
                    SboxColumn(label: 'Nhân viên', minWidth: 140, text: (t) => '${t['employeeName'] ?? ''}'),
                    SboxColumn(label: 'Buổi', numeric: true, minWidth: 80, text: (t) {
                      final d = (t['sessionDelta'] as num?)?.toInt() ?? 0;
                      return d > 0 ? '+$d' : '$d';
                    }),
                    SboxColumn(label: 'Ghi chú', minWidth: 160, hideOnMobile: true, text: (t) => '${t['note'] ?? ''}'),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title, Widget child, {Widget? action}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: SboxSpace.sm),
        child: Row(children: [
          Expanded(child: Text(tr(title), style: SboxType.titleSmStyle())),
          if (action != null) action,
        ]),
      ),
      SboxCard(padding: EdgeInsets.zero, child: child),
    ]);
  }
}
