import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../services/api_service.dart';
import '../notification_overlay.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Kết quả chọn hãng sau bảng so sánh cước.
class ShippingCarrierPick {
  const ShippingCarrierPick({
    required this.carrierCode,
    required this.carrierName,
    required this.fee,
    required this.weightGrams,
    required this.lengthCm,
    required this.widthCm,
    required this.heightCm,
    this.serviceCode,
    this.serviceName,
    this.shipFeePayer = 'shop',
    this.fixedShipFee,
  });

  final String carrierCode;
  final String carrierName;
  final double fee;
  final int weightGrams;
  final int lengthCm;
  final int widthCm;
  final int heightCm;
  final String? serviceCode;
  final String? serviceName;

  /// customer | shop | fixed
  final String shipFeePayer;
  final double? fixedShipFee;
}

/// Dialog: ước tính kiện → so sánh hãng → chọn 1 hãng.
Future<ShippingCarrierPick?> showShippingCompareDialog({
  required BuildContext context,
  required String orderId,
  required String orderNo,
  double? codAmount,
}) {
  return showModalBottomSheet<ShippingCarrierPick>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _ShippingCompareSheet(
      orderId: orderId,
      orderNo: orderNo,
      codAmount: codAmount,
    ),
  );
}

class _ShippingCompareSheet extends StatefulWidget {
  const _ShippingCompareSheet({
    required this.orderId,
    required this.orderNo,
    this.codAmount,
  });

  final String orderId;
  final String orderNo;
  final double? codAmount;

  @override
  State<_ShippingCompareSheet> createState() => _ShippingCompareSheetState();
}

class _ShippingCompareSheetState extends State<_ShippingCompareSheet> {
  final _api = ApiService();
  final _money = NumberFormat('#,##0', 'vi_VN');
  final _weightCtrl = TextEditingController(text: '500');
  final _lengthCtrl = TextEditingController(text: '10');
  final _widthCtrl = TextEditingController(text: '10');
  final _heightCtrl = TextEditingController(text: '10');
  final _fixedFeeCtrl = TextEditingController(text: '30000');

  bool _loading = true;
  bool _quoting = false;
  /// Mặc định mở — chỉ thu khi user bấm thu.
  bool _packageExpanded = true;
  String? _error;
  List<_QuoteRow> _quotes = const [];
  int _volWeight = 0;
  int _chargeable = 0;
  String _packageSource = '';
  List<String> _notes = const [];
  String? _selectedCode;

