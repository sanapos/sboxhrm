import '../../widgets/hrm_page_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'dart:convert';

import '../../models/pos_customer.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_loyalty_rates.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_vnd_thousands_formatter.dart';
import '../../widgets/settings/settings_page.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Cấu hình tích điểm / đổi điểm theo cửa hàng.
class PosLoyaltySettingsScreen extends StatefulWidget {
  const PosLoyaltySettingsScreen({super.key});

  @override
  State<PosLoyaltySettingsScreen> createState() =>
      _PosLoyaltySettingsScreenState();
}

class _PosLoyaltySettingsScreenState extends State<PosLoyaltySettingsScreen> {
  late final PosSellSettingsHelper _helper =
      PosSellSettingsHelper(ApiService());
  PosStoreSellSettingsDto? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool _enabled = true;
  final _earnCtrl = TextEditingController();
  final _redeemCtrl = TextEditingController();
  double _maxPct = 100;
  bool _refundRedeem = false;
  final _money = NumberFormat('#,###', 'vi_VN');
  final _api = ApiService();

  /// Hạng thành viên đang sửa + bản đã lưu (JSON) để biết có thay đổi.
  final List<_TierRow> _tiers = [];
  String _tiersSaved = '[]';
  static const _tierColors = ['#64748B', '#F59E0B', '#0EA5E9', '#8B5CF6', '#EF4444', '#10B981'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _earnCtrl.dispose();
    _redeemCtrl.dispose();
    for (final t in _tiers) {
      t.dispose();
    }
    super.dispose();
  }

