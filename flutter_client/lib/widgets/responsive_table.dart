import 'package:flutter/material.dart';
import '../utils/responsive_helper.dart';

/// A column definition for ResponsiveTable
class ResponsiveColumn {
  final String label;
  final String? fieldKey;
  // Builder for cell content; receives the row data and the row index
  final Widget Function(Map<String, dynamic> row, int index)? cellBuilder;
  // Whether to hide this column on mobile card view
  final bool showInCard;
  // Whether to always show as the card header/title field
  final bool isPrimary;
  // Flex for DataTable columns (desktop)
  final int flex;

  const ResponsiveColumn({
    required this.label,
    this.fieldKey,
    this.cellBuilder,
    this.showInCard = true,
    this.isPrimary = false,
    this.flex = 1,
  });
}

/// Renders a DataTable on desktop/tablet and a card list on mobile.
///
/// [columns] defines the column schema.
/// [rows] is a list of plain Map<String, dynamic> data.
/// [onRowTap] is an optional callback when a card/row is tapped.
/// [isLoading] shows a loading indicator when true.
/// [emptyMessage] is shown when rows is empty.
class ResponsiveTable extends StatelessWidget {
  final List<ResponsiveColumn> columns;
  final List<Map<String, dynamic>> rows;
  final void Function(Map<String, dynamic> row, int index)? onRowTap;
  final bool isLoading;
  final String emptyMessage;
  final Widget? header;
  final List<Widget>? actions;
  /// Extra widgets shown above the table (e.g. filter bar)
  final Widget? toolbar;

  const ResponsiveTable({
    super.key,
    required this.columns,
    required this.rows,
    this.onRowTap,
    this.isLoading = false,
    this.emptyMessage = 'Không có dữ liệu',
    this.header,
    this.actions,
    this.toolbar,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (toolbar != null) toolbar!,
        if (rows.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inbox_outlined, size: 48, color: Color(0xFFA1A1AA)),
                  const SizedBox(height: 12),
                  Text(emptyMessage, style: const TextStyle(color: Color(0xFFA1A1AA))),
                ],
              ),
            ),
          )
        else if (Responsive.isMobile(context))
          Expanded(child: _buildCardList(context))
        else
          Expanded(child: _buildDataTable(context)),
      ],
    );
  }

  Widget _buildCardList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) => _buildCard(context, rows[index], index),
    );
  }

  Widget _buildCard(BuildContext context, Map<String, dynamic> row, int index) {
    // Primary column shown as card header
    final primaryCol = columns.firstWhere(
      (c) => c.isPrimary,
      orElse: () => columns.first,
    );

    final cardCols = columns.where((c) => c.showInCard && !c.isPrimary).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onRowTap != null ? () => onRowTap!(row, index) : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Primary row
              Row(
                children: [
                  Expanded(
                    child: primaryCol.cellBuilder != null
                        ? primaryCol.cellBuilder!(row, index)
                        : Text(
                            '${row[primaryCol.fieldKey] ?? ''}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                  ),
                  if (onRowTap != null)
                    const Icon(Icons.chevron_right, color: Color(0xFFA1A1AA), size: 20),
                ],
              ),
              if (cardCols.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Divider(height: 24),
                const SizedBox(height: 8),
                // Grid of key-value pairs
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: cardCols.map((col) {
                    return ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 120),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            col.label,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFA1A1AA),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          col.cellBuilder != null
                              ? col.cellBuilder!(row, index)
                              : Text(
                                  '${row[col.fieldKey] ?? '—'}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataTable(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF4F4F5)),
          dataRowMinHeight: 44,
          dataRowMaxHeight: 56,
          headingRowHeight: 44,
          columnSpacing: 20,
          horizontalMargin: 16,
          columns: columns
              .map((col) => DataColumn(
                    label: Text(
                      col.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: Color(0xFF52525B),
                      ),
                    ),
                  ))
              .toList(),
          rows: rows.asMap().entries.map((entry) {
            final index = entry.key;
            final row = entry.value;
            return DataRow(
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                if (states.contains(WidgetState.hovered)) {
                  return const Color(0xFFF0F4FF);
                }
                return index.isEven ? Colors.white : const Color(0xFFFAFAFB);
              }),
              onSelectChanged: onRowTap != null
                  ? (_) => onRowTap!(row, index)
                  : null,
              cells: columns.map((col) {
                return DataCell(
                  col.cellBuilder != null
                      ? col.cellBuilder!(row, index)
                      : Text('${row[col.fieldKey] ?? ''}'),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}

/// A simple mobile-friendly search + filter bar
class MobileFilterBar extends StatelessWidget {
  final TextEditingController? controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final List<Widget> filters;

  const MobileFilterBar({
    super.key,
    this.controller,
    this.hintText = 'Tìm kiếm...',
    this.onChanged,
    this.filters = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Column(
        children: [
          TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          if (filters.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters
                    .expand((f) => [f, const SizedBox(width: 8)])
                    .take(filters.length * 2 - 1)
                    .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
