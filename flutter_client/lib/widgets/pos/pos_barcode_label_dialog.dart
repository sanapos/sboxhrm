import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/pos_product.dart';
import '../../utils/pos_barcode_print.dart';
import 'pos_pdf_preview_dialog.dart';
import 'pos_theme.dart';

/// Dialog chọn loại giấy in tem mã — giao diện kiểu KiotViet.
Future<void> showPosBarcodeLabelDialog(
  BuildContext context,
  List<PosProduct> products,
) async {
  if (products.isEmpty) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PosBarcodeLabelDialog(products: products),
  );
}

class _PosBarcodeLabelDialog extends StatefulWidget {
  const _PosBarcodeLabelDialog({required this.products});

  final List<PosProduct> products;

  @override
  State<_PosBarcodeLabelDialog> createState() => _PosBarcodeLabelDialogState();
}

class _PosBarcodeLabelDialogState extends State<_PosBarcodeLabelDialog> {
  int _copies = 1;
  late final TextEditingController _copiesCtrl;
  PosBarcodeCodeField _codeField = PosBarcodeCodeField.productCode;
  PosBarcodePriceMode _priceMode = PosBarcodePriceMode.withVnd;
  PosBarcodeUnitMode _unitMode = PosBarcodeUnitMode.withoutUnit;
  PosBarcodeStoreMode _storeMode = PosBarcodeStoreMode.withoutStore;
  PosBarcodeLabelTemplate? _selectedTemplate;

  @override
  void initState() {
    super.initState();
    _copiesCtrl = TextEditingController(text: '1');
  }

  @override
  void dispose() {
    _copiesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (size.width * 0.92).clamp(720, 1100),
          maxHeight: size.height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 260, child: _buildSidebar()),
                  const VerticalDivider(width: 1),
                  Expanded(child: _buildTemplateGrid()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: PosTheme.border)),
      ),
      child: Row(
        children: [
          const Text(
            'Chọn loại giấy in tem mã',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel('Số lượng in'),
          TextField(
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: PosTheme.inputDecoration(label: ''),
            controller: _copiesCtrl,
            onChanged: (v) {
              final n = int.tryParse(v);
              if (n != null && n >= 1 && n <= 5000) setState(() => _copies = n);
            },
          ),
          const SizedBox(height: 12),
          _dropdown<PosBarcodeCodeField>(
            value: _codeField,
            items: PosBarcodeCodeField.values,
            label: (v) => v.label,
            onChanged: (v) => setState(() => _codeField = v!),
          ),
          const SizedBox(height: 10),
          _dropdown<String>(
            value: 'general',
            items: const ['general'],
            label: (v) => 'Bảng giá chung',
            onChanged: (_) {},
          ),
          const SizedBox(height: 10),
          _dropdown<PosBarcodePriceMode>(
            value: _priceMode,
            items: PosBarcodePriceMode.values,
            label: (v) => v.label,
            onChanged: (v) => setState(() => _priceMode = v!),
          ),
          const SizedBox(height: 10),
          _dropdown<PosBarcodeUnitMode>(
            value: _unitMode,
            items: PosBarcodeUnitMode.values,
            label: (v) => v.label,
            onChanged: (v) => setState(() => _unitMode = v!),
          ),
          const SizedBox(height: 10),
          _dropdown<PosBarcodeStoreMode>(
            value: _storeMode,
            items: PosBarcodeStoreMode.values,
            label: (v) => v.label,
            onChanged: (v) => setState(() => _storeMode = v!),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _exportExcel,
            icon: const Icon(Icons.table_chart_outlined, size: 18),
            label: const Text('Xuất file Excel'),
            style: OutlinedButton.styleFrom(
              foregroundColor: PosTheme.kiotBlue,
              side: const BorderSide(color: PosTheme.kiotBlue),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Lưu ý:',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '• Nếu mã vạch in không đầy đủ, hãy chọn khổ giấy lớn hơn hoặc rút ngắn mã hàng.\n'
            '• Phần mềm hỗ trợ in tối đa 5000 tem/lần.\n'
            '• Tránh ký tự đặc biệt hoặc dấu trong mã vạch.',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _fieldLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(text, style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: PosTheme.inputDecoration(label: ''),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(label(e), style: const TextStyle(fontSize: 12))))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTemplateGrid() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: posBarcodeLabelTemplates.map((t) {
          final selected = _selectedTemplate?.id == t.id;
          return SizedBox(
            width: 200,
            child: Column(
              children: [
                Container(
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected ? PosTheme.kiotBlue : PosTheme.border,
                      width: selected ? 2 : 1,
                    ),
                  ),
                  child: _templatePreview(t),
                ),
                const SizedBox(height: 8),
                Text(
                  t.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                ),
                Text(
                  t.sizeLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 10, color: PosTheme.textSecondary),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => _preview(t),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: PosTheme.kiotBlue,
                      side: const BorderSide(color: PosTheme.kiotBlue),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    child: const Text('Xem bản in', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _templatePreview(PosBarcodeLabelTemplate t) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.qr_code_2, size: 36, color: Colors.grey.shade500),
          const SizedBox(height: 4),
          Text(
            t.cols > 1 ? '${t.cols} nhãn/hàng' : '1 nhãn',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  PosBarcodePrintOptions _options(PosBarcodeLabelTemplate template) =>
      PosBarcodePrintOptions(
        template: template,
        copiesPerProduct: _copies,
        codeField: _codeField,
        priceMode: _priceMode,
        unitMode: _unitMode,
        storeMode: _storeMode,
      );

  Future<void> _preview(PosBarcodeLabelTemplate template) async {
    setState(() => _selectedTemplate = template);
    try {
      final bytes = await buildPosBarcodeLabelPdfBytes(
        widget.products,
        options: _options(template),
      );
      if (!mounted) return;
      await showPosPdfPreviewDialog(
        context,
        bytes: bytes,
        title: 'Xem bản in — ${template.name}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không tạo được bản in: $e')),
      );
    }
  }

  Future<void> _exportExcel() async {
    if (_selectedTemplate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chọn mẫu giấy và bấm «Xem bản in» trước')),
      );
      return;
    }
    await exportPosBarcodeLabelsExcel(
      widget.products,
      options: _options(_selectedTemplate!),
    );
  }
}
