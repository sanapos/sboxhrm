import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import 'package:sbox_pos/l10n/app_tr.dart';

import '../../utils/pos_print_template_defaults.dart';

/// Render HTML mẫu in (kèm bảng — flutter_html 3 tách table ra extension).
Widget buildPosRenderedHtml(
  String html, {
  double bodyFontSize = 13,
  double tableFontSize = 12,
  bool a4Width = false,
  bool shrinkWrap = false,
  HtmlPaddings? bodyPadding,
  double? pageWidth,
}) {
  final child = Html(
    data: html,
    shrinkWrap: shrinkWrap || !a4Width,
    extensions: const [PosPrintTableExtension()],
    style: {
      'html': Style(backgroundColor: Colors.white),
      'body': Style(
        margin: Margins.zero,
        padding: bodyPadding ?? HtmlPaddings.all(12),
        fontSize: FontSize(bodyFontSize),
        fontFamily: '"Times New Roman", Times, serif',
        color: Colors.black,
        lineHeight: LineHeight.number(1.4),
      ),
      'div': Style(
        margin: Margins.zero,
        padding: HtmlPaddings.zero,
        lineHeight: LineHeight.number(1.35),
      ),
      'h2': Style(
        fontSize: FontSize(18),
        fontWeight: FontWeight.w800,
        textAlign: TextAlign.center,
        alignment: Alignment.center,
        width: Width(100, Unit.percent),
        margin: Margins.symmetric(vertical: 8),
      ),
      'h3': Style(
        fontSize: FontSize(14),
        fontWeight: FontWeight.w800,
        textAlign: TextAlign.left,
        margin: Margins.only(bottom: 2),
      ),
      'b': Style(fontWeight: FontWeight.w800),
      'strong': Style(fontWeight: FontWeight.w800),
      'table': Style(
        width: Width(100, Unit.percent),
        fontSize: FontSize(tableFontSize),
      ),
      'p': Style(
        margin: Margins.symmetric(vertical: 6),
        lineHeight: LineHeight.number(1.45),
        textAlign: TextAlign.justify,
      ),
      'th': Style(
        padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 5),
        fontSize: FontSize(tableFontSize),
        fontWeight: FontWeight.w800,
        textAlign: TextAlign.center,
      ),
      'td': Style(
        padding: HtmlPaddings.symmetric(horizontal: 6, vertical: 5),
        fontSize: FontSize(tableFontSize),
      ),
    },
  );
  if (a4Width) {
    final w = pageWidth ?? kPosA4CssWidth;
    return SizedBox(
      width: w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [ClipRect(child: child)],
      ),
    );
  }
  return child;
}

/// Khổ A4 CSS @ 96dpi — luôn render đúng 794×1123 rồi thu phóng, không reflow.
const kPosA4CssWidth = 794.0;
const kPosA4CssHeight = kPosA4CssWidth * 297 / 210;

/// Tờ A4/A5: một dải giấy liền, vạch cắt trang — không nhân bản widget (phóng to không lẫn).
Widget buildPosA4ScaledSheet({
  Widget? child,
  Widget Function()? buildChild,
  required double zoom,
  EdgeInsets pad = const EdgeInsets.all(8),
  double pageWidth = kPosA4CssWidth,
  double pageHeight = kPosA4CssHeight,
}) {
  assert(child != null || buildChild != null);
  return PosA4PaginatedSheet(
    zoom: zoom,
    pad: pad,
    pageWidth: pageWidth,
    pageHeight: pageHeight,
    buildChild: buildChild ?? () => child!,
  );
}

class PosA4PaginatedSheet extends StatelessWidget {
  const PosA4PaginatedSheet({
    super.key,
    required this.buildChild,
    required this.zoom,
    this.pad = const EdgeInsets.all(8),
    this.pageWidth = kPosA4CssWidth,
    this.pageHeight = kPosA4CssHeight,
  });

