import 'package:flutter/material.dart';

import '../l10n/app_tr.dart';
import '../screens/app_info_screen.dart';
import 'delete_account_dialog.dart';

/// Điều khoản, chính sách, trợ giúp, xóa tài khoản cho app không có trang «Cài đặt» (BOSS, KDS).
class CompanionAccountLinks extends StatelessWidget {
  const CompanionAccountLinks({super.key});

  void _open(BuildContext context, String type) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AppInfoScreen(type: type)));
  }

  @override
  Widget build(BuildContext context) {
    const danger = Color(0xFFB91C1C);
    Widget link(IconData icon, String label, String type) => ListTile(
          leading: Icon(icon),
          title: Text(tr(label)),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(context, type),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      link(Icons.description_outlined, 'Điều khoản sử dụng', 'terms'),
      link(Icons.privacy_tip_outlined, 'Chính sách bảo mật', 'privacy'),
      link(Icons.help_outline_rounded, 'Trợ giúp', 'help'),
      link(Icons.bug_report_outlined, 'Báo lỗi & Góp ý', 'bugreport'),
      ListTile(
        leading: const Icon(Icons.person_remove_outlined, color: danger),
        title: Text(tr('Xóa tài khoản'), style: const TextStyle(color: danger)),
        onTap: () => showDeleteAccountDialog(context),
      ),
    ]);
  }
}

/// Mở [CompanionAccountLinks] thành trang riêng (menu màn bếp KDS).
class CompanionAccountScreen extends StatelessWidget {
  const CompanionAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Thông tin & tài khoản'))),
      body: const SingleChildScrollView(child: CompanionAccountLinks()),
    );
  }
}
