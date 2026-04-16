import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';

class StoresTab extends StatefulWidget {
  const StoresTab({super.key});

  @override
  State<StoresTab> createState() => StoresTabState();
}

class StoresTabState extends State<StoresTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _filteredStores = [];
  bool _isLoading = false;

  final _searchCtrl = TextEditingController();
  String? _statusFilter;
  String? _packageFilter;
  String? _expiryFilter;
  String? _inactivityFilter;
  int _currentPage = 1;
  final int _pageSize = 20;

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

  List<Map<String, dynamic>> get stores => _stores;

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getSystemStores();
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        _stores = AdminHelpers.extractList(res['data']);
        _applyFilters();
      } else {
        AdminHelpers.showApiError(context, res);
      }
    } catch (e) {
      debugPrint('StoresTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  void _applyFilters() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredStores = _stores.where((s) {
        final name = (s['name'] ?? '').toString().toLowerCase();
        final code = (s['code'] ?? '').toString().toLowerCase();
        final phone = (s['phone'] ?? '').toString().toLowerCase();
        final email = (s['ownerEmail'] ?? '').toString().toLowerCase();
        final matchSearch = query.isEmpty ||
            name.contains(query) ||
            code.contains(query) ||
            phone.contains(query) ||
            email.contains(query);

        final isActive = s['isActive'] as bool? ?? true;
        final isLocked = s['isLocked'] as bool? ?? false;
        final matchStatus = _statusFilter == null ||
            (_statusFilter == 'active' && isActive && !isLocked) ||
            (_statusFilter == 'inactive' && !isActive) ||
            (_statusFilter == 'locked' && isLocked);

        // Package filter
        final matchPackage = _packageFilter == null ||
            (s['servicePackageName']?.toString() == _packageFilter);

        // Expiry filter
        final remaining = _getRemainingDays(s);
        final matchExpiry = _expiryFilter == null ||
            (_expiryFilter == 'expired' && remaining != null && remaining <= 0) ||
            (_expiryFilter == 'expiring30' && remaining != null && remaining > 0 && remaining <= 30) ||
            (_expiryFilter == 'valid' && remaining != null && remaining > 30);

        // Inactivity filter
        final inactiveDays = _getInactiveDays(s);
        final matchInactivity = _inactivityFilter == null ||
            (_inactivityFilter == '<7' && inactiveDays != null && inactiveDays < 7) ||
            (_inactivityFilter == '<30' && inactiveDays != null && inactiveDays < 30) ||
            (_inactivityFilter == '<90' && inactiveDays != null && inactiveDays < 90) ||
            (_inactivityFilter == '<180' && inactiveDays != null && inactiveDays < 180) ||
            (_inactivityFilter == '<365' && inactiveDays != null && inactiveDays < 365) ||
            (_inactivityFilter == '>365' && inactiveDays != null && inactiveDays >= 365) ||
            (_inactivityFilter == 'never' && inactiveDays == null);

        return matchSearch && matchStatus && matchPackage && matchExpiry && matchInactivity;
      }).toList();
      _currentPage = 1;
    });
  }

  /// Get remaining days from expiryDate (primary) or trialStartDate+trialDays (fallback)
  int? _getRemainingDays(Map<String, dynamic> store) {
    // Primary: use expiryDate if available
    final expiry = store['expiryDate'];
    if (expiry != null) {
      final expiryDate = DateTime.tryParse(expiry.toString());
      if (expiryDate != null) {
        return expiryDate.difference(DateTime.now()).inDays;
      }
    }
    // Fallback: trialStartDate + trialDays
    final trialStart = store['trialStartDate'];
    final trialDays = store['trialDays'] as int?;
    if (trialStart != null && trialDays != null) {
      final startDate = DateTime.tryParse(trialStart.toString());
      if (startDate != null) {
        final endDate = startDate.add(Duration(days: trialDays));
        return endDate.difference(DateTime.now()).inDays;
      }
    }
    return null;
  }

  /// Get number of inactive days (days since last attendance)
  int? _getInactiveDays(Map<String, dynamic> store) {
    final lastActivity = store['lastActivityAt'];
    if (lastActivity == null) return null;
    final dt = DateTime.tryParse(lastActivity.toString());
    if (dt == null) return null;
    return DateTime.now().difference(dt).inDays;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _buildToolbar(),
        Expanded(
          child: _filteredStores.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.store,
                  _searchCtrl.text.isNotEmpty
                      ? 'Không tìm thấy cửa hàng'
                      : 'Chưa có cửa hàng')
              : _buildPaginatedList(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final activeCount = _stores
        .where((s) => s['isActive'] == true && s['isLocked'] != true)
        .length;
    final inactiveCount = _stores.where((s) => s['isActive'] != true).length;
    final lockedCount = _stores.where((s) => s['isLocked'] == true).length;
    final expiredCount = _stores.where((s) {
      final r = _getRemainingDays(s);
      return r != null && r <= 0;
    }).length;
    final expiringCount = _stores.where((s) {
      final r = _getRemainingDays(s);
      return r != null && r > 0 && r <= 30;
    }).length;

    // Collect unique package names
    final packageNames = _stores
        .map((s) => s['servicePackageName']?.toString())
        .where((n) => n != null)
        .toSet()
        .toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Column(
        children: [
          AdminHelpers.searchBar(
            controller: _searchCtrl,
            hint: 'Tìm cửa hàng theo tên, mã, SĐT...',
            onChanged: _applyFilters,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildDropdown<String?>(
                value: _statusFilter,
                hint: 'Trạng thái',
                items: [
                  _dropItem(null, 'Tất cả'),
                  _dropItem('active', 'Hoạt động'),
                  _dropItem('inactive', 'Tạm tắt'),
                  _dropItem('locked', 'Bị khóa'),
                ],
                onChanged: (v) {
                  _statusFilter = v;
                  _applyFilters();
                },
              ),
              _buildDropdown<String?>(
                value: _expiryFilter,
                hint: 'Thời hạn',
                items: [
                  _dropItem(null, 'Tất cả'),
                  _dropItem('expired', 'Hết hạn'),
                  _dropItem('expiring30', 'Sắp hết (≤30 ngày)'),
                  _dropItem('valid', 'Còn hạn (>30 ngày)'),
                ],
                onChanged: (v) {
                  _expiryFilter = v;
                  _applyFilters();
                },
              ),
              if (packageNames.isNotEmpty)
                _buildDropdown<String?>(
                  value: _packageFilter,
                  hint: 'Gói DV',
                  items: [
                    _dropItem(null, 'Tất cả gói'),
                    ...packageNames.map((n) => _dropItem(n, n!)),
                  ],
                  onChanged: (v) {
                    _packageFilter = v;
                    _applyFilters();
                  },
                ),
              _buildDropdown<String?>(
                value: _inactivityFilter,
                hint: 'Không GD',
                items: [
                  _dropItem(null, 'Tất cả'),
                  _dropItem('<7', '< 7 ngày'),
                  _dropItem('<30', '< 1 tháng'),
                  _dropItem('<90', '< 3 tháng'),
                  _dropItem('<180', '< 6 tháng'),
                  _dropItem('<365', '< 12 tháng'),
                  _dropItem('>365', '> 12 tháng'),
                  _dropItem('never', 'Chưa có GD'),
                ],
                onChanged: (v) {
                  _inactivityFilter = v;
                  _applyFilters();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              AdminHelpers.countBadge(
                  'Tổng', _stores.length, AdminHelpers.primary),
              const SizedBox(width: 8),
              AdminHelpers.countBadge(
                  'Hoạt động', activeCount, AdminHelpers.success),
              const SizedBox(width: 8),
              if (expiringCount > 0) ...[
                AdminHelpers.countBadge(
                    'Sắp hết hạn', expiringCount, AdminHelpers.warning),
                const SizedBox(width: 8),
              ],
              if (expiredCount > 0) ...[
                AdminHelpers.countBadge(
                    'Hết hạn', expiredCount, AdminHelpers.danger),
                const SizedBox(width: 8),
              ],
              if (inactiveCount > 0) ...[
                AdminHelpers.countBadge(
                    'Tạm tắt', inactiveCount, Colors.grey),
                const SizedBox(width: 8),
              ],
              if (lockedCount > 0)
                AdminHelpers.countBadge(
                    'Bị khóa', lockedCount, AdminHelpers.danger),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: const TextStyle(fontSize: 13)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  DropdownMenuItem<String?> _dropItem(String? value, String label) {
    return DropdownMenuItem(
        value: value, child: Text(label, style: const TextStyle(fontSize: 13)));
  }

  Widget _buildPaginatedList() {
    final isMobile = Responsive.isMobile(context);
    final totalCount = _filteredStores.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = isMobile ? 0 : (page - 1) * _pageSize;
    final endIndex = isMobile ? totalCount : (page * _pageSize).clamp(0, totalCount);
    final paginatedItems = _filteredStores.sublist(startIndex.clamp(0, totalCount), endIndex);

    return Column(
      children: [
        Expanded(
          child: Responsive.isMobile(context)
            ? ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                itemCount: paginatedItems.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: _buildStoreDeckItem(paginatedItems[i]),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: paginatedItems.length,
                itemBuilder: (ctx, i) => _buildStoreCard(paginatedItems[i]),
              ),
        ),
        if (totalPages > 1 && !isMobile)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hiển thị ${startIndex + 1}-$endIndex / $totalCount', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Row(children: [
                  IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: page > 1 ? () => setState(() => _currentPage--) : null, visualDensity: VisualDensity.compact),
                  Text('$page / $totalPages', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: page < totalPages ? () => setState(() => _currentPage++) : null, visualDensity: VisualDensity.compact),
                ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStoreDeckItem(Map<String, dynamic> store) {
    final isActive = store['isActive'] as bool? ?? true;
    final isLocked = store['isLocked'] as bool? ?? false;
    final name = store['name'] ?? store['storeName'] ?? 'N/A';
    final phone = store['phone']?.toString() ?? '';
    final licenseType = store['licenseType']?.toString() ?? '';

    return InkWell(
      onTap: () => _showStoreDetail(store),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.store, color: Color(0xFF1E3A5F), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([if (phone.isNotEmpty) phone, AdminHelpers.licenseTypeLabel(licenseType)].join(' \u00b7 '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isLocked ? Colors.red.withValues(alpha: 0.1) : isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(isLocked ? 'Kh\u00f3a' : isActive ? 'H\u0110' : 'T\u1eaft', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isLocked ? Colors.red : isActive ? Colors.green : Colors.grey)),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
        ]),
      ),
    );
  }

  Widget _buildStoreCard(Map<String, dynamic> store) {
    final isActive = store['isActive'] as bool? ?? true;
    final isLocked = store['isLocked'] as bool? ?? false;
    final name = store['name'] ?? store['storeName'] ?? 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AdminHelpers.cardDecoration(
        borderColor: isLocked
            ? AdminHelpers.danger
            : isActive
                ? AdminHelpers.primary
                : Colors.grey,
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AdminHelpers.primary.withValues(alpha: 0.1),
          child:
              const Icon(Icons.store, color: AdminHelpers.primary, size: 20),
        ),
        title: Text(name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (store['phone'] != null)
            Text(store['phone'],
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
          const SizedBox(height: 4),
          Row(children: [
            AdminHelpers.statusChip(
                isLocked
                    ? 'Bị khóa'
                    : isActive
                        ? 'Hoạt động'
                        : 'Tắt',
                isLocked
                    ? AdminHelpers.danger
                    : isActive
                        ? AdminHelpers.success
                        : Colors.grey),
            const SizedBox(width: 6),
            if (store['licenseType'] != null)
              AdminHelpers.statusChip(
                  AdminHelpers.licenseTypeLabel(store['licenseType']?.toString()), AdminHelpers.primaryDark),
            if (store['servicePackageName'] != null) ...[              const SizedBox(width: 6),
              AdminHelpers.statusChip(
                  store['servicePackageName'], const Color(0xFF7C3AED)),
            ],
            if (_getTrialStatus(store) != null) ...[              const SizedBox(width: 6),
              _getTrialStatus(store)!,
            ],
            () {
              final days = _getInactiveDays(store);
              final Color chipColor;
              final String label;
              if (days == null) {
                chipColor = Colors.grey;
                label = 'Chưa có GD';
              } else if (days == 0) {
                chipColor = AdminHelpers.success;
                label = 'Hôm nay';
              } else if (days < 7) {
                chipColor = AdminHelpers.success;
                label = '$days ngày';
              } else if (days < 30) {
                chipColor = Colors.orange;
                label = '$days ngày';
              } else {
                chipColor = AdminHelpers.danger;
                label = '$days ngày';
              }
              return Padding(
                padding: const EdgeInsets.only(left: 6),
                child: AdminHelpers.statusChip(label, chipColor),
              );
            }(),
          ]),
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // User accounts button
            IconButton(
              onPressed: () => _showStoreUsers(store),
              icon: const Icon(Icons.people, size: 20),
              tooltip: 'Tài khoản cửa hàng',
              color: AdminHelpers.info,
            ),
            const Icon(Icons.expand_more, size: 20),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(children: [
              if (store['address'] != null)
                AdminHelpers.infoRow(Icons.location_on, store['address']),
              if (store['ownerEmail'] != null)
                AdminHelpers.infoRow(Icons.email, store['ownerEmail']),
              AdminHelpers.infoRow(Icons.people,
                  'Users: ${store['userCount'] ?? store['totalUsers'] ?? 'N/A'}'),
              AdminHelpers.infoRow(Icons.router,
                  'Devices: ${store['deviceCount'] ?? store['totalDevices'] ?? 'N/A'}'),
              if (store['servicePackageName'] != null)
                AdminHelpers.infoRow(Icons.inventory,
                    'Gói DV: ${store['servicePackageName']}'),
              if (store['trialDays'] != null)
                AdminHelpers.infoRow(Icons.timer,
                    'Dùng thử: ${store['trialDays']} ngày'),
              if (store['expiryDate'] != null)
                AdminHelpers.infoRow(Icons.event,
                    'Hết hạn: ${AdminHelpers.formatDate(store['expiryDate'])}'),
              () {
                final days = _getInactiveDays(store);
                final lastActivity = store['lastActivityAt'];
                if (days != null && lastActivity != null) {
                  final dt = DateTime.tryParse(lastActivity.toString());
                  final formatted = dt != null
                      ? '${dt.day}/${dt.month}/${dt.year}'
                      : lastActivity.toString();
                  return AdminHelpers.infoRow(Icons.access_time,
                      'GD cuối: $formatted ($days ngày trước)');
                }
                return AdminHelpers.infoRow(
                    Icons.access_time, 'Chưa có giao dịch');
              }(),
              AdminHelpers.infoRow(Icons.autorenew,
                  'Gia hạn: ${store['renewalCount'] ?? 0}/3 lần'),
              if (isLocked && store['lockReason'] != null)
                AdminHelpers.infoRow(
                    Icons.info_outline, 'Lý do khóa: ${store['lockReason']}'),
              const Divider(height: 24),
              // Action buttons row 1: primary actions
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _actionButton(
                    icon: Icons.edit,
                    label: 'Đổi tên',
                    color: AdminHelpers.primary,
                    onTap: () => _editStoreName(store),
                  ),
                  _actionButton(
                    icon: Icons.info_outline,
                    label: 'Chi tiết',
                    color: AdminHelpers.info,
                    onTap: () => _showStoreDetail(store),
                  ),
                  _actionButton(
                    icon: isActive ? Icons.pause : Icons.play_arrow,
                    label: isActive ? 'Tắt' : 'Bật',
                    color: isActive ? Colors.orange : AdminHelpers.success,
                    onTap: () => _toggleStoreStatus(store),
                  ),
                  if (!isLocked)
                    _actionButton(
                      icon: Icons.lock,
                      label: 'Khóa',
                      color: AdminHelpers.danger,
                      onTap: () => _lockStore(store),
                    )
                  else
                    _actionButton(
                      icon: Icons.lock_open,
                      label: 'Mở khóa',
                      color: AdminHelpers.success,
                      onTap: () => _unlockStore(store),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              // Action buttons row 2: danger zone
              Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  _actionButton(
                    icon: Icons.vpn_key,
                    label: 'Kích hoạt Key',
                    color: AdminHelpers.success,
                    onTap: () => _showActivateKey(store),
                  ),
                  _actionButton(
                    icon: Icons.calendar_month,
                    label: 'Gia hạn (${store['renewalCount'] ?? 0}/3)',
                    color: const Color(0xFF7C3AED),
                    onTap: () => _showExtendDays(store),
                  ),
                  _actionButton(
                    icon: Icons.restart_alt,
                    label: 'Khôi phục gốc',
                    color: AdminHelpers.warning,
                    onTap: () => _resetStoreData(store),
                  ),
                  _actionButton(
                    icon: Icons.delete_forever,
                    label: 'Xóa hoàn toàn',
                    color: AdminHelpers.danger,
                    onTap: () => _deleteStore(store),
                  ),
                ],
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  // ═══════════════════════ EDIT STORE NAME ═══════════════════════
  Future<void> _editStoreName(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final currentName = store['name']?.toString() ?? '';
    final nameCtrl = TextEditingController(text: currentName);
    final descCtrl =
        TextEditingController(text: store['description']?.toString() ?? '');
    final addressCtrl =
        TextEditingController(text: store['address']?.toString() ?? '');
    final phoneCtrl =
        TextEditingController(text: store['phone']?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.edit, color: AdminHelpers.primary, size: 22),
          SizedBox(width: 8),
          Text('Chỉnh sửa cửa hàng', style: TextStyle(fontSize: 18)),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdminHelpers.dialogField(
                  nameCtrl, 'Tên cửa hàng', Icons.store),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  descCtrl, 'Mô tả', Icons.description),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  addressCtrl, 'Địa chỉ', Icons.location_on),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  phoneCtrl, 'Số điện thoại', Icons.phone),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Lưu'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final res = await _apiService.updateStore(
      storeId,
      name: nameCtrl.text.trim(),
      description: descCtrl.text.trim(),
      address: addressCtrl.text.trim(),
      phone: phoneCtrl.text.trim(),
    );

    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Cập nhật cửa hàng thành công');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ STORE DETAIL ═══════════════════════
  Future<void> _showStoreDetail(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final res = await _apiService.getStoreFullDetail(storeId);

    if (!mounted) return;
    if (res['isSuccess'] != true) {
      AdminHelpers.showApiError(context, res);
      return;
    }

    final d = res['data'] as Map<String, dynamic>? ?? {};
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleRow = Row(children: [
      const Icon(Icons.store, color: AdminHelpers.primary, size: 22),
      const SizedBox(width: 8),
      Expanded(
          child: Text(d['name'] ?? 'Chi tiết',
              style: const TextStyle(fontSize: 18))),
    ]);

    final contentBody = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _detailSection('Thông tin cơ bản', [
          _detailRow('Mã', d['code']),
          _detailRow('Tên', d['name']),
          _detailRow('Mô tả', d['description']),
        ]),
        _detailSection('Liên hệ', [
          _detailRow('Địa chỉ', d['address']),
          _detailRow('Điện thoại', d['phone']),
          _detailRow('Email chủ sở hữu', d['ownerEmail']),
          _detailRow('Chủ sở hữu', d['ownerName']),
        ]),
        _detailSection('Trạng thái', [
          _detailRow(
              'Hoạt động', d['isActive'] == true ? 'Có' : 'Không'),
          _detailRow(
              'Bị khóa', d['isLocked'] == true ? 'Có' : 'Không'),
          if (d['isLocked'] == true)
            _detailRow('Lý do khóa', d['lockReason']),
          if (d['lockedAt'] != null)
            _detailRow('Khóa lúc',
                AdminHelpers.formatDateTime(d['lockedAt'])),
        ]),
        _detailSection('Gói dịch vụ & License', [
          _detailRow('Gói dịch vụ', d['servicePackageName']),
          _detailRow('Loại license', d['licenseType']),
          _detailRow('License key', d['licenseKey']),
          _detailRow('Hết hạn',
              AdminHelpers.formatDate(d['expiryDate'])),
          _detailRow('Ngày bắt đầu dùng thử',
              AdminHelpers.formatDate(d['trialStartDate'])),
          _detailRow('Số ngày dùng thử',
              d['trialDays']?.toString()),
          _detailRow(
              'Max Users', d['maxUsers']?.toString()),
          _detailRow(
              'Max Devices', d['maxDevices']?.toString()),
        ]),
        _detailSection('Thống kê', [
          _detailRow(
              'Tổng Users', d['totalUsers']?.toString()),
          _detailRow(
              'Tổng Devices', d['totalDevices']?.toString()),
        ]),
        _detailSection('Thời gian', [
          _detailRow('Tạo lúc',
              AdminHelpers.formatDateTime(d['createdAt'])),
          _detailRow('Cập nhật',
              AdminHelpers.formatDateTime(d['updatedAt'])),
        ]),
      ],
    );

    if (isMobile) {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          insetPadding: EdgeInsets.zero,
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
                title: Text(d['name'] ?? 'Chi tiết', overflow: TextOverflow.ellipsis),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 16),
                    contentBody,
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: titleRow,
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng')),
          ],
        ),
      );
    }
  }

  Widget _detailSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AdminHelpers.primaryDark)),
        const Divider(height: 24),
        ...children,
      ],
    );
  }

  Widget _detailRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 140,
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[600]))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  // ═══════════════════════ STORE USERS / ACCOUNTS ═══════════════════════
  Future<void> _showStoreUsers(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final storeName = store['name'] ?? 'N/A';

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final res = await _apiService.getSystemUsers(storeId: storeId);
    if (!mounted) return;
    Navigator.pop(context); // dismiss loading

    if (res['isSuccess'] != true) {
      AdminHelpers.showApiError(context, res);
      return;
    }

    final users = AdminHelpers.extractList(res['data']);

    showDialog(
      context: context,
      builder: (ctx) => _StoreUsersDialog(
        storeName: storeName,
        users: users,
        apiService: _apiService,
      ),
    );
  }

  // ═══════════════════════ RESET STORE DATA ═══════════════════════
  Future<void> _resetStoreData(Map<String, dynamic> store) async {
    final name = store['name'] ?? 'N/A';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber, color: AdminHelpers.warning, size: 24),
          SizedBox(width: 8),
          Text('Khôi phục cài đặt gốc'),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bạn sắp khôi phục cài đặt gốc cho cửa hàng "$name".'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminHelpers.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AdminHelpers.warning.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Thao tác này sẽ xóa:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('• Toàn bộ dữ liệu chấm công'),
                    Text('• Toàn bộ thiết bị và cấu hình'),
                    Text('• Toàn bộ nhân viên'),
                    Text('• Toàn bộ lệnh thiết bị'),
                    SizedBox(height: 8),
                    Text('Tài khoản người dùng sẽ được giữ lại.',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AdminHelpers.success)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restart_alt, size: 16),
            label: const Text('Xác nhận khôi phục'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.warning),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final storeId = store['id']?.toString() ?? '';
    final res = await _apiService.deleteAllStoreData(storeId);

    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(
          context, 'Đã khôi phục cài đặt gốc cho "$name"');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ DELETE STORE ═══════════════════════
  Future<void> _deleteStore(Map<String, dynamic> store) async {
    final name = store['name'] ?? 'N/A';
    final storeId = store['id']?.toString() ?? '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.delete_forever, color: AdminHelpers.danger, size: 24),
          SizedBox(width: 8),
          Text('Xóa hoàn toàn cửa hàng'),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Bạn sắp XÓA HOÀN TOÀN cửa hàng "$name".'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminHelpers.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AdminHelpers.danger.withValues(alpha: 0.3)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('⚠ CẢNH BÁO: Không thể hoàn tác!',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AdminHelpers.danger)),
                    SizedBox(height: 4),
                    Text('Cửa hàng sẽ bị xóa khỏi danh sách.'),
                    Text('Tất cả dữ liệu liên quan sẽ bị xóa:'),
                    SizedBox(height: 4),
                    Text('• Toàn bộ tài khoản người dùng'),
                    Text('• Toàn bộ dữ liệu chấm công'),
                    Text('• Toàn bộ nhân viên & phòng ban'),
                    Text('• Toàn bộ thiết bị & cấu hình'),
                    Text('• Toàn bộ lương, phụ cấp, KPI'),
                    Text('• Và tất cả dữ liệu khác'),
                    SizedBox(height: 8),
                    Text('Tên cửa hàng có thể được đăng ký lại.',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AdminHelpers.info)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('Xóa hoàn toàn'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.danger),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final res = await _apiService.deleteStore(storeId);

    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(
          context, 'Đã xóa hoàn toàn cửa hàng "$name"');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ STATUS ACTIONS ═══════════════════════
  Future<void> _toggleStoreStatus(Map<String, dynamic> store) async {
    await _apiService.toggleStoreStatus(store['id']?.toString() ?? '');
    loadData();
  }

  Future<void> _lockStore(Map<String, dynamic> store) async {
    final reason = await AdminHelpers.showInputDialog(
        context, 'Khóa cửa hàng', 'Lý do khóa (tùy chọn)');
    if (reason == null) return;
    await _apiService.lockStore(
        store['id']?.toString() ?? '', reason.isNotEmpty ? reason : null);
    loadData();
  }

  Future<void> _unlockStore(Map<String, dynamic> store) async {
    await _apiService.unlockStore(store['id']?.toString() ?? '');
    loadData();
  }

  // ═══════════════════════ TRIAL STATUS HELPER ═══════════════════════
  Widget? _getTrialStatus(Map<String, dynamic> store) {
    final remaining = _getRemainingDays(store);
    if (remaining == null) return null;

    if (remaining > 30) {
      return AdminHelpers.statusChip(
          'Còn $remaining ngày', AdminHelpers.success);
    } else if (remaining > 0) {
      return AdminHelpers.statusChip(
          'Còn $remaining ngày', AdminHelpers.warning);
    } else {
      return AdminHelpers.statusChip('Hết hạn', AdminHelpers.danger);
    }
  }

  // ═══════════════════════ EXTEND DAYS ═══════════════════════
  Future<void> _showExtendDays(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final name = store['name'] ?? 'N/A';
    final renewalCount = store['renewalCount'] as int? ?? 0;

    if (renewalCount >= 3) {
      AdminHelpers.showError(context,
          'Cửa hàng "$name" đã gia hạn tối đa 3 lần. Vui lòng kích hoạt key mới.');
      return;
    }

    final daysCtrl = TextEditingController(text: '30');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const Icon(Icons.calendar_month,
              color: Color(0xFF7C3AED), size: 22),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Gia hạn — $name',
                  style: const TextStyle(fontSize: 17))),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 350,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Nhập số ngày muốn gia hạn thêm:'),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  daysCtrl, 'Số ngày', Icons.timer),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Hủy')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Gia hạn'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED)),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    final days = int.tryParse(daysCtrl.text.trim());
    if (days == null || days <= 0) {
      AdminHelpers.showError(context, 'Số ngày không hợp lệ');
      return;
    }

    final res = await _apiService.extendStoreDays(storeId, days);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã gia hạn thêm $days ngày cho "$name"');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ KÍCH HOẠT KEY (NHIỀU KEY) ═══════════════════════
  Future<void> _showActivateKey(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final name = store['name'] ?? 'N/A';

    final keyControllers = <TextEditingController>[TextEditingController()];
    Map<String, dynamic>? previewData;
    bool isPreviewing = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.vpn_key, color: AdminHelpers.success, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text('Kích hoạt Key — $name',
                    style: const TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: AdminHelpers.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline,
                          color: AdminHelpers.info, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nhập 1 hoặc nhiều license key (cùng gói dịch vụ).\n'
                          'Kích nhiều key sẽ được tặng thêm ngày nếu có chương trình khuyến mãi.',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    ]),
                  ),
                  ...List.generate(keyControllers.length, (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: keyControllers[i],
                          decoration: InputDecoration(
                            labelText: 'Key ${i + 1}',
                            prefixIcon: const Icon(Icons.vpn_key, size: 18),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setDlgState(() => previewData = null),
                        ),
                      ),
                      if (keyControllers.length > 1)
                        IconButton(
                          icon: const Icon(Icons.remove_circle, color: Colors.red, size: 20),
                          onPressed: () {
                            setDlgState(() {
                              keyControllers[i].dispose();
                              keyControllers.removeAt(i);
                              previewData = null;
                            });
                          },
                        ),
                    ]),
                  )),
                  if (keyControllers.length < 4)
                    TextButton.icon(
                      onPressed: () => setDlgState(() {
                        keyControllers.add(TextEditingController());
                        previewData = null;
                      }),
                      icon: const Icon(Icons.add, size: 16),
                      label: Text('Thêm key (${keyControllers.length}/4)'),
                    ),
                  const SizedBox(height: 8),
                  // Preview button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isPreviewing ? null : () async {
                        final keys = keyControllers
                            .map((c) => c.text.trim())
                            .where((k) => k.isNotEmpty)
                            .toList();
                        if (keys.isEmpty) return;
                        setDlgState(() => isPreviewing = true);
                        final res = await _apiService.previewBulkActivation(storeId, keys);
                        if (ctx.mounted) {
                          setDlgState(() {
                            isPreviewing = false;
                            if (res['isSuccess'] == true) {
                              previewData = res['data'] is Map<String, dynamic>
                                  ? res['data'] as Map<String, dynamic>
                                  : null;
                            } else {
                              previewData = null;
                              NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi');
                            }
                          });
                        }
                      },
                      icon: isPreviewing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.preview, size: 16),
                      label: const Text('Xem trước'),
                    ),
                  ),
                  // Preview result
                  if (previewData != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminHelpers.success.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AdminHelpers.success.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Kết quả dự kiến:', style: TextStyle(fontWeight: FontWeight.bold, color: AdminHelpers.success)),
                          const SizedBox(height: 6),
                          Text('• Số key hợp lệ: ${previewData!['keyCount']}'),
                          Text('• Tổng ngày từ key: ${previewData!['totalDays']} ngày'),
                          if ((previewData!['bonusDays'] as int? ?? 0) > 0) ...[
                            Text('• 🎁 Ngày tặng thêm: ${previewData!['bonusDays']} ngày',
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            if (previewData!['promotionName'] != null)
                              Text('  (CT: ${previewData!['promotionName']})',
                                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                          ],
                          const Divider(),
                          Text('Tổng cộng: ${previewData!['grandTotalDays']} ngày',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          if (previewData!['newExpiryDate'] != null)
                            Text('Hạn mới: ${_fmtDate(previewData!['newExpiryDate'])}',
                                style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            ElevatedButton.icon(
              onPressed: () async {
                final keys = keyControllers
                    .map((c) => c.text.trim())
                    .where((k) => k.isNotEmpty)
                    .toList();
                if (keys.isEmpty) {
                  NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: 'Vui lòng nhập ít nhất 1 key');
                  return;
                }
                Navigator.pop(ctx);
                final res = await _apiService.bulkActivateLicenses(storeId, keys);
                if (!mounted) return;
                if (res['isSuccess'] == true) {
                  final data = res['data'];
                  final bonus = data is Map ? (data['bonusDays'] ?? 0) : 0;
                  final total = data is Map ? (data['grandTotalDays'] ?? 0) : 0;
                  AdminHelpers.showSuccess(context,
                      'Đã kích hoạt ${keys.length} key cho "$name".\n'
                      'Tổng: $total ngày (bonus: $bonus ngày)');
                  loadData();
                } else {
                  AdminHelpers.showApiError(context, res);
                }
              },
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Kích hoạt'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.success),
            ),
          ],
        ),
      ),
    );

    for (final c in keyControllers) {
      c.dispose();
    }
  }

  String _fmtDate(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return d.toString();
    }
  }

  // ═══════════════════════ ASSIGN SERVICE PACKAGE ═══════════════════════
  // ignore: unused_element
  Future<void> _showAssignPackage(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final name = store['name'] ?? 'N/A';

    // Load packages
    final res = await _apiService.getServicePackages();
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      AdminHelpers.showApiError(context, res);
      return;
    }

    final packages = AdminHelpers.extractList(res['data']);
    if (packages.isEmpty) {
      AdminHelpers.showError(context, 'Chưa có gói dịch vụ nào');
      return;
    }

    String? selectedId = store['servicePackageId']?.toString();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.inventory,
                color: AdminHelpers.info, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text('Gán gói DV — $name',
                    style: const TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: packages.map((pkg) {
                final pkgId = pkg['id']?.toString() ?? '';
                final isSelected = selectedId == pkgId;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: isSelected
                          ? AdminHelpers.primary
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    color: isSelected
                        ? AdminHelpers.primary.withValues(alpha: 0.05)
                        : null,
                  ),
                  child: ListTile(
                    onTap: () => setDlgState(() => selectedId = pkgId),
                    leading: Icon(
                      isSelected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: isSelected
                          ? AdminHelpers.primary
                          : Colors.grey,
                    ),
                    title: Text(pkg['name'] ?? '',
                        style: const TextStyle(
                            fontWeight: FontWeight.w600)),
                    subtitle: Text(
                        '${pkg['defaultDurationDays'] ?? 0} ngày · '
                        'Max ${pkg['maxUsers'] ?? 0} users · '
                        'Max ${pkg['maxDevices'] ?? 0} devices',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey[600])),
                    trailing: (pkg['isActive'] == true)
                        ? const Icon(Icons.check_circle,
                            color: AdminHelpers.success, size: 18)
                        : const Icon(Icons.cancel,
                            color: Colors.grey, size: 18),
                  ),
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Hủy')),
            ElevatedButton.icon(
              onPressed: selectedId != null
                  ? () => Navigator.pop(ctx, selectedId)
                  : null,
              icon: const Icon(Icons.check, size: 16),
              label: const Text('Gán gói'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primary),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final assignRes =
        await _apiService.assignPackageToStore(storeId, result);
    if (!mounted) return;
    if (assignRes['isSuccess'] == true) {
      AdminHelpers.showSuccess(
          context, 'Đã gán gói dịch vụ cho "$name"');
      loadData();
    } else {
      AdminHelpers.showApiError(context, assignRes);
    }
  }
}

