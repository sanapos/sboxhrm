import 'dart:convert';
import 'dart:math' as math;

/// Loại chương trình — khớp PosPromotionsController.Types (server).
class PosPromotionTypes {
  static const timeDiscount = 'time_discount';
  static const qtyDiscount = 'qty_discount';
  static const buyXGetY = 'buy_x_get_y';
  static const comboPrice = 'combo_price';
  static const billDiscount = 'bill_discount';
  static const addonPrice = 'addon_price';
  static const nearExpiry = 'near_expiry';

  static const all = [timeDiscount, qtyDiscount, buyXGetY, comboPrice, billDiscount, addonPrice, nearExpiry];

  static String label(String t) => switch (t) {
        timeDiscount => 'Giảm giá theo giờ / mặt hàng',
        qtyDiscount => 'Mua nhiều giảm giá',
        buyXGetY => 'Mua X tặng Y',
        comboPrice => 'Đồng giá combo',
        billDiscount => 'Giảm theo tổng hóa đơn',
        addonPrice => 'Mua kèm giá ưu đãi',
        nearExpiry => 'Hàng cận hạn tự giảm',
        _ => t,
      };

  static String hint(String t) => switch (t) {
        timeDiscount => 'Vd: 18h–21h rau, cá giảm 30%; hàng có mã vạch giảm 10%',
        qtyDiscount => 'Vd: mua từ 5 cái giảm 20%; 3 cái −10%, 6 cái −15%',
        buyXGetY => 'Vd: mua 2 tặng 1 cùng loại; mua 2 sữa tặng 1 bánh',
        comboPrice => 'Vd: 3 món bất kỳ trong nhóm giá 99.000đ',
        billDiscount => 'Vd: hóa đơn từ 500.000đ giảm 50.000đ hoặc 5%',
        addonPrice => 'Vd: mua dầu ăn thì nước mắm còn 10.000đ',
        nearExpiry => 'Lô còn ≤ N ngày hết hạn tự giảm %',
        _ => '',
      };
}

/// Chương trình khuyến mãi (đọc từ /api/pos/promotions[/active]).
class PosPromotion {
  PosPromotion({
    required this.id,
    required this.name,
    required this.type,
    this.priority = 0,
    this.stackable = false,
    this.validFrom,
    this.validTo,
    this.daysOfWeekMask = 0,
    this.timeFromMinutes,
    this.timeToMinutes,
    this.membersOnly = false,
    Map<String, dynamic>? config,
    this.note,
    this.isActive = true,
    Set<String>? resolvedProductIds,
  })  : config = config ?? <String, dynamic>{},
        resolvedProductIds = resolvedProductIds ?? <String>{};

  final String id;
  final String name;
  final String type;
  final int priority;
  final bool stackable;
  final DateTime? validFrom;
  final DateTime? validTo;
  /// bit0 = Thứ 2 … bit6 = Chủ nhật; 0 = mọi ngày.
  final int daysOfWeekMask;
  final int? timeFromMinutes;
  final int? timeToMinutes;
  final bool membersOnly;
  final Map<String, dynamic> config;
  final String? note;
  final bool isActive;
  /// Hàng cận hạn server đã tính sẵn (near_expiry).
  final Set<String> resolvedProductIds;

