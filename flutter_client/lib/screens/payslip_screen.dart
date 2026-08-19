import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/api_datetime.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/page_top_actions.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class PayslipScreen extends StatefulWidget {
  const PayslipScreen({super.key});

  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  bool _isManager = false;

  List<Map<String, dynamic>> _payslips = [];
  List<Map<String, dynamic>> _employees = [];

  int? _filterYear;
  int? _filterMonth;
  String? _filterEmployeeUserId;
  String? _filterDepartment;
  DateTime? _filterFromDate;
  DateTime? _filterToDate;
  bool _filtersExpanded = false;
  final Set<String> _expandedPayslipIds = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initAndLoad());
  }

  Future<void> _initAndLoad() async {
    final role = context.read<AuthProvider>().user?.role ?? '';
    _isManager = role == 'Admin' ||
        role == 'Manager' ||
        role == 'SuperAdmin' ||
        role == 'Agent' ||
        role == 'DepartmentHead' ||
        role == 'HR';
    if (_isManager) await _loadEmployees();
    await _loadData();
  }

  Future<void> _loadEmployees() async {
    try {
      final list = await _apiService.getEmployeesForSelect(pageSize: 1000);
      if (!mounted) return;
      setState(() {
        _employees = list
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (_) {}
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic> res;
      if (_isManager) {
        res = await _apiService.getStorePayslips(
          year: _filterYear,
          month: _filterMonth,
          employeeUserId: _filterEmployeeUserId,
          department: _filterDepartment,
          periodStartFrom: _filterFromDate,
          periodEndTo: _filterToDate != null
              ? DateTime(
                  _filterToDate!.year,
                  _filterToDate!.month,
                  _filterToDate!.day,
                  23,
                  59,
                  59,
                )
              : null,
        );
      } else {
        res = await _apiService.getMyPayslips();
      }
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() {
          _payslips = List<Map<String, dynamic>>.from(res['data'] ?? []);
        });
      }
    } catch (e) {
      debugPrint('Error loading payslips: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<String> get _departments {
    final depts = _employees
        .map((e) => (e['department'] ?? e['departmentName'])?.toString().trim())
        .where((d) => d != null && d.isNotEmpty)
        .cast<String>()
        .toSet()
        .toList();
    depts.sort();
    return depts;
  }

  List<Map<String, dynamic>> get _filteredPayslips {
    return _payslips.where((p) {
      final y = (p['year'] as num?)?.toInt();
      final m = (p['month'] as num?)?.toInt();
      if (_filterYear != null && y != _filterYear) return false;
      if (_filterMonth != null && m != _filterMonth) return false;
      if (_filterEmployeeUserId != null &&
          p['employeeUserId']?.toString() != _filterEmployeeUserId) {
        return false;
      }
      if (_filterDepartment != null &&
          (p['department']?.toString() ?? '') != _filterDepartment) {
        return false;
      }
      if (_filterFromDate != null || _filterToDate != null) {
        final start = parseApiUtcDateTime(p['periodStart']);
        final end = parseApiUtcDateTime(p['periodEnd']);
        if (_filterFromDate != null &&
            end != null &&
            end.isBefore(_filterFromDate!)) {
          return false;
        }
        if (_filterToDate != null &&
            start != null &&
            start.isAfter(DateTime(
              _filterToDate!.year,
              _filterToDate!.month,
              _filterToDate!.day,
              23,
              59,
              59,
            ))) {
          return false;
        }
      }
      return true;
    }).toList()
      ..sort((a, b) {
        final ay = (a['year'] as num?)?.toInt() ?? 0;
        final by = (b['year'] as num?)?.toInt() ?? 0;
        if (ay != by) return by.compareTo(ay);
        final am = (a['month'] as num?)?.toInt() ?? 0;
        final bm = (b['month'] as num?)?.toInt() ?? 0;
        if (am != bm) return bm.compareTo(am);
        return (a['employeeName']?.toString() ?? '')
            .compareTo(b['employeeName']?.toString() ?? '');
      });
  }

  void _resetFilters() {
    setState(() {
      _filterYear = null;
      _filterMonth = null;
      _filterEmployeeUserId = null;
      _filterDepartment = null;
      _filterFromDate = null;
      _filterToDate = null;
    });
    if (_isManager) _loadData();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom
        ? (_filterFromDate ?? DateTime.now())
        : (_filterToDate ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _filterFromDate = picked;
      } else {
        _filterToDate = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 768;
    final list = _filteredPayslips;
    return RegisterPageTopActions(
      actions: [
        HrmTopBarAction(
          icon: Icons.refresh,
          label: 'Tải lại',
          onPressed: _isLoading ? null : _loadData,
        ),
      ],
      child: Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildFilterPanel(isMobile),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                          itemCount: list.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildPayslipCard(list[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long, size: 72, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(tr('Chưa có phiếu lương'),
            style: TextStyle(color: Colors.grey[500], fontSize: 16),
          ),
          if (_isManager) ...[
            const SizedBox(height: 8),
            Text(tr('Chốt lương tại Tổng hợp lương để tạo phiếu'),
              style: TextStyle(color: Colors.grey[400], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterPanel(bool isMobile) {
    return Material(
      color: Colors.white,
      child: ExpansionTile(
        initiallyExpanded: _filtersExpanded,
        onExpansionChanged: (v) => setState(() => _filtersExpanded = v),
        title: Text(tr('Bộ lọc'),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Text(
          tr(_filterSummary()),
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: _resetFilters, child: Text(tr('Xóa lọc'))),
            Icon(
              _filtersExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey[600],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: isMobile
                ? Column(
                    children: [
                      _yearMonthRow(),
                      const SizedBox(height: 8),
                      if (_isManager) ...[
                        _employeeDropdown(),
                        const SizedBox(height: 8),
                        _departmentDropdown(),
                        const SizedBox(height: 8),
                      ],
                      _dateRangeRow(),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _isLoading ? null : _loadData,
                          icon: const Icon(Icons.search, size: 18),
                          label: Text(tr('Áp dụng bộ lọc')),
                        ),
                      ),
                    ],
                  )
                : Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _yearMonthRow(),
                      if (_isManager) ...[
                        _employeeDropdown(),
                        _departmentDropdown(),
                      ],
                      _dateRangeRow(),
                      FilledButton.icon(
                        onPressed: _isLoading ? null : _loadData,
                        icon: const Icon(Icons.search, size: 18),
                        label: Text(tr('Áp dụng')),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _filterSummary() {
    final parts = <String>[];
    if (_filterYear != null) {
      parts.add('Năm $_filterYear');
    } else {
      parts.add('Tất cả năm');
    }
    if (_filterMonth != null) parts.add('T$_filterMonth');
    if (_filterDepartment != null) parts.add(_filterDepartment!);
    if (_filterFromDate != null) {
      parts.add('Từ ${DateFormat('dd/MM/yy').format(_filterFromDate!)}');
    }
    if (_filterToDate != null) {
      parts.add('Đến ${DateFormat('dd/MM/yy').format(_filterToDate!)}');
    }
    return parts.join(' · ');
  }

  Widget _yearMonthRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<int?>(
            value: _filterYear,
            decoration: _filterDecoration('Năm'),
            items: [
              DropdownMenuItem<int?>(
                value: null,
                child: Text(tr('Tất cả năm')),
              ),
              ...List.generate(6, (i) {
                final y = DateTime.now().year - 3 + i;
                return DropdownMenuItem(value: y, child: Text(tr('$y')));
              }),
            ],
            onChanged: (v) => setState(() => _filterYear = v),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: DropdownButtonFormField<int?>(
            value: _filterMonth,
            decoration: _filterDecoration('Tháng'),
            items: [
              DropdownMenuItem(value: null, child: Text(tr('Tất cả tháng'))),
              ...List.generate(
                12,
                (i) => DropdownMenuItem(
                  value: i + 1,
                  child: Text(tr('Tháng ${i + 1}')),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _filterMonth = v),
          ),
        ),
      ],
    );
  }

  Widget _employeeDropdown() {
    final withUser = _employees
        .where((e) => (e['applicationUserId']?.toString() ?? '').isNotEmpty)
        .toList();
    return SizedBox(
      width: 260,
      child: DropdownButtonFormField<String?>(
        value: _filterEmployeeUserId,
        isExpanded: true,
        decoration: _filterDecoration('Nhân viên'),
        items: [
          DropdownMenuItem(value: null, child: Text(tr('Tất cả nhân viên'))),
          ...withUser.map((e) {
            final uid = e['applicationUserId']?.toString() ?? '';
            final name =
                '${e['lastName'] ?? ''} ${e['firstName'] ?? ''}'.trim();
            final code = e['employeeCode']?.toString() ?? '';
            final label = name.isNotEmpty ? '$name ($code)' : code;
            return DropdownMenuItem(value: uid, child: Text(tr(label)));
          }),
        ],
        onChanged: (v) => setState(() => _filterEmployeeUserId = v),
      ),
    );
  }

  Widget _departmentDropdown() {
    return SizedBox(
      width: 200,
      child: DropdownButtonFormField<String?>(
        value: _departments.contains(_filterDepartment)
            ? _filterDepartment
            : null,
        isExpanded: true,
        decoration: _filterDecoration('Phòng ban'),
        items: [
          DropdownMenuItem(value: null, child: Text(tr('Tất cả phòng ban'))),
          ..._departments.map(
            (d) => DropdownMenuItem(value: d, child: Text(tr(d))),
          ),
        ],
        onChanged: (v) => setState(() => _filterDepartment = v),
      ),
    );
  }

  Widget _dateRangeRow() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dateChip('Từ ngày', _filterFromDate, () => _pickDate(isFrom: true)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Text(tr('—')),
        ),
        _dateChip('Đến ngày', _filterToDate, () => _pickDate(isFrom: false)),
      ],
    );
  }

  Widget _dateChip(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE4E4E7)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              tr(date != null
                  ? DateFormat('dd/MM/yyyy').format(date)
                  : label),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _filterDecoration(String label) {
    return InputDecoration(
      labelText: tr(label),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
    );
  }

  String _payslipCardId(Map<String, dynamic> p) {
    return p['id']?.toString() ??
        '${p['employeeId']}_${p['year']}_${p['month']}';
  }

  Widget _buildPayslipCard(Map<String, dynamic> p) {
    final id = _payslipCardId(p);
    final expanded = _expandedPayslipIds.contains(id);
    final month = p['month'];
    final year = p['year'];
    final monthDisplay = month != null && year != null
        ? 'T${month.toString().padLeft(2, '0')}/$year'
        : '';
    final empName = p['employeeName']?.toString() ?? '';
    final dept = p['department']?.toString() ?? '';
    final code = p['employeeCode']?.toString() ?? '';
    final status = p['status']?.toString() ?? 'Draft';
    final periodStart =
        formatApiDateTime(p['periodStart'], pattern: 'dd/MM/yyyy');
    final periodEnd = formatApiDateTime(p['periodEnd'], pattern: 'dd/MM/yyyy');
    final paymentStatus = p['paymentStatus']?.toString() ??
        ((p['isPaid'] == true) ? 'Đã thanh toán' : 'Chưa thanh toán');
    final isPaid = p['isPaid'] == true || paymentStatus == 'Đã thanh toán';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() {
                if (expanded) {
                  _expandedPayslipIds.remove(id);
                } else {
                  _expandedPayslipIds.add(id);
                }
              }),
              child: Ink(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF059669), HrmPageChrome.primaryNavy],
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(empName.isNotEmpty ? empName : 'Nhân viên'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.25,
                              ),
                            ),
                            if (code.isNotEmpty || dept.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                tr([
                                  if (code.isNotEmpty) code,
                                  if (dept.isNotEmpty) dept,
                                ].join(' · ')),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (monthDisplay.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(tr('Kỳ $monthDisplay'),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (periodStart.isNotEmpty &&
                                periodEnd.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                tr('$periodStart — $periodEnd'),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _buildStatusChip(
                                  _statusLabel(status),
                                  Colors.white.withValues(alpha: 0.2),
                                ),
                                _buildStatusChip(
                                  paymentStatus,
                                  isPaid
                                      ? const Color(0xFF16A34A)
                                      : const Color(0xFFF59E0B),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            tr(_formatCurrency(p['netSalary'] ?? 0)),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Icon(
                            expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: Color(0xFFE4E4E7)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInlineSection(
                    'Thu nhập',
                    Icons.add_circle,
                    HrmPageChrome.primaryNavy,
                    [
                      _detailRow('Lương cơ bản', p['baseSalary']),
                      _detailRow('Phụ cấp', p['allowances']),
                      _detailRow('Thưởng', p['bonus']),
                      _detailRow('Tăng ca', p['overtimePay']),
                      if (_payslipShowsTravel(p))
                        _detailRow(
                          'Lương đi đường (${_payslipTravelHours(p).toStringAsFixed(1)}h)',
                          p['travelSalary'],
                        ),
                      _detailRow('Tổng thu nhập (Gross)', p['grossSalary']),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInlineSection(
                    'Khấu trừ',
                    Icons.remove_circle,
                    const Color(0xFFEF4444),
                    [
                      _detailRow('BHXH', p['socialInsurance']),
                      _detailRow('BHYT', p['healthInsurance']),
                      _detailRow('BHTN', p['unemploymentInsurance']),
                      _detailRow('Thuế TNCN', p['tax']),
                      _detailRow('Khấu trừ khác', p['deductions']),
                    ],
                  ),
                  if (p['cashTransactionCode']?.toString().isNotEmpty == true) ...[
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(tr('${tr('Phiếu chi: ')}${p['cashTransactionCode']}'),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                  if ((p['notes']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        tr(p['notes'].toString()),
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _showAttendanceSnapshot(p),
                    icon: const Icon(Icons.fact_check_outlined, size: 18),
                    label: Text(tr('Xem bảng chấm công kỳ lương')),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HrmPageChrome.primaryNavy,
                      side: BorderSide(
                          color: HrmPageChrome.primaryNavy.withValues(alpha: 0.4)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusChip(String label, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        tr(label),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildInlineSection(
    String title,
    IconData icon,
    Color color,
    List<Widget> rows,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  tr(title),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          ...rows,
        ],
      ),
    );
  }

  double _payslipTravelHours(Map<String, dynamic> p) {
    final v = p['travelHours'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  bool _payslipShowsTravel(Map<String, dynamic> p) {
    if (_payslipTravelHours(p) <= 0) return false;
    final pay = p['travelSalary'];
    if (pay is num) return pay > 0;
    return (double.tryParse(pay?.toString() ?? '') ?? 0) > 0;
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(tr(label), style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          Text(
            tr(_formatCurrency(value ?? 0)),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Future<void> _showAttendanceSnapshot(Map<String, dynamic> payslip) async {
    final id = payslip['id']?.toString();
    if (id == null || id.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 16),
            Expanded(child: Text(tr('Đang tải bảng chấm công...'))),
          ],
        ),
      ),
    );

    Map<String, dynamic>? snapshotData;
    String? errorMessage;
    try {
      final res = await _apiService.getPayslipAttendanceSnapshot(id);
      if (res['isSuccess'] == true && res['data'] != null) {
        final payload = Map<String, dynamic>.from(res['data'] as Map);
        final inner = payload['data'];
        snapshotData = inner is Map
            ? Map<String, dynamic>.from(inner)
            : payload;
      } else {
        errorMessage =
            res['message']?.toString() ?? 'Chưa có bản chấm công đính kèm';
      }
    } catch (e) {
      errorMessage = 'Lỗi tải dữ liệu: $e';
    }

    if (!mounted) return;
    Navigator.of(context).pop(); // close loading

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month,
                        color: HrmPageChrome.primaryNavy),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(tr('${tr('Chấm công kỳ lương ')}${payslip['month']}/${payslip['year']}'),
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: snapshotData == null
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            tr(errorMessage ??
                                'Phiếu lương này chưa có bản chấm công (chốt trước khi cập nhật tính năng).'),
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ),
                      )
                    : _buildAttendanceSnapshotBody(snapshotData),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _snapshotTravelHours(Map<String, dynamic> summary) {
    final v = summary['travelHours'];
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Widget _buildAttendanceSnapshotBody(Map<String, dynamic> data) {
    final summary = data['summary'] is Map
        ? Map<String, dynamic>.from(data['summary'] as Map)
        : <String, dynamic>{};
    final daily = (data['dailyRecords'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
        [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (summary.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBAE6FD)),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _snapChip('Tổng công', '${summary['workDays'] ?? '-'}'),
                _snapChip('Tăng ca',
                    '${(summary['otTotalHours'] as num?)?.toStringAsFixed(1) ?? '-'}h'),
                _snapChip('Đi trễ',
                    '${summary['lateCount'] ?? 0} lần (${summary['lateMinutes'] ?? 0}p)'),
                _snapChip('Vắng', '${summary['absentDays'] ?? 0} ngày'),
                if (_snapshotTravelHours(summary) > 0)
                  _snapChip(
                    'Đi đường',
                    '${_snapshotTravelHours(summary).toStringAsFixed(1)}h',
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text(tr('Chi tiết theo ngày (${daily.length})'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (daily.isEmpty)
          Text(tr('Không có dòng chấm công'),
              style: TextStyle(color: Colors.grey[600], fontSize: 13))
        else
          ...daily.map((d) => _dailySnapshotTile(d)),
        if (data['attendanceLogs'] is List &&
            (data['attendanceLogs'] as List).isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(tr('${tr('Log chấm công gốc (')}${(data['attendanceLogs'] as List).length})'),
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          ...(data['attendanceLogs'] as List).whereType<Map>().map((raw) {
            final log = Map<String, dynamic>.from(raw);
            final time = parseApiUtcDateTime(log['time']);
            return ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                (log['state'] as num?)?.toInt() == 1
                    ? Icons.logout
                    : Icons.login,
                size: 18,
                color: HrmPageChrome.primaryNavy,
              ),
              title: Text(
                tr(time != null
                    ? DateFormat('dd/MM/yyyy HH:mm').format(time.toLocal())
                    : log['time']?.toString() ?? ''),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                tr('${log['stateLabel'] ?? ''} • ${log['deviceName'] ?? ''}'),
                style: const TextStyle(fontSize: 11),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _snapChip(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr(label), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        Text(tr(value),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }

  Widget _dailySnapshotTile(Map<String, dynamic> d) {
    final shifts = (d['shiftNames'] as List?)?.join(', ') ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(DateFormat('dd/MM/yyyy').format(
                    DateTime.tryParse(d['date']?.toString() ?? '') ??
                        DateTime.now(),
                  )),
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (shifts.isNotEmpty)
                  Text(tr(shifts),
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey[600])),
              ],
            ),
          ),
          Expanded(
            child: Text(
              tr('${d['checkIn'] ?? '--'} → ${d['checkOut'] ?? '--'}'),
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              tr('${(d['workHours'] as num?)?.toStringAsFixed(1) ?? '0'}h • ${d['status'] ?? ''}'),
              style: const TextStyle(fontSize: 11),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'Approved':
        return 'Đã chốt';
      case 'Paid':
        return 'Đã thanh toán';
      case 'PendingApproval':
        return 'Chờ duyệt';
      case 'Draft':
        return 'Nháp';
      case 'Cancelled':
        return 'Đã hủy';
      default:
        return status;
    }
  }

  String _formatCurrency(dynamic amount) {
    try {
      final n = amount is num ? amount : num.tryParse(amount.toString()) ?? 0;
      return '${NumberFormat('#,###', 'vi_VN').format(n)}đ';
    } catch (_) {
      return '0đ';
    }
  }
}
