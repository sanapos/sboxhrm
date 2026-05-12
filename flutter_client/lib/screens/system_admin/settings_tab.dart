import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../providers/auth_provider.dart';
import '../../utils/responsive_helper.dart';
import 'system_admin_helpers.dart';

class SettingsTab extends StatefulWidget {
  const SettingsTab({super.key});

  @override
  State<SettingsTab> createState() => SettingsTabState();
}

class SettingsTabState extends State<SettingsTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _settings = [];
  bool _isLoading = false;

  final _searchCtrl = TextEditingController();
  String? _groupFilter;
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get settings => _settings;

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getAllAppSettings();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() =>
            _settings = List<Map<String, dynamic>>.from(res['data'] ?? []));
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      debugPrint('SettingsTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filteredSettings {
    final query = _searchCtrl.text.toLowerCase();
    return _settings.where((s) {
      final key = (s['key'] ?? '').toString().toLowerCase();
      final value = (s['value'] ?? '').toString().toLowerCase();
      final desc = (s['description'] ?? '').toString().toLowerCase();
      final group = (s['group'] ?? '').toString().toLowerCase();
      final matchSearch = query.isEmpty ||
          key.contains(query) ||
          value.contains(query) ||
          desc.contains(query);

      final matchGroup =
          _groupFilter == null || group == _groupFilter!.toLowerCase();

      return matchSearch && matchGroup;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final role = (Provider.of<AuthProvider>(context).currentUser?.role ?? '').toLowerCase();
    final isSuperAdmin = role == 'superadmin';

    final filtered = _filteredSettings;
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final setting in filtered) {
      final group = setting['group']?.toString().trim().isNotEmpty == true
          ? setting['group'].toString()
          : 'General';
      grouped.putIfAbsent(group, () => []).add(setting);
    }
    final groups = grouped.keys.toList()..sort();
    for (final group in groups) {
      grouped[group]!.sort((a, b) {
        final left = (a['displayOrder'] as num?)?.toInt() ?? 0;
        final right = (b['displayOrder'] as num?)?.toInt() ?? 0;
        return left.compareTo(right);
      });
    }

    // All group names from unfiltered data
    final allGroups = _settings
        .map((s) =>
            s['group']?.toString().trim().isNotEmpty == true
                ? s['group'].toString()
                : 'General')
        .toSet()
        .toList()
      ..sort();

    return Column(
      children: [
        _buildToolbar(allGroups),
        if (isSuperAdmin) _buildGoogleDriveCard(),
        Expanded(
          child: filtered.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.settings, 'Chưa có cấu hình ứng dụng')
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: groups.length,
                  itemBuilder: (ctx, i) =>
                      _buildSettingsGroup(groups[i], grouped[groups[i]]!),
                ),
        ),
      ],
    );
  }

  Widget _buildGoogleDriveCard() {
    final gdriveEnabled = _settings.firstWhere(
        (s) => s['key'] == 'google_drive_enabled',
        orElse: () => {})['value']?.toString().toLowerCase() == 'true';
    final hasFolderId = _settings.any((s) =>
        s['key'] == 'google_drive_folder_id' &&
        (s['value']?.toString().trim().isNotEmpty == true));
    final hasCredentials = _settings.any((s) =>
        s['key'] == 'google_drive_credentials_json' &&
        (s['value']?.toString().trim().isNotEmpty == true));

    final isConfigured = hasFolderId && hasCredentials;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gdriveEnabled
              ? [const Color(0xFF4285F4), const Color(0xFF34A853)]
              : [Colors.grey.shade400, Colors.grey.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: (gdriveEnabled ? const Color(0xFF4285F4) : Colors.grey)
                .withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showGoogleDriveDialog(),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.cloud_upload_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Google Drive Storage',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15)),
                      const SizedBox(height: 4),
                      Text(
                        gdriveEnabled
                            ? (isConfigured
                                ? 'Đang hoạt động • Ảnh sẽ lưu lên Google Drive'
                                : 'Bật nhưng chưa cấu hình đủ thông tin')
                            : 'Chưa bật • Ảnh đang lưu local server',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                      gdriveEnabled ? Icons.check_circle : Icons.settings,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      gdriveEnabled ? 'ON' : 'Cấu hình',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showGoogleDriveDialog() {
    final enabledSetting = _settings.firstWhere(
        (s) => s['key'] == 'google_drive_enabled',
        orElse: () => {'value': 'false'});
    final folderIdSetting = _settings.firstWhere(
        (s) => s['key'] == 'google_drive_folder_id',
        orElse: () => {'value': ''});
    final credentialsSetting = _settings.firstWhere(
        (s) => s['key'] == 'google_drive_credentials_json',
        orElse: () => {'value': ''});

    bool isEnabled =
        enabledSetting['value']?.toString().toLowerCase() == 'true';
    final folderIdCtrl =
        TextEditingController(text: folderIdSetting['value']?.toString() ?? '');
    final credentialsCtrl = TextEditingController(
        text: credentialsSetting['value']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.cloud, color: Color(0xFF4285F4), size: 20),
          ),
          const SizedBox(width: 10),
          const Text('Cấu hình Google Drive'),
        ]),
        content: SizedBox(
          width: 520,
          child: StatefulBuilder(
            builder: (ctx, setSt) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Enable toggle
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isEnabled
                          ? const Color(0xFF34A853).withValues(alpha: 0.08)
                          : Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: isEnabled
                              ? const Color(0xFF34A853).withValues(alpha: 0.3)
                              : Colors.grey.shade300),
                    ),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bật Google Drive Storage',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        isEnabled
                            ? 'Tất cả ảnh upload sẽ lưu lên Google Drive'
                            : 'Đang lưu ảnh trên local server',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade600),
                      ),
                      value: isEnabled,
                      onChanged: (v) => setSt(() => isEnabled = v),
                      activeThumbColor: const Color(0xFF34A853),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Folder ID
                  const Text('Google Drive Folder ID',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    'Lấy từ URL: drive.google.com/drive/folders/{ID_Ở_ĐÂY}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: folderIdCtrl,
                    decoration: InputDecoration(
                      hintText: 'vd: 1AbC2dEf3GhI4jKl5mNo6pQr...',
                      prefixIcon:
                          const Icon(Icons.folder_outlined, size: 20),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste, size: 18),
                        tooltip: 'Paste từ clipboard',
                        onPressed: () async {
                          final data = await Clipboard.getData('text/plain');
                          if (data?.text != null) {
                            // Extract folder ID from URL if pasted
                            var text = data!.text!.trim();
                            final match = RegExp(
                                    r'folders/([a-zA-Z0-9_-]+)')
                                .firstMatch(text);
                            if (match != null) text = match.group(1)!;
                            folderIdCtrl.text = text;
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Credentials JSON
                  const Text('Service Account JSON',
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  Text(
                    'Nội dung file JSON của Google Service Account',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: credentialsCtrl,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      hintText: '{"type": "service_account", ...}',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10)),
                      suffixIcon: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.paste, size: 18),
                            tooltip: 'Paste từ clipboard',
                            onPressed: () async {
                              final data =
                                  await Clipboard.getData('text/plain');
                              if (data?.text != null) {
                                credentialsCtrl.text = data!.text!.trim();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Instructions
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF4285F4).withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              const Color(0xFF4285F4).withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(children: [
                          Icon(Icons.info_outline,
                              size: 16, color: Color(0xFF4285F4)),
                          SizedBox(width: 6),
                          Text('Hướng dẫn cài đặt',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: Color(0xFF4285F4))),
                        ]),
                        const SizedBox(height: 8),
                        _instrStep('1', 'Vào console.cloud.google.com → Tạo project'),
                        _instrStep('2', 'Bật Google Drive API'),
                        _instrStep('3', 'Tạo Service Account → Download JSON key'),
                        _instrStep('4', 'Tạo folder trên Google Drive'),
                        _instrStep('5', 'Share folder cho email Service Account (Editor)'),
                        _instrStep('6', 'Copy Folder ID và paste JSON vào đây'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton.icon(
            onPressed: () => _saveGoogleDriveSettings(
                ctx, isEnabled, folderIdCtrl.text, credentialsCtrl.text),
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Lưu cấu hình'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF4285F4),
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _instrStep(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF4285F4).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(num,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4285F4))),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
          ),
        ],
      ),
    );
  }

  Future<void> _saveGoogleDriveSettings(
      BuildContext ctx, bool enabled, String folderId, String credentials) async {
    // Validate
    if (enabled && folderId.trim().isEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('Vui lòng nhập Folder ID'),
            backgroundColor: Colors.orange));
      }
      return;
    }
    if (enabled && credentials.trim().isEmpty) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
            content: Text('Vui lòng nhập Service Account JSON'),
            backgroundColor: Colors.orange));
      }
      return;
    }

    // Validate JSON format by attempting to parse
    if (enabled && credentials.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(credentials.trim());
        if (parsed is! Map) throw const FormatException('Must be a JSON object');
      } catch (_) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
              content: Text('Service Account JSON không hợp lệ'),
              backgroundColor: Colors.red));
        }
        return;
      }
    }

    Navigator.pop(ctx);

    // Save all 3 settings
    final results = await Future.wait([
      _apiService.upsertAppSetting(
        key: 'google_drive_enabled',
        value: enabled.toString(),
        description: 'Bật/tắt lưu trữ ảnh trên Google Drive',
        group: 'Storage',
        dataType: 'text',
        displayOrder: 1,
        isPublic: false,
      ),
      _apiService.upsertAppSetting(
        key: 'google_drive_folder_id',
        value: folderId.trim(),
        description: 'Google Drive Folder ID để lưu trữ ảnh',
        group: 'Storage',
        dataType: 'text',
        displayOrder: 2,
        isPublic: false,
      ),
      _apiService.upsertAppSetting(
        key: 'google_drive_credentials_json',
        value: credentials.trim(),
        description: 'Google Service Account JSON credentials',
        group: 'Storage',
        dataType: 'textarea',
        displayOrder: 3,
        isPublic: false,
      ),
    ]);

    final allSuccess = results.every((r) => r['isSuccess'] == true);
    if (mounted) {
      if (allSuccess) {
        AdminHelpers.showSuccess(context, 'Đã lưu cấu hình Google Drive');
        loadData();
      } else {
        AdminHelpers.showApiError(context, results.firstWhere(
            (r) => r['isSuccess'] != true,
            orElse: () => {'message': 'Lỗi không xác định'}));
      }
    }
  }

  Widget _buildToolbar(List<String> allGroups) {
    final isMobile = Responsive.isMobile(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          if (isMobile) ...[            Row(children: [
              Expanded(
                child: AdminHelpers.searchBar(
                  controller: _searchCtrl,
                  hint: 'Tìm cấu hình theo key, giá trị...',
                  onChanged: () => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => setState(() => _showMobileFilters = !_showMobileFilters),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  height: 40,
                  width: 40,
                  decoration: BoxDecoration(
                    color: _showMobileFilters ? AdminHelpers.primary.withValues(alpha: 0.1) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _showMobileFilters ? AdminHelpers.primary.withValues(alpha: 0.3) : Colors.grey.shade300),
                  ),
                  child: Stack(
                    children: [
                      Center(child: Icon(_showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined, size: 18, color: _showMobileFilters ? AdminHelpers.primary : Colors.grey.shade600)),
                      if (_groupFilter != null)
                        Positioned(top: 4, right: 4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle))),
                    ],
                  ),
                ),
              ),
            ]),
            if (_showMobileFilters) ...[              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _groupFilter,
                        isExpanded: true,
                        hint: const Text('Nhóm', style: TextStyle(fontSize: 13)),
                        items: [
                          const DropdownMenuItem(
                              value: null,
                              child: Text('Tất cả nhóm',
                                  style: TextStyle(fontSize: 13))),
                          ...allGroups.map((g) => DropdownMenuItem(
                              value: g.toLowerCase(),
                              child: Text(g, style: const TextStyle(fontSize: 13)))),
                        ],
                        onChanged: (v) {
                          setState(() => _groupFilter = v);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    final res = await _apiService.initializeAppSettings();
                    if (!mounted) return;
                    if (res['isSuccess'] == true) {
                      loadData();
                      AdminHelpers.showSuccess(
                          context, 'Đã khởi tạo settings mặc định');
                    } else {
                      AdminHelpers.showApiError(context, res);
                    }
                  },
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  label: const Text('Khởi tạo', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AdminHelpers.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12)),
                ),
              ]),
            ],
          ] else ...[          Row(children: [
            Expanded(
              child: AdminHelpers.searchBar(
                controller: _searchCtrl,
                hint: 'Tìm cấu hình theo key, giá trị...',
                onChanged: () => setState(() {}),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _groupFilter,
                  hint: const Text('Nhóm', style: TextStyle(fontSize: 13)),
                  items: [
                    const DropdownMenuItem(
                        value: null,
                        child: Text('Tất cả nhóm',
                            style: TextStyle(fontSize: 13))),
                    ...allGroups.map((g) => DropdownMenuItem(
                        value: g.toLowerCase(),
                        child: Text(g, style: const TextStyle(fontSize: 13)))),
                  ],
                  onChanged: (v) {
                    setState(() => _groupFilter = v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: () async {
                final res = await _apiService.initializeAppSettings();
                if (!mounted) return;
                if (res['isSuccess'] == true) {
                  loadData();
                  AdminHelpers.showSuccess(
                      context, 'Đã khởi tạo settings mặc định');
                } else {
                  AdminHelpers.showApiError(context, res);
                }
              },
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('Khởi tạo mặc định'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primary,
                  foregroundColor: Colors.white),
            ),
          ]),
          ],
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
            AdminHelpers.countBadge(
                'Tổng', _settings.length, AdminHelpers.primary),
            const SizedBox(width: 8),
            ...allGroups.take(5).map((g) {
              final count = _settings
                  .where((s) =>
                      (s['group']?.toString().trim().isNotEmpty == true
                          ? s['group'].toString()
                          : 'General') == g)
                  .length;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AdminHelpers.countBadge(g, count, AdminHelpers.info),
              );
            }),
          ]),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGroup(
      String group, List<Map<String, dynamic>> settings) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AdminHelpers.cardDecoration(borderColor: AdminHelpers.primary),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AdminHelpers.primary.withValues(alpha: 0.1),
          child: const Icon(Icons.settings,
              color: AdminHelpers.primary, size: 18),
        ),
        title: Text(group,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${settings.length} cấu hình',
            style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        children: settings.map(_buildSettingRow).toList(),
      ),
    );
  }

  Widget _buildSettingRow(Map<String, dynamic> setting) {
    final dataType = setting['dataType']?.toString() ?? 'text';
    final value = setting['value']?.toString() ?? '';
    final description = setting['description']?.toString();
    final isPublic = setting['isPublic'] == true;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AdminHelpers.surfaceBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(setting['key']?.toString() ?? 'N/A',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                    ),
                    AdminHelpers.statusChip(dataType, AdminHelpers.info),
                    const SizedBox(width: 6),
                    AdminHelpers.statusChip(
                        isPublic ? 'Public' : 'Private',
                        isPublic ? AdminHelpers.success : Colors.grey),
                  ]),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(description,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    value.isEmpty ? 'Chưa có giá trị' : value,
                    style: TextStyle(
                        fontSize: 12,
                        color: value.isEmpty
                            ? Colors.grey[500]
                            : Colors.grey[800]),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    setting['lastModified'] != null
                        ? 'Cập nhật: ${AdminHelpers.formatDateTime(setting['lastModified'])}'
                        : 'Chưa cập nhật',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ]),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => _showEditSettingDialog(setting),
            icon: const Icon(Icons.edit_outlined, size: 18),
            tooltip: 'Sửa cấu hình',
          ),
        ],
      ),
    );
  }

  void _showEditSettingDialog(Map<String, dynamic> setting) {
    final valueCtrl =
        TextEditingController(text: setting['value']?.toString() ?? '');
    final descriptionCtrl =
        TextEditingController(text: setting['description']?.toString() ?? '');
    final groupCtrl = TextEditingController(
        text: setting['group']?.toString() ?? 'General');
    final displayOrderCtrl = TextEditingController(
        text: (setting['displayOrder'] ?? 0).toString());
    bool isPublic = setting['isPublic'] == true;
    String dataType = setting['dataType']?.toString() ?? 'text';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cập nhật ${setting['key']}'),
        content: SizedBox(
          width: 460,
          child: StatefulBuilder(
            builder: (ctx, setSt) => SingleChildScrollView(
              child:
                  Column(mainAxisSize: MainAxisSize.min, children: [
                AdminHelpers.dialogField(
                    groupCtrl, 'Nhóm', Icons.folder_open),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: dataType,
                  decoration: InputDecoration(
                      labelText: 'Kiểu dữ liệu',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: const [
                    'text',
                    'textarea',
                    'email',
                    'phone',
                    'url',
                    'image'
                  ]
                      .map((item) => DropdownMenuItem(
                          value: item, child: Text(item)))
                      .toList(),
                  onChanged: (value) =>
                      setSt(() => dataType = value ?? dataType),
                ),
                const SizedBox(height: 12),
                AdminHelpers.dialogField(displayOrderCtrl,
                    'Thứ tự hiển thị', Icons.format_list_numbered),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Mô tả',
                    prefixIcon: const Icon(Icons.notes, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueCtrl,
                  maxLines: dataType == 'textarea' ? 5 : 2,
                  decoration: InputDecoration(
                    labelText: 'Giá trị',
                    prefixIcon: const Icon(Icons.tune, size: 20),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Cho phép public'),
                  value: isPublic,
                  onChanged: (value) =>
                      setSt(() => isPublic = value),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final res = await _apiService.upsertAppSetting(
                key: setting['key']?.toString() ?? '',
                value: valueCtrl.text,
                description: descriptionCtrl.text.trim(),
                group: groupCtrl.text.trim().isEmpty
                    ? 'General'
                    : groupCtrl.text.trim(),
                dataType: dataType,
                displayOrder:
                    int.tryParse(displayOrderCtrl.text) ?? 0,
                isPublic: isPublic,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (res['isSuccess'] == true) {
                loadData();
                if (mounted) {
                  AdminHelpers.showSuccess(
                      context, 'Cập nhật cấu hình thành công');
                }
              } else {
                if (mounted) AdminHelpers.showApiError(context, res);
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }
}
