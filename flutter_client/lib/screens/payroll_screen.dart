import 'package:flutter/material.dart';
import '../models/attendance.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import 'attendance/payroll_summary_tab.dart';
import 'main_layout.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';

/// Màn hình Tổng hợp lương
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final ApiService _apiService = ApiService();
  final GlobalKey<PayrollSummaryTabState> _payrollTabKey = GlobalKey();

  List<Attendance> _attendances = [];
  List<Device> _devices = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    ScreenRefreshNotifier.payroll.addListener(_onExternalRefresh);
  }

  void _onExternalRefresh() {
    if (mounted) {
      _loadData();
    }
  }

  @override
  void dispose() {
    ScreenRefreshNotifier.payroll.removeListener(_onExternalRefresh);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final deviceList = await _apiService.getDevices(storeOnly: true);
      final parsedDevices = deviceList
          .map((d) => Device.fromJson(d as Map<String, dynamic>))
          .toList();
      final deviceIds = parsedDevices.map((d) => d.id).toList();

      List<Attendance> allAttendances = [];
      if (deviceIds.isNotEmpty) {
        final now = DateTime.now();
        final fromDate = DateTime(now.year, now.month, 1);
        int page = 1;
        const pageSize = 200;
        while (true) {
          final result = await _apiService.getAttendances(
            deviceIds: deviceIds,
            fromDate: fromDate,
            toDate: now,
            page: page,
            pageSize: pageSize,
          );
          final items = (result['items'] as List?) ?? [];
          allAttendances.addAll(
            items.map((a) => Attendance.fromJson(a as Map<String, dynamic>)),
          );
          if (items.length < pageSize) break;
          page++;
        }
      }

      if (mounted) {
        setState(() {
          _devices = parsedDevices;
          _attendances = allAttendances;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading payroll data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isMobile = Responsive.isMobile(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      body: Column(
        children: [
          // ═══ Gradient Header ═══
          Container(
            padding: EdgeInsets.fromLTRB(isMobile ? 14 : 24, isMobile ? 12 : 18, isMobile ? 14 : 24, isMobile ? 12 : 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Theme.of(context).primaryColor,
                  Theme.of(context).primaryColor.withValues(alpha: 0.85),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(isMobile ? 8 : 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.payments, color: Colors.white, size: isMobile ? 18 : 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Tổng hợp lương',
                        style: TextStyle(color: Colors.white, fontSize: isMobile ? 16 : 20, fontWeight: FontWeight.bold)),
                      if (!isMobile)
                        Text('Bảng lương chi tiết nhân viên',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13)),
                    ],
                  ),
                ),
                if (isMobile)
                  PopupMenuButton<String>(
                    icon: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.more_vert, size: 18, color: Colors.white),
                    ),
                    onSelected: (v) {
                      if (v == 'excel') _payrollTabKey.currentState?.exportToExcel();
                      if (v == 'png') _payrollTabKey.currentState?.exportToPng();
                      if (v == 'cols') _payrollTabKey.currentState?.showColumnSelectorDialog();
                    },
                    itemBuilder: (_) => [
                      if (Provider.of<PermissionProvider>(context, listen: false).canExport('Payroll'))
                      const PopupMenuItem(value: 'excel', child: Row(children: [Icon(Icons.table_chart_outlined, size: 18), SizedBox(width: 10), Text('Xuất Excel')])),
                      if (Provider.of<PermissionProvider>(context, listen: false).canExport('Payroll'))
                      const PopupMenuItem(value: 'png', child: Row(children: [Icon(Icons.image_outlined, size: 18), SizedBox(width: 10), Text('Xuất PNG')])),
                      const PopupMenuItem(value: 'cols', child: Row(children: [Icon(Icons.view_column_outlined, size: 18), SizedBox(width: 10), Text('Chọn cột')])),
                    ],
                  )
                else ...[
                  if (Provider.of<PermissionProvider>(context, listen: false).canExport('Payroll')) ...[
                  _buildHeaderActionBtn(Icons.table_chart_outlined, 'Excel', () {
                    _payrollTabKey.currentState?.exportToExcel();
                  }),
                  const SizedBox(width: 8),
                  _buildHeaderActionBtn(Icons.image_outlined, 'PNG', () {
                    _payrollTabKey.currentState?.exportToPng();
                  }),
                  const SizedBox(width: 8),
                  ],
                  _buildHeaderActionBtn(Icons.view_column_outlined, 'Cột', () {
                    _payrollTabKey.currentState?.showColumnSelectorDialog();
                  }),
                ],
              ],
            ),
          ),
          // ═══ Content ═══
          Expanded(
            child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : PayrollSummaryTab(
                  key: _payrollTabKey,
                  attendances: _attendances,
                  devices: _devices,
                  fromDate: DateTime(now.year, now.month, 1),
                  toDate: now,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderActionBtn(IconData icon, String label, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}
