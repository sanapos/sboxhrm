import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../app_responsive_dialog.dart';
import '../sbox/sbox_ui.dart';
import 'settings_page.dart';

/// Thiết lập SBOX › Tham số hệ thống: cài / xóa dữ liệu mẫu của cửa hàng (chỉ người có quyền sửa).
/// Trước đây nằm trong «Cài đặt» cá nhân — đây là thao tác trên dữ liệu cả cửa hàng.
class SampleDataSection extends StatefulWidget {
  const SampleDataSection({super.key});

  @override
  State<SampleDataSection> createState() => _SampleDataSectionState();
}

class _SampleDataSectionState extends State<SampleDataSection> {
  bool _seeding = false;
  bool _deleting = false;

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(tr(m)),
        backgroundColor: error ? SboxColors.danger : null,
        behavior: SnackBarBehavior.floating,
      ));

  Future<String?> _storeIdentifier() async {
    final id = context.read<AuthProvider>().user?.storeId ?? '';
    if (id.isNotEmpty) return id;
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('saved_store_code') ?? '';
    return code.isEmpty ? null : code;
  }

  Future<bool> _confirm(String title, String message, String action, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr(title)),
        content: Text(tr(message)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Hủy'))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: danger ? ElevatedButton.styleFrom(backgroundColor: SboxColors.danger, foregroundColor: Colors.white) : null,
            child: Text(tr(action)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run({required bool seed}) async {
    final ok = seed
        ? await _confirm(_seedTitle, _seedConfirm, _seedTitle)
        : await _confirm(_deleteTitle, _deleteConfirm, 'Xóa', danger: true);
    if (!ok || !mounted) return;
    final store = await _storeIdentifier();
    if (!mounted) return;
    if (store == null) return _toast('Không tìm thấy mã cửa hàng. Vui lòng đăng nhập lại.', error: true);
    setState(() => seed ? _seeding = true : _deleting = true);
    try {
      final r = seed ? await ApiService().seedSampleData(store) : await ApiService().deleteSampleData(store);
      if (!mounted) return;
      if (r['isSuccess'] == true) {
        final d = r['data'];
        _toast(seed ? 'Đã cài dữ liệu mẫu' : (d is Map && d['message'] != null ? '${d['message']}' : 'Đã xóa dữ liệu mẫu'));
      } else {
        _toast('${r['message'] ?? (seed ? 'Không cài được dữ liệu mẫu' : 'Không xóa được dữ liệu mẫu')}', error: true);
      }
    } catch (e) {
      if (mounted) _toast('${seed ? 'Không cài được' : 'Không xóa được'} dữ liệu mẫu: $e', error: true);
    } finally {
      if (mounted) setState(() => seed ? _seeding = false : _deleting = false);
    }
  }

  static const _seedTitle = 'Cài dữ liệu mẫu';
  static const _seedDesc =
      'HRM: 10 NV + 15 ngày. POS: hàng và bàn/ghế/phòng theo ngành cửa hàng. Nếu đã có nhân viên, chỉ thêm mẫu POS (không trùng tên).';
  static const _seedConfirm =
      'Cài dữ liệu mẫu? Nếu cửa hàng chưa có NV: tạo 10 NV demo + hàng POS theo ngành. Nếu đã có NV: chỉ thêm hàng/bàn POS mẫu, không đụng nhân viên thật.';
  static const _deleteTitle = 'Xóa dữ liệu mẫu';
  static const _deleteDesc = 'Xóa nhân viên demo, chấm công, phép và hàng/bàn POS mẫu';
  static const _deleteConfirm =
      'Xóa dữ liệu mẫu HRM + POS? Hàng/bàn đã bán thật sẽ không xóa được nếu đang được dùng. Không hoàn tác.';

  @override
  Widget build(BuildContext context) {
    Widget busy() => const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
    return SettingsSection(
      title: 'Dữ liệu mẫu',
      subtitle: 'Thêm dữ liệu minh họa để làm quen phần mềm, xóa đi trước khi dùng thật',
      icon: Icons.dataset_outlined,
      children: [
        SettingsTile(
          divider: false,
          label: _seedTitle,
          help: _seedDesc,
          control: OutlinedButton.icon(
            onPressed: _seeding || _deleting ? null : () => _run(seed: true),
            icon: _seeding ? busy() : const Icon(Icons.add_circle_outline_rounded, size: 18),
            label: Text(tr('Cài')),
          ),
        ),
        SettingsTile(
          label: _deleteTitle,
          help: _deleteDesc,
          control: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: SboxColors.danger),
            onPressed: _seeding || _deleting ? null : () => _run(seed: false),
            icon: _deleting ? busy() : const Icon(Icons.delete_sweep_outlined, size: 18),
            label: Text(tr('Xóa')),
          ),
        ),
      ],
    );
  }
}
