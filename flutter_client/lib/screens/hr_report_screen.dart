import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/report_access_utils.dart';
import '../widgets/hrm_page_chrome.dart';

const _theme = Color(0xFF7C3AED);

class HrReportScreen extends StatefulWidget {
  const HrReportScreen({super.key});

  @override
  State<HrReportScreen> createState() => _HrReportScreenState();
}

class _HrReportScreenState extends State<HrReportScreen> {
  final ApiService _api = ApiService();
  int _year = DateTime.now().year;
  bool _loading = false;
  String? _loadError;
  Map<String, dynamic> _headcount = {};
  Map<String, dynamic> _org = {};
  List<Map<String, dynamic>> _contracts = [];

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
        _api.getHrHeadcountMovement(year: _year),
        _api.getHrOrgHeadcount(),
        _api.getHrContractExpiry(days: 90),
      ]);
      if (!mounted) return;
      String? err;
      Map<String, dynamic> headcount = {};
      Map<String, dynamic> org = {};
      List<Map<String, dynamic>> contracts = [];

      if (results[0]['isSuccess'] == true && results[0]['data'] is Map) {
        headcount = Map<String, dynamic>.from(results[0]['data'] as Map);
      } else {
        err ??= results[0]['message']?.toString();
      }
      if (results[1]['isSuccess'] == true && results[1]['data'] is Map) {
        org = Map<String, dynamic>.from(results[1]['data'] as Map);
      } else {
        err ??= results[1]['message']?.toString();
      }
      final contractParsed = parseReportListResponse(
        results[2],
        listKey: 'items',
      );
      contracts = contractParsed.items;
      err ??= contractParsed.error;

      setState(() {
        _headcount = headcount;
        _org = org;
        _contracts = contracts;
        _loadError = err;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = 'Không tải được báo cáo nhân sự: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HrmPageChrome.background,
      appBar: AppBar(
        title: const Text('Báo cáo nhân sự'),
        backgroundColor: _theme,
        foregroundColor: Colors.white,
        actions: [
          if (Provider.of<PermissionProvider>(context, listen: false)
              .canExport('HrReport'))
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _yearPicker(),
                  reportLoadErrorBanner(_loadError),
                  _sectionTitle('Biến động nhân sự $_year'),
                  _headcountCard(),
                  const SizedBox(height: 12),
                  _sectionTitle('Cơ cấu tổ chức'),
                  _orgCard(),
                  const SizedBox(height: 12),
                  _sectionTitle('Hợp đồng sắp hết hạn (90 ngày)'),
                  _contractsList(),
                ],
              ),
            ),
    );
  }

  Widget _yearPicker() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Row(
        children: [
          const Text('Năm:', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 12),
          DropdownButton<int>(
            value: _year,
            items: List.generate(5, (i) {
              final y = DateTime.now().year - 2 + i;
              return DropdownMenuItem(value: y, child: Text('$y'));
            }),
            onChanged: (v) {
              if (v == null) return;
              setState(() => _year = v);
              _load();
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );

  Widget _headcountCard() {
    final months = (_headcount['months'] as List?) ?? [];
    if (months.isEmpty) {
      return _emptyCard('Chưa có dữ liệu biến động nhân sự');
    }
    return Card(
      child: Column(
        children: months.take(12).map((m) {
          final row = Map<String, dynamic>.from(m as Map);
          return ListTile(
            dense: true,
            title: Text('Tháng ${row['month'] ?? ''}'),
            subtitle: Text(
              'Tuyển: ${row['hired'] ?? 0} · Nghỉ: ${row['resigned'] ?? 0} · Cuối kỳ: ${row['endingHeadcount'] ?? 0}',
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _orgCard() {
    final items = (_org['items'] as List?) ?? (_org['departments'] as List?) ?? [];
    if (items.isEmpty) {
      return _emptyCard('Chưa có dữ liệu cơ cấu tổ chức');
    }
    return Card(
      child: Column(
        children: items.map((e) {
          final row = Map<String, dynamic>.from(e as Map);
          return ListTile(
            dense: true,
            title: Text(row['department']?.toString() ?? row['name']?.toString() ?? '—'),
            trailing: Text('${row['count'] ?? row['headcount'] ?? 0} NV'),
          );
        }).toList(),
      ),
    );
  }

  Widget _contractsList() {
    if (_contracts.isEmpty) {
      return _emptyCard('Không có hợp đồng sắp hết hạn trong 90 ngày');
    }
    return Card(
      child: Column(
        children: _contracts.map((row) {
          final exp = row['expiryDate'] ?? row['endDate'];
          final expDt = exp != null ? DateTime.tryParse(exp.toString()) : null;
          return ListTile(
            dense: true,
            title: Text(row['employeeName']?.toString() ?? row['fullName']?.toString() ?? '—'),
            subtitle: Text(row['department']?.toString() ?? ''),
            trailing: Text(
              expDt != null ? DateFormat('dd/MM/yyyy').format(expDt) : '',
              style: const TextStyle(fontSize: 12),
            ),
          );
        }).toList(),
      ),
    );
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
