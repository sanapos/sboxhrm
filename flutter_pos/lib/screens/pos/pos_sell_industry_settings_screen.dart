import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Thiết lập hồ sơ ngành / tài nguyên (tách khỏi màn phụ & hủy-trả).
///
/// [section]: `profile` | `resources` | `all` (legacy).
class PosSellIndustrySettingsScreen extends StatefulWidget {
  const PosSellIndustrySettingsScreen({
    super.key,
    this.embeddedInSettings = false,
    this.section = 'all',
  });

  final bool embeddedInSettings;
  /// `profile` | `resources` | `all`
  final String section;

  @override
  State<PosSellIndustrySettingsScreen> createState() =>
      _PosSellIndustrySettingsScreenState();
}

class _PosSellIndustrySettingsScreenState
    extends State<PosSellIndustrySettingsScreen> {
  late final PosSellSettingsHelper _helper =
      PosSellSettingsHelper(ApiService());
  PosStoreSellSettingsDto? _settings;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<PosProduct> _timedProducts = [];

  bool get _showProfile =>
      widget.section == 'all' || widget.section == 'profile';
  bool get _showResources =>
      widget.section == 'all' || widget.section == 'resources';

  String get _title => switch (widget.section) {
        'profile' => 'Hồ sơ ngành & chế độ bán',
        'resources' => 'Bàn / tài nguyên / tạm tính',
        _ => 'Ngành hàng & bán hàng',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _loadTimedProducts() async {
    final res = await ApiService().getPosProducts(
      productType: PosProductType.service,
      pageSize: 200,
      sortBy: PosProductSortBy.name,
      sortDesc: false,
    );
    if (!mounted) return;
    final raw = res['data'];
    final items = raw is Map
        ? (raw['items'] ?? raw['Items'])
        : raw is List
            ? raw
            : null;
    final list = <PosProduct>[];
    if (items is List) {
      for (final e in items) {
        if (e is! Map) continue;
        final p = PosProduct.fromJson(Map<String, dynamic>.from(e));
        if (p.isTimedService) list.add(p);
      }
    }
    setState(() => _timedProducts = list);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final r = await _helper.load();
    if (!mounted) return;
    setState(() {
      _settings = r.settings;
      _error = r.error;
      _loading = false;
    });
    if (_showResources) unawaited(_loadTimedProducts());
  }

  Future<void> _save({
    required bool applyDefaults,
    bool quiet = false,
  }) async {
    final s = _settings;
    if (s == null || _saving) return;
    setState(() => _saving = true);
    final r = await _helper.save(s, applyDefaults: applyDefaults);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.settings != null) {
      setState(() => _settings = r.settings);
      if (!quiet) {
        NotificationOverlayManager().showSuccess(
          title: 'Đã lưu',
          message: tr('Hồ sơ ngành: ${_settings!.sellProfile.label}'),
        );
      }
    } else {
      NotificationOverlayManager().showError(
        title: r.status == 403 ? 'Không có quyền' : 'Lỗi',
        message: r.status == 403
            ? 'Tài khoản không có quyền sửa bán hàng / hàng hóa.'
            : (r.error ?? 'Không lưu được'),
      );
      await _load();
    }
  }

  Future<void> _onProfileChanged(PosSellProfile? v) async {
    if (v == null || _settings == null) return;
    final prev = _settings!;
    if (prev.sellProfile == v) return;

    final next = prev.withProfileDefaults(v);
    final disablingResources = prev.enableResources && !next.enableResources;
    if (disablingResources) {
      final openRes = await ApiService().getPosOpenResourceSessions();
      if (!mounted) return;
      final list = openRes['data'] is List ? openRes['data'] as List : const [];
      if (list.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(tr('Còn bàn đang mở')),
            content: Text(tr(
              'Còn ${list.length} bàn/phiên đang mở. '
              'Thanh toán hoặc đóng bàn trước khi đổi sang «${v.label}».',
            )),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Đã hiểu')),
              ),
            ],
          ),
        );
        setState(() {}); // giữ dropdown giá trị cũ
        return;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đổi hồ sơ ngành?')),
        content: Text(tr(
          'Chuyển sang «${v.label}» sẽ áp cấu hình mặc định '
          '(bàn, sơ đồ, tạm tính, tính giờ, gói buổi).',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Đổi ngành')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      setState(() {});
      return;
    }

    setState(() => _settings = next);
    await _save(applyDefaults: true);
  }

  Future<void> _patchAndSave(
    PosStoreSellSettingsDto Function(PosStoreSellSettingsDto) patch,
  ) async {
    final s = _settings;
    if (s == null) return;
    final next = patch(s);
    if (s.enableResources && !next.enableResources) {
      final openRes = await ApiService().getPosOpenResourceSessions();
      if (!mounted) return;
      final list = openRes['data'] is List ? openRes['data'] as List : const [];
      if (list.isNotEmpty) {
        NotificationOverlayManager().showError(
          title: 'Còn bàn đang mở',
          message: tr(
            'Còn ${list.length} bàn/phiên đang mở. '
            'Đóng bàn trước khi tắt tài nguyên phục vụ.',
          ),
        );
        setState(() {});
        return;
      }
    }
    setState(() => _settings = next);
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
                    Text(tr(_error!), style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 12),
                    FilledButton(onPressed: _load, child: Text(tr('Thử lại'))),
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
                    Expanded(
                      child: Text(tr(_title),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          )),
                    ),
                    if (_saving)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        tooltip: tr('Tải lại'),
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
        title: Text(tr(_title)),
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
              tooltip: tr('Tải lại'),
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
        if (_showProfile) ...[
          Text(tr('Hồ sơ ngành'),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<PosSellProfile>(
            value: s.sellProfile,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: PosSellProfile.values
                .map((p) =>
                    DropdownMenuItem(value: p, child: Text(tr(p.label))))
                .toList(),
            onChanged: _saving ? null : _onProfileChanged,
          ),
          const SizedBox(height: 8),
          Text(
            tr('Đổi ngành sẽ lưu ngay và bật sẵn bàn/ghế, tính giờ hoặc gói buổi.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const Divider(height: 28),
          Text(tr('Chế độ bán mặc định'),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value:
                const {'quick', 'normal', 'delivery'}.contains(s.defaultSellMode)
                    ? s.defaultSellMode
                    : 'quick',
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: 'quick', child: Text(tr('Bán nhanh'))),
              DropdownMenuItem(value: 'normal', child: Text(tr('Bán thường'))),
              DropdownMenuItem(
                  value: 'delivery', child: Text(tr('Giao hàng'))),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v == null) return;
                    _patchAndSave((cur) => cur.copyWith(defaultSellMode: v));
                  },
          ),
          if (_showResources) const Divider(height: 28),
        ],
        if (_showResources) ...[
          Text(tr('Tài nguyên phục vụ'),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            tr(s.sellProfile == PosSellProfile.retail
                ? 'Đổi hồ sơ ngành (F&B / salon / …) để bật bàn và sơ đồ.'
                : 'Công tắc tự lưu khi đổi.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Sơ đồ bàn / ghế / phòng')),
            subtitle: Text(tr('F&B, salon, karaoke')),
            value: s.showFloorPlan,
            onChanged: _saving || s.sellProfile == PosSellProfile.retail
                ? null
                : (v) =>
                    _patchAndSave((cur) => cur.copyWith(showFloorPlan: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bật tài nguyên phục vụ')),
            value: s.enableResources,
            onChanged: _saving || s.sellProfile == PosSellProfile.retail
                ? null
                : (v) =>
                    _patchAndSave((cur) => cur.copyWith(enableResources: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Bắt buộc chọn bàn/phòng khi bán')),
            value: s.requireResourceOnSale,
            onChanged: _saving || !s.enableResources
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(requireResourceOnSale: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Dịch vụ tính theo giờ/phút')),
            value: s.enableHourlyBilling,
            onChanged: _saving || s.sellProfile == PosSellProfile.retail
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(enableHourlyBilling: v)),
          ),
          if (s.enableHourlyBilling) ...[
            const SizedBox(height: 4),
            DropdownButtonFormField<String?>(
              value: () {
                final id = s.defaultHourlyProductId;
                if (id == null || id.isEmpty) return null;
                if (_timedProducts.any((p) => p.id == id)) return id;
                return null;
              }(),
              decoration: InputDecoration(
                labelText: tr('SP tính giờ mặc định khi mở bàn'),
                helperText: tr(
                    'Tự thêm vào đơn trống. Có thể ghi đè từng bàn/phòng.'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(tr('— Không tự thêm —')),
                ),
                ..._timedProducts.map(
                  (p) => DropdownMenuItem<String?>(
                    value: p.id,
                    child: Text(tr(p.name), overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (v) => _patchAndSave((cur) => v == null
                      ? cur.copyWith(clearDefaultHourlyProductId: true)
                      : cur.copyWith(defaultHourlyProductId: v)),
            ),
            const SizedBox(height: 8),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Gói buổi (Gym)')),
            subtitle: Text(tr('Mua gói cộng buổi, check-in trừ buổi')),
            value: s.enableSessionPacks,
            onChanged: _saving ||
                    (s.sellProfile != PosSellProfile.gym &&
                        !s.enableSessionPacks)
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(enableSessionPacks: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Cho phép tạm tính')),
            subtitle: Text(
                tr('Hiện nút Tạm tính — đánh dấu bàn và in hóa đơn tạm')),
            value: s.allowProvisionalBill,
            onChanged: _saving || !s.enableResources
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(allowProvisionalBill: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Hỏi số khách khi mở bàn')),
            subtitle: Text(tr(
                'Bật thì hiện hộp nhập số khách khi mở bàn trống. '
                'Tắt: mở bàn thẳng (mặc định 1 khách — sửa sau trên bàn).')),
            value: s.promptGuestCountOnOpen,
            onChanged: _saving || !s.enableResources
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(promptGuestCountOnOpen: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Cho phép bán khi hết hàng / tồn âm')),
            subtitle: Text(tr(
                'Bật: vẫn thêm món và thanh toán khi tồn khả dụng không đủ '
                '(kho có thể âm). Tắt: chặn thêm/thanh toán khi hết hàng.')),
            value: s.allowNegativeStock,
            onChanged: _saving
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(allowNegativeStock: v)),
          ),
        ],
      ],
    );
  }
}
