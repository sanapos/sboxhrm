import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/advanced_reports_service.dart';

/// Màn hình tập trung 29 báo cáo HR nâng cao (8 cụm, mỗi cụm một tab).
/// Mỗi báo cáo có:
///  • Bộ lọc (ngày, năm, tháng, phòng ban, v.v.)
///  • Nút "Xem" → fetch JSON, hiển thị bảng/preview.
///  • Nút "Xuất Excel" → tải file .xlsx.
class AdvancedReportsScreen extends StatefulWidget {
  const AdvancedReportsScreen({super.key});

  @override
  State<AdvancedReportsScreen> createState() => _AdvancedReportsScreenState();
}

class _AdvancedReportsScreenState extends State<AdvancedReportsScreen>
    with SingleTickerProviderStateMixin {
  final _svc = AdvancedReportsService();
  late final TabController _tab;

  // ignore: unused_field
  final _fmtMoney = NumberFormat('#,##0', 'vi_VN');
  // ignore: unused_field
  final _fmtDate = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Báo cáo HR nâng cao'),
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.fingerprint), text: '1. Chấm công'),
            Tab(icon: Icon(Icons.beach_access), text: '2. Nghỉ phép & Ca'),
            Tab(icon: Icon(Icons.people_outline), text: '3. Nhân sự'),
            Tab(icon: Icon(Icons.cake), text: '4. Vòng đời NV'),
            Tab(icon: Icon(Icons.payments), text: '5. Lương'),
            Tab(icon: Icon(Icons.account_balance_wallet), text: '6. Tài chính'),
            Tab(icon: Icon(Icons.trending_up), text: '7. Hiệu suất'),
            Tab(icon: Icon(Icons.dashboard), text: '8. Điều hành'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _clusterAttendance(),
          _clusterLeaveShift(),
          _clusterHrCore(),
          _clusterLifecycle(),
          _clusterPayroll(),
          _clusterFinance(),
          _clusterPerformance(),
          _clusterExecutive(),
        ],
      ),
    );
  }

  // ════════════════════════ CLUSTER 1 ════════════════════════
  Widget _clusterAttendance() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Tuân thủ giờ giấc',
          subtitle: 'Compliance theo tháng (pro-rated)',
          filters: const [_FilterKind.year, _FilterKind.month, _FilterKind.department],
          fetch: (f) => _svc.compliance(
              year: f.year, month: f.month, department: f.department),
          excel: (f) => _svc.complianceExcel(
              year: f.year, month: f.month, department: f.department),
        ),
        _ReportDef(
          title: 'Vắng không phép',
          subtitle: 'Absence (loại trừ phép/holiday/mobile)',
          filters: const [_FilterKind.range, _FilterKind.department],
          fetch: (f) => _svc.absence(
              from: f.from, to: f.to, department: f.department),
          excel: (f) => _svc.absenceExcel(
              from: f.from, to: f.to, department: f.department),
        ),
        _ReportDef(
          title: 'No-show',
          subtitle: 'Có ca nhưng không chấm công',
          filters: const [_FilterKind.range, _FilterKind.department],
          fetch: (f) => _svc.noShow(
              from: f.from, to: f.to, department: f.department),
          excel: (f) => _svc.noShowExcel(
              from: f.from, to: f.to, department: f.department),
        ),
        _ReportDef(
          title: 'Bất thường chấm công',
          subtitle: 'Nhiều/thiếu lượt, ra-vào bất thường',
          filters: const [_FilterKind.range, _FilterKind.department],
          fetch: (f) => _svc.anomalies(
              from: f.from, to: f.to, department: f.department),
          excel: (f) => _svc.anomaliesExcel(
              from: f.from, to: f.to, department: f.department),
        ),
        _ReportDef(
          title: 'Field check-in',
          subtitle: 'Tổng hợp visit report ngoài hiện trường',
          filters: const [_FilterKind.range, _FilterKind.employee],
          fetch: (f) => _svc.fieldSummary(
              from: f.from, to: f.to, employeeCode: f.employeeCode),
          excel: (f) => _svc.fieldSummaryExcel(
              from: f.from, to: f.to, employeeCode: f.employeeCode),
        ),
        _ReportDef(
          title: 'Chấm công mobile',
          subtitle: 'Thống kê sử dụng app mobile',
          filters: const [_FilterKind.range],
          fetch: (f) => _svc.mobileUsage(from: f.from, to: f.to),
          excel: (f) => _svc.mobileUsageExcel(from: f.from, to: f.to),
        ),
      ],
    );
  }

  // ════════════════════════ CLUSTER 2 ════════════════════════
  Widget _clusterLeaveShift() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Số dư phép',
          subtitle: 'Leave balance + breakdown theo loại',
          filters: const [_FilterKind.year, _FilterKind.department],
          fetch: (f) =>
              _svc.leaveBalance(year: f.year, department: f.department),
          excel: (f) =>
              _svc.leaveBalanceExcel(year: f.year, department: f.department),
        ),
        _ReportDef(
          title: 'SLA duyệt phép',
          subtitle: 'Thời gian duyệt, rate theo người duyệt',
          filters: const [_FilterKind.range],
          fetch: (f) => _svc.leaveApprovalSla(from: f.from, to: f.to),
          excel: (f) => _svc.leaveApprovalSlaExcel(from: f.from, to: f.to),
        ),
        _ReportDef(
          title: 'Phủ ca (shift coverage)',
          subtitle: 'Quota tối thiểu/tối đa vs thực tế',
          filters: const [_FilterKind.range, _FilterKind.department],
          fetch: (f) => _svc.shiftCoverage(
              from: f.from, to: f.to, department: f.department),
          excel: (f) => _svc.shiftCoverageExcel(
              from: f.from, to: f.to, department: f.department),
        ),
        _ReportDef(
          title: 'Hoán đổi ca',
          subtitle: 'Tần suất đổi ca theo nhân viên',
          filters: const [_FilterKind.range],
          fetch: (f) => _svc.shiftSwaps(from: f.from, to: f.to),
          excel: (f) => _svc.shiftSwapsExcel(from: f.from, to: f.to),
        ),
      ],
    );
  }

  // ════════════════════════ CLUSTER 3 ════════════════════════
  Widget _clusterHrCore() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Biến động nhân sự',
          subtitle: 'Tuyển / nghỉ / HC theo tháng',
          filters: const [_FilterKind.year, _FilterKind.department],
          fetch: (f) =>
              _svc.headcountMovement(year: f.year, department: f.department),
          excel: (f) => _svc.headcountMovementExcel(
              year: f.year, department: f.department),
        ),
        _ReportDef(
          title: 'Tỷ lệ nghỉ việc',
          subtitle: 'Turnover theo PB / chi nhánh',
          filters: const [_FilterKind.year, _FilterKind.groupBy],
          fetch: (f) => _svc.turnover(year: f.year, groupBy: f.groupBy),
          excel: (f) => _svc.turnoverExcel(year: f.year, groupBy: f.groupBy),
        ),
        _ReportDef(
          title: 'Phân bố thâm niên',
          subtitle: '< 6 tháng / 6–12 / 1–3 / 3–5 / > 5 năm',
          filters: const [_FilterKind.department],
          fetch: (f) => _svc.tenureDistribution(department: f.department),
          excel: (f) => _svc.tenureDistributionExcel(department: f.department),
        ),
        _ReportDef(
          title: 'Demographics',
          subtitle: 'Giới tính / độ tuổi theo PB',
          filters: const [_FilterKind.department],
          fetch: (f) => _svc.demographics(department: f.department),
          excel: (f) => _svc.demographicsExcel(department: f.department),
        ),
        _ReportDef(
          title: 'Headcount tổ chức',
          subtitle: 'Theo PB / chi nhánh / cấp bậc',
          filters: const [],
          fetch: (f) => _svc.orgHeadcount(),
          excel: (f) => _svc.orgHeadcountExcel(),
        ),
      ],
    );
  }

  // ════════════════════════ CLUSTER 4 ════════════════════════
  Widget _clusterLifecycle() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Hết hạn HĐ / Thử việc',
          subtitle: 'Sắp hết HĐ trong N ngày tới',
          filters: const [_FilterKind.days, _FilterKind.department],
          defaults: const {'days': 90},
          fetch: (f) => _svc.contractExpiry(
              days: f.days ?? 90, department: f.department),
          excel: (f) => _svc.contractExpiryExcel(
              days: f.days ?? 90, department: f.department),
        ),
        _ReportDef(
          title: 'Sinh nhật sắp tới',
          subtitle: 'Trong N ngày tới',
          filters: const [_FilterKind.days, _FilterKind.department],
          defaults: const {'days': 30},
          fetch: (f) =>
              _svc.birthdays(days: f.days ?? 30, department: f.department),
          excel: (f) => _svc.birthdaysExcel(
              days: f.days ?? 30, department: f.department),
        ),
        _ReportDef(
          title: 'Sắp nghỉ hưu',
          subtitle: 'Nam 62, Nữ 60 (VN)',
          filters: const [_FilterKind.years],
          defaults: const {'years': 5},
          fetch: (f) => _svc.retirement(years: f.years ?? 5),
          excel: (f) => _svc.retirementExcel(years: f.years ?? 5),
        ),
      ],
    );
  }

  // ════════════════════════ CLUSTER 5 ════════════════════════
  Widget _clusterPayroll() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Chi phí lương theo PB',
          filters: const [_FilterKind.year, _FilterKind.month, _FilterKind.department],
          fetch: (f) => _svc.payrollCostByDepartment(
              year: f.year, month: f.month, department: f.department),
          excel: (f) => _svc.payrollCostByDepartmentExcel(
              year: f.year, month: f.month, department: f.department),
        ),
        _ReportDef(
          title: 'Tỷ lệ chi phí OT/Base',
          filters: const [_FilterKind.year, _FilterKind.department],
          fetch: (f) =>
              _svc.otCostRatio(year: f.year, department: f.department),
          excel: (f) =>
              _svc.otCostRatioExcel(year: f.year, department: f.department),
        ),
        _ReportDef(
          title: 'Thưởng & phụ cấp',
          filters: const [_FilterKind.year, _FilterKind.month],
          fetch: (f) => _svc.bonusAllowance(year: f.year, month: f.month),
          excel: (f) => _svc.bonusAllowanceExcel(year: f.year, month: f.month),
        ),
        _ReportDef(
          title: 'Trạng thái payslip',
          subtitle: 'Draft / Pending / Approved / Paid',
          filters: const [_FilterKind.year, _FilterKind.month],
          fetch: (f) =>
              _svc.payslipStatusDistribution(year: f.year, month: f.month),
          excel: (f) => _svc.payslipStatusDistributionExcel(
              year: f.year, month: f.month),
        ),
      ],
    );
  }

  // ════════════════════════ CLUSTER 6 ════════════════════════
  Widget _clusterFinance() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Tổng hợp phiếu phạt',
          filters: const [_FilterKind.range, _FilterKind.department],
          fetch: (f) => _svc.penaltySummary(
              from: f.from, to: f.to, department: f.department),
          excel: (f) => _svc.penaltySummaryExcel(
              from: f.from, to: f.to, department: f.department),
        ),
        _ReportDef(
          title: 'Dư nợ ứng lương',
          filters: const [_FilterKind.range, _FilterKind.department],
          fetch: (f) => _svc.advanceDebt(
              from: f.from, to: f.to, department: f.department),
          excel: (f) => _svc.advanceDebtExcel(
              from: f.from, to: f.to, department: f.department),
        ),
        _ReportDef(
          title: 'Công nợ tiền ăn',
          subtitle: 'Nhập kỳ YYYY-MM hoặc khoảng ngày',
          filters: const [_FilterKind.period, _FilterKind.range],
          fetch: (f) =>
              _svc.mealDebt(period: f.period, from: f.from, to: f.to),
          excel: (f) =>
              _svc.mealDebtExcel(period: f.period, from: f.from, to: f.to),
        ),
      ],
    );
  }

  // ════════════════════════ CLUSTER 7 ════════════════════════
  Widget _clusterPerformance() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Tổng hợp KPI',
          filters: const [_FilterKind.year, _FilterKind.month, _FilterKind.department],
          fetch: (f) => _svc.kpiSummary(
              year: f.year, month: f.month, department: f.department),
          excel: (f) => _svc.kpiSummaryExcel(
              year: f.year, month: f.month, department: f.department),
        ),
        _ReportDef(
          title: 'Sản lượng (Production)',
          filters: const [_FilterKind.range, _FilterKind.department],
          fetch: (f) => _svc.productionOutput(
              from: f.from, to: f.to, department: f.department),
          excel: (f) => _svc.productionOutputExcel(
              from: f.from, to: f.to, department: f.department),
        ),
        _ReportDef(
          title: 'Tài sản cấp phát',
          subtitle: 'Assigned / In-stock / Broken / Lost',
          filters: const [_FilterKind.department],
          fetch: (f) => _svc.assetAssignment(department: f.department),
          excel: (f) => _svc.assetAssignmentExcel(department: f.department),
        ),
      ],
    );
  }

  // ════════════════════════ CLUSTER 8 ════════════════════════
  Widget _clusterExecutive() {
    return _ReportCluster(
      reports: [
        _ReportDef(
          title: 'Tổng hợp điều hành tháng',
          subtitle: 'Dashboard 1 trang: NS / Chấm công / Phép / Lương / Tài chính',
          filters: const [_FilterKind.year, _FilterKind.month],
          fetch: (f) =>
              _svc.executiveMonthlySummary(year: f.year, month: f.month),
          excel: (f) => _svc.executiveMonthlySummaryExcel(
              year: f.year, month: f.month),
        ),
      ],
    );
  }
}

