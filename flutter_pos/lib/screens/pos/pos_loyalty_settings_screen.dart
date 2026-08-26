import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_loyalty_rates.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

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

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(child: Text(tr(_error!)))
            : _buildBody();

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Tích điểm & đổi điểm')),
        backgroundColor: PosTheme.kiotBlue,
        foregroundColor: Colors.white,
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            TextButton(
              onPressed: _settings == null ? null : _save,
              child: Text(tr('Lưu'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    final rates = _previewRates;
    const sample = 100000.0;
    final earnPts = rates.earnPoints(sample);
    final redeemDong = earnPts * rates.redeemValue;
    final pctBack = sample > 0 ? (redeemDong / sample * 100) : 0.0;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('Mỗi cửa hàng tự chọn tỷ lệ. Server dùng đúng số này lúc thanh toán — thu ngân không thể đổi tay.'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Bật tích điểm / đổi điểm')),
          subtitle: Text(tr(
              'Tắt: khách lẻ và khách CRM đều không cộng điểm, ô đổi điểm ẩn.')),
          value: _enabled,
          onChanged: _saving
              ? null
              : (v) => setState(() => _enabled = v),
        ),
        const Divider(height: 28),
        Text(tr('Mỗi bao nhiêu đồng được 1 điểm'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _earnCtrl,
          enabled: _enabled && !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '10000',
            suffixText: 'đ / 1 điểm',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Text(
          tr('0 = không tích điểm. Mặc định 10.000đ → 1 điểm.'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        Text(tr('1 điểm đổi được bao nhiêu đồng'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(
          controller: _redeemCtrl,
          enabled: _enabled && !_saving,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: '100',
            suffixText: 'đ',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            isDense: true,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 4),
        Text(
          tr('0 = không cho đổi điểm. Mặc định 1 điểm = 100đ.'),
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        Text(
          tr('Đổi điểm tối đa ${_maxPct.toStringAsFixed(0)}% giá trị đơn (sau voucher)'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Slider(
          value: _maxPct,
          min: 10,
          max: 100,
          divisions: 18,
          label: '${_maxPct.toStringAsFixed(0)}%',
          onChanged: !_enabled || _saving
              ? null
              : (v) => setState(() => _maxPct = v.roundToDouble()),
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              !rates.enabled
                  ? tr('Chương trình đang tắt.')
                  : tr(
                      'Ví dụ đơn ${_money.format(sample)}đ: tích ${earnPts.toStringAsFixed(0)} điểm'
                      '${rates.canRedeem && earnPts > 0 ? ' · đổi lại giảm ${_money.format(redeemDong)}đ (~${pctBack.toStringAsFixed(1)}%)' : ''}.'),
              style: TextStyle(fontSize: 13, color: Colors.blue.shade900),
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _saving || _settings == null ? null : _save,
          icon: const Icon(Icons.save),
          label: Text(tr('Lưu')),
        ),
      ],
    );
  }
}
