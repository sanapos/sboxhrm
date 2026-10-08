import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../models/pos_print_template_v2.dart';
import '../../utils/pos_print_template_compiler.dart';
import 'pos_print_exact_preview.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// Cỡ chữ nhanh (điểm in).
const kPosPrintFontPresets = <(String, double)>[
  ('Nhỏ', 20),
  ('Vừa', 26),
  ('Lớn', 32),
  ('Tiêu đề', 40),
  ('Rất lớn', 52),
];

const double kPosPrintMinFont = 12;
const double kPosPrintMaxFont = 64;

/// Chuẩn bị ảnh cho máy in nhiệt: thu về khổ giấy, nền trong suốt → trắng, chuyển đen trắng.
/// [photo] = ảnh chụp → chấm điểm (dither) giữ sắc độ; ngược lại logo nét (ngưỡng).
/// Trả base64 PNG hoặc null nếu không đọc được ảnh.
String? preparePosPrintImage(Uint8List raw, {int maxWidth = 576, bool photo = false, int threshold = 160}) {
  final src = img.decodeImage(raw);
  if (src == null) return null;
  final resized = src.width > maxWidth ? img.copyResize(src, width: maxWidth, interpolation: img.Interpolation.average) : src;
  final w = resized.width;
  final h = resized.height;
  final out = img.Image(width: w, height: h, numChannels: 3);
  const bayer = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
  ];
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = resized.getPixel(x, y);
      final a = resized.numChannels == 4 ? p.aNormalized : 1.0;
      final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
      final maxV = p.maxChannelValue == 0 ? 255.0 : p.maxChannelValue.toDouble();
      // Trộn với nền trắng theo độ trong suốt.
      final l = 255 - a * (255 - lum * 255 / maxV);
      final t = photo ? (bayer[y % 4][x % 4] + 0.5) * 16 : threshold.toDouble();
      final v = l < t ? 0 : 255;
      out.setPixelRgb(x, y, v, v, v);
    }
  }
  return base64Encode(img.encodePng(out));
}

/// Thanh định dạng nhanh cho khối đang chọn — căn trái/giữa/phải, cỡ chữ, đậm, IN HOA, sắp xếp, hoàn tác.
class PosPrintFormatToolbar extends StatelessWidget {
  const PosPrintFormatToolbar({
    super.key,
    required this.block,
    required this.onChanged,
    required this.readOnly,
    this.onUndo,
    this.onRedo,
    this.onMoveUp,
    this.onMoveDown,
    this.onDuplicate,
    this.onDelete,
  });

  final PosPrintBlock block;
  final ValueChanged<PosPrintBlock> onChanged;
  final bool readOnly;
  final VoidCallback? onUndo;
  final VoidCallback? onRedo;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;

  bool get _hasText => switch (block.type) {
        PosPrintBlockType.divider || PosPrintBlockType.spacer || PosPrintBlockType.vietQr || PosPrintBlockType.barcode => false,
        _ => true,
      };

  bool get _hasAlign => switch (block.type) {
        PosPrintBlockType.text || PosPrintBlockType.field || PosPrintBlockType.image => true,
        _ => false,
      };

