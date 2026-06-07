import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../models/cash_transaction.dart';
import '../utils/report_screen_helpers.dart';
import '../utils/vietnamese_text_fix.dart';

const _cRowH = 54.0;
const _cHdrH = 44.0;
const _cStickyW = 168.0;
const _cTheme = Color(0xFF0EA5E9);

class CashReportScreen extends StatefulWidget {
  const CashReportScreen({super.key});
  @override
  State<CashReportScreen> createState() => _CashReportScreenState();
}

class _CashReportScreenState extends State<CashReportScreen> {
  final ApiService _api = ApiService();
  final _fmtDate = DateFormat('dd/MM/yyyy');
  final _fmtMoney = NumberFormat('#,##0', 'vi_VN');

  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  String _datePreset = 'this_month';
  int? _typeFilter;
  bool _loading = false;
  List<Map<String, dynamic>> _items = [];
  // ignore: unused_field
  Map<String, dynamic> _summary = {};
  String _empSearch = '';

  List<Map<String, dynamic>> get _filtered => _empSearch.isEmpty
      ? _items
      : _items
          .where((t) => (t['createdByUserName']?.toString() ?? '')
              .toLowerCase()
              .contains(_empSearch.toLowerCase()))
          .toList();

  double get _totalIncome => _items
      .where((t) => _safeInt(t['type']) == 1)
      .fold(0.0, (s, t) => s + _safeDouble(t['amount']));
  double get _totalExpense => _items
      .where((t) => _safeInt(t['type']) == 2)
      .fold(0.0, (s, t) => s + _safeDouble(t['amount']));
  // ignore: unused_element
  double get _balance => _totalIncome - _totalExpense;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  List<String> get _empSuggestions => _items
      .map((t) => t['createdByUserName']?.toString() ?? '')
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
      final r = await _api.getCashTransactions(
          fromDate: _from, toDate: _to, type: _typeFilter, pageSize: 500);
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
      setState(() => _items = list);
    } catch (e) {
      debugPrint('cash_report _load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
    // Load summary separately — failure here won't block the main data
    try {
      final s =
          await _api.getCashTransactionSummary(fromDate: _from, toDate: _to);
      if (mounted && s['isSuccess'] == true && s['data'] is Map) {
        setState(() => _summary = Map<String, dynamic>.from(s['data'] as Map));
      }
    } catch (_) {}
  }

  Future<void> _exportExcel() async {
    final data = _filtered;
    final rows = <List<dynamic>>[];
    for (int i = 0; i < data.length; i++) {
      final t = data[i];
      final date = t['transactionDate'] != null
          ? DateTime.tryParse(t['transactionDate'].toString())
          : null;
      final typeVal = _safeInt(t['type']);
      rows.add([
        i + 1,
        t['transactionCode']?.toString() ?? '',
        fixVietnameseMojibake(t['categoryName']?.toString() ?? ''),
        typeVal == 1 ? 'Thu' : 'Chi',
        date != null ? _fmtDate.format(date) : '',
        _safeDouble(t['amount']),
        t['description']?.toString() ?? '',
        _paymentLabel(t['paymentMethod']),
        _statusLabel(t['status']),
        t['createdByUserName']?.toString() ?? '',
      ]);
    }
    await ClientExcelExport.export(
      context: context,
      title: 'Báo cáo thu chi',
      sheetName: 'Bao cao thu chi',
      filePrefix: 'BaoCaoThuChi',
      headers: const [
        'STT',
        'Mã GD',
        'Danh mục',
        'Loại',
        'Ngày',
        'Số tiền (đ)',
        'Mô tả',
        'Phương thức',
        'Trạng thái',
        'Người tạo',
      ],
      rows: rows,
      periodLabel: '${_fmtDate.format(_from)} – ${_fmtDate.format(_to)}',
      summaryLines: [
        'Tổng thu: ${_fmtMoney.format(_totalIncome)} đ',
        'Tổng chi: ${_fmtMoney.format(_totalExpense)} đ',
      ],
    );
  }

  String _paymentLabel(dynamic v) {
    final val = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 1;
    try {
      return PaymentMethodType.fromValue(val).label;
    } catch (_) {
      return v?.toString() ?? '';
    }
  }

  String _statusLabel(dynamic v) {
    final val = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 1;
    try {
      return CashTransactionStatus.fromValue(val).label;
    } catch (_) {
      return v?.toString() ?? '';
    }
  }

  Color _typeColor(dynamic v) {
    final val = (v is num) ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 1;
    return val == 1 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Báo cáo thu chi'),
        backgroundColor: _cTheme,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (Provider.of<PermissionProvider>(context, listen: false)
              .canExport('CashReport'))
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
          Expanded(child: _typeDrop()),
          const SizedBox(width: 8),
          SizedBox(
            height: 40,
            child: FilledButton.icon(
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Tìm', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _cTheme,
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
        _buildEmpSearch('Lọc theo người tạo...'),
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

  Widget _typeDrop() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(8)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: _typeFilter,
          isExpanded: true,
          hint: const Text('Loại',
              style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          style: const TextStyle(fontSize: 12, color: Color(0xFF111827)),
          icon: const Icon(Icons.keyboard_arrow_down,
              size: 18, color: Color(0xFF9CA3AF)),
          items: const [
            DropdownMenuItem(value: null, child: Text('Tất cả')),
            DropdownMenuItem(value: 1, child: Text('Thu')),
            DropdownMenuItem(value: 2, child: Text('Chi')),
          ],
          onChanged: (v) => setState(() => _typeFilter = v),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final f = _filtered;
    final sIncome = f
        .where((t) => _safeInt(t['type']) == 1)
        .fold(0.0, (s, t) => s + _safeDouble(t['amount']));
    final sExpense = f
        .where((t) => _safeInt(t['type']) == 2)
        .fold(0.0, (s, t) => s + _safeDouble(t['amount']));
    final sBalance = sIncome - sExpense;
    final sCount = f.length;
    return Container(
      height: 78,
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          _sumCard('Giao dịch', sCount.toString(), Icons.receipt_outlined,
              Colors.blueGrey),
          _sumCard('Tổng thu', '${_fmtMoney.format(sIncome)}đ',
              Icons.arrow_circle_down, const Color(0xFF16A34A)),
          _sumCard('Tổng chi', '${_fmtMoney.format(sExpense)}đ',
              Icons.arrow_circle_up, const Color(0xFFDC2626)),
          _sumCard(
              'Còn lại',
              '${_fmtMoney.format(sBalance)}đ',
              Icons.account_balance_wallet,
              sBalance >= 0
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFDC2626)),
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
          height: _cHdrH,
          color: hdrBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: Color(0xFF374151))),
        );

    Widget dCell(String t, double w, int i,
            {Color? textColor, bool ellipsis = true}) =>
        Container(
          width: w,
          height: _cRowH,
          color: i.isEven ? evenBg : oddBg,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(t,
              style: TextStyle(
                  fontSize: 12, color: textColor ?? const Color(0xFF374151)),
              overflow: ellipsis ? TextOverflow.ellipsis : null),
        );

    return Container(
      color: Colors.white,
      margin: const EdgeInsets.only(top: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // ═══ STICKY: Danh mục ═══
            Container(
              width: _cStickyW,
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
                      width: _cStickyW,
                      height: _cHdrH,
                      color: hdrBg,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: const Text('Danh mục',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              color: Color(0xFF374151))),
                    ),
                    ...List.generate(rows.length, (i) {
                      final t = rows[i];
                      final typeVal = _safeInt(t['type']);
                      final catName = fixVietnameseMojibake(
                          t['categoryName']?.toString() ?? '—');
                      final typeColor = _typeColor(typeVal);
                      return Container(
                        width: _cStickyW,
                        height: _cRowH,
                        color: i.isEven ? evenBg : oddBg,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(catName,
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF111827)),
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 1),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color: typeColor.withValues(alpha: 0.35)),
                                ),
                                child: Text(typeVal == 1 ? 'Thu' : 'Chi',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: typeColor)),
                              ),
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
                        hCell('Mã GD', 108),
                        hCell('Ngày', 104),
                        hCell('Số tiền', 128),
                        hCell('Mô tả', 180),
                        hCell('Phương thức', 120),
                        hCell('Trạng thái', 108),
                      ]),
                      ...List.generate(rows.length, (i) {
                        final t = rows[i];
                        final date = t['transactionDate'] != null
                            ? DateTime.tryParse(t['transactionDate'].toString())
                            : null;
                        final typeVal = _safeInt(t['type']);
                        final amt = _safeDouble(t['amount']);
                        return Row(children: [
                          dCell(
                              t['transactionCode']?.toString() ?? '—', 108, i),
                          dCell(date != null ? _fmtDate.format(date) : '—', 104,
                              i),
                          dCell('${_fmtMoney.format(amt)}đ', 128, i,
                              textColor: _typeColor(typeVal)),
                          dCell(t['description']?.toString() ?? '', 180, i),
                          dCell(_paymentLabel(t['paymentMethod']), 120, i),
                          dCell(_statusLabel(t['status']), 108, i),
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
