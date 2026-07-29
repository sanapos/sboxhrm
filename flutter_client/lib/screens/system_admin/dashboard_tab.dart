import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../widgets/admin/admin_mobile_widgets.dart';
import 'system_admin_helpers.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
import 'package:zkteco_flutter_client/l10n/app_ui_locale.dart';

class DashboardTab extends StatefulWidget {
  final bool agentMode;
  final VoidCallback? onLoaded;
  final VoidCallback? onNavigateToStores;
  final VoidCallback? onNavigateToUsers;
  final VoidCallback? onNavigateToDevices;
  final VoidCallback? onNavigateToAgents;
  final VoidCallback? onNavigateToLicenses;

  const DashboardTab({
    super.key,
    this.agentMode = false,
    this.onLoaded,
    this.onNavigateToStores,
    this.onNavigateToUsers,
    this.onNavigateToDevices,
    this.onNavigateToAgents,
    this.onNavigateToLicenses,
  });

  @override
  State<DashboardTab> createState() => DashboardTabState();
}

class DashboardTabState extends State<DashboardTab> {
  final ApiService _apiService = ApiService();
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _health;
  bool _isLoading = false;

  // Date filter
  late DateTime _fromDate;
  late DateTime _toDate;
  String _selectedPeriod = 'today'; // today, 7days, 30days, custom

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDate = DateTime(now.year, now.month, now.day);
    _toDate = DateTime(now.year, now.month, now.day);
    loadData();
  }

  String _formatDateParam(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic>? get dashboardData => _dashboard;

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    try {
      if (widget.agentMode) {
        final results = await Future.wait([
          _apiService.getAgentDashboard(
            fromDate: _formatDateParam(_fromDate),
            toDate: _formatDateParam(_toDate),
          ),
          _apiService.getAgentStores(pageSize: 5),
        ]);
        if (!mounted) return;
        if (results[0]['isSuccess'] == true) {
          final d = Map<String, dynamic>.from(results[0]['data'] as Map);
          setState(() => _dashboard = {
                'totalStores': d['storeCount'] ?? 0,
                'activeStores': d['activeStores'] ?? 0,
                'inactiveStores': d['inactiveStores'] ?? 0,
                'lockedStores': d['lockedStores'] ?? 0,
                'totalUsers': d['totalUsers'] ?? 0,
                'totalDevices': d['totalDevices'] ?? 0,
                'onlineDevices': d['onlineDevices'] ?? 0,
                'offlineDevices': d['offlineDevices'] ?? 0,
                'totalLicenseKeys': d['totalKeys'] ?? 0,
                'usedLicenseKeys': d['usedKeys'] ?? 0,
                'availableLicenseKeys': d['availableKeys'] ?? 0,
                'totalAgents': 1,
                'agentName': d['agentName'],
                'agentCode': d['agentCode'],
                'storesExpiringSoon': d['storesExpiringSoon'] ?? 0,
                'todayAttendances': d['todayAttendances'] ?? 0,
                'totalAttendanceToday': d['todayAttendances'] ?? 0,
                'storesCreatedInPeriod': d['storesCreatedInPeriod'] ?? 0,
                'keysActivatedInPeriod': d['keysActivatedInPeriod'] ?? 0,
                'keysCreatedInPeriod': d['keysCreatedInPeriod'] ?? 0,
                'usersCreatedInPeriod': d['usersCreatedInPeriod'] ?? 0,
                'storeAttendances': d['storeAttendances'] ?? const [],
                'recentActivities': d['recentActivities'] ?? const [],
                'recentStores':
                    AdminHelpers.extractList(results[1]['data']),
              });
        } else {
          AdminHelpers.showApiError(context, results[0]);
        }
        setState(() => _health = null);
      } else {
        final results = await Future.wait([
          _apiService.getSystemAdminDashboard(
            fromDate: _formatDateParam(_fromDate),
            toDate: _formatDateParam(_toDate),
          ),
          _apiService.getSystemHealth(),
          _apiService.getSystemStores(pageSize: 5),
        ]);
        if (!mounted) return;
        if (results[0]['isSuccess'] == true) {
          final data = results[0]['data'] as Map<String, dynamic>? ?? {};
          if (results[2]['isSuccess'] == true) {
            data['recentStores'] =
                AdminHelpers.extractList(results[2]['data']);
          }
          setState(() => _dashboard = data);
        } else {
          AdminHelpers.showApiError(context, results[0]);
        }
        if (results[1]['isSuccess'] == true) {
          setState(() => _health = results[1]['data']);
        }
      }
    } catch (e) {
      debugPrint('DashboardTab error: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
      widget.onLoaded?.call();
    }
  }

  void _setPeriod(String period) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    setState(() {
      _selectedPeriod = period;
      switch (period) {
        case 'today':
          _fromDate = today;
          _toDate = today;
          break;
        case '7days':
          _fromDate = today.subtract(const Duration(days: 6));
          _toDate = today;
          break;
        case '30days':
          _fromDate = today.subtract(const Duration(days: 29));
          _toDate = today;
          break;
      }
    });
    loadData();
  }

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _fromDate, end: _toDate),
      locale: appUiLocale(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AdminHelpers.primary,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _fromDate = picked.start;
        _toDate = picked.end;
      });
      loadData();
    }
  }

  String get _periodLabel {
    final fmt = DateFormat('dd/MM/yyyy');
    if (_selectedPeriod == 'today') return 'Hôm nay';
    if (_selectedPeriod == '7days') return '7 ngày qua';
    if (_selectedPeriod == '30days') return '30 ngày qua';
    return '${fmt.format(_fromDate)} - ${fmt.format(_toDate)}';
  }

  Map<String, dynamic>? get healthData => _health;

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _dashboard == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_dashboard == null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.shield, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(tr('Không thể tải dữ liệu dashboard'),
            style: TextStyle(color: Colors.grey[500])),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: loadData,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(tr('Thử lại'))),
      ]));
    }
    return RefreshIndicator(
      onRefresh: loadData,
      child: Stack(
        children: [
          SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: adminTabPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with refresh
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    Icon(Icons.touch_app, size: 16, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Text(tr('Nhấn vào thẻ số liệu để xem chi tiết'),
                        style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 12,
                            fontStyle: FontStyle.italic)),
                    const Spacer(),
                  ]),
                ),
                // Overall stats
                _buildStatRow(),
                const SizedBox(height: 24),
                // Date filter section
                _buildDateFilter(),
                const SizedBox(height: 16),
                // Period report cards
                _buildPeriodReportCards(),
                const SizedBox(height: 20),
                // Recent activities (notifications)
                _buildRecentActivities(),
                const SizedBox(height: 20),
                // Two-column layout for health and recent stores
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth > 900) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(children: [
                              if (_health != null) _buildHealthCard(),
                              const SizedBox(height: 16),
                              _buildSystemResourceCard(),
                            ]),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 7,
                            child: _buildRecentStoresPreview(),
                          ),
                        ],
                      );
                    }
                    return Column(children: [
                      if (_health != null) _buildHealthCard(),
                      const SizedBox(height: 16),
                      _buildSystemResourceCard(),
                      const SizedBox(height: 16),
                      _buildRecentStoresPreview(),
                    ]);
                  },
                ),
              ],
            ),
          ),
          if (_isLoading)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
                ),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDateFilter() {
    final mobile = adminUseMobileLayout(context);
    final chipData = <({String label, String? period, bool custom})>[
      (label: 'Hôm nay', period: 'today', custom: false),
      (label: '7 ngày qua', period: '7days', custom: false),
      (label: '30 ngày qua', period: '30days', custom: false),
      (
        label: _selectedPeriod == 'custom' ? _periodLabel : 'Tùy chọn ngày',
        period: null,
        custom: true,
      ),
    ];

    return Container(
      padding: EdgeInsets.all(mobile ? 12 : 16),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.date_range,
                color: AdminHelpers.primary, size: 20),
            const SizedBox(width: 10),
            Text(tr('Báo cáo: '),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.grey[700])),
          ]),
          const SizedBox(height: 10),
          if (mobile)
            Column(
              children: [
                for (final item in chipData) ...[
                  _buildFullWidthPeriodChip(
                    label: item.label,
                    period: item.period,
                    isCustom: item.custom,
                  ),
                  if (item != chipData.last) const SizedBox(height: 8),
                ],
              ],
            )
          else
            Row(children: [
              const SizedBox(width: 30),
              for (var i = 0; i < chipData.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                chipData[i].custom
                    ? ActionChip(
                        avatar: Icon(Icons.calendar_month,
                            size: 16,
                            color: _selectedPeriod == 'custom'
                                ? Colors.white
                                : AdminHelpers.primary),
                        label: Text(
                          tr(chipData[i].label),
                          style: TextStyle(
                            fontSize: 12,
                            color: _selectedPeriod == 'custom'
                                ? Colors.white
                                : Colors.grey[700],
                          ),
                        ),
                        backgroundColor: _selectedPeriod == 'custom'
                            ? AdminHelpers.primary
                            : Colors.grey[100],
                        side: BorderSide(
                          color: _selectedPeriod == 'custom'
                              ? AdminHelpers.primary
                              : Colors.grey.shade300,
                        ),
                        onPressed: _pickCustomRange,
                      )
                    : _periodChip(
                        chipData[i].label,
                        chipData[i].period!,
                      ),
              ],
            ]),
        ],
      ),
    );
  }

  Widget _buildFullWidthPeriodChip({
    required String label,
    required String? period,
    required bool isCustom,
  }) {
    final selected = isCustom
        ? _selectedPeriod == 'custom'
        : _selectedPeriod == period;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: selected ? AdminHelpers.primary : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: isCustom ? _pickCustomRange : () => _setPeriod(period!),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? AdminHelpers.primary : Colors.grey.shade300,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isCustom ? Icons.calendar_month : Icons.event,
                  size: 18,
                  color: selected ? Colors.white : AdminHelpers.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    tr(label),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? Colors.white : Colors.grey[800],
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle,
                      size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _periodChip(String label, String period) {
    final selected = _selectedPeriod == period;
    return ChoiceChip(
      label: Text(tr(label), style: TextStyle(fontSize: 12,
          color: selected ? Colors.white : Colors.grey[700])),
      selected: selected,
      selectedColor: AdminHelpers.primary,
      backgroundColor: Colors.grey[100],
      side: BorderSide(
          color: selected ? AdminHelpers.primary : Colors.grey.shade300),
      onSelected: (_) => _setPeriod(period),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildPeriodReportCards() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.insights,
                color: AdminHelpers.primary, size: 20),
            const SizedBox(width: 8),
            Text(tr('Thống kê theo khoảng thời gian'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.grey[800])),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AdminHelpers.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tr(_periodLabel),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AdminHelpers.primary)),
            ),
          ]),
          const SizedBox(height: 16),
          _buildPeriodReportCardsContent(),
        ],
      ),
    );
  }

  Widget _buildPeriodReportCardsContent() {
    final mobile = adminUseMobileLayout(context);
    final cards = [
      _buildReportCard(
        'CH tạo mới',
        _dashboard?['storesCreatedInPeriod'] ?? 0,
        Icons.add_business,
        AdminHelpers.success,
        onTap: widget.onNavigateToStores,
      ),
      _buildReportCard(
        'Key kích hoạt',
        _dashboard?['keysActivatedInPeriod'] ?? 0,
        Icons.key,
        const Color(0xFFE65100),
        onTap: widget.onNavigateToLicenses,
      ),
      _buildReportCard(
        'Key tạo mới',
        _dashboard?['keysCreatedInPeriod'] ?? 0,
        Icons.vpn_key_outlined,
        AdminHelpers.info,
        onTap: widget.onNavigateToLicenses,
      ),
      _buildReportCard(
        'User tạo mới',
        _dashboard?['usersCreatedInPeriod'] ?? 0,
        Icons.person_add,
        AdminHelpers.primaryDark,
        onTap: widget.onNavigateToUsers,
      ),
    ];
    if (mobile) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: cards,
    );
  }

  Widget _buildReportCard(
      String label, dynamic value, IconData icon, Color color,
      {VoidCallback? onTap}) {
    final count = value is int ? value : 0;
    final mobile = adminUseMobileLayout(context);
    return SizedBox(
      width: mobile ? double.infinity : 200,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: color.withValues(alpha: 0.04),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.3)),
              color: color.withValues(alpha: 0.04),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('$count'),
                          style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: color)),
                      Text(tr(label),
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 12)),
                    ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow() {
    final mobile = adminUseMobileLayout(context);
    final cards = [
        _buildStatCard(
          'Cửa hàng',
          '${_dashboard?['totalStores'] ?? 0}',
          Icons.store,
          AdminHelpers.primary,
          sub: '${_dashboard?['activeStores'] ?? 0} hoạt động',
          onTap: widget.onNavigateToStores,
        ),
        _buildStatCard(
          'Người dùng',
          '${_dashboard?['totalUsers'] ?? 0}',
          Icons.people,
          AdminHelpers.primaryDark,
          onTap: widget.onNavigateToUsers,
        ),
        _buildStatCard(
          'Thiết bị',
          '${_dashboard?['totalDevices'] ?? 0}',
          Icons.router,
          AdminHelpers.info,
          sub: '${_dashboard?['onlineDevices'] ?? 0} online',
          onTap: widget.onNavigateToDevices,
        ),
        if (!widget.agentMode)
          _buildStatCard(
            'Đại lý',
            '${_dashboard?['totalAgents'] ?? 0}',
            Icons.support_agent,
            AdminHelpers.warning,
            onTap: widget.onNavigateToAgents,
          ),
        _buildStatCard(
          'Chấm công hôm nay',
          '${_dashboard?['totalAttendanceToday'] ?? _dashboard?['todayAttendances'] ?? 0}',
          Icons.fingerprint,
          AdminHelpers.primary,
          onTap: _showAttendanceTodayDetail,
        ),
        _buildStatCard(
          'License',
          '${_dashboard?['totalLicenseKeys'] ?? _dashboard?['totalLicenses'] ?? 0}',
          Icons.vpn_key,
          AdminHelpers.primaryDark,
          sub:
              '${_dashboard?['usedLicenseKeys'] ?? _dashboard?['activeLicenses'] ?? 0} đã dùng',
          onTap: widget.onNavigateToLicenses,
        ),
    ];
    if (mobile) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            cards[i],
            if (i < cards.length - 1) const SizedBox(height: 10),
          ],
        ],
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: cards,
    );
  }

  Widget _buildStatCard(
      String label, String value, IconData icon, Color color,
      {String? sub, VoidCallback? onTap}) {
    final mobile = adminUseMobileLayout(context);
    return SizedBox(
      width: mobile ? double.infinity : 220,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          hoverColor: color.withValues(alpha: 0.04),
          splashColor: color.withValues(alpha: 0.1),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border(left: BorderSide(color: color, width: 4)),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.1), blurRadius: 10)
              ],
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(value),
                          style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: color)),
                      Text(tr(label),
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 12)),
                      if (sub != null)
                        Text(tr(sub),
                            style: TextStyle(
                                color: Colors.grey[500], fontSize: 11)),
                    ]),
              ),
              Icon(Icons.arrow_forward_ios,
                  size: 14, color: Colors.grey[400]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildHealthCard() {
    final checks = _health?['checks'] as List? ?? [];
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.monitor_heart,
                color: AdminHelpers.primary, size: 20),
            const SizedBox(width: 8),
            Text(tr('System Health'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey[800])),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _health?['status'] == 'Healthy'
                    ? AdminHelpers.success.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                    _health?['status'] == 'Healthy'
                        ? Icons.check_circle
                        : Icons.warning,
                    size: 14,
                    color: _health?['status'] == 'Healthy'
                        ? AdminHelpers.success
                        : Colors.orange),
                const SizedBox(width: 4),
                Text(tr(_health?['status'] ?? 'N/A'),
                    style: TextStyle(
                        color: _health?['status'] == 'Healthy'
                            ? AdminHelpers.success
                            : Colors.orange,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          if (checks.isNotEmpty)
            ...checks.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(children: [
                    Icon(
                        c['status'] == 'Healthy'
                            ? Icons.check_circle
                            : Icons.warning,
                        size: 16,
                        color: c['status'] == 'Healthy'
                            ? AdminHelpers.success
                            : Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(tr(c['name'] ?? ''),
                            style: TextStyle(
                                color: Colors.grey[700], fontSize: 13))),
                    Text(tr(c['status'] ?? ''),
                        style: TextStyle(
                            color: c['status'] == 'Healthy'
                                ? AdminHelpers.success
                                : Colors.orange,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ]),
                )),
          if (checks.isEmpty)
            Row(children: [
              Icon(
                  _health?['status'] == 'Healthy'
                      ? Icons.check_circle
                      : Icons.warning,
                  size: 20,
                  color: _health?['status'] == 'Healthy'
                      ? AdminHelpers.success
                      : Colors.orange),
              const SizedBox(width: 8),
              Text(tr('${tr('Trạng thái: ')}${_health?['status'] ?? 'N/A'}'),
                  style: TextStyle(color: Colors.grey[700])),
            ]),
        ],
      ),
    );
  }

  Widget _buildSystemResourceCard() {
    final totalDevices = _dashboard?['totalDevices'] ?? 0;
    final onlineDevices = _dashboard?['onlineDevices'] ?? 0;
    final offlineDevices = _dashboard?['offlineDevices'] ??
        (totalDevices is int && onlineDevices is int
            ? totalDevices - onlineDevices
            : 0);
    final onlineRatio = totalDevices > 0 ? onlineDevices / totalDevices : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.bar_chart,
                color: AdminHelpers.info, size: 20),
            const SizedBox(width: 8),
            Text(tr('Tình trạng thiết bị'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey[800])),
          ]),
          const SizedBox(height: 16),
          // Progress bar for online/offline ratio
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(tr('Online: $onlineDevices / $totalDevices'),
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[700])),
                  Text(tr('${(onlineRatio * 100).toStringAsFixed(0)}%'),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AdminHelpers.success)),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: onlineRatio,
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      AdminHelpers.success),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                _legendDot(AdminHelpers.success, 'Online ($onlineDevices)'),
                const SizedBox(width: 16),
                _legendDot(Colors.grey, 'Offline ($offlineDevices)'),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3))),
      const SizedBox(width: 6),
      Text(tr(label), style: TextStyle(fontSize: 12, color: Colors.grey[600])),
    ]);
  }

  Widget _buildRecentStoresPreview() {
    final storeStats = _dashboard?['recentStores'] as List? ?? [];
    final totalStores = _dashboard?['totalStores'] ?? 0;
    final activeStores = _dashboard?['activeStores'] ?? 0;
    final lockedStores = _dashboard?['lockedStores'] ?? 0;
    final inactiveStores =
        totalStores is int && activeStores is int
            ? totalStores - activeStores
            : 0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.analytics,
                color: AdminHelpers.primary, size: 20),
            const SizedBox(width: 8),
            Text(tr('Tổng quan nhanh'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.grey[800])),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onNavigateToStores,
              icon: const Icon(Icons.store, size: 16),
              label:
                  Text(tr('Xem tất cả'), style: TextStyle(fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 12, runSpacing: 8, children: [
            AdminHelpers.countBadge(
                'Hoạt động', activeStores is int ? activeStores : 0,
                AdminHelpers.success),
            if (inactiveStores > 0)
              AdminHelpers.countBadge('Tạm tắt', inactiveStores, Colors.grey),
            if (lockedStores != null && (lockedStores as num) > 0)
              AdminHelpers.countBadge(
                  'Bị khóa', lockedStores is int ? lockedStores : 0,
                  AdminHelpers.danger),
          ]),
          if (storeStats.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(tr('Cửa hàng gần đây'),
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.grey[700])),
            const SizedBox(height: 10),
            ...storeStats.take(5).map((s) {
              final store = s is Map ? s : {};
              final name = store['name'] ?? store['storeName'] ?? 'N/A';
              final isActive = store['isActive'] as bool? ?? true;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AdminHelpers.surfaceBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: InkWell(
                  onTap: widget.onNavigateToStores,
                  child: Row(children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isActive
                            ? AdminHelpers.success
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(tr(name.toString()),
                            style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13))),
                    if (store['userCount'] != null ||
                        store['totalUsers'] != null)
                      _miniStat(Icons.people,
                          '${store['userCount'] ?? store['totalUsers'] ?? 0}'),
                    const SizedBox(width: 8),
                    if (store['deviceCount'] != null ||
                        store['totalDevices'] != null)
                      _miniStat(Icons.router,
                          '${store['deviceCount'] ?? store['totalDevices'] ?? 0}'),
                  ]),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _miniStat(IconData icon, String value) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: Colors.grey[500]),
      const SizedBox(width: 3),
      Text(tr(value), style: TextStyle(fontSize: 11, color: Colors.grey[600])),
    ]);
  }

  Widget _buildRecentActivities() {
    final activities = _dashboard?['recentActivities'] as List? ?? [];
    if (activities.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AdminHelpers.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.notifications_active,
                color: AdminHelpers.warning, size: 20),
            const SizedBox(width: 8),
            Text(tr('Thông báo hoạt động'),
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.grey[800])),
            const Spacer(),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AdminHelpers.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(tr('${activities.length} mục'),
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AdminHelpers.warning)),
            ),
          ]),
          const SizedBox(height: 14),
          ...activities.take(15).map((a) {
            final activity = a is Map<String, dynamic> ? a : <String, dynamic>{};
            final type = activity['activityType']?.toString() ?? '';
            final desc = activity['description']?.toString() ?? '';
            final storeName = activity['storeName']?.toString();
            final createdAt = activity['createdAt']?.toString();
            final isStore = type == 'StoreCreated';
            final icon = isStore ? Icons.add_business : Icons.vpn_key;
            final color = isStore ? AdminHelpers.success : const Color(0xFFE65100);

            String timeStr = '';
            if (createdAt != null) {
              try {
                final dt = DateTime.parse(createdAt).toLocal();
                timeStr = DateFormat('dd/MM HH:mm').format(dt);
              } catch (_) {}
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8)),
                    child: Icon(icon, color: color, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(desc),
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (storeName != null && !isStore)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(tr('Cửa hàng: $storeName'),
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[500])),
                          ),
                      ],
                    ),
                  ),
                  if (timeStr.isNotEmpty)
                    Text(tr(timeStr),
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500])),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  void _showAttendanceTodayDetail() {
    final stores = _dashboard?['storeAttendances'] as List? ?? [];
    final total = _dashboard?['todayAttendances'] ?? 0;
    final isMobile = MediaQuery.of(context).size.width < 768;

    final titleRow = Row(children: [
      Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: AdminHelpers.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.fingerprint,
            color: AdminHelpers.primary, size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Chấm công hôm nay'),
              style: TextStyle(fontSize: 16)),
          Text(tr('Tổng: $total lượt'),
              style:
                  TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      )),
    ]);

    Widget buildStoreList({double? height}) {
      if (stores.isEmpty) {
        return SizedBox(
          height: height ?? 100,
          child: Center(
            child: Text(tr('Chưa có dữ liệu chấm công hôm nay'),
                style: TextStyle(color: Colors.grey[500])),
          ),
        );
      }
      return SizedBox(
        height: height,
        child: ListView.builder(
          shrinkWrap: height == null,
          itemCount: stores.length,
          itemBuilder: (ctx, i) {
            final s = stores[i] is Map ? stores[i] : {};
            final name = s['storeName'] ??
                s['name'] ??
                'Cửa hàng ${i + 1}';
            final count =
                s['count'] ?? s['attendanceCount'] ?? 0;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AdminHelpers.surfaceBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: AdminHelpers.primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6)),
                  child: const Icon(Icons.store,
                      color: AdminHelpers.primary, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(tr(name.toString()),
                        style: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13))),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AdminHelpers.primary
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8)),
                  child: Text(tr('$count lượt'),
                      style: const TextStyle(
                          color: AdminHelpers.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13)),
                ),
              ]),
            );
          },
        ),
      );
    }

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
                title: Text(tr('Chấm công hôm nay')),
              ),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleRow,
                    const SizedBox(height: 16),
                    Expanded(child: buildStoreList()),
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
        builder: (ctx) => ScrollableAlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: titleRow,
          content: SizedBox(
            width: 500,
            height: stores.isEmpty
                ? 100
                : (stores.length * 60.0).clamp(100, 400),
            child: buildStoreList(
              height: stores.isEmpty
                  ? 100
                  : (stores.length * 60.0).clamp(100, 400),
            ),
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
}
