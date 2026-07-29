import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/web_route_parser.dart';
import 'agent_license_keys_screen.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Portal riêng cho đại lý (Agent) tại /admin.
class AgentPortalScreen extends StatefulWidget {
  const AgentPortalScreen({super.key});

  @override
  State<AgentPortalScreen> createState() => _AgentPortalScreenState();
}

class _AgentPortalScreenState extends State<AgentPortalScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  late TabController _tabs;
  final _deviceSearchCtrl = TextEditingController();

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _dashboard;
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _devices = [];
  String? _referralLink;
  String? _deviceStoreFilter;
  bool? _deviceOnlineFilter;
  bool _loading = true;
  bool _devicesLoading = false;
  String? _error;

  static const _accent = Color(0xFFEA580C);
  static const _navy = Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _deviceSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getAgentProfile(),
        _api.getAgentDashboard(),
        _api.getAgentStores(),
        _api.getAgentReferralLink(),
        _loadDevices(),
      ]);
      if (!mounted) return;
      if (results[0]['isSuccess'] == true) {
        _profile = Map<String, dynamic>.from(results[0]['data'] as Map);
      }
      if (results[1]['isSuccess'] == true) {
        _dashboard = Map<String, dynamic>.from(results[1]['data'] as Map);
      }
      if (results[2]['isSuccess'] == true) {
        _stores = List<Map<String, dynamic>>.from(results[2]['data'] ?? []);
      }
      if (results[3]['isSuccess'] == true) {
        _referralLink =
            (results[3]['data'] as Map?)?['referralLink']?.toString();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<Map<String, dynamic>> _loadDevices() async {
    setState(() => _devicesLoading = true);
    final res = await _api.getAgentDevices(
      storeId: _deviceStoreFilter,
      isOnline: _deviceOnlineFilter,
      search: _deviceSearchCtrl.text.trim().isEmpty
          ? null
          : _deviceSearchCtrl.text.trim(),
      pageSize: 100,
    );
    if (mounted) {
      if (res['isSuccess'] == true && res['data'] is Map) {
        final data = res['data'] as Map;
        _devices = List<Map<String, dynamic>>.from(data['items'] ?? []);
      }
      setState(() => _devicesLoading = false);
    }
    return res;
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Đăng xuất?')),
        content: Text(tr('Bạn có chắc muốn đăng xuất khỏi cổng đại lý?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(tr('Huỷ')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(tr('Đăng xuất')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await Provider.of<AuthProvider>(context, listen: false).logout();
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: tr(link)));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('Đã sao chép link'))),
    );
  }

  int _intVal(dynamic v) => (v as num?)?.toInt() ?? 0;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final email = auth.currentUser?.email ?? 'Đại lý';
    final dash = _dashboard;
    final agentName =
        dash?['agentName']?.toString() ?? _profile?['name']?.toString() ?? email;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_navy, Color(0xFF334155)],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Row(
                      children: [
                        const Icon(Icons.support_agent,
                            color: Colors.white, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Cổng đại lý'),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                tr(agentName),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _handleLogout(context),
                          icon: const Icon(Icons.logout,
                              color: Colors.white, size: 16),
                          label: Text(tr('Đăng xuất'),
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  if (dash != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Row(
                        children: [
                          _statChip('Cửa hàng',
                              '${_intVal(dash['storeCount'])}'),
                          const SizedBox(width: 8),
                          _statChip('Thiết bị',
                              '${_intVal(dash['onlineDevices'])}/${_intVal(dash['totalDevices'])} online'),
                          const SizedBox(width: 8),
                          _statChip('Key',
                              '${_intVal(dash['availableKeys'])}'),
                        ],
                      ),
                    ),
                  TabBar(
                    controller: _tabs,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: [
                      Tab(text: tr('Tổng quan')),
                      Tab(text: tr('Gian hàng')),
                      Tab(text: tr('Thiết bị')),
                      Tab(text: tr('License')),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(tr('Lỗi: $_error')))
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _buildOverviewTab(),
                          _buildStoresTab(),
                          _buildDevicesTab(),
                          const AgentLicenseKeysScreen(embedded: true),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        tr('$label: $value'),
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final dash = _dashboard;
    final link =
        _referralLink ?? profileCodeLink(_profile?['code']?.toString());

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (dash != null) ...[
            Text(tr('${tr('Xin chào, ')}${dash['agentName'] ?? ''}'),
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: _navy),
            ),
            if (dash['agentCode'] != null)
              Text(tr('${tr('Mã đại lý: ')}${dash['agentCode']}'),
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.35,
              children: [
                _dashCard(
                  icon: Icons.storefront,
                  color: const Color(0xFF0891B2),
                  title: 'Cửa hàng',
                  value: '${_intVal(dash['storeCount'])}',
                  subtitle:
                      '${_intVal(dash['activeStores'])} HĐ · ${_intVal(dash['lockedStores'])} khóa',
                  onTap: () => _tabs.animateTo(1),
                ),
                _dashCard(
                  icon: Icons.router,
                  color: const Color(0xFF7C3AED),
                  title: 'Thiết bị',
                  value: '${_intVal(dash['totalDevices'])}',
                  subtitle:
                      '${_intVal(dash['onlineDevices'])} online · ${_intVal(dash['offlineDevices'])} offline',
                  onTap: () => _tabs.animateTo(2),
                ),
                _dashCard(
                  icon: Icons.vpn_key,
                  color: const Color(0xFF059669),
                  title: 'License key',
                  value: '${_intVal(dash['availableKeys'])}',
                  subtitle:
                      'Đã dùng ${_intVal(dash['usedKeys'])}/${_intVal(dash['totalKeys'])}',
                  onTap: () => _tabs.animateTo(3),
                ),
                _dashCard(
                  icon: Icons.event_busy,
                  color: _accent,
                  title: 'Sắp hết hạn',
                  value: '${_intVal(dash['storesExpiringSoon'])}',
                  subtitle: 'Trong 30 ngày tới',
                  onTap: () => _tabs.animateTo(1),
                ),
              ],
            ),
            if (_intVal(dash['storesExpiringSoon']) > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDBA74)),
                ),
                child: Row(children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: _accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(tr('${tr('Có ')}${_intVal(dash['storesExpiringSoon'])} cửa hàng sắp hết hạn license — liên hệ khách hàng gia hạn sớm.'),
                      style: const TextStyle(fontSize: 13, color: _accent),
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 16),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.link, color: _accent, size: 20),
                    SizedBox(width: 8),
                    Text(tr('Link giới thiệu đăng ký cửa hàng'),
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600)),
                  ]),
                  const SizedBox(height: 8),
                  Text(tr('Gửi link cho khách hàng — cửa hàng đăng ký qua link sẽ tự thuộc quyền quản lý của bạn.'),
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  if (link != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(tr(link),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 12)),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () => _copyLink(link),
                      icon: const Icon(Icons.copy, size: 18),
                      label: Text(tr('Sao chép link')),
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE0F2FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(Icons.visibility_outlined,
                  size: 18, color: Color(0xFF0369A1)),
              SizedBox(width: 8),
              Expanded(
                child: Text(tr('Chế độ xem — đại lý theo dõi cửa hàng, thiết bị và license. Thao tác quản trị do SuperAdmin thực hiện.'),
                  style: TextStyle(fontSize: 12, color: Color(0xFF0369A1)),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _dashCard({
    required IconData icon,
    required Color color,
    required String title,
    required String value,
    required String subtitle,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Text(tr(value),
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(tr(title),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(tr(subtitle),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesTab() {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              TextField(
                controller: _deviceSearchCtrl,
                decoration: InputDecoration(
                  hintText: tr('Tìm serial, tên máy, cửa hàng...'),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadDevices,
                  ),
                ),
                onSubmitted: (_) => _loadDevices(),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(tr('Tất cả')),
                      selected: _deviceOnlineFilter == null,
                      onSelected: (_) {
                        setState(() => _deviceOnlineFilter = null);
                        _loadDevices();
                      },
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: Text(tr('Online')),
                      selected: _deviceOnlineFilter == true,
                      onSelected: (_) {
                        setState(() => _deviceOnlineFilter = true);
                        _loadDevices();
                      },
                    ),
                    const SizedBox(width: 6),
                    FilterChip(
                      label: Text(tr('Offline')),
                      selected: _deviceOnlineFilter == false,
                      onSelected: (_) {
                        setState(() => _deviceOnlineFilter = false);
                        _loadDevices();
                      },
                    ),
                    if (_stores.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _deviceStoreFilter,
                          hint: Text(tr('Cửa hàng')),
                          items: [
                            DropdownMenuItem<String?>(
                              value: null,
                              child: Text(tr('Tất cả CH')),
                            ),
                            ..._stores.map((s) => DropdownMenuItem<String?>(
                                  value: s['id']?.toString(),
                                  child: Text(
                                    tr(s['name']?.toString() ?? ''),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                )),
                          ],
                          onChanged: (v) {
                            setState(() => _deviceStoreFilter = v);
                            _loadDevices();
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _devicesLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadDevices,
                  child: _devices.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            SizedBox(height: 80),
                            Center(
                              child: Text(tr('Chưa có thiết bị tại cửa hàng thuộc đại lý'),
                                style: TextStyle(color: Color(0xFF64748B)),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(16),
                          itemCount: _devices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) => _buildDeviceCard(_devices[i]),
                        ),
                ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> d) {
    final online = d['isOnline'] == true;
    final lastSync = d['lastSyncAt']?.toString();
    String lastLabel = '—';
    if (lastSync != null) {
      final dt = DateTime.tryParse(lastSync);
      if (dt != null) {
        lastLabel = DateFormat('dd/MM/yyyy HH:mm').format(dt.toLocal());
      }
    }

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: online
              ? const Color(0xFFDCFCE7)
              : const Color(0xFFF1F5F9),
          child: Icon(
            Icons.router,
            color: online ? const Color(0xFF059669) : Colors.grey,
            size: 20,
          ),
        ),
        title: Text(
          tr(d['name']?.toString() ?? d['serialNumber']?.toString() ?? 'Thiết bị'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr('SN: ${d['serialNumber'] ?? '—'}'),
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            Text(
              tr('${d['storeName'] ?? '—'} · Sync: $lastLabel'),
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: online
                ? const Color(0xFFDCFCE7)
                : const Color(0xFFFEE2E2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            tr(online ? 'Online' : 'Offline'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: online ? const Color(0xFF059669) : const Color(0xFFDC2626),
            ),
          ),
        ),
        isThreeLine: true,
      ),
    );
  }

  String? profileCodeLink(String? code) {
    if (code == null || code.isEmpty) return null;
    return '${webAppBaseUrl(ApiService.baseUrl)}/#/register?agentCode=$code';
  }

  void _showStoreDetail(Map<String, dynamic> s) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(s['name']?.toString() ?? 'Gian hàng')),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailLine('Mã', s['code']),
              _detailLine('Gói DV', s['packageName']),
              _detailLine('Trạng thái', s['isLocked'] == true
                  ? 'Bị khóa'
                  : (s['isActive'] == true ? 'Hoạt động' : 'Ngừng')),
              if (s['expiryDate'] != null)
                _detailLine('Hết hạn', s['expiryDate']?.toString()),
              if (s['maxUsers'] != null)
                _detailLine('Max users', s['maxUsers']?.toString()),
              if (s['maxDevices'] != null)
                _detailLine('Max devices', s['maxDevices']?.toString()),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('Đóng')),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(tr(label),
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: Text(tr(value.toString()),
                style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildStoresTab() {
    if (_stores.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: 120),
            Center(
              child: Text(tr('Chưa có gian hàng nào thuộc đại lý'),
                  style: TextStyle(color: Color(0xFF64748B))),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _stores.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final s = _stores[i];
          final locked = s['isLocked'] == true;
          final active = s['isActive'] == true && !locked;
          return Card(
            child: ListTile(
              onTap: () => _showStoreDetail(s),
              leading: CircleAvatar(
                backgroundColor: const Color(0xFFE0F2FE),
                child: Icon(Icons.store,
                    color: locked ? Colors.red : const Color(0xFF0891B2),
                    size: 20),
              ),
              title: Text(tr(s['name']?.toString() ?? '')),
              subtitle: Text(tr('${tr('Mã: ')}${s['code'] ?? ''} · Gói: ${s['packageName'] ?? '—'}'),
              ),
              trailing: Chip(
                label: Text(
                  tr(locked ? 'Khóa' : (active ? 'Hoạt động' : 'Ngừng')),
                  style: const TextStyle(fontSize: 11),
                ),
                backgroundColor: locked
                    ? const Color(0xFFFEE2E2)
                    : (active
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFF1F5F9)),
              ),
            ),
          );
        },
      ),
    );
  }
}
