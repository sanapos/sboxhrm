import 'package:flutter/material.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../utils/attendance_load_utils.dart';
import '../utils/report_screen_helpers.dart';
import '../providers/permission_provider.dart';

const _lRowH = 54.0;
const _lHdrH = 44.0;
const _lStickyW = 154.0;
const _lTheme = Color(0xFF0284C7);

class LeaveReportScreen extends StatefulWidget {
  const LeaveReportScreen({super.key});
  @override
  State<LeaveReportScreen> createState() => _LeaveReportScreenState();
}

class _LeaveReportScreenState extends State<LeaveReportScreen> {
  final ApiService _api = ApiService();
  final _fmtDate = DateFormat('dd/MM/yyyy');
  final _fmtDateApi = DateFormat('yyyy-MM-dd');

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  int? _statusFilter; // 0=pending,1=approved,2=rejected,3=cancelled
  bool _loading = false;
  List<Map<String, dynamic>> _leaves = [];
  String _empSearch = '';
  String? _selectedBranchId;
  final _branchFilter = ReportBranchFilter();

  List<Map<String, dynamic>> get _filtered {
    Set<String>? branchIds;
    if (_selectedBranchId != null) {
      branchIds = _branchFilter.userIdsForBranch(_selectedBranchId);
      if (branchIds.isEmpty) return [];
    }
    return _leaves.where((l) {
      final empKey = l['employeeUserId']?.toString() ??
          l['employeeId']?.toString() ??
          '';
      if (branchIds != null && !branchIds.contains(empKey)) {
        return false;
      }
      if (_empSearch.isNotEmpty &&
          !(l['employeeName']?.toString() ?? '')
              .toLowerCase()
              .contains(_empSearch.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
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

  List<String> get _empSuggestions => _leaves
      .map((l) => l['employeeName']?.toString() ?? '')
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await loadLeavesForPeriod(
        _api,
        fromDate: _fmtDateApi.format(_from),
        toDate: _fmtDateApi.format(_to),
        status: _statusFilter?.toString(),
        pageSize: 500,
      );
      setState(() {
        _leaves = items
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
    } catch (e) {
      debugPrint('leave_report _load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportExcel() async {
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final l = data[i];
      final startDate = l['startDate'] != null
          ? DateTime.tryParse(l['startDate'].toString())
          : null;
      final endDate =
          l['endDate'] != null ? DateTime.tryParse(l['endDate'].toString()) : null;
      final days = (startDate != null && endDate != null)
          ? endDate.difference(startDate).inDays + 1
          : 1;
      rows.add([
        i + 1,
        l['employeeName']?.toString() ?? '',
        _leaveTypeName(l['type'] ?? l['leaveType']),
        startDate != null ? _fmtDate.format(startDate) : '',
        endDate != null ? _fmtDate.format(endDate) : '',
        days,
        l['reason']?.toString() ?? '',
        _statusLabel(_normalizeStatus(l['status'])),
        l['approvedByName']?.toString() ?? '',
      ]);
    }
    await ClientExcelExport.export(
      context: context,
      title: 'Báo cáo nghỉ phép',
      sheetName: 'Bao cao nghi phep',
      filePrefix: 'BaoCaoNghiPhep',
      headers: const [
        'STT',
        'Nhân viên',
        'Loại phép',
        'Từ ngày',
        'Đến ngày',
        'Số ngày',
        'Lý do',
        'Trạng thái',
        'Người duyệt',
      ],
      rows: rows,
      periodLabel: '${_fmtDate.format(_from)} – ${_fmtDate.format(_to)}',
    );
  }

  int _normalizeStatus(dynamic s) {
    if (s == null) return 0;
    if (s is int) return s;
    final str = s.toString().toLowerCase();
    if (str == '0' || str == 'pending') return 0;
    if (str == '1' || str == 'approved') return 1;
    if (str == '2' || str == 'rejected') return 2;
    if (str == '3' || str == 'cancelled') return 3;
    return int.tryParse(str) ?? 0;
  }

  String _statusLabel(int s) {
    switch (s) {
      case 0:
        return 'Chờ duyệt';
      case 1:
        return 'Đã duyệt';
      case 2:
        return 'Từ chối';
      case 3:
        return 'Đã hủy';
      default:
        return 'Không rõ';
    }
  }

  Color _statusColor(int s) {
    switch (s) {
      case 0:
        return Colors.orange;
      case 1:
        return const Color(0xFF16A34A);
      case 2:
        return const Color(0xFFDC2626);
      case 3:
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  String _leaveTypeName(dynamic t) {
    switch (t?.toString().toLowerCase()) {
      case 'annualleave':
        return 'Phép năm';
      case 'holiday':
        return 'Nghỉ lễ';
      case 'personalpaid':
        return 'Phép có lương';
      case 'personalunpaid':
        return 'Phép không lương';
      case 'sickleave':
        return 'Nghỉ ốm';
      case 'maternityleave':
        return 'Thai sản';
      case 'compensatoryleave':
        return 'Nghỉ bù';
      default:
        return t?.toString() ?? '—';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: const Text('Báo cáo nghỉ phép'),
        backgroundColor: _lTheme,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (Provider.of<PermissionProvider>(context, listen: false)
              .canExport('LeaveReport'))
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

  Widget _buildFilters() {
    final hasActiveFilters = _statusFilter != null ||
        _selectedBranchId != null ||
        _empSearch.isNotEmpty;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReportDateRangeFilterBar(
            from: _from,
            to: _to,
            preset: _datePreset,
            onChanged: (f, t, p) {
              setState(() {
                _from = f;
                _to = t;
                _datePreset = p;
              });
              _load();
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
          _statusDrop(),
          SizedBox(
              width: 200,
              child: _buildEmpSearch('T\u00ecm nh\u00e2n vi\u00ean...')),
          if (_branchFilter.branches.isNotEmpty)
            SizedBox(
              width: 170,
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFD1D5DB)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    key: const ValueKey('branch_\$_selectedBranchId'),
                    value: _selectedBranchId,
                    isExpanded: true,
                    hint: const Text('Chi nh\u00e1nh',
                        style:
                            TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
                    style:
                        const TextStyle(fontSize: 12, color: Color(0xFF111827)),
                    icon: const Icon(Icons.keyboard_arrow_down,
                        size: 18, color: Color(0xFF9CA3AF)),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('T\u1ea5t c\u1ea3 CN')),
                      ..._branchFilter.branches.map((b) => DropdownMenuItem<String?>(
                          value: b['id']?.toString(),
                          child: Text(b['name']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) async {
                      if (v != null) await _branchFilter.ensureEmployees(_api);
                      if (mounted) setState(() => _selectedBranchId = v);
                    },
                  ),
                ),
              ),
            ),
          if (hasActiveFilters)
            SizedBox(
              height: 40,
              child: TextButton.icon(
                icon: const Icon(Icons.filter_alt_off, size: 15),
                label: const Text('X\u00f3a l\u1ecdc',
                    style: TextStyle(fontSize: 12)),
                onPressed: () => setState(() {
                  _statusFilter = null;
                  _selectedBranchId = null;
                  _empSearch = '';
                }),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
            ],
          ),
        ],
      ),
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _statusFilter,
          isExpanded: true,
          hint: const Text('Trạng thái',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 18, color: Color(0xFF9CA3AF)),
          items: const [
            DropdownMenuItem(value: null, child: Text('Tất cả')),
            DropdownMenuItem(value: 0, child: Text('Chờ duyệt')),
            DropdownMenuItem(value: 1, child: Text('Đã duyệt')),
            DropdownMenuItem(value: 2, child: Text('Từ chối')),
            DropdownMenuItem(value: 3, child: Text('Đã hủy')),
          ],
          onChanged: (v) {
            setState(() => _statusFilter = v);
            _load();
          },
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final f = _filtered;
    final pending = f.where((l) => _normalizeStatus(l['status']) == 0).length;
    final approved = f.where((l) => _normalizeStatus(l['status']) == 1).length;
    final totalDays = f.fold(0.0, (s, l) {
      try {
        final start = DateTime.parse(l['startDate'].toString());
        final end = DateTime.parse(l['endDate'].toString());
        return s + end.difference(start).inDays + 1;
      } catch (_) {
        return s + 1;
      }
    });
    return Container(
      height: 78,
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _sumCard('Tổng đơn', f.length.toString(), Icons.description_outlined,
              Colors.blueGrey),
          _sumCard('Chờ duyệt', pending.toString(), Icons.hourglass_empty,
              Colors.orange),
          _sumCard('Đã duyệt', approved.toString(), Icons.check_circle_outline,
              const Color(0xFF16A34A)),
          _sumCard('Tổng ngày nghỉ', '${totalDays.toInt()} ngày',
              Icons.event_busy, _lTheme),
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

    const hdrBg = Color(0xFFE0F2FE);
    const evenBg = Colors.white;
    const oddBg = Color(0xFFF9FAFB);

    Widget hCell(String t, double w) => Container(
          width: w,
          height: _lHdrH,
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
          height: _lRowH,
          color: i.isEven ? evenBg : oddBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12, color: textColor ?? const Color(0xFF374151)),
              overflow: TextOverflow.ellipsis),
        );

    Widget sCell(int s, double w, int i) => Container(
          width: w,
          height: _lRowH,
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
            // ═══ STICKY: Nhân viên ═══
            Container(
              width: _lStickyW,
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
                      width: _lStickyW,
                      height: _lHdrH,
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
                      final l = rows[i];
                      final name = l['employeeName']?.toString() ?? '—';
                      return Container(
                        width: _lStickyW,
                        height: _lRowH,
                        color: i.isEven ? evenBg : oddBg,
                        alignment: Alignment.centerLeft,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(name,
                            style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827)),
                            overflow: TextOverflow.ellipsis),
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
                        hCell('Loại phép', 120),
                        hCell('Từ ngày', 104),
                        hCell('Đến ngày', 104),
                        hCell('Số ngày', 80),
                        hCell('Lý do', 170),
                        hCell('Trạng thái', 112),
                      ]),
                      ...List.generate(rows.length, (i) {
                        final l = rows[i];
                        final startDate = l['startDate'] != null
                            ? DateTime.tryParse(l['startDate'].toString())
                            : null;
                        final endDate = l['endDate'] != null
                            ? DateTime.tryParse(l['endDate'].toString())
                            : null;
                        final days = (startDate != null && endDate != null)
                            ? endDate.difference(startDate).inDays + 1
                            : 1;
                        final status = _normalizeStatus(l['status']);
                        return Row(children: [
                          dCell(_leaveTypeName(l['type'] ?? l['leaveType']),
                              120, i),
                          dCell(
                              startDate != null
                                  ? _fmtDate.format(startDate)
                                  : '—',
                              104,
                              i),
                          dCell(
                              endDate != null ? _fmtDate.format(endDate) : '—',
                              104,
                              i),
                          dCell('$days ngày', 80, i, textColor: _lTheme),
                          dCell(l['reason']?.toString() ?? '', 170, i),
                          sCell(status, 112, i),
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
