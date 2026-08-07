import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../../services/api_service.dart';
import '../../widgets/admin/admin_mobile_widgets.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class AgentProfileTab extends StatefulWidget {
  final ValueChanged<Map<String, dynamic>>? onProfileLoaded;

  const AgentProfileTab({super.key, this.onProfileLoaded});

  @override
  State<AgentProfileTab> createState() => AgentProfileTabState();
}

class AgentProfileTabState extends State<AgentProfileTab> {
  final _apiService = ApiService();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> loadProfile() async {
    setState(() => _loading = true);
    try {
      final res = await _apiService.getAgentProfile();
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        setState(() {
          _profile = data;
          _phoneCtrl.text = data['phone']?.toString() ?? '';
          _addressCtrl.text = data['address']?.toString() ?? '';
          _descCtrl.text = data['description']?.toString() ?? '';
        });
        widget.onProfileLoaded?.call(data);
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      debugPrint('AgentProfileTab.loadProfile: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final res = await _apiService.updateAgentProfile(
        phone: _phoneCtrl.text.trim(),
        address: _addressCtrl.text.trim(),
        description: _descCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = Map<String, dynamic>.from(res['data'] as Map);
        setState(() => _profile = data);
        widget.onProfileLoaded?.call(data);
        AdminHelpers.showSuccess(context, 'Đã lưu thông tin đại lý');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: tr(link)));
    NotificationOverlayManager().showSuccess(
      title: 'Sao chép',
      message: tr('Đã sao chép link giới thiệu'),
    );
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    var showCurrent = false;
    var showNew = false;
    var showConfirm = false;
    var isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submit() async {
            final current = currentCtrl.text.trim();
            final newPassword = newCtrl.text;
            final confirm = confirmCtrl.text;

            if (current.isEmpty) {
              NotificationOverlayManager().showWarning(
                title: 'Thiếu thông tin',
                message: tr('Vui lòng nhập mật khẩu hiện tại'),
              );
              return;
            }
            if (newPassword.length < 6) {
              NotificationOverlayManager().showWarning(
                title: 'Mật khẩu quá ngắn',
                message: tr('Mật khẩu mới phải có ít nhất 6 ký tự'),
              );
              return;
            }
            if (newPassword == current) {
              NotificationOverlayManager().showWarning(
                title: 'Không hợp lệ',
                message: tr('Mật khẩu mới phải khác mật khẩu hiện tại'),
              );
              return;
            }
            if (newPassword != confirm) {
              NotificationOverlayManager().showWarning(
                title: 'Không khớp',
                message: tr('Mật khẩu xác nhận không khớp'),
              );
              return;
            }

            setDialogState(() => isSaving = true);
            try {
              final res = await _apiService.updateOwnPassword(
                currentPassword: current,
                newPassword: newPassword,
              );
              if (!ctx.mounted) return;
              if (res['isSuccess'] == true) {
                Navigator.pop(ctx);
                NotificationOverlayManager().showSuccess(
                  title: 'Thành công',
                  message: tr('Đã đổi mật khẩu'),
                );
              } else {
                NotificationOverlayManager().showError(
                  title: 'Lỗi',
                  message: res['message']?.toString() ?? 'Không thể đổi mật khẩu',
                );
              }
            } finally {
              if (ctx.mounted) setDialogState(() => isSaving = false);
            }
          }

          return ScrollableAlertDialog(
            title: Text(tr('Đổi mật khẩu')),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _passwordField(
                    controller: currentCtrl,
                    label: 'Mật khẩu hiện tại',
                    obscure: !showCurrent,
                    onToggle: () =>
                        setDialogState(() => showCurrent = !showCurrent),
                  ),
                  const SizedBox(height: 12),
                  _passwordField(
                    controller: newCtrl,
                    label: 'Mật khẩu mới',
                    obscure: !showNew,
                    onToggle: () => setDialogState(() => showNew = !showNew),
                  ),
                  const SizedBox(height: 12),
                  _passwordField(
                    controller: confirmCtrl,
                    label: 'Xác nhận mật khẩu mới',
                    obscure: !showConfirm,
                    onToggle: () =>
                        setDialogState(() => showConfirm = !showConfirm),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text(tr('Hủy')),
              ),
              FilledButton(
                onPressed: isSaving ? null : submit,
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('Lưu')),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback onToggle,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: tr(label),
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
          onPressed: onToggle,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_profile == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.support_agent, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(tr('Không tải được hồ sơ đại lý')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: loadProfile,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(tr('Thử lại')),
            ),
          ],
        ),
      );
    }

    final p = _profile!;
    final referralLink = p['referralLink']?.toString() ?? '';

    return RefreshIndicator(
      onRefresh: loadProfile,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: adminTabPadding(context),
        children: [
          _buildHeaderCard(p),
          const SizedBox(height: 16),
          _buildStatsRow(p),
          const SizedBox(height: 16),
          _sectionTitle('Thông tin liên hệ'),
          const SizedBox(height: 10),
          _infoTile(Icons.email_outlined, 'Email đăng nhập',
              p['email']?.toString() ?? '—'),
          const SizedBox(height: 12),
          AdminHelpers.dialogField(
            _phoneCtrl,
            'Số điện thoại / Zalo',
            Icons.phone,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: tr('Địa chỉ'),
              prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: tr('Giới thiệu về đại lý'),
              prefixIcon: const Icon(Icons.info_outline, size: 20),
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveProfile,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(tr('Lưu thông tin')),
            ),
          ),
          const SizedBox(height: 24),
          _sectionTitle('Link giới thiệu cửa hàng'),
          const SizedBox(height: 8),
          Text(tr('Gửi link này cho khách hàng đăng ký cửa hàng dưới mã đại lý của bạn.'),
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          const SizedBox(height: 10),
          if (referralLink.isNotEmpty) _linkBox(referralLink),
          const SizedBox(height: 24),
          _sectionTitle('Bảo mật'),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _showChangePasswordDialog,
            icon: const Icon(Icons.lock_outline),
            label: Text(tr('Đổi mật khẩu đăng nhập')),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(Map<String, dynamic> p) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AdminHelpers.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.business, color: AdminHelpers.primary, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(p['name']?.toString() ?? 'Đại lý'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(tr('${tr('Mã đại lý: ')}${p['code'] ?? '—'}'),
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow(Map<String, dynamic> p) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _statChip(
          'Đăng ký',
          '${AdminHelpers.agentTotalStores(p)}',
        ),
        _statChip(
          'Kích hoạt',
          '${AdminHelpers.agentActivatedStores(p)}',
        ),
        _statChip(
          'Dùng thử',
          '${AdminHelpers.agentTrialStores(p)}',
        ),
        _statChip('Key còn', '${AdminHelpers.agentAvailableKeys(p)}'),
        _statChip('Key đã dùng', '${AdminHelpers.agentUsedKeys(p)}'),
        _statChip(
          'Quỹ gia hạn',
          '${AdminHelpers.agentRenewalBalance(p)} ngày',
        ),
      ],
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr(value),
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 16)),
          Text(tr(label), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      tr(title),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AdminHelpers.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(label),
                    style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text(tr(value), style: const TextStyle(fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _linkBox(String link) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminHelpers.surfaceBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectableText(tr(link), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _copyLink(link),
              icon: const Icon(Icons.copy, size: 16),
              label: Text(tr('Sao chép link')),
            ),
          ),
        ],
      ),
    );
  }
}