  final Widget Function() buildChild;
  final double zoom;
  final EdgeInsets pad;
  final double pageWidth;
  final double pageHeight;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE5E7EB),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availW =
              math.max(80.0, constraints.maxWidth - pad.horizontal);
          final scale = zoom <= 0
              ? (availW / pageWidth).clamp(0.12, 1.0)
              : zoom.clamp(0.2, 3.0);
          final viewW = pageWidth * scale;
          final paper = SizedBox(
            width: pageWidth,
            child: Material(
              color: Colors.white,
              elevation: 5,
              clipBehavior: Clip.hardEdge,
              child: CustomPaint(
                foregroundPainter: _A4PageMarksPainter(pageHeight: pageHeight),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: pageWidth,
                    maxWidth: pageWidth,
                    minHeight: pageHeight,
                  ),
                  child: buildChild(),
                ),
              ),
            ),
          );
          final scaled = SizedBox(
            width: viewW,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: paper,
            ),
          );
          final body = Padding(
            padding: pad,
            child: Align(alignment: Alignment.topCenter, child: scaled),
          );
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: viewW > availW + 1
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: body,
                    )
                  : body,
            ),
          );
        },
      ),
    );
  }
}

class _A4PageMarksPainter extends CustomPainter {
  _A4PageMarksPainter({required this.pageHeight});

  final double pageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (pageHeight <= 0 || size.height <= 0) return;
    final pages = math.max(1, (size.height / pageHeight).ceil());
    final line = Paint()
      ..color = const Color(0xFF9CA3AF)
      ..strokeWidth = 1;
    for (var i = 1; i < pages; i++) {
      final y = i * pageHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      final tp = TextPainter(
        text: TextSpan(
          text: 'Trang $i / $pages',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
            backgroundColor: Color(0xE6FFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(8, y - tp.height - 4));
    }
    if (pages > 1) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'Trang $pages / $pages',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF6B7280),
            backgroundColor: Color(0xE6FFFFFF),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(8, (pages - 1) * pageHeight + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _A4PageMarksPainter old) =>
      old.pageHeight != pageHeight;
}

bool posHtmlLooksLikeA4(String html) {
  final t = html.toLowerCase();
  return t.contains('a4') ||
      t.contains('a5') ||
      t.contains('210mm') ||
      t.contains('148mm') ||
      t.contains('times new roman') ||
      t.contains('báo giá') ||
      t.contains('hợp đồng') ||
      t.contains('nghiệm thu') ||
      t.contains('bàn giao');
}

/// Bỏ vỏ `<html><head>…` khi In thử bọc document — preview chỉ lấy body như tab Xem.
String stripPosHtmlDocumentShell(String html) {
  final t = html.trim();
  if (!t.toLowerCase().contains('<html')) return html;
  final m = RegExp(
    r'<body[^>]*>([\s\S]*)</body>',
    caseSensitive: false,
  ).firstMatch(t);
  return m?.group(1)?.trim() ?? html;
}

HtmlPaddings _pageSetupPadding(PosCommercialPageSetup setup) {
  const mm = 3.78;
  return HtmlPaddings.only(
    top: setup.topMm * mm,
    right: setup.rightMm * mm,
    bottom: setup.bottomMm * mm,
    left: setup.leftMm * mm,
  );
}

/// Tờ A4: zoom ≤ 0 = cả trang; > 0 = khổ thật (cuộn 2 chiều).
Widget buildPosA4PaperPreview(String html, {double zoom = 0}) {
  final setup = PosCommercialPageSetup.parse(html);
  return buildPosA4ScaledSheet(
    zoom: zoom,
    pageWidth: setup.cssWidth,
    pageHeight: setup.cssHeight,
    buildChild: () => buildPosRenderedHtml(
      stripPosHtmlDocumentShell(html),
      bodyFontSize: 13,
      tableFontSize: 12,
      a4Width: true,
      shrinkWrap: true,
      pageWidth: setup.cssWidth,
      bodyPadding: _pageSetupPadding(setup),
    ),
  );
}

/// Xem trước A4 có nút thu phóng (cả trang / 50–200%).
class PosA4ZoomablePreview extends StatefulWidget {
  const PosA4ZoomablePreview({super.key, required this.html});