  factory PosPromotion.fromJson(Map<String, dynamic> j) {
    DateTime? d(dynamic v) => v == null ? null : DateTime.tryParse('$v');
    Map<String, dynamic> cfg = {};
    final raw = j['configJson'] ?? j['ConfigJson'];
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) cfg = Map<String, dynamic>.from(m);
      } catch (_) {}
    } else if (raw is Map) {
      cfg = Map<String, dynamic>.from(raw);
    }
    final resolved = (j['resolvedProductIds'] ?? j['ResolvedProductIds']) as List?;
    return PosPromotion(
      id: '${j['id'] ?? j['Id']}',
      name: '${j['name'] ?? j['Name'] ?? ''}',
      type: '${j['type'] ?? j['Type'] ?? PosPromotionTypes.timeDiscount}',
      priority: ((j['priority'] ?? j['Priority']) as num?)?.toInt() ?? 0,
      stackable: (j['stackable'] ?? j['Stackable']) == true,
      validFrom: d(j['validFrom'] ?? j['ValidFrom']),
      validTo: d(j['validTo'] ?? j['ValidTo']),
      daysOfWeekMask: ((j['daysOfWeekMask'] ?? j['DaysOfWeekMask']) as num?)?.toInt() ?? 0,
      timeFromMinutes: ((j['timeFromMinutes'] ?? j['TimeFromMinutes']) as num?)?.toInt(),
      timeToMinutes: ((j['timeToMinutes'] ?? j['TimeToMinutes']) as num?)?.toInt(),
      membersOnly: (j['membersOnly'] ?? j['MembersOnly']) == true,
      config: cfg,
      note: (j['note'] ?? j['Note'])?.toString(),
      isActive: (j['isActive'] ?? j['IsActive']) != false,
      resolvedProductIds: resolved?.map((e) => '$e').toSet(),
    );
  }

  Map<String, dynamic> toSaveJson() => {
        'name': name,
        'type': type,
        'priority': priority,
        'stackable': stackable,
        'validFrom': validFrom == null ? null : _ymd(validFrom!),
        'validTo': validTo == null ? null : _ymd(validTo!),
        'daysOfWeekMask': daysOfWeekMask,
        'timeFromMinutes': timeFromMinutes,
        'timeToMinutes': timeToMinutes,
        'membersOnly': membersOnly,
        'configJson': jsonEncode(config),
        'note': note,
        'isActive': isActive,
      };

  static String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Đang hiệu lực lúc [now] (giờ máy bán) — ngày, thứ, khung giờ, thành viên.
  bool isLiveAt(DateTime now, {bool hasCustomer = false}) {
    if (!isActive) return false;
    if (membersOnly && !hasCustomer) return false;
    final from = timeFromMinutes;
    final to = timeToMinutes;
    final m = now.hour * 60 + now.minute;
    // Khung giờ vắt qua nửa đêm (VD 22:00–02:00): phần sau 0h thuộc ngày bắt đầu khung
    // → «Thứ 6 22:00–02:00» vẫn áp lúc 01:00 sáng thứ 7; hạn chương trình cũng tính theo ngày đó.
    final overnightTail = from != null && to != null && from > to && m < to;
    final ref = overnightTail ? now.subtract(const Duration(days: 1)) : now;
    final day = DateTime(ref.year, ref.month, ref.day);
    if (validFrom != null && day.isBefore(DateTime(validFrom!.year, validFrom!.month, validFrom!.day))) return false;
    if (validTo != null && day.isAfter(DateTime(validTo!.year, validTo!.month, validTo!.day))) return false;
    if (daysOfWeekMask != 0 && (daysOfWeekMask & (1 << (ref.weekday - 1))) == 0) return false;
    if (from != null && to != null && from != to) {
      final inside = from < to ? (m >= from && m < to) : (m >= from || m < to);
      if (!inside) return false;
    }
    return true;
  }

  /// Mô tả ngắn điều kiện thời gian (hiện trong danh sách).
  String get scheduleLabel {
    final parts = <String>[];
    if (timeFromMinutes != null && timeToMinutes != null && timeFromMinutes != timeToMinutes) {
      String hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
      parts.add('${hm(timeFromMinutes!)}–${hm(timeToMinutes!)}');
    }
    if (daysOfWeekMask != 0 && daysOfWeekMask != 0x7F) {
      const names = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
      parts.add([for (var i = 0; i < 7; i++) if (daysOfWeekMask & (1 << i) != 0) names[i]].join(','));
    }
    if (membersOnly) parts.add('khách thành viên');
    return parts.isEmpty ? 'Cả ngày' : parts.join(' · ');
  }

  // ── đọc cấu hình ──
  double num_(String k, [double d = 0]) {
    final v = config[k];
    if (v is num) return v.toDouble();
    return double.tryParse('${v ?? ''}') ?? d;
  }

  String? str_(String k) {
    final v = config[k];
    return v == null || '$v'.isEmpty ? null : '$v';
  }

  Map<String, dynamic> get target =>
      config['target'] is Map ? Map<String, dynamic>.from(config['target'] as Map) : const {'scope': 'all'};

  /// Dòng hàng có thuộc phạm vi áp dụng.
  bool matches(PosPromoLine l) {
    if (type == PosPromotionTypes.nearExpiry) return resolvedProductIds.contains(l.productId);
    final t = target;
    switch ('${t['scope'] ?? 'all'}') {
      case 'categories':
        final ids = (t['categoryIds'] as List?)?.map((e) => '$e').toSet() ?? const {};
        return l.categoryId != null && ids.contains(l.categoryId);
      case 'products':
        final ids = (t['products'] as List?)
                ?.map((e) => e is Map ? '${e['id']}' : '$e')
                .toSet() ??
            const {};
        return ids.contains(l.productId);
      case 'barcoded':
        return l.hasBarcode;
      default:
        return true;
    }
  }
}

