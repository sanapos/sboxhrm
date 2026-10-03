import '../../widgets/hrm_page_chrome.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_loyalty_rates.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
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
  final _money = NumberFormat('#,###', 'vi_VN');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _earnCtrl.dispose();
    _redeemCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
    final r = await _helper.save(
      s.copyWith(
        loyaltyEnabled: _enabled,
        loyaltyEarnPerAmount: earn,
        loyaltyRedeemValue: redeem,
        loyaltyMaxRedeemPercent: _maxPct,
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
  bool get _dirty {
    final s = _settings;
    if (s == null) return false;
    return _enabled != s.loyaltyEnabled ||
        _parseMoney(_earnCtrl.text) != s.loyaltyEarnPerAmount ||
        _parseMoney(_redeemCtrl.text) != s.loyaltyRedeemValue ||
        _maxPct != s.loyaltyMaxRedeemPercent.clamp(1, 100);
  }

  void _discard() {
    final s = _settings;
    if (s == null) return;
    setState(() {
      _enabled = s.loyaltyEnabled;
      _earnCtrl.text = _fmtNum(s.loyaltyEarnPerAmount);
      _redeemCtrl.text = _fmtNum(s.loyaltyRedeemValue);
      _maxPct = s.loyaltyMaxRedeemPercent.clamp(1, 100);
    });
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
            SettingsNote(
              !rates.enabled
                  ? 'Chương trình đang tắt.'
                  : 'Ví dụ đơn ${_money.format(sample)}đ: tích ${earnPts.toStringAsFixed(0)} điểm'
                      '${rates.canRedeem && earnPts > 0 ? ' · đổi lại giảm ${_money.format(redeemDong)}đ (~${pctBack.toStringAsFixed(1)}%)' : ''}.',
              icon: Icons.calculate_outlined,
            ),
          ],
        ),
      ],
    );
    if (HrmPageChrome.isHubBody(context)) return page;
    return Scaffold(appBar: AppBar(title: Text(tr('Tích điểm & đổi điểm'))), body: page);
  }
}
