import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../utils/web_route_parser.dart';
import 'agent_license_keys_screen.dart';

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

  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _stores = [];
  String? _referralLink;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
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
        _api.getAgentStores(),
        _api.getAgentReferralLink(),
      ]);
      if (!mounted) return;
      if (results[0]['isSuccess'] == true) {
        _profile = Map<String, dynamic>.from(results[0]['data'] as Map);
      }
      if (results[1]['isSuccess'] == true) {
        _stores = List<Map<String, dynamic>>.from(results[1]['data'] ?? []);
      }
      if (results[2]['isSuccess'] == true) {
        _referralLink = (results[2]['data'] as Map?)?['referralLink']?.toString();
      }
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Bạn có chắc muốn đăng xuất khỏi cổng đại lý?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await Provider.of<AuthProvider>(context, listen: false).logout();
  }

  void _copyLink(String link) {
    Clipboard.setData(ClipboardData(text: link));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã sao chép link')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final email = auth.currentUser?.email ?? 'Đại lý';
    final profile = _profile;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF334155)],
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
                              const Text(
                                'Cổng đại lý',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                profile?['name']?.toString() ?? email,
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
                          label: const Text('Đăng xuất',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                  if (profile != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                      child: Row(
                        children: [
                          _statChip('Cửa hàng',
                              '${profile['storeCount'] ?? 0}/${profile['maxStores'] ?? 0}'),
                          const SizedBox(width: 8),
                          _statChip('Key còn',
                              '${profile['availableKeys'] ?? 0}'),
                          const SizedBox(width: 8),
                          _statChip('Mã', profile['code']?.toString() ?? ''),
                        ],
                      ),
                    ),
                  TabBar(
                    controller: _tabs,
                    indicatorColor: Colors.white,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    tabs: const [
                      Tab(text: 'Tổng quan'),
                      Tab(text: 'Gian hàng'),
                      Tab(text: 'License Key'),
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
                    ? Center(child: Text('Lỗi: $_error'))
                    : TabBarView(
                        controller: _tabs,
                        children: [
                          _buildOverviewTab(),
                          _buildStoresTab(),
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
        '$label: $value',
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _buildOverviewTab() {
    final link = _referralLink ??
        (profileCodeLink(_profile?['code']?.toString()));
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Link giới thiệu đăng ký cửa hàng',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text(
                  'Gửi link này cho khách hàng. Cửa hàng đăng ký qua link sẽ thuộc quyền quản lý của bạn.',
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
                    child: SelectableText(link,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _copyLink(link),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Sao chép link'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text('License key khả dụng: ${_profile?['availableKeys'] ?? 0}'),
            subtitle: Text('Đã dùng: ${_profile?['usedKeys'] ?? 0} / Tổng: ${_profile?['totalKeys'] ?? 0}'),
            trailing: TextButton(
              onPressed: () => _tabs.animateTo(2),
              child: const Text('Xem'),
            ),
          ),
        ),
      ],
    );
  }

  String? profileCodeLink(String? code) {
    if (code == null || code.isEmpty) return null;
    return '${webAppBaseUrl(ApiService.baseUrl)}/#/register?agentCode=$code';
  }

  Widget _buildStoresTab() {
    if (_stores.isEmpty) {
      return const Center(
        child: Text('Chưa có gian hàng nào thuộc đại lý',
            style: TextStyle(color: Color(0xFF64748B))),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _stores.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final s = _stores[i];
        final locked = s['isLocked'] == true;
        final active = s['isActive'] == true && !locked;
        return Card(
          child: ListTile(
            title: Text(s['name']?.toString() ?? ''),
            subtitle: Text(
              'Mã: ${s['code'] ?? ''} · Gói: ${s['packageName'] ?? '—'}',
            ),
            trailing: Chip(
              label: Text(
                locked ? 'Khóa' : (active ? 'Hoạt động' : 'Ngừng'),
                style: const TextStyle(fontSize: 11),
              ),
              backgroundColor: locked
                  ? const Color(0xFFFEE2E2)
                  : (active ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9)),
            ),
          ),
        );
      },
    );
  }
}