  @override
  Widget build(BuildContext context) {
    final st = block.style;
    void setStyle(PosPrintTextStyle s) => onChanged(block.copyWith(style: s));
    Widget sep() => Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: PosTheme.border);
    Widget btn(IconData icon, String tip, VoidCallback? on, {bool active = false}) => IconButton(
          tooltip: tr(tip),
          visualDensity: VisualDensity.compact,
          isSelected: active,
          style: IconButton.styleFrom(
            backgroundColor: active ? const Color(0xFFE3F2FD) : null,
            foregroundColor: active ? const Color(0xFF1565C0) : null,
          ),
          onPressed: readOnly ? null : on,
          icon: Icon(icon, size: 19),
        );
    final isImage = block.type == PosPrintBlockType.image;
    return Material(
      color: const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(children: [
          btn(Icons.undo, 'Hoàn tác (Ctrl+Z)', onUndo),
          btn(Icons.redo, 'Làm lại (Ctrl+Y)', onRedo),
          sep(),
          if (_hasAlign) ...[
            btn(Icons.format_align_left, 'Căn trái', () => setStyle(st.copyWith(align: PosPrintTextAlign.left)),
                active: st.align == PosPrintTextAlign.left),
            btn(Icons.format_align_center, 'Căn giữa', () => setStyle(st.copyWith(align: PosPrintTextAlign.center)),
                active: st.align == PosPrintTextAlign.center),
            btn(Icons.format_align_right, 'Căn phải', () => setStyle(st.copyWith(align: PosPrintTextAlign.right)),
                active: st.align == PosPrintTextAlign.right),
            sep(),
          ],
          if (_hasText && !isImage) ...[
            btn(Icons.text_decrease, 'Chữ nhỏ hơn',
                () => setStyle(st.copyWith(fontSize: (st.fontSize - 2).clamp(kPosPrintMinFont, kPosPrintMaxFont)))),
            PopupMenuButton<double>(
              tooltip: tr('Cỡ chữ'),
              enabled: !readOnly,
              onSelected: (v) => setStyle(st.copyWith(fontSize: v)),
              itemBuilder: (_) => [
                for (final p in kPosPrintFontPresets)
                  PopupMenuItem(value: p.$2, child: Text(tr('${p.$1} (${p.$2.toInt()})'))),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(border: Border.all(color: PosTheme.border), borderRadius: BorderRadius.circular(6)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('${st.fontSize.toInt()}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  const Icon(Icons.arrow_drop_down, size: 18),
                ]),
              ),
            ),
            btn(Icons.text_increase, 'Chữ to hơn',
                () => setStyle(st.copyWith(fontSize: (st.fontSize + 2).clamp(kPosPrintMinFont, kPosPrintMaxFont)))),
            btn(Icons.format_bold, 'In đậm', () => setStyle(st.copyWith(bold: !st.bold)), active: st.bold),
            btn(Icons.title, 'IN HOA', () => setStyle(st.copyWith(uppercase: !st.uppercase)), active: st.uppercase),
            sep(),
          ],
          btn(Icons.arrow_upward, 'Đưa lên', onMoveUp),
          btn(Icons.arrow_downward, 'Đưa xuống', onMoveDown),
          btn(Icons.copy_all_outlined, 'Nhân bản khối', onDuplicate),
          btn(Icons.delete_outline, 'Xóa khối', onDelete),
        ]),
      ),
    );
  }
}

/// Căn lề & khoảng cách của khối: khoảng trên / dưới, thụt trái / phải — hiển thị kèm mm.
class PosPrintLayoutEditor extends StatelessWidget {
  const PosPrintLayoutEditor({
    super.key,
    required this.block,
    required this.paperSize,
    required this.onChanged,
    required this.readOnly,
  });

  final PosPrintBlock block;
  final String paperSize;
  final ValueChanged<PosPrintBlock> onChanged;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final st = block.style;
    final perMm = posPrintDotsPerMm(paperSize);
    String mm(double dots) => (dots / perMm).toStringAsFixed(1);
    final maxIndent = (posPrintDotsPerMm(paperSize) * 25).roundToDouble();

    Widget row(String label, IconData icon, double value, double max, PosPrintTextStyle Function(double) apply) {
      return Row(children: [
        Icon(icon, size: 18, color: SboxColors.slate600),
        const SizedBox(width: 6),
        SizedBox(width: 92, child: Text(tr(label), style: const TextStyle(fontSize: 13))),
        Expanded(
          child: Slider(
            value: value.clamp(0, max),
            min: 0,
            max: max,
            divisions: (max / 2).round(),
            label: '${mm(value)} mm',
            onChanged: readOnly ? null : (v) => onChanged(block.copyWith(style: apply(v.roundToDouble()))),
          ),
        ),
        SizedBox(width: 54, child: Text('${mm(value)} mm', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
      ]);
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(tr('Căn lề & khoảng cách'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        if (st.hasLayout && !readOnly)
          TextButton(
            onPressed: () => onChanged(block.copyWith(
                style: st.copyWith(spaceBefore: 0, spaceAfter: 0, indentLeft: 0, indentRight: 0))),
            child: Text(tr('Đặt lại')),
          ),
      ]),
      row('Cách trên', Icons.vertical_align_top, st.spaceBefore, 80, (v) => st.copyWith(spaceBefore: v)),
      row('Cách dưới', Icons.vertical_align_bottom, st.spaceAfter, 80, (v) => st.copyWith(spaceAfter: v)),
      row('Lề trái', Icons.format_indent_increase, st.indentLeft, maxIndent, (v) => st.copyWith(indentLeft: v)),
      row('Lề phải', Icons.format_indent_decrease, st.indentRight, maxIndent, (v) => st.copyWith(indentRight: v)),
    ]);
  }
}

/// Khối ảnh / logo: chọn ảnh, kiểu xử lý (logo nét / ảnh chụp), độ rộng, căn trái/giữa/phải.
class PosPrintImageBlockEditor extends StatefulWidget {
  const PosPrintImageBlockEditor({
    super.key,
    required this.block,
    required this.paperSize,
    required this.onChanged,
    required this.readOnly,
  });

  final PosPrintBlock block;
  final String paperSize;
  final ValueChanged<PosPrintBlock> onChanged;
  final bool readOnly;

