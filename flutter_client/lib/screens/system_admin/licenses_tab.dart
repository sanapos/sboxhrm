import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/api_service.dart';
import '../../utils/responsive_helper.dart';
import 'system_admin_helpers.dart';

class LicensesTab extends StatefulWidget {
  const LicensesTab({super.key});

  @override
  State<LicensesTab> createState() => LicensesTabState();
}

class LicensesTabState extends State<LicensesTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _licenses = [];
  List<Map<String, dynamic>> _filteredLicenses = [];
  List<Map<String, dynamic>> _servicePackages = [];
  List<Map<String, dynamic>> _agents = [];
  bool _isLoading = false;

  final _searchCtrl = TextEditingController();
  String? _statusFilter;
  String? _typeFilter;
  String? _packageFilter;
  String? _assignFilter;
  String? _agentFilter;
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

  List<Map<String, dynamic>> get licenses => _licenses;

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getLicenseKeys(pageSize: 500),
        _apiService.getServicePackages(),
        _apiService.getSystemAgents(pageSize: 200),
      ]);
      if (!mounted) return;
      final licRes = results[0];
      final pkgRes = results[1];
      final agentRes = results[2];
      if (licRes['isSuccess'] == true) {
        _licenses = AdminHelpers.extractList(licRes['data']);
      }
      if (pkgRes['isSuccess'] == true) {
        _servicePackages = AdminHelpers.extractList(pkgRes['data']);
      }
      if (agentRes['isSuccess'] == true) {
        _agents = AdminHelpers.extractList(agentRes['data']);
      }
      _applyFilters();
    } catch (e) {
      debugPrint('LicensesTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  String _getStatus(Map<String, dynamic> l) {
    if (l['isActive'] == false) return 'revoked';
    if (l['isUsed'] == true) return 'activated';
    return 'available';
  }

  void _applyFilters() {
    final query = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredLicenses = _licenses.where((l) {
        final key = (l['key'] ?? '').toString().toLowerCase();
        final store = (l['storeName'] ?? '').toString().toLowerCase();
        final agent = (l['agentName'] ?? '').toString().toLowerCase();
        final pkg = (l['servicePackageName'] ?? '').toString().toLowerCase();
        final notes = (l['notes'] ?? '').toString().toLowerCase();
        final matchSearch = query.isEmpty ||
            key.contains(query) ||
            store.contains(query) ||
            agent.contains(query) ||
            pkg.contains(query) ||
            notes.contains(query);

        final status = _getStatus(l);
        final matchStatus =
            _statusFilter == null || status == _statusFilter;

        final type = (l['licenseType'] ?? '').toString();
        final matchType = _typeFilter == null || type == _typeFilter;

        final spId = (l['servicePackageId'] ?? '').toString();
        final matchPkg = _packageFilter == null || spId == _packageFilter;

        bool matchAssign = true;
        if (_assignFilter == 'unassigned') {
          matchAssign = l['agentId'] == null && l['storeId'] == null;
        } else if (_assignFilter == 'assigned_agent') {
          matchAssign = l['agentId'] != null;
        } else if (_assignFilter == 'assigned_store') {
          matchAssign = l['storeId'] != null;
        }

        final matchAgent = _agentFilter == null ||
            (l['agentId'] ?? '').toString() == _agentFilter;

        return matchSearch && matchStatus && matchType && matchPkg && matchAssign && matchAgent;
      }).toList();
      _currentPage = 1;
    });
  }

  bool _canDelete(Map<String, dynamic> l) {
    return l['isUsed'] != true && l['agentId'] == null;
  }

  int _countByStatus(String status) =>
      _licenses.where((l) => _getStatus(l) == status).length;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      children: [
        _buildToolbar(),
        _buildCountBadges(),
        Expanded(
          child: _filteredLicenses.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.vpn_key,
                  _searchCtrl.text.isNotEmpty ||
                          _statusFilter != null ||
                          _typeFilter != null ||
                          _packageFilter != null ||
                          _assignFilter != null ||
                          _agentFilter != null
                      ? 'Không tìm thấy license phù hợp'
                      : 'Chưa có license key')
              : _buildPaginatedList(),
        ),
      ],
    );
  }

  Widget _buildToolbar() {
    final types = _licenses
        .map((l) => (l['licenseType'] ?? '').toString())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
      child: Column(children: [
        AdminHelpers.searchBar(
          controller: _searchCtrl,
          hint: 'Tìm key, cửa hàng, đại lý, gói...',
          onChanged: _applyFilters,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildDropdown<String?>(
              value: _statusFilter,
              hint: 'Trạng thái',
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả')),
                DropdownMenuItem(
                    value: 'available',
                    child: Text('Chưa dùng (${_countByStatus('available')})')),
                DropdownMenuItem(
                    value: 'activated',
                    child: Text('Đã kích hoạt (${_countByStatus('activated')})')),
                DropdownMenuItem(
                    value: 'revoked',
                    child: Text('Thu hồi (${_countByStatus('revoked')})')),
              ],
              onChanged: (v) {
                _statusFilter = v;
                _applyFilters();
              },
            ),
            _buildDropdown<String?>(
              value: _typeFilter,
              hint: 'Loại gói',
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả')),
                ...types.map((t) => DropdownMenuItem(value: t, child: Text(AdminHelpers.licenseTypeLabel(t)))),
              ],
              onChanged: (v) {
                _typeFilter = v;
                _applyFilters();
              },
            ),
            ElevatedButton.icon(
              onPressed: _showCreateLicenseDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tạo key'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.primaryDark,
                  foregroundColor: Colors.white),
            ),
            OutlinedButton.icon(
              onPressed: _showBatchCreateDialog,
              icon: const Icon(Icons.library_add, size: 18),
              label: const Text('Tạo hàng loạt'),
            ),
            OutlinedButton.icon(
              onPressed: _showBatchAssignAgentDialog,
              icon: const Icon(Icons.assignment_ind, size: 18),
              label: const Text('Cấp cho đại lý'),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AdminHelpers.info),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildDropdown<String?>(
              value: _packageFilter,
              hint: 'Gói dịch vụ',
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả gói')),
                ..._servicePackages.map((p) => DropdownMenuItem(
                    value: p['id']?.toString(),
                    child: Text(p['name']?.toString() ?? ''))),
              ],
              onChanged: (v) {
                _packageFilter = v;
                _applyFilters();
              },
            ),
            _buildDropdown<String?>(
              value: _assignFilter,
              hint: 'Phân bổ',
              items: const [
                DropdownMenuItem(value: null, child: Text('Tất cả')),
                DropdownMenuItem(
                    value: 'unassigned', child: Text('Chưa gán')),
                DropdownMenuItem(
                    value: 'assigned_agent', child: Text('Đã gán đại lý')),
                DropdownMenuItem(
                    value: 'assigned_store', child: Text('Đã gán cửa hàng')),
              ],
              onChanged: (v) {
                _assignFilter = v;
                _applyFilters();
              },
            ),
            _buildDropdown<String?>(
              value: _agentFilter,
              hint: 'Đại lý',
              items: [
                const DropdownMenuItem(value: null, child: Text('Tất cả đại lý')),
                ..._agents.map((a) => DropdownMenuItem(
                    value: a['id']?.toString(),
                    child: Text(a['fullName']?.toString() ?? a['userName']?.toString() ?? ''))),
              ],
              onChanged: (v) {
                _agentFilter = v;
                _applyFilters();
              },
            ),
            if (_statusFilter != null ||
                _typeFilter != null ||
                _packageFilter != null ||
                _assignFilter != null ||
                _agentFilter != null)
              TextButton.icon(
                onPressed: () {
                  _statusFilter = null;
                  _typeFilter = null;
                  _packageFilter = null;
                  _assignFilter = null;
                  _agentFilter = null;
                  _applyFilters();
                },
                icon: const Icon(Icons.clear_all, size: 16),
                label: const Text('Xóa bộ lọc', style: TextStyle(fontSize: 12)),
              ),
          ],
        ),
      ]),
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
          style: const TextStyle(fontSize: 13, color: Colors.black87),
        ),
      ),
    );
  }

  Widget _buildCountBadges() {
    final available = _countByStatus('available');
    final activated = _countByStatus('activated');
    final revoked = _countByStatus('revoked');
    final unassigned =
        _licenses.where((l) => l['agentId'] == null && l['storeId'] == null).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          AdminHelpers.countBadge('Tổng', _licenses.length, AdminHelpers.primary),
          const SizedBox(width: 8),
          AdminHelpers.countBadge('Chưa dùng', available, AdminHelpers.success),
          const SizedBox(width: 8),
          AdminHelpers.countBadge('Đã kích hoạt', activated, AdminHelpers.primaryDark),
          const SizedBox(width: 8),
          AdminHelpers.countBadge('Thu hồi', revoked, AdminHelpers.danger),
          const SizedBox(width: 8),
          AdminHelpers.countBadge('Chưa gán', unassigned, AdminHelpers.warning),
          const SizedBox(width: 8),
          Text('Hiển thị: ${_filteredLicenses.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ]),
      ),
    );
  }

  Color _getCardBgColor(Map<String, dynamic> license) {
    final status = _getStatus(license);
    if (status == 'revoked') return AdminHelpers.danger.withValues(alpha: 0.04);
    if (status == 'activated') return AdminHelpers.success.withValues(alpha: 0.05);
    if (license['agentId'] != null) return AdminHelpers.info.withValues(alpha: 0.06);
    return Colors.white;
  }

  Widget _buildPaginatedList() {
    final isMobile = Responsive.isMobile(context);
    final totalCount = _filteredLicenses.length;
    final totalPages = (totalCount / _pageSize).ceil().clamp(1, 99999);
    final page = _currentPage.clamp(1, totalPages);
    final startIndex = isMobile ? 0 : (page - 1) * _pageSize;
    final endIndex = isMobile ? totalCount : (page * _pageSize).clamp(0, totalCount);
    final paginatedItems = _filteredLicenses.sublist(startIndex.clamp(0, totalCount), endIndex);

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
                    child: _buildLicenseDeckItem(paginatedItems[i]),
                  ),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: paginatedItems.length,
                itemBuilder: (ctx, i) => _buildLicenseCard(paginatedItems[i]),
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

  Widget _buildLicenseDeckItem(Map<String, dynamic> license) {
    final status = _getStatus(license);
    final statusColor = status == 'activated' ? Colors.green : status == 'available' ? Colors.blue : Colors.red;
    final statusText = status == 'activated' ? 'K\u00edch ho\u1ea1t' : status == 'available' ? 'C\u00f2n tr\u1ed1ng' : 'Thu h\u1ed3i';
    final key = license['key']?.toString() ?? '';
    final licenseType = license['licenseType']?.toString() ?? '';

    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.vpn_key, color: statusColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(key.length > 24 ? '${key.substring(0, 24)}...' : key, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text([AdminHelpers.licenseTypeLabel(licenseType), license['servicePackageName'] ?? '', '${license['durationDays'] ?? 0}d'].join(' \u00b7 '),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(statusText, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ]),
      ),
    );
  }

  Widget _buildLicenseCard(Map<String, dynamic> license) {
    final status = _getStatus(license);
    final Color statusColor = switch (status) {
      'activated' => AdminHelpers.primaryDark,
      'available' => AdminHelpers.success,
      'revoked' => AdminHelpers.danger,
      _ => Colors.grey,
    };
    final statusText = switch (status) {
      'activated' => 'Đã kích hoạt',
      'available' => 'Chưa dùng',
      'revoked' => 'Thu hồi',
      _ => status,
    };
    final canDel = _canDelete(license);
    final cardBg = _getCardBgColor(license);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: AdminHelpers.cardDecoration(borderColor: statusColor).copyWith(color: cardBg),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(Icons.vpn_key, color: statusColor, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: SelectableText(
                          license['key'] ?? 'N/A',
                          style: const TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: 'Copy key',
                        onPressed: () {
                          Clipboard.setData(
                              ClipboardData(text: license['key'] ?? ''));
                          if (mounted) {
                            AdminHelpers.showSuccess(context, 'Đã copy key');
                          }
                        },
                      ),
                    ]),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: [
                      AdminHelpers.statusChip(statusText, statusColor),
                      if (license['licenseType'] != null)
                        AdminHelpers.statusChip(
                            AdminHelpers.licenseTypeLabel(license['licenseType']?.toString()), AdminHelpers.info),
                      if (license['servicePackageName'] != null)
                        AdminHelpers.statusChip(
                            license['servicePackageName'], AdminHelpers.primary),
                      AdminHelpers.statusChip(
                          '${license['durationDays'] ?? 0} ngày',
                          Colors.grey),
                    ]),
                  ]),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: Wrap(spacing: 16, runSpacing: 4, children: [
                _infoItem(Icons.people, 'Users: ${license['maxUsers'] ?? 0}'),
                _infoItem(Icons.router, 'Devices: ${license['maxDevices'] ?? 0}'),
                if (license['storeName'] != null)
                  _infoItem(Icons.store, license['storeName']),
                if (license['agentName'] != null)
                  _infoItem(Icons.person, 'Đại lý: ${license['agentName']}'),
                if (license['activatedAt'] != null)
                  _infoItem(Icons.check_circle,
                      'Kích hoạt: ${AdminHelpers.formatDateTime(license['activatedAt'])}'),
                _infoItem(Icons.calendar_today,
                    'Tạo: ${AdminHelpers.formatDate(license['createdAt'])}'),
                if (license['notes'] != null &&
                    license['notes'].toString().isNotEmpty)
                  _infoItem(Icons.note, license['notes']),
              ]),
            ),
            const SizedBox(width: 8),
            if (status == 'available')
              IconButton(
                icon: const Icon(Icons.block,
                    color: AdminHelpers.warning, size: 18),
                tooltip: 'Thu hồi',
                onPressed: () => _revokeLicense(license),
              ),
            if (canDel)
              IconButton(
                icon: const Icon(Icons.delete_forever,
                    color: AdminHelpers.danger, size: 18),
                tooltip: 'Xóa vĩnh viễn',
                onPressed: () => _deleteLicense(license),
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _infoItem(IconData icon, String text) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 13, color: Colors.grey[500]),
      const SizedBox(width: 4),
      Text(text,
          style: TextStyle(fontSize: 12, color: Colors.grey[700])),
    ]);
  }

  Future<void> _revokeLicense(Map<String, dynamic> license) async {
    final confirm = await AdminHelpers.showConfirmDialog(
        context, 'Thu hồi License', 'Bạn có chắc muốn thu hồi license này?');
    if (confirm == true) {
      final res = await _apiService
          .revokeLicenseKey(license['id']?.toString() ?? '');
      if (mounted) {
        if (res['isSuccess'] == true) {
          AdminHelpers.showSuccess(context, 'Đã thu hồi license');
        } else {
          AdminHelpers.showApiError(context, res);
        }
      }
      loadData();
    }
  }

  Future<void> _deleteLicense(Map<String, dynamic> license) async {
    final confirm = await AdminHelpers.showConfirmDialog(context,
        'Xóa vĩnh viễn License', 'Key này sẽ bị xóa vĩnh viễn. Tiếp tục?');
    if (confirm == true) {
      final res = await _apiService
          .deleteLicenseKeyPermanent(license['id']?.toString() ?? '');
      if (mounted) {
        if (res['isSuccess'] == true) {
          AdminHelpers.showSuccess(context, 'Đã xóa license');
        } else {
          AdminHelpers.showApiError(context, res);
        }
      }
      loadData();
    }
  }

  void _showCreateLicenseDialog() {
    String licenseType = 'Basic';
    String? selectedPackageId;
    final daysCtrl = TextEditingController(text: '365');
    final usersCtrl = TextEditingController(text: '50');
    final devicesCtrl = TextEditingController(text: '10');
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo License Key'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: StatefulBuilder(
            builder: (ctx, setSt) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String?>(
                initialValue: selectedPackageId,
                decoration: InputDecoration(
                    labelText: 'Gói dịch vụ',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('-- Không chọn --')),
                  ..._servicePackages
                      .where((p) => p['isActive'] == true)
                      .map((p) => DropdownMenuItem(
                          value: p['id']?.toString(),
                          child: Text(p['name']?.toString() ?? ''))),
                ],
                onChanged: (v) {
                  setSt(() {
                    selectedPackageId = v;
                    if (v != null) {
                      final pkg = _servicePackages.firstWhere(
                          (p) => p['id']?.toString() == v,
                          orElse: () => <String, dynamic>{});
                      if (pkg.isNotEmpty) {
                        daysCtrl.text =
                            (pkg['defaultDurationDays'] ?? 365).toString();
                        usersCtrl.text =
                            (pkg['maxUsers'] ?? 50).toString();
                        devicesCtrl.text =
                            (pkg['maxDevices'] ?? 10).toString();
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: licenseType,
                decoration: InputDecoration(
                    labelText: 'Loại license',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: const [
                  DropdownMenuItem(value: 'Basic', child: Text('Cơ bản')),
                  DropdownMenuItem(value: 'Advanced', child: Text('Nâng cao')),
                  DropdownMenuItem(value: 'Professional', child: Text('Chuyên nghiệp')),
                ],
                onChanged: (v) =>
                    setSt(() => licenseType = v ?? licenseType),
              ),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  daysCtrl, 'Số ngày', Icons.calendar_today),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: AdminHelpers.dialogField(
                        usersCtrl, 'Max users', Icons.people)),
                const SizedBox(width: 12),
                Expanded(
                    child: AdminHelpers.dialogField(
                        devicesCtrl, 'Max devices', Icons.router)),
              ]),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(notesCtrl, 'Ghi chú', Icons.note),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final res = await _apiService.createLicenseKey(
                licenseType: licenseType,
                durationDays: int.tryParse(daysCtrl.text),
                maxUsers: int.tryParse(usersCtrl.text),
                maxDevices: int.tryParse(devicesCtrl.text),
                notes: notesCtrl.text.isEmpty ? null : notesCtrl.text,
                servicePackageId: selectedPackageId,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) {
                if (res['isSuccess'] == true) {
                  AdminHelpers.showSuccess(context, 'Đã tạo license key');
                } else {
                  AdminHelpers.showApiError(context, res);
                }
              }
              loadData();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primaryDark,
                foregroundColor: Colors.white),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  void _showBatchCreateDialog() {
    final countCtrl = TextEditingController(text: '10');
    String licenseType = 'Basic';
    String? selectedPackageId;
    final daysCtrl = TextEditingController(text: '365');
    final usersCtrl = TextEditingController(text: '50');
    final devicesCtrl = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tạo hàng loạt License'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: StatefulBuilder(
            builder: (ctx, setSt) =>
                Column(mainAxisSize: MainAxisSize.min, children: [
              AdminHelpers.dialogField(
                  countCtrl, 'Số lượng', Icons.numbers),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: selectedPackageId,
                decoration: InputDecoration(
                    labelText: 'Gói dịch vụ',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('-- Không chọn --')),
                  ..._servicePackages
                      .where((p) => p['isActive'] == true)
                      .map((p) => DropdownMenuItem(
                          value: p['id']?.toString(),
                          child: Text(p['name']?.toString() ?? ''))),
                ],
                onChanged: (v) {
                  setSt(() {
                    selectedPackageId = v;
                    if (v != null) {
                      final pkg = _servicePackages.firstWhere(
                          (p) => p['id']?.toString() == v,
                          orElse: () => <String, dynamic>{});
                      if (pkg.isNotEmpty) {
                        daysCtrl.text =
                            (pkg['defaultDurationDays'] ?? 365).toString();
                        usersCtrl.text =
                            (pkg['maxUsers'] ?? 50).toString();
                        devicesCtrl.text =
                            (pkg['maxDevices'] ?? 10).toString();
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: licenseType,
                decoration: InputDecoration(
                    labelText: 'Loại license',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10))),
                items: const [
                  DropdownMenuItem(value: 'Basic', child: Text('Cơ bản')),
                  DropdownMenuItem(value: 'Advanced', child: Text('Nâng cao')),
                  DropdownMenuItem(value: 'Professional', child: Text('Chuyên nghiệp')),
                ],
                onChanged: (v) =>
                    setSt(() => licenseType = v ?? licenseType),
              ),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(
                  daysCtrl, 'Số ngày', Icons.calendar_today),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: AdminHelpers.dialogField(
                        usersCtrl, 'Max users', Icons.people)),
                const SizedBox(width: 12),
                Expanded(
                    child: AdminHelpers.dialogField(
                        devicesCtrl, 'Max devices', Icons.router)),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              final res = await _apiService.createBatchLicenseKeys(
                count: int.tryParse(countCtrl.text),
                licenseType: licenseType,
                durationDays: int.tryParse(daysCtrl.text),
                maxUsers: int.tryParse(usersCtrl.text),
                maxDevices: int.tryParse(devicesCtrl.text),
                servicePackageId: selectedPackageId,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) {
                if (res['isSuccess'] == true) {
                  AdminHelpers.showSuccess(
                      context, 'Đã tạo ${countCtrl.text} license keys');
                } else {
                  AdminHelpers.showApiError(context, res);
                }
              }
              loadData();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.primaryDark,
                foregroundColor: Colors.white),
            child: const Text('Tạo'),
          ),
        ],
      ),
    );
  }

  void _showBatchAssignAgentDialog() {
    String? selectedAgentId;
    String? selectedPackageId;
    String? selectedLicenseType;
    final countCtrl = TextEditingController(text: '10');

    // Count available keys
    final availableCount = _licenses
        .where((l) =>
            l['isUsed'] != true &&
            l['isActive'] != false &&
            l['agentId'] == null)
        .length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cấp key hàng loạt cho đại lý'),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 420,
          child: StatefulBuilder(
            builder: (ctx, setSt) {
              // Recalculate filtered count based on selected filters
              var filteredAvailable = _licenses.where((l) =>
                  l['isUsed'] != true &&
                  l['isActive'] != false &&
                  l['agentId'] == null);
              if (selectedPackageId != null) {
                filteredAvailable = filteredAvailable.where(
                    (l) => l['servicePackageId']?.toString() == selectedPackageId);
              }
              if (selectedLicenseType != null) {
                filteredAvailable = filteredAvailable.where(
                    (l) => l['licenseType']?.toString() == selectedLicenseType);
              }
              final filteredCount = filteredAvailable.length;

              return Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdminHelpers.info.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline,
                        color: AdminHelpers.info, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Tổng key khả dụng: $availableCount | Phù hợp bộ lọc: $filteredCount',
                      style: const TextStyle(
                          fontSize: 13, color: AdminHelpers.info),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedAgentId,
                  decoration: InputDecoration(
                      labelText: 'Chọn đại lý *',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: _agents
                      .where((a) => a['isActive'] == true)
                      .map((a) => DropdownMenuItem(
                          value: a['id']?.toString(),
                          child: Text(
                              '${a['name'] ?? ''} (${a['code'] ?? ''})')))
                      .toList(),
                  onChanged: (v) => setSt(() => selectedAgentId = v),
                ),
                const SizedBox(height: 12),
                AdminHelpers.dialogField(
                    countCtrl, 'Số lượng key cấp', Icons.numbers),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: selectedPackageId,
                  decoration: InputDecoration(
                      labelText: 'Gói dịch vụ (tuỳ chọn)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('-- Tất cả gói --')),
                    ..._servicePackages
                        .where((p) => p['isActive'] == true)
                        .map((p) => DropdownMenuItem(
                            value: p['id']?.toString(),
                            child: Text(p['name']?.toString() ?? ''))),
                  ],
                  onChanged: (v) => setSt(() => selectedPackageId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: selectedLicenseType,
                  decoration: InputDecoration(
                      labelText: 'Loại license (tuỳ chọn)',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10))),
                  items: const [
                    DropdownMenuItem(
                        value: null, child: Text('-- Tất cả loại --')),
                    DropdownMenuItem(value: 'Basic', child: Text('Cơ bản')),
                    DropdownMenuItem(value: 'Advanced', child: Text('Nâng cao')),
                    DropdownMenuItem(
                        value: 'Professional', child: Text('Chuyên nghiệp')),
                  ],
                  onChanged: (v) => setSt(() => selectedLicenseType = v),
                ),
              ]);
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Hủy')),
          ElevatedButton.icon(
            onPressed: () async {
              if (selectedAgentId == null) {
                AdminHelpers.showError(context, 'Vui lòng chọn đại lý');
                return;
              }
              final count = int.tryParse(countCtrl.text) ?? 0;
              if (count <= 0) {
                AdminHelpers.showError(context, 'Số lượng phải lớn hơn 0');
                return;
              }
              final res =
                  await _apiService.batchAssignLicensesToAgentByCount(
                agentId: selectedAgentId!,
                count: count,
                servicePackageId: selectedPackageId,
                licenseType: selectedLicenseType,
              );
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) {
                if (res['isSuccess'] == true) {
                  final assigned =
                      res['data']?['assignedCount'] ?? count;
                  AdminHelpers.showSuccess(
                      context, 'Đã cấp $assigned key cho đại lý');
                } else {
                  AdminHelpers.showApiError(context, res);
                }
              }
              loadData();
            },
            icon: const Icon(Icons.assignment_ind, size: 18),
            label: const Text('Cấp key'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.info,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