  /// customer | shop | fixed
  String _shipFeePayer = 'shop';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _lengthCtrl.dispose();
    _widthCtrl.dispose();
    _heightCtrl.dispose();
    _fixedFeeCtrl.dispose();
    super.dispose();
  }

  int _parseInt(TextEditingController c, int fallback) =>
      int.tryParse(c.text.trim()) ?? fallback;

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.comparePosShipping({
      'orderId': widget.orderId,
      if (widget.codAmount != null) 'codAmount': widget.codAmount,
    });
    if (!mounted) return;
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _loading = false;
        _error = res['message']?.toString() ?? 'Không so sánh được cước';
      });
      return;
    }
    _applyCompare(Map<String, dynamic>.from(res['data'] as Map));
    setState(() => _loading = false);
  }

  void _applyCompare(Map<String, dynamic> data) {
    final pkg = data['package'] is Map
        ? Map<String, dynamic>.from(data['package'] as Map)
        : (data['Package'] is Map
            ? Map<String, dynamic>.from(data['Package'] as Map)
            : <String, dynamic>{});
    final w = (pkg['weightGrams'] ?? pkg['WeightGrams'] as num?)?.toInt() ?? 500;
    final l = (pkg['lengthCm'] ?? pkg['LengthCm'] as num?)?.toInt() ?? 10;
    final wi = (pkg['widthCm'] ?? pkg['WidthCm'] as num?)?.toInt() ?? 10;
    final h = (pkg['heightCm'] ?? pkg['HeightCm'] as num?)?.toInt() ?? 10;
    _weightCtrl.text = '$w';
    _lengthCtrl.text = '$l';
    _widthCtrl.text = '$wi';
    _heightCtrl.text = '$h';
    _volWeight =
        (pkg['volumetricWeightGrams'] ?? pkg['VolumetricWeightGrams'] as num?)
                ?.toInt() ??
            0;
    _chargeable =
        (pkg['chargeableWeightGrams'] ?? pkg['ChargeableWeightGrams'] as num?)
                ?.toInt() ??
            w;
    _packageSource = (pkg['source'] ?? pkg['Source'] ?? '').toString();
    final notesRaw = pkg['notes'] ?? pkg['Notes'];
    _notes = notesRaw is List
        ? notesRaw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const [];

    final rawQuotes = data['quotes'] ?? data['Quotes'];
    final list = <_QuoteRow>[];
    if (rawQuotes is List) {
      for (final e in rawQuotes) {
        if (e is! Map) continue;
        final m = Map<String, dynamic>.from(e);
        list.add(_QuoteRow(
          code: (m['carrierCode'] ?? m['CarrierCode'] ?? '').toString(),
          name: (m['carrierName'] ?? m['CarrierName'] ?? '').toString(),
          success: m['success'] == true || m['Success'] == true,
          fee: (m['fee'] as num?)?.toDouble() ??
              (m['Fee'] as num?)?.toDouble() ??
              0,
          serviceName: (m['serviceName'] ?? m['ServiceName'])?.toString(),
          serviceCode: (m['serviceCode'] ?? m['ServiceCode'])?.toString(),
          message: (m['message'] ?? m['Message'])?.toString(),
        ));
      }
    }
    // Ưu tiên hãng báo giá OK; nội bộ xếp cuối nếu có hãng ngoài.
    list.sort((a, b) {
      if (a.success != b.success) return a.success ? -1 : 1;
      final aInternal = a.code.toLowerCase().contains('internal') ||
          a.name.toLowerCase().contains('nội bộ');
      final bInternal = b.code.toLowerCase().contains('internal') ||
          b.name.toLowerCase().contains('nội bộ');
      if (aInternal != bInternal) return aInternal ? 1 : -1;
      if (a.success && b.success) return a.fee.compareTo(b.fee);
      return a.name.compareTo(b.name);
    });
    _quotes = list;
    final prev = _selectedCode;
    final best = list.where((q) => q.success).toList();
    if (prev != null && best.any((q) => q.code == prev)) {
      _selectedCode = prev;
    } else {
      _selectedCode = best.isNotEmpty ? best.first.code : null;
    }
  }

  Future<void> _requote() async {
    setState(() {
      _quoting = true;
      _error = null;
    });
    final res = await _api.comparePosShipping({
      'orderId': widget.orderId,
      'weightGrams': _parseInt(_weightCtrl, 500),
      'lengthCm': _parseInt(_lengthCtrl, 10),
      'widthCm': _parseInt(_widthCtrl, 10),
      'heightCm': _parseInt(_heightCtrl, 10),
      if (widget.codAmount != null) 'codAmount': widget.codAmount,
    });
    if (!mounted) return;
    setState(() => _quoting = false);
    if (res['isSuccess'] != true || res['data'] is! Map) {
      setState(() {
        _error = res['message']?.toString() ?? 'Không so sánh được cước';
      });
      return;
    }
    setState(() => _applyCompare(Map<String, dynamic>.from(res['data'] as Map)));
  }

  void _confirm() {
    final code = _selectedCode;
    if (code == null || code.isEmpty) {
      NotificationOverlayManager().showWarning(
        title: 'Chưa chọn hãng',
        message: tr('Chọn một đơn vị vận chuyển trong bảng'),
      );
      return;
    }
    final row = _quotes.where((q) => q.code == code).firstOrNull;
    if (row == null || !row.success) {
      NotificationOverlayManager().showWarning(
        title: 'Hãng không khả dụng',
        message: row?.message ?? tr('Chọn hãng báo giá thành công'),
      );
      return;
    }
    double? fixedFee;
    if (_shipFeePayer == 'fixed') {
      final raw = _fixedFeeCtrl.text.trim().replaceAll(RegExp(r'[^\d]'), '');
      fixedFee = double.tryParse(raw);
      if (fixedFee == null || fixedFee <= 0) {
        NotificationOverlayManager().showWarning(
          title: 'Ship cố định',
          message: tr('Nhập số tiền phí ship cố định (vd 30000)'),
        );
        return;
      }
    }
    Navigator.pop(
      context,
      ShippingCarrierPick(
        carrierCode: row.code,
        carrierName: row.name,
        fee: row.fee,
        weightGrams: _chargeable > 0
            ? _chargeable
            : _parseInt(_weightCtrl, 500),
        lengthCm: _parseInt(_lengthCtrl, 10),
        widthCm: _parseInt(_widthCtrl, 10),
        heightCm: _parseInt(_heightCtrl, 10),
        serviceCode: row.serviceCode,
        serviceName: row.serviceName,
        shipFeePayer: _shipFeePayer,
        fixedShipFee: fixedFee,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final sheetH = MediaQuery.of(context).size.height * 0.92;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: sheetH,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('So sánh cước vận chuyển'),
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      tr('Đơn ${widget.orderNo} — chọn hãng rồi tạo mã'),
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              if (_loading)
                const Expanded(
                    child: Center(child: CircularProgressIndicator()))
              else ...[
                // Hãng vận chuyển lên trước — không bị che bởi kiện hàng / ai trả ship.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Row(
                    children: [
                      Text(tr('Đơn vị vận chuyển'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                      const Spacer(),
                      Text(
                        tr('${_quotes.where((q) => q.success).length}/${_quotes.length} khả dụng'),
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 12)),
                  ),
                Expanded(child: _quotesTable()),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: _compactPackageBar(),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                  child: _payerChips(),
                ),
                if (_shipFeePayer == 'fixed')
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: TextField(
                      controller: _fixedFeeCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: InputDecoration(
                        labelText: tr('Phí ship cố định (đ)'),
                        hintText: '30000',
                        isDense: true,
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr('Huỷ')),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: PosTheme.kiotBlue),
                          onPressed: _confirm,
                          icon: const Icon(Icons.local_shipping_outlined),
                          label: Text(tr('Tạo vận đơn')),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactPackageBar() {
    return Material(
      color: const Color(0xFFF5F5F4),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr('Kiện hàng · tính cước ${_chargeable > 0 ? _chargeable : _parseInt(_weightCtrl, 500)}g'
                        '${_volWeight > 0 ? ' (thể tích $_volWeight g)' : ''}'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _packageExpanded = !_packageExpanded),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  icon: Icon(
                    _packageExpanded
                        ? Icons.unfold_less
                        : Icons.unfold_more,
                    size: 18,
                  ),
                  label: Text(
                    tr(_packageExpanded ? 'Thu' : 'Mở'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            if (_packageExpanded) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _numField(_weightCtrl, 'KL (g)')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_lengthCtrl, 'Dài (cm)')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_widthCtrl, 'Rộng')),
                  const SizedBox(width: 6),
                  Expanded(child: _numField(_heightCtrl, 'Cao')),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: PosTheme.kiotBlue,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: _quoting ? null : _requote,
                  icon: _quoting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: Text(tr('Tính lại cước')),
                ),
              ),
              if (_notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _notes.take(2).join(' · '),
                  style:
                      TextStyle(fontSize: 10, color: Colors.orange.shade900),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _payerChips() {
    Widget chip(String value, String label) {
      final on = _shipFeePayer == value;
      return FilterChip(
        selected: on,
        label: Text(tr(label), style: const TextStyle(fontSize: 12)),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        selectedColor: PosTheme.kiotBlue.withOpacity(0.15),
        checkmarkColor: PosTheme.kiotBlue,
        onSelected: (_) => setState(() => _shipFeePayer = value),
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(tr('Phí ship:'),
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800)),
        chip('shop', 'Shop trả'),
        chip('customer', 'Khách trả'),
        chip('fixed', 'Cố định'),
      ],
    );
  }

  Widget _numField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: tr(label),
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      ),
    );
  }

  Widget _quotesTable() {
    if (_quotes.isEmpty) {
      return Center(
          child: Text(tr(
              'Chưa có báo giá — bật hãng trong Cài đặt vận chuyển')));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      itemCount: _quotes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (ctx, i) {
        final q = _quotes[i];
        final selected = _selectedCode == q.code;
        final successFees =
            _quotes.where((x) => x.success).map((x) => x.fee).toList();
        final cheapest = q.success &&
            successFees.isNotEmpty &&
            q.fee == successFees.reduce((a, b) => a < b ? a : b);
        return Material(
          color: selected
              ? PosTheme.kiotBlue.withOpacity(0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap:
                q.success ? () => setState(() => _selectedCode = q.code) : null,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? PosTheme.kiotBlue
                      : Colors.grey.shade300,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: q.success
                        ? (selected ? PosTheme.kiotBlue : Colors.grey)
                        : Colors.grey.shade400,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                q.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13),
                              ),
                            ),
                            if (cheapest)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  tr('Rẻ nhất'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.green.shade800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if ((q.serviceName ?? '').isNotEmpty)
                          Text(q.serviceName!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700)),
                        if (!q.success)
                          Text(
                            q.message ?? tr('Không báo được giá'),
                            style: TextStyle(
                                fontSize: 11, color: Colors.red.shade700),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    q.success
                        ? (q.fee <= 0
                            ? tr('Miễn phí')
                            : '${_money.format(q.fee)}đ')
                        : '—',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: q.success
                          ? PosTheme.kiotBlue
                          : Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _QuoteRow {
  const _QuoteRow({
    required this.code,
    required this.name,
    required this.success,
    required this.fee,
    this.serviceName,
    this.serviceCode,
    this.message,
  });

  final String code;
  final String name;
  final bool success;
  final double fee;
  final String? serviceName;
  final String? serviceCode;
  final String? message;
}