/// Một dòng giỏ hàng đưa vào tính khuyến mãi.
class PosPromoLine {
  PosPromoLine({
    required this.key,
    required this.productId,
    required this.qty,
    required this.gross,
    this.categoryId,
    this.hasBarcode = false,
    this.manualDiscount = 0,
  });

  /// Khóa duy nhất của dòng trong giỏ (rowId).
  final String key;
  final String productId;
  final String? categoryId;
  final bool hasBarcode;
  final double qty;
  /// Thành tiền trước giảm (đơn giá × SL + topping).
  final double gross;
  /// Giảm tay của thu ngân trên dòng.
  final double manualDiscount;

  double get unit => qty > 0 ? gross / qty : 0;
  double get net => math.max(0, gross - manualDiscount);
}

class PosPromoApplied {
  PosPromoApplied(this.id, this.name, this.amount);
  final String id;
  final String name;
  double amount;
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'amount': amount};
}

/// Gợi ý thêm hàng tặng / mua kèm chưa có trong giỏ.
class PosPromoSuggestion {
  PosPromoSuggestion({
    required this.promotionName,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.text,
  });
  final String promotionName;
  final String productId;
  final String productName;
  final double qty;
  final String text;
}

class PosPromoResult {
  final Map<String, double> lineDiscount = {};
  final Map<String, List<String>> lineLabels = {};
  double billDiscount = 0;
  String? billLabel;
  final List<PosPromoApplied> applied = [];
  final List<PosPromoSuggestion> suggestions = [];

  double get total => lineDiscount.values.fold(0.0, (a, b) => a + b) + billDiscount;
  bool get isEmpty => total <= 0 && suggestions.isEmpty;

  /// Lưu vào đơn (PromotionsJson) — để báo cáo và khôi phục khi mở lại đơn tạm.
  String? toOrderJson(Map<String, String> lineSaveKeys) {
    if (applied.isEmpty) return null;
    final lines = <String, double>{};
    lineDiscount.forEach((k, v) {
      final sk = lineSaveKeys[k];
      if (sk != null && v > 0) lines[sk] = (lines[sk] ?? 0) + v;
    });
    return jsonEncode({
      'applied': applied.where((a) => a.amount > 0).map((a) => a.toJson()).toList(),
      'lines': lines,
      'bill': billDiscount,
    });
  }
}

class _Cand {
  _Cand(this.p, this.amount);
  final PosPromotion p;
  double amount;
}

