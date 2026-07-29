import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../utils/responsive_helper.dart';
import '../widgets/mobile_bottom_nav_config_sheet.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'app_info_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _serverUrl = ApiService.baseUrl;
  bool _isDeletingSampleData = false;
  bool _isSeedingSampleData = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    await SharedPreferences.getInstance();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final canManageData =
        Provider.of<PermissionProvider>(context, listen: false)
            .canEdit('SystemSettings');
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(l.settingsTitle),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr(l.settingsSubtitle),
              style: TextStyle(color: Colors.grey[400]),
            ),
            const SizedBox(height: 24),

            // Account section
            _buildSection(
              context,
              title: l.account,
              icon: Icons.person,
              children: [
                _buildProfileCard(context),
                const Divider(height: 1),
                _buildSettingTile(
                  context,
                  icon: Icons.lock_outline,
                  title: 'Đổi mật khẩu',
                  subtitle: 'Cập nhật mật khẩu đăng nhập của bạn',
                  onTap: () => _showChangePasswordDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // App settings
            _buildSection(
              context,
              title: l.application,
              icon: Icons.settings,
              children: [
                _buildSettingTile(
                  context,
                  icon: Icons.dark_mode,
                  title: l.darkMode,
                  subtitle: Consumer<ThemeProvider>(
                    builder: (context, tp, _) => Text(
                      tr(tp.isDarkMode ? l.turnedOn : l.turnedOff),
                      style: TextStyle(color: Colors.grey[400], fontSize: 14),
                    ),
                  ),
                  trailing: Consumer<ThemeProvider>(
                    builder: (context, themeProvider, child) {
                      return Switch(
                        value: themeProvider.isDarkMode,
                        onChanged: (value) {
                          themeProvider.toggleTheme();
                        },
                      );
                    },
                  ),
                ),
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    return _buildSettingTile(
                      context,
                      icon: Icons.language,
                      title: l.language,
                      subtitle: Text(
                        tr(themeProvider.languageLabel),
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                      onTap: () => _showLanguageDialog(context),
                    );
                  },
                ),
                if (Responsive.isMobile(context))
                  _buildSettingTile(
                    context,
                    icon: Icons.tune_rounded,
                    title: 'Thanh công cụ dưới',
                    subtitle:
                        '5 vị trí cố định — đổi thứ tự và chức năng hiển thị',
                    onTap: () => MobileBottomNavConfigSheet.show(context),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // Server settings
            _buildSection(
              context,
              title: l.connection,
              icon: Icons.cloud,
              children: [
                _buildSettingTile(
                  context,
                  icon: Icons.dns,
                  title: l.serverConfig,
                  subtitle: _serverUrl,
                  onTap: () => _showServerDialog(context),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.sync,
                  title: l.autoSync,
                  subtitle: l.every5Minutes,
                  onTap: () => _showSyncDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Data management
            if (canManageData) ...[
              _buildSection(
                context,
                title: l.dataManagement,
                icon: Icons.storage,
                children: [
                  _buildSettingTile(
                    context,
                    icon: Icons.dataset,
                    title: l.seedSampleData,
                    subtitle: l.seedSampleDataDesc,
                    trailing: _isSeedingSampleData
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _isSeedingSampleData
                        ? null
                        : () => _showSeedSampleDataDialog(context),
                  ),
                  _buildSettingTile(
                    context,
                    icon: Icons.delete_sweep,
                    title: l.deleteSampleData,
                    subtitle: l.deleteSampleDataDesc,
                    trailing: _isDeletingSampleData
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child:
                                CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _isDeletingSampleData
                        ? null
                        : () => _showDeleteSampleDataDialog(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // About
            _buildSection(
              context,
              title: l.information,
              icon: Icons.info,
              children: [
                _buildSettingTile(
                  context,
                  icon: Icons.app_shortcut,
                  title: l.version,
                  subtitle: '2.0.0',
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.description,
                  title: l.termsOfUse,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AppInfoScreen(type: 'terms'),
                  )),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.privacy_tip,
                  title: l.privacyPolicy,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AppInfoScreen(type: 'privacy'),
                  )),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.help,
                  title: l.help,
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AppInfoScreen(type: 'help'),
                  )),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.bug_report_outlined,
                  title: 'Báo lỗi & Góp ý',
                  subtitle: 'Gửi phản hồi cho nhà phát triển',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AppInfoScreen(type: 'bugreport'),
                  )),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Logout
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showLogoutDialog(context),
                icon: const Icon(Icons.logout, color: Colors.red),
                label: Text(
                  tr(l.logout),
                  style: const TextStyle(color: Colors.red),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: Theme.of(context).primaryColor),
            const SizedBox(width: 8),
            Text(
              tr(title),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildProfileCard(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final user = authProvider.user;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor:
                Theme.of(context).primaryColor.withValues(alpha: 0.2),
            child: Text(
              tr((user?.fullName ?? 'U')[0].toUpperCase()),
              style: TextStyle(
                color: Theme.of(context).primaryColor,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(user?.fullName ?? 'User'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(user?.email ?? ''),
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color:
                        Theme.of(context).primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    tr(user?.role ?? 'Employee'),
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showEditProfileDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    dynamic subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    Widget? subtitleWidget;
    if (subtitle is Widget) {
      subtitleWidget = subtitle;
    } else if (subtitle is String) {
      subtitleWidget = Text(tr(subtitle));
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: Theme.of(context).primaryColor,
          size: 20,
        ),
      ),
      title: Text(tr(title)),
      subtitle: subtitleWidget,
      trailing:
          trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final currentLang = themeProvider.locale.languageCode;
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        title: Text(tr(l.selectLanguage)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Text(tr('🇻🇳')),
              title: Text(tr('Tiếng Việt')),
              trailing: currentLang == 'vi'
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                themeProvider.setLocale(const Locale('vi'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Text(tr('🇺🇸')),
              title: Text(tr('English')),
              trailing: currentLang == 'en'
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                themeProvider.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showServerDialog(BuildContext context) {
    final controller = TextEditingController(text: tr(_serverUrl));
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        title: Text(tr(l.serverConfig)),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: tr('URL Server API'),
              hintText: tr('http://192.168.1.2:7070'),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(l.cancel)),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _serverUrl = controller.text);
              Navigator.pop(context);
              appNotification.showInfo(
                title: l.serverConfig,
                message: tr('URL Server được tùy chỉnh qua biến môi trường API_BASE_URL khi build.\nURL hiện tại: ${ApiService.baseUrl}'),
              );
            },
            child: Text(tr(l.save)),
          ),
        ],
      ),
    );
  }

  void _showSyncDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr(l.autoSync)),
        content: Text(tr('Hệ thống tự động đồng bộ dữ liệu chấm công mỗi 5 phút.\nDữ liệu sẽ được cập nhật khi có kết nối mạng.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Đóng')),
          ),
        ],
      ),
    );
  }

  void _showEditProfileDialog(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(tr('Thông tin tài khoản')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Họ tên', user?.fullName ?? 'N/A'),
            _buildInfoRow('Email', user?.email ?? 'N/A'),
            _buildInfoRow('Vai trò', user?.role ?? 'N/A'),
            const SizedBox(height: 12),
            Text(tr('Bạn có thể đổi mật khẩu trong mục Đổi mật khẩu bên dưới.'),
              style: TextStyle(color: Color(0xFF71717A), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(l.cancel)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showChangePasswordDialog(context);
            },
            child: Text(tr('Đổi mật khẩu')),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    var showCurrent = false;
    var showNew = false;
    var showConfirm = false;
    var isSaving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> submit() async {
            final current = currentController.text.trim();
            final newPassword = newController.text;
            final confirm = confirmController.text;

            if (current.isEmpty) {
              appNotification.showWarning(
                title: 'Thiếu thông tin',
                message: tr('Vui lòng nhập mật khẩu hiện tại'),
              );
              return;
            }
            if (newPassword.length < 6) {
              appNotification.showWarning(
                title: 'Mật khẩu quá ngắn',
                message: tr('Mật khẩu mới phải có ít nhất 6 ký tự'),
              );
              return;
            }
            if (newPassword != confirm) {
              appNotification.showWarning(
                title: 'Không khớp',
                message: tr('Mật khẩu xác nhận không khớp'),
              );
              return;
            }

            setDialogState(() => isSaving = true);
            try {
              final response = await ApiService().updateOwnPassword(
                currentPassword: current,
                newPassword: newPassword,
              );
              if (!ctx.mounted) return;
              if (response['isSuccess'] == true) {
                Navigator.pop(ctx);
                appNotification.showSuccess(
                  title: 'Thành công',
                  message: tr('Đã đổi mật khẩu thành công'),
                );
              } else {
                appNotification.showError(
                  title: 'Lỗi',
                  message:
                      response['message']?.toString() ?? 'Không thể đổi mật khẩu',
                );
              }
            } catch (e) {
              if (ctx.mounted) {
                appNotification.showError(
                  title: 'Lỗi',
                  message: tr('Không thể đổi mật khẩu: $e'),
                );
              }
            } finally {
              if (ctx.mounted) {
                setDialogState(() => isSaving = false);
              }
            }
          }

          InputDecoration fieldDecoration({
            required String hint,
            required bool visible,
            required VoidCallback toggle,
          }) {
            return InputDecoration(
              hintText: tr(hint),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixIcon: IconButton(
                icon: Icon(
                  visible ? Icons.visibility_off : Icons.visibility,
                  size: 20,
                ),
                onPressed: toggle,
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            );
          }

          return ScrollableAlertDialog(
            title: Text(tr('Đổi mật khẩu')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Nhập mật khẩu hiện tại và mật khẩu mới để cập nhật tài khoản của bạn.'),
                  style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
                ),
                const SizedBox(height: 16),
                Text(tr('Mật khẩu hiện tại'),
                    style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                const SizedBox(height: 6),
                TextField(
                  controller: currentController,
                  obscureText: !showCurrent,
                  enabled: !isSaving,
                  decoration: fieldDecoration(
                    hint: 'Nhập mật khẩu hiện tại',
                    visible: showCurrent,
                    toggle: () =>
                        setDialogState(() => showCurrent = !showCurrent),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr('Mật khẩu mới'),
                    style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                const SizedBox(height: 6),
                TextField(
                  controller: newController,
                  obscureText: !showNew,
                  enabled: !isSaving,
                  decoration: fieldDecoration(
                    hint: 'Tối thiểu 6 ký tự',
                    visible: showNew,
                    toggle: () => setDialogState(() => showNew = !showNew),
                  ),
                ),
                const SizedBox(height: 12),
                Text(tr('Xác nhận mật khẩu mới'),
                    style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
                const SizedBox(height: 6),
                TextField(
                  controller: confirmController,
                  obscureText: !showConfirm,
                  enabled: !isSaving,
                  decoration: fieldDecoration(
                    hint: 'Nhập lại mật khẩu mới',
                    visible: showConfirm,
                    toggle: () =>
                        setDialogState(() => showConfirm = !showConfirm),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(ctx),
                child: Text(tr(l.cancel)),
              ),
              FilledButton.icon(
                onPressed: isSaving ? null : submit,
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset, size: 18),
                label: Text(tr(isSaving ? 'Đang lưu...' : 'Lưu')),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      currentController.dispose();
      newController.dispose();
      confirmController.dispose();
    });
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 80,
              child: Text(tr(label),
                  style:
                      const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
          Expanded(
              child: Text(tr(value),
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }

  void _showSeedSampleDataDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        title: Text(tr(l.seedSampleData)),
        content: Text(tr(l.seedSampleDataConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(l.cancel)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _seedSampleData();
            },
            child: Text(tr(l.seedSampleData)),
          ),
        ],
      ),
    );
  }

  Future<void> _seedSampleData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final storeId = authProvider.user?.storeId ?? '';

    String storeIdentifier = storeId;
    if (storeIdentifier.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      storeIdentifier = prefs.getString('saved_store_code') ?? '';
    }

    if (storeIdentifier.isEmpty) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: tr('Không tìm thấy mã cửa hàng. Vui lòng đăng nhập lại.'),
        );
      }
      return;
    }

    setState(() => _isSeedingSampleData = true);
    try {
      final result = await ApiService().seedSampleData(storeIdentifier);
      if (!mounted) return;
      if (result['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: tr('Đã cài dữ liệu mẫu thành công!'),
        );
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: result['message']?.toString() ?? 'Không thể cài dữ liệu mẫu',
        );
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: tr('Không thể cài dữ liệu mẫu: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _isSeedingSampleData = false);
    }
  }

  void _showDeleteSampleDataDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        title: Text(tr(l.deleteSampleData)),
        content: Text(tr(l.deleteSampleDataConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(l.cancel)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSampleData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr(l.delete)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSampleData() async {
    // Try storeId from auth provider first, fallback to saved_store_code
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final storeId = authProvider.user?.storeId ?? '';

    String storeIdentifier = storeId;
    if (storeIdentifier.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      storeIdentifier = prefs.getString('saved_store_code') ?? '';
    }

    if (storeIdentifier.isEmpty) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: tr('Không tìm thấy mã cửa hàng. Vui lòng đăng nhập lại.'),
        );
      }
      return;
    }

    setState(() => _isDeletingSampleData = true);
    try {
      final result = await ApiService().deleteSampleData(storeIdentifier);
      if (!mounted) return;
      if (result['isSuccess'] == true) {
        final data = result['data'];
        final msg = data is Map
            ? (data['message'] ?? 'Đã xóa dữ liệu mẫu')
            : 'Đã xóa dữ liệu mẫu';
        appNotification.showSuccess(
          title: 'Thành công',
          message: msg.toString(),
        );
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: result['message']?.toString() ?? 'Không thể xóa dữ liệu mẫu',
        );
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi',
          message: tr('Không thể xóa dữ liệu mẫu: $e'),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingSampleData = false);
    }
  }

  void _showLogoutDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => ScrollableAlertDialog(
        title: Text(tr(l.logout)),
        content: Text(tr(l.logoutConfirm)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr(l.cancel)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr(l.logout)),
          ),
        ],
      ),
    );
  }
}