  final String html;

  @override
  State<PosA4ZoomablePreview> createState() => _PosA4ZoomablePreviewState();
}

class _PosA4ZoomablePreviewState extends State<PosA4ZoomablePreview> {
  double _zoom = 0;
  static const _steps = <double>[0.4, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final label = _zoom <= 0 ? tr('Cả trang') : '${(_zoom * 100).round()}%';
    return Column(
      children: [
        Material(
          color: Colors.white,
          child: Row(
            children: [
              IconButton(
                tooltip: tr('Thu nhỏ'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 20),
                onPressed: () => setState(() {
                  if (_zoom <= 0) return;
                  _zoom = _steps.lastWhere((z) => z < _zoom - 0.001,
                      orElse: () => 0);
                }),
              ),
              Text(label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13)),
              IconButton(
                tooltip: tr('Phóng to'),
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 20),
                onPressed: () => setState(() {
                  if (_zoom <= 0) {
                    _zoom = 0.75;
                    return;
                  }
                  final i = _steps.indexWhere((z) => z > _zoom + 0.001);
                  if (i >= 0) _zoom = _steps[i];
                }),
              ),
              TextButton(
                onPressed: () => setState(() => _zoom = 0),
                child: Text(tr('Cả trang')),
              ),
              TextButton(
                onPressed: () => setState(() => _zoom = 1),
                child: Text(tr('100%')),
              ),
            ],
          ),
        ),
        Expanded(child: buildPosA4PaperPreview(widget.html, zoom: _zoom)),
      ],
    );
  }
}

/// Xem trước HTML mẫu in trên mobile/desktop (không cần web).
Widget buildPosHtmlPreview(String htmlDocument, {bool? a4Paper}) {
  if (htmlDocument.trim().isEmpty) {
    return Center(child: Text(tr('Chưa có nội dung')));
  }
  final a4 = a4Paper ?? posHtmlLooksLikeA4(htmlDocument);
  if (a4) {
    return PosA4ZoomablePreview(html: stripPosHtmlDocumentShell(htmlDocument));
  }
  return LayoutBuilder(
    builder: (context, constraints) {
      final paperW = constraints.maxWidth.clamp(280.0, 420.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: paperW,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: buildPosRenderedHtml(
              htmlDocument,
              bodyFontSize: 11,
              tableFontSize: 10,
            ),
          ),
        ),
      );
    },
  );
}

Future<void> printPosHtmlDocument(String htmlDocument) async {}

/// Bảng in A4: Flutter [Table] + độ rộng cố định — không dùng LayoutGrid
/// (flutter_html_table bung chiều cao, chữ biến mất trên điện thoại).
class PosPrintTableExtension extends HtmlExtension {
  const PosPrintTableExtension();

  @override
  Set<String> get supportedTags => {'table'};

  @override
  InlineSpan build(ExtensionContext context) {
    if (context.elementName != 'table' || context.element == null) {
      return const WidgetSpan(child: SizedBox.shrink());
    }
    return WidgetSpan(
      alignment: PlaceholderAlignment.top,
      child: _PosHtmlTableView(table: context.element!),
    );
  }
}

class _PosHtmlTableView extends StatelessWidget {
  const _PosHtmlTableView({required this.table});

  final dynamic table;

  static final _widthRe = RegExp(r'width\s*:\s*([\d.]+)\s*(%|px)?');
  static final _fontSizeRe = RegExp(r'font-size\s*:\s*([\d.]+)\s*px');

  /// Chỉ hàng/cột trực tiếp — querySelectorAll gom cả table lồng (quốc hiệu nhân đôi).
  List<dynamic> _directCols(dynamic t) {
    final cols = <dynamic>[];
    for (final child in t.children) {
      final n = '${child.localName}';
      if (n == 'col') cols.add(child);
      if (n == 'colgroup') {
        for (final g in child.children) {
          if ('${g.localName}' == 'col') cols.add(g);
        }
      }
    }
    return cols;
  }

