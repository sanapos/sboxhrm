import 'dart:async';
import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../../services/api_service.dart';
import '../../widgets/admin/admin_mobile_widgets.dart';
import '../../widgets/device_sync_progress_overlay.dart';
import 'system_admin_helpers.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class DevicesTab extends StatefulWidget {
  final List<Map<String, dynamic>> stores;
  final bool agentMode;

  const DevicesTab({super.key, this.stores = const [], this.agentMode = false});

  @override
  State<DevicesTab> createState() => DevicesTabState();
}

class DevicesTabState extends State<DevicesTab> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _devices = [];
  List<Map<String, dynamic>> _agents = [];
  List<Map<String, dynamic>> _localStores = [];
  bool _isLoading = false;

  String? _storeFilter;
  String? _agentFilter; // agentId | '__none__' | null
  String? _statusFilter; // 'online', 'offline', 'unassigned', null=all
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadStores();
    loadData();
    if (!widget.agentMode) _loadAgents();
  }

  List<Map<String, dynamic>> get _storesSource =>
      widget.stores.isNotEmpty ? widget.stores : _localStores;

  Future<void> _loadStores() async {
    if (widget.stores.isNotEmpty) return;
    try {
      final res = widget.agentMode
          ? await _apiService.getAgentStores(pageSize: 500)
          : await _apiService.getSystemStores(pageSize: 500);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() => _localStores = AdminHelpers.extractList(res['data']));
      }
    } catch (e) {
      debugPrint('DevicesTab stores error: $e');
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get devices => _devices;

  Future<void> _loadAgents() async {
    try {
      final res = await _apiService.getSystemAgents(pageSize: 200);
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() => _agents = AdminHelpers.extractList(res['data']));
      }
    } catch (e) {
      debugPrint('DevicesTab agents error: $e');
    }
  }

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      await _loadStores();
      final res = widget.agentMode
          ? await _apiService.getAgentAdminDevices(
              storeId: _storeFilter,
              isOnline: _statusFilter == 'online'
                  ? true
                  : _statusFilter == 'offline'
                      ? false
                      : null,
              isClaimed: _statusFilter == 'unassigned' ? false : null,
            )
          : await _apiService.getSystemDevices(
              storeId: _storeFilter,
              agentId: _agentFilter != null && _agentFilter != '__none__'
                  ? _agentFilter
                  : null,
              noAgent: _agentFilter == '__none__' ? true : null,
              isOnline: _statusFilter == 'online'
                  ? true
                  : _statusFilter == 'offline'
                      ? false
                      : null,
              isClaimed: _statusFilter == 'unassigned' ? false : null,
            );
      if (!mounted) return;
      if (res['isSuccess'] == true) {
        setState(() =>
            _devices = AdminHelpers.extractList(res['data']));
      }
    } catch (e) {
      debugPrint('DevicesTab error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filteredDevices {
    if (_searchCtrl.text.isEmpty) return _devices;
    final query = _searchCtrl.text.toLowerCase();
    return _devices.where((d) {
      final name = (d['deviceName'] ?? d['name'] ?? '').toString().toLowerCase();
      final serial = (d['serialNumber'] ?? '').toString().toLowerCase();
      final ip = (d['ipAddress'] ?? '').toString().toLowerCase();
      final store = (d['storeName'] ?? '').toString().toLowerCase();
      return name.contains(query) ||
          serial.contains(query) ||
          ip.contains(query) ||
          store.contains(query);
    }).toList();
  }

  bool _hasStoreAssignment(Map<String, dynamic> d) =>
      d['storeId'] != null && d['storeId'].toString().isNotEmpty;

  String _resolveStoreGroupLabel(Map<String, dynamic> d) {
    if (!_hasStoreAssignment(d)) return 'Chưa gán cửa hàng';

    final direct = d['storeName'] ?? d['storeCode'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }

    final sid = d['storeId']?.toString();
    for (final s in _storesSource) {
      if (s['id']?.toString() == sid) {
        final name = s['name'] ?? s['storeName'] ?? s['code'];
        if (name != null && name.toString().trim().isNotEmpty) {
          return name.toString().trim();
        }
      }
    }
    return sid != null ? 'Cửa hàng ($sid)' : 'Đã gán cửa hàng';
  }

  String _storeGroupKey(Map<String, dynamic> d) =>
      _hasStoreAssignment(d) ? d['storeId']!.toString() : '__unassigned__';

  ({List<Map<String, dynamic>> unassigned, List<({String label, Map<String, List<Map<String, dynamic>>> stores})> agents})
      _groupByAgentAndStore(List<Map<String, dynamic>> devices) {
    final unassigned = <Map<String, dynamic>>[];
    final agentBuckets = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final d in devices) {
      if (!_hasStoreAssignment(d)) {
        unassigned.add(d);
        continue;
      }
      final agentLabel =
          (d['agentName'] ?? 'Chưa có đại lý').toString().trim();
      final storeLabel = _resolveStoreGroupLabel(d);
      agentBuckets.putIfAbsent(agentLabel, () => {});
      agentBuckets[agentLabel]!.putIfAbsent(storeLabel, () => []).add(d);
    }

    final agents = agentBuckets.entries
        .map((e) => (label: e.key, stores: e.value))
        .toList()
      ..sort((a, b) {
        if (a.label == 'Chưa có đại lý') return 1;
        if (b.label == 'Chưa có đại lý') return -1;
        return a.label.compareTo(b.label);
      });

    return (unassigned: unassigned, agents: agents);
  }

  Map<String, List<Map<String, dynamic>>> _groupByStoreOnly(
      List<Map<String, dynamic>> devices) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final d in devices) {
      grouped.putIfAbsent(_storeGroupKey(d), () => []).add(d);
    }
    return grouped;
  }

  String _labelForStoreGroupKey(String key, List<Map<String, dynamic>> devices) {
    if (key == '__unassigned__') return 'Chưa gán cửa hàng';
    if (devices.isNotEmpty) return _resolveStoreGroupLabel(devices.first);
    return key;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final filtered = _filteredDevices;
    final onlineCount = _devices.where((d) => d['isOnline'] == true).length;
    final unassignedCount =
        _devices.where((d) => !_hasStoreAssignment(d)).length;

    final listChildren = <Widget>[];

    if (widget.agentMode) {
      final grouped = _groupByStoreOnly(filtered);
      final sortedKeys = grouped.keys.toList()
        ..sort((a, b) {
          if (a == '__unassigned__') return -1;
          if (b == '__unassigned__') return 1;
          return _labelForStoreGroupKey(a, grouped[a]!)
              .compareTo(_labelForStoreGroupKey(b, grouped[b]!));
        });
      for (final storeKey in sortedKeys) {
        final storeDevices = grouped[storeKey]!;
        final storeOnline =
            storeDevices.where((d) => d['isOnline'] == true).length;
        listChildren.add(_buildDeviceStoreGroup(
          _labelForStoreGroupKey(storeKey, storeDevices),
          storeDevices,
          storeOnline,
        ));
      }
    } else {
      final partitioned = _groupByAgentAndStore(filtered);
      if (partitioned.unassigned.isNotEmpty) {
        final online = partitioned.unassigned
            .where((d) => d['isOnline'] == true)
            .length;
        listChildren.add(_buildDeviceStoreGroup(
          'Chưa gán cửa hàng',
          partitioned.unassigned,
          online,
        ));
      }
      for (final agentGroup in partitioned.agents) {
        listChildren.add(_buildAgentDeviceGroup(agentGroup));
      }
    }

    return Column(
      children: [
        _buildToolbar(onlineCount, unassignedCount),
        Expanded(
          child: filtered.isEmpty
              ? AdminHelpers.emptyState(
                  Icons.router,
                  _searchCtrl.text.isNotEmpty
                      ? 'Không tìm thấy thiết bị'
                      : 'Không có thiết bị')
              : ListView(
                  padding: EdgeInsets.symmetric(
                      horizontal: adminUseMobileLayout(context) ? 12 : 20),
                  children: listChildren,
                ),
        ),
      ],
    );
  }

  Widget _buildAgentDeviceGroup(
      ({String label, Map<String, List<Map<String, dynamic>>> stores})
          agentGroup) {
    final storeEntries = agentGroup.stores.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final totalDevices = agentGroup.stores.values
        .fold<int>(0, (sum, list) => sum + list.length);
    final onlineDevices = agentGroup.stores.values
        .expand((list) => list)
        .where((d) => d['isOnline'] == true)
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AdminHelpers.cardDecoration(borderColor: AdminHelpers.primary),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: AdminHelpers.primary.withValues(alpha: 0.1),
          child: const Icon(Icons.support_agent,
              color: AdminHelpers.primary, size: 20),
        ),
        title: Text(tr(agentGroup.label),
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Row(children: [
          AdminHelpers.statusChip(
              '$totalDevices thiết bị', AdminHelpers.info),
          const SizedBox(width: 6),
          AdminHelpers.statusChip('$onlineDevices online',
              onlineDevices > 0 ? AdminHelpers.success : Colors.grey),
          const SizedBox(width: 6),
          AdminHelpers.statusChip('${storeEntries.length} cửa hàng',
              AdminHelpers.primaryDark),
        ]),
        children: storeEntries.map((entry) {
          final storeOnline =
              entry.value.where((d) => d['isOnline'] == true).length;
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: _buildDeviceStoreGroup(
              entry.key,
              entry.value,
              storeOnline,
              nested: true,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildToolbar(int onlineCount, int unassignedCount) {
    final statsRow = AdminMobileStatRow(children: [
      AdminHelpers.countBadge('Tổng', _devices.length, AdminHelpers.info),
      const SizedBox(width: 8),
      AdminHelpers.countBadge('Online', onlineCount, AdminHelpers.success),
      const SizedBox(width: 8),
      AdminHelpers.countBadge(
          'Offline',
          _devices.length - onlineCount - unassignedCount,
          Colors.grey),
      if (unassignedCount > 0) ...[
        const SizedBox(width: 8),
        AdminHelpers.countBadge(
            'Chưa gán', unassignedCount, AdminHelpers.warning),
      ],
    ]);

    if (adminUseMobileLayout(context)) {
      return AdminMobileListToolbar(
        searchController: _searchCtrl,
        searchHint: 'Tìm thiết bị theo tên, SN, IP...',
        onSearchChanged: () => setState(() {}),
        activeFilterCount: (_storeFilter != null ? 1 : 0) +
            (_agentFilter != null ? 1 : 0) +
            (_statusFilter != null ? 1 : 0),
        onRefresh: loadData,
        onOpenFilters: () => showAdminFilterSheet(
          context,
          onApply: () {
            setState(() {});
            loadData();
          },
          onClear: () {
            setState(() {
              _storeFilter = null;
              _agentFilter = null;
              _statusFilter = null;
            });
            loadData();
          },
          child: _buildFilterFields(fullWidth: true),
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
            hint: 'Tìm thiết bị theo tên, SN, IP...',
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          _buildFilterFields(),
          const SizedBox(height: 8),
          statsRow,
        ],
      ),
    );
  }

  Widget _buildFilterFields({bool fullWidth = false}) {
    final agentDropdown = !widget.agentMode
        ? Container(
            width: fullWidth ? double.infinity : 200,
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _agentFilter,
                hint: Text(tr('Tất cả đại lý'),
                    style: TextStyle(fontSize: 13)),
                items: [
                  DropdownMenuItem<String>(
                      value: null,
                      child: Text(tr('Tất cả đại lý'),
                          style: TextStyle(fontSize: 13))),
                  DropdownMenuItem<String>(
                      value: '__none__',
                      child: Text(tr('Chưa có đại lý'),
                          style: TextStyle(fontSize: 13))),
                  ..._agents.map((a) => DropdownMenuItem(
                        value: a['id']?.toString(),
                        child: Text(
                          tr('${a['name'] ?? a['code'] ?? 'Đại lý'} (${a['code'] ?? ''})'),
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      )),
                ],
                onChanged: (v) {
                  setState(() => _agentFilter = v);
                  loadData();
                },
              ),
            ),
          )
        : null;

    final storeDropdown = Container(
      width: fullWidth ? double.infinity : 200,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: _storeFilter,
          hint: Text(tr('Tất cả cửa hàng'), style: TextStyle(fontSize: 13)),
          items: [
            DropdownMenuItem<String>(
                value: null,
                child: Text(tr('Tất cả cửa hàng'), style: TextStyle(fontSize: 13))),
            ..._storesSource.map((s) => DropdownMenuItem(
                  value: s['id']?.toString(),
                  child: Text(tr(s['name'] ?? 'N/A'),
                      style: const TextStyle(fontSize: 13)),
                )),
          ],
          onChanged: (v) {
            setState(() => _storeFilter = v);
            loadData();
          },
        ),
      ),
    );

    final statusDropdown = Container(
      width: fullWidth ? double.infinity : null,
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300)),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          isExpanded: fullWidth,
          value: _statusFilter,
          hint: Text(tr('Tất cả'), style: TextStyle(fontSize: 13)),
          items: [
            DropdownMenuItem(
                value: null,
                child: Text(tr('Tất cả'), style: TextStyle(fontSize: 13))),
            DropdownMenuItem(
                value: 'online',
                child: Text(tr('Online'), style: TextStyle(fontSize: 13))),
            DropdownMenuItem(
                value: 'offline',
                child: Text(tr('Offline'), style: TextStyle(fontSize: 13))),
            DropdownMenuItem(
                value: 'unassigned',
                child: Text(tr('Chưa gán'), style: TextStyle(fontSize: 13))),
          ],
          onChanged: (v) {
            setState(() => _statusFilter = v);
            loadData();
          },
        ),
      ),
    );

    if (fullWidth) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (agentDropdown != null) ...[
            agentDropdown,
            const SizedBox(height: 12),
          ],
          storeDropdown,
          const SizedBox(height: 12),
          statusDropdown,
        ],
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        if (agentDropdown != null) agentDropdown,
        storeDropdown,
        statusDropdown,
      ],
    );
  }

  Widget _buildDeviceStoreGroup(
      String storeName,
      List<Map<String, dynamic>> devices,
      int onlineCount,
      {bool nested = false}) {
    final isUnclaimed = storeName == 'Chưa gán cửa hàng';
    return Container(
      margin: EdgeInsets.only(bottom: nested ? 0 : 10),
      decoration: AdminHelpers.cardDecoration(
        borderColor: isUnclaimed ? AdminHelpers.warning : AdminHelpers.info,
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor:
              (isUnclaimed ? AdminHelpers.warning : AdminHelpers.info)
                  .withValues(alpha: 0.1),
          child: Icon(
              isUnclaimed ? Icons.device_unknown : Icons.store,
              color: isUnclaimed ? AdminHelpers.warning : AdminHelpers.info,
              size: 20),
        ),
        title: Text(tr(storeName),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(children: [
          AdminHelpers.statusChip(
              '${devices.length} thiết bị', AdminHelpers.info),
          const SizedBox(width: 6),
          AdminHelpers.statusChip('$onlineCount online',
              onlineCount > 0 ? AdminHelpers.success : Colors.grey),
        ]),
        children: MediaQuery.of(context).size.width < 600
          ? [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(devices.length, (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 10, left: 4, right: 4),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: _buildDeviceDeckItem(devices[i]),
                  ),
                )),
              ),
            ]
          : devices.map(_buildDeviceCard).toList(),
      ),
    );
  }

  Widget _buildDeviceDeckItem(Map<String, dynamic> device) {
    final isOnline = device['isOnline'] == true;
    final deviceName = device['deviceName'] ?? device['name'] ?? '';
    final serialNumber = device['serialNumber'] ?? '';
    final displayName = deviceName.isNotEmpty ? deviceName : serialNumber;

    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: isOnline ? AdminHelpers.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.router, color: isOnline ? AdminHelpers.success : Colors.red.shade400, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(tr(displayName), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(tr([serialNumber, if (device['ipAddress'] != null) device['ipAddress']].where((s) => s.toString().isNotEmpty).join(' \u00b7 ')),
                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: isOnline ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
            child: Text(tr(isOnline ? 'Online' : 'Offline'), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isOnline ? Colors.green : Colors.red)),
          ),
        ]),
      ),
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> device) {
    final isOnline = device['isOnline'] == true;
    final deviceName = device['deviceName'] ?? device['name'] ?? '';
    final serialNumber = device['serialNumber'] ?? '';
    final displayName =
        deviceName.isNotEmpty ? deviceName : serialNumber;
    final hasStore = _hasStoreAssignment(device);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: AdminHelpers.surfaceBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        leading: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isOnline ? AdminHelpers.success : Colors.red.shade400,
            boxShadow: isOnline
                ? [
                    BoxShadow(
                        color:
                            AdminHelpers.success.withValues(alpha: 0.4),
                        blurRadius: 6)
                  ]
                : null,
          ),
        ),
        title: Text(tr(displayName),
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Row(children: [
          Icon(Icons.tag, size: 12, color: Colors.grey[500]),
          const SizedBox(width: 4),
          Text(tr(serialNumber),
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontFamily: 'monospace')),
          if (device['ipAddress'] != null) ...[
            const SizedBox(width: 10),
            Icon(Icons.lan, size: 12, color: Colors.grey[500]),
            const SizedBox(width: 4),
            Text(tr(device['ipAddress']),
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[500],
                    fontFamily: 'monospace')),
          ],
        ]),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AdminHelpers.statusChip(
                isOnline ? 'Online' : 'Offline',
                isOnline ? AdminHelpers.success : Colors.red.shade400),
            const SizedBox(width: 4),
            const Icon(Icons.expand_more, size: 18),
          ],
        ),
        children: [
          // Info rows
          if (device['lastOnline'] != null)
            AdminHelpers.infoRow(Icons.access_time,
                'Lần cuối online: ${AdminHelpers.formatDateTime(device['lastOnline'])}'),
          if (device['storeName'] != null)
            AdminHelpers.infoRow(
                Icons.store, 'Cửa hàng: ${device['storeName']}'),
          if (hasStore && device['storeName'] == null)
            AdminHelpers.infoRow(
                Icons.store, 'Cửa hàng: ${_resolveStoreGroupLabel(device)}'),
          if (device['agentName'] != null)
            AdminHelpers.infoRow(
                Icons.support_agent, 'Đại lý: ${device['agentName']}'),
          if (!hasStore)
            AdminHelpers.infoRow(Icons.warning_amber,
                'Chưa gán cửa hàng'),
          AdminHelpers.infoRow(Icons.calendar_today,
              'Tạo lúc: ${AdminHelpers.formatDateTime(device['createdAt'])}'),
          const Divider(height: 24),
          // Action buttons
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.center,
            children: [
              if (context.systemAdminCanEdit) ...[
                if (hasStore)
                  _deviceAction(
                    icon: Icons.link_off,
                    label: 'Gỡ khỏi CH',
                    color: AdminHelpers.warning,
                    onTap: () => _unassignDevice(device),
                  ),
                _deviceAction(
                  icon: Icons.swap_horiz,
                  label: 'Chuyển CH',
                  color: AdminHelpers.info,
                  onTap: () => _transferDevice(device),
                ),
                _deviceAction(
                  icon: Icons.restart_alt,
                  label: 'Khởi động lại',
                  color: AdminHelpers.primary,
                  onTap: () => _restartDevice(device),
                ),
                _deviceAction(
                  icon: Icons.cleaning_services,
                  label: 'Xóa dữ liệu',
                  color: AdminHelpers.danger,
                  onTap: () => _clearDeviceData(device),
                ),
                _deviceAction(
                  icon: Icons.person_add,
                  label: 'Thêm user',
                  color: AdminHelpers.success,
                  onTap: () => _addUserToDevice(device),
                ),
                _deviceAction(
                  icon: Icons.sync,
                  label: 'Đồng bộ CC',
                  color: Colors.teal,
                  onTap: () => _syncAttendance(device),
                ),
              ],
              if (context.systemAdminCanDelete)
                _deviceAction(
                  icon: Icons.delete_forever,
                  label: 'Xóa thiết bị',
                  color: AdminHelpers.danger,
                  onTap: () => _deleteDevice(device),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _deviceAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.3)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      icon: Icon(icon, size: 14),
      label: Text(tr(label), style: const TextStyle(fontSize: 11)),
    );
  }

  // ═══════════════════════ UNASSIGN DEVICE ═══════════════════════
  Future<void> _unassignDevice(Map<String, dynamic> device) async {
    final name = device['deviceName'] ?? device['serialNumber'] ?? 'N/A';
    final confirmed = await AdminHelpers.showConfirmDialog(
        context,
        'Gỡ thiết bị khỏi cửa hàng',
        'Gỡ "$name" khỏi cửa hàng ${device['storeName'] ?? ''}?\n'
            'Thiết bị sẽ trở thành chưa gán.');

    if (confirmed != true || !mounted) return;

    final res = widget.agentMode
        ? await _apiService.agentUnassignDevice(device['id']?.toString() ?? '')
        : await _apiService
            .unassignSystemDevice(device['id']?.toString() ?? '');
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã gỡ "$name" khỏi cửa hàng');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ TRANSFER DEVICE ═══════════════════════
  Future<void> _transferDevice(Map<String, dynamic> device) async {
    final name = device['deviceName'] ?? device['serialNumber'] ?? 'N/A';
    final currentStoreId = device['storeId']?.toString();

    // Filter out current store from the list
    final availableStores = widget.stores
        .where((s) => s['id']?.toString() != currentStoreId)
        .toList();

    if (availableStores.isEmpty) {
      AdminHelpers.showError(context, 'Không có cửa hàng nào để chuyển');
      return;
    }

    String? selectedStoreId;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => ScrollableAlertDialog(
          title: Row(children: [
            const Icon(Icons.swap_horiz, color: AdminHelpers.info, size: 22),
            const SizedBox(width: 8),
            Expanded(
                child: Text(tr('Chuyển "$name"'),
                    style: const TextStyle(fontSize: 17))),
          ]),
          content: SizedBox(
            width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (device['storeName'] != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(children: [
                      Text(tr('Đang ở: '),
                          style: TextStyle(color: Colors.grey)),
                      AdminHelpers.statusChip(
                          device['storeName'], AdminHelpers.info),
                    ]),
                  ),
                Text(tr('Chọn cửa hàng đích:'),
                    style:
                        TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: availableStores.length,
                    itemBuilder: (_, i) {
                      final store = availableStores[i];
                      final storeId = store['id']?.toString();
                      final isSelected = selectedStoreId == storeId;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AdminHelpers.primary.withValues(alpha: 0.1)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: isSelected
                                  ? AdminHelpers.primary
                                  : Colors.grey.shade200),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(Icons.store,
                              color: isSelected
                                  ? AdminHelpers.primary
                                  : Colors.grey,
                              size: 20),
                          title: Text(tr(store['name'] ?? 'N/A'),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal)),
                          subtitle: Text(tr(store['code'] ?? ''),
                              style: const TextStyle(fontSize: 11)),
                          trailing: isSelected
                              ? const Icon(Icons.check_circle,
                                  color: AdminHelpers.primary, size: 20)
                              : null,
                          onTap: () {
                            setDialogState(
                                () => selectedStoreId = storeId);
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr('Hủy'))),
            FilledButton.icon(
              onPressed: selectedStoreId == null
                  ? null
                  : () => Navigator.pop(ctx, selectedStoreId),
              icon: const Icon(Icons.swap_horiz, size: 16),
              label: Text(tr('Chuyển')),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AdminHelpers.info),
            ),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    final res = widget.agentMode
        ? await _apiService.agentAssignDeviceToStore(
            device['id']?.toString() ?? '', result)
        : await _apiService.assignSystemDeviceToStore(
            device['id']?.toString() ?? '', result);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã chuyển "$name" sang cửa hàng mới');
      loadData();
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ RESTART DEVICE ═══════════════════════
  Future<void> _restartDevice(Map<String, dynamic> device) async {
    final name = device['deviceName'] ?? device['serialNumber'] ?? 'N/A';
    final confirmed = await AdminHelpers.showConfirmDialog(
        context,
        'Khởi động lại thiết bị',
        'Gửi lệnh khởi động lại đến "$name"?\n'
            'Thiết bị sẽ reboot và mất kết nối tạm thời.');

    if (confirmed != true || !mounted) return;

    final deviceId = device['id']?.toString() ?? '';
    // CommandType.RestartDevice = 6
    final res = await _apiService.sendDeviceCommand(deviceId, 6);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(
          context, 'Đã gửi lệnh khởi động lại "$name"');
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  // ═══════════════════════ CLEAR DATA ═══════════════════════
  Future<void> _clearDeviceData(Map<String, dynamic> device) async {
    final name = device['deviceName'] ?? device['serialNumber'] ?? 'N/A';

    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Row(children: [
          Icon(Icons.cleaning_services,
              color: AdminHelpers.danger, size: 22),
          SizedBox(width: 8),
          Text(tr('Xóa dữ liệu thiết bị'), style: TextStyle(fontSize: 17)),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Thiết bị: $name'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              _clearOption(
                  ctx, 'Xóa dữ liệu chấm công', Icons.schedule, 3,
                  desc: 'Xóa toàn bộ log chấm công trên máy'),
              _clearOption(
                  ctx, 'Xóa danh sách user', Icons.people, 4,
                  desc: 'Xóa toàn bộ user đã đăng ký trên máy'),
              _clearOption(
                  ctx, 'Xóa toàn bộ dữ liệu', Icons.delete_forever, 5,
                  desc: 'Khôi phục thiết bị về trạng thái ban đầu',
                  danger: true),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('Hủy'))),
        ],
      ),
    );

    if (result == null || !mounted) return;

    final res =
        await _apiService.sendDeviceCommand(device['id']?.toString() ?? '', result);
    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(context, 'Đã gửi lệnh xóa dữ liệu cho "$name"');
    } else {
      AdminHelpers.showApiError(context, res);
    }
  }

  Widget _clearOption(
      BuildContext ctx, String title, IconData icon, int cmdType,
      {String? desc, bool danger = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
                color: danger
                    ? AdminHelpers.danger.withValues(alpha: 0.3)
                    : Colors.grey.shade200)),
        leading: Icon(icon,
            color: danger ? AdminHelpers.danger : AdminHelpers.warning,
            size: 20),
        title: Text(tr(title),
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: danger ? AdminHelpers.danger : null)),
        subtitle:
            desc != null ? Text(tr(desc), style: const TextStyle(fontSize: 11)) : null,
        onTap: () => Navigator.pop(ctx, cmdType),
      ),
    );
  }

  // ═══════════════════════ ADD USER TO DEVICE ═══════════════════════
  Future<void> _addUserToDevice(Map<String, dynamic> device) async {
    final deviceId = device['id']?.toString() ?? '';
    final name = device['deviceName'] ?? device['serialNumber'] ?? 'N/A';
    final pinCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final cardCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Row(children: [
          const Icon(Icons.person_add,
              color: AdminHelpers.success, size: 22),
          const SizedBox(width: 8),
          Expanded(
              child: Text(tr('Thêm user - $name'),
                  style: const TextStyle(fontSize: 16))),
        ]),
        content: SizedBox(
          width: MediaQuery.of(context).size.width < 600 ? MediaQuery.of(context).size.width - 32 : 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AdminHelpers.dialogField(pinCtrl, 'Mã PIN (bắt buộc)', Icons.pin),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(nameCtrl, 'Tên nhân viên', Icons.person),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(cardCtrl, 'Số thẻ', Icons.credit_card),
              const SizedBox(height: 12),
              AdminHelpers.dialogField(passCtrl, 'Mật khẩu', Icons.lock,
                  obscureText: true),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('Hủy'))),
          FilledButton.icon(
            onPressed: () {
              if (pinCtrl.text.trim().isEmpty) {
                AdminHelpers.showError(ctx, 'Vui lòng nhập mã PIN');
                return;
              }
              Navigator.pop(ctx, true);
            },
            icon: const Icon(Icons.person_add, size: 16),
            label: Text(tr('Thêm')),
            style: ElevatedButton.styleFrom(
                backgroundColor: AdminHelpers.success),
          ),
        ],
      ),
    );

    if (result != true || !mounted) return;

    // Use syncEmployeeToDevice to add user
    final res = await _apiService.syncEmployeeToDevice(
      employeeId: '', // Will be created as device user
      deviceId: deviceId,
      pin: pinCtrl.text.trim(),
      cardNumber: cardCtrl.text.trim().isNotEmpty ? cardCtrl.text.trim() : null,
      password: passCtrl.text.trim().isNotEmpty ? passCtrl.text.trim() : null,
    );

    if (!mounted) return;
    if (res['isSuccess'] == true) {
      AdminHelpers.showSuccess(
          context, 'Đã thêm user PIN=${pinCtrl.text} vào "$name"');
    } else {
      // Fallback: try sendDeviceCommand with AddDeviceUser=0
      final cmdRes = await _apiService.sendDeviceCommand(deviceId, 0,
          command: 'PIN=${pinCtrl.text.trim()}\t'
              'Name=${nameCtrl.text.trim()}\t'
              'Card=${cardCtrl.text.trim()}\t'
              'Password=${passCtrl.text.trim()}');
      if (!mounted) return;
      if (cmdRes['isSuccess'] == true) {
        AdminHelpers.showSuccess(
            context, 'Đã gửi lệnh thêm user PIN=${pinCtrl.text} vào "$name"');
      } else {
        AdminHelpers.showApiError(context, res);
      }
    }
  }

  // ═══════════════════════ SYNC ATTENDANCE ═══════════════════════
  Future<void> _syncAttendance(Map<String, dynamic> device) async {
    final name = device['deviceName'] ?? device['serialNumber'] ?? 'N/A';
    final deviceId = device['id']?.toString() ?? '';
    if (deviceId.isEmpty) return;
    unawaited(DeviceSyncProgressDialog.show(
      apiService: _apiService,
      kind: DeviceSyncKind.attendances,
      devices: [DeviceSyncTarget(deviceId: deviceId, deviceName: name.toString())],
    ));
  }

  // ═══════════════════════ DELETE DEVICE ═══════════════════════
  Future<void> _deleteDevice(Map<String, dynamic> device) async {
    final name = device['deviceName'] ?? device['serialNumber'] ?? 'N/A';
    final sn = device['serialNumber'] ?? '';
    final confirmed = await AdminHelpers.showConfirmDialog(
        context,
        'Xóa thiết bị',
        'Bạn có chắc muốn xóa thiết bị "$name" (SN: $sn) khỏi hệ thống?\n'
            'Hành động này không thể hoàn tác.');

    if (confirmed != true || !mounted) return;

    final res = await _apiService.deleteDevice(device['id']?.toString() ?? '');
    if (!mounted) return;
    if (res['success'] == true) {
      AdminHelpers.showSuccess(context, 'Đã xóa thiết bị "$name"');
      loadData();
    } else {
      AdminHelpers.showError(context, res['message'] ?? 'Lỗi xóa thiết bị');
    }
  }
}
