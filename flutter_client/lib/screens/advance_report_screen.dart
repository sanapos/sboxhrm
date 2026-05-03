import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../models/hrm.dart';
import '../utils/file_saver.dart' as file_saver;
import '../widgets/notification_overlay.dart';
import 'package:excel/excel.dart' as excel_lib;

const _aRowH = 54.0;
const _aHdrH = 44.0;
const _aStickyW = 164.0;
const _aTheme = Color(0xFFF59E0B);

class AdvanceReportScreen extends StatefulWidget {
  const AdvanceReportScreen({super.key});
  @override
  State<AdvanceReportScreen> createState() => _AdvanceReportScreenState();
}

class _AdvanceReportScreenState extends State<AdvanceReportScreen> {
  final ApiService _api = ApiService();
  final _fmtDate = DateFormat('dd/MM/yyyy');
  final _fmtMoney = NumberFormat('#,##0', 'vi_VN');

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  AdvanceRequestStatus? _statusFilter;
  bool _loading = false;
  List<AdvanceRequest> _requests = [];
  String _empSearch = '';

  List<AdvanceRequest> get _filtered => _empSearch.isEmpty
      ? _requests
      : _requests
          .where((r) =>
              r.employeeName.toLowerCase().contains(_empSearch.toLowerCase()))
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

