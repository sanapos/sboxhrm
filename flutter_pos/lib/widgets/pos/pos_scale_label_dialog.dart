import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_product.dart';
import '../../services/api_service.dart';
import '../../utils/pos_barcode_print.dart';
import '../../utils/pos_scale_barcode.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../notification_overlay.dart';
import 'pos_barcode_label_dialog.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Cân & in tem hàng cân tại quầy (rau, thịt, cá… bán theo kg / mét):
/// nhập khối lượng từng gói → tính tiền theo đơn giá → in tem mã cân EAN-13
/// (đầu 20–29 + PLU + khối lượng) mà màn bán hàng đọc lại đúng hàng, đúng số lượng.
Future<void> showPosScaleLabelDialog(BuildContext context, {PosProduct? product}) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _PosScaleLabelDialog(initial: product),
  );
}

class _Pack {
  _Pack(this.qty);
  final double qty;
}

class _PosScaleLabelDialog extends StatefulWidget {
  const _PosScaleLabelDialog({this.initial});
  final PosProduct? initial;

  @override
  State<_PosScaleLabelDialog> createState() => _PosScaleLabelDialogState();
}

class _PosScaleLabelDialogState extends State<_PosScaleLabelDialog> {
  final _api = ApiService();
  final _money = NumberFormat('#,###', 'vi_VN');
  final _qtyFmt = NumberFormat('#,##0.###', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yy');
  final _searchCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _shelfCtrl = TextEditingController();
  final _qtyFocus = FocusNode();

  PosProduct? _product;
  List<PosProduct> _results = [];
  bool _searching = false;
  PosScaleBarcodeConfig _scale = const PosScaleBarcodeConfig();
  bool _scaleLoaded = false;
  bool _enableScale = true;
  bool _busy = false;
  final List<_Pack> _packs = [];

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) _select(widget.initial!);
    _loadScaleConfig();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _shelfCtrl.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadScaleConfig() async {
    final r = await PosSellSettingsHelper(_api).load();
    if (!mounted) return;
    setState(() {
      _scale = PosScaleBarcodeConfig.parse(r.settings?.extraJson);
      _scaleLoaded = true;
    });
  }

