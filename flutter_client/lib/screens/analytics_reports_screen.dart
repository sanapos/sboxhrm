import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_tr.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';

/// Kiểu tham số kỳ của báo cáo.
enum _PeriodKind { range, month, year, none }

class _ReportSpec {
  final String group;
  final String title;
  final String subtitle;
  final String path;
  final _PeriodKind period;
  final List<String> modules; // cần quyền Xem ít nhất một module
  const _ReportSpec(this.group, this.title, this.subtitle, this.path, this.period, this.modules);
}

const _attendanceModules = ['AttendanceReport', 'AttendanceSummary', 'AttendanceByShift', 'Attendance'];

/// Các báo cáo phân tích có sẵn trên máy chủ nhưng trước đây chưa có màn xem.
const _reports = <_ReportSpec>[
  _ReportSpec('Chấm công', 'Tỷ lệ chuyên cần', 'Theo nhân viên trong tháng', '/api/reports/attendance-analytics/compliance', _PeriodKind.month, _attendanceModules),
  _ReportSpec('Chấm công', 'Vắng không phép', 'Từng ngày vắng không có đơn', '/api/reports/attendance-analytics/absence', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Có lịch nhưng không chấm công', 'Theo ngày xếp lịch', '/api/reports/attendance-analytics/no-show', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Chấm công bất thường', 'Quá sớm, quá muộn, chấm nhiều lần', '/api/reports/attendance-analytics/anomalies', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Công tác / check-in điểm', 'Tổng hợp lượt check-in ngoài', '/api/reports/attendance-analytics/field-summary', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Chấm công', 'Chấm công Mobile / WiFi', 'Mức dùng chấm công điện thoại', '/api/reports/attendance-analytics/mobile-usage', _PeriodKind.range, _attendanceModules),
  _ReportSpec('Nghỉ phép & ca', 'Số ngày phép còn lại', 'Theo nhân viên trong năm', '/api/reports/leave-shift/leave-balance', _PeriodKind.year, ['LeaveReport']),
  _ReportSpec('Nghỉ phép & ca', 'Thời gian duyệt đơn phép', 'Người duyệt nhanh / chậm', '/api/reports/leave-shift/leave-approval-sla', _PeriodKind.range, ['LeaveReport']),
  _ReportSpec('Nghỉ phép & ca', 'Độ phủ ca theo định mức', 'Thiếu / đủ / vượt người mỗi ca', '/api/reports/leave-shift/shift-coverage', _PeriodKind.range, ['LeaveReport', 'WorkSchedule']),
  _ReportSpec('Nghỉ phép & ca', 'Tần suất đổi ca', 'Theo nhân viên', '/api/reports/leave-shift/shift-swaps', _PeriodKind.range, ['LeaveReport']),
  _ReportSpec('Hiệu suất', 'Tổng hợp KPI', 'Theo nhân viên và phòng ban', '/api/reports/performance/kpi-summary', _PeriodKind.month, ['KPI']),
  _ReportSpec('Hiệu suất', 'Sản lượng', 'Theo nhân viên và sản phẩm', '/api/reports/performance/production-output', _PeriodKind.range, ['KPI']),
  _ReportSpec('Hiệu suất', 'Tài sản đang giao', 'Theo trạng thái và người giữ', '/api/reports/performance/asset-assignment', _PeriodKind.none, ['KPI']),
  _ReportSpec('Tổng hợp', 'Báo cáo điều hành tháng', 'Nhân sự, chấm công, chi phí trong tháng', '/api/reports/executive/monthly-summary', _PeriodKind.month, ['Report']),
  _ReportSpec('Tài chính nhân sự', 'Nợ tiền cơm', 'Theo nhân viên', '/api/reports/finance/meal-debt', _PeriodKind.range, ['Meal']),
];

/// Danh sách báo cáo phân tích (lọc theo quyền).
class AnalyticsReportsScreen extends StatelessWidget {
  const AnalyticsReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final perm = context.watch<PermissionProvider>();
    final visible = _reports.where((r) => r.modules.any(perm.canView)).toList();
    final groups = <String, List<_ReportSpec>>{};
    for (final r in visible) {
      groups.putIfAbsent(r.group, () => []).add(r);
    }
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(title: Text(tr('Báo cáo phân tích'))),
      body: visible.isEmpty
          ? Center(child: Text(tr('Không có báo cáo nào bạn được xem')))
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                for (final g in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(tr(g.key),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, color: HrmPageChrome.primaryNavy)),
                  ),
                  for (final r in g.value)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.insert_chart_outlined, color: HrmPageChrome.primaryNavy),
                        title: Text(tr(r.title), style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(tr(r.subtitle)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => _AnalyticsReportViewer(spec: r))),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

