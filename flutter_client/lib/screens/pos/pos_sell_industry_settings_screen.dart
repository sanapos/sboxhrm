import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/pos_product.dart';
import '../../models/pos_sell_industry.dart';
import '../../models/qr_order_lock_config.dart';
import '../../services/api_service.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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

  String get _title {
    final noun = _settings?.sellProfile.resourceNoun;
    return switch (widget.section) {
      'profile' => 'Ngành hàng & chế độ bán',
      'resources' => (noun != null && noun.isNotEmpty)
          ? '${noun[0].toUpperCase()}${noun.substring(1)} / tạm tính'
          : 'Tạm tính & tồn kho',
      _ => 'Ngành hàng & bán hàng',
    };
  }

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
          message: tr('Ngành hàng: ${_settings!.sellProfile.label}'),
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
            title: Text(tr(
                'Còn ${_resourceOpenLabel(prev.sellProfile, list.length)} đang mở')),
            content: Text(tr(
              'Còn ${_resourceOpenLabel(prev.sellProfile, list.length)} đang mở. '
              'Thanh toán hoặc đóng trước khi đổi sang «${v.label}».',
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
        title: Text(tr('Đổi ngành hàng?')),
        content: Text(tr(
          'Chuyển sang «${v.label}» sẽ áp cấu hình mặc định:\n'
          '${v.description}',
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

  String _resourceOpenLabel(PosSellProfile profile, int count) {
    final noun = profile.resourceNoun;
    if (noun.isEmpty) return '$count phiên';
    return '$count $noun';
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
          title: 'Còn phiên đang mở',
          message: tr(
            'Còn ${_resourceOpenLabel(s.sellProfile, list.length)} đang mở. '
            'Đóng trước khi tắt tài nguyên phục vụ.',
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
      children: [
        if (_showProfile) ...[
          Text(tr('Chọn ngành hàng'),
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 4),
          Text(
            tr('Tên ngành quyết định giao diện bán: hàng hóa hay sơ đồ, '
                'bàn/ghế/phòng, báo bếp, tính giờ, gói buổi.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 10),
          ...PosSellProfile.values.map((p) => _profileCard(p, s.sellProfile)),
          const SizedBox(height: 8),
          Text(
            tr('Đổi ngành sẽ lưu ngay và bật sẵn cấu hình mặc định của ngành đó.'),
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
              DropdownMenuItem(
                value: 'quick',
                child: Text(tr('Bán nhanh — quét mã, thanh toán ngay')),
              ),
              DropdownMenuItem(
                value: 'normal',
                child: Text(tr('Bán thường — hóa đơn đủ thông tin')),
              ),
              DropdownMenuItem(
                value: 'delivery',
                child: Text(tr('Giao hàng — địa chỉ, phí ship')),
              ),
            ],
            onChanged: _saving
                ? null
                : (v) {
                    if (v == null) return;
                    _patchAndSave((cur) => cur.copyWith(defaultSellMode: v));
                  },
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Ca thu ngân (mở ca / đóng két)')),
            subtitle: Text(tr(
                'Mỗi tài khoản thu ngân mở ca riêng. Thanh toán bắt buộc có ca mở; '
                'đếm két khi đóng ca. Vào Menu ⋮ trên màn bán hàng → Ca thu ngân.')),
            value: s.enableCashierShift,
            onChanged: _saving
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(enableCashierShift: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Khóa đơn tạm đa máy')),
            subtitle: Text(tr(
                'Bật: máy đang mở đơn tạm giữ khóa — máy khác phải «Nhận bàn» mới sửa. '
                'Tắt: nhiều máy cùng sửa draft (dễ xung đột). Khuyến nghị bật khi ≥2 máy POS.')),
            value: s.enableMultiDeviceDraftLock,
            onChanged: _saving
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(enableMultiDeviceDraftLock: v)),
          ),
          if (_showResources) const Divider(height: 28),
        ],
        if (_showResources) ...[
          Text(
            tr(s.sellProfile.usesFloorPlan
                ? 'Sơ đồ & ${s.sellProfile.resourceNoun}'
                : 'Tạm tính & tồn kho'),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            tr(s.sellProfile.usesFloorPlan
                ? 'Công tắc tự lưu khi đổi. Thuật ngữ theo ngành: ${s.sellProfile.resourceNoun}.'
                : 'Bán lẻ / gym không dùng sơ đồ. Bật tạm tính để in hóa đơn chưa thu tiền.'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(s.sellProfile.floorTabLabel.isEmpty
                ? 'Sơ đồ'
                : s.sellProfile.floorTabLabel)),
            subtitle: Text(tr(s.sellProfile.usesFloorPlan
                ? 'Hiện tab sơ đồ trên màn bán'
                : 'Không dùng với bán lẻ / gym')),
            value: s.showFloorPlan,
            onChanged: _saving || !s.sellProfile.usesFloorPlan
                ? null
                : (v) =>
                    _patchAndSave((cur) => cur.copyWith(showFloorPlan: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(s.sellProfile.resourceNoun.isEmpty
                ? 'Bật tài nguyên phục vụ'
                : 'Bật ${s.sellProfile.resourceNoun} phục vụ')),
            value: s.enableResources,
            onChanged: _saving || !s.sellProfile.usesFloorPlan
                ? null
                : (v) =>
                    _patchAndSave((cur) => cur.copyWith(enableResources: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(s.sellProfile.resourceNoun.isEmpty
                ? 'Bắt buộc chọn tài nguyên khi bán'
                : 'Bắt buộc chọn ${s.sellProfile.resourceNoun} khi bán')),
            value: s.requireResourceOnSale,
            onChanged: _saving || !s.enableResources
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(requireResourceOnSale: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Dịch vụ tính giờ / block / ngày')),
            subtitle: Text(tr(
                'Karaoke, bi-a, khách sạn: phí mở phòng + nhảy tiền theo block phút hoặc theo ngày')),
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
                labelText: tr(s.sellProfile.resourceNoun.isEmpty
                    ? 'SP tính giờ mặc định khi mở phiên'
                    : 'SP tính giờ mặc định khi mở ${s.sellProfile.resourceNoun}'),
                helperText: tr(
                    'Tự thêm vào đơn trống. Có thể ghi đè từng ${s.sellProfile.resourceNoun.isEmpty ? 'tài nguyên' : s.sellProfile.resourceNoun}.'),
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
            title: Text(tr('Gói buổi / liệu trình / thẻ tập')),
            subtitle: Text(tr(
                'Salon, spa, gym: bán gói cộng buổi, check-in trừ buổi, hạn dùng theo ngày')),
            value: s.enableSessionPacks,
            onChanged: _saving ||
                    (s.sellProfile != PosSellProfile.gym &&
                        s.sellProfile != PosSellProfile.salon &&
                        !s.enableSessionPacks)
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(enableSessionPacks: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Cho phép tạm tính')),
            subtitle: Text(tr(s.sellProfile.usesFloorPlan
                ? 'Hiện nút Tạm tính lúc thanh toán — đánh dấu ${s.sellProfile.resourceNoun} và in hóa đơn tạm'
                : 'Hiện nút Tạm tính lúc thanh toán — in chưa thu tiền')),
            value: s.allowProvisionalBill,
            onChanged: _saving
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(allowProvisionalBill: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr(s.sellProfile.resourceNoun.isEmpty
                ? 'Hỏi số khách khi mở phiên'
                : 'Hỏi số khách khi mở ${s.sellProfile.resourceNoun}')),
            subtitle: Text(tr(
                'Bật thì hiện hộp nhập số khách khi mở trống. '
                'Tắt: mở thẳng (mặc định 1 khách).')),
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
                'Bật: vẫn thêm hàng và thanh toán khi tồn khả dụng không đủ '
                '(kho có thể âm). Tắt: chặn thêm/thanh toán khi hết hàng.')),
            value: s.allowNegativeStock,
            onChanged: _saving
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(allowNegativeStock: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('QR order tại bàn')),
            subtitle: Text(tr(
                'Tắt mặc định. Bật thì khách quét QR trên bàn để gọi món; '
                'phiếu bếp in qua Agent, thanh toán vẫn tại quầy.')),
            value: s.enableQrTableOrder,
            onChanged: _saving
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(enableQrTableOrder: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Tự in phiếu bếp khi khách đặt QR')),
            subtitle: Text(tr(
                'Bật: khách gửi món là in phiếu qua Agent. '
                'Tắt: ghi món vào bàn, thu ngân bấm Báo bếp để in.')),
            value: s.enableQrOrderAutoPrint,
            onChanged: _saving || !s.enableQrTableOrder
                ? null
                : (v) => _patchAndSave(
                    (cur) => cur.copyWith(enableQrOrderAutoPrint: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('QR: chỉ gọi món khi đã mở bàn')),
            subtitle: Text(tr(
                'Không cho khách ngoài quán tự mở đơn từ tem QR. '
                'Thu ngân mở bàn rồi khách mới đặt được.')),
            value: QrOrderLockConfig.fromExtraJson(s.extraJson)
                .requireOpenSession,
            onChanged: _saving || !s.enableQrTableOrder
                ? null
                : (v) => _patchAndSave((cur) {
                      final next =
                          QrOrderLockConfig.fromExtraJson(cur.extraJson)
                              .copyWith(requireOpenSession: v);
                      return cur.copyWith(
                        extraJson: next.mergeIntoExtraJson(cur.extraJson),
                      );
                    }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('QR: chỉ gọi món trong phạm vi quán (GPS)')),
            subtitle: Text(tr(
                'Cần vùng chấm công (geofence) quanh quán. '
                'Khách phải bật vị trí — có thể giả GPS trên máy root.')),
            value:
                QrOrderLockConfig.fromExtraJson(s.extraJson).requireGeofence,
            onChanged: _saving || !s.enableQrTableOrder
                ? null
                : (v) => _patchAndSave((cur) {
                      final next =
                          QrOrderLockConfig.fromExtraJson(cur.extraJson)
                              .copyWith(requireGeofence: v);
                      return cur.copyWith(
                        extraJson: next.mergeIntoExtraJson(cur.extraJson),
                      );
                    }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('QR: bật xác nhận order')),
            subtitle: Text(tr(
                'Mặc định tắt. Bật: món không in thẳng xuống bếp — '
                'âm thanh + thông báo để thu ngân xác nhận (Báo bếp).')),
            value: QrOrderLockConfig.fromExtraJson(s.extraJson)
                .requireOrderConfirmation,
            onChanged: _saving || !s.enableQrTableOrder
                ? null
                : (v) => _patchAndSave((cur) {
                      final next =
                          QrOrderLockConfig.fromExtraJson(cur.extraJson)
                              .copyWith(requireOrderConfirmation: v);
                      return cur.copyWith(
                        extraJson: next.mergeIntoExtraJson(cur.extraJson),
                      );
                    }),
          ),
          const Divider(height: 24),
          Text(tr('Báo cáo & cuối ngày'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 4),
          Text(
            tr(
              'Luôn theo giờ VN (UTC+7). '
              'Bật «ngày qua đêm» khi quán bán qua nửa đêm: ví dụ bắt đầu 06:00 → '
              'đơn 01:00 sáng vẫn thuộc ngày KD hôm trước. '
              'Báo cáo doanh thu, cuối ngày và danh sách ca thu ngân dùng cùng giờ này.',
            ),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700, height: 1.4),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(tr('Ngày qua đêm (báo cáo / cuối ngày)')),
            subtitle: Text(tr(s.overnightReportEnabled
                ? 'Ngày KD: ${s.reportDayStartHour.toString().padLeft(2, '0')}:00 → '
                    '${s.reportDayStartHour.toString().padLeft(2, '0')}:00 hôm sau'
                : 'Tắt: theo ngày lịch 00:00–24:00')),
            value: s.overnightReportEnabled,
            onChanged: _saving
                ? null
                : (v) => _patchAndSave((cur) => cur.copyWith(
                      reportDayStartHour: v ? 6 : 0,
                    )),
          ),
          if (s.overnightReportEnabled)
            DropdownButtonFormField<int>(
              value: s.reportDayStartHour.clamp(1, 12),
              decoration: InputDecoration(
                labelText: tr('Giờ bắt đầu ngày kinh doanh'),
                helperText: tr(
                  'Đơn trước giờ này tính vào ngày KD hôm trước. '
                  'Preset «Hôm nay» trên báo cáo = ngày KD hiện tại (không phải lịch dương nếu đã qua giờ).',
                ),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (var h = 1; h <= 12; h++)
                  DropdownMenuItem(
                    value: h,
                    child: Text(tr('${h.toString().padLeft(2, '0')}:00')),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v == null) return;
                      _patchAndSave((cur) => cur.copyWith(reportDayStartHour: v));
                    },
            ),
        ],
      ],
    );
  }

  IconData _profileIcon(PosSellProfile p) => switch (p) {
        PosSellProfile.retail => Icons.storefront_outlined,
        PosSellProfile.salon => Icons.content_cut_outlined,
        PosSellProfile.roomHourly => Icons.meeting_room_outlined,
        PosSellProfile.restaurant => Icons.restaurant_outlined,
        PosSellProfile.gym => Icons.fitness_center_outlined,
        PosSellProfile.hotel => Icons.hotel_outlined,
      };

  Widget _profileCard(PosSellProfile p, PosSellProfile selected) {
    final on = p == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? PosTheme.kiotBlueLight : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: on ? PosTheme.kiotBlue : PosTheme.border,
            width: on ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: _saving ? null : () => unawaited(_onProfileChanged(p)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _profileIcon(p),
                  color: on ? PosTheme.kiotBlue : Colors.grey.shade600,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(p.label),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: on ? PosTheme.kiotBlue : PosTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tr(p.description),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final h in p.featureHints)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: on
                                    ? Colors.white
                                    : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                tr(h),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: on
                                      ? PosTheme.kiotBlue
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (on)
                  const Icon(Icons.check_circle, color: PosTheme.kiotBlue),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
