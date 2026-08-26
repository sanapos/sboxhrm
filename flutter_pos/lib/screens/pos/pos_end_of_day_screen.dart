import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_end_of_day_report.dart';
import '../../models/pos_sell_industry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_end_of_day_print.dart';
import '../../utils/pos_report_export.dart';
import '../../utils/pos_kiot_time_range.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../utils/media_query_safe_padding.dart';
import '../../utils/store_role_helper.dart';
import '../../widgets/hrm_page_chrome.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_hub_scope.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';
import 'package:sbox_pos/l10n/app_ui_locale.dart';

const _kiotBlue = PosTheme.kiotBlue;
final _money = NumberFormat('#,##0', 'vi_VN');
final _qtyFmt = NumberFormat('#,##0.##', 'vi_VN');
final _dtFmt = DateFormat('dd/MM/yyyy HH:mm');

/// Màn hình tổng kết cuối ngày theo nhân viên (bill + A4).
class PosEndOfDayScreen extends StatefulWidget {
  const PosEndOfDayScreen({super.key});

  @override
  State<PosEndOfDayScreen> createState() => _PosEndOfDayScreenState();
}

class _PosEndOfDayScreenState extends State<PosEndOfDayScreen> {
  final _api = ApiService();

  PosKiotTimeFilterState _time = PosKiotTimeFilterState(
    preset: PosKiotTimePreset.today,
    isCustom: false,
  );
  PosEndOfDayPrintFormat _format = PosEndOfDayPrintFormat.bill58;
  String _filterBy = 'soldByEmployee';
  bool _showProductDetail = true;
  bool _loading = false;
  String? _error;
  PosEndOfDayReport? _report;
  List<PosEndOfDayStaff> _staff = [];
  String? _selectedStaffKey;
  bool _canPickStaff = false;
  PosStoreSellSettingsDto? _sellSettings;
  bool _savingOvernight = false;
  final _pngKey = GlobalKey();
  List<Map<String, dynamic>> _cashierShifts = const [];
  bool _cashierShiftEnabled = false;
  bool _filtersOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAndLoad());
  }

  Future<void> _initAndLoad() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    _canPickStaff = StoreRoleHelper.isManagerOrAbove(auth.userRole) ||
        perm.canViewAllPosStaffReports();
    await _loadSellSettings();
    await _loadStaff();
    await _loadReport();
  }

  Future<void> _loadSellSettings() async {
    final r = await PosSellSettingsHelper(_api).load();
    if (!mounted) return;
    if (r.settings != null) {
      setState(() => _sellSettings = r.settings);
    }
  }

  Future<void> _setOvernight(bool enabled, {int? hour}) async {
    final cur = _sellSettings;
    if (cur == null || _savingOvernight) return;
    setState(() => _savingOvernight = true);
    final next = cur.copyWith(
      reportDayStartHour: enabled ? (hour ?? (cur.reportDayStartHour > 0 ? cur.reportDayStartHour : 6)) : 0,
    );
    final r = await PosSellSettingsHelper(_api).save(next, applyDefaults: false);
    if (!mounted) return;
    setState(() => _savingOvernight = false);
    if (r.settings != null) {
      setState(() => _sellSettings = r.settings);
      await _loadStaff();
      await _loadReport();
    } else {
      NotificationOverlayManager().showError(
        title: 'Không lưu được',
        message: tr(r.error ?? 'Thử lại'),
      );
    }
  }

  (DateTime?, DateTime?) get _range => _time.resolvedRange;

  Future<void> _loadStaff() async {
    final from = _range.$1;
    final to = _range.$2;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final res = await _api.getPosEndOfDayStaff(
      from: from,
      to: to,
      filterBy: _filterBy,
    );
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is List) {
      final list = (res['data'] as List)
          .whereType<Map>()
          .map((e) => PosEndOfDayStaff.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() {
        _staff = list;
        if (!_canPickStaff) {
          // Thu ngân: luôn khóa theo tài khoản đang đăng nhập (không bỏ filter).
          _selectedStaffKey = _selfStaffKey(auth, list);
        } else if (_selectedStaffKey != null &&
            list.every((s) => _staffKey(s) != _selectedStaffKey)) {
          _selectedStaffKey = null;
        }
      });
    } else if (!_canPickStaff) {
      setState(() {
        _selectedStaffKey = _selfStaffKey(auth, const []);
      });
    }
  }

  String? _staffKey(PosEndOfDayStaff s) =>
      _filterBy == 'soldByEmployee' ? s.employeeId : s.email;

  /// Key lọc theo user hiện tại; ưu tiên khớp danh sách staff API.
  String? _selfStaffKey(AuthProvider auth, List<PosEndOfDayStaff> list) {
    final user = auth.user;
    if (user == null) return null;
    if (_filterBy == 'soldByEmployee') {
      final eid = (user.employeeId ?? '').trim();
      if (eid.isNotEmpty) {
        final hit = list.where((s) => (s.employeeId ?? '') == eid);
        if (hit.isNotEmpty) return hit.first.employeeId;
        return eid;
      }
      final email = user.email.trim();
      if (email.isNotEmpty) return email;
      return null;
    }
    final email = user.email.trim();
    if (email.isNotEmpty) {
      final hit = list.where(
          (s) => s.email.toLowerCase() == email.toLowerCase());
      if (hit.isNotEmpty) return hit.first.email;
      return email;
    }
    return null;
  }

  String _selfAccountLabel() {
    final user = Provider.of<AuthProvider>(context, listen: false).user;
    final name = (user?.fullName ?? '').trim();
    if (name.isNotEmpty) return name;
    final email = (user?.email ?? '').trim();
    if (email.isNotEmpty) return email;
    return 'tài khoản đang đăng nhập';
  }

  Future<void> _loadReport() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final from = _range.$1;
    final to = _range.$2;
    // Luôn gửi staff đã chọn (kể cả thu ngân) — trước đây chỉ gửi khi manager.
    final staffKey = _selectedStaffKey;
    final res = await _api.getPosEndOfDayReport(
      from: from,
      to: to,
      staffEmail: _filterBy != 'soldByEmployee' ? staffKey : null,
      soldByEmployeeId: _filterBy == 'soldByEmployee' ? staffKey : null,
      filterBy: _filterBy,
      includeProductDetail: _showProductDetail,
      includeTransactions: _format == PosEndOfDayPrintFormat.a4,
    );

    // Ca thu ngân trong cùng kỳ — tham chiếu đếm két, không cộng vào doanh thu EOD.
    String? openedBy;
    if (staffKey != null && staffKey.isNotEmpty) {
      if (_filterBy == 'soldByEmployee') {
        final hit = _staff.where((s) => s.employeeId == staffKey);
        openedBy = hit.isNotEmpty ? hit.first.email : null;
      } else {
        openedBy = staffKey;
      }
    }
    // Khi lọc theo employeeId mà không có email → không lọc openedBy (manager xem tất cả).
    final shiftRes = await _api.getPosCashierShifts(
      from: from,
      to: to,
      openedBy: openedBy,
      dayStartHour: _sellSettings?.reportDayStartHour,
    );

    if (!mounted) return;
    List<Map<String, dynamic>> shifts = const [];
    var shiftEnabled = _sellSettings?.enableCashierShift == true;
    if (shiftRes['isSuccess'] == true && shiftRes['data'] is Map) {
      final d = Map<String, dynamic>.from(shiftRes['data'] as Map);
      shiftEnabled = d['enabled'] == true || shiftEnabled;
      final items = d['items'];
      if (items is List) {
        shifts = items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }

    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _report = PosEndOfDayReport.fromJson(
            Map<String, dynamic>.from(res['data'] as Map));
        _cashierShifts = shifts;
        _cashierShiftEnabled = shiftEnabled;
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? 'Không tải được báo cáo';
        _cashierShifts = shifts;
        _cashierShiftEnabled = shiftEnabled;
        _loading = false;
      });
    }
  }

  Future<void> _applyPreset(PosKiotTimePreset preset) async {
    setState(() => _time = PosKiotTimeFilterState(preset: preset, isCustom: false));
    await _loadStaff();
    await _loadReport();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now.add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: _time.customFrom ?? now,
        end: _time.customTo ?? now,
      ),
      locale: appUiLocale(),
      helpText: 'Chọn khoảng thời gian',
    );
    if (picked == null || !mounted) return;
    setState(() => _time = PosKiotTimeFilterState(
          isCustom: true,
          customFrom: picked.start,
          customTo: picked.end,
        ));
    await _loadStaff();
    await _loadReport();
  }

  Future<void> _exportExcel() async {
    final r = _report;
    if (r == null) return;
    await PosReportExport.excel(
      context: context,
      title: 'Tổng kết cuối ngày',
      sheetName: 'Cuoi ngay',
      filePrefix: 'POS_CuoiNgay',
      periodLabel: _time.displayLabel,
      filterLabel: r.staffName,
      headers: const ['Hạng mục', 'Giá trị'],
      rows: [
        ['Số HĐ', r.orderCount],
        ['Doanh thu', r.totalSales],
        ['VAT', r.vat],
        ['DT thuần', r.netSales],
        ['Hoàn trả', r.refundTotal],
        ['Tiền mặt', r.cashTotal],
        ['Công nợ', r.debtTotal],
        ['Thực thu HĐ', r.actualReceived],
        ['Thu cọc', r.depositCollected],
        ['Hoàn cọc', r.depositRefunded],
        ['Mất cọc', r.depositForfeited],
        ['Cọc đang giữ', r.depositHeld],
        ['Tiền mặt két', r.drawerCash],
        ['Quỹ vào hôm nay', r.fundInToday],
        for (final p in r.payments) [p.paymentMethod, p.total],
        for (final p in r.products) [p.productName, p.qty],
      ],
    );
  }

  Future<void> _print() async {
    final r = _report;
    if (r == null) return;
    await printPosEndOfDayReport(
      context,
      r,
      format: _format,
      showProductDetail: _showProductDetail,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hideAppBar = HrmPageChrome.usesMainLayoutAppBar &&
        !PosHubScope.pushedSubPageOf(context);
    final pushed = PosHubScope.pushedSubPageOf(context);
    return withFallbackTopInset(
      context,
      Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: hideAppBar
          ? null
          : AppBar(
              backgroundColor: _kiotBlue,
              foregroundColor: Colors.white,
              automaticallyImplyLeading: pushed,
              title: Text(tr('Tổng kết cuối ngày')),
              actions: [
                IconButton(
                  tooltip: tr('Xuất PNG'),
                  onPressed: _report == null ? null : () => PosReportExport.png(
                    context: context,
                    key: _pngKey,
                    filePrefix: 'POS_CuoiNgay',
                  ),
                  icon: const Icon(Icons.image_outlined),
                ),
                IconButton(
                  tooltip: tr('Xuất Excel'),
                  onPressed: _report == null ? null : _exportExcel,
                  icon: const Icon(Icons.file_download_outlined),
                ),
                IconButton(
                  tooltip: tr('Tải lại'),
                  onPressed: _loading ? null : _loadReport,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Column(
        children: [
          _buildToolbar(),
          Expanded(
            child: RepaintBoundary(key: _pngKey, child: _buildBody()),
          ),
          _buildBottomBar(),
        ],
      ),
    ),
    );
  }

  Widget _buildToolbar() {
    final filters = Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            IconButton(
              tooltip: tr('Xuất PNG'),
              onPressed: _report == null
                  ? null
                  : () => PosReportExport.png(
                        context: context,
                        key: _pngKey,
                        filePrefix: 'POS_CuoiNgay',
                      ),
              icon: const Icon(Icons.image_outlined),
            ),
            IconButton(
              tooltip: tr('Xuất Excel'),
              onPressed: _report == null ? null : _exportExcel,
              icon: const Icon(Icons.file_download_outlined),
            ),
            if (_canPickStaff) ...[
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: _selectedStaffKey,
                  decoration: InputDecoration(
                    labelText: tr('Nhân viên'),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                      value: null,
                      child: Text(tr('Tất cả nhân viên')),
                    ),
                    ..._staff.map((s) => DropdownMenuItem<String?>(
                          value: _staffKey(s),
                          child: Text(tr(s.displayName), overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) async {
                          setState(() => _selectedStaffKey = v);
                          await _loadReport();
                        },
                ),
              ),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  value: _filterBy,
                  decoration: InputDecoration(
                    labelText: tr('Lọc theo'),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    DropdownMenuItem(value: 'soldBy', child: Text(tr('Người bán'))),
                    DropdownMenuItem(
                        value: 'soldByEmployee', child: Text(tr('NV (hồ sơ)'))),
                    DropdownMenuItem(value: 'createdBy', child: Text(tr('Người tạo'))),
                  ],
                  onChanged: _loading
                      ? null
                      : (v) async {
                          if (v == null) return;
                          setState(() {
                            _filterBy = v;
                            _selectedStaffKey = null;
                          });
                          await _loadStaff();
                          await _loadReport();
                        },
                ),
              ),
            ] else
              Chip(
                avatar: const Icon(Icons.person_outline, size: 18),
                label: Text(tr('Chỉ ${_selfAccountLabel()}')),
              ),
            FilterChip(
              label: Text(tr(_sellSettings?.overnightReportEnabled == true
                  ? 'Qua đêm ${_sellSettings!.reportDayStartHour.toString().padLeft(2, '0')}:00'
                  : 'UTC+7 (nửa đêm)')),
              selected: _sellSettings?.overnightReportEnabled == true,
              onSelected: (_loading || _savingOvernight || !_canPickStaff)
                  ? null
                  : (v) => unawaited(_setOvernight(v)),
            ),
            if (_sellSettings?.overnightReportEnabled == true && _canPickStaff)
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<int>(
                  value: (_sellSettings!.reportDayStartHour).clamp(1, 12),
                  decoration: InputDecoration(
                    labelText: tr('Giờ cắt'),
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    for (var h = 1; h <= 12; h++)
                      DropdownMenuItem(
                        value: h,
                        child: Text('${h.toString().padLeft(2, '0')}:00'),
                      ),
                  ],
                  onChanged: (_loading || _savingOvernight)
                      ? null
                      : (v) {
                          if (v == null) return;
                          unawaited(_setOvernight(true, hour: v));
                        },
                ),
              ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<PosEndOfDayPrintFormat>(
                value: _format,
                decoration: InputDecoration(
                  labelText: tr('Mẫu in'),
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: [
                  DropdownMenuItem(
                    value: PosEndOfDayPrintFormat.bill58,
                    child: Text(tr('Bill K58')),
                  ),
                  DropdownMenuItem(
                    value: PosEndOfDayPrintFormat.bill80,
                    child: Text(tr('Bill K80')),
                  ),
                  DropdownMenuItem(
                    value: PosEndOfDayPrintFormat.a4,
                    child: Text(tr('Khổ A4')),
                  ),
                ],
                onChanged: _loading
                    ? null
                    : (v) async {
                        if (v == null) return;
                        setState(() => _format = v);
                        if (v == PosEndOfDayPrintFormat.a4) await _loadReport();
                      },
              ),
            ),
          ],
    );
    final mobile = posUseMobileList(context);
    return Material(
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: PosTheme.border)),
        ),
        child: mobile
            ? PosFilterCollapse(
                expanded: _filtersOpen,
                onToggle: () => setState(() => _filtersOpen = !_filtersOpen),
                title: 'Bộ lọc',
                subtitle: _eodFilterSummary,
                child: filters,
              )
            : filters,
      ),
    );
  }

  String get _eodFilterSummary {
    var staff = _canPickStaff ? 'Tất cả NV' : 'Tài khoản này';
    if (_canPickStaff && _selectedStaffKey != null) {
      for (final s in _staff) {
        if (_staffKey(s) == _selectedStaffKey) {
          staff = s.displayName;
          break;
        }
      }
    }
    final fmt = switch (_format) {
      PosEndOfDayPrintFormat.bill58 => 'K58',
      PosEndOfDayPrintFormat.bill80 => 'K80',
      _ => 'A4',
    };
    return '${_time.displayLabel} · $staff · $fmt';
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _kiotBlue));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr(_error!), style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _loadReport, child: Text(tr('Thử lại'))),
          ],
        ),
      );
    }
    final r = _report;
    if (r == null) {
      return Center(child: Text(tr('Không có dữ liệu')));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_cashierShiftEnabled) _buildCashierShiftsCard(),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: PosTheme.border),
                  boxShadow: const [
                    BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 2)),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: _format == PosEndOfDayPrintFormat.a4
                      ? _buildA4Preview(r)
                      : _buildBillPreview(r),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCashierShiftsCard() {
    final timeFmt = DateFormat('HH:mm');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F9FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBAE6FD)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Ca thu ngân trong kỳ (${_cashierShifts.length})'),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFF0C4A6E),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                tr(
                  'Phiếu EOD = doanh thu theo ngày/NV (không nhân đôi khi mở 2 ca). '
                  'Mỗi dòng dưới = một lần mở→đóng ca (đếm két riêng). '
                  '«Tiền mặt két» trên phiếu = tiền mặt HĐ + cọc, không gồm tiền đầu ca.',
                ),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.grey.shade700,
                ),
              ),
              if (_cashierShifts.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  tr('Không có ca nào trong khoảng đã chọn.'),
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ] else ...[
                const SizedBox(height: 8),
                for (final s in _cashierShifts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      () {
                        final openedAt = DateTime.tryParse('${s['openedAt'] ?? ''}');
                        final closedAt = DateTime.tryParse('${s['closedAt'] ?? ''}');
                        final oLocal = openedAt == null
                            ? null
                            : (openedAt.isUtc ? openedAt.toLocal() : openedAt);
                        final cLocal = closedAt == null
                            ? null
                            : (closedAt.isUtc ? closedAt.toLocal() : closedAt);
                        final status = '${s['status'] ?? ''}';
                        final by = '${s['openedByName'] ?? ''}';
                        final opening = (s['openingCash'] is num)
                            ? (s['openingCash'] as num).toDouble()
                            : 0.0;
                        final counted = s['countedCash'];
                        final diff = s['difference'];
                        final parts = <String>[
                          if (oLocal != null) timeFmt.format(oLocal),
                          if (cLocal != null) '→ ${timeFmt.format(cLocal)}',
                          if (status == 'Open') '(đang mở)',
                          if (by.isNotEmpty) by,
                          'đầu ${_money.format(opening)}',
                          if (counted is num) 'đếm ${_money.format(counted)}',
                          if (diff is num) 'lệch ${_money.format(diff)}',
                        ];
                        return parts.join(' · ');
                      }(),
                      style: const TextStyle(fontSize: 12, height: 1.35),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBillPreview(PosEndOfDayReport r) {
    final staff = r.staffName ?? r.staffEmail ?? 'Tất cả nhân viên';
    final k58 = _format == PosEndOfDayPrintFormat.bill58;
    final maxW = k58 ? 280.0 : 340.0;

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 4),
          child: Text(
            tr(title),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: Color(0xFF334155),
            ),
          ),
        );

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFFFDF8),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (r.storeName != null && r.storeName!.trim().isNotEmpty)
                  Text(
                    tr(r.storeName!.trim()),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                Text(tr('TỔNG KẾT CUỐI NGÀY'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                Text(
                  tr('Bill ${k58 ? 'K58' : 'K80'}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('NV: $staff\n'
                  '${_dt(r.from)} – ${_dt(r.to)}'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: PosTheme.textSecondary, height: 1.35),
                ),
                const Divider(height: 20, thickness: 1.2),
                section('BÁN HÀNG'),
                _summaryLine('', 'Số đơn', '${r.orderCount}'),
                _summaryLine('', 'Doanh thu', _fmt(r.totalSales)),
                _summaryLine('', 'Chiết khấu', _fmt(r.orderDiscount)),
                _summaryLine('', 'VAT', _fmt(r.vat)),
                _summaryLine('', 'DT ròng', _fmt(r.netSales), bold: true),
                if (r.closedOffDayOrders.isNotEmpty) ...[
                  const Divider(height: 16),
                  section('CHỐT NGÀY KHÁC'),
                  _summaryLine('', 'Số HĐ', '${r.closedOffDayCount}'),
                  for (final o in r.closedOffDayOrders.take(k58 ? 8 : 15))
                    _summaryLine(
                      '',
                      o.orderNo,
                      o.draftDayLabel,
                      indent: true,
                    ),
                ],
                const Divider(height: 16),
                section('TRẢ / HỦY'),
                _summaryLine('', 'Trả hàng', _fmt(r.refundTotal)),
                _summaryLine('', 'Sau trả', _fmt(r.totalAfterRefund)),
                _summaryLine('', 'Hủy đơn', '${r.canceledCount}'),
                const Divider(height: 16),
                section('THANH TOÁN BÁN HÀNG'),
                _summaryLine('', 'Tiền mặt HĐ', _fmt(r.cashTotal), indent: true),
                _summaryLine('', 'Ghi nợ', _fmt(r.debtTotal), indent: true),
                for (final p in r.payments)
                  if (!p.paymentMethod.toLowerCase().contains('mặt') &&
                      p.paymentMethod.toLowerCase() != 'cash')
                    _summaryLine('', p.paymentMethod, _fmt(p.total), indent: true),
                _summaryLine('', 'Thực thu HĐ (gồm cọc trừ)', _fmt(r.actualReceived)),
                const Divider(height: 16),
                section('CỌC ĐẶT BÀN'),
                _summaryLine('', 'Thu cọc hôm nay', _fmt(r.depositCollected), indent: true),
                for (final p in r.depositByPayment)
                  _summaryLine('', p.paymentMethod, _fmt(p.total), indent: true),
                _summaryLine('', 'Hoàn cọc', _fmt(r.depositRefunded), indent: true),
                _summaryLine('', 'Mất cọc (thu nhập)', _fmt(r.depositForfeited), indent: true),
                _summaryLine('', 'Đang giữ (chưa nhận bàn)', _fmt(r.depositHeld), indent: true),
                _summaryLine('', 'Đã trừ HĐ hôm nay', _fmt(r.depositApplied), indent: true),
                const Divider(height: 18, thickness: 1.4),
                _summaryLine('', 'TIỀN MẶT TRONG KÉT', _fmt(r.drawerCash), bold: true),
                _summaryLine('', 'QUỸ VÀO HÔM NAY', _fmt(r.fundInToday), bold: true),
                if (r.otherIncome > 0)
                  _summaryLine('', 'Thu nhập khác (mất cọc)', _fmt(r.otherIncome)),
                const Divider(height: 18, thickness: 1.4),
                if (_showProductDetail && r.products.isNotEmpty) ...[
                  section('HÀNG BÁN'),
                  for (final p in r.products.take(k58 ? 15 : 30))
                    _summaryLine(
                      '',
                      p.productName,
                      '${_qty(p.qty)} · ${_fmt(p.revenue)}',
                      indent: true,
                    ),
                  if (r.lineDiscountTotal > 0)
                    _summaryLine('', 'CK mặt hàng', _fmt(r.lineDiscountTotal)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildA4Preview(PosEndOfDayReport r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tr('BÁO CÁO CUỐI NGÀY VỀ BÁN HÀNG'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _summaryLine('', 'Số đơn', '${r.orderCount}'),
        _summaryLine('', 'Doanh thu ròng', _fmt(r.netSales)),
        _summaryLine('', 'Thực thu HĐ', _fmt(r.actualReceived), bold: true),
        _summaryLine('', 'Thu cọc hôm nay', _fmt(r.depositCollected)),
        _summaryLine('', 'Hoàn cọc', _fmt(r.depositRefunded)),
        _summaryLine('', 'Mất cọc', _fmt(r.depositForfeited)),
        _summaryLine('', 'Tiền mặt két', _fmt(r.drawerCash), bold: true),
        _summaryLine('', 'Quỹ vào hôm nay', _fmt(r.fundInToday), bold: true),
        if (r.closedOffDayOrders.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Hóa đơn chốt ngày khác'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final o in r.closedOffDayOrders)
            _summaryLine('', o.orderNo, o.draftDayLabel, indent: true),
        ],
        if (r.transactions.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(tr('Chi tiết giao dịch'), style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              columns: [
                DataColumn(label: Text(tr('Mã GD'))),
                DataColumn(label: Text(tr('Thời gian'))),
                DataColumn(label: Text(tr('SL')), numeric: true),
                DataColumn(label: Text(tr('Doanh thu')), numeric: true),
                DataColumn(label: Text(tr('Thực thu')), numeric: true),
              ],
              rows: r.transactions
                  .map((t) => DataRow(cells: [
                        DataCell(Text(tr(t.closedOffDay
                            ? '${t.orderNo} · ${t.note ?? 'Chốt ngày khác'}'
                            : t.orderNo))),
                        DataCell(Text(tr(_dt(t.createdAt)))),
                        DataCell(Text(tr(_qty(t.qty)))),
                        DataCell(Text(tr(_fmt(t.revenue)))),
                        DataCell(Text(tr(_fmt(t.actualReceived)))),
                      ]))
                  .toList(),
            ),
          ),
        ],
        if (_showProductDetail && r.products.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(tr('Hàng hóa bán ra'), style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...r.products.map((p) => _summaryLine(
                '',
                p.productName,
                '${_qty(p.qty)} · ${_fmt(p.revenue)}',
                indent: true,
              )),
        ],
      ],
    );
  }

  Widget _summaryLine(
    String idx,
    String label,
    String value, {
    bool indent = false,
    bool bold = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 16 : 0, top: 4, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (idx.isNotEmpty)
            SizedBox(width: 22, child: Text(tr(idx), style: const TextStyle(fontSize: 12)))
          else if (!indent)
            const SizedBox(width: 22),
          Expanded(
            child: Text(
              tr(label),
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          Text(
            tr(value),
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Material(
      color: Colors.white,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: PosTheme.border)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _presetChip('Hôm nay', PosKiotTimePreset.today),
                    _presetChip('Hôm qua', PosKiotTimePreset.yesterday),
                    _presetChip('7 ngày', PosKiotTimePreset.last7Days),
                    TextButton(
                      onPressed: _pickCustomRange,
                      child: Text(tr('Khác')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Checkbox(
                    value: _showProductDetail,
                    activeColor: _kiotBlue,
                    onChanged: _loading
                        ? null
                        : (v) async {
                            setState(() => _showProductDetail = v ?? true);
                            await _loadReport();
                          },
                  ),
                  Expanded(
                    child: Text(tr('Chi tiết hàng bán'), style: TextStyle(fontSize: 12)),
                  ),
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(tr('Thoát')),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: _kiotBlue),
                    onPressed: _report == null || _loading ? null : _print,
                    icon: const Icon(Icons.print, size: 18),
                    label: Text(tr('In')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _presetChip(String label, PosKiotTimePreset preset) {
    final active = !_time.isCustom && _time.preset == preset;
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: active ? _kiotBlue : PosTheme.textPrimary,
        backgroundColor: active ? PosTheme.kiotBlueLight : null,
      ),
      onPressed: _loading ? null : () => _applyPreset(preset),
      child: Text(tr(label), style: TextStyle(fontWeight: active ? FontWeight.w600 : null)),
    );
  }

  String _fmt(num v) => _money.format(v);
  String _qty(num v) => _qtyFmt.format(v);
  String _dt(DateTime d) => _dtFmt.format(d);
}

