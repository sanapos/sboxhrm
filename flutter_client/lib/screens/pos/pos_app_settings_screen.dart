import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_tr.dart';
import '../../providers/auth_provider.dart';
import '../../providers/permission_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/navigation_notifier.dart';
import '../../utils/permission_navigation.dart';
import '../../widgets/pos/pos_mobile_widgets.dart';
import '../../widgets/pos/pos_theme.dart';
import '../app_info_screen.dart';
import '../settings_hub_screen.dart';

/// Cài đặt app POS độc lập: ngôn ngữ, phiên bản, điều khoản — không OTA APK (Play).
class PosAppSettingsScreen extends StatefulWidget {
  const PosAppSettingsScreen({super.key});

  @override
  State<PosAppSettingsScreen> createState() => _PosAppSettingsScreenState();
}

class _PosAppSettingsScreenState extends State<PosAppSettingsScreen> {
  String _versionLabel = '…';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _versionLabel = '${info.version} (${info.buildNumber})');
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = '—');
    }
  }

  Future<void> _pickLanguage() async {
    final theme = context.read<ThemeProvider>();
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Chọn ngôn ngữ')),
        children: [
          RadioListTile<String>(
            value: 'vi',
            groupValue: theme.locale.languageCode,
            title: const Text('Tiếng Việt'),
            onChanged: (v) => Navigator.pop(ctx, v),
          ),
          RadioListTile<String>(
            value: 'en',
            groupValue: theme.locale.languageCode,
            title: const Text('English'),
            onChanged: (v) => Navigator.pop(ctx, v),
          ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    if (picked == theme.locale.languageCode) return;
    await theme.setLocale(Locale(picked));
    if (mounted) setState(() {});
  }

  void _openInfo(String type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AppInfoScreen(type: type),
      ),
    );
  }

  void _openPosHub() {
    SettingsHubScreen.pendingSubIndex.value = null;
    if (NavigationNotifier.mainLayoutReady.value) {
      NavigationNotifier.navigateToModule.value = 'SettingsHub';
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsHubScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final perm = Provider.of<PermissionProvider>(context);
    final theme = Provider.of<ThemeProvider>(context);
    final user = auth.user;
    final canPosHub = PermissionNavigation.canNavigate(perm, 'PosSell') ||
        PermissionNavigation.canNavigate(perm, 'PosProducts') ||
        PermissionNavigation.canNavigate(perm, 'SettingsHub');
    final langLabel =
        theme.locale.languageCode == 'en' ? 'English' : 'Tiếng Việt';

    return Scaffold(
      backgroundColor: PosTheme.background,
      appBar: AppBar(
        title: Text(tr('Cài đặt')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _card(
            children: [
              ListTile(
                leading:
                    const Icon(Icons.person_outline, color: PosTheme.kiotBlue),
                title: Text(
                  tr(user?.fullName ?? 'Tài khoản'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  user?.email.isNotEmpty == true
                      ? user!.email
                      : tr('Cửa hàng POS'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            children: [
              ListTile(
                leading: const Icon(Icons.language, color: PosTheme.kiotBlue),
                title: Text(tr('Ngôn ngữ')),
                subtitle: Text(langLabel),
                trailing: const Icon(Icons.chevron_right),
                onTap: _pickLanguage,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline, color: PosTheme.kiotBlue),
                title: Text(tr('Phiên bản')),
                subtitle: Text(tr('SBOX POS $_versionLabel')),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined,
                    color: PosTheme.kiotBlue),
                title: Text(tr('Điều khoản sử dụng')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openInfo('terms'),
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined,
                    color: PosTheme.kiotBlue),
                title: Text(tr('Chính sách bảo mật')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openInfo('privacy'),
              ),
              const Divider(height: 1),
              ListTile(
                leading:
                    const Icon(Icons.help_outline, color: PosTheme.kiotBlue),
                title: Text(tr('Trợ giúp')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openInfo('help'),
              ),
            ],
          ),
          if (canPosHub) ...[
            const SizedBox(height: 12),
            _card(
              children: [
                ListTile(
                  leading:
                      const Icon(Icons.tune_outlined, color: PosTheme.kiotBlue),
                  title: Text(tr('Thiết lập POS')),
                  subtitle: Text(tr('Cửa hàng, ngành hàng, máy in…')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _openPosHub,
                ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => showPosLogoutDialog(context),
            icon: const Icon(Icons.logout, color: Colors.red),
            label: Text(
              tr('Đăng xuất'),
              style: TextStyle(
                color: Colors.red.shade700,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required List<Widget> children}) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Column(children: children),
    );
  }
}