  @override
  State<PosPrintImageBlockEditor> createState() => _PosPrintImageBlockEditorState();
}

class _PosPrintImageBlockEditorState extends State<PosPrintImageBlockEditor> {
  Uint8List? _raw;
  bool _photo = false;
  double _threshold = 160;
  bool _busy = false;

  int get _maxDots {
    final perMm = posPrintDotsPerMm(widget.paperSize);
    return (perMm * 80).round().clamp(240, 640);
  }

  Future<void> _pick() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = r?.files.single.bytes;
    if (bytes == null) return;
    _raw = bytes;
    await _apply();
  }

  Future<void> _apply() async {
    final raw = _raw;
    if (raw == null) return;
    setState(() => _busy = true);
    final data = preparePosPrintImage(raw, maxWidth: _maxDots, photo: _photo, threshold: _threshold.round());
    if (!mounted) return;
    setState(() => _busy = false);
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('Không đọc được ảnh (dùng PNG / JPG)'))));
      return;
    }
    widget.onChanged(widget.block.copyWith(imageData: data));
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.block;
    final bytes = decodePosPrintImageData(b.imageData);
    final ro = widget.readOnly;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: PosTheme.border),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: switch (b.style.align) {
          PosPrintTextAlign.left => Alignment.centerLeft,
          PosPrintTextAlign.right => Alignment.centerRight,
          _ => Alignment.center,
        },
        padding: const EdgeInsets.all(8),
        child: bytes == null
            ? Text(tr('Chưa có ảnh — bấm «Chọn ảnh» (logo PNG nền trong suốt in đẹp nhất)'),
                textAlign: TextAlign.center, style: const TextStyle(color: SboxColors.slate600, fontSize: 12))
            : FractionallySizedBox(
                widthFactor: b.imageWidthPct / 100,
                child: Image.memory(bytes, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
              ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: ro || _busy ? null : _pick,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.image_outlined, size: 18),
          label: Text(tr(bytes == null ? 'Chọn ảnh' : 'Đổi ảnh')),
        ),
        if (bytes != null)
          OutlinedButton.icon(
            onPressed: ro ? null : () => widget.onChanged(PosPrintBlock(type: PosPrintBlockType.image, style: b.style, imageWidthPct: b.imageWidthPct)),
            icon: const Icon(Icons.hide_image_outlined, size: 18),
            label: Text(tr('Bỏ ảnh')),
          ),
      ]),
      const SizedBox(height: 12),
      Text(tr('Độ rộng ảnh: ${b.imageWidthPct}% khổ in')),
      Slider(
        value: b.imageWidthPct.toDouble(),
        min: 10,
        max: 100,
        divisions: 18,
        label: '${b.imageWidthPct}%',
        onChanged: ro ? null : (v) => widget.onChanged(b.copyWith(imageWidthPct: v.round())),
      ),
      Text(tr('Vị trí ảnh'), style: const TextStyle(fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      SegmentedButton<PosPrintTextAlign>(
        segments: [
          ButtonSegment(value: PosPrintTextAlign.left, icon: const Icon(Icons.align_horizontal_left, size: 18), label: Text(tr('Trái'))),
          ButtonSegment(value: PosPrintTextAlign.center, icon: const Icon(Icons.align_horizontal_center, size: 18), label: Text(tr('Giữa'))),
          ButtonSegment(value: PosPrintTextAlign.right, icon: const Icon(Icons.align_horizontal_right, size: 18), label: Text(tr('Phải'))),
        ],
        selected: {b.style.align},
        onSelectionChanged: ro ? null : (s) => widget.onChanged(b.copyWith(style: b.style.copyWith(align: s.first))),
      ),
      if (_raw != null) ...[
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _photo,
          title: Text(tr('Ảnh chụp (giữ sắc độ bằng chấm điểm)')),
          subtitle: Text(tr('Tắt = logo nét đen trắng')),
          onChanged: ro
              ? null
              : (v) {
                  setState(() => _photo = v);
                  _apply();
                },
        ),
        if (!_photo) ...[
          Text(tr('Độ đậm logo: ${_threshold.round()}')),
          Slider(
            value: _threshold,
            min: 80,
            max: 230,
            divisions: 15,
            onChanged: ro ? null : (v) => setState(() => _threshold = v),
            onChangeEnd: ro ? null : (_) => _apply(),
          ),
        ],
      ],
      const SizedBox(height: 4),
      Text(
        tr('Ảnh được chuyển đen trắng đúng như máy in nhiệt sẽ in. Xem cột «Xem trước» để thấy kết quả thật.'),
        style: const TextStyle(fontSize: 12, color: SboxColors.slate600),
      ),
    ]);
  }
}