// ══════════════════════ Shared cluster widget ══════════════════════

enum _FilterKind {
  year,
  month,
  range,
  department,
  employee,
  groupBy,
  days,
  years,
  period,
}

class _FilterState {
  int? year;
  int? month;
  DateTime? from;
  DateTime? to;
  String? department;
  String? employeeCode;
  String? groupBy;
  int? days;
  int? years;
  String? period;
}

class _ReportDef {
  final String title;
  final String? subtitle;
  final List<_FilterKind> filters;
  final Map<String, dynamic>? defaults;
  final Future<Map<String, dynamic>> Function(_FilterState f) fetch;
  final Future<Map<String, dynamic>> Function(_FilterState f) excel;

  _ReportDef({
    required this.title,
    this.subtitle,
    required this.filters,
    this.defaults,
    required this.fetch,
    required this.excel,
  });
}

class _ReportCluster extends StatelessWidget {
  final List<_ReportDef> reports;
  const _ReportCluster({required this.reports});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: reports.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ReportCard(def: reports[i]),
    );
  }
}

class _ReportCard extends StatefulWidget {
  final _ReportDef def;
  const _ReportCard({required this.def});
  @override
  State<_ReportCard> createState() => _ReportCardState();
}

class _ReportCardState extends State<_ReportCard> {
  final _filter = _FilterState();
  bool _loading = false;
  bool _exporting = false;
  Map<String, dynamic>? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _filter.year = now.year;
    _filter.month = now.month;
    _filter.from = DateTime(now.year, now.month, 1);
    _filter.to = now;
    final d = widget.def.defaults;
    if (d != null) {
      _filter.days = d['days'] as int?;
      _filter.years = d['years'] as int?;
    }
  }

  Future<void> _run() async {
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    final res = await widget.def.fetch(_filter);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true) {
        _result = res['data'] is Map<String, dynamic>
            ? res['data'] as Map<String, dynamic>
            : {'value': res['data']};
      } else {
        _error = res['message']?.toString() ?? 'Không tải được dữ liệu';
      }
    });
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final res = await widget.def.excel(_filter);
    if (!mounted) return;
    setState(() => _exporting = false);
    final ok = res['isSuccess'] == true;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: ok ? Colors.green : Colors.red,
      content: Text(ok
          ? 'Đã tải Excel thành công'
          : 'Lỗi: ${res['message'] ?? 'không xác định'}'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(widget.def.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: widget.def.subtitle == null
            ? null
            : Text(widget.def.subtitle!,
                style: const TextStyle(fontSize: 12)),
        childrenPadding: const EdgeInsets.all(12),
        children: [
          // Filter card
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.blue.shade50, Colors.indigo.shade50],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.tune, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text('Bộ lọc',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Colors.blue.shade900)),
                ]),
                const SizedBox(height: 10),
                _filterRow(),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _loading ? null : _run,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _loading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.search, size: 18),
                      label: const Text('Xem báo cáo',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    OutlinedButton.icon(
                      onPressed: _exporting ? null : _export,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green.shade700,
                        side: BorderSide(color: Colors.green.shade300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _exporting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.file_download_outlined,
                              size: 18),
                      label: const Text('Xuất Excel',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                border: Border.all(color: Colors.red.shade200),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(Icons.error_outline,
                    color: Colors.red.shade700, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade900)),
                ),
              ]),
            ),
          if (_result != null) _ResultView(data: _result!),
        ],
      ),
    );
  }

  Widget _filterRow() {
    final kinds = widget.def.filters;
    final widgets = <Widget>[];
    for (final k in kinds) {
      switch (k) {
        case _FilterKind.year:
          widgets.add(_yearField());
          break;
        case _FilterKind.month:
          widgets.add(_monthField());
          break;
        case _FilterKind.range:
          widgets.add(_dateField('Từ', _filter.from, (d) => _filter.from = d));
          widgets.add(_dateField('Đến', _filter.to, (d) => _filter.to = d));
          break;
        case _FilterKind.department:
          widgets.add(_textField('Phòng ban', (v) => _filter.department = v));
          break;
        case _FilterKind.employee:
          widgets.add(_textField('Mã NV', (v) => _filter.employeeCode = v));
          break;
        case _FilterKind.groupBy:
          widgets.add(_groupByField());
          break;
        case _FilterKind.days:
          widgets.add(_intField('Số ngày', _filter.days,
              (v) => _filter.days = v, defaultV: 90));
          break;
        case _FilterKind.years:
          widgets.add(_intField('Số năm', _filter.years,
              (v) => _filter.years = v, defaultV: 5));
          break;
        case _FilterKind.period:
          widgets.add(_textField('Kỳ (YYYY-MM)', (v) => _filter.period = v));
          break;
      }
    }
    return Wrap(spacing: 8, runSpacing: 8, children: widgets);
  }

  Widget _yearField() => SizedBox(
        width: 90,
        child: TextFormField(
          initialValue: _filter.year?.toString(),
          decoration: const InputDecoration(
              labelText: 'Năm', isDense: true, border: OutlineInputBorder()),
          keyboardType: TextInputType.number,
          onChanged: (v) => _filter.year = int.tryParse(v),
        ),
      );

  Widget _monthField() => SizedBox(
        width: 90,
        child: TextFormField(
          initialValue: _filter.month?.toString(),
          decoration: const InputDecoration(
              labelText: 'Tháng', isDense: true, border: OutlineInputBorder()),
          keyboardType: TextInputType.number,
          onChanged: (v) => _filter.month = int.tryParse(v),
        ),
      );

  Widget _dateField(String label, DateTime? value, void Function(DateTime) set) {
    final df = DateFormat('dd/MM/yyyy');
    return SizedBox(
      width: 160,
      child: InkWell(
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? DateTime.now(),
            firstDate: DateTime(2020),
            lastDate: DateTime(2035),
          );
          if (picked != null) setState(() => set(picked));
        },
        child: InputDecorator(
          decoration: InputDecoration(
              labelText: label,
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.calendar_today, size: 16)),
          child: Text(value == null ? '-' : df.format(value)),
        ),
      ),
    );
  }

  Widget _textField(String label, void Function(String?) onChange) => SizedBox(
        width: 180,
        child: TextFormField(
          decoration: InputDecoration(
              labelText: label, isDense: true, border: const OutlineInputBorder()),
          onChanged: (v) => onChange(v.trim().isEmpty ? null : v.trim()),
        ),
      );

  Widget _intField(String label, int? value, void Function(int?) onChange,
          {int? defaultV}) =>
      SizedBox(
        width: 110,
        child: TextFormField(
          initialValue: (value ?? defaultV)?.toString(),
          decoration: InputDecoration(
              labelText: label, isDense: true, border: const OutlineInputBorder()),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChange(int.tryParse(v)),
        ),
      );

  Widget _groupByField() => SizedBox(
        width: 160,
        child: DropdownButtonFormField<String>(
          initialValue: _filter.groupBy ?? 'department',
          decoration: const InputDecoration(
              labelText: 'Group by',
              isDense: true,
              border: OutlineInputBorder()),
          items: const [
            DropdownMenuItem(value: 'department', child: Text('Phòng ban')),
            DropdownMenuItem(value: 'branch', child: Text('Chi nhánh')),
          ],
          onChanged: (v) => _filter.groupBy = v,
        ),
      );
}

