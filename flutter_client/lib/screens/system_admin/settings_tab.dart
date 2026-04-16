import 'package:flutter/material.dart';
import '../../services/api_service.dart';
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
