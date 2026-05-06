import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../utils/file_saver.dart' as file_saver;
import '../widgets/notification_overlay.dart';
import '../providers/permission_provider.dart';
import 'package:excel/excel.dart' as excel_lib;

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
  int? _statusFilter; // 0=pending,1=approved,2=rejected,3=cancelled
  bool _loading = false;
  List<Map<String, dynamic>> _leaves = [];
  String _empSearch = '';

  List<Map<String, dynamic>> get _filtered => _empSearch.isEmpty
      ? _leaves
      : _leaves
          .where((l) => (l['employeeName']?.toString() ?? '')
              .toLowerCase()
              .contains(_empSearch.toLowerCase()))
          .toList();

  @override
  void initState() {
    super.initState();
    _load();
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
      final result = await _api.getAllLeaves(
        fromDate: _fmtDateApi.format(_from),
        toDate: _fmtDateApi.format(_to),
        status: _statusFilter?.toString(),
        pageSize: 500,
      );
      final list = <Map<String, dynamic>>[];
      if (result['isSuccess'] == true) {
        final data = result['data'];
        final items = data is List
            ? data
            : (data is Map && data['items'] is List ? data['items'] : []);
        for (final item in items) {
          if (item is Map) list.add(Map<String, dynamic>.from(item));
        }
      }
      setState(() => _leaves = list);
    } catch (e) {
      debugPrint('leave_report _load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_leaves.isEmpty) {
      NotificationOverlayManager()
          .showError(title: 'Thông báo', message: 'Không có dữ liệu để xuất');
      return;
    }
    try {
      final wb = excel_lib.Excel.createExcel();
      final sh = wb['Báo cáo nghỉ phép'];
      wb.delete('Sheet1');
      sh.appendRow([
        'STT',
        'Nhân viên',
        'Loại phép',
        'Từ ngày',
        'Đến ngày',
        'Số ngày',
        'Lý do',
        'Trạng thái',
        'Người duyệt'
      ].map((h) => excel_lib.TextCellValue(h)).toList());
      for (int i = 0; i < _leaves.length; i++) {
        final l = _leaves[i];
        final startDate = l['startDate'] != null
            ? DateTime.tryParse(l['startDate'].toString())
            : null;
        final endDate = l['endDate'] != null
            ? DateTime.tryParse(l['endDate'].toString())
            : null;
        final days = (startDate != null && endDate != null)
            ? endDate.difference(startDate).inDays + 1
            : 1;
        sh.appendRow([
          excel_lib.IntCellValue(i + 1),
          excel_lib.TextCellValue(l['employeeName']?.toString() ?? ''),
          excel_lib.TextCellValue(_leaveTypeName(l['type'] ?? l['leaveType'])),
          excel_lib.TextCellValue(
              startDate != null ? _fmtDate.format(startDate) : ''),
          excel_lib.TextCellValue(
              endDate != null ? _fmtDate.format(endDate) : ''),
          excel_lib.IntCellValue(days),
          excel_lib.TextCellValue(l['reason']?.toString() ?? ''),
          excel_lib.TextCellValue(_statusLabel(_normalizeStatus(l['status']))),
          excel_lib.TextCellValue(l['approvedByName']?.toString() ?? ''),
        ]);
      }
      final bytes = wb.encode();
      if (bytes != null) {
        final fn =
            'BaoCaoNghiPhep_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
        await file_saver.saveFileBytes(bytes, fn,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (mounted) {
          NotificationOverlayManager()
              .showSuccess(title: 'Xuất Excel', message: 'Đã xuất: $fn');
        }
      }
    } catch (e) {
      if (mounted) {
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Không thể xuất Excel: $e');
      }
    }
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

  Future<void> _pickFrom() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _from,
        firstDate: DateTime(2020),
        lastDate: _to);
    if (d != null) setState(() => _from = d);
  }

  Future<void> _pickTo() async {
    final d = await showDatePicker(
        context: context,
        initialDate: _to,
        firstDate: _from,
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (d != null) setState(() => _to = d);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
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
        _buildFilters(),
        _buildSummary(),
        Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _buildTable()),
      ]),
    );
  }

  Widget _buildFilters() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(children: [
        Row(children: [
          Expanded(child: _DateBtn('Từ ngày', _from, _pickFrom)),
          const SizedBox(width: 8),
          Expanded(child: _DateBtn('Đến ngày', _to, _pickTo)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: _StatusDrop()),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Tìm', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _lTheme,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                minimumSize: const Size(0, 40),
              ),
              onPressed: _load,
            ),
          ),
        ]),
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

  Widget _DateBtn(String label, DateTime val, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          const Icon(Icons.calendar_today_outlined,
              size: 14, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 6),
          Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xFF9CA3AF), height: 1.1)),
                Text(_fmtDate.format(val),
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.2)),
              ])),
        ]),
      ),
    );
  }

  Widget _StatusDrop() {
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
          onChanged: (v) => setState(() => _statusFilter = v),
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
          _SumCard('Tổng đơn', f.length.toString(), Icons.description_outlined,
              Colors.blueGrey),
          _SumCard('Chờ duyệt', pending.toString(), Icons.hourglass_empty,
              Colors.orange),
          _SumCard('Đã duyệt', approved.toString(), Icons.check_circle_outline,
              const Color(0xFF16A34A)),
          _SumCard('Tổng ngày nghỉ', '${totalDays.toInt()} ngày',
              Icons.event_busy, _lTheme),
        ],
      ),
    );
  }

  Widget _SumCard(String title, String value, IconData icon, Color color) {
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
      child: SingleChildScrollView(
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
      ),
    );
  }
}
