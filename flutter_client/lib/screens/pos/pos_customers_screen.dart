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
import '../../widgets/pos/pos_customer_quote_care_section.dart';
import '../../widgets/pos/pos_debt_statement.dart';
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
  String _birthday = 'all';
  String _inactive = 'all';
  String _status = 'active';
  String _sort = 'debt';
  String _tier = 'all';
  List<PosCustomerTier> _tiers = [];
  int _noTierCount = 0;
  int _page = 1;
  int _pageSize = 50;
  int _total = 0;
  double _sumDebt = 0;
  double _sumPurchase = 0;
  double _sumPoints = 0;
  int _birthdaysThisMonth = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadTiers();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  static double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;

  /// Hạng thành viên của cửa hàng (+ số khách mỗi hạng cho bộ lọc).
  Future<void> _loadTiers() async {
    final res = await _api.getPosCustomerTiers();
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    final data = res['data'] as Map;
    setState(() {
      _tiers = (data['tiers'] as List? ?? [])
          .whereType<Map>()
          .map((e) => PosCustomerTier.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _noTierCount = (data['noTierCount'] as num?)?.toInt() ?? 0;
      if (_tier != 'all' && _tier != 'none' && !_tiers.any((t) => t.name == _tier)) _tier = 'all';
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosCustomers(
      search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
      hasDebt: _debt == 'debt' ? true : null,
      page: _page,
      pageSize: _pageSize,
      birthday: _birthday == 'all' ? null : _birthday,
      inactiveDays: int.tryParse(_inactive),
      status: _status,
      sort: _sort,
      tier: _tier == 'all' ? null : _tier,
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
        _sumPoints = _d(data['sumPoints']);
        _birthdaysThisMonth = (data['birthdaysThisMonth'] as num?)?.toInt() ?? 0;
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

  void _setFilter(void Function() change) {
    setState(() {
      change();
      _page = 1;
    });
    _load();
  }

  static String _dm(DateTime? d) =>
      d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  static String _ago(DateTime? utc) {
    if (utc == null) return 'Chưa mua';
    final days = DateTime.now().toUtc().difference(utc).inDays;
    if (days <= 0) return 'Hôm nay';
    if (days < 30) return '$days ngày trước';
    if (days < 365) return '${days ~/ 30} tháng trước';
    return '${days ~/ 365} năm trước';
  }

  Future<void> _openAdd() async {
    final created = await showDialog<dynamic>(context: context, builder: (_) => const PosCustomerFormDialog());
    if (created != null) _load();
  }

  Future<void> _openDetail(PosCustomer c) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _PosCustomerDetailScreen(customer: c, tiers: _tiers, onChanged: _load)),
    );
    _load();
    _loadTiers();
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
        onRefresh: () async {
          await Future.wait([_load(), _loadTiers()]);
        },
        filters: SboxFilterBar(
          searchHint: 'Tìm tên, SĐT, mã khách',
          searchController: _searchCtrl,
          onSearch: _onSearch,
          filters: [
            SboxFilterChip<String>(
              label: 'Công nợ',
              value: _debt,
              options: const {'all': 'Tất cả', 'debt': 'Đang nợ'},
              onChanged: (v) => _setFilter(() => _debt = v),
            ),
            SboxFilterChip<String>(
              label: 'Sinh nhật',
              value: _birthday,
              options: const {
                'all': 'Tất cả',
                'today': 'Hôm nay',
                'week': 'Trong 7 ngày tới',
                'month': 'Trong tháng này',
                'next30': 'Trong 30 ngày tới',
              },
              onChanged: (v) => _setFilter(() {
                _birthday = v;
                if (v != 'all') _sort = 'birthday';
              }),
            ),
            SboxFilterChip<String>(
              label: 'Mua hàng',
              value: _inactive,
              options: const {
                'all': 'Tất cả',
                '30': 'Không mua > 30 ngày',
                '60': 'Không mua > 60 ngày',
                '90': 'Không mua > 90 ngày',
                '180': 'Không mua > 6 tháng',
              },
              onChanged: (v) => _setFilter(() => _inactive = v),
            ),
            if (_tiers.isNotEmpty)
              SboxFilterChip<String>(
                label: 'Hạng',
                value: _tier,
                options: {
                  'all': 'Tất cả',
                  for (final t in _tiers.reversed) t.name: '${t.name} (${t.customerCount})',
                  'none': 'Chưa có hạng ($_noTierCount)',
                },
                onChanged: (v) => _setFilter(() => _tier = v),
              ),
            SboxFilterChip<String>(
              label: 'Trạng thái',
              value: _status,
              options: const {'active': 'Đang hoạt động', 'inactive': 'Ngừng hoạt động', 'all': 'Tất cả'},
              onChanged: (v) => _setFilter(() => _status = v),
            ),
            SboxFilterChip<String>(
              label: 'Sắp xếp',
              value: _sort,
              options: const {
                'debt': 'Nợ nhiều nhất',
                'purchase': 'Mua nhiều nhất',
                'points': 'Điểm cao nhất',
                'recent': 'Mua gần đây',
                'birthday': 'Sinh nhật sắp tới',
                'newest': 'Mới thêm',
                'name': 'Tên A → Z',
              },
              onChanged: (v) => _setFilter(() => _sort = v),
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
            onTap: _debt == 'debt' ? null : () => _setFilter(() => _debt = 'debt'),
          ),
          SboxKpi(label: 'Điểm đang có', value: SboxFmt.number(_sumPoints), icon: Icons.stars_outlined, tone: SboxTone.violet),
          SboxKpi(
            label: 'Sinh nhật tháng này',
            value: SboxFmt.number(_birthdaysThisMonth),
            icon: Icons.cake_outlined,
            tone: SboxTone.warning,
            onTap: _birthday == 'month'
                ? null
                : () => _setFilter(() {
                      _birthday = 'month';
                      _sort = 'birthday';
                    }),
          ),
        ],
        maxKpiColumns: 5,
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
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.bodyStyle().copyWith(fontWeight: SboxType.semibold)),
                      ),
                      if (c.birthdayWithin(7)) ...[
                        const SizedBox(width: 4),
                        Tooltip(message: tr('Sinh nhật ${_dm(c.birthday)}'), child: const Icon(Icons.cake_rounded, size: 15, color: SboxColors.warning)),
                      ],
                      if (c.tier != null) ...[
                        const SizedBox(width: 6),
                        PosTierBadge(name: c.tier!, color: _tiers.where((t) => t.name == c.tier).firstOrNull?.color),
                      ],
                      if (!c.isActive) ...[
                        const SizedBox(width: 6),
                        const SboxStatusChip(label: 'Ngừng', tone: SboxTone.neutral),
                      ],
                    ]),
                    Text(c.customerCode, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(SboxColors.textMuted)),
                  ]),
                ),
                SboxColumn(label: 'Điện thoại', minWidth: 130, text: (c) => c.phone ?? '—'),
                SboxColumn(label: 'Sinh nhật', minWidth: 90, hideOnMobile: true, text: (c) => _dm(c.birthday)),
                SboxColumn(label: 'Mua gần nhất', minWidth: 120, hideOnMobile: true, text: (c) => c.orderCount > 0 ? '${_ago(c.lastPurchaseAt)} · ${c.orderCount} đơn' : 'Chưa mua'),
                SboxColumn(label: 'Tổng mua', numeric: true, minWidth: 130, text: (c) => SboxFmt.money(c.totalPurchase)),
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
                ),
                SboxColumn(label: 'Điểm', numeric: true, minWidth: 90, hideOnMobile: true, text: (c) => SboxFmt.number(c.pointBalance)),
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
  const _PosCustomerDetailScreen({required this.customer, required this.onChanged, this.tiers = const []});

  final PosCustomer customer;
  final VoidCallback onChanged;

  /// Hạng thành viên của cửa hàng (tăng dần theo tổng mua).
  final List<PosCustomerTier> tiers;

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
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _points = [];

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
    // Sản phẩm khách đã mua (2 năm) + lịch sử điểm — chạy song song với lịch sử đơn / thu nợ.
    final extra = Future.wait([
      _api.getPosCustomerPurchaseHistory(_customer.id, days: 730),
      _api.getPosCustomerPointHistory(_customer.id, pageSize: 100),
    ]);
    final res = await _api.getPosCustomerHistory(_customer.id);
    final ex = await extra;
    if (!mounted) return;
    final ph = ex[0], pt = ex[1];
    _products = ph['isSuccess'] == true && ph['data'] is Map ? _maps((ph['data'] as Map)['products']) : [];
    _points = pt['isSuccess'] == true && pt['data'] is Map ? _maps((pt['data'] as Map)['items']) : [];
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

  /// Tăng để sổ đối chiếu tải lại sau khi thu nợ.
  int _statementToken = 0;

  Future<void> _collectDebt() async {
    final ok = await showPosCustomerDebtCollectDialog(context, customer: _customer);
    if (ok == true) {
      setState(() => _statementToken++);
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

  Future<void> _toggleActive() async {
    final res = await _api.setPosCustomerActive(_customer.id, !_customer.isActive);
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() => _customer = PosCustomer.fromJson(Map<String, dynamic>.from(res['data'] as Map)));
      widget.onChanged();
    } else {
      NotificationOverlayManager().showError(title: 'Không đổi được trạng thái', message: res['message']?.toString() ?? '');
    }
  }

  static String _dmy(DateTime? d) =>
      d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

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
      if (c.birthday != null) 'Sinh nhật ${_dmy(c.birthday)}${c.birthdayWithin(7) ? ' 🎂' : ''}',
      if (!c.isActive) 'Ngừng hoạt động',
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
            if (canEdit)
              SboxButton.ghost(
                label: c.isActive ? 'Ngừng hoạt động' : 'Kích hoạt lại',
                icon: c.isActive ? Icons.block_outlined : Icons.check_circle_outline,
                onPressed: _toggleActive,
              ),
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
          if (widget.tiers.isNotEmpty) _tierCard(),
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
              'Sổ đối chiếu công nợ',
              PosDebtStatementView(
                loader: (from, to) => _api.getPosCustomerStatement(_customer.id, from, to),
                increaseLabel: 'Phát sinh nợ',
                decreaseLabel: 'Đã thu / trả hàng',
                reloadToken: _statementToken,
              ),
            ),
            _section(
              'Báo giá & chăm sóc',
              PosCustomerQuoteCareSection(
                  customerId: _customer.id, phone: _customer.phone, customerName: _customer.name),
            ),
            _section(
              'Sản phẩm đã mua',
              SboxDataTable<Map<String, dynamic>>(
                rows: _products,
                pageSize: 10,
                emptyTitle: 'Chưa mua sản phẩm nào',
                columns: [
                  SboxColumn(label: 'Sản phẩm', primary: true, flex: 3, minWidth: 180, text: (p) => '${p['productName'] ?? '—'}', sortValue: (p) => '${p['productName'] ?? ''}'),
                  SboxColumn(label: 'Số lần', numeric: true, minWidth: 80, text: (p) => SboxFmt.number(_d(p['timesBought'])), sortValue: (p) => _d(p['timesBought'])),
                  SboxColumn(label: 'Tổng SL', numeric: true, minWidth: 90, text: (p) => '${SboxFmt.decimal(_d(p['totalQty']))} ${p['unitName'] ?? ''}'.trim(), sortValue: (p) => _d(p['totalQty'])),
                  SboxColumn(label: 'Tiền mua', numeric: true, minWidth: 120, text: (p) => SboxFmt.money(_d(p['totalAmount'])), sortValue: (p) => _d(p['totalAmount'])),
                  SboxColumn(label: 'Giá gần nhất', numeric: true, minWidth: 110, hideOnMobile: true, text: (p) => SboxFmt.money(_d(p['lastPrice']))),
                  SboxColumn(label: 'Mua lần cuối', minWidth: 110, hideOnMobile: true, text: (p) => _date(p['lastDate']).split(' ').first, sortValue: (p) => '${p['lastDate'] ?? ''}'),
                ],
              ),
            ),
            _section(
              'Lịch sử điểm',
              SboxDataTable<Map<String, dynamic>>(
                rows: _points,
                pageSize: 10,
                emptyTitle: 'Chưa có giao dịch điểm',
                columns: [
                  SboxColumn(label: 'Ngày', primary: true, minWidth: 140, text: (t) => _date(t['createdAt'])),
                  SboxColumn(label: 'Loại', minWidth: 120, text: (t) => switch ('${t['type']}') {
                        'Earn' => 'Tích điểm',
                        'Redeem' => 'Dùng điểm',
                        'Adjust' => 'Điều chỉnh',
                        'Reverse' || 'Revoke' => 'Hoàn / thu hồi',
                        final s => s,
                      }),
                  SboxColumn(label: 'Điểm', numeric: true, minWidth: 90, cell: (t) {
                    final p = _d(t['points']);
                    return Text(p > 0 ? '+${SboxFmt.number(p)}' : SboxFmt.number(p),
                        textAlign: TextAlign.right,
                        style: SboxType.bodyStyle(p >= 0 ? SboxColors.successText : SboxColors.dangerText));
                  }),
                  SboxColumn(label: 'Còn lại', numeric: true, minWidth: 90, text: (t) => SboxFmt.number(_d(t['balanceAfter']))),
                  SboxColumn(label: 'Ghi chú', minWidth: 160, hideOnMobile: true, text: (t) => '${t['note'] ?? ''}'),
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

  /// Hạng hiện tại, ưu đãi và còn bao nhiêu tổng mua để lên hạng kế tiếp.
  Widget _tierCard() {
    final tiers = widget.tiers;
    final spend = _customer.totalPurchase;
    final i = PosCustomerTier.indexFor(tiers, spend);
    final cur = i >= 0 ? tiers[i] : null;
    final next = i + 1 < tiers.length ? tiers[i + 1] : null;
    final from = cur?.minSpend ?? 0;
    final progress = next == null ? 1.0 : ((spend - from) / (next.minSpend - from)).clamp(0.0, 1.0);
    return SboxCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: SboxSpace.sm, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(tr('Hạng thành viên'), style: SboxType.smallStyle(SboxColors.textMuted)),
          cur == null
              ? const SboxStatusChip(label: 'Chưa có hạng', tone: SboxTone.neutral)
              : PosTierBadge(name: cur.name, color: cur.color),
          if ((cur?.benefit ?? '').isNotEmpty) Text(tr('Ưu đãi: ${cur!.benefit}'), style: SboxType.bodyStyle()),
        ]),
        const SizedBox(height: SboxSpace.sm),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            backgroundColor: SboxColors.slate100,
            color: posTierColor(next?.color ?? cur?.color) ?? SboxColors.brand600,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          next == null
              ? tr('Đang ở hạng cao nhất')
              : tr('Còn ${SboxFmt.money(next.minSpend - spend)} tổng mua để lên hạng ${next.name}'),
          style: SboxType.smallStyle(SboxColors.textMuted),
        ),
      ]),
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

/// Màu «#RRGGBB» của hạng (null nếu không có / sai định dạng).
Color? posTierColor(String? hex) {
  final h = (hex ?? '').replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

/// Nhãn hạng thành viên có màu.
class PosTierBadge extends StatelessWidget {
  const PosTierBadge({super.key, required this.name, this.color});

  final String name;
  final String? color;

  @override
  Widget build(BuildContext context) {
    final c = posTierColor(color) ?? SboxColors.brand600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium_rounded, size: 12, color: c),
        const SizedBox(width: 3),
        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.smallStyle(c).copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}
