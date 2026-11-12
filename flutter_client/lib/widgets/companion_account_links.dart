import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../l10n/app_tr.dart';
import '../providers/auth_provider.dart';
import '../theme/sbox_tokens.dart';
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

/// Mở [CompanionAccountLinks] thành trang riêng (menu màn bếp KDS): tài khoản đang đăng nhập, các liên kết, phiên bản.
class CompanionAccountScreen extends StatefulWidget {
  const CompanionAccountScreen({super.key});

  @override
  State<CompanionAccountScreen> createState() => _CompanionAccountScreenState();
}

class _CompanionAccountScreenState extends State<CompanionAccountScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'v${info.version} (${info.buildNumber})');
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, ({String name, String email})>(
        (a) => (name: a.user?.fullName ?? '', email: a.user?.email ?? ''));
    final name = user.name.trim();
    return Scaffold(
      appBar: AppBar(title: Text(tr('Thông tin & tài khoản'))),
      body: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: SboxColors.brand600,
                child: Text(
                  name.isEmpty ? '?' : name[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: SboxColors.textMuted, fontSize: 13)),
                ]),
              ),
            ]),
          ),
          const Divider(height: 16),
          const CompanionAccountLinks(),
          if (_version.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(_version, textAlign: TextAlign.center,
                  style: const TextStyle(color: SboxColors.textMuted, fontSize: 12)),
            ),
        ]),
      ),
    );
  }
}