  void _select(PosProduct p) {
    setState(() {
      _product = p;
      _results = [];
      _priceCtrl.text = '${p.basePrice.round()}';
      _shelfCtrl.text = (p.packShelfLifeDays ?? 0) > 0 ? '${p.packShelfLifeDays}' : '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _qtyFocus.requestFocus());
  }

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    setState(() => _searching = true);
    final res = await _api.getPosProducts(search: q.trim(), pageSize: 20);
    if (!mounted) return;
    final raw = res['isSuccess'] == true && res['data'] is Map
        ? ((res['data'] as Map)['items'] as List? ?? const [])
        : const [];
    setState(() {
      _searching = false;
      _results = raw.map((e) => PosProduct.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    });
  }

  double get _unitPrice =>
      double.tryParse(_priceCtrl.text.replaceAll('.', '').replaceAll(',', '').trim()) ?? 0;

  String get _unit {
    final u = _product?.baseUnitName.trim() ?? '';
    return u.isEmpty ? 'kg' : u;
  }

  double _amountOf(double qty) => (qty * _unitPrice).roundToDouble();

  void _addPack() {
    final q = double.tryParse(_qtyCtrl.text.trim().replaceAll(',', '.'));
    if (q == null || q <= 0) return;
    setState(() {
      _packs.add(_Pack(q));
      _qtyCtrl.clear();
    });
    _qtyFocus.requestFocus();
  }

  Future<void> _print() async {
    final p = _product;
    if (p == null || _packs.isEmpty) return;
    if (_unitPrice <= 0) {
      NotificationOverlayManager().showWarning(title: 'Thiếu đơn giá', message: tr('Nhập đơn giá / $_unit'));
      return;
    }
    setState(() => _busy = true);
    try {
      // 1) PLU: chưa có → hệ thống gán số nhỏ nhất còn trống.
      var plu = p.scalePlu;
      if (plu == null || plu.isEmpty) {
        final r = await _api.assignPosProductScalePlu(p.id);
        plu = r['isSuccess'] == true && r['data'] is Map ? '${(r['data'] as Map)['scalePlu'] ?? ''}' : '';
        if (plu.isEmpty) {
          NotificationOverlayManager().showError(
              title: 'Lỗi', message: r['message']?.toString() ?? tr('Không gán được mã PLU'));
          return;
        }
        _product = p.copyWith(scalePlu: plu);
      }

      // 2) Bật đọc tem cân ở màn bán hàng (bắt buộc để quét được tem).
      var cfg = _scale;
      if (!cfg.enabled && _enableScale) {
        final helper = PosSellSettingsHelper(_api);
        final cur = await helper.load();
        if (cur.settings != null) {
          cfg = cfg.copyWith(enabled: true);
          final saved = await helper.save(
              cur.settings!.copyWith(extraJson: cfg.mergeIntoExtraJson(cur.settings!.extraJson)));
          if (saved.settings == null) {
            NotificationOverlayManager().showWarning(
                title: 'Chưa bật đọc tem cân', message: saved.error ?? '');
          } else {
            _scale = cfg;
          }
        }
      }
      final encodeCfg = cfg.enabled ? cfg : cfg.copyWith(enabled: true);

      // 3) Tem tạm cho từng gói → dùng chung hộp in tem (máy tem / PDF / Excel).
      final packedOn = DateTime.now();
      final shelf = int.tryParse(_shelfCtrl.text.trim());
      final hsd = shelf != null && shelf > 0 ? packedOn.add(Duration(days: shelf)) : null;
      final labels = <PosProduct>[];
      for (final pack in _packs) {
        final amount = _amountOf(pack.qty);
        final value = encodeCfg.isWeight ? pack.qty : amount;
        final code = encodeCfg.encode(plu, value);
        if (code == null) {
          NotificationOverlayManager().showError(
            title: 'Không tạo được mã cân',
            message: encodeCfg.isWeight
                ? tr('Khối lượng tối đa ${_qtyFmt.format(encodeCfg.maxValue)} $_unit, PLU tối đa ${encodeCfg.pluDigits} số')
                : tr('Mã cân đang để «thành tiền», tối đa ${_money.format(encodeCfg.maxValue)}đ — đổi sang «trọng lượng» ở Thiết lập ngành hàng'),
          );
          return;
        }
        final label = p.copyWith(barcode: code, basePrice: amount, baseUnitName: '');
        posLabelDetail[label] = [
          '${_qtyFmt.format(pack.qty)} $_unit × ${_money.format(_unitPrice)}đ',
          'ĐG ${_dateFmt.format(packedOn)}',
          if (hsd != null) 'HSD ${_dateFmt.format(hsd)}',
        ].join(' · ');
        labels.add(label);
      }
      if (!mounted) return;
      await showPosBarcodeLabelDialog(context, labels);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _product;
    final total = _packs.fold<double>(0, (s, x) => s + _amountOf(x.qty));
    return AlertDialog(
      title: Text(tr('Cân & in tem hàng cân')),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (p == null) ...[
                TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  decoration: PosTheme.inputDecoration(label: 'Tìm hàng (tên / mã / PLU)', hint: 'vd: rau mồng tơi, thịt ba chỉ'),
                  onChanged: _search,
                ),
                if (_searching) const LinearProgressIndicator(minHeight: 2),
                for (final r in _results.take(8))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(tr('${r.productCode} · ${_money.format(r.basePrice.round())}đ/${r.baseUnitName}'
                        '${(r.scalePlu ?? '').isNotEmpty ? ' · PLU ${r.scalePlu}' : ''}')),
                    onTap: () => _select(r),
                  ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(p.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    if (widget.initial == null)
                      TextButton(
                        onPressed: () => setState(() {
                          _product = null;
                          _packs.clear();
                        }),
                        child: Text(tr('Đổi hàng')),
                      ),
                  ],
                ),
                Text(
                  tr((p.scalePlu ?? '').isNotEmpty ? 'PLU ${p.scalePlu}' : 'Chưa có PLU — tự gán khi in'),
                  style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: PosTheme.inputDecoration(label: 'Đơn giá / $_unit'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _shelfCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: PosTheme.inputDecoration(label: 'Dùng trong (ngày)', hint: 'Trống = không in HSD'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _qtyCtrl,
                        focusNode: _qtyFocus,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                        decoration: PosTheme.inputDecoration(label: 'Khối lượng gói ($_unit)', hint: 'vd 0,45 — Enter để thêm'),
                        onSubmitted: (_) => _addPack(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      style: PosTheme.filledButtonStyle,
                      onPressed: _addPack,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('Thêm gói')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _packs.length; i++)
                  Row(
                    children: [
                      Text('${i + 1}.', style: const TextStyle(color: PosTheme.textSecondary)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${_qtyFmt.format(_packs[i].qty)} $_unit')),
                      Text(tr('${_money.format(_amountOf(_packs[i].qty))}đ'),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _packs.removeAt(i)),
                      ),
                    ],
                  ),
                if (_packs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(tr('${_packs.length} tem · tổng ${_money.format(total)}đ'),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                if (_scaleLoaded && !_scale.enabled)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _enableScale,
                    onChanged: (v) => setState(() => _enableScale = v ?? true),
                    title: Text(tr('Bật đọc tem cân ở màn bán hàng')),
                    subtitle: Text(tr('Cần bật để quét tem này khi thanh toán')),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng'))),
        FilledButton.icon(
          style: PosTheme.filledButtonStyle,
          onPressed: p == null || _packs.isEmpty || _busy ? null : _print,
          icon: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.print_outlined, size: 18),
          label: Text(tr('In ${_packs.length} tem')),
        ),
      ],
    );
  }
}