// ───────────────── Result preview (generic JSON renderer) ─────────────────

class _ResultView extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ResultView({required this.data});

  // Vietnamese labels — covers all DTO fields across the 29 endpoints.
  // Keys stored in camelCase; lookup is case-insensitive with PascalCase fallback.
  static const Map<String, String> _labels = {
    // ── Filters / time
    'year': 'Năm', 'month': 'Tháng', 'years': 'Năm',
    'from': 'Từ ngày', 'to': 'Đến ngày', 'date': 'Ngày',
    'fromDate': 'Từ ngày', 'toDate': 'Đến ngày',
    'period': 'Kỳ', 'periodId': 'Kỳ KPI', 'periodName': 'Tên kỳ',
    'periodStart': 'Bắt đầu kỳ', 'periodEnd': 'Kết thúc kỳ',
    'absenceDate': 'Ngày vắng',
    'scheduledDate': 'Ngày dự kiến',
    'dayOfWeek': 'Thứ',
    'daysRemaining': 'Số ngày còn',
    'daysUntil': 'Số ngày đến',
    'yearsRemaining': 'Số năm còn',
    'days': 'Số ngày',
    // ── Grouping
    'department': 'Phòng ban', 'branch': 'Chi nhánh',
    'store': 'Cửa hàng', 'storeName': 'Cửa hàng',
    'groupBy': 'Nhóm theo', 'groupName': 'Nhóm',
    'byEmployee': 'Theo nhân viên', 'byDepartment': 'Theo phòng ban',
    'byBranch': 'Theo chi nhánh', 'byLevel': 'Theo cấp bậc',
    'byProduct': 'Theo sản phẩm', 'byStatus': 'Theo trạng thái',
    'byType': 'Theo loại',
    'bucket': 'Nhóm', 'buckets': 'Các nhóm',
    'key': 'Khóa', 'type': 'Loại', 'other': 'Khác',
    // ── Employee
    'employeeCode': 'Mã NV', 'code': 'Mã',
    'pin': 'Mã chấm công',
    'name': 'Tên', 'fullName': 'Họ tên', 'employeeName': 'Họ tên',
    'employeeCount': 'Số nhân viên', 'totalEmployees': 'Tổng nhân viên',
    'affectedEmployees': 'NV bị ảnh hưởng',
    'position': 'Chức vụ', 'title': 'Chức vụ',
    'dateOfBirth': 'Ngày sinh', 'birthday': 'Sinh nhật',
    'nextBirthday': 'Sinh nhật sắp tới',
    'gender': 'Giới tính', 'age': 'Tuổi',
    'avgAge': 'Tuổi TB',
    'tenureYears': 'Thâm niên (năm)',
    'joinDate': 'Ngày vào',
    'employmentType': 'Loại HĐLĐ',
    'turningAge': 'Đến tuổi',
    // Age buckets
    'ageUnder25': 'Dưới 25',
    'age_Under25': 'Dưới 25',
    'age2534': '25–34', 'age_25_34': '25–34',
    'age3544': '35–44', 'age_35_44': '35–44',
    'age4554': '45–54', 'age_45_54': '45–54',
    'age55Plus': '55+', 'age_55Plus': '55+',
    'male': 'Nam', 'female': 'Nữ',
    // ── Attendance
    'standardDays': 'Ngày công chuẩn',
    'daysWorked': 'Ngày làm',
    'presentDays': 'Ngày có mặt',
    'absentDays': 'Ngày vắng',
    'lateDays': 'Ngày đi trễ',
    'lateCount': 'Số lần trễ',
    'earlyCount': 'Số lần về sớm',
    'forgotCount': 'Số lần quên chấm',
    'leaveDays': 'Ngày nghỉ phép',
    'complianceRate': 'Tỷ lệ tuân thủ (%)',
    'avgComplianceRate': 'TB tuân thủ (%)',
    'punchCount': 'Số lượt chấm',
    'totalPunches': 'Tổng lượt chấm',
    'avgPunchesPerDay': 'TB lượt/ngày',
    'firstPunch': 'Chấm đầu',
    'lastPunch': 'Chấm cuối',
    'checkIns': 'Lượt vào',
    'checkOuts': 'Lượt ra',
    'totalMinutes': 'Tổng phút',
    'uniqueManDays': 'Ngày công (unique)',
    'details': 'Chi tiết',
    'issues': 'Vấn đề',
    'anomalyType': 'Loại bất thường',
    'reason': 'Lý do',
    // ── Field / Mobile / WiFi
    'firstVisit': 'Lần đầu',
    'lastVisit': 'Lần cuối',
    'totalVisits': 'Tổng lượt',
    'distinctLocations': 'Số địa điểm',
    'wifiCount': 'Lượt WiFi',
    'faceGpsCount': 'Lượt Face + GPS',
    'devicesUsed': 'Thiết bị dùng',
    // ── Leave / Shift
    'leaveType': 'Loại phép',
    'paidEntitlement': 'Phép có lương',
    'paidUsed': 'Phép có lương đã dùng',
    'paidRemaining': 'Phép có lương còn',
    'unpaidUsed': 'Phép không lương',
    'sickUsed': 'Nghỉ ốm',
    'otherUsed': 'Loại khác',
    'pendingLeaves': 'Đơn chờ duyệt',
    'approvedLeaves': 'Đơn đã duyệt',
    'approvedUnpaid': 'Đã duyệt không lương',
    'approved': 'Đã duyệt',
    'pending': 'Chờ duyệt',
    'rejected': 'Từ chối',
    'cancelled': 'Đã hủy',
    'rejectionRate': 'Tỷ lệ từ chối',
    'approvalRate': 'Tỷ lệ duyệt',
    'avgResolutionHours': 'TB giờ xử lý',
    'avgResponseHours': 'TB giờ phản hồi',
    'approverId': 'Mã người duyệt',
    'approverName': 'Người duyệt',
    'approvers': 'Người duyệt',
    'shift': 'Ca', 'shiftId': 'Mã ca', 'shiftName': 'Tên ca',
    'minRequired': 'Yêu cầu tối thiểu',
    'maxAllowed': 'Tối đa cho phép',
    'assigned': 'Đã phân', 'assignedCount': 'Số đã phân',
    'gap': 'Chênh lệch',
    'underCount': 'Thiếu',
    'overCount': 'Thừa',
    'okCount': 'Đạt',
    'totalSwaps': 'Tổng lần đổi ca',
    // ── HR / Lifecycle
    'headcount': 'Tổng nhân sự',
    'headcountStart': 'Đầu kỳ',
    'headcountEnd': 'Cuối kỳ',
    'atMonthStart': 'Đầu tháng',
    'atMonthEnd': 'Cuối tháng',
    'yearEndHeadcount': 'NS cuối năm',
    'endingHeadcount': 'NS cuối kỳ',
    'hired': 'Tuyển mới', 'totalHired': 'Tổng tuyển mới',
    'resigned': 'Nghỉ việc', 'totalResigned': 'Tổng nghỉ việc',
    'netChange': 'Biến động ròng',
    'turnoverRate': 'Tỷ lệ nghỉ việc',
    'turnoverRatePercent': 'Nghỉ việc (%)',
    'expiryDate': 'Ngày hết hạn',
    'retirementDate': 'Ngày nghỉ hưu',
    'urgent30': 'Dưới 30 ngày',
    'soon60': 'Dưới 60 ngày',
    'later90': 'Dưới 90 ngày',
    'registered': 'Đã đăng ký',
    // ── Payroll
    'baseSalary': 'Lương cơ bản',
    'totalBase': 'Tổng lương CB',
    'overtimePay': 'Tiền OT',
    'overtimeUnits': 'Đơn vị OT',
    'totalOvertime': 'Tổng OT',
    'totalOt': 'Tổng tiền OT',
    'bonus': 'Thưởng',
    'totalBonus': 'Tổng thưởng',
    'avgBonus': 'Thưởng TB',
    'allowances': 'Phụ cấp',
    'totalAllowances': 'Tổng phụ cấp',
    'avgAllowances': 'Phụ cấp TB',
    'deductions': 'Khấu trừ',
    'totalDeductions': 'Tổng khấu trừ',
    'tax': 'Thuế TNCN',
    'totalTax': 'Tổng thuế',
    'insurance': 'Bảo hiểm',
    'totalInsurance': 'Tổng BH',
    'grossSalary': 'Tổng lương',
    'totalGross': 'Tổng gross',
    'grossPercent': 'Tỷ trọng gross (%)',
    'netSalary': 'Thực lĩnh',
    'totalNet': 'Tổng thực lĩnh',
    'otRatioPercent': 'Tỷ lệ OT (%)',
    'overallRatio': 'Tỷ lệ chung',
    'payslipCount': 'Số phiếu lương',
    'payroll': 'Lương',
    // ── Finance
    'amount': 'Số tiền',
    'avgAmount': 'Số tiền TB',
    'totalAmount': 'Tổng tiền',
    'paidAmount': 'Đã thanh toán',
    'pendingAmount': 'Đang chờ',
    'approvedAmount': 'Đã duyệt (tiền)',
    'rejectedAmount': 'Từ chối (tiền)',
    'cancelledAmount': 'Đã hủy (tiền)',
    'outstandingDebt': 'Dư nợ',
    'totalOutstanding': 'Tổng dư nợ',
    'totalPaid': 'Tổng đã thu',
    'totalApproved': 'Tổng đã duyệt',
    'totalRejected': 'Tổng từ chối',
    'totalRequested': 'Tổng yêu cầu',
    'totalRequests': 'Tổng đơn',
    'ticketCount': 'Số phiếu',
    'totalTickets': 'Tổng phiếu',
    'penaltyApproved': 'Phạt đã duyệt',
    'advanceApproved': 'Ứng đã duyệt',
    'advanceOutstanding': 'Ứng còn nợ',
    'mealCharge': 'Tiền ăn phát sinh',
    'mealPayment': 'Tiền ăn đã thu',
    'mealOutstanding': 'Tiền ăn còn nợ',
    'totalCharge': 'Tổng phát sinh',
    'totalPayment': 'Tổng thanh toán',
    'lastTransactionDate': 'GD gần nhất',
    // ── Performance
    'kpiCount': 'Số KPI',
    'avgScore': 'Điểm TB',
    'totalScore': 'Tổng điểm',
    'avgCompletion': 'Hoàn thành TB (%)',
    'completionPercent': 'Hoàn thành (%)',
    'weightedScore': 'Điểm trọng số',
    'target': 'Mục tiêu',
    'actual': 'Thực tế',
    'ratio': 'Tỷ lệ',
    'percent': 'Phần trăm',
    'usagePercent': '% sử dụng',
    'topPerformers': 'NV xuất sắc',
    // Production
    'productCode': 'Mã SP',
    'productName': 'Tên SP',
    'quantity': 'Số lượng',
    'totalQuantity': 'Tổng SL',
    'totalEntries': 'Số bản ghi',
    'avgDailyQuantity': 'SL TB / ngày',
    'unit': 'Đơn vị',
    // Assets
    'assetCode': 'Mã tài sản',
    'assetName': 'Tên tài sản',
    'assignedDate': 'Ngày cấp',
    'brand': 'Thương hiệu',
    'serialNumber': 'Số serial',
    'currentValue': 'Giá trị hiện tại',
    'totalValue': 'Tổng giá trị',
    'totalAssets': 'Tổng TS',
    'inStockCount': 'Tồn kho',
    'brokenCount': 'Hỏng',
    'lostCount': 'Mất',
    'disposedCount': 'Thanh lý',
    'assignments': 'Phân bổ',
    // ── Executive
    'attendance': 'Chấm công',
    'leave': 'Nghỉ phép',
    'finance': 'Tài chính',
    'pendingCount': 'Đang chờ',
    'rejectedCount': 'Bị từ chối',
    'otherCount': 'Khác',
    'totalNoShows': 'Tổng vắng mặt',
    'totalAbsenceRecords': 'Tổng lượt vắng',
    // ── Status values
    'status': 'Trạng thái',
    'total': 'Tổng',
    'count': 'Số lượng',
    'items': 'Danh sách',
  };

  bool _isHiddenKey(String k) {
    final lk = k.toLowerCase();
    if (lk == 'id') return true;
    if (lk.endsWith('id') && lk != 'pid') return true;
    if (lk.endsWith('guid') || lk.endsWith('uuid')) return true;
    return false;
  }

  // Cached lowercase lookup map, built once
  static final Map<String, String> _labelsLower = {
    for (final e in _labels.entries) e.key.toLowerCase(): e.value,
  };

  // Status/enum value translations
  static const Map<String, String> _statusVi = {
    'draft': 'Nháp',
    'pending': 'Chờ duyệt',
    'approved': 'Đã duyệt',
    'rejected': 'Từ chối',
    'cancelled': 'Đã hủy',
    'canceled': 'Đã hủy',
    'paid': 'Đã thanh toán',
    'unpaid': 'Chưa thanh toán',
    'active': 'Đang hoạt động',
    'inactive': 'Ngừng',
    'probation': 'Thử việc',
    'working': 'Đang làm',
    'resigned': 'Đã nghỉ',
    'retired': 'Đã nghỉ hưu',
    'assigned': 'Đã cấp',
    'available': 'Sẵn sàng',
    'instock': 'Tồn kho',
    'broken': 'Hỏng',
    'lost': 'Mất',
    'disposed': 'Thanh lý',
    'male': 'Nam',
    'female': 'Nữ',
    'other': 'Khác',
    'none': 'Không',
    'na': 'N/A',
  };

  String _label(String k) {
    final lk = k.toLowerCase();
    final v = _labelsLower[lk];
    if (v != null) return v;
    // Humanize camelCase / PascalCase → "Camel case"
    final spaced = k.replaceAllMapped(
        RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]!.toLowerCase()}');
    final cleaned = spaced.replaceAll('_', ' ').trim();
    if (cleaned.isEmpty) return k;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> primaryList = _pickList(data);
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _summaryStatGrid(isNarrow),
        if (primaryList.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.table_rows_outlined, size: 16, color: Colors.blueGrey),
              const SizedBox(width: 6),
              Text('Chi tiết (${primaryList.length} dòng)',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: Colors.blueGrey)),
            ],
          ),
          const SizedBox(height: 8),
          isNarrow ? _buildCardList(primaryList) : _buildTable(primaryList),
        ] else if (_hasOnlyScalars(data)) ...[
          // already shown in stat grid
        ] else ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            width: double.infinity,
            child: Text(
              const JsonEncoder.withIndent('  ').convert(data),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ],
    );
  }

  bool _hasOnlyScalars(Map<String, dynamic> m) =>
      m.values.every((v) => v is! Map && v is! List);

  /// Modern stat grid — 2 cột trên mobile, 4 cột trên rộng.
  Widget _summaryStatGrid(bool isNarrow) {
    final fields = <MapEntry<String, dynamic>>[];
    data.forEach((k, v) {
      if (v is! Map && v is! List && !_isHiddenKey(k)) {
        fields.add(MapEntry(k, v));
      }
    });
    if (fields.isEmpty) return const SizedBox();

    final crossAxisCount = isNarrow ? 2 : 4;
    return LayoutBuilder(builder: (context, c) {
      final tileW = (c.maxWidth - (crossAxisCount - 1) * 8) / crossAxisCount;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: fields.map((e) {
          final col = _colorForKey(e.key);
          return SizedBox(
            width: tileW,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [col.withValues(alpha: .12), col.withValues(alpha: .04)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: col.withValues(alpha: .35), width: .6),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_label(e.key),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: col.withValues(alpha: .9),
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_fmt(e.value, e.key),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }).toList(),
      );
    });
  }

  Color _colorForKey(String k) {
    final lk = k.toLowerCase();
    if (lk.contains('rate') || lk.contains('pct') || lk.contains('percent'))
      return const Color(0xFF059669);
    if (lk.contains('total') || lk.contains('count')) return const Color(0xFF2563EB);
    if (lk.contains('approved') || lk.contains('paid')) return const Color(0xFF16A34A);
    if (lk.contains('rejected') || lk.contains('cancelled') ||
        lk.contains('absent') || lk.contains('late') ||
        lk.contains('outstanding') || lk.contains('debt') ||
        lk.contains('broken') || lk.contains('lost')) return const Color(0xFFDC2626);
    if (lk.contains('pending') || lk.contains('draft')) return const Color(0xFFEA580C);
    if (lk.contains('date') || lk == 'period' || lk == 'year' || lk == 'month')
      return const Color(0xFF7C3AED);
    return const Color(0xFF475569);
  }

  String _fmt(dynamic v, [String key = '']) {
    if (v == null) return '-';
    if (v is bool) return v ? 'Có' : 'Không';
    if (v is num) {
      final lk = key.toLowerCase();
      if (lk.contains('rate') ||
          lk.contains('pct') ||
          lk.contains('percent') ||
          lk.contains('ratio')) {
        return '${NumberFormat('#,##0.##', 'vi_VN').format(v)}%';
      }
      // Money-like keys → add ₫
      if (lk.contains('salary') ||
          lk.contains('amount') ||
          lk.contains('cost') ||
          lk.contains('pay') ||
          lk.contains('bonus') ||
          lk.contains('allowance') ||
          lk.contains('tax') ||
          lk.contains('deduction') ||
          lk.contains('insurance') ||
          lk.contains('debt') ||
          lk.contains('charge') ||
          lk.contains('payment') ||
          lk.contains('value') ||
          lk.contains('price') ||
          lk.contains('gross') ||
          lk.contains('net') ||
          lk.contains('outstanding')) {
        return '${NumberFormat('#,##0', 'vi_VN').format(v)} ₫';
      }
      if (v is int || v == v.toInt()) {
        return NumberFormat('#,##0', 'vi_VN').format(v);
      }
      return NumberFormat('#,##0.##', 'vi_VN').format(v);
    }
    if (v is String) {
      // Status mapping
      final st = _statusVi[v.toLowerCase().replaceAll(' ', '')];
      if (st != null) return st;
      if (v.length >= 10) {
        final dt = DateTime.tryParse(v);
        if (dt != null) {
          final hasTime = v.contains('T') && !v.endsWith('T00:00:00');
          return hasTime
              ? DateFormat('dd/MM/yyyy HH:mm').format(dt)
              : DateFormat('dd/MM/yyyy').format(dt);
        }
      }
    }
    return v.toString();
  }

  List<Map<String, dynamic>> _pickList(Map<String, dynamic> m) {
    const prefer = [
      'Items', 'items',
      'ByEmployee', 'byEmployee',
      'Assignments', 'assignments',
      'Buckets', 'buckets',
      'Rows', 'rows',
    ];
    for (final k in prefer) {
      final v = m[k];
      if (v is List && v.isNotEmpty && v.first is Map) {
        return v.cast<Map<String, dynamic>>();
      }
    }
    for (final v in m.values) {
      if (v is List && v.isNotEmpty && v.first is Map) {
        return v.cast<Map<String, dynamic>>();
      }
    }
    return [];
  }

  List<String> _cols(Map<String, dynamic> first) {
    return first.keys
        .where((k) =>
            first[k] is! Map && first[k] is! List && !_isHiddenKey(k))
        .toList();
  }

  Widget _buildTable(List<Map<String, dynamic>> rows) {
    final cols = _cols(rows.first);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columnSpacing: 16,
        headingRowColor:
            WidgetStateProperty.all(Colors.blueGrey.shade50),
        columns: cols
            .map((c) => DataColumn(
                label: Text(_label(c),
                    style: const TextStyle(fontWeight: FontWeight.bold))))
            .toList(),
        rows: rows
            .take(200)
            .map((r) => DataRow(
                cells: cols
                    .map((c) => DataCell(Text(_fmt(r[c], c))))
                    .toList()))
            .toList(),
      ),
    );
  }

  Widget _buildCardList(List<Map<String, dynamic>> rows) {
    final cols = _cols(rows.first);
    const titleKeys = [
      'FullName', 'fullName',
      'EmployeeName', 'employeeName',
      'Name', 'name',
      'Date', 'date',
      'Department', 'department',
      'Branch', 'branch',
      'ShiftName', 'shiftName', 'Shift', 'shift',
      'ProductName', 'productName',
      'AssetName', 'assetName',
      'LeaveType', 'leaveType',
      'Bucket', 'bucket',
      'TenureRange', 'tenureRange',
      'Status', 'status',
    ];
    const subtitleKeys = [
      'employeeCode', 'EmployeeCode', 'code', 'Code',
      'department', 'Department',
      'position', 'Position',
      'assetCode', 'AssetCode',
      'productCode', 'ProductCode',
    ];
    String? titleKey;
    for (final t in titleKeys) {
      if (cols.contains(t)) {
        titleKey = t;
        break;
      }
    }
    titleKey ??= cols.isNotEmpty ? cols.first : null;
    String? subtitleKey;
    for (final s in subtitleKeys) {
      if (cols.contains(s) && s != titleKey) {
        subtitleKey = s;
        break;
      }
    }

    return Column(
      children: rows.take(200).map((r) {
        final title =
            titleKey != null ? _fmt(r[titleKey], titleKey) : '';
        final subtitle = subtitleKey != null
            ? '${_label(subtitleKey)}: ${_fmt(r[subtitleKey], subtitleKey)}'
            : '';
        final fields = cols
            .where((c) => c != titleKey && c != subtitleKey)
            .toList();
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blueGrey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(10),
                    topRight: Radius.circular(10),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title.isNotEmpty && title != '-')
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Color(0xFF0F172A))),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle,
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.blueGrey.shade700)),
                      ),
                  ],
                ),
              ),
              // Field grid — 2 columns for tighter mobile view
              Padding(
                padding: const EdgeInsets.all(10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: fields.map((c) {
                    return SizedBox(
                      width: 150,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_label(c),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500)),
                          const SizedBox(height: 2),
                          Text(_fmt(r[c], c),
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _colorForKey(c))),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
