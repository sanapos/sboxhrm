import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/pos_print_template.dart';
import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../widgets/pos/pos_barcode_label_dialog.dart';
import '../../widgets/pos/pos_scale_label_dialog.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_printer_settings_hub_screen.dart';
import 'pos_label_templates_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';

/// «In tem nhãn» (trang chủ): một chỗ cho mọi loại tem — tem hàng hóa, tem cân, tem thông số / tự soạn,
/// soạn mẫu tem (khổ tùy chỉnh, mã vạch / QR tự soạn) và máy in tem. Trước đây nằm rải ở Hàng hóa,
/// Nhập hàng, menu «Thêm» màn bán và Thiết lập → Mẫu in.
class PosLabelPrintHubScreen extends StatelessWidget {
  const PosLabelPrintHubScreen({super.key});

  Future<void> _printProducts(BuildContext context, String documentType) async {
    final picked = await showDialog<List<({PosProduct product, int qty})>>(
      context: context,
      builder: (_) => _PosLabelProductPicker(
        title: documentType == PosPrintDocumentTypes.specLabel
            ? 'Chọn hàng in tem thông số'
            : 'Chọn hàng in tem',
      ),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    await showPosBarcodeLabelDialog(
      context,
      [for (final p in picked) p.product],
      quantities: [for (final p in picked) p.qty],
      documentType: documentType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final actions = <_HubAction>[
      _HubAction(
        icon: Icons.qr_code_scanner,
        title: 'Tem hàng hóa',
        subtitle: 'Mã vạch, tên, giá — chọn hàng, số tem, khổ tem, bảng giá / biến thể',
        onTap: () => _printProducts(context, PosPrintDocumentTypes.barcodeLabel),
      ),
      _HubAction(
        icon: Icons.scale_outlined,
        title: 'Cân & in tem cân',
        subtitle: 'Hàng tươi bán theo kg / gram / lạng: khối lượng, đơn giá, thành tiền, mã cân, HSD',
        onTap: () => showPosScaleLabelDialog(context),
      ),
      _HubAction(
        icon: Icons.qr_code_2,
        title: 'Tem thông số / tự soạn',
        subtitle: 'Thương hiệu, KL, kích thước, bảo hành… khổ tùy chỉnh, mã QR nội dung tự soạn',
        onTap: () => _printProducts(context, PosPrintDocumentTypes.specLabel),
      ),
    ];
    final designs = <_HubAction>[
      _HubAction(
        icon: Icons.design_services_outlined,
        title: 'Mẫu tem (trình soạn tem)',
        subtitle: 'Tem sản phẩm · tem cân · tem thông số · tem ly / báo bếp — chọn khổ tem, kéo thả chữ, mã vạch, QR, ảnh',
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const PosLabelTemplatesScreen(),
        )),
      ),
      _HubAction(
        icon: Icons.print_outlined,
        title: 'Máy in tem',
        subtitle: 'Kết nối, khổ cuộn tem, khe giấy',
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => const PosPrinterSettingsHubScreen(),
        )),
      ),
    ];

    return Scaffold(
      backgroundColor: PosTheme.background,
      // Tiêu đề do khung trang chủ vẽ («In tem nhãn» trên thanh trên).
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _section('In tem'),
          _grid(context, actions),
          const SizedBox(height: 16),
          _section('Soạn mẫu & máy in'),
          _grid(context, designs),
        ],
      ),
    );
  }

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Text(
          tr(text),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: PosTheme.textSecondary),
        ),
      );

  Widget _grid(BuildContext context, List<_HubAction> items) => LayoutBuilder(
        builder: (context, c) {
          final cols = c.maxWidth >= 900 ? 3 : (c.maxWidth >= 560 ? 2 : 1);
          final w = (c.maxWidth - (cols - 1) * 10) / cols;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [for (final a in items) SizedBox(width: w, child: _HubCard(action: a))],
          );
        },
      );
}

class _HubAction {
  const _HubAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _HubCard extends StatelessWidget {
  const _HubCard({required this.action});
  final _HubAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PosTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: PosTheme.kiotBlueLight, borderRadius: BorderRadius.circular(10)),
                child: Icon(action.icon, color: PosTheme.kiotBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr(action.title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(
                      tr(action.subtitle),
                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: SboxColors.slate400),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chọn nhiều hàng + số tem từng hàng.
class _PosLabelProductPicker extends StatefulWidget {
  const _PosLabelProductPicker({required this.title});
  final String title;

  @override
  State<_PosLabelProductPicker> createState() => _PosLabelProductPickerState();
}

class _PosLabelProductPickerState extends State<_PosLabelProductPicker> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _money = NumberFormat('#,##0', 'vi_VN');
  List<PosProduct> _results = [];
  final _picked = <String, ({PosProduct product, int qty})>{};
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() => _loading = true);
    final res = await _api.getPosProducts(search: q.trim().isEmpty ? null : q.trim(), pageSize: 30);
    if (!mounted || seq != _seq) return;
    final raw = res['isSuccess'] == true && res['data'] is Map
        ? ((res['data'] as Map)['items'] as List? ?? const [])
        : const [];
    setState(() {
      _loading = false;
      _results = raw.map((e) => PosProduct.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    });
  }

  void _toggle(PosProduct p) {
    setState(() {
      if (_picked.remove(p.id) == null) _picked[p.id] = (product: p, qty: 1);
    });
  }

  void _setQty(String id, int qty) {
    final cur = _picked[id];
    if (cur == null) return;
    setState(() => _picked[id] = (product: cur.product, qty: qty.clamp(1, 999)));
  }

  @override
  Widget build(BuildContext context) {
    final total = _picked.values.fold<int>(0, (a, b) => a + b.qty);
    return AlertDialog(
      title: Text(tr(widget.title)),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            TextField(
              controller: _searchCtrl,
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 20),
                hintText: tr('Tìm tên, mã hàng, mã vạch'),
                border: const OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _results.isEmpty && !_loading
                  ? Center(child: Text(tr('Không có hàng phù hợp'), style: const TextStyle(color: PosTheme.textSecondary)))
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = _results[i];
                        final sel = _picked[p.id];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                          leading: Checkbox(value: sel != null, onChanged: (_) => _toggle(p)),
                          title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                            '${p.productCode}${(p.barcode ?? '').isNotEmpty ? ' · ${p.barcode}' : ''}'
                            ' · ${_money.format(p.basePrice)}đ',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: sel == null
                              ? null
                              : Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                                    onPressed: () => _setQty(p.id, sel.qty - 1),
                                  ),
                                  Text('${sel.qty}', style: const TextStyle(fontWeight: FontWeight.w700)),
                                  IconButton(
                                    visualDensity: VisualDensity.compact,
                                    icon: const Icon(Icons.add_circle_outline, size: 20),
                                    onPressed: () => _setQty(p.id, sel.qty + 1),
                                  ),
                                ]),
                          onTap: () => _toggle(p),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Hủy'))),
        FilledButton(
          onPressed: _picked.isEmpty ? null : () => Navigator.pop(context, _picked.values.toList()),
          child: Text(tr(_picked.isEmpty ? 'Chọn hàng' : 'Tiếp tục · ${_picked.length} hàng, $total tem')),
        ),
      ],
    );
  }
}
