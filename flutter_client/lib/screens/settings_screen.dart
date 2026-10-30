import 'package:flutter/material.dart';
import '../widgets/delete_account_dialog.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../utils/responsive_helper.dart';
import '../widgets/mobile_bottom_nav_config_sheet.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_locale.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../config/sbox_app_variant.dart';
import '../services/api_service.dart';
import '../services/biometric_login_service.dart';
import '../services/zalo_bot_api.dart';
import '../widgets/zalo_link_sheet.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/server_url_dialog.dart';
import 'app_info_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../theme/sbox_tokens.dart';
import '../utils/permission_role_options.dart';
/// «Cài đặt» — trang cá nhân dùng chung HRM và POS: hồ sơ, mật khẩu, giao diện, ngôn ngữ,
/// thanh công cụ dưới, phiên bản, trợ giúp, đăng xuất, xóa tài khoản.
/// Cấu hình cửa hàng nằm ở «Thiết lập SBOX» (dữ liệu mẫu → Tham số hệ thống).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.showAppBar = false});

  /// Mở bằng Navigator.push (POS Thêm, menu màn bán) — tự vẽ thanh tiêu đề + nút quay lại.
  final bool showAppBar;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _serverUrl = ApiService.baseUrl;
  String _appVersionLabel = '…';

  /// Đăng nhập bằng Face ID / vân tay: chỉ hiện khi máy có cảm biến đã cài.
  bool _bioAvailable = false;
  bool _bioEnabled = false;
  bool _bioBusy = false;
  String _bioLabel = '';

  /// Zalo bot của cửa hàng (/api/zalo-bot/me) — dòng «Liên kết Zalo» chỉ hiện khi cửa hàng đã bật bot.
  Map<String, dynamic>? _zalo;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _loadAppVersion();
    _loadBiometric();
    _loadZalo();
  }

  Future<void> _loadZalo() async {
    if (SboxAppVariant.standalonePos) return;
    final r = await ZaloBotApi().getMyLink();
    if (!mounted || r['isSuccess'] != true || r['data'] is! Map) return;
    setState(() => _zalo = Map<String, dynamic>.from(r['data'] as Map));
  }

  Future<void> _openZaloLink() async {
    final z = _zalo;
    if (z == null) return;
    final next = await ZaloLinkSheet.show(context, z);
    if (!mounted) return;
    if (next != null) setState(() => _zalo = next);
    await _loadZalo();
  }

  Future<void> _loadBiometric() async {
    final bio = BiometricLoginService.instance;
    if (!await bio.isAvailable()) return;
    final label = await bio.loginLabel();
    final me = await bio.lastLoginIdentity();
    final acc = await bio.savedAccount();
    if (!mounted) return;
    setState(() {
      _bioAvailable = true;
      _bioLabel = label;
      _bioEnabled =
          acc != null && acc.sameAs(ApiService.baseUrl, me.storeCode, me.email);
    });
  }

  Future<void> _toggleBiometric(bool on) async {
    final bio = BiometricLoginService.instance;
    if (!on) {
      await bio.disable();
      if (mounted) setState(() => _bioEnabled = false);
      return;
    }
    final me = await bio.lastLoginIdentity();
    if (!mounted || me.email.isEmpty) return;
    final password = await _askPasswordForBiometric();
    if (password == null || !mounted) return;
    setState(() => _bioBusy = true);
    try {
      // Kiểm tra mật khẩu bằng API đăng nhập (không đổi phiên đang dùng).
      final api = ApiService();
      final res = me.storeCode.isEmpty
          ? await api.adminLogin(me.email, password)
          : await api.login(me.storeCode, me.email, password);
      if (res['isSuccess'] != true) {
        appNotification.showError(
          title: _bioLabel,
          message: res['message']?.toString() ?? tr('Mật khẩu không đúng'),
        );
        return;
      }
      final ok = await bio.enable(
          storeCode: me.storeCode, email: me.email, password: password);
      if (mounted) setState(() => _bioEnabled = ok);
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
  }

  Future<String?> _askPasswordForBiometric() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_bioLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Nhập mật khẩu hiện tại để bật đăng nhập nhanh trên điện thoại này.')),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(labelText: tr('Mật khẩu')),
              onSubmitted: (v) => Navigator.pop(ctx, v.isEmpty ? null : v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Hủy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, controller.text.isEmpty ? null : controller.text),
            child: Text(tr('Tiếp tục')),
          ),
        ],
      ),
    );
  }

  Future<void> _loadPreferences() async {
    await SharedPreferences.getInstance();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _appVersionLabel = '${info.version} (${info.buildNumber})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _appVersionLabel = '—');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: widget.showAppBar ? AppBar(title: Text(tr('Cài đặt'))) : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Điện thoại: thanh trên đã ghi «Cài đặt» — bỏ tiêu đề to lặp lại.
            if (!widget.showAppBar && !Responsive.isMobile(context)) Text(
              tr('Cài đặt'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('Tài khoản của bạn và cách ứng dụng hiển thị trên máy này. Cấu hình cửa hàng nằm ở Thiết lập SBOX.'),
              style: TextStyle(color: SboxColors.slate400),
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
                if (_zalo != null && (_zalo!['available'] == true || _zalo!['linked'] == true))
                  _buildSettingTile(
                    context,
                    icon: Icons.forum_outlined,
                    title: 'Liên kết Zalo',
                    subtitle: _zalo!['linked'] == true
                        ? 'Đang nhận thông báo qua Zalo'
                        : 'Nhận thông báo lương, chấm công qua Zalo',
                    onTap: _openZaloLink,
                  ),
                if (_bioAvailable &&
                    !Provider.of<AuthProvider>(context).isImpersonating)
                  _buildSettingTile(
                    context,
                    icon: Theme.of(context).platform == TargetPlatform.iOS
                        ? Icons.face_outlined
                        : Icons.fingerprint,
                    title: _bioLabel,
                    subtitle: _bioEnabled
                        ? 'Đang bật trên điện thoại này'
                        : 'Mở app không cần nhập mật khẩu',
                    trailing: _bioBusy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Switch(
                            value: _bioEnabled,
                            onChanged: _toggleBiometric,
                          ),
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
                if (ThemeProvider.darkModeAvailable)
                _buildSettingTile(
                  context,
                  icon: Icons.dark_mode,
                  title: l.darkMode,
                  subtitle: Consumer<ThemeProvider>(
                    builder: (context, tp, _) => Text(
                      tr(tp.isDarkMode ? l.turnedOn : l.turnedOff),
                      style: TextStyle(color: SboxColors.slate400, fontSize: 14),
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
                        style: TextStyle(color: SboxColors.slate400, fontSize: 14),
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
                // Máy chủ kết nối là thiết lập của máy này; app POS phát hành cố định máy chủ.
                if (!SboxAppVariant.standalonePos)
                  _buildSettingTile(
                    context,
                    icon: Icons.dns,
                    title: l.serverConfig,
                    subtitle: _serverUrl,
                    onTap: () => _showServerDialog(context),
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
                  subtitle: _appVersionLabel,
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
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                onPressed: () => showDeleteAccountDialog(context),
                icon: const Icon(Icons.person_remove_outlined, size: 18, color: Colors.red),
                label: Text(tr('Xóa tài khoản'), style: const TextStyle(color: Colors.red)),
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
                  style: TextStyle(color: SboxColors.slate400),
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    // Tên vai trò tiếng Việt («Admin» → «Quản trị viên») như màn Phân quyền.
                    tr(PermissionRoleOptions.displayNameOf(user?.role ?? 'Employee')),
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
          borderRadius: BorderRadius.circular(10),
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
            for (final e in AppLocale.languages.entries)
              ListTile(
                leading: Text(_languageFlags[e.key] ?? ''),
                // Native names on purpose: a user who picked the wrong language
                // must still recognise their own.
                title: Text(e.value),
                trailing: currentLang == e.key
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  themeProvider.setLocale(Locale(e.key));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  static const Map<String, String> _languageFlags = {
    'vi': '🇻🇳',
    'en': '🇺🇸',
    'ko': '🇰🇷',
    'ja': '🇯🇵',
    'zh': '🇨🇳',
  };

  Future<void> _showServerDialog(BuildContext context) async {
    await showServerUrlDialog(context);
    if (!mounted) return;
    setState(() => _serverUrl = ApiService.baseUrl);
  }

  void _showEditProfileDialog(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final user = authProvider.user;
    final l = AppLocalizations.of(context);

    final parts = (user?.fullName ?? '').trim().split(RegExp(r'\s+'));
    final lastNameCtl = TextEditingController(
        text: parts.isNotEmpty ? parts.first : '');
    final firstNameCtl = TextEditingController(
        text: parts.length > 1 ? parts.sublist(1).join(' ') : '');
    final phoneCtl = TextEditingController();
    var loadingProfile = true;
    var saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          if (loadingProfile) {
            loadingProfile = false;
            ApiService().getOwnProfile().then((res) {
              if (!ctx.mounted) return;
              if (res['isSuccess'] == true && res['data'] is Map) {
                final d = Map<String, dynamic>.from(res['data'] as Map);
                lastNameCtl.text =
                    (d['lastName'] ?? d['LastName'] ?? lastNameCtl.text)
                        .toString();
                firstNameCtl.text =
                    (d['firstName'] ?? d['FirstName'] ?? firstNameCtl.text)
                        .toString();
                phoneCtl.text =
                    (d['phoneNumber'] ?? d['PhoneNumber'] ?? '').toString();
                setDlg(() {});
              }
            });
          }
          return ScrollableAlertDialog(
            title: Text(tr('Thông tin tài khoản')),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: lastNameCtl,
                    decoration: InputDecoration(
                      labelText: tr('Họ'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: firstNameCtl,
                    decoration: InputDecoration(
                      labelText: tr('Tên'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    textCapitalization: TextCapitalization.words,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: tr('Số điện thoại'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('Email', user?.email ?? 'N/A'),
                  _buildInfoRow('Vai trò', user?.role == null ? '—' : PermissionRoleOptions.displayNameOf(user!.role)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr(l.cancel)),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _showChangePasswordDialog(context);
                      },
                child: Text(tr('Đổi mật khẩu')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final first = firstNameCtl.text.trim();
                        final last = lastNameCtl.text.trim();
                        if (first.isEmpty && last.isEmpty) {
                          appNotification.showWarning(
                            title: 'Thiếu thông tin',
                            message: tr('Nhập họ hoặc tên'),
                          );
                          return;
                        }
                        setDlg(() => saving = true);
                        final res = await ApiService().updateOwnProfile(
                          firstName: first,
                          lastName: last,
                          phoneNumber: phoneCtl.text.trim(),
                        );
                        if (!ctx.mounted) return;
                        setDlg(() => saving = false);
                        if (res['isSuccess'] == true) {
                          final full =
                              '$last $first'.trim();
                          authProvider.applyLocalProfile(fullName: full);
                          if (ctx.mounted) Navigator.pop(ctx);
                          appNotification.showSuccess(
                            title: 'Đã lưu',
                            message: tr('Đã cập nhật thông tin tài khoản'),
                          );
                        } else {
                          appNotification.showError(
                            title: 'Lỗi',
                            message: (res['message'] ?? 'Không lưu được')
                                .toString(),
                          );
                        }
                      },
                child: saving
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
    ).whenComplete(() {
      lastNameCtl.dispose();
      firstNameCtl.dispose();
      phoneCtl.dispose();
    });
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
            if (newPassword == current) {
              appNotification.showWarning(
                title: 'Không hợp lệ',
                message: tr('Mật khẩu mới phải khác mật khẩu hiện tại'),
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
                final bio = BiometricLoginService.instance;
                final me = await bio.lastLoginIdentity();
                await bio.updatePasswordIfEnabled(
                    storeCode: me.storeCode,
                    email: me.email,
                    password: newPassword);
                if (!ctx.mounted) return;
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            );
          }

          return ScrollableAlertDialog(
            title: Text(tr('Đổi mật khẩu')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Nhập mật khẩu hiện tại và mật khẩu mới để cập nhật tài khoản của bạn.'),
                  style: TextStyle(color: SboxColors.slate500, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Text(tr('Mật khẩu hiện tại'),
                    style: TextStyle(fontSize: 13, color: SboxColors.slate500)),
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
                    style: TextStyle(fontSize: 13, color: SboxColors.slate500)),
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
                    style: TextStyle(fontSize: 13, color: SboxColors.slate500)),
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
                      const TextStyle(color: SboxColors.slate500, fontSize: 13))),
          Expanded(
              child: Text(tr(value),
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
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