  List<String> get _empSuggestions => _requests
      .map((r) => r.employeeName)
      .where((n) => n.isNotEmpty)
      .toSet()
      .toList()
    ..sort();

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _api.getAdvanceRequests(
        fromDate: _from,
        toDate: _to,
        status: _statusFilter?.index,
        pageSize: 500,
      );
      final list = <AdvanceRequest>[];
      if (result['isSuccess'] == true) {
        final data = result['data'];
        final items = data is List
            ? data
            : (data is Map && data['items'] is List ? data['items'] : []);
        for (final item in items) {
          try {
            list.add(AdvanceRequest.fromJson(
                Map<String, dynamic>.from(item as Map)));
          } catch (_) {}
        }
      }
      setState(() => _requests = list);
    } catch (e) {
      debugPrint('advance_report _load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_requests.isEmpty) {
      NotificationOverlayManager()
          .showError(title: 'Thông báo', message: 'Không có dữ liệu để xuất');
      return;
    }
    try {
      final wb = excel_lib.Excel.createExcel();
      final sh = wb['Báo cáo ứng lương'];
      wb.delete('Sheet1');
      sh.appendRow([
        'STT',
        'Nhân viên',
        'Mã NV',
        'Tháng/Năm',
        'Ngày tạo',
        'Số tiền (đ)',
        'Lý do',
        'Trạng thái',
        'Người duyệt',
        'Ngày duyệt'
      ].map((h) => excel_lib.TextCellValue(h)).toList());
      for (int i = 0; i < _requests.length; i++) {
        final r = _requests[i];
        sh.appendRow([
          excel_lib.IntCellValue(i + 1),
          excel_lib.TextCellValue(r.employeeName),
          excel_lib.TextCellValue(r.employeeCode),
          excel_lib.TextCellValue((r.forMonth != null && r.forYear != null)
              ? '${r.forMonth}/${r.forYear}'
              : ''),
          excel_lib.TextCellValue(_fmtDate.format(r.requestDate)),
          excel_lib.DoubleCellValue(r.amount),
          excel_lib.TextCellValue(r.reason ?? ''),
          excel_lib.TextCellValue(_statusLabel(r.status)),
          excel_lib.TextCellValue(r.approvedByName ?? ''),
          excel_lib.TextCellValue(
              r.approvedDate != null ? _fmtDate.format(r.approvedDate!) : ''),
        ]);
      }
      final bytes = wb.encode();
      if (bytes != null) {
        final fn =
            'BaoCaoUngLuong_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
        await file_saver.saveFileBytes(bytes, fn,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
        if (mounted)
          NotificationOverlayManager()
              .showSuccess(title: 'Xuất Excel', message: 'Đã xuất: $fn');
      }
    } catch (e) {
      if (mounted)
        NotificationOverlayManager()
            .showError(title: 'Lỗi', message: 'Không thể xuất Excel: $e');
    }
  }

  String _statusLabel(AdvanceRequestStatus s) {
    switch (s) {
      case AdvanceRequestStatus.pending:
        return 'Chờ duyệt';
      case AdvanceRequestStatus.approved:
        return 'Đã duyệt';
      case AdvanceRequestStatus.rejected:
        return 'Từ chối';
      case AdvanceRequestStatus.cancelled:
        return 'Đã hủy';
    }
  }

  Color _statusColor(AdvanceRequestStatus s) {
    switch (s) {
      case AdvanceRequestStatus.pending:
        return Colors.orange;
      case AdvanceRequestStatus.approved:
        return const Color(0xFF16A34A);
      case AdvanceRequestStatus.rejected:
        return const Color(0xFFDC2626);
      case AdvanceRequestStatus.cancelled:
        return Colors.grey;
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
        title: const Text('Báo cáo ứng lương'),
        backgroundColor: _aTheme,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
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
                backgroundColor: _aTheme,
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
        child: DropdownButton<AdvanceRequestStatus?>(
          value: _statusFilter,
          isExpanded: true,
          hint: const Text('Trạng thái',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 18, color: Color(0xFF9CA3AF)),
          items: [
            const DropdownMenuItem(value: null, child: Text('Tất cả')),
            ...AdvanceRequestStatus.values.map((s) =>
                DropdownMenuItem(value: s, child: Text(_statusLabel(s)))),
          ],
          onChanged: (v) => setState(() => _statusFilter = v),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      height: 78,
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _SumCard('Tổng yêu cầu', _filtered.length.toString(), Icons.list_alt,
              Colors.blueGrey),
          _SumCard(
              'Chờ duyệt',
              _filtered
                  .where((r) => r.status == AdvanceRequestStatus.pending)
                  .length
                  .toString(),
              Icons.hourglass_empty,
              Colors.orange),
          _SumCard(
              'Đã duyệt',
              _filtered
                  .where((r) => r.status == AdvanceRequestStatus.approved)
                  .length
                  .toString(),
              Icons.check_circle_outline,
              const Color(0xFF16A34A)),
          _SumCard(
              'Tổng tiền',
              '${_fmtMoney.format(_filtered.fold(0.0, (s, r) => s + r.amount))}đ',
              Icons.payments_outlined,
              _aTheme),
          _SumCard(
              'Tiền đã duyệt',
              '${_fmtMoney.format(_filtered.where((r) => r.status == AdvanceRequestStatus.approved).fold(0.0, (s, r) => s + r.amount))}đ',
              Icons.account_balance,
              const Color(0xFF16A34A)),
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

    const hdrBg = Color(0xFFFEF3C7);
    const evenBg = Colors.white;
    const oddBg = Color(0xFFF9FAFB);

    Widget hCell(String t, double w) => Container(
          width: w,
          height: _aHdrH,
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
          height: _aRowH,
          color: i.isEven ? evenBg : oddBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12, color: textColor ?? const Color(0xFF374151)),
              overflow: TextOverflow.ellipsis),
        );

    Widget sCell(AdvanceRequestStatus s, double w, int i) => Container(
          width: w,
          height: _aRowH,
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
              width: _aStickyW,
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
                      width: _aStickyW,
                      height: _aHdrH,
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
                      final r = rows[i];
                      return Container(
                        width: _aStickyW,
                        height: _aRowH,
                        color: i.isEven ? evenBg : oddBg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(r.employeeName,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827)),
                                  overflow: TextOverflow.ellipsis),
                              Text(r.employeeCode,
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
                        hCell('Tháng/Năm', 92),
                        hCell('Ngày tạo', 104),
                        hCell('Số tiền', 128),
                        hCell('Lý do', 180),
                        hCell('Trạng thái', 112),
                        hCell('Người duyệt', 130),
                      ]),
                      ...List.generate(rows.length, (i) {
                        final r = rows[i];
                        final monthYear =
                            (r.forMonth != null && r.forYear != null)
                                ? '${r.forMonth}/${r.forYear}'
                                : '—';
                        return Row(children: [
                          dCell(monthYear, 92, i),
                          dCell(_fmtDate.format(r.requestDate), 104, i),
                          dCell('${_fmtMoney.format(r.amount)}đ', 128, i,
                              textColor: _aTheme),
                          dCell(r.reason ?? '', 180, i),
                          sCell(r.status, 112, i),
                          dCell(r.approvedByName ?? '—', 130, i),
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