/// Nhãn tiếng Việt cho khóa hay gặp; khóa lạ hiển thị dạng tách chữ.
const _labels = <String, String>{
  'employeeCode': 'Mã NV', 'employeeName': 'Nhân viên', 'department': 'Phòng ban',
  'date': 'Ngày', 'scheduledDate': 'Ngày xếp lịch', 'dayOfWeek': 'Thứ', 'from': 'Từ ngày', 'to': 'Đến ngày',
  'shiftName': 'Ca', 'status': 'Trạng thái', 'count': 'Số lượng', 'total': 'Tổng', 'amount': 'Số tiền',
  'totalNoShows': 'Tổng lượt vắng', 'workDays': 'Ngày công', 'scheduledDays': 'Ngày có lịch',
  'presentDays': 'Ngày có mặt', 'absentDays': 'Ngày vắng', 'lateCount': 'Số lần trễ', 'lateMinutes': 'Phút trễ',
  'earlyCount': 'Số lần về sớm', 'earlyMinutes': 'Phút về sớm', 'complianceRate': 'Tỷ lệ chuyên cần (%)',
  'minRequired': 'Tối thiểu', 'maxAllowed': 'Tối đa', 'registered': 'Đã xếp', 'gap': 'Còn thiếu',
  'underCount': 'Số ca thiếu', 'okCount': 'Số ca đạt', 'overCount': 'Số ca vượt',
  'entitled': 'Phép được hưởng', 'used': 'Đã dùng', 'remaining': 'Còn lại', 'pending': 'Chờ duyệt',
  'approverName': 'Người duyệt', 'avgHours': 'TB giờ duyệt', 'score': 'Điểm', 'target': 'Mục tiêu',
  'actual': 'Thực tế', 'productName': 'Sản phẩm', 'quantity': 'Số lượng', 'assetName': 'Tài sản',
  'assetCode': 'Mã tài sản', 'assignedTo': 'Người giữ', 'reason': 'Lý do', 'note': 'Ghi chú',
  'items': 'Chi tiết', 'byEmployee': 'Theo nhân viên', 'byDepartment': 'Theo phòng ban',
  'byProduct': 'Theo sản phẩm', 'byStatus': 'Theo trạng thái', 'assignments': 'Đang giao',
  'topPerformers': 'Dẫn đầu', 'approvers': 'Theo người duyệt', 'debt': 'Còn nợ', 'paid': 'Đã trả',
};

String _label(String key) {
  final k = _labels[key];
  if (k != null) return k;
  final spaced = key.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}');
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

bool _isScalar(dynamic v) => v == null || v is num || v is String || v is bool;

class _AnalyticsReportViewer extends StatefulWidget {
  final _ReportSpec spec;
  const _AnalyticsReportViewer({required this.spec});

  @override
  State<_AnalyticsReportViewer> createState() => _AnalyticsReportViewerState();
}

