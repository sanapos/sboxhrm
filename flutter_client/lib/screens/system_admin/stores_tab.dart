import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:flutter/services.dart';
import '../../data/vietnam_provinces.dart';
import '../../services/api_service.dart';
import '../../utils/agent_mutation_result.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/admin/admin_mobile_widgets.dart';
import '../../widgets/notification_overlay.dart';
import 'system_admin_helpers.dart';
import '../../widgets/hrm_page_chrome.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class StoresTab extends StatefulWidget {
  final bool agentMode;

  const StoresTab({super.key, this.agentMode = false});

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
  String? _usageFilter; // trial / active / inactive / expired
  String? _inactivityFilter;
  String? _agentFilter; // agentId | '__none__' (chưa gán) | null (tất cả)
  List<Map<String, dynamic>> _agents = [];
  int _currentPage = 1;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    loadData();
    if (!widget.agentMode) _loadAgents();
  }

  Future<void> _loadAgents() async {
    try {
      final res = await _apiService.getSystemAgents(pageSize: 1000);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() => _agents = AdminHelpers.extractList(res['data']));
      }
    } catch (e) {
      debugPrint('StoresTab load agents error: $e');
    }
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
      final res = widget.agentMode
          ? await _apiService.getAgentStores()
          : await _apiService.getSystemStores();
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
        final province = (s['province'] ?? '').toString().toLowerCase();
        final matchSearch = query.isEmpty ||
            name.contains(query) ||
            code.contains(query) ||
            phone.contains(query) ||
            province.contains(query) ||
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

        // Usage filter (trial / active / inactive / expired)
        final usage = _getUsageStatus(s);
        final matchUsage = _usageFilter == null || usage == _usageFilter;

        // Agent filter
        final agentId = s['agentId']?.toString();
        final matchAgent = _agentFilter == null ||
            (_agentFilter == '__none__' &&
                (agentId == null || agentId.isEmpty)) ||
            (_agentFilter != '__none__' && agentId == _agentFilter);

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

        return matchSearch && matchStatus && matchPackage && matchExpiry && matchUsage && matchInactivity && matchAgent;
      }).toList();
      _currentPage = 1;
    });
  }

  /// Get remaining days from expiryDate (primary) or trialStartDate+trialDays (fallback)
  int? _getRemainingDays(Map<String, dynamic> store) =>
      AdminHelpers.getStoreRemainingDays(store);

  /// Get number of inactive days (days since last attendance)
  int? _getInactiveDays(Map<String, dynamic> store) {
    final lastActivity = store['lastActivityAt'];
    if (lastActivity == null) return null;
    final dt = DateTime.tryParse(lastActivity.toString());
    if (dt == null) return null;
    return DateTime.now().difference(dt).inDays;
  }

  /// Returns true if store is currently on a trial license (not a paid package)
  bool _isTrial(Map<String, dynamic> store) {
    final lt = (store['licenseType'] ?? '').toString().toLowerCase();
    // Treat as trial when licenseType explicitly says trial, OR when there is no
    // paid package AND a trialStartDate/trialDays is configured.
    if (lt == 'trial') return true;
    final hasPackage = store['servicePackageName'] != null;
    final hasTrial = store['trialStartDate'] != null && store['trialDays'] != null;
    return !hasPackage && hasTrial;
  }

  /// Compute usage status for filters/badges:
  /// 'trial'   = đang dùng thử (còn hạn dùng thử)
  /// 'active'  = đang sử dụng (đã mua, còn hạn, có giao dịch)
  /// 'inactive'= không sử dụng (còn hạn nhưng chưa từng có giao dịch)
  /// 'expired' = hết hạn sử dụng
  String _getUsageStatus(Map<String, dynamic> store) {
    final remaining = _getRemainingDays(store);
    if (remaining != null && remaining <= 0) return 'expired';
    if (_isTrial(store)) return 'trial';
    final lastActivity = store['lastActivityAt'];
    if (lastActivity == null) return 'inactive';
    return 'active';
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

  int get _activeFilterCount {
    var n = 0;
    if (_statusFilter != null) n++;
    if (_usageFilter != null) n++;
    if (_expiryFilter != null) n++;
    if (_packageFilter != null) n++;
    if (_inactivityFilter != null) n++;
    if (_agentFilter != null) n++;
    return n;
  }

  void _clearFilters() {
    setState(() {
      _statusFilter = null;
      _usageFilter = null;
      _expiryFilter = null;
      _packageFilter = null;
      _inactivityFilter = null;
      _agentFilter = null;
    });
    _applyFilters();
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
    final trialCount =
        _stores.where((s) => _getUsageStatus(s) == 'trial').length;
    final usingCount =
        _stores.where((s) => _getUsageStatus(s) == 'active').length;
    final notUsingCount =
        _stores.where((s) => _getUsageStatus(s) == 'inactive').length;

    // Collect unique package names
    final packageNames = _stores
        .map((s) => s['servicePackageName']?.toString())
        .where((n) => n != null)
        .toSet()
        .toList();

    final statsRow = AdminMobileStatRow(children: [
      AdminHelpers.countBadge('Tổng', _stores.length, AdminHelpers.primary),
      const SizedBox(width: 8),
      AdminHelpers.countBadge('Hoạt động', activeCount, AdminHelpers.success),
      if (trialCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge(
            'Dùng thử', trialCount, HrmPageChrome.chipMid),
      ],
      if (usingCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge('Đang SD', usingCount, AdminHelpers.info),
      ],
      if (notUsingCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge(
            'Không SD', notUsingCount, Colors.grey.shade600),
      ],
      if (expiringCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge(
            'Sắp hết hạn', expiringCount, AdminHelpers.warning),
      ],
      if (expiredCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge('Hết hạn', expiredCount, AdminHelpers.danger),
      ],
      if (inactiveCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge('Tạm tắt', inactiveCount, Colors.grey),
      ],
      if (lockedCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge('Bị khóa', lockedCount, AdminHelpers.danger),
      ],
    ]);

    if (adminUseMobileLayout(context)) {
      return AdminMobileListToolbar(
        searchController: _searchCtrl,
        searchHint: 'Tìm cửa hàng theo tên, mã, SĐT...',
        onSearchChanged: _applyFilters,
        activeFilterCount: _activeFilterCount,
        onRefresh: loadData,
        onOpenFilters: () => showAdminFilterSheet(
          context,
          onApply: _applyFilters,
          onClear: _clearFilters,
          child: _buildFilterFields(packageNames),
        ),
        stats: statsRow,
      );
    }

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
          _buildFilterFields(packageNames),
          const SizedBox(height: 8),
          statsRow,
        ],
      ),
    );
  }

  Widget _buildFilterFields(List<String?> packageNames) {
    final mobile = adminUseMobileLayout(context);
    final filters = <Widget>[
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
        value: _usageFilter,
        hint: 'Tình trạng SD',
        items: [
          _dropItem(null, 'Tất cả tình trạng'),
          _dropItem('trial', 'Đang dùng thử'),
          _dropItem('active', 'Đang sử dụng'),
          _dropItem('inactive', 'Không sử dụng'),
          _dropItem('expired', 'Hết hạn sử dụng'),
        ],
        onChanged: (v) {
          _usageFilter = v;
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
      _buildDropdown<String?>(
        value: _agentFilter,
        hint: 'Đại lý',
        items: [
          _dropItem(null, 'Tất cả đại lý'),
          _dropItem('__none__', 'Chưa gán đại lý'),
          ..._agents.map((a) => _dropItem(
                a['id']?.toString(),
                (a['name'] ?? a['code'] ?? 'Đại lý').toString(),
              )),
        ],
        onChanged: (v) {
          _agentFilter = v;
          _applyFilters();
        },
      ),
    ];

    if (mobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: filters,
      );
    }
    return Wrap(spacing: 6, runSpacing: 6, children: filters);
  }

  Widget _buildDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    final mobile = adminUseMobileLayout(context);
    return Container(
      width: mobile ? double.infinity : null,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          isExpanded: mobile,
          value: value,
          hint: Text(tr(hint), style: const TextStyle(fontSize: 13)),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  DropdownMenuItem<String?> _dropItem(String? value, String label) {
    return DropdownMenuItem(
        value: value, child: Text(tr(label), style: const TextStyle(fontSize: 13)));
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
                Text(tr('Hiển thị ${startIndex + 1}-$endIndex / $totalCount'), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                Row(children: [
                  IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: page > 1 ? () => setState(() => _currentPage--) : null, visualDensity: VisualDensity.compact),
                  Text(tr('$page / $totalPages'), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
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
    final trialChip = _getTrialStatus(store);
    final agentName = store['agentName']?.toString() ?? '';
    final hasAgent = store['agentId'] != null &&
        store['agentId'].toString().isNotEmpty;

    return InkWell(
      onTap: () {
        if (adminUseMobileLayout(context)) {
          _showStoreMobileActions(store);
        } else {
          _showStoreDetail(store);
        }
      },
      onLongPress: adminUseMobileLayout(context)
          ? () => _showStoreDetail(store)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.store, color: HrmPageChrome.primaryNavy, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(name), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(tr([if (phone.isNotEmpty) phone, AdminHelpers.licenseTypeLabel(licenseType)].join(' \u00b7 ')),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(
                tr(hasAgent ? 'Đại lý: $agentName' : 'Đại lý: Chưa gán'),
                style: TextStyle(
                  color: hasAgent ? HrmPageChrome.chipMid : const Color(0xFFA1A1AA),
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (trialChip != null) ...[
                const SizedBox(height: 4),
                trialChip,
              ],
              const SizedBox(height: 2),
              Text(
                tr(AdminHelpers.storeRenewalLabel(
                    context, store['renewalCount'] as int? ?? 0)),
                style: TextStyle(
                  fontSize: 11,
                  color: (store['renewalCount'] as int? ?? 0) >=
                          AdminHelpers.maxStoreRenewals
                      ? AdminHelpers.warning
                      : const Color(0xFF71717A),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isLocked ? Colors.red.withValues(alpha: 0.1) : isActive ? Colors.green.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(tr(isLocked ? 'Kh\u00f3a' : isActive ? 'H\u0110' : 'T\u1eaft'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isLocked ? Colors.red : isActive ? Colors.green : Colors.grey)),
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
        title: Text(tr(name),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle:
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (store['phone'] != null)
            Text(tr(store['phone']),
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
                  AdminHelpers.licenseTypeChipLabel(
                      store['licenseType']?.toString()),
                  AdminHelpers.primaryDark),
            if (store['servicePackageName'] != null) ...[              const SizedBox(width: 6),
              AdminHelpers.statusChip(
                  store['servicePackageName'], HrmPageChrome.chipMid),
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
              tooltip: tr('Tài khoản cửa hàng'),
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
              AdminHelpers.infoRow(
                  Icons.storefront,
                  (store['agentName'] != null &&
                          store['agentName'].toString().isNotEmpty)
                      ? 'Đại lý: ${store['agentName']}'
                      : 'Đại lý: Chưa gán'),
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
                  AdminHelpers.storeRenewalLabel(context, store['renewalCount'] as int? ?? 0)),
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
                  if (context.systemAdminCanEdit) ...[
                    _actionButton(
                      icon: Icons.edit,
                      label: 'Đổi tên',
                      color: AdminHelpers.primary,
                      onTap: () => _editStoreName(store),
                    ),
                    if (!widget.agentMode) ...[
                      _actionButton(
                        icon: Icons.inventory_2_outlined,
                        label: 'Đổi gói',
                        color: HrmPageChrome.chipLight,
                        onTap: () => _showAssignPackage(store),
                      ),
                      _actionButton(
                        icon: Icons.handshake_outlined,
                        label: (store['agentId'] != null &&
                                store['agentId'].toString().isNotEmpty)
                            ? 'Đổi đại lý'
                            : 'Gán đại lý',
                        color: HrmPageChrome.chipMid,
                        onTap: () => _showAssignAgent(store),
                      ),
                    ],
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
                  _actionButton(
                    icon: Icons.info_outline,
                    label: 'Chi tiết',
                    color: AdminHelpers.info,
                    onTap: () => _showStoreDetail(store),
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
                  if (context.systemAdminCanEdit) ...[
                    _actionButton(
                      icon: Icons.vpn_key,
                      label: 'Kích hoạt Key',
                      color: AdminHelpers.success,
                      onTap: () => _showActivateKey(store),
                    ),
                    _actionButton(
                      icon: Icons.calendar_month,
                      label: _extendButtonLabel(context, store),
                      color: HrmPageChrome.chipMid,
                      onTap: () => _showExtendDays(store),
                    ),
                    if (!widget.agentMode)
                      _actionButton(
                        icon: Icons.restart_alt,
                        label: 'Khôi phục gốc',
                        color: AdminHelpers.warning,
                        onTap: () => _resetStoreData(store),
                      ),
                  ],
                  if (context.systemAdminCanDelete)
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
      label: Text(tr(label), style: const TextStyle(fontSize: 12)),
    );
  }

  Future<void> _showStoreMobileActions(Map<String, dynamic> store) async {
    final name = store['name'] ?? store['storeName'] ?? 'Cửa hàng';
    final isActive = store['isActive'] as bool? ?? true;
    final isLocked = store['isLocked'] as bool? ?? false;
    final hasAgent = store['agentId'] != null &&
        store['agentId'].toString().isNotEmpty;
    final canEdit = context.systemAdminCanEdit;
    final canDelete = context.systemAdminCanDelete;

    final actions = <AdminActionSheetItem>[];

    if (canEdit) {
      actions.addAll([
        AdminActionSheetItem(
          icon: Icons.calendar_month,
          label: _extendButtonLabel(context, store),
          color: HrmPageChrome.chipMid,
          onTap: () => _showExtendDays(store),
        ),
        AdminActionSheetItem(
          icon: Icons.vpn_key,
          label: 'Kích hoạt License Key',
          color: AdminHelpers.success,
          onTap: () => _showActivateKey(store),
        ),
      ]);
    }

    actions.addAll([
      AdminActionSheetItem(
        icon: Icons.info_outline,
        label: 'Xem chi tiết',
        onTap: () => _showStoreDetail(store),
      ),
      AdminActionSheetItem(
        icon: Icons.people,
        label: 'Tài khoản cửa hàng',
        onTap: () => _showStoreUsers(store),
      ),
    ]);

    if (canEdit) {
      if (!widget.agentMode) {
        actions.addAll([
          AdminActionSheetItem(
            icon: Icons.handshake_outlined,
            label: hasAgent ? 'Đổi đại lý' : 'Gán đại lý',
            color: HrmPageChrome.chipMid,
            onTap: () => _showAssignAgent(store),
          ),
          AdminActionSheetItem(
            icon: Icons.inventory_2_outlined,
            label: 'Đổi gói dịch vụ',
            onTap: () => _showAssignPackage(store),
          ),
        ]);
      }
      actions.addAll([
        AdminActionSheetItem(
          icon: Icons.edit,
          label: 'Đổi tên',
          onTap: () => _editStoreName(store),
        ),
        AdminActionSheetItem(
          icon: isActive ? Icons.pause : Icons.play_arrow,
          label: isActive ? 'Tắt cửa hàng' : 'Bật cửa hàng',
          onTap: () => _toggleStoreStatus(store),
        ),
        AdminActionSheetItem(
          icon: isLocked ? Icons.lock_open : Icons.lock,
          label: isLocked ? 'Mở khóa' : 'Khóa cửa hàng',
          color: isLocked ? AdminHelpers.success : AdminHelpers.danger,
          onTap: () => isLocked ? _unlockStore(store) : _lockStore(store),
        ),
      ]);
      if (!widget.agentMode) {
        actions.add(AdminActionSheetItem(
          icon: Icons.restart_alt,
          label: 'Khôi phục gốc',
          color: AdminHelpers.warning,
          onTap: () => _resetStoreData(store),
        ));
      }
    }

    if (canDelete) {
      actions.add(AdminActionSheetItem(
        icon: Icons.delete_forever,
        label: 'Xóa cửa hàng',
        destructive: true,
        onTap: () => _deleteStore(store),
      ));
    }

    await showAdminActionSheet(
      context,
      title: name.toString(),
      subtitle: hasAgent
          ? 'Đại lý: ${store['agentName']}'
          : 'Chưa gán đại lý',
      actions: actions,
    );
  }

  // ═══════════════════════ EDIT STORE NAME ═══════════════════════
  Future<void> _showAssignAgent(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    if (_agents.isEmpty) {
      await _loadAgents();
    }
    final currentAgentId = store['agentId']?.toString();
    String? selected = currentAgentId;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => ScrollableAlertDialog(
          title: Row(children: [
            Icon(Icons.handshake_outlined,
                color: HrmPageChrome.chipMid, size: 22),
            SizedBox(width: 8),
            Text(tr('Gán đại lý cho cửa hàng'), style: TextStyle(fontSize: 18)),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600
                ? MediaQuery.of(context).size.width - 32
                : 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('${tr('Cửa hàng: ')}${store['name'] ?? ''}'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selected,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Chọn đại lý'),
                    prefixIcon: Icon(Icons.storefront),
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem<String?>(
                        value: null, child: Text(tr('— Không gán / Gỡ đại lý —'))),
                    ..._agents.map((a) => DropdownMenuItem<String?>(
                          value: a['id']?.toString(),
                          child: Text(
                            tr('${a['name'] ?? a['code'] ?? 'Đại lý'} (${a['code'] ?? ''})'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                  ],
                  onChanged: (v) => setLocal(() => selected = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: () =>
                  Navigator.pop(ctx, {'agentId': selected}),
              icon: const Icon(Icons.save, size: 16),
              label: Text(tr('Lưu')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: HrmPageChrome.chipMid),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;
    final newAgentId = result['agentId'] as String?;
    if (newAgentId == currentAgentId) return;

    Map<String, dynamic> res;
    if (newAgentId == null || newAgentId.isEmpty) {
      // Gỡ đại lý hiện tại
      if (currentAgentId == null || currentAgentId.isEmpty) return;
      res = await _apiService.removeStoreFromAgent(currentAgentId, storeId);
    } else {
      res = await _apiService.assignStoreToAgent(newAgentId, storeId);
    }

    if (!mounted) return;
    final assignResult = AgentMutationResult.parseStoreAssignment(
      Map<String, dynamic>.from(res),
      expectedAgentId: newAgentId,
    );
    if (assignResult.ok) {
      AdminHelpers.showSuccess(context, 'Đã cập nhật đại lý cho cửa hàng');
      await loadData();
    } else {
      AdminHelpers.showError(
        context,
        assignResult.errorMessage ?? res['message']?.toString() ?? 'Không cập nhật được',
      );
      await loadData();
    }
  }

  Future<void> _editStoreName(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final currentName = store['name']?.toString() ?? '';
    final nameCtrl = TextEditingController(text: tr(currentName));
    final descCtrl =
        TextEditingController(text: tr(store['description']?.toString() ?? ''));
    final addressCtrl =
        TextEditingController(text: tr(store['address']?.toString() ?? ''));
    final phoneCtrl =
        TextEditingController(text: tr(store['phone']?.toString() ?? ''));
    var selectedProvince = store['province']?.toString();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
        title: Row(children: [
          Icon(Icons.edit, color: AdminHelpers.primary, size: 22),
          SizedBox(width: 8),
          Text(tr('Chỉnh sửa cửa hàng'), style: TextStyle(fontSize: 18)),
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
              DropdownButtonFormField<String>(
                initialValue: selectedProvince != null &&
                        kVietnamProvinces.contains(selectedProvince)
                    ? selectedProvince
                    : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Tỉnh / thành phố'),
                  prefixIcon: const Icon(Icons.location_city_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                items: kVietnamProvinces
                    .map((p) => DropdownMenuItem(value: p, child: Text(tr(p))))
                    .toList(),
                onChanged: (v) => setDialogState(() => selectedProvince = v),
              ),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  addressCtrl, 'Địa chỉ chi tiết', Icons.location_on),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  phoneCtrl, 'Số điện thoại', Icons.phone),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.save, size: 16),
            label: Text(tr('Lưu')),
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primary),
          ),
        ],
      ),
      ),
    );

    if (result != true || !mounted) return;

    final res = widget.agentMode
        ? await _apiService.agentUpdateStore(
            storeId,
            name: nameCtrl.text.trim(),
            description: descCtrl.text.trim(),
            address: addressCtrl.text.trim(),
            province: selectedProvince?.trim(),
            phone: phoneCtrl.text.trim(),
          )
        : await _apiService.updateStore(
      storeId,
      name: nameCtrl.text.trim(),
      description: descCtrl.text.trim(),
      address: addressCtrl.text.trim(),
      province: selectedProvince?.trim(),
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
    final results = await Future.wait([
      widget.agentMode
          ? _apiService.getAgentStoreFullDetail(storeId)
          : _apiService.getStoreFullDetail(storeId),
      widget.agentMode
          ? _apiService.getAgentPosOverview(storeId: storeId)
          : _apiService.getSystemPosOverview(storeId: storeId),
    ]);
    final res = results[0];
    final posRes = results[1];

    if (!mounted) return;
    if (res['isSuccess'] != true) {
      AdminHelpers.showApiError(context, res);
      return;
    }

    final d = res['data'] as Map<String, dynamic>? ?? {};
    final pos = posRes['isSuccess'] == true && posRes['data'] is Map
        ? Map<String, dynamic>.from(posRes['data'] as Map)
        : null;
    final isMobile = MediaQuery.of(context).size.width < 600;

    final titleRow = Row(children: [
      const Icon(Icons.store, color: AdminHelpers.primary, size: 22),
      const SizedBox(width: 8),
      Expanded(
          child: Text(tr(d['name'] ?? 'Chi tiết'),
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
          _detailRow('Tỉnh / thành', d['province']),
          _detailRow('Địa chỉ', d['address']),
          _detailRow('Điện thoại', d['phone']),
          _detailRow('Email chủ sở hữu', d['ownerEmail']),
          _detailRow('Chủ sở hữu', d['ownerName']),
        ]),
        _detailSection('Đại lý', [
          _detailRow(
            'Quản lý bởi',
            (store['agentName'] != null &&
                    store['agentName'].toString().isNotEmpty)
                ? store['agentName']
                : 'Chưa gán',
          ),
          if (store['agentEmail'] != null &&
              store['agentEmail'].toString().isNotEmpty)
            _detailRow('Email đại lý', store['agentEmail']),
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
          _detailRow('Loại license',
              AdminHelpers.licenseTypeLabel(d['licenseType']?.toString())),
          _detailRow('License key', d['licenseKey']),
          _detailRow('Hết hạn',
              AdminHelpers.formatDate(d['expiryDate'])),
          _detailRow(
              'Số lần gia hạn',
              AdminHelpers.storeRenewalLabel(
                  context, d['renewalCount'] as int? ?? store['renewalCount'] as int? ?? 0)),
          _detailRow('Ngày bắt đầu dùng thử',
              AdminHelpers.formatDate(d['trialStartDate'])),
          _detailRow('Số ngày dùng thử',
              d['trialDays']?.toString()),
          _detailRow(
              'Max Users', d['maxUsers']?.toString()),
          _detailRow(
              'Máy chấm công', d['maxDevices']?.toString()),
        ]),
        _detailSection('Thống kê', [
          _detailRow(
              'Tổng Users', d['totalUsers']?.toString()),
          _detailRow(
              'Tổng Devices', d['totalDevices']?.toString()),
        ]),
        if (pos != null)
          _detailSection('POS cửa hàng', [
            _detailRow('Doanh thu hôm nay', '${pos['todayRevenue'] ?? 0} ₫'),
            _detailRow('Đơn hôm nay', '${pos['todayOrders'] ?? 0}'),
            _detailRow('Đơn QR hôm nay', '${pos['todayQrOrders'] ?? 0}'),
            _detailRow('Doanh thu kỳ (hôm nay)', '${pos['periodRevenue'] ?? 0} ₫'),
            _detailRow('Print Agent online',
                '${pos['printAgentsOnline'] ?? 0}/${pos['printAgentsTotal'] ?? 0}'),
            _detailRow('Máy in lỗi',
                '${pos['printersUnhealthy'] ?? 0}/${pos['printersTotal'] ?? 0}'),
            _detailRow('Job in lỗi 24h', '${pos['printJobsFailed24h'] ?? 0}'),
            _detailRow('Phiếu bếp chờ', '${pos['kitchenJobsQueued'] ?? 0}'),
            _detailRow('Đơn nháp / bàn mở', '${pos['openDraftOrders'] ?? 0}'),
            _detailRow('Ca thu ngân mở', '${pos['openCashierShifts'] ?? 0}'),
            _detailRow('Hết hàng / dưới ĐM',
                '${pos['outOfStockSkus'] ?? 0} / ${pos['belowMinSkus'] ?? 0}'),
            _detailRow('HĐĐT lỗi', '${pos['einvoiceFailed'] ?? 0}'),
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
                title: Text(tr(d['name'] ?? 'Chi tiết'), overflow: TextOverflow.ellipsis),
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
              bottomNavigationBar: context.systemAdminCanEdit
                  ? SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _showExtendDays(store);
                                },
                                icon: const Icon(Icons.calendar_month, size: 18),
                                label: Text(
                                  tr(_extendButtonLabel(context, store)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: HrmPageChrome.chipMid,
                                  minimumSize: const Size.fromHeight(44),
                                ),
                              ),
                            ),
                            if (!widget.agentMode) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _showAssignAgent(store);
                                  },
                                  icon: const Icon(Icons.handshake_outlined,
                                      size: 18),
                                  label: Text(
                                    tr((store['agentId'] != null &&
                                            store['agentId']
                                                .toString()
                                                .isNotEmpty)
                                        ? 'Đổi đại lý'
                                        : 'Gán đại lý'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: HrmPageChrome.chipMid,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => ScrollableAlertDialog(
          title: titleRow,
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(child: contentBody),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Đóng'))),
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
        Text(tr(title),
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
              child: Text(tr(label),
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[600]))),
          Expanded(
              child: Text(tr(value),
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

    final res = widget.agentMode
        ? await _apiService.getAgentAdminUsers(storeId: storeId)
        : await _apiService.getSystemUsers(storeId: storeId);
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
      builder: (ctx) => ScrollableAlertDialog(
        title: Row(children: [
          Icon(Icons.warning_amber, color: AdminHelpers.warning, size: 24),
          SizedBox(width: 8),
          Text(tr('Khôi phục cài đặt gốc')),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Bạn sắp khôi phục cài đặt gốc cho cửa hàng "$name".')),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminHelpers.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AdminHelpers.warning.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Thao tác này sẽ xóa:'),
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text(tr('• Toàn bộ dữ liệu chấm công')),
                    Text(tr('• Toàn bộ thiết bị và cấu hình')),
                    Text(tr('• Toàn bộ nhân viên')),
                    Text(tr('• Toàn bộ lệnh thiết bị')),
                    SizedBox(height: 8),
                    Text(tr('Tài khoản người dùng sẽ được giữ lại.'),
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
              child: Text(tr('Hủy'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restart_alt, size: 16),
            label: Text(tr('Xác nhận khôi phục')),
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
      builder: (ctx) => ScrollableAlertDialog(
        title: Row(children: [
          Icon(Icons.delete_forever, color: AdminHelpers.danger, size: 24),
          SizedBox(width: 8),
          Text(tr('Xóa hoàn toàn cửa hàng')),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Bạn sắp XÓA HOÀN TOÀN cửa hàng "$name".')),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AdminHelpers.danger.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AdminHelpers.danger.withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('⚠ CẢNH BÁO: Không thể hoàn tác!'),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AdminHelpers.danger)),
                    SizedBox(height: 4),
                    Text(tr('Cửa hàng sẽ bị xóa khỏi danh sách.')),
                    Text(tr('Tất cả dữ liệu liên quan sẽ bị xóa:')),
                    SizedBox(height: 4),
                    Text(tr('• Toàn bộ tài khoản người dùng')),
                    Text(tr('• Toàn bộ dữ liệu chấm công')),
                    Text(tr('• Toàn bộ nhân viên & phòng ban')),
                    Text(tr('• Toàn bộ thiết bị & cấu hình')),
                    Text(tr('• Toàn bộ lương, phụ cấp, KPI')),
                    Text(tr('• Và tất cả dữ liệu khác')),
                    SizedBox(height: 8),
                    Text(tr('Tên cửa hàng có thể được đăng ký lại.'),
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
              child: Text(tr('Hủy'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: Text(tr('Xóa hoàn toàn')),
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
    if (widget.agentMode) {
      await _apiService.agentToggleStoreStatus(store['id']?.toString() ?? '');
    } else {
      await _apiService.toggleStoreStatus(store['id']?.toString() ?? '');
    }
    loadData();
  }

  Future<void> _lockStore(Map<String, dynamic> store) async {
    final reason = await AdminHelpers.showInputDialog(
        context, 'Khóa cửa hàng', 'Lý do khóa (tùy chọn)');
    if (reason == null) return;
    if (widget.agentMode) {
      await _apiService.agentLockStore(
          store['id']?.toString() ?? '', reason.isNotEmpty ? reason : null);
    } else {
      await _apiService.lockStore(
          store['id']?.toString() ?? '', reason.isNotEmpty ? reason : null);
    }
    loadData();
  }

  Future<void> _unlockStore(Map<String, dynamic> store) async {
    if (widget.agentMode) {
      await _apiService.agentUnlockStore(store['id']?.toString() ?? '');
    } else {
      await _apiService.unlockStore(store['id']?.toString() ?? '');
    }
    loadData();
  }

  // ═══════════════════════ TRIAL STATUS HELPER ═══════════════════════
  Widget? _getTrialStatus(Map<String, dynamic> store) {
    final remaining = _getRemainingDays(store);
    final isTrial = _isTrial(store);
    if (remaining == null) {
      return isTrial
          ? AdminHelpers.statusChip('Dùng thử', HrmPageChrome.chipMid)
          : null;
    }

    if (remaining <= 0) {
      return AdminHelpers.statusChip(
          isTrial ? 'Hết hạn dùng thử' : 'Hết hạn', AdminHelpers.danger);
    }
    final prefix = isTrial ? 'Dùng thử · ' : '';
    final color = remaining > 30
        ? (isTrial ? HrmPageChrome.chipMid : AdminHelpers.success)
        : AdminHelpers.warning;
    return AdminHelpers.statusChip('${prefix}Còn $remaining ngày', color);
  }

  // ═══════════════════════ EXTEND DAYS ═══════════════════════
  String _extendButtonLabel(BuildContext context, Map<String, dynamic> store) {
    final renewalCount = store['renewalCount'] as int? ?? 0;
    if (context.canBypassStoreRenewalLimit &&
        renewalCount >= AdminHelpers.maxStoreRenewals) {
      return 'Gia hạn ($renewalCount)';
    }
    return 'Gia hạn ($renewalCount/${AdminHelpers.maxStoreRenewals})';
  }

  Future<void> _showExtendDays(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final name = store['name'] ?? 'N/A';
    final renewalCount = store['renewalCount'] as int? ?? 0;
    final canBypass = context.canBypassStoreRenewalLimit;
    final allowCustomDays = canBypass && !widget.agentMode;

    int agentRenewalBalance = 0;
    if (widget.agentMode) {
      try {
        final prof = await _apiService.getAgentProfile();
        if (prof['isSuccess'] == true && prof['data'] is Map) {
          agentRenewalBalance =
              (prof['data']['renewalDayBalance'] as num?)?.toInt() ?? 0;
        }
      } catch (e) {
        debugPrint('Load agent renewal balance: $e');
      }
      if (!mounted) return;
      if (agentRenewalBalance <= 0) {
        AdminHelpers.showError(context,
            'Quỹ gia hạn đã hết. Vui lòng liên hệ Super Admin để được cấp thêm ngày.');
        return;
      }
    }

    if (renewalCount >= AdminHelpers.maxStoreRenewals && !canBypass) {
      AdminHelpers.showError(context,
          'Cửa hàng "$name" đã gia hạn tối đa ${AdminHelpers.maxStoreRenewals} lần. Vui lòng kích hoạt key mới.');
      return;
    }

    final daysCtrl = TextEditingController(text: tr('30'));
    var selectedPreset = 30;
    if (widget.agentMode && agentRenewalBalance > 0) {
      final affordable = kStoreExtendDayPresets
          .where((d) => d <= agentRenewalBalance)
          .toList();
      if (affordable.isNotEmpty) {
        selectedPreset = affordable.last;
        daysCtrl.text = selectedPreset.toString();
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          title: Row(children: [
            const Icon(Icons.calendar_month,
                color: HrmPageChrome.chipMid, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(tr('Gia hạn — $name'),
                    style: const TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600
                ? MediaQuery.of(context).size.width - 32
                : 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.agentMode) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: HrmPageChrome.chipMid.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      const Icon(Icons.account_balance_wallet_outlined,
                          color: HrmPageChrome.chipMid, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tr('Quỹ gia hạn còn: $agentRenewalBalance ngày'),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                  ),
                ],
                Text(
                  tr(canBypass && renewalCount >= AdminHelpers.maxStoreRenewals
                      ? 'Đã gia hạn $renewalCount lần — Super Admin toàn quyền có thể gia hạn thêm.'
                      : allowCustomDays
                          ? 'Đã gia hạn $renewalCount/${AdminHelpers.maxStoreRenewals} lần. Chọn hoặc nhập số ngày:'
                          : widget.agentMode
                              ? 'Đã gia hạn $renewalCount/${AdminHelpers.maxStoreRenewals} lần. Đại lý chỉ chọn 7, 14, 21 hoặc 30 ngày:'
                              : 'Đã gia hạn $renewalCount/${AdminHelpers.maxStoreRenewals} lần. Chọn 7, 14, 21 hoặc 30 ngày:'),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: kStoreExtendDayPresets.map((days) {
                    final selected = selectedPreset == days;
                    final disabled = widget.agentMode &&
                        agentRenewalBalance > 0 &&
                        days > agentRenewalBalance;
                    return ChoiceChip(
                      label: Text(tr('$days ngày')),
                      selected: selected,
                      onSelected: disabled
                          ? null
                          : (_) {
                        setDialogState(() {
                          selectedPreset = days;
                          daysCtrl.text = days.toString();
                        });
                      },
                      selectedColor: HrmPageChrome.chipMid.withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: selected
                            ? HrmPageChrome.chipMid
                            : Colors.black87,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    );
                  }).toList(),
                ),
                if (allowCustomDays) ...[
                  const SizedBox(height: 12),
                  AdminHelpers.dialogField(
                      daysCtrl, 'Số ngày (tùy chỉnh)', Icons.timer),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 16),
              label: Text(tr('Gia hạn')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: HrmPageChrome.chipMid),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) {
      daysCtrl.dispose();
      return;
    }

    final days = allowCustomDays
        ? int.tryParse(daysCtrl.text.trim())
        : selectedPreset;
    daysCtrl.dispose();

    if (days == null || days <= 0) {
      AdminHelpers.showError(context, 'Số ngày không hợp lệ');
      return;
    }

    if (!allowCustomDays && !kStoreExtendDayPresets.contains(days)) {
      AdminHelpers.showError(context,
          'Chỉ được gia hạn 7, 14, 21 hoặc 30 ngày. Super Admin toàn quyền mới nhập tùy chỉnh.');
      return;
    }

    if (widget.agentMode && days > agentRenewalBalance) {
      AdminHelpers.showError(context,
          'Quỹ gia hạn không đủ. Còn $agentRenewalBalance ngày, cần $days ngày.');
      return;
    }

    final res = widget.agentMode
        ? await _apiService.agentExtendStoreDays(storeId, days)
        : await _apiService.extendStoreDays(storeId, days);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã gia hạn thêm $days ngày cho "$name"');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ ĐỔI GÓI DỊCH VỤ ═══════════════════════
  Future<void> _showAssignPackage(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final name = store['name'] ?? 'N/A';
    final currentPackageId = store['servicePackageId']?.toString();

    // Load danh sách gói dịch vụ
    final res = await _apiService.getServicePackages();
    if (!mounted) return;
    if (res['isSuccess'] != true) {
      AdminHelpers.showError(context, res['message'] ?? 'Không tải được danh sách gói');
      return;
    }
    final packages = (res['data'] as List<dynamic>? ?? []);
    if (packages.isEmpty) {
      AdminHelpers.showError(context, 'Chưa có gói dịch vụ nào. Vui lòng tạo gói trước.');
      return;
    }

    String? selectedId = currentPackageId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => ScrollableAlertDialog(
          title: Row(children: [
            Icon(Icons.inventory_2_outlined, color: HrmPageChrome.chipLight, size: 22),
            SizedBox(width: 8),
            Text(tr('Đổi gói dịch vụ'), style: TextStyle(fontSize: 18)),
          ]),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr('Cửa hàng: $name'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (store['servicePackageName'] != null) ...
                  [const SizedBox(height: 4),
                  Text(tr('${tr('Gói hiện tại: ')}${store['servicePackageName']}'),
                      style: const TextStyle(color: Colors.grey, fontSize: 13))],
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Chọn gói dịch vụ'),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: packages.map((p) {
                    final pid = p['id']?.toString() ?? '';
                    final pname = p['name']?.toString() ?? pid;
                    final maxU = p['maxUsers'];
                    final maxD = p['maxDevices'];
                    final dur = p['defaultDurationDays'];
                    final public = p is! Map || p['isPublic'] != false;
                    return DropdownMenuItem<String>(
                      value: pid,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(tr(pname), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            tr('${public ? 'Công khai' : 'Nội bộ'} · Users: $maxU | Devices: $maxD | ${dur ?? '?'} ngày'),
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setDlgState(() => selectedId = v),
                ),
                const SizedBox(height: 8),
                Text(tr('⚠ Nếu store đang hết hạn, sẽ được gia hạn theo số ngày mặc định của gói mới.'),
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: selectedId == null ? null : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.check, size: 16),
              label: Text(tr('Xác nhận')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: HrmPageChrome.chipLight),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || selectedId == null || !mounted) return;

    final result = await _apiService.assignPackageToStore(storeId, selectedId!);
    if (!mounted) return;
    if (result['isSuccess'] == true) {
      final pkgName = packages
          .firstWhere((p) => p['id']?.toString() == selectedId,
              orElse: () => {})
          ['name']
          ?.toString() ?? selectedId;
      AdminHelpers.showSuccess(
          context, 'Đã đổi gói "$pkgName" cho cửa hàng "$name"');
      loadData();
    } else {
      AdminHelpers.showApiError(context, result);
    }
  }

  // ═══════════════════════ KÍCH HOẠT KEY (NHIỀU KEY) ═══════════════════════
  Future<List<Map<String, dynamic>>> _loadActivatableLicenseKeys(
      String storeId) async {
    try {
      final res = widget.agentMode
          ? await _apiService.getAgentActivatableLicensesForStore(storeId)
          : await _apiService.getActivatableLicensesForStore(storeId);
      if (res['isSuccess'] == true && res['data'] is List) {
        return (res['data'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (e) {
      debugPrint('Load activatable license keys failed: $e');
    }
    return [];
  }

  String _licenseKeyQuickSubtitle(Map<String, dynamic> key) {
    final pkg = key['servicePackageName']?.toString();
    final type = AdminHelpers.licenseTypeLabel(key['licenseType']?.toString());
    final days = key['durationDays'];
    final agentName = key['agentName']?.toString();
    final parts = <String>[
      if (pkg != null && pkg.isNotEmpty) pkg else type,
      if (days != null) '$days ngày',
      if (agentName == null || agentName.isEmpty) 'Key chung' else agentName,
    ];
    return parts.join(' · ');
  }

  String _activatableKeysHint(Map<String, dynamic> store) {
    final agentName = store['agentName']?.toString();
    if (agentName != null && agentName.isNotEmpty) {
      return 'Chỉ key của đại lý "$agentName" hoặc key chung (chưa gán đại lý).';
    }
    return 'Cửa hàng chưa gán đại lý — chỉ dùng key chung (chưa cấp cho đại lý nào).';
  }

  Future<void> _showActivateKey(Map<String, dynamic> store) async {
    final storeId = store['id']?.toString() ?? '';
    final name = store['name'] ?? 'N/A';

    final availableKeys = await _loadActivatableLicenseKeys(storeId);
    if (!mounted) return;

    final keyControllers = <TextEditingController>[TextEditingController()];
    final selectedKeys = <String>{};
    Map<String, dynamic>? previewData;
    bool isPreviewing = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => ScrollableAlertDialog(
          title: Row(children: [
            const Icon(Icons.vpn_key, color: AdminHelpers.success, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(tr('Kích hoạt Key — $name'),
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
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          color: AdminHelpers.info, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tr('${_activatableKeysHint(store)}\n'
                          'Chọn tối đa 4 key cùng gói dịch vụ.'),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ]),
                  ),
                  if (availableKeys.isNotEmpty) ...[
                    Text(tr('Key khả dụng (${availableKeys.length})'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: availableKeys.length > 4 ? 220 : 280,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: availableKeys.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final item = availableKeys[i];
                          final code = item['key']?.toString() ?? '';
                          if (code.isEmpty) return const SizedBox.shrink();
                          final checked = selectedKeys.contains(code);
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              setDlgState(() {
                                previewData = null;
                                if (v == true) {
                                  if (selectedKeys.length >= 4 &&
                                      !selectedKeys.contains(code)) {
                                    NotificationOverlayManager().showWarning(
                                      title: 'Giới hạn',
                                      message: tr('Chỉ chọn tối đa 4 key'),
                                    );
                                    return;
                                  }
                                  selectedKeys.add(code);
                                } else {
                                  selectedKeys.remove(code);
                                }
                              });
                            },
                            title: Text(
                              tr(code),
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              tr(_licenseKeyQuickSubtitle(item)),
                              style: const TextStyle(fontSize: 11),
                            ),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          );
                        },
                      ),
                    ),
                    if (selectedKeys.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: selectedKeys
                            .map((k) => InputChip(
                                  label: Text(tr(k),
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11)),
                                  onDeleted: () => setDlgState(() {
                                    selectedKeys.remove(k);
                                    previewData = null;
                                  }),
                                ))
                            .toList(),
                      ),
                    ],
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Expanded(child: Divider()),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text(tr('hoặc nhập key'),
                              style: TextStyle(
                                  fontSize: 12, color: Color(0xFF71717A))),
                        ),
                        Expanded(child: Divider()),
                      ]),
                    ),
                  ] else ...[
                    Text(tr('Không có key sẵn trong kho — nhập key thủ công.'),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                  ],
                  ...List.generate(keyControllers.length, (i) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: keyControllers[i],
                          decoration: InputDecoration(
                            labelText: tr('Key ${i + 1}'),
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
                      label: Text(tr('Thêm key (${keyControllers.length}/4)')),
                    ),
                  const SizedBox(height: 8),
                  if (!widget.agentMode) ...[
                    // Preview button (SuperAdmin bulk promotion preview)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: isPreviewing ? null : () async {
                          final manualKeys = keyControllers
                              .map((c) => c.text.trim())
                              .where((k) => k.isNotEmpty);
                          final keys = {
                            ...selectedKeys,
                            ...manualKeys,
                          }.toList();
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
                        label: Text(tr('Xem trước')),
                      ),
                    ),
                  ],
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
                          Text(tr('Kết quả dự kiến:'), style: TextStyle(fontWeight: FontWeight.bold, color: AdminHelpers.success)),
                          const SizedBox(height: 6),
                          Text(tr('${tr('• Số key hợp lệ: ')}${previewData!['keyCount']}')),
                          Text(tr('${tr('• Tổng ngày từ key: ')}${previewData!['totalDays']} ngày')),
                          if ((previewData!['bonusDays'] as int? ?? 0) > 0) ...[
                            Text(tr('${tr('• 🎁 Ngày tặng thêm: ')}${previewData!['bonusDays']} ngày'),
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                            if (previewData!['promotionName'] != null)
                              Text(tr('  (CT: ${previewData!['promotionName']})'),
                                  style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic)),
                          ],
                          const Divider(),
                          Text(tr('${tr('Tổng cộng: ')}${previewData!['grandTotalDays']} ngày'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          if (previewData!['newExpiryDate'] != null)
                            Text(tr('${tr('Hạn mới: ')}${_fmtDate(previewData!['newExpiryDate'])}'),
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
                child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: () async {
                final manualKeys = keyControllers
                    .map((c) => c.text.trim())
                    .where((k) => k.isNotEmpty);
                final keys = {
                  ...selectedKeys,
                  ...manualKeys,
                }.toList();
                if (keys.isEmpty) {
                  NotificationOverlayManager().showWarning(title: 'Thiếu thông tin', message: tr('Vui lòng chọn hoặc nhập ít nhất 1 key'));
                  return;
                }
                if (keys.length > 4) {
                  NotificationOverlayManager().showWarning(
                      title: 'Giới hạn', message: tr('Chỉ kích hoạt tối đa 4 key'));
                  return;
                }
                Navigator.pop(ctx);
                if (widget.agentMode) {
                  var ok = 0;
                  String? lastError;
                  for (final key in keys) {
                    final res = await _apiService.agentActivateLicenseForStore(
                        storeId, {'licenseKey': key});
                    if (res['isSuccess'] == true) {
                      ok++;
                    } else {
                      lastError = res['message']?.toString();
                      break;
                    }
                  }
                  if (!mounted) return;
                  if (ok == keys.length) {
                    AdminHelpers.showSuccess(context,
                        'Đã kích hoạt $ok key cho "$name".');
                    loadData();
                  } else {
                    AdminHelpers.showError(context,
                        lastError ?? 'Không kích hoạt được key');
                  }
                } else {
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
                }
              },
              icon: const Icon(Icons.check, size: 16),
              label: Text(tr('Kích hoạt')),
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
      final dt = DateTime.parse(d.toString()).toLocal();
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return d.toString();
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
  final Map<String, bool> _passwordRevealed = {};
  final Map<String, String> _newPasswords = {};

  String? _visiblePassword(String userId, Map<String, dynamic> user) {
    final local = _newPasswords[userId];
    if (local != null && local.isNotEmpty) return local;
    final fromApi = user['plainTextPassword']?.toString();
    if (fromApi != null && fromApi.isNotEmpty) return fromApi;
    return null;
  }

  @override
  void initState() {
    super.initState();
    _users = List.from(widget.users);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollableAlertDialog(
      title: Row(children: [
        const Icon(Icons.people, color: AdminHelpers.info, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(tr('Tài khoản — ${widget.storeName}'),
              style: const TextStyle(fontSize: 17)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: AdminHelpers.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(tr('${_users.length} tài khoản'),
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
            child: Text(tr('Đóng'))),
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
    final visiblePassword = _visiblePassword(userId, user);

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
                    Text(tr(fullName.isNotEmpty ? fullName[0].toUpperCase() : '?'),
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
                      Text(tr(fullName.isNotEmpty ? fullName : email),
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
                          child: Text(tr(email),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600])),
                        ),
                        // Copy email
                        InkWell(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: tr(email)));
                            AdminHelpers.showSuccess(context, 'Đã copy email');
                          },
                          child: Icon(Icons.copy,
                              size: 14, color: Colors.grey[400]),
                        ),
                      ],
                    ),
                    if (lastLogin != null)
                      Text(tr('Đăng nhập cuối: ${AdminHelpers.formatDateTime(lastLogin)}'),
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
                        child: visiblePassword != null
                            ? (_passwordRevealed[userId] == true
                                ? SelectableText(
                                    tr(visiblePassword),
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600))
                                : Text(tr('••••••••'),
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[500])))
                            : Text(tr('Chưa lưu (đặt lại MK để xem)'),
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[500])),
                      ),
                      if (visiblePassword != null) ...[
                        InkWell(
                          onTap: () => setState(() {
                            _passwordRevealed[userId] =
                                !(_passwordRevealed[userId] ?? false);
                          }),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              _passwordRevealed[userId] == true
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () {
                            Clipboard.setData(
                                ClipboardData(text: tr(visiblePassword)));
                            AdminHelpers.showSuccess(
                                context, 'Đã copy mật khẩu');
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.copy,
                                size: 14, color: AdminHelpers.primary),
                          ),
                        ),
                      ],
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () => _resetPassword(userId, email),
                        icon: const Icon(Icons.refresh,
                            size: 14, color: AdminHelpers.warning),
                        label: Text(tr('Đặt lại MK'),
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
    final newPass = await AdminHelpers.showPasswordInputDialog(
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
        _passwordRevealed[userId] = true;
        final idx = _users.indexWhere((u) => u['id']?.toString() == userId);
        if (idx >= 0) {
          _users[idx] = Map<String, dynamic>.from(_users[idx])
            ..['plainTextPassword'] = newPass;
        }
      });
      AdminHelpers.showSuccess(context, 'Đã đặt lại mật khẩu cho $email');
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }
}
