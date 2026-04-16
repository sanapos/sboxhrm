import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';

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
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.settingsTitle,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l.settingsSubtitle,
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
                      tp.isDarkMode ? l.turnedOn : l.turnedOff,
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
                        themeProvider.languageLabel,
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                      onTap: () => _showLanguageDialog(context),
                    );
                  },
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
                          child: CircularProgressIndicator(strokeWidth: 2),
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
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _isDeletingSampleData
                      ? null
                      : () => _showDeleteSampleDataDialog(context),
                ),
              ],
            ),
            const SizedBox(height: 24),

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
                  onTap: () => _showInfoDialog(context, l.termsOfUse, 'Ứng dụng quản lý chấm công ZKTeco ADMS.\nBản quyền thuộc về công ty.\nNghiêm cấm sao chép, phân phối trái phép.'),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.privacy_tip,
                  title: l.privacyPolicy,
                  onTap: () => _showInfoDialog(context, l.privacyPolicy, 'Chúng tôi cam kết bảo mật thông tin cá nhân của bạn.\nDữ liệu chấm công chỉ được sử dụng cho mục đích quản lý nội bộ.\nKhông chia sẻ dữ liệu với bên thứ ba.'),
                ),
                _buildSettingTile(
                  context,
                  icon: Icons.help,
                  title: l.help,
                  onTap: () => _showInfoDialog(context, l.help, 'Liên hệ hỗ trợ:\n• Email: support@sbox.vn\n• Hotline: 1900-xxxx\n• Giờ làm việc: 8:00 - 17:30 (T2-T6)'),
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
                  l.logout,
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
              title,
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
            backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.2),
            child: Text(
              (user?.fullName ?? 'U')[0].toUpperCase(),
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
                  user?.fullName ?? 'User',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style: TextStyle(color: Colors.grey[400]),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    user?.role ?? 'Employee',
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
      subtitleWidget = Text(subtitle);
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
      title: Text(title),
      subtitle: subtitleWidget,
      trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right) : null),
      onTap: onTap,
    );
  }

  void _showLanguageDialog(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final currentLang = themeProvider.locale.languageCode;
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.selectLanguage),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Text('🇻🇳'),
              title: const Text('Tiếng Việt'),
              trailing: currentLang == 'vi'
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () {
                themeProvider.setLocale(const Locale('vi'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Text('🇺🇸'),
              title: const Text('English'),
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
    final controller = TextEditingController(text: _serverUrl);
    final l = AppLocalizations.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.serverConfig),
        content: SingleChildScrollView(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'URL Server API',
              hintText: 'http://192.168.1.2:7070',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _serverUrl = controller.text);
              Navigator.pop(context);
              appNotification.showInfo(
                title: l.serverConfig,
                message: 'URL Server được tùy chỉnh qua biến môi trường API_BASE_URL khi build.\nURL hiện tại: ${ApiService.baseUrl}',
              );
            },
            child: Text(l.save),
          ),
        ],
      ),
    );
  }

  void _showSyncDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.autoSync),
        content: const Text('Hệ thống tự động đồng bộ dữ liệu chấm công mỗi 5 phút.\nDữ liệu sẽ được cập nhật khi có kết nối mạng.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context, String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Đóng'),
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
      builder: (ctx) => AlertDialog(
        title: const Text('Thông tin tài khoản'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Họ tên', user?.fullName ?? 'N/A'),
            _buildInfoRow('Email', user?.email ?? 'N/A'),
            _buildInfoRow('Vai trò', user?.role ?? 'N/A'),
            const SizedBox(height: 12),
            const Text(
              'Liên hệ quản trị viên để thay đổi thông tin tài khoản.',
              style: TextStyle(color: Color(0xFF71717A), fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l.cancel),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }

  void _showSeedSampleDataDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.seedSampleData),
        content: Text(l.seedSampleDataConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _seedSampleData();
            },
            child: Text(l.seedSampleData),
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
          message: 'Không tìm thấy mã cửa hàng. Vui lòng đăng nhập lại.',
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
          message: 'Đã cài dữ liệu mẫu thành công!',
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
          message: 'Không thể cài dữ liệu mẫu: $e',
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
      builder: (context) => AlertDialog(
        title: Text(l.deleteSampleData),
        content: Text(l.deleteSampleDataConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteSampleData();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l.delete),
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
          message: 'Không tìm thấy mã cửa hàng. Vui lòng đăng nhập lại.',
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
        final msg = data is Map ? (data['message'] ?? 'Đã xóa dữ liệu mẫu') : 'Đã xóa dữ liệu mẫu';
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
          message: 'Không thể xóa dữ liệu mẫu: $e',
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
      builder: (context) => AlertDialog(
        title: Text(l.logout),
        content: Text(l.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Provider.of<AuthProvider>(context, listen: false).logout();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l.logout),
          ),
        ],
      ),
    );
  }
}
