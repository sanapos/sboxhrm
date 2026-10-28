import '../../widgets/hrm_page_chrome.dart';
import 'package:flutter/material.dart';

import '../../models/cancel_return_reason_config.dart';
import '../../models/pos_after_bill_approval_config.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/settings/settings_page.dart';
import 'pos_cancel_return_history_screen.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Thiết lập kiểm soát lý do hủy / trả + lối vào lịch sử.
class PosCancelReturnSettingsScreen extends StatefulWidget {
  const PosCancelReturnSettingsScreen({super.key});

  @override
  State<PosCancelReturnSettingsScreen> createState() =>
      _PosCancelReturnSettingsScreenState();
}

class _PosCancelReturnSettingsScreenState
    extends State<PosCancelReturnSettingsScreen> {
  late final PosSellSettingsHelper _helper =
      PosSellSettingsHelper(ApiService());
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
    final r = await _helper.load();
    if (!mounted) return;
    setState(() {
      _settings = r.settings;
      _error = r.error;
      _loading = false;
    });
  }

  Future<void> _patchCfg(
    CancelReturnReasonConfig Function(CancelReturnReasonConfig) fn,
  ) async {
    final s = _settings;
    if (s == null || _saving) return;
    final next = fn(CancelReturnReasonConfig.fromExtraJson(s.extraJson));
    final patched =
        s.copyWith(extraJson: next.mergeIntoExtraJson(s.extraJson));
    setState(() {
      _settings = patched;
      _saving = true;
    });
    final r = await _helper.save(patched);
    if (!mounted) return;
    setState(() => _saving = false);
    if (r.settings != null) {
      setState(() => _settings = r.settings);
    } else {
      NotificationOverlayManager().showError(
        title: 'Lỗi',
        message: r.error ?? 'Không lưu được',
      );
      await _load();
    }
  }

  Future<void> _setAfterBillApproval(bool v) async {
    final s = _settings;
    if (s == null || _saving) return;
    final patched = s.copyWith(extraJson: PosAfterBillApprovalConfig.merge(s.extraJson, v));
    setState(() {
      _settings = patched;
      _saving = true;
    });
    final r = await _helper.save(patched);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (r.settings != null) _settings = r.settings;
    });
    if (r.settings == null) {
      NotificationOverlayManager().showError(title: 'Lỗi', message: r.error ?? 'Không lưu được');
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = CancelReturnReasonConfig.fromExtraJson(_settings?.extraJson);
    final page = SettingsPage(
      title: 'Kiểm soát hủy / trả',
      subtitle: 'Bắt buộc lý do khi hủy / trả, xem lại lịch sử để chống gian lận',
      icon: Icons.rule_folder_outlined,
      loading: _loading,
      error: _error,
      onRetry: _load,
      saving: _saving,
      children: [
        SettingsSection(
          title: 'Lý do hủy / trả',
          subtitle: 'Hủy món đã báo bếp luôn hỏi lý do (thao tác sai, khách yêu cầu, nhập tùy ý)',
          icon: Icons.fact_check_outlined,
          children: [
            SettingsTile(
              label: 'Bắt buộc chọn lý do',
              help: 'Áp dụng cả hủy đơn đã hoàn thành và trả hàng',
              control: Switch(
                value: cfg.enabled,
                onChanged: _saving ? null : (v) => _patchCfg((c) => c.copyWith(enabled: v)),
              ),
            ),
            SettingsLinkTile(
              icon: Icons.history_rounded,
              label: 'Lịch sử hủy / trả',
              help: 'Lọc theo thao tác, nhân viên, thời gian; xem trước / sau tạm tính',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PosCancelReturnHistoryScreen()),
              ),
            ),
          ],
        ),
        // Tùy chọn này thuộc «Cho phép tạm tính» — chỉ hiện khi cửa hàng đang dùng tạm tính.
        if (_settings?.allowProvisionalBill == true)
          SettingsSection(
            title: 'Sau tạm tính',
            subtitle: 'Khách đã cầm phiếu tạm tính — chặn giảm tiền khi không có quản lý',
            icon: Icons.admin_panel_settings_outlined,
            children: [
              SettingsTile(
                label: 'Cần quản lý duyệt',
                help: 'Hủy món, hủy / xóa đơn, thu ít hơn phiếu tạm tính: chủ / quản lý nhập mật khẩu trên máy để duyệt. '
                    'Người duyệt được ghi vào lịch sử.',
                control: Switch(
                  value: PosAfterBillApprovalConfig.enabledIn(_settings?.extraJson),
                  onChanged: _saving ? null : _setAfterBillApproval,
                ),
              ),
            ],
          ),
      ],
    );
    if (HrmPageChrome.isHubBody(context)) return page;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Kiểm soát hủy / trả'))),
      body: page,
    );
  }
}
