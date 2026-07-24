import 'package:flutter/material.dart';

import '../../models/customer_display_models.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import '../main_layout.dart' show ScreenRefreshNotifier;

/// Cài đặt giao diện bán hàng theo ngành.
class PosSellIndustrySettingsScreen extends StatefulWidget {
  const PosSellIndustrySettingsScreen({
    super.key,
    this.embeddedInSettings = false,
  });

  final bool embeddedInSettings;

  @override
  State<PosSellIndustrySettingsScreen> createState() =>
      _PosSellIndustrySettingsScreenState();
}

class _PosSellIndustrySettingsScreenState
    extends State<PosSellIndustrySettingsScreen> {
  final _api = ApiService();
  PosStoreSellSettingsDto? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final res = await _api.getPosSellSettings();
    if (!mounted) return;
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _settings = PosStoreSellSettingsDto.fromJson(
            Map<String, dynamic>.from(res['data'] as Map));
        _loading = false;
      });
    } else {
      setState(() {
        _error = res['message']?.toString() ?? 'Không tải được thiết lập';
        _loading = false;
      });
    }
  }

  Future<void> _save({
    required bool applyDefaults,
    bool quiet = false,
  }) async {
    final s = _settings;
    if (s == null || _saving) return;
    setState(() => _saving = true);
    final res = await _api.updatePosSellSettings(
      s.toSaveBody(applyProfileDefaults: applyDefaults),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] == true && res['data'] is Map) {
      setState(() {
        _settings = PosStoreSellSettingsDto.fromJson(
            Map<String, dynamic>.from(res['data'] as Map));
      });
      ScreenRefreshNotifier.refreshPosSellIndustry();
      if (!quiet) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã lưu',
          message: 'Hồ sơ ngành: ${_settings!.sellProfile.label}',
        );
      }
    } else {
      final status = res['statusCode'];
      final msg = res['message']?.toString() ?? 'Không lưu được';
      NotificationOverlayManager().showError(
        title: status == 403 ? 'Không có quyền' : 'Lỗi',
        message: status == 403
            ? 'Tài khoản không có quyền sửa bán hàng / hàng hóa.'
            : msg,
      );
      // Reload để UI khớp server nếu save fail.
      await _load();
    }
  }

  Future<void> _onProfileChanged(PosSellProfile? v) async {
    if (v == null || _settings == null) return;
    setState(() => _settings = _settings!.withProfileDefaults(v));
    await _save(applyDefaults: true);
  }

  Future<void> _patchAndSave(
    PosStoreSellSettingsDto Function(PosStoreSellSettingsDto) patch,
  ) async {
    final s = _settings;
    if (s == null) return;
    setState(() => _settings = patch(s));
    await _save(applyDefaults: false, quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: const Text('Thử lại')),
                  ],
                ),
              )
            : _buildForm();

    if (widget.embeddedInSettings) {
      return ColoredBox(
        color: PosTheme.background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Ngành hàng & bán hàng',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (_saving)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        tooltip: 'Tải lại',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                      ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: const Text('Ngành hàng & bán hàng'),
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
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Tải lại',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildForm() {
    final s = _settings!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Hồ sơ ngành',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<PosSellProfile>(
          value: s.sellProfile,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: PosSellProfile.values
              .map((p) => DropdownMenuItem(value: p, child: Text(p.label)))
              .toList(),
          onChanged: _saving ? null : _onProfileChanged,
        ),
        const SizedBox(height: 8),
        Text(
          'Đổi ngành sẽ lưu ngay và bật sẵn bàn/ghế, tính giờ hoặc gói buổi. '
          'Chỉnh công tắc bên dưới cũng tự lưu.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const Divider(height: 28),
        const Text(
          'Chế độ bán mặc định',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: const {'quick', 'normal', 'delivery'}.contains(s.defaultSellMode)
              ? s.defaultSellMode
              : 'quick',
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'quick', child: Text('Bán nhanh')),
            DropdownMenuItem(value: 'normal', child: Text('Bán thường')),
            DropdownMenuItem(value: 'delivery', child: Text('Giao hàng')),
          ],
          onChanged: _saving
              ? null
              : (v) {
                  if (v == null) return;
                  _patchAndSave((cur) => cur.copyWith(defaultSellMode: v));
                },
        ),
        const Divider(height: 28),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sơ đồ bàn / ghế / phòng'),
          subtitle: const Text('F&B, salon, karaoke'),
          value: s.showFloorPlan,
          onChanged: _saving
              ? null
              : (v) => _patchAndSave((cur) => cur.copyWith(showFloorPlan: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bật tài nguyên phục vụ'),
          value: s.enableResources,
          onChanged: _saving
              ? null
              : (v) =>
                  _patchAndSave((cur) => cur.copyWith(enableResources: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Bắt buộc chọn bàn/phòng khi bán'),
          value: s.requireResourceOnSale,
          onChanged: _saving
              ? null
              : (v) => _patchAndSave(
                  (cur) => cur.copyWith(requireResourceOnSale: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Dịch vụ tính theo giờ/phút'),
          value: s.enableHourlyBilling,
          onChanged: _saving
              ? null
              : (v) =>
                  _patchAndSave((cur) => cur.copyWith(enableHourlyBilling: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Gói buổi (Gym)'),
          subtitle: const Text('Mua gói cộng buổi, check-in trừ buổi'),
          value: s.enableSessionPacks,
          onChanged: _saving
              ? null
              : (v) =>
                  _patchAndSave((cur) => cur.copyWith(enableSessionPacks: v)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cho phép tạm tính'),
          subtitle: const Text(
              'Hiện nút Tạm tính khi thanh toán — in hóa đơn tạm (F&B)'),
          value: s.allowProvisionalBill,
          onChanged: _saving
              ? null
              : (v) => _patchAndSave(
                  (cur) => cur.copyWith(allowProvisionalBill: v)),
        ),
        const Divider(height: 28),
        const Text(
          'Màn hình phụ (khách)',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 4),
        Text(
          'Chỉ máy có 2 màn (display phụ). Ảnh/video | hóa đơn. Không media → SBOX HRM.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 8),
        ..._buildCustomerDisplayTiles(s),
      ],
    );
  }

  List<Widget> _buildCustomerDisplayTiles(PosStoreSellSettingsDto s) {
    final cd = CustomerDisplayConfig.fromExtraJson(s.extraJson);
    Future<void> patchCd(
      CustomerDisplayConfig Function(CustomerDisplayConfig) fn,
    ) {
      return _patchAndSave((cur) {
        final next = fn(CustomerDisplayConfig.fromExtraJson(cur.extraJson));
        return cur.copyWith(extraJson: next.mergeIntoExtraJson(cur.extraJson));
      });
    }

    return [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Bật màn hình phụ'),
        value: cd.enabled,
        onChanged: _saving
            ? null
            : (v) => patchCd((c) => c.copyWith(enabled: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Tự mở khi vào bán hàng'),
        subtitle: const Text('Android: display phụ / Presentation · Web: popup'),
        value: cd.autoOpenOnPos,
        onChanged: _saving || !cd.enabled
            ? null
            : (v) => patchCd((c) => c.copyWith(autoOpenOnPos: v)),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Chiếu ảnh sản phẩm khi chờ'),
        value: cd.useProductImages,
        onChanged: _saving || !cd.enabled
            ? null
            : (v) => patchCd((c) => c.copyWith(useProductImages: v)),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Thời gian đổi ảnh/video'),
        trailing: DropdownButton<int>(
          value: const {3, 5, 8, 10, 15, 20, 30}.contains(cd.idleSeconds)
              ? cd.idleSeconds
              : 8,
          items: const [
            DropdownMenuItem(value: 3, child: Text('3 giây')),
            DropdownMenuItem(value: 5, child: Text('5 giây')),
            DropdownMenuItem(value: 8, child: Text('8 giây')),
            DropdownMenuItem(value: 10, child: Text('10 giây')),
            DropdownMenuItem(value: 15, child: Text('15 giây')),
            DropdownMenuItem(value: 20, child: Text('20 giây')),
            DropdownMenuItem(value: 30, child: Text('30 giây')),
          ],
          onChanged: _saving || !cd.enabled
              ? null
              : (v) {
                  if (v == null) return;
                  patchCd((c) => c.copyWith(idleSeconds: v));
                },
        ),
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('URL video giới thiệu'),
        subtitle: Text(
          cd.promoVideoUrls.isEmpty
              ? 'Chưa có — nhấn để thêm (mỗi dòng một URL)'
              : '${cd.promoVideoUrls.length} video',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.edit_outlined, size: 20),
        onTap: _saving || !cd.enabled
            ? null
            : () => _editPromoVideos(cd, patchCd),
      ),
    ];
  }

  Future<void> _editPromoVideos(
    CustomerDisplayConfig cd,
    Future<void> Function(CustomerDisplayConfig Function(CustomerDisplayConfig))
        patchCd,
  ) async {
    final ctrl = TextEditingController(text: cd.promoVideoUrls.join('\n'));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('URL video promo'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: ctrl,
            maxLines: 6,
            decoration: const InputDecoration(
              hintText: 'https://...\nmỗi dòng một URL',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final urls = ctrl.text
        .split(RegExp(r'[\r\n]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    await patchCd((c) => c.copyWith(promoVideoUrls: urls));
  }
}
