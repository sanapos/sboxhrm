import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/pos_product.dart';
import '../../providers/permission_provider.dart';
import '../../services/api_service.dart';
import '../../utils/pos_promotion_engine.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Khuyến mãi tự áp ở màn bán (siêu thị / cửa hàng).
class PosPromotionsScreen extends StatefulWidget {
  const PosPromotionsScreen({super.key});

  @override
  State<PosPromotionsScreen> createState() => _PosPromotionsScreenState();
}

class _PosPromotionsScreenState extends State<PosPromotionsScreen> {
  final _api = ApiService();
  List<PosPromotion> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosPromotions();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = res['isSuccess'] == true && res['data'] is List
          ? (res['data'] as List).map((e) => PosPromotion.fromJson(Map<String, dynamic>.from(e as Map))).toList()
          : [];
    });
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: res['message']?.toString() ?? 'Không tải được');
    }
  }

  Future<void> _edit([PosPromotion? p]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PosPromotionEditorPage(existing: p)),
    );
    if (saved == true) _load();
  }

  Future<void> _toggle(PosPromotion p, bool on) async {
    final body = p.toSaveJson()..['isActive'] = on;
    final res = await _api.savePosPromotion(p.id, body);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      _load();
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: res['message']?.toString() ?? '');
    }
  }

  Future<void> _delete(PosPromotion p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Xoá chương trình «${p.name}»?')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Huỷ'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Xoá'))),
        ],
      ),
    );
    if (ok != true) return;
    final res = await _api.deletePosPromotion(p.id);
    if (!mounted) return;
    if (res['isSuccess'] == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final perm = Provider.of<PermissionProvider>(context);
    final canEdit = perm.canEdit('PosProducts') || perm.canCreate('PosProducts');
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Khuyến mãi')),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const PosPromotionReportScreen())),
            icon: const Icon(Icons.insights_outlined, size: 18),
            label: Text(tr('Hiệu quả')),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text(tr('Tạo chương trình')),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('Chưa có chương trình khuyến mãi.\nVí dụ: giờ vàng 18h–21h rau cá giảm 30%, mua 2 tặng 1, '
                          'mua từ 5 cái giảm 20%, hóa đơn từ 500.000đ giảm 50.000đ…'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final p = _items[i];
                    final live = p.isLiveAt(now, hasCustomer: true);
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: canEdit ? () => _edit(p) : null,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Flexible(
                                        child: Text(p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      ),
                                      if (live) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.green.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(tr('Đang chạy'),
                                              style: TextStyle(fontSize: 11, color: Colors.green.shade800)),
                                        ),
                                      ],
                                    ]),
                                    const SizedBox(height: 2),
                                    Text(
                                      tr('${PosPromotionTypes.label(p.type)} · ${p.scheduleLabel}'
                                          '${_dateRange(p)}'),
                                      style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              if (canEdit) Switch(value: p.isActive, onChanged: (v) => _toggle(p, v)),
                              if (canEdit)
                                IconButton(
                                  tooltip: tr('Xoá'),
                                  icon: const Icon(Icons.delete_outline, size: 20),
                                  onPressed: () => _delete(p),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _dateRange(PosPromotion p) {
    if (p.validFrom == null && p.validTo == null) return '';
    final f = DateFormat('dd/MM/yy');
    return ' · ${p.validFrom == null ? '…' : f.format(p.validFrom!)} → ${p.validTo == null ? '…' : f.format(p.validTo!)}';
  }
}

/// Tạo / sửa chương trình khuyến mãi.
class PosPromotionEditorPage extends StatefulWidget {
  const PosPromotionEditorPage({super.key, this.existing});
  final PosPromotion? existing;

  @override
  State<PosPromotionEditorPage> createState() => _PosPromotionEditorPageState();
}

class _PosPromotionEditorPageState extends State<PosPromotionEditorPage> {
  final _api = ApiService();
  final _dateFmt = DateFormat('dd/MM/yyyy');
  late final TextEditingController _name;
  late final TextEditingController _note;
  final Map<String, TextEditingController> _num = {};
  late String _type;
  int _priority = 0;
  bool _stackable = false;
  bool _membersOnly = false;
  bool _active = true;
  DateTime? _from;
  DateTime? _to;
  int _days = 0;
  TimeOfDay? _timeFrom;
  TimeOfDay? _timeTo;
  String _scope = 'all';
  bool _mixed = false;
  final Set<String> _categoryIds = {};
  List<PosCatalogItem> _categories = [];
  /// Hàng trong phạm vi áp dụng (id → tên).
  final Map<String, String> _products = {};
  ({String id, String name})? _gift;
  ({String id, String name})? _addon;
  List<({TextEditingController min, TextEditingController pct})> _tiers = [];
  bool _saving = false;

  TextEditingController _c(String key) => _num.putIfAbsent(key, () => TextEditingController());

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _name = TextEditingController(text: p?.name ?? '');
    _note = TextEditingController(text: p?.note ?? '');
    _type = p?.type ?? PosPromotionTypes.timeDiscount;
    _priority = p?.priority ?? 0;
    _stackable = p?.stackable ?? false;
    _membersOnly = p?.membersOnly ?? false;
    _active = p?.isActive ?? true;
    _from = p?.validFrom;
    _to = p?.validTo;
    _days = p?.daysOfWeekMask ?? 0;
    if (p?.timeFromMinutes != null) {
      _timeFrom = TimeOfDay(hour: p!.timeFromMinutes! ~/ 60, minute: p.timeFromMinutes! % 60);
    }
    if (p?.timeToMinutes != null) {
      _timeTo = TimeOfDay(hour: p!.timeToMinutes! ~/ 60, minute: p.timeToMinutes! % 60);
    }
    final cfg = p?.config ?? const <String, dynamic>{};
    for (final k in ['percent', 'amountPerUnit', 'salePrice', 'buyQty', 'getQty', 'giftPercent', 'comboQty',
      'comboPrice', 'minBill', 'billPercent', 'billAmount', 'maxDiscount', 'addonPrice', 'maxPerTrigger',
      'nearExpiryDays']) {
      final v = cfg[k];
      if (v is num && v != 0) _c(k).text = v == v.roundToDouble() ? v.toInt().toString() : '$v';
    }
    _mixed = cfg['mixed'] == true;
    final t = cfg['target'] is Map ? Map<String, dynamic>.from(cfg['target'] as Map) : const <String, dynamic>{};
    _scope = '${t['scope'] ?? 'all'}';
    _categoryIds.addAll(((t['categoryIds'] as List?) ?? const []).map((e) => '$e'));
    for (final e in (t['products'] as List?) ?? const []) {
      if (e is Map) {
        _products['${e['id']}'] = '${e['name'] ?? e['id']}';
      } else {
        _products['$e'] = '$e';
      }
    }
    if (cfg['giftProductId'] != null) {
      _gift = (id: '${cfg['giftProductId']}', name: '${cfg['giftProductName'] ?? ''}');
    }
    if (cfg['addonProductId'] != null) {
      _addon = (id: '${cfg['addonProductId']}', name: '${cfg['addonProductName'] ?? ''}');
    }
    _tiers = [
      for (final e in (cfg['tiers'] as List?) ?? const [])
        if (e is Map)
          (
            min: TextEditingController(text: '${(e['minQty'] as num?)?.toInt() ?? ''}'),
            pct: TextEditingController(text: '${e['percent'] ?? ''}'),
          ),
    ];
    if (_tiers.isEmpty) _tiers.add((min: TextEditingController(), pct: TextEditingController()));
    if (_type == PosPromotionTypes.buyXGetY) {
      if (_c('buyQty').text.isEmpty) _c('buyQty').text = '2';
      if (_c('getQty').text.isEmpty) _c('getQty').text = '1';
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    for (final c in _num.values) {
      c.dispose();
    }
    for (final t in _tiers) {
      t.min.dispose();
      t.pct.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final res = await _api.getPosProductCategories();
    if (!mounted || res['isSuccess'] != true || res['data'] is! List) return;
    setState(() {
      _categories = (res['data'] as List)
          .map((e) => PosCatalogItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    });
  }

  double _n(String k) => double.tryParse(_c(k).text.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0;

  Map<String, dynamic> _config() {
    final cfg = <String, dynamic>{};
    void put(String k) {
      final v = _n(k);
      if (v != 0) cfg[k] = v;
    }

    final usesTarget = _type != PosPromotionTypes.billDiscount && _type != PosPromotionTypes.nearExpiry;
    if (usesTarget) {
      cfg['target'] = {
        'scope': _scope,
        if (_scope == 'categories') 'categoryIds': _categoryIds.toList(),
        if (_scope == 'products')
          'products': [for (final e in _products.entries) {'id': e.key, 'name': e.value}],
      };
    }
    switch (_type) {
      case PosPromotionTypes.timeDiscount:
        put('percent');
        put('amountPerUnit');
        put('salePrice');
      case PosPromotionTypes.nearExpiry:
        put('percent');
        cfg['nearExpiryDays'] = _n('nearExpiryDays') > 0 ? _n('nearExpiryDays').toInt() : 3;
      case PosPromotionTypes.qtyDiscount:
        cfg['mixed'] = _mixed;
        cfg['tiers'] = [
          for (final t in _tiers)
            if ((int.tryParse(t.min.text.trim()) ?? 0) > 0 && (double.tryParse(t.pct.text.trim()) ?? 0) > 0)
              {'minQty': int.parse(t.min.text.trim()), 'percent': double.parse(t.pct.text.trim())},
        ];
      case PosPromotionTypes.buyXGetY:
        put('buyQty');
        put('getQty');
        cfg['giftPercent'] = _n('giftPercent') > 0 ? _n('giftPercent') : 100;
        if (_gift != null) {
          cfg['giftProductId'] = _gift!.id;
          cfg['giftProductName'] = _gift!.name;
        }
      case PosPromotionTypes.comboPrice:
        put('comboQty');
        put('comboPrice');
      case PosPromotionTypes.billDiscount:
        put('minBill');
        put('billPercent');
        put('billAmount');
        put('maxDiscount');
      case PosPromotionTypes.addonPrice:
        put('addonPrice');
        cfg['maxPerTrigger'] = _n('maxPerTrigger') > 0 ? _n('maxPerTrigger') : 1;
        if (_addon != null) {
          cfg['addonProductId'] = _addon!.id;
          cfg['addonProductName'] = _addon!.name;
        }
    }
    return cfg;
  }

  String? _validate(Map<String, dynamic> cfg) {
    if (_name.text.trim().isEmpty) return 'Nhập tên chương trình';
    if (_scope == 'products' && cfg['target'] != null && _products.isEmpty) return 'Chọn ít nhất 1 mặt hàng';
    if (_scope == 'categories' && cfg['target'] != null && _categoryIds.isEmpty) return 'Chọn ít nhất 1 nhóm hàng';
    switch (_type) {
      case PosPromotionTypes.timeDiscount:
        if (_n('percent') <= 0 && _n('amountPerUnit') <= 0 && _n('salePrice') <= 0) {
          return 'Nhập % giảm, số tiền giảm / đơn vị hoặc giá bán khuyến mãi';
        }
      case PosPromotionTypes.nearExpiry:
        if (_n('percent') <= 0) return 'Nhập % giảm';
      case PosPromotionTypes.qtyDiscount:
        if ((cfg['tiers'] as List).isEmpty) return 'Nhập ít nhất 1 mức: mua từ … giảm …%';
      case PosPromotionTypes.buyXGetY:
        if (_n('buyQty') <= 0 || _n('getQty') <= 0) return 'Nhập số lượng mua và số lượng tặng';
      case PosPromotionTypes.comboPrice:
        if (_n('comboQty') < 2 || _n('comboPrice') <= 0) return 'Nhập số món (≥ 2) và giá đồng giá';
      case PosPromotionTypes.billDiscount:
        if (_n('billPercent') <= 0 && _n('billAmount') <= 0) return 'Nhập % hoặc số tiền giảm';
      case PosPromotionTypes.addonPrice:
        if (_addon == null) return 'Chọn hàng mua kèm';
    }
    return null;
  }

  Future<void> _save() async {
    final cfg = _config();
    final err = _validate(cfg);
    if (err != null) {
      NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: tr(err));
      return;
    }
    final promo = PosPromotion(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      type: _type,
      priority: _priority,
      stackable: _stackable,
      validFrom: _from,
      validTo: _to,
      daysOfWeekMask: _days,
      timeFromMinutes: _timeFrom == null || _timeTo == null ? null : _timeFrom!.hour * 60 + _timeFrom!.minute,
      timeToMinutes: _timeFrom == null || _timeTo == null ? null : _timeTo!.hour * 60 + _timeTo!.minute,
      membersOnly: _membersOnly,
      config: cfg,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      isActive: _active,
    );
    setState(() => _saving = true);
    final res = await _api.savePosPromotion(widget.existing?.id, promo.toSaveJson());
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true) {
      Navigator.pop(context, true);
    } else {
      NotificationOverlayManager().showError(title: 'Lỗi', message: res['message']?.toString() ?? 'Không lưu được');
    }
  }

  Future<({String id, String name})?> _pickProduct() async {
    final picked = await showDialog<PosProduct>(context: context, builder: (_) => const _ProductSearchDialog());
    return picked == null ? null : (id: picked.id, name: picked.name);
  }

  Widget _numField(String key, String label, {String? hint, String? suffix}) => TextField(
        controller: _c(key),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        decoration: PosTheme.inputDecoration(label: suffix == null ? label : '$label ($suffix)', hint: hint),
      );

  Widget _row(List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );

  Widget _section(String title, List<Widget> children) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );

  Widget _pickTile(String label, ({String id, String name})? v, void Function(({String id, String name})?) set) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(tr(v == null ? label : v.name)),
        subtitle: v == null ? null : Text(tr(label)),
        trailing: Wrap(children: [
          if (v != null) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => set(null))),
          TextButton(
            onPressed: () async {
              final p = await _pickProduct();
              if (p != null) setState(() => set(p));
            },
            child: Text(tr('Chọn hàng')),
          ),
        ]),
      );

  Widget _ruleSection() {
    switch (_type) {
      case PosPromotionTypes.timeDiscount:
        return _section('Mức giảm (chọn 1 cách)', [
          _row([
            _numField('percent', 'Giảm', suffix: '%'),
            _numField('amountPerUnit', 'Giảm mỗi đơn vị', suffix: 'đ'),
          ]),
          _row([_numField('salePrice', 'Hoặc bán đồng giá', suffix: 'đ', hint: 'vd 9.000đ / sp')]),
        ]);
      case PosPromotionTypes.nearExpiry:
        return _section('Hàng cận hạn', [
          _row([
            _numField('nearExpiryDays', 'Lô còn ≤', suffix: 'ngày', hint: 'Mặc định 3'),
            _numField('percent', 'Giảm', suffix: '%'),
          ]),
          Text(tr('Áp cho hàng có lô sắp hết hạn (theo HSD nhập kho), tự cập nhật mỗi lần mở màn bán.'),
              style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          const SizedBox(height: 8),
        ]);
      case PosPromotionTypes.qtyDiscount:
        return _section('Mức giảm theo số lượng', [
          for (var i = 0; i < _tiers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _tiers[i].min,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: PosTheme.inputDecoration(label: 'Mua từ (sp)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _tiers[i].pct,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: PosTheme.inputDecoration(label: 'Giảm (%)'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: _tiers.length <= 1 ? null : () => setState(() => _tiers.removeAt(i)),
                ),
              ]),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _tiers.add((min: TextEditingController(), pct: TextEditingController()))),
              icon: const Icon(Icons.add, size: 18),
              label: Text(tr('Thêm mức')),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _mixed,
            onChanged: (v) => setState(() => _mixed = v),
            title: Text(tr('Cộng dồn số lượng các mặt hàng trong phạm vi')),
            subtitle: Text(tr('Tắt: tính riêng từng mặt hàng')),
          ),
        ]);
      case PosPromotionTypes.buyXGetY:
        return _section('Mua … tặng …', [
          _row([
            _numField('buyQty', 'Mua', suffix: 'sp'),
            _numField('getQty', 'Tặng', suffix: 'sp'),
            _numField('giftPercent', 'Giảm hàng tặng', suffix: '%', hint: '100 = miễn phí'),
          ]),
          _pickTile('Hàng tặng (trống = tặng cùng loại)', _gift, (v) => _gift = v),
        ]);
      case PosPromotionTypes.comboPrice:
        return _section('Đồng giá combo', [
          _row([
            _numField('comboQty', 'Số món', suffix: 'sp'),
            _numField('comboPrice', 'Giá cả combo', suffix: 'đ'),
          ]),
        ]);
      case PosPromotionTypes.billDiscount:
        return _section('Giảm theo tổng hóa đơn', [
          _row([_numField('minBill', 'Hóa đơn từ', suffix: 'đ')]),
          _row([
            _numField('billPercent', 'Giảm', suffix: '%'),
            _numField('billAmount', 'Hoặc giảm', suffix: 'đ'),
          ]),
          _row([_numField('maxDiscount', 'Giảm tối đa', suffix: 'đ', hint: 'Trống = không giới hạn')]),
        ]);
      case PosPromotionTypes.addonPrice:
        return _section('Mua kèm giá ưu đãi', [
          _pickTile('Hàng mua kèm', _addon, (v) => _addon = v),
          _row([
            _numField('addonPrice', 'Giá ưu đãi', suffix: 'đ'),
            _numField('maxPerTrigger', 'Tối đa / 1 sp mua', hint: 'Mặc định 1'),
          ]),
        ]);
    }
    return const SizedBox.shrink();
  }

  Widget _targetSection() {
    if (_type == PosPromotionTypes.billDiscount || _type == PosPromotionTypes.nearExpiry) {
      return const SizedBox.shrink();
    }
    final title = switch (_type) {
      PosPromotionTypes.buyXGetY => 'Hàng phải mua',
      PosPromotionTypes.addonPrice => 'Khi mua hàng',
      _ => 'Áp dụng cho',
    };
    return _section(title, [
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final s in const [
          ('all', 'Tất cả hàng'),
          ('categories', 'Theo nhóm hàng'),
          ('products', 'Mặt hàng cụ thể'),
          ('barcoded', 'Hàng có mã vạch'),
        ])
          ChoiceChip(
            label: Text(tr(s.$2)),
            selected: _scope == s.$1,
            onSelected: (_) => setState(() => _scope = s.$1),
          ),
      ]),
      const SizedBox(height: 8),
      if (_scope == 'categories')
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final c in _categories)
            FilterChip(
              label: Text(c.name),
              selected: _categoryIds.contains(c.id),
              onSelected: (v) => setState(() => v ? _categoryIds.add(c.id) : _categoryIds.remove(c.id)),
            ),
          if (_categories.isEmpty) Text(tr('Chưa có nhóm hàng')),
        ]),
      if (_scope == 'products') ...[
        for (final e in _products.entries)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(e.value),
            trailing: IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => setState(() => _products.remove(e.key)),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final p = await _pickProduct();
              if (p != null) setState(() => _products[p.id] = p.name);
            },
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('Thêm mặt hàng')),
          ),
        ),
      ],
      const SizedBox(height: 6),
    ]);
  }

  Widget _scheduleSection() {
    const dayNames = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    Future<void> pickDate(bool from) async {
      final now = DateTime.now();
      final d = await showDatePicker(
        context: context,
        initialDate: (from ? _from : _to) ?? now,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 5),
      );
      if (d != null) setState(() => from ? _from = d : _to = d);
    }

    Future<void> pickTime(bool from) async {
      final t = await showTimePicker(
        context: context,
        initialTime: (from ? _timeFrom : _timeTo) ?? TimeOfDay(hour: from ? 18 : 21, minute: 0),
      );
      if (t != null) setState(() => from ? _timeFrom = t : _timeTo = t);
    }

    String hm(TimeOfDay? t) => t == null ? '--:--' : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    return _section('Thời gian áp dụng', [
      _row([
        OutlinedButton.icon(
          onPressed: () => pickDate(true),
          icon: const Icon(Icons.event, size: 16),
          label: Text(_from == null ? tr('Từ ngày') : _dateFmt.format(_from!)),
        ),
        OutlinedButton.icon(
          onPressed: () => pickDate(false),
          icon: const Icon(Icons.event, size: 16),
          label: Text(_to == null ? tr('Đến ngày') : _dateFmt.format(_to!)),
        ),
      ]),
      _row([
        OutlinedButton.icon(
          onPressed: () => pickTime(true),
          icon: const Icon(Icons.schedule, size: 16),
          label: Text(tr('Từ ${hm(_timeFrom)}')),
        ),
        OutlinedButton.icon(
          onPressed: () => pickTime(false),
          icon: const Icon(Icons.schedule, size: 16),
          label: Text(tr('Đến ${hm(_timeTo)}')),
        ),
      ]),
      if (_timeFrom != null || _timeTo != null || _from != null || _to != null)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => setState(() {
              _timeFrom = _timeTo = null;
              _from = _to = null;
            }),
            child: Text(tr('Xoá ngày / giờ (áp dụng mọi lúc)')),
          ),
        ),
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (var i = 0; i < 7; i++)
          FilterChip(
            label: Text(dayNames[i]),
            selected: _days & (1 << i) != 0,
            onSelected: (v) => setState(() => _days = v ? _days | (1 << i) : _days & ~(1 << i)),
          ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 4),
        child: Text(tr('Không chọn thứ = mọi ngày. Giờ kết thúc nhỏ hơn giờ bắt đầu = qua đêm.'),
            style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(widget.existing == null ? 'Tạo khuyến mãi' : 'Sửa khuyến mãi')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: PosTheme.filledButtonStyle,
              onPressed: _saving ? null : _save,
              child: Text(tr('Lưu')),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          _section('Chương trình', [
            TextField(controller: _name, decoration: PosTheme.inputDecoration(label: 'Tên chương trình', hint: 'vd: Giờ vàng rau cá')),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _type,
              isExpanded: true,
              decoration: PosTheme.inputDecoration(label: 'Loại khuyến mãi'),
              items: [
                for (final t in PosPromotionTypes.all)
                  DropdownMenuItem(value: t, child: Text(tr(PosPromotionTypes.label(t)))),
              ],
              onChanged: widget.existing != null
                  ? null
                  : (v) => setState(() {
                        _type = v ?? _type;
                        if (_type == PosPromotionTypes.buyXGetY) {
                          if (_c('buyQty').text.isEmpty) _c('buyQty').text = '2';
                          if (_c('getQty').text.isEmpty) _c('getQty').text = '1';
                        }
                      }),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 8),
              child: Text(tr(PosPromotionTypes.hint(_type)),
                  style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
            ),
          ]),
          _ruleSection(),
          _targetSection(),
          _scheduleSection(),
          _section('Tùy chọn', [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: Text(tr('Đang bật')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _stackable,
              onChanged: (v) => setState(() => _stackable = v),
              title: Text(tr('Cộng dồn với khuyến mãi khác')),
              subtitle: Text(tr('Tắt: cùng 1 mặt hàng chỉ lấy chương trình giảm nhiều nhất')),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _membersOnly,
              onChanged: (v) => setState(() => _membersOnly = v),
              title: Text(tr('Chỉ khách thành viên')),
              subtitle: Text(tr('Áp khi đã chọn khách hàng trên hóa đơn')),
            ),
            Row(children: [
              Expanded(child: Text(tr('Ưu tiên (khi giảm bằng nhau)'))),
              IconButton(onPressed: () => setState(() => _priority--), icon: const Icon(Icons.remove)),
              Text('$_priority'),
              IconButton(onPressed: () => setState(() => _priority++), icon: const Icon(Icons.add)),
            ]),
            TextField(controller: _note, decoration: PosTheme.inputDecoration(label: 'Ghi chú')),
            const SizedBox(height: 10),
          ]),
        ],
      ),
    );
  }
}

