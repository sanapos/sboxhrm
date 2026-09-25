import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_tr.dart';
import '../services/api_service.dart';
import '../utils/report_screen_helpers.dart';
import '../widgets/hrm_page_chrome.dart';

/// Độ phủ ca theo định mức nhân sự: mỗi ngày × ca × phòng ban → số người đã xếp
/// so với tối thiểu / tối đa (Thiếu / Cảnh báo / Đạt / Vượt).
class ShiftCoverageScreen extends StatefulWidget {
  const ShiftCoverageScreen({super.key});

  @override
  State<ShiftCoverageScreen> createState() => _ShiftCoverageScreenState();
}

Color _statusColor(String s) => switch (s) {
      'Thiếu' => const Color(0xFFC62828),
      'Cảnh báo' => const Color(0xFFEF6C00),
      'Vượt' => const Color(0xFF7B1FA2),
      _ => const Color(0xFF2E7D32),
    };

class _ShiftCoverageScreenState extends State<ShiftCoverageScreen> {
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  late DateTime _from;
  late DateTime _to;
  bool _loading = false;
  String? _error;
  String? _statusFilter;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));
    _to = _from.add(const Duration(days: 6));
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getShiftCoverageReport(from: _from, to: _to);
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? tr('Không tải được báo cáo');
      });
      return;
    }
    final data = (res['data'] as Map?)?.cast<String, dynamic>() ?? const {};
    setState(() {
      _loading = false;
      _items = ((data['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    });
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 180)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (picked == null) return;
    setState(() {
      _from = picked.start;
      _to = picked.end;
    });
    await _load();
  }

  List<Map<String, dynamic>> get _visible => _statusFilter == null
      ? _items
      : _items.where((i) => i['status'] == _statusFilter).toList();

  DateTime _date(Map<String, dynamic> i) =>
      DateTime.tryParse('${i['date']}') ?? DateTime(2000);

  Future<void> _export() async {
    final rows = _visible;
    await ClientExcelExport.export(
      context: context,
      title: 'Độ phủ ca theo định mức',
      sheetName: 'Do phu ca',
      filePrefix: 'DoPhuCa',
      headers: const ['STT', 'Ngày', 'Ca', 'Phòng ban', 'Tối thiểu', 'Tối đa', 'Đã xếp', 'Còn thiếu', 'Trạng thái'],
      rows: [
        for (var i = 0; i < rows.length; i++)
          [
            i + 1,
            _dateFmt.format(_date(rows[i])),
            rows[i]['shiftName'] ?? '',
            rows[i]['department'] ?? '',
            rows[i]['minRequired'] ?? 0,
            rows[i]['maxAllowed'] ?? 0,
            rows[i]['registered'] ?? 0,
            rows[i]['gap'] ?? 0,
            rows[i]['status'] ?? '',
          ],
      ],
      periodLabel: '${_dateFmt.format(_from)} – ${_dateFmt.format(_to)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final i in _items) {
      final s = i['status']?.toString() ?? '';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final byDate = <DateTime, List<Map<String, dynamic>>>{};
    for (final i in _visible) {
      byDate.putIfAbsent(_date(i), () => []).add(i);
    }
    final dates = byDate.keys.toList()..sort();

    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: Text(tr('Độ phủ ca theo định mức')),
        actions: [
          IconButton(
            tooltip: tr('Xuất Excel'),
            onPressed: _items.isEmpty || _loading ? null : _export,
            icon: const Icon(Icons.table_view_outlined),
          ),
          IconButton(
            tooltip: tr('Tải lại'),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loading ? null : _pickRange,
              icon: const Icon(Icons.date_range, size: 18),
              label: Text('${_dateFmt.format(_from)} – ${_dateFmt.format(_to)}'),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in const ['Thiếu', 'Cảnh báo', 'Đạt', 'Vượt'])
                ChoiceChip(
                  selected: _statusFilter == s,
                  visualDensity: VisualDensity.compact,
                  avatar: CircleAvatar(backgroundColor: _statusColor(s), radius: 6),
                  label: Text('${tr(s)} ${counts[s] ?? 0}'),
                  onSelected: (_) =>
                      setState(() => _statusFilter = _statusFilter == s ? null : s),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red))
          else if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                tr('Chưa có định mức nhân sự cho ca nào. Thiết lập định mức (tối thiểu / tối đa người mỗi ca) trong màn Lịch làm việc.'),
                textAlign: TextAlign.center,
              ),
            )
          else
            for (final d in dates) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 4),
                child: Text(DateFormat('EEEE, dd/MM/yyyy', 'vi').format(d),
                    style: const TextStyle(fontWeight: FontWeight.w700, color: HrmPageChrome.primaryNavy)),
              ),
              for (final i in byDate[d]!) _tile(i),
            ],
        ],
      ),
    );
  }

  Widget _tile(Map<String, dynamic> i) {
    final status = i['status']?.toString() ?? '';
    final color = _statusColor(status);
    final registered = (i['registered'] as num?)?.toInt() ?? 0;
    final min = (i['minRequired'] as num?)?.toInt() ?? 0;
    final max = (i['maxAllowed'] as num?)?.toInt() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color.withValues(alpha: 0.35)),
      ),
      child: ListTile(
        dense: true,
        title: Text('${i['shiftName'] ?? ''} · ${i['department'] ?? ''}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(tr('Đã xếp $registered / tối thiểu $min – tối đa $max')
            + ((i['gap'] as num? ?? 0) > 0 ? ' · ${tr('thiếu')} ${i['gap']}' : '')),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(tr(status),
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