  double _tierMin(_TierRow t) => double.tryParse(t.min.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  List<Map<String, dynamic>> _tiersPayload() => [
        for (final t in _tiers)
          if (t.name.text.trim().isNotEmpty)
            PosCustomerTier(
              name: t.name.text.trim(),
              minSpend: _tierMin(t),
              color: t.color,
              benefit: t.benefit.text.trim(),
            ).toJson(),
      ];

  void _setTiers(List<PosCustomerTier> list) {
    for (final t in _tiers) {
      t.dispose();
    }
    _tiers
      ..clear()
      ..addAll(list.map((t) => _TierRow(t.name, t.minSpend > 0 ? _money.format(t.minSpend) : '0', t.benefit ?? '', t.color)));
    _tiersSaved = jsonEncode(_tiersPayload());
  }

  Future<void> _loadTiers() async {
    final res = await _api.getPosCustomerTiers();
    if (!mounted || res['isSuccess'] != true || res['data'] is! Map) return;
    final list = ((res['data'] as Map)['tiers'] as List? ?? [])
        .whereType<Map>()
        .map((e) => PosCustomerTier.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    setState(() => _setTiers(list));
  }

  bool get _tiersDirty => jsonEncode(_tiersPayload()) != _tiersSaved;

  void _addTier() {
    final last = _tiers.isEmpty ? 0.0 : _tierMin(_tiers.last);
    setState(() => _tiers.add(_TierRow('', _money.format(last <= 0 ? 2000000 : last * 2), '',
        _tierColors[_tiers.length % _tierColors.length])));
  }

  Future<bool> _saveTiers() async {
    final res = await _api.savePosCustomerTiers(_tiersPayload());
    if (!mounted) return false;
    if (res['isSuccess'] == true && res['data'] is Map) {
      final list = ((res['data'] as Map)['tiers'] as List? ?? [])
          .whereType<Map>()
          .map((e) => PosCustomerTier.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      setState(() => _setTiers(list));
      return true;
    }
    NotificationOverlayManager().showError(title: 'Hạng thành viên', message: res['message']?.toString() ?? 'Không lưu được');
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    _loadTiers();
    final r = await _helper.load();
    if (!mounted) return;
    final s = r.settings;
    setState(() {
      _settings = s;
      _error = r.error;
      _loading = false;
      if (s != null) {
        _enabled = s.loyaltyEnabled;
        _earnCtrl.text = _fmtNum(s.loyaltyEarnPerAmount);
        _redeemCtrl.text = _fmtNum(s.loyaltyRedeemValue);
        _maxPct = s.loyaltyMaxRedeemPercent.clamp(1, 100);
        _refundRedeem = s.loyaltyRefundRedeemOnReturn;
      }
    });
  }

  String _fmtNum(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toString();
  }

  double _parseMoney(String raw) {
    final t = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    return double.tryParse(t) ?? 0;
  }

  PosLoyaltyRates get _previewRates => PosLoyaltyRates(
        enabled: _enabled,
        earnPerAmount: _parseMoney(_earnCtrl.text),
        redeemValue: _parseMoney(_redeemCtrl.text),
        maxRedeemPercent: _maxPct,
      );

  Future<void> _save() async {
    final s = _settings;
    if (s == null || _saving) return;
    final earn = _parseMoney(_earnCtrl.text);
    final redeem = _parseMoney(_redeemCtrl.text);
    setState(() => _saving = true);
    if (_tiersDirty && !await _saveTiers()) {
      if (mounted) setState(() => _saving = false);
      return;
    }
    if (!_ratesDirty) {
      if (!mounted) return;
      setState(() => _saving = false);
      NotificationOverlayManager().showSuccess(title: 'Tích điểm', message: tr('Đã lưu hạng thành viên'));
      return;
    }
    final r = await _helper.save(
      s.copyWith(
        loyaltyEnabled: _enabled,
        loyaltyEarnPerAmount: earn,
        loyaltyRedeemValue: redeem,
        loyaltyMaxRedeemPercent: _maxPct,
        loyaltyRefundRedeemOnReturn: _refundRedeem,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.settings != null) {
      setState(() => _settings = r.settings);
      NotificationOverlayManager().showSuccess(
        title: 'Tích điểm',
        message: tr('Đã lưu tỷ lệ cho cửa hàng này'),
      );
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: r.error ?? 'Không lưu được',
      );
    }
  }

  /// Có thay đổi chưa lưu (hiện thanh Lưu / Bỏ thay đổi ở dưới).
  bool get _dirty => _ratesDirty || _tiersDirty;

  bool get _ratesDirty {
    final s = _settings;
    if (s == null) return false;
    return _enabled != s.loyaltyEnabled ||
        _parseMoney(_earnCtrl.text) != s.loyaltyEarnPerAmount ||
        _parseMoney(_redeemCtrl.text) != s.loyaltyRedeemValue ||
        _maxPct != s.loyaltyMaxRedeemPercent.clamp(1, 100) ||
        _refundRedeem != s.loyaltyRefundRedeemOnReturn;
  }

  void _discard() {
    final s = _settings;
    if (s == null) return;
    final saved = (jsonDecode(_tiersSaved) as List)
        .map((e) => PosCustomerTier.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    setState(() {
      _setTiers(saved);
      _enabled = s.loyaltyEnabled;
      _earnCtrl.text = _fmtNum(s.loyaltyEarnPerAmount);
      _redeemCtrl.text = _fmtNum(s.loyaltyRedeemValue);
      _maxPct = s.loyaltyMaxRedeemPercent.clamp(1, 100);
      _refundRedeem = s.loyaltyRefundRedeemOnReturn;
    });
  }

  Widget _tierRow(int i) {
    final t = _tiers[i];
    InputDecoration deco(String label, {String? suffix}) => InputDecoration(
          labelText: tr(label),
          suffixText: suffix,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        );
    final color = Color(0xFF000000 | (int.tryParse((t.color ?? '#64748B').substring(1), radix: 16) ?? 0x64748B));
    final colorDot = InkWell(
      customBorder: const CircleBorder(),
      onTap: _saving
          ? null
          : () => setState(() => t.color = _tierColors[(_tierColors.indexOf(t.color ?? '') + 1) % _tierColors.length]),
      child: Tooltip(
        message: tr('Đổi màu'),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(Icons.workspace_premium_rounded, color: color, size: 22),
        ),
      ),
    );
    final remove = IconButton(
      tooltip: tr('Xóa hạng'),
      onPressed: _saving ? null : () => setState(() => _tiers.removeAt(i).dispose()),
      icon: const Icon(Icons.delete_outline, color: Colors.red),
    );
    final name = TextField(controller: t.name, enabled: !_saving, decoration: deco('Tên hạng'), onChanged: (_) => setState(() {}));
    final min = TextField(
      controller: t.min,
      enabled: !_saving,
      keyboardType: TextInputType.number,
      inputFormatters: [PosVndThousandsFormatter()],
      decoration: deco('Tổng mua từ', suffix: 'đ'),
      onChanged: (_) => setState(() {}),
    );
    final benefit = TextField(controller: t.benefit, enabled: !_saving, decoration: deco('Ưu đãi (ghi chú)'), onChanged: (_) => setState(() {}));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth < 560) {
          return Column(children: [
            Row(children: [colorDot, Expanded(child: name), remove]),
            const SizedBox(height: 8),
            min,
            const SizedBox(height: 8),
            benefit,
          ]);
        }
        return Row(children: [
          colorDot,
          Expanded(flex: 2, child: name),
          const SizedBox(width: 8),
          Expanded(flex: 2, child: min),
          const SizedBox(width: 8),
          Expanded(flex: 3, child: benefit),
          remove,
        ]);
      }),
    );
  }

  Widget _numField(TextEditingController c, String suffix, String hint) => SizedBox(
        width: 140,
        child: TextField(
          controller: c,
          enabled: _enabled && !_saving,
          textAlign: TextAlign.right,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: hint,
            suffixText: tr(suffix),
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final rates = _previewRates;
    const sample = 100000.0;
    final earnPts = rates.earnPoints(sample);
    final redeemDong = earnPts * rates.redeemValue;
    final pctBack = sample > 0 ? (redeemDong / sample * 100) : 0.0;
    final page = SettingsPage(
      title: 'Tích điểm & đổi điểm',
      subtitle: 'Tỷ lệ riêng của cửa hàng — máy chủ dùng đúng số này khi thanh toán, thu ngân không đổi tay được',
      icon: Icons.stars_outlined,
      loading: _loading,
      error: _error,
      onRetry: _load,
      dirty: _dirty,
      saving: _saving,
      onSave: _save,
      onDiscard: _discard,
      children: [
        SettingsSection(
          title: 'Chương trình',
          icon: Icons.loyalty_outlined,
          children: [
            SettingsTile(
              label: 'Bật tích điểm / đổi điểm',
              help: 'Tắt: không cộng điểm cho khách, ẩn ô đổi điểm khi thanh toán',
              divider: false,
              control: Switch(value: _enabled, onChanged: _saving ? null : (v) => setState(() => _enabled = v)),
            ),
          ],
        ),
        SettingsSection(
          title: 'Tỷ lệ',
          icon: Icons.percent_rounded,
          children: [
            SettingsTile(
              label: 'Tích 1 điểm cho mỗi',
              help: '0 = không tích điểm · mặc định 10.000đ',
              divider: false,
              control: _numField(_earnCtrl, 'đ', '10000'),
            ),
            SettingsTile(
              label: '1 điểm đổi được',
              help: '0 = không cho đổi điểm · mặc định 100đ',
              control: _numField(_redeemCtrl, 'đ', '100'),
            ),
            SettingsTile(
              label: 'Đổi điểm tối đa ${_maxPct.toStringAsFixed(0)}% giá trị đơn',
              help: 'Tính sau khi trừ voucher',
              inline: false,
              control: Slider(
                value: _maxPct,
                min: 10,
                max: 100,
                divisions: 18,
                label: '${_maxPct.toStringAsFixed(0)}%',
                onChanged: !_enabled || _saving ? null : (v) => setState(() => _maxPct = v.roundToDouble()),
              ),
            ),
            SettingsTile(
              label: 'Hoàn điểm đã đổi khi khách trả hàng',
              help: 'Bật: đơn có dùng điểm, khách trả hàng → hoàn lại điểm theo tỷ lệ hàng trả (trả hết đơn → hoàn hết). '
                  'Tắt: điểm đã đổi coi như đã dùng, chỉ hoàn tiền khách đã trả.',
              control: Switch(
                value: _refundRedeem,
                onChanged: !_enabled || _saving ? null : (v) => setState(() => _refundRedeem = v),
              ),
            ),
            SettingsNote(
              !rates.enabled
                  ? 'Chương trình đang tắt.'
                  : 'Ví dụ đơn ${_money.format(sample)}đ: tích ${earnPts.toStringAsFixed(0)} điểm'
                      '${rates.canRedeem && earnPts > 0 ? ' · đổi lại giảm ${_money.format(redeemDong)}đ (~${pctBack.toStringAsFixed(1)}%)' : ''}.',
              icon: Icons.calculate_outlined,
            ),
          ],
        ),
        SettingsSection(
          title: 'Hạng thành viên',
          subtitle: 'Hạng theo tổng mua của khách — khách đạt mức của hạng cao nhất nào thì thuộc hạng đó',
          icon: Icons.workspace_premium_outlined,
          trailing: TextButton.icon(
            onPressed: _saving || _tiers.length >= 10 ? null : _addTier,
            icon: const Icon(Icons.add, size: 18),
            label: Text(tr('Thêm hạng')),
          ),
          children: [
            if (_tiers.isEmpty)
              const SettingsNote('Chưa có hạng. Ví dụ: Bạc từ 2.000.000đ, Vàng từ 10.000.000đ, Kim cương từ 50.000.000đ.',
                  icon: Icons.info_outline),
            for (var i = 0; i < _tiers.length; i++) _tierRow(i),
          ],
        ),
      ],
    );
    if (HrmPageChrome.isHubBody(context)) return page;
    return Scaffold(appBar: AppBar(title: Text(tr('Tích điểm & đổi điểm'))), body: page);
  }
}

/// Một dòng hạng đang sửa.
class _TierRow {
  _TierRow(String name, String min, String benefit, this.color)
      : name = TextEditingController(text: name),
        min = TextEditingController(text: min),
        benefit = TextEditingController(text: benefit);

  final TextEditingController name;
  final TextEditingController min;
  final TextEditingController benefit;
  String? color;

  void dispose() {
    name.dispose();
    min.dispose();
    benefit.dispose();
  }
}
