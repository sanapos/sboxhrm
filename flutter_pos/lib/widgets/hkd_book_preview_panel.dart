import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:sbox_pos/l10n/app_tr.dart';

/// Bảng xem sổ HKD trên màn hình (JSON preview) — không cần tải Excel.
class HkdBookPreviewPanel extends StatefulWidget {
  const HkdBookPreviewPanel({
    super.key,
    required this.preview,
    required this.loading,
    required this.accent,
    this.error,
    this.onExport,
    this.canExport = false,
    this.exporting = false,
  });

  final Map<String, dynamic>? preview;
  final bool loading;
  final Color accent;
  final String? error;
  final VoidCallback? onExport;
  final bool canExport;
  final bool exporting;

  @override
  State<HkdBookPreviewPanel> createState() => _HkdBookPreviewPanelState();
}

class _HkdBookPreviewPanelState extends State<HkdBookPreviewPanel> {
  final _searchCtrl = TextEditingController();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _qty = NumberFormat('#,##0.###', 'vi_VN');

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  double _num(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse('$v') ?? 0;
  }

  String _cell(dynamic v, {bool money = false, bool qty = false}) {
    if (v == null) return '';
    if (v is String) return v;
    if (money) return _money.format(_num(v));
    if (qty) return _qty.format(_num(v));
    if (v is num) {
      if (v == v.roundToDouble()) return v.toInt().toString();
      return _qty.format(v);
    }
    return '$v';
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> data) {
    final raw = (data['rows'] as List?) ?? const [];
    final q = _searchCtrl.text.trim().toLowerCase();
    final mapped = raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (q.isEmpty) return mapped;
    return mapped.where((row) {
      return row.values.any((v) => '$v'.toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.error != null && widget.error!.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(widget.error!,
            style: const TextStyle(color: Color(0xFFB42318))),
      );
    }
    final data = widget.preview;
    if (data == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          tr('Chọn sổ và kỳ dữ liệu để xem chi tiết trên màn hình.'),
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
      );
    }

    final title = data['title']?.toString() ?? '';
    final period = data['periodLabel']?.toString() ?? '';
    final note = data['note']?.toString();
    final truncated = data['truncated'] == true;
    final summary = ((data['summary'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final columns = ((data['columns'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final rows = _rows(data);
    final totalCount = (data['rowCount'] as num?)?.toInt() ?? rows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(title.isEmpty ? 'Chi tiết sổ' : title),
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  if (period.isNotEmpty)
                    Text(period,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF71717A))),
                ],
              ),
            ),
            if (widget.canExport)
              FilledButton.icon(
                onPressed: widget.exporting ? null : widget.onExport,
                style: FilledButton.styleFrom(backgroundColor: widget.accent),
                icon: const Icon(Icons.download, size: 16),
                label: Text(tr('Xuất Excel')),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (summary.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: summary.map((s) {
              final label = s['label']?.toString() ?? '';
              final value = _num(s['value']);
              final isCount = label.toLowerCase().contains('số ') ||
                  label.toLowerCase().contains('sku');
              return Container(
                constraints: const BoxConstraints(minWidth: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: widget.accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(label),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF71717A))),
                    const SizedBox(height: 2),
                    Text(
                      isCount
                          ? _money.format(value.round())
                          : _money.format(value),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: widget.accent,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        if (truncated || (note != null && note.isNotEmpty)) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr(note ?? 'Đang xem một phần dữ liệu. Xuất Excel để xem đủ.'),
              style: const TextStyle(fontSize: 12, color: Color(0xFF9A3412)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _searchCtrl,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: tr('Tìm trong sổ (số CT, diễn giải, mã...)'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          tr(rows.length == totalCount
              ? '$totalCount dòng'
              : '${rows.length} / $totalCount dòng'),
          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
        ),
        const SizedBox(height: 8),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              tr(_searchCtrl.text.trim().isEmpty
                  ? 'Không có phát sinh trong kỳ đã chọn.'
                  : 'Không khớp từ khóa tìm kiếm.'),
              style: const TextStyle(color: Color(0xFF71717A)),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 560),
            child: Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                headingRowHeight: 36,
                dataRowMinHeight: 36,
                dataRowMaxHeight: 52,
                columnSpacing: 16,
                headingRowColor: WidgetStatePropertyAll(
                  widget.accent.withValues(alpha: 0.08),
                ),
                columns: [
                  for (final c in columns)
                    DataColumn(
                      label: Text(
                        tr(c['label']?.toString() ?? c['key']?.toString() ?? ''),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                      numeric: c['money'] == true ||
                          c['Money'] == true ||
                          c['qty'] == true ||
                          c['Qty'] == true,
                    ),
                ],
                rows: [
                  for (final row in rows)
                    DataRow(
                      cells: [
                        for (final c in columns)
                          DataCell(
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: (c['key'] == 'description' ||
                                        c['key'] == 'productName')
                                    ? 280
                                    : 140,
                              ),
                              child: Text(
                                _cell(
                                  row[c['key']],
                                  money: c['money'] == true || c['Money'] == true,
                                  qty: c['qty'] == true || c['Qty'] == true,
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: row['description'] ==
                                              'Tồn cuối kỳ' ||
                                          row['description'] == 'Tồn đầu kỳ'
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 2,
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
