import 'package:flutter/material.dart';

import '../../models/cancel_return_reason_config.dart';
import '../../models/pos_sell_industry.dart';
import '../../services/api_service.dart';
import '../../utils/pos_sell_settings_helper.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_theme.dart';
import 'pos_cancel_return_history_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

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
        title: Text(tr('Kiểm soát hủy / trả')),
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
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildBody() {
    final cfg = CancelReturnReasonConfig.fromExtraJson(_settings?.extraJson);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('Hủy món đã báo bếp luôn hỏi lý do (Thao tác sai / Khách yêu cầu / nhập tùy ý). '
              'Bật thêm thì hủy đơn hoàn thành và trả hàng cũng phải chọn lý do.'),
          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(tr('Bắt buộc chọn lý do hủy / trả')),
          subtitle: Text(
              tr('Áp dụng hủy đơn hoàn thành và trả hàng (hủy món bếp luôn bắt buộc)')),
          value: cfg.enabled,
          onChanged: _saving
              ? null
              : (v) => _patchCfg((c) => c.copyWith(enabled: v)),
        ),
        const Divider(height: 28),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history, color: PosTheme.kiotBlue),
          title: Text(tr('Lịch sử hủy / trả')),
          subtitle: Text(
              tr('Lọc thao tác, trước/sau tạm tính, nhân viên, thời gian')),
          trailing: const Icon(Icons.chevron_right),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const PosCancelReturnHistoryScreen(),
              ),
            );
          },
        ),
      ],
    );
  }
}