// ═══════════════════════ STORE USERS DIALOG ═══════════════════════
class _StoreUsersDialog extends StatefulWidget {
  final String storeName;
  final List<Map<String, dynamic>> users;
  final ApiService apiService;

  const _StoreUsersDialog({
    required this.storeName,
    required this.users,
    required this.apiService,
  });

  @override
  State<_StoreUsersDialog> createState() => _StoreUsersDialogState();
}

class _StoreUsersDialogState extends State<_StoreUsersDialog> {
  late List<Map<String, dynamic>> _users;
  // Track which user's password is visible
  // ignore: unused_field
  final Map<String, bool> _showPassword = {};
  final Map<String, String> _newPasswords = {};

  @override
  void initState() {
    super.initState();
    _users = List.from(widget.users);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        const Icon(Icons.people, color: AdminHelpers.info, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Tài khoản — ${widget.storeName}',
              style: const TextStyle(fontSize: 17)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AdminHelpers.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text('${_users.length} tài khoản',
              style: const TextStyle(
                  fontSize: 12, color: AdminHelpers.primary)),
        ),
      ]),
      content: SizedBox(
        width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 600,
        height: 450,
        child: _users.isEmpty
            ? AdminHelpers.emptyState(Icons.person_off, 'Không có tài khoản')
            : ListView.separated(
                itemCount: _users.length,
                separatorBuilder: (_, __) => const Divider(height: 24),
                itemBuilder: (ctx, i) => _buildUserTile(_users[i]),
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Đóng')),
      ],
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id']?.toString() ?? '';
    final email = user['email'] ?? 'N/A';
    final fullName = user['fullName'] ?? '';
    final role = user['role'] ?? '';
    final isActive = user['isActive'] as bool? ?? true;
    final lastLogin = user['lastLoginAt'];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _roleColor(role).withValues(alpha: 0.15),
                child:
                    Text(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: _roleColor(role),
                          fontWeight: FontWeight.bold,
                        )),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(fullName.isNotEmpty ? fullName : email,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 6),
                      AdminHelpers.statusChip(role, _roleColor(role)),
                      if (!isActive) ...[
                        const SizedBox(width: 4),
                        AdminHelpers.statusChip(
                            'Inactive', AdminHelpers.danger),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.email, size: 12, color: Colors.grey[500]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(email,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                        ),
                        // Copy email
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: email));
                            AdminHelpers.showSuccess(context, 'Đã copy email');
                          },
                          child: Icon(Icons.copy,
                              size: 14, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                    if (lastLogin != null)
                      Text(
                          'Đăng nhập cuối: ${AdminHelpers.formatDateTime(lastLogin)}',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey[500])),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Password management row
          Row(
            children: [
              const SizedBox(width: 46), // align with content
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.vpn_key,
                          size: 14, color: Colors.grey[500]),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _newPasswords.containsKey(userId)
                            ? Text(_newPasswords[userId]!,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600))
                            : Text('••••••••',
                                style: TextStyle(
                                    fontSize: 13, color: Colors.grey[500])),
                      ),
                      // Reset password
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _resetPassword(userId, email),
                        icon: const Icon(Icons.refresh,
                            size: 14, color: AdminHelpers.warning),
                        label: const Text('Đặt lại MK',
                            style: TextStyle(
                                fontSize: 11, color: AdminHelpers.warning)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role.toLowerCase()) {
      case 'superadmin':
        return AdminHelpers.danger;
      case 'admin':
        return AdminHelpers.primary;
      case 'manager':
        return AdminHelpers.info;
      default:
        return Colors.grey;
    }
  }

  Future<void> _resetPassword(String userId, String email) async {
    final newPass = await AdminHelpers.showInputDialog(
      context,
      'Đặt lại mật khẩu',
      'Nhập mật khẩu mới cho $email',
    );
    if (newPass == null || newPass.isEmpty) return;

    final res = await widget.apiService.updateUserCredentials(
      userId,
      newPassword: newPass,
    );

    if (!mounted) return;
    if (res['isSuccess'] == true) {
      setState(() {
        _newPasswords[userId] = newPass;
      });
      AdminHelpers.showSuccess(context, 'Đã đặt lại mật khẩu cho $email');
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }
}
