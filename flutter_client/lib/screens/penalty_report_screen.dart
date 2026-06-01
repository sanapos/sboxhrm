import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../widgets/hrm_page_chrome.dart';
import '../utils/report_screen_helpers.dart';

const _pRowH = 54.0;
const _pHdrH = 44.0;
const _pStickyW = 164.0;
const _pTheme = Color(0xFFEC4899);

class PenaltyReportScreen extends StatefulWidget {
  const PenaltyReportScreen({super.key});
  @override
  State<PenaltyReportScreen> createState() => _PenaltyReportScreenState();
}

class _PenaltyReportScreenState extends State<PenaltyReportScreen> {
  final ApiService _api = ApiService();
  final _fmtDate = DateFormat('dd/MM/yyyy');
  final _fmtMoney = NumberFormat('#,##0', 'vi_VN');

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  String? _statusFilter;
  bool _loading = false;
  List<Map<String, dynamic>> _tickets = [];
  // ignore: unused_field
  Map<String, dynamic> _stats = {};
  String _empSearch = '';
  String? _selectedBranchId;
  final _branchFilter = ReportBranchFilter();

  List<Map<String, dynamic>> get _filtered {
    var result = _tickets;
    if (_selectedBranchId != null) {
      final ids = _branchFilter.userIdsForBranch(_selectedBranchId);
      if (ids.isEmpty) return [];
      result = result
          .where((t) => ids.contains(t['employeeUserId']?.toString()))
          .toList();
    }
    if (_empSearch.isEmpty) return result;
    return result
        .where((t) => (t['employeeName']?.toString() ?? '')
            .toLowerCase()
            .contains(_empSearch.toLowerCase()))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _branchFilter.loadBranches(_api).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<String> get _empSuggestions => _tickets
      .map((t) => t['employeeName']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  /// Safe parse: handles int, num, String, null — no TypeError
  static int _safeInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? -1;
  }

  static double _safeDouble(dynamic v) {
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0.0;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final r = await _api.getPenaltyTickets(
          fromDate: _from, toDate: _to, status: _statusFilter, pageSize: 500);
      final list = <Map<String, dynamic>>[];
      if (r['isSuccess'] == true) {
        final data = r['data'];
        final items = data is List
            ? data
            : (data is Map && data['items'] is List ? data['items'] : []);
        for (final item in items) {
          if (item is Map) list.add(Map<String, dynamic>.from(item));
        }
      }
      setState(() => _tickets = list);
    } catch (e) {
      debugPrint('penalty_report _load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // Load stats separately — failure won't block main data
    try {
      final s = await _api.getPenaltyTicketStats(
        fromDate: DateFormat('yyyy-MM-dd').format(_from),
        toDate: DateFormat('yyyy-MM-dd').format(_to),
      );
      if (mounted && s['isSuccess'] == true && s['data'] is Map) {
        setState(() => _stats = Map<String, dynamic>.from(s['data'] as Map));
      }
    } catch (_) {}
  }

  Future<void> _exportExcel() async {
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final t = data[i];
      final date =
          t['date'] != null ? DateTime.tryParse(t['date'].toString()) : null;
      rows.add([
        i + 1,
        t['employeeName']?.toString() ?? '',
        t['departmentName']?.toString() ?? '',
        _penaltyTypeLabel(t['penaltyTypeName'] ?? t['type']),
        date != null ? _fmtDate.format(date) : '',
        _safeDouble(t['amount']),
        _statusLabel(t['status']),
        t['note']?.toString() ?? t['reason']?.toString() ?? '',
      ]);
    }
    await ClientExcelExport.export(
      context: context,
      title: 'Báo cáo phạt',
      sheetName: 'Bao cao phat',
      filePrefix: 'BaoCaoPhat',
      headers: const [
        'STT',
        'Nhân viên',
        'Phòng ban',
        'Loại phạt',
        'Ngày',
        'Số tiền (đ)',
        'Trạng thái',
        'Ghi chú',
      ],
      rows: rows,
      periodLabel:
          '${_fmtDate.format(_from)} – ${_fmtDate.format(_to)}',
      filterLabel: _selectedBranchId != null ? 'Theo chi nhánh' : null,
    );
  }

  String _statusLabel(dynamic s) {
    switch (_safeInt(s)) {
      case 0:
        return 'Chờ duyệt';
      case 1:
        return 'Đã duyệt';
      case 2:
        return 'Đã hủy';
      default:
        final str = s?.toString().toLowerCase() ?? '';
        if (str == 'pending') return 'Chờ duyệt';
        if (str == 'approved') return 'Đã duyệt';
        if (str == 'cancelled' || str == 'canceled') return 'Đã hủy';
        if (str == 'rejected') return 'Từ chối';
        return '';
    }
  }

  String _penaltyTypeLabel(dynamic t) {
    if (t == null || t.toString().trim().isEmpty) return '—';
    switch (t.toString().toLowerCase().trim()) {
      case 'late':
        return 'Đi muộn';
      case 'absent':
        return 'Vắng mặt';
      case 'earlyleave':
      case 'earlycheck':
      case 'early':
        return 'Về sớm';
      case 'disciplinary':
        return 'Kỷ luật';
      case 'financial':
      case 'financialpenalty':
        return 'Phạt tiền';
      case 'warning':
        return 'Cảnh báo';
      case 'misconduct':
        return 'Vi phạm';
      case 'performance':
        return 'Hiệu suất kém';
      default:
        return t.toString();
    }
  }

  Color _statusColor(dynamic s) {
    switch (_safeInt(s)) {
      case 0:
        return Colors.orange;
      case 1:
        return const Color(0xFF16A34A);
      case 2:
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Báo cáo phạt'),
        backgroundColor: _pTheme,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (Provider.of<PermissionProvider>(context, listen: false)
              .canExport('PenaltyReport'))
            IconButton(
                icon: const Icon(Icons.file_download_outlined),
                tooltip: 'Xuất Excel',
                onPressed: _exportExcel),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFilters(),
                _buildSummary(),
                if (_loading)
                  const Padding(
                    padding: EdgeInsets.all(48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _buildTable(),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ─── FILTERS ───────────────────────────────────────────────
  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(children: [
        ReportDateRangeFilterBar(
          from: _from,
          to: _to,
          preset: _datePreset,
          onChanged: (f, t, p) => setState(() {
            _from = f;
            _to = t;
            _datePreset = p;
          }),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _statusDrop()),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: FilledButton.icon(
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Tìm', style: TextStyle(fontSize: 13)),
              style: FilledButton.styleFrom(
                backgroundColor: HrmPageChrome.primaryNavy,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                minimumSize: const Size(0, 40),
              ),
              onPressed: _load,
            ),
          ),
        ]),
        if (_branchFilter.branches.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Row(children: [
              const Icon(Icons.account_tree_outlined,
                  size: 16, color: Color(0xFF6B7280)),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _selectedBranchId,
                    isExpanded: true,
                    isDense: true,
                    style:
                        const TextStyle(fontSize: 13, color: Color(0xFF111827)),
                    icon: const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: Color(0xFF9CA3AF)),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tất cả chi nhánh',
                              style: TextStyle(fontSize: 13))),
                      ..._branchFilter.branches.map((b) => DropdownMenuItem<String?>(
                          value: b['id']?.toString(),
                          child: Text(b['name']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)))),
                    ],
                    onChanged: (v) async {
                      if (v != null) await _branchFilter.ensureEmployees(_api);
                      if (mounted) setState(() => _selectedBranchId = v);
                    },
                  ),
                ),
              ),
              if (_selectedBranchId != null)
                InkWell(
                  onTap: () => setState(() => _selectedBranchId = null),
                  child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.close,
                          size: 14, color: Color(0xFF9CA3AF))),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 6),
        _buildEmpSearch('Lọc theo tên nhân viên...'),
      ]),
    );
  }

  Widget _buildEmpSearch(String hint) {
    final suggestions = _empSuggestions;
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        if (suggestions.isEmpty) return const Iterable<String>.empty();
        if (textEditingValue.text.isEmpty) return suggestions;
        final q = textEditingValue.text.toLowerCase();
        return suggestions.where((s) => s.toLowerCase().contains(q));
      },
      onSelected: (selection) => setState(() => _empSearch = selection),
      fieldViewBuilder: (context, fieldCtrl, focusNode, _) {
        return Container(
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: fieldCtrl,
            focusNode: focusNode,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              prefixIcon: const Icon(Icons.person_search_outlined,
                  size: 18, color: Color(0xFF9CA3AF)),
              suffixIcon: _empSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        fieldCtrl.clear();
                        setState(() => _empSearch = '');
                      })
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 4),
              border: InputBorder.none,
              isDense: true,
            ),
            onChanged: (v) => setState(() => _empSearch = v),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                shrinkWrap: true,
                children: options
                    .map((option) => InkWell(
                          onTap: () => onSelected(option),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            child: Row(children: [
                              const Icon(Icons.person_outline,
                                  size: 16, color: Color(0xFF6B7280)),
                              const SizedBox(width: 8),
                              Flexible(
                                  child: Text(option,
                                      style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF111827)))),
                            ]),
                          ),
                        ))
                    .toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _statusDrop() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD1D5DB)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _statusFilter,
          isExpanded: true,
          hint: const Text('Trạng thái',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 18, color: Color(0xFF9CA3AF)),
          items: const [
            DropdownMenuItem(value: null, child: Text('Tất cả')),
            DropdownMenuItem(value: '0', child: Text('Chờ duyệt')),
            DropdownMenuItem(value: '1', child: Text('Đã duyệt')),
            DropdownMenuItem(value: '2', child: Text('Đã hủy')),
          ],
          onChanged: (v) => setState(() => _statusFilter = v),
        ),
      ),
    );
  }

  // ─── SUMMARY ───────────────────────────────────────────────
  Widget _buildSummary() {
    final f = _filtered;
    final total = f.length;
    final approved = f.where((t) => _safeInt(t['status']) == 1).length;
    final totalAmt = f.fold(0.0, (s, t) => s + _safeDouble(t['amount']));
    final approvedAmt = f
        .where((t) => _safeInt(t['status']) == 1)
        .fold(0.0, (s, t) => s + _safeDouble(t['amount']));
    return Container(
      height: 78,
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _sumCard('Tổng phiếu', total.toString(), Icons.receipt_long, _pTheme),
          _sumCard('Đã duyệt', approved.toString(), Icons.check_circle_outline,
              const Color(0xFF16A34A)),
          _sumCard('Tổng tiền phạt', '${_fmtMoney.format(totalAmt)}đ',
              Icons.money_off_outlined, Colors.orange),
          _sumCard('Tiền đã duyệt', '${_fmtMoney.format(approvedAmt)}đ',
              Icons.payments_outlined, Colors.red),
        ],
      ),
    );
  }

  Widget _sumCard(String title, String value, IconData icon, Color color) {
    return Container(
      width: 148,
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(children: [
        Icon(icon, color: color, size: 26),
        const SizedBox(width: 8),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Text(title,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
                  overflow: TextOverflow.ellipsis),
              Text(value,
                  style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.bold, color: color),
                  overflow: TextOverflow.ellipsis),
            ])),
      ]),
    );
  }

  // ─── TABLE ─────────────────────────────────────────────────
  Widget _buildTable() {
    final rows = _filtered;
    if (rows.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text('Không có dữ liệu',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
      ]));
    }

    const hdrBg = Color(0xFFFCE7F3);
    const evenBg = Colors.white;
    const oddBg = Color(0xFFF9FAFB);

    Widget hCell(String t, double w) => Container(
          width: w,
          height: _pHdrH,
          color: hdrBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: Color(0xFF374151))),
        );

    Widget dCell(String t, double w, int i, {Color? textColor}) => Container(
          width: w,
          height: _pRowH,
          color: i.isEven ? evenBg : oddBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12.5, color: textColor ?? const Color(0xFF374151)),
              overflow: TextOverflow.ellipsis),
        );

    Widget sCell(dynamic s, double w, int i) => Container(
          width: w,
          height: _pRowH,
          color: i.isEven ? evenBg : oddBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: _statusColor(s).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _statusColor(s).withValues(alpha: 0.4)),
            ),
            child: Text(_statusLabel(s),
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _statusColor(s))),
          ),
        );

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // ═══ STICKY COLUMN ═══
            Container(
              width: _pStickyW,
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(2, 0))
                ],
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: _pStickyW,
                      height: _pHdrH,
                      color: hdrBg,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Text('Nhân viên',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF374151))),
                    ),
                    ...List.generate(rows.length, (i) {
                      final t = rows[i];
                      final name = t['employeeName']?.toString() ??
                          t['employee']?.toString() ??
                          '—';
                      final dept = t['departmentName']?.toString() ?? '';
                      return Container(
                        width: _pStickyW,
                        height: _pRowH,
                        color: i.isEven ? evenBg : oddBg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827)),
                                  overflow: TextOverflow.ellipsis),
                              if (dept.isNotEmpty)
                                Text(dept,
                                    style: const TextStyle(
                                        fontSize: 11, color: Color(0xFF6B7280)),
                                    overflow: TextOverflow.ellipsis),
                            ]),
                      );
                    }),
                  ]),
            ),
            // ═══ SCROLLABLE COLUMNS ═══
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        hCell('Loại phạt', 140),
                        hCell('Ngày', 104),
                        hCell('Số tiền', 120),
                        hCell('Ghi chú', 160),
                        hCell('Trạng thái', 112),
                      ]),
                      ...List.generate(rows.length, (i) {
                        final t = rows[i];
                        final date = t['date'] != null
                            ? DateTime.tryParse(t['date'].toString())
                            : null;
                        final amt = _safeDouble(t['amount']);
                        return Row(children: [
                          dCell(
                              _penaltyTypeLabel(
                                  t['penaltyTypeName'] ?? t['type']),
                              140,
                              i),
                          dCell(date != null ? _fmtDate.format(date) : '—', 104,
                              i),
                          dCell('${_fmtMoney.format(amt)}đ', 120, i,
                              textColor: _pTheme),
                          dCell(
                              t['note']?.toString() ??
                                  t['reason']?.toString() ??
                                  '',
                              160,
                              i),
                          sCell(t['status'], 112, i),
                        ]);
                      }),
                    ]),
              ),
            ),
          ],
        ),
    );
  }
}