  List<dynamic> _directRows(dynamic t) {
    final rows = <dynamic>[];
    void takeTrs(dynamic parent) {
      for (final c in parent.children) {
        if ('${c.localName}' == 'tr') rows.add(c);
      }
    }

    for (final child in t.children) {
      final n = '${child.localName}';
      if (n == 'tr') {
        rows.add(child);
      } else if (n == 'thead' || n == 'tbody' || n == 'tfoot') {
        takeTrs(child);
      }
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final cols = _directCols(table);
    final widths = <int, TableColumnWidth>{};
    for (var i = 0; i < cols.length; i++) {
      final raw = cols[i].attributes['width'] ??
          _widthRe.firstMatch(cols[i].attributes['style'] ?? '')?.group(1);
      final n = double.tryParse(raw ?? '');
      if (n == null || n <= 0) continue;
      // Luôn flex — width="385" px làm bảng rộng hơn khổ A4 (lề 12mm).
      widths[i] = FlexColumnWidth(n);
    }

    final allRows = _directRows(table);
    if (allRows.isEmpty) return const SizedBox.shrink();

    final bordered = table.outerHtml.contains('border:1px') ||
        table.outerHtml.contains('border: 1px');
    final headerBg = const Color(0xFFF3F4F6);
    final bodyRows = <dynamic>[];
    final footRows = <dynamic>[];
    for (final row in allRows) {
      if (row.parent?.localName == 'tfoot') {
        footRows.add(row);
      } else {
        bodyRows.add(row);
      }
    }

    final colCount = math.max<int>(
      (cols.length as num).toInt(),
      bodyRows.fold<int>(
          0, (m, r) => math.max(m, _expandedCells(r, bordered: bordered).length)),
    );

    final children = <TableRow>[
      for (final row in bodyRows)
        TableRow(
          decoration: BoxDecoration(
            color: row.children.any((c) => c.localName == 'th') ||
                    (row.attributes['style'] ?? '').contains('background')
                ? headerBg
                : null,
          ),
          children: _padRow(_expandedCells(row, bordered: bordered), colCount),
        ),
    ];

    Widget result = Table(
      columnWidths: widths.isEmpty ? null : widths,
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: bordered
          ? TableBorder.all(color: const Color(0xFF111111), width: 0.7)
          : const TableBorder(),
      children: children,
    );
    if (footRows.isNotEmpty) {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          result,
          for (final row in footRows) _footerRow(row, bordered),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final w = (!c.maxWidth.isFinite || c.maxWidth < 40)
            ? kPosA4CssWidth
            : math.min(c.maxWidth, kPosA4CssWidth);
        return SizedBox(width: w, child: result);
      },
    );
  }

  List<Widget> _expandedCells(dynamic row, {required bool bordered}) {
    final out = <Widget>[];
    for (final cell in row.children) {
      if (cell.localName != 'td' && cell.localName != 'th') continue;
      final span = int.tryParse(cell.attributes['colspan'] ?? '1') ?? 1;
      out.add(_cell(cell, isHead: cell.localName == 'th', bordered: bordered));
      for (var i = 1; i < span; i++) {
        out.add(const SizedBox.shrink());
      }
    }
    return out;
  }

  List<Widget> _padRow(List<Widget> cells, int colCount) {
    if (cells.length >= colCount) return cells;
    return [...cells, for (var i = cells.length; i < colCount; i++) const SizedBox.shrink()];
  }

