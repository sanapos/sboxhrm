import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../utils/report_access_utils.dart';
import '../widgets/hrm_page_chrome.dart';

const _theme = Color(0xFF7C3AED);

class PayrollReportScreen extends StatefulWidget {
  const PayrollReportScreen({super.key});

  @override
  State<PayrollReportScreen> createState() => _PayrollReportScreenState();
}

class _PayrollReportScreenState extends State<PayrollReportScreen> {
  final ApiService _api = ApiService();
  final _fmtMoney = NumberFormat('#,##0', 'vi_VN');
  int _year = DateTime.now().year;
  int _month = DateTime.now().month;
  bool _loading = false;
  String? _loadError;
  List<Map<String, dynamic>> _costByDept = [];
  List<Map<String, dynamic>> _statusItems = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final results = await Future.wait([
        _api.getPayrollCostByDepartment(year: _year, month: _month),
        _api.getPayrollStatusDistribution(year: _year, month: _month),
      ]);
      if (!mounted) return;
      String? err;
      List<Map<String, dynamic>> costs = [];
      List<Map<String, dynamic>> statuses = [];

      final costData = results[0]['data'];
      if (results[0]['isSuccess'] == true && costData is Map) {
        final items = costData['items'] ?? costData['departments'];
        if (items is List) {
          costs = items
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } else {
        err ??= results[0]['message']?.toString();
      }

      final statusParsed = parseReportListResponse(results[1], listKey: 'items');
      statuses = statusParsed.items;
      err ??= statusParsed.error;

      setState(() {
        _costByDept = costs;
        _statusItems = statuses;
        _loadError = err;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Không tải được báo cáo lương: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: const Text('Báo cáo lương'),
        backgroundColor: _theme,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _periodPicker(),
                  reportLoadErrorBanner(_loadError),
                  _sectionTitle('Chi phí lương theo phòng ban'),
                  _costCard(),
                  const SizedBox(height: 12),
                  _sectionTitle('Trạng thái phiếu lương'),
                  _statusCard(),
                ],
              ),
            ),
    );
  }

  Widget _periodPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _month,
              decoration: const InputDecoration(labelText: 'Tháng', isDense: true),
              items: List.generate(
                12,
                (i) => DropdownMenuItem(value: i + 1, child: Text('Tháng ${i + 1}')),
              ),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _month = v);
                _load();
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _year,
              decoration: const InputDecoration(labelText: 'Năm', isDense: true),
              items: List.generate(
                5,
                (i) {
                  final y = DateTime.now().year - 2 + i;
                  return DropdownMenuItem(value: y, child: Text('$y'));
                },
              ),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _year = v);
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _costCard() {
    if (_costByDept.isEmpty) {
      return _emptyCard('Chưa có dữ liệu chi phí lương tháng $_month/$_year');
    }
    return Card(
      child: Column(
        children: _costByDept.map((row) {
          final net = row['netSalary'] ?? row['totalNet'] ?? row['net'];
          return ListTile(
            dense: true,
            title: Text(row['department']?.toString() ?? '—'),
            subtitle: Text('${row['employeeCount'] ?? 0} nhân viên'),
            trailing: Text('${_fmtMoney.format(_toNum(net))} đ',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          );
        }).toList(),
      ),
    );
  }

  Widget _statusCard() {
    if (_statusItems.isEmpty) {
      return _emptyCard('Chưa có phiếu lương tháng $_month/$_year');
    }
    return Card(
      child: Column(
        children: _statusItems.map((row) {
          return ListTile(
            dense: true,
            title: Text(row['status']?.toString() ?? '—'),
            subtitle: Text('Net: ${_fmtMoney.format(_toNum(row['totalNet']))} đ'),
            trailing: Text('${row['count'] ?? 0}'),
          );
        }).toList(),
      ),
    );
  }

  double _toNum(dynamic v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString() ?? '') ?? 0;
  }

  Widget _emptyCard(String msg) => Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(msg, style: const TextStyle(color: Color(0xFF71717A))),
          ),
        ),
      );
}