class _ProductSearchDialog extends StatefulWidget {
  const _ProductSearchDialog();

  @override
  State<_ProductSearchDialog> createState() => _ProductSearchDialogState();
}

class _ProductSearchDialogState extends State<_ProductSearchDialog> {
  final _api = ApiService();
  final _money = NumberFormat('#,###', 'vi_VN');
  List<PosProduct> _items = [];
  bool _loading = false;

  Future<void> _search(String q) async {
    if (q.trim().isEmpty) {
      setState(() => _items = []);
      return;
    }
    setState(() => _loading = true);
    final res = await _api.getPosProducts(search: q.trim(), pageSize: 30);
    if (!mounted) return;
    final raw = res['isSuccess'] == true && res['data'] is Map
        ? ((res['data'] as Map)['items'] as List? ?? const [])
        : const [];
    setState(() {
      _loading = false;
      _items = raw.map((e) => PosProduct.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Chọn hàng')),
      content: SizedBox(
        width: 460,
        height: 420,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: PosTheme.inputDecoration(label: 'Tìm tên / mã / mã vạch'),
            onChanged: _search,
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(children: [
              for (final p in _items)
                ListTile(
                  dense: true,
                  title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(tr('${p.productCode} · ${_money.format(p.basePrice.round())}đ')),
                  onTap: () => Navigator.pop(context, p),
                ),
            ]),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Đóng')))],
    );
  }
}

/// Hiệu quả khuyến mãi: số hóa đơn, tiền giảm, doanh thu hóa đơn có áp.
class PosPromotionReportScreen extends StatefulWidget {
  const PosPromotionReportScreen({super.key});

  @override
  State<PosPromotionReportScreen> createState() => _PosPromotionReportScreenState();
}

class _PosPromotionReportScreenState extends State<PosPromotionReportScreen> {
  final _api = ApiService();
  final _money = NumberFormat('#,###', 'vi_VN');
  final _dateFmt = DateFormat('dd/MM/yyyy');
  late DateTime _from;
  late DateTime _to;
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 29));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await _api.getPosPromotionReport(_from, _to);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _data = res['isSuccess'] == true && res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
    });
  }

  Future<void> _pickRange() async {
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (r == null) return;
    _from = r.start;
    _to = r.end;
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = ((_data?['items'] as List?) ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    double n(dynamic v) => v is num ? v.toDouble() : 0;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Hiệu quả khuyến mãi'))),
      body: Column(children: [
        ListTile(
          leading: const Icon(Icons.date_range),
          title: Text('${_dateFmt.format(_from)} → ${_dateFmt.format(_to)}'),
          trailing: TextButton(onPressed: _pickRange, child: Text(tr('Đổi'))),
        ),
        if (_data != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(child: _stat('Hóa đơn có KM', '${_data!['orders'] ?? 0}')),
              Expanded(child: _stat('Tổng tiền giảm', '${_money.format(n(_data!['totalDiscount']))}đ')),
            ]),
          ),
        const Divider(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? Center(child: Text(tr('Chưa có hóa đơn áp khuyến mãi trong khoảng này')))
                  : ListView(
                      children: [
                        for (final i in items)
                          ListTile(
                            title: Text('${i['name']}'),
                            subtitle: Text(tr('${i['orders']} hóa đơn · doanh thu ${_money.format(n(i['revenue']))}đ')),
                            trailing: Text(tr('−${_money.format(n(i['discount']))}đ'),
                                style: TextStyle(fontWeight: FontWeight.w700, color: Colors.red.shade700)),
                          ),
                      ],
                    ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(label), style: const TextStyle(fontSize: 12, color: PosTheme.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      );
}
