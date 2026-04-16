import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class PayslipScreen extends StatefulWidget {
  const PayslipScreen({super.key});

  @override
  State<PayslipScreen> createState() => _PayslipScreenState();
}

class _PayslipScreenState extends State<PayslipScreen> with SingleTickerProviderStateMixin {
  final ApiService _apiService = ApiService();
  late TabController _tabController;
  bool _isLoading = false;

  List<Map<String, dynamic>> _myPayslips = [];
  Map<String, dynamic>? _selectedPayslip;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getMyPayslips();
      if (res['isSuccess'] == true) {
        setState(() => _myPayslips = List<Map<String, dynamic>>.from(res['data'] ?? []));
      }
    } catch (e) {
      debugPrint('Error loading payslips: $e');
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadPayslipDetail(String id) async {
    final res = await _apiService.getPayslipById(id);
    if (res['isSuccess'] == true) {
      setState(() {
        _selectedPayslip = res['data'];
        _tabController.animateTo(1);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          TabBar(
            controller: _tabController,
            labelColor: const Color(0xFF059669),
            unselectedLabelColor: Colors.grey[600],
            indicatorColor: const Color(0xFF059669),
            indicatorWeight: 3,
            tabs: const [
              Tab(icon: Icon(Icons.list_alt), text: 'Phiếu lương'),
              Tab(icon: Icon(Icons.receipt_long), text: 'Chi tiết'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPayslipList(),
                      _buildPayslipDetail(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF059669), Color(0xFF1E3A5F)]),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.receipt_long, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Phiếu lương', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Xem chi tiết phiếu lương hàng tháng', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayslipList() {
    if (_myPayslips.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Chưa có phiếu lương', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _myPayslips.length,
        itemBuilder: (ctx, i) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildPayslipDeckItem(_myPayslips[i]),
          ),
        ),
      ),
    );
  }

  Widget _buildPayslipDeckItem(Map<String, dynamic> payslip) {
    final netSalary = payslip['netSalary'] ?? payslip['totalAmount'] ?? 0;
    final month = payslip['month'];
    final year = payslip['year'];
    final monthDisplay = month != null && year != null ? 'T${month.toString().padLeft(2, '0')}/$year' : (payslip['payPeriod'] ?? '');
    final status = payslip['statusName']?.toString() ?? payslip['status']?.toString() ?? 'Draft';
    final isPaid = status == 'Paid';
    final statusColor = isPaid ? const Color(0xFF1E3A5F) : const Color(0xFFF59E0B);
    return InkWell(
      onTap: () => _loadPayslipDetail(payslip['id']?.toString() ?? ''),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF059669), Color(0xFF1E3A5F)]),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.receipt, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Phiếu lương $monthDisplay', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(_formatDate(payslip['createdAt']), style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                ],
              ),
            ),
            Text(_formatCurrency(netSalary), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF059669))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(isPaid ? 'Đã TT' : 'Chưa TT', style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  Widget _buildPayslipDetail() {
    if (_selectedPayslip == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('Chọn phiếu lương để xem chi tiết', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
          ],
        ),
      );
    }
    final p = _selectedPayslip!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Summary card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF059669), Color(0xFF1E3A5F)]),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                const Text('LƯƠNG THỰC NHẬN', style: TextStyle(color: Colors.white70, fontSize: 14, letterSpacing: 1)),
                const SizedBox(height: 8),
                Text(_formatCurrency(p['netSalary'] ?? 0), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text('Kỳ lương: T${p['month']?.toString().padLeft(2, '0') ?? ''}/${p['year'] ?? ''}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _buildDetailSection('Thu nhập', Icons.add_circle, const Color(0xFF1E3A5F), [
            _detailRow('Lương cơ bản', p['baseSalary']),
            _detailRow('Phụ cấp', p['allowances']),
            _detailRow('Thưởng', p['bonus']),
            _detailRow('Tăng ca', p['overtimePay']),
            _detailRow('Tổng thu nhập (Gross)', p['grossSalary']),
          ]),
          const SizedBox(height: 16),
          _buildDetailSection('Khấu trừ', Icons.remove_circle, const Color(0xFFEF4444), [
            _detailRow('BHXH', p['socialInsurance']),
            _detailRow('BHYT', p['healthInsurance']),
            _detailRow('BHTN', p['unemploymentInsurance']),
            _detailRow('Thuế TNCN', p['tax']),
            _detailRow('Khấu trừ khác', p['deductions']),
          ]),
        ],
      ),
    );
  }

  Widget _buildDetailSection(String title, IconData icon, Color color, List<Widget> rows) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 15)),
            ]),
          ),
          const Divider(height: 24),
          ...rows,
        ],
      ),
    );
  }

  Widget _detailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[700])),
          Text(_formatCurrency(value ?? 0), style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '';
    try { return DateFormat('dd/MM/yyyy').format(DateTime.parse(date.toString())); } catch (_) { return date.toString(); }
  }

  String _formatCurrency(dynamic amount) {
    try {
      final n = amount is num ? amount : num.tryParse(amount.toString()) ?? 0;
      return '${NumberFormat('#,###', 'vi_VN').format(n)}đ';
    } catch (_) {
      return '0đ';
    }
  }
}