/// Tính khuyến mãi cho giỏ hàng. Mỗi dòng: lấy chương trình không cộng dồn có tiền giảm lớn nhất
/// (bằng tiền → ưu tiên cao hơn) + mọi chương trình cộng dồn; không giảm quá thành tiền còn lại.
/// Giảm hóa đơn tính sau, trên tổng đã trừ giảm dòng.
PosPromoResult computePosPromotions({
  required List<PosPromotion> promotions,
  required List<PosPromoLine> lines,
  required DateTime now,
  bool hasCustomer = false,
}) {
  final res = PosPromoResult();
  final live = promotions.where((p) => p.isLiveAt(now, hasCustomer: hasCustomer)).toList();
  if (live.isEmpty || lines.isEmpty) return res;

  final cands = <String, List<_Cand>>{for (final l in lines) l.key: []};
  void add(PosPromotion p, String key, double amount) {
    if (amount <= 0.0001) return;
    final list = cands[key]!;
    final existing = list.where((c) => identical(c.p, p)).firstOrNull;
    if (existing != null) {
      existing.amount += amount;
    } else {
      list.add(_Cand(p, amount));
    }
  }

  for (final p in live) {
    switch (p.type) {
      case PosPromotionTypes.timeDiscount:
      case PosPromotionTypes.nearExpiry:
        final pct = p.num_('percent');
        final perUnit = p.num_('amountPerUnit');
        final salePrice = p.num_('salePrice');
        for (final l in lines.where(p.matches)) {
          double off;
          if (salePrice > 0) {
            off = math.max(0, l.unit - salePrice);
          } else if (pct > 0) {
            off = l.unit * math.min(pct, 100) / 100;
          } else {
            off = math.min(perUnit, l.unit);
          }
          add(p, l.key, off * l.qty);
        }

      case PosPromotionTypes.qtyDiscount:
        final tiers = ((p.config['tiers'] as List?) ?? const [])
            .whereType<Map>()
            .map((t) => (
                  min: (t['minQty'] as num?)?.toDouble() ?? 0,
                  pct: (t['percent'] as num?)?.toDouble() ?? 0,
                ))
            .where((t) => t.min > 0 && t.pct > 0)
            .toList()
          ..sort((a, b) => b.min.compareTo(a.min));
        if (tiers.isEmpty) break;
        final mixed = p.config['mixed'] == true;
        final matched = lines.where(p.matches).toList();
        final groups = <String, List<PosPromoLine>>{};
        for (final l in matched) {
          groups.putIfAbsent(mixed ? '*' : l.productId, () => []).add(l);
        }
        for (final g in groups.values) {
          final q = g.fold<double>(0, (s, l) => s + l.qty);
          final tier = tiers.where((t) => q >= t.min).firstOrNull;
          if (tier == null) continue;
          for (final l in g) {
            add(p, l.key, l.gross * math.min(tier.pct, 100) / 100);
          }
        }

      case PosPromotionTypes.buyXGetY:
        final buy = p.num_('buyQty', 1).floor();
        final get = p.num_('getQty', 1).floor();
        final giftPct = math.min(p.num_('giftPercent', 100), 100) / 100;
        final giftId = p.str_('giftProductId');
        if (buy <= 0 || get <= 0) break;
        if (giftId == null) {
          // Cùng loại: mỗi (X+Y) cái của cùng mặt hàng → Y cái giảm.
          final byProduct = <String, List<PosPromoLine>>{};
          for (final l in lines.where(p.matches)) {
            byProduct.putIfAbsent(l.productId, () => []).add(l);
          }
          for (final g in byProduct.values) {
            final q = g.fold<double>(0, (s, l) => s + l.qty).floor();
            var free = (q ~/ (buy + get)) * get;
            for (final l in g) {
              if (free <= 0) break;
              final take = math.min(free.toDouble(), l.qty.floorToDouble());
              add(p, l.key, take * l.unit * giftPct);
              free -= take.toInt();
            }
          }
        } else {
          final buyCount = lines
              .where((l) => l.productId != giftId && p.matches(l))
              .fold<double>(0, (s, l) => s + l.qty)
              .floor();
          final entitled = (buyCount ~/ buy) * get;
          if (entitled <= 0) break;
          var left = entitled.toDouble();
          for (final l in lines.where((l) => l.productId == giftId)) {
            if (left <= 0) break;
            final take = math.min(left, l.qty);
            add(p, l.key, take * l.unit * giftPct);
            left -= take;
          }
          if (left > 0) {
            final name = p.str_('giftProductName') ?? 'hàng tặng';
            res.suggestions.add(PosPromoSuggestion(
              promotionName: p.name,
              productId: giftId,
              productName: name,
              qty: left,
              text: 'Được tặng ${_q(left)} × $name',
            ));
          }
        }

      case PosPromotionTypes.comboPrice:
        final n = p.num_('comboQty', 0).floor();
        final price = p.num_('comboPrice');
        if (n <= 1 || price <= 0) break;
        final units = <({String key, double unit})>[];
        for (final l in lines.where(p.matches)) {
          for (var i = 0; i < l.qty.floor(); i++) {
            units.add((key: l.key, unit: l.unit));
          }
        }
        units.sort((a, b) => b.unit.compareTo(a.unit));
        for (var i = 0; i + n <= units.length; i += n) {
          final group = units.sublist(i, i + n);
          final sum = group.fold<double>(0, (s, u) => s + u.unit);
          final off = sum - price;
          if (off <= 0) continue;
          for (final u in group) {
            add(p, u.key, off * u.unit / sum);
          }
        }

      case PosPromotionTypes.addonPrice:
        final addonId = p.str_('addonProductId');
        final addonPrice = p.num_('addonPrice');
        final maxPer = p.num_('maxPerTrigger', 1);
        if (addonId == null) break;
        final triggers = lines
            .where((l) => l.productId != addonId && p.matches(l))
            .fold<double>(0, (s, l) => s + l.qty)
            .floor();
        if (triggers <= 0) break;
        var allowed = maxPer > 0 ? triggers * maxPer : double.infinity;
        var inCart = 0.0;
        for (final l in lines.where((l) => l.productId == addonId)) {
          inCart += l.qty;
          if (allowed <= 0) continue;
          final take = math.min(allowed, l.qty);
          add(p, l.key, take * math.max(0, l.unit - addonPrice));
          allowed -= take;
        }
        if (inCart <= 0) {
          final name = p.str_('addonProductName') ?? 'hàng mua kèm';
          res.suggestions.add(PosPromoSuggestion(
            promotionName: p.name,
            productId: addonId,
            productName: name,
            qty: 1,
            text: 'Mua kèm $name chỉ ${_money(addonPrice)}đ',
          ));
        }
    }
  }

  // ── chọn khuyến mãi từng dòng ──
  final appliedById = <String, PosPromoApplied>{};
  void credit(PosPromotion p, double amount) {
    if (amount <= 0) return;
    appliedById.putIfAbsent(p.id, () => PosPromoApplied(p.id, p.name, 0)).amount += amount;
  }

  var afterLines = 0.0;
  for (final l in lines) {
    final list = cands[l.key]!;
    final exclusive = list.where((c) => !c.p.stackable).toList()
      ..sort((a, b) {
        final c = b.amount.compareTo(a.amount);
        return c != 0 ? c : b.p.priority.compareTo(a.p.priority);
      });
    final chosen = <_Cand>[
      if (exclusive.isNotEmpty) exclusive.first,
      ...list.where((c) => c.p.stackable),
    ];
    var sum = chosen.fold<double>(0, (s, c) => s + c.amount);
    final cap = l.net;
    final scale = sum > cap && sum > 0 ? cap / sum : 1.0;
    sum = 0;
    for (final c in chosen) {
      final a = _round(c.amount * scale);
      if (a <= 0) continue;
      credit(c.p, a);
      sum += a;
      res.lineLabels.putIfAbsent(l.key, () => []).add(c.p.name);
    }
    if (sum > 0) res.lineDiscount[l.key] = sum;
    afterLines += math.max(0, l.net - sum);
  }

  // ── giảm hóa đơn ──
  final billCands = <_Cand>[];
  for (final p in live.where((p) => p.type == PosPromotionTypes.billDiscount)) {
    final minBill = p.num_('minBill');
    if (afterLines < minBill || afterLines <= 0) continue;
    final pct = p.num_('billPercent');
    var off = pct > 0 ? afterLines * math.min(pct, 100) / 100 : p.num_('billAmount');
    final maxOff = p.num_('maxDiscount');
    if (maxOff > 0) off = math.min(off, maxOff);
    if (off > 0) billCands.add(_Cand(p, off));
  }
  if (billCands.isNotEmpty) {
    final exclusive = billCands.where((c) => !c.p.stackable).toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final chosen = [if (exclusive.isNotEmpty) exclusive.first, ...billCands.where((c) => c.p.stackable)];
    var total = 0.0;
    for (final c in chosen) {
      final a = _round(math.min(c.amount, afterLines - total));
      if (a <= 0) continue;
      credit(c.p, a);
      total += a;
    }
    res.billDiscount = total;
    res.billLabel = chosen.map((c) => c.p.name).join(', ');
  }

  res.applied.addAll(appliedById.values.where((a) => a.amount > 0));
  return res;
}

double _round(double v) => v.roundToDouble();

String _q(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

String _money(double v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}