class _AnalyticsReportViewerState extends State<_AnalyticsReportViewer> {
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  final _num = NumberFormat('#,##0.##', 'vi_VN');
  late DateTime _from;
  late DateTime _to;
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _data = const {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, 1);
    _to = DateTime(now.year, now.month, now.day);
    _load();
  }

  Map<String, String> get _params {
    final iso = DateFormat('yyyy-MM-dd');
    return switch (widget.spec.period) {
      _PeriodKind.range => {'from': iso.format(_from), 'to': iso.format(_to)},
      _PeriodKind.month => {'year': '${_from.year}', 'month': '${_from.month}'},
      _PeriodKind.year => {'year': '${_from.year}'},
      _PeriodKind.none => {},
    };
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getAnalyticsReport(widget.spec.path, _params);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res['isSuccess'] == true && res['data'] is Map) {
        _data = Map<String, dynamic>.from(res['data'] as Map);
      } else {
        _error = res['message']?.toString() ?? tr('Không tải được báo cáo');
      }
    });
  }

  Future<void> _pickPeriod() async {
    if (widget.spec.period == _PeriodKind.range) {
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 60)),
        initialDateRange: DateTimeRange(start: _from, end: _to),
      );
      if (r == null) return;
      _from = r.start;
      _to = r.end;
    } else {
      final d = await showDatePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        initialDate: _from,
        helpText: widget.spec.period == _PeriodKind.year ? tr('Chọn năm (ngày bất kỳ)') : tr('Chọn tháng (ngày bất kỳ)'),
      );
      if (d == null) return;
      _from = d;
    }
    await _load();
  }

  String get _periodLabel => switch (widget.spec.period) {
        _PeriodKind.range => '${_dateFmt.format(_from)} – ${_dateFmt.format(_to)}',
        _PeriodKind.month => 'Tháng ${_from.month}/${_from.year}',
        _PeriodKind.year => 'Năm ${_from.year}',
        _PeriodKind.none => 'Hiện tại',
      };

  Future<void> _excel() async {
    final res = await _api.downloadAnalyticsReportExcel(widget.spec.path, _params);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
          title: 'Không xuất được Excel', message: res['message']?.toString() ?? '');
      return;
    }
    await saveAndOpenFileBytes(
      List<int>.from(res['data'] as List),
      '${widget.spec.title.replaceAll(' ', '_')}.xlsx',
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  }

  String _fmt(String key, dynamic v) {
    if (v == null) return '';
    if (v is bool) return v ? tr('Có') : tr('Không');
    if (v is num) return _num.format(v);
    final s = v.toString();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(s)) {
      final d = DateTime.tryParse(s);
      if (d != null) {
        return d.hour == 0 && d.minute == 0
            ? _dateFmt.format(d)
            : DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal());
      }
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final scalars = _data.entries.where((e) => _isScalar(e.value) && e.key != 'from' && e.key != 'to').toList();
    final blocks = _data.entries.where((e) => e.value is Map).toList();
    final lists = _data.entries.where((e) => e.value is List && (e.value as List).isNotEmpty).toList();
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: Text(tr(widget.spec.title)),
        actions: [
          IconButton(
            tooltip: tr('Xuất Excel'),
            onPressed: _loading || _error != null ? null : _excel,
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(tooltip: tr('Tải lại'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          if (widget.spec.period != _PeriodKind.none)
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _pickPeriod,
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(tr(_periodLabel)),
              ),
            ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else ...[
            if (scalars.isNotEmpty) _kpis(scalars),
            for (final b in blocks)
              _kpis((b.value as Map).entries
                  .where((e) => _isScalar(e.value))
                  .map((e) => MapEntry('${e.key}', e.value))
                  .toList(), title: _label(b.key)),
            if (lists.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    prefixIcon: const Icon(Icons.search),
                    hintText: tr('Lọc theo tên, mã, phòng ban...'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            for (final l in lists) _table(l.key, (l.value as List).whereType<Map>().toList()),
            if (scalars.isEmpty && blocks.isEmpty && lists.isEmpty)
              Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(tr('Không có dữ liệu trong kỳ')))),
          ],
        ],
      ),
    );
  }

  Widget _kpis(List<MapEntry<String, dynamic>> items, {String? title}) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              Wrap(
                spacing: 18,
                runSpacing: 8,
                children: [
                  for (final e in items)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(tr(_label(e.key)), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        Text(_fmt(e.key, e.value),
                            style: const TextStyle(fontWeight: FontWeight.w800, color: HrmPageChrome.primaryNavy)),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _table(String key, List<Map> rows) {
    final cols = <String>[];
    for (final r in rows.take(20)) {
      for (final e in r.entries) {
        final k = '${e.key}';
        if (_isScalar(e.value) && !cols.contains(k) && !k.toLowerCase().endsWith('id')) cols.add(k);
      }
    }
    final visible = _search.isEmpty
        ? rows
        : rows.where((r) => r.values.any((v) => '$v'.toLowerCase().contains(_search))).toList();
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
              child: Text('${tr(_label(key))} (${visible.length})',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 32,
                dataRowMaxHeight: 48,
                columnSpacing: 18,
                columns: [for (final c in cols) DataColumn(label: Text(tr(_label(c))))],
                rows: [
                  for (final r in visible.take(500))
                    DataRow(cells: [for (final c in cols) DataCell(Text(_fmt(c, r[c])))]),
                ],
              ),
            ),
            if (visible.length > 500)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(tr('Hiển thị 500 / ${visible.length} dòng — xuất Excel để xem đủ.')),
              ),
          ],
        ),
      ),
    );
  }
}