  Widget _footerRow(dynamic row, bool bordered) {
    final cells = row.children
        .where((c) => c.localName == 'td' || c.localName == 'th')
        .toList();
    if (cells.isEmpty) return const SizedBox.shrink();
    final left = cells.first;
    final right = cells.length > 1 ? cells.last : null;
    final box = BoxDecoration(
      color: (row.attributes['style'] ?? '').contains('background')
          ? const Color(0xFFF8FAFC)
          : null,
      border: bordered
          ? const Border(
              left: BorderSide(color: Color(0xFF111111), width: 0.7),
              right: BorderSide(color: Color(0xFF111111), width: 0.7),
              bottom: BorderSide(color: Color(0xFF111111), width: 0.7),
            )
          : null,
    );
    return Container(
      decoration: box,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: _cell(left, isHead: true, bordered: bordered),
          ),
          Expanded(
            flex: 2,
            child: right == null
                ? const SizedBox.shrink()
                : _cell(right, isHead: true, bordered: bordered),
          ),
        ],
      ),
    );
  }

  String _cellText(dynamic cell) {
    var html = '${cell.innerHtml}';
    html = html.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    html = html.replaceAll(RegExp(r'</div>', caseSensitive: false), '\n');
    html = html.replaceAll(RegExp(r'<[^>]+>'), '');
    html = html
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
    return html
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r' *\n *'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  double _fontSizeOf(String style, {required bool bordered}) {
    final m = _fontSizeRe.firstMatch(style);
    final n = m == null ? null : double.tryParse(m.group(1)!);
    return n ?? (bordered ? 12.0 : 13.0);
  }

  Widget _cell(dynamic cell, {required bool isHead, required bool bordered}) {
    final style = cell.attributes['style'] ?? '';
    final inner = '${cell.innerHtml}';
    final align = style.contains('text-align:right')
        ? TextAlign.right
        : style.contains('text-align:center')
            ? TextAlign.center
            : style.contains('text-align:left')
                ? TextAlign.left
                : (cell.localName == 'th' ? TextAlign.center : TextAlign.left);
    final bold = isHead ||
        cell.localName == 'th' ||
        inner.contains('<b>') ||
        inner.contains('<h2') ||
        inner.contains('<h3') ||
        style.contains('font-weight:bold') ||
        style.contains('font-weight:700') ||
        style.contains('font-weight:800');
    final fs = _fontSizeOf(style, bordered: bordered);
    final rich = inner.contains('<h2') ||
        inner.contains('<h3') ||
        inner.contains('<div') ||
        inner.contains('<table') ||
        inner.contains('<br');
    if (rich) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Html(
          data: inner,
          shrinkWrap: true,
          extensions: const [PosPrintTableExtension()],
          style: {
            'body': Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              fontSize: FontSize(fs),
              fontFamily: '"Times New Roman", Times, serif',
              color: Colors.black,
              textAlign: align,
              lineHeight: LineHeight.number(1.35),
            ),
            'h2': Style(
              fontSize: FontSize(18),
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.center,
              margin: Margins.symmetric(vertical: 4),
            ),
            'h3': Style(
              fontSize: FontSize(14),
              fontWeight: FontWeight.w800,
              textAlign: TextAlign.left,
              margin: Margins.only(bottom: 2),
            ),
            'div': Style(
              margin: Margins.zero,
              padding: HtmlPaddings.zero,
              fontSize: FontSize(13),
            ),
            'b': Style(fontWeight: FontWeight.w800),
            'strong': Style(fontWeight: FontWeight.w800),
            'i': Style(fontStyle: FontStyle.italic),
            'p': Style(margin: Margins.zero),
          },
        ),
      );
    }
    final text = _cellText(cell);
    final nowrap = style.contains('white-space:nowrap') ||
        style.contains('white-space: nowrap');
    final alignDir = align == TextAlign.right
        ? Alignment.centerRight
        : align == TextAlign.center
            ? Alignment.center
            : Alignment.centerLeft;
    final textW = Text(
      text,
      textAlign: align,
      softWrap: !nowrap,
      maxLines: nowrap ? 1 : null,
      overflow: nowrap ? TextOverflow.clip : TextOverflow.visible,
      style: TextStyle(
        fontSize: fs,
        fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
        height: 1.3,
        color: Colors.black,
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: nowrap
          ? Align(
              alignment: alignDir,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: alignDir,
                child: textW,
              ),
            )
          : textW,
    );
  }
}
