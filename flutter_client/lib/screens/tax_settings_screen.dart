import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

class TaxSettingsScreen extends StatefulWidget {
  const TaxSettingsScreen({super.key});

  @override
  State<TaxSettingsScreen> createState() => _TaxSettingsScreenState();
}

class _TaxSettingsScreenState extends State<TaxSettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // Personal deduction (Giảm trừ bản thân)
  final _personalDeductionController = TextEditingController(text: '11.000.000');
  
  // Dependent deduction (Giảm trừ người phụ thuộc)
  final _dependentDeductionController = TextEditingController(text: '4.400.000');
  
  // Progressive tax brackets - 7 levels
  final _bracket1AmountController = TextEditingController(text: '5.000.000');
  final _bracket1RateController = TextEditingController(text: '5');
  final _bracket2AmountController = TextEditingController(text: '10.000.000');
  final _bracket2RateController = TextEditingController(text: '10');
  final _bracket3AmountController = TextEditingController(text: '18.000.000');
  final _bracket3RateController = TextEditingController(text: '15');
  final _bracket4AmountController = TextEditingController(text: '32.000.000');
  final _bracket4RateController = TextEditingController(text: '20');
  final _bracket5AmountController = TextEditingController(text: '52.000.000');
  final _bracket5RateController = TextEditingController(text: '25');
  final _bracket6AmountController = TextEditingController(text: '80.000.000');
  final _bracket6RateController = TextEditingController(text: '30');
  final _bracket7RateController = TextEditingController(text: '35');

  // Employee tax deductions
  List<Map<String, dynamic>> _employeeDeductions = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    // Load tax settings
    try {
      final settings = await _apiService.getTaxSettings();
      if (mounted) {
        setState(() {
          _personalDeductionController.text = formatNumber(settings['personalDeduction'] ?? 11000000);
          _dependentDeductionController.text = formatNumber(settings['dependentDeduction'] ?? 4400000);
          _bracket1AmountController.text = formatNumber(settings['taxBracket1Max'] ?? 5000000);
          _bracket1RateController.text = settings['taxRate1']?.toString() ?? '5';
          _bracket2AmountController.text = formatNumber(settings['taxBracket2Max'] ?? 10000000);
          _bracket2RateController.text = settings['taxRate2']?.toString() ?? '10';
          _bracket3AmountController.text = formatNumber(settings['taxBracket3Max'] ?? 18000000);
          _bracket3RateController.text = settings['taxRate3']?.toString() ?? '15';
          _bracket4AmountController.text = formatNumber(settings['taxBracket4Max'] ?? 32000000);
          _bracket4RateController.text = settings['taxRate4']?.toString() ?? '20';
          _bracket5AmountController.text = formatNumber(settings['taxBracket5Max'] ?? 52000000);
          _bracket5RateController.text = settings['taxRate5']?.toString() ?? '25';
          _bracket6AmountController.text = formatNumber(settings['taxBracket6Max'] ?? 80000000);
          _bracket6RateController.text = settings['taxRate6']?.toString() ?? '30';
          _bracket7RateController.text = settings['taxRate7']?.toString() ?? '35';
        });
      }
    } catch (e) {
      debugPrint('Error loading tax settings: $e');
    }

    // Load employee deductions independently
    try {
      final deductions = await _apiService.getEmployeeTaxDeductions();
      debugPrint('Loaded ${deductions.length} employee deductions');
      if (mounted) {
        setState(() {
          _employeeDeductions = deductions.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading employee deductions: $e');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    final settings = {
      'personalDeduction': parseFormattedNumber(_personalDeductionController.text)?.toDouble() ?? 11000000,
      'dependentDeduction': parseFormattedNumber(_dependentDeductionController.text)?.toDouble() ?? 4400000,
      'taxBracket1Max': parseFormattedNumber(_bracket1AmountController.text)?.toDouble() ?? 5000000,
      'taxRate1': double.tryParse(_bracket1RateController.text) ?? 5,
      'taxBracket2Max': parseFormattedNumber(_bracket2AmountController.text)?.toDouble() ?? 10000000,
      'taxRate2': double.tryParse(_bracket2RateController.text) ?? 10,
      'taxBracket3Max': parseFormattedNumber(_bracket3AmountController.text)?.toDouble() ?? 18000000,
      'taxRate3': double.tryParse(_bracket3RateController.text) ?? 15,
      'taxBracket4Max': parseFormattedNumber(_bracket4AmountController.text)?.toDouble() ?? 32000000,
      'taxRate4': double.tryParse(_bracket4RateController.text) ?? 20,
      'taxBracket5Max': parseFormattedNumber(_bracket5AmountController.text)?.toDouble() ?? 52000000,
      'taxRate5': double.tryParse(_bracket5RateController.text) ?? 25,
      'taxBracket6Max': parseFormattedNumber(_bracket6AmountController.text)?.toDouble() ?? 80000000,
      'taxRate6': double.tryParse(_bracket6RateController.text) ?? 30,
      'taxRate7': double.tryParse(_bracket7RateController.text) ?? 35,
    };

    try {
      final response = await _apiService.saveTaxSettings(settings);
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: 'Đã lưu thiết lập thuế TNCN');
        } else {
          appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Lỗi khi lưu thiết lập');
        }
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: 'Lỗi: $e');
      }
    }
  }

  @override
  void dispose() {
    _personalDeductionController.dispose();
    _dependentDeductionController.dispose();
    _bracket1AmountController.dispose();
    _bracket1RateController.dispose();
    _bracket2AmountController.dispose();
    _bracket2RateController.dispose();
    _bracket3AmountController.dispose();
    _bracket3RateController.dispose();
    _bracket4AmountController.dispose();
    _bracket4RateController.dispose();
    _bracket5AmountController.dispose();
    _bracket5RateController.dispose();
    _bracket6AmountController.dispose();
    _bracket6RateController.dispose();
    _bracket7RateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 1200;
    final isMediumScreen = screenWidth >= 800 && screenWidth < 1200;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Thuế TNCN', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 18)),
        leading: Responsive.isMobile(context) ? null : IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Color(0xFF71717A)),
            onPressed: () {},
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF71717A).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.receipt_long, color: Color(0xFF71717A), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Thiết lập Thuế TNCN',
                            style: TextStyle(
                              color: Color(0xFF1E3A5F),
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Cấu hình biểu thuế lũy tiến và giảm trừ gia cảnh theo Luật thuế TNCN sửa đổi 2026',
                            style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
                          ),
                        ],
                      ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Main content - 3 columns
                  if (isWideScreen)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildDeductionCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildTaxBracketsCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildSummaryCard()),
                      ],
                    )
                  else if (isMediumScreen)
                    Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildDeductionCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildTaxBracketsCard()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildDeductionCard(),
                        const SizedBox(height: 16),
                        _buildTaxBracketsCard(),
                        const SizedBox(height: 16),
                        _buildSummaryCard(),
                      ],
                    ),

                  const SizedBox(height: 24),

                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saveSettings,
                      icon: const Icon(Icons.save, size: 20),
                      label: const Text('Lưu thiết lập thuế TNCN', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Employee Tax Deductions Table
                  _buildEmployeeDeductionsCard(),
                ],
              ),
            ),
    );
  }

  String _formatCurrency(dynamic value) {
    final amount = (value is num) ? value.toDouble() : (double.tryParse(value?.toString() ?? '0') ?? 0);
    if (amount == 0) return '0';
    final parts = amount.toStringAsFixed(0).split('');
    final buffer = StringBuffer();
    for (var i = 0; i < parts.length; i++) {
      if (i > 0 && (parts.length - i) % 3 == 0) buffer.write('.');
      buffer.write(parts[i]);
    }
    return buffer.toString();
  }

  // Employee Tax Deductions Card - row click to edit
  Widget _buildEmployeeDeductionsCard() {
    final personalDeduction = parseFormattedNumber(_personalDeductionController.text)?.toDouble() ?? 11000000;
    final dependentDeductionRate = parseFormattedNumber(_dependentDeductionController.text)?.toDouble() ?? 4400000;
    final isMobile = Responsive.isMobile(context);

    const headerStyle = TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 11);
    const cellStyle = TextStyle(color: Color(0xFF18181B), fontSize: 12);
    const mutedStyle = TextStyle(color: Color(0xFF71717A), fontSize: 12);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.all(isMobile ? 14 : 20),
            child: Row(
              children: [
                Container(
                  width: isMobile ? 40 : 48,
                  height: isMobile ? 40 : 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8B)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(Icons.people, color: Colors.white, size: isMobile ? 20 : 24),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Thiết lập người phụ thuộc theo nhân viên',
                        style: TextStyle(
                          color: const Color(0xFF18181B),
                          fontSize: isMobile ? 13 : 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Nhấn vào từng nhân viên để xem chi tiết và chỉnh sửa',
                        style: TextStyle(color: Colors.grey[500], fontSize: isMobile ? 11 : 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content: Cards on mobile, Table on desktop
          if (_employeeDeductions.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text('Chưa có nhân viên nào', style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 14)),
              ),
            )
          else if (isMobile)
            // Mobile: Deck list
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _employeeDeductions.length,
                  separatorBuilder: (_, __) => const Divider(height: 24, color: Color(0xFFE4E4E7)),
                  itemBuilder: (context, index) {
                    final emp = _employeeDeductions[index];
                    final numDependents = (emp['numberOfDependents'] ?? 0) as int;
                    final mandatoryIns = (emp['mandatoryInsurance'] is num)
                        ? (emp['mandatoryInsurance'] as num).toDouble()
                        : (double.tryParse(emp['mandatoryInsurance']?.toString() ?? '0') ?? 0);
                    final otherExempt = (emp['otherExemptions'] is num)
                        ? (emp['otherExemptions'] as num).toDouble()
                        : (double.tryParse(emp['otherExemptions']?.toString() ?? '0') ?? 0);
                    final dependentDeduction = numDependents * dependentDeductionRate;
                    final totalExemption = personalDeduction + dependentDeduction + mandatoryIns + otherExempt;

                    return InkWell(
                      onTap: () => _showEmployeeDeductionDialog(index),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: const Color(0xFF1E3A5F).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                            child: Center(child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(emp['employeeName'] ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text([emp['employeeCode'] ?? '', '$numDependents NPT', _formatCurrency(totalExemption)].where((s) => s.isNotEmpty).join(' \u00b7 '),
                                style: const TextStyle(color: Color(0xFF71717A), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ]),
                          ),
                          const Icon(Icons.chevron_right, size: 18, color: Color(0xFFA1A1AA)),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            )
          else
            // Desktop: Table
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 72),
                  child: Container(
                    width: 750,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE4E4E7)),
                    ),
                    child: Column(
                      children: [
                        // Table Header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1E3A5F),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(11),
                              topRight: Radius.circular(11),
                            ),
                          ),
                          child: const Row(
                        children: [
                          Expanded(flex: 1, child: Text('STT', style: headerStyle)),
                          Expanded(flex: 3, child: Text('Mã nhân viên', style: headerStyle)),
                          Expanded(flex: 4, child: Text('Họ tên', style: headerStyle)),
                          Expanded(flex: 3, child: Text('Giảm trừ bản thân', textAlign: TextAlign.right, style: headerStyle)),
                          Expanded(flex: 2, child: Text('Người phụ thuộc', textAlign: TextAlign.center, style: headerStyle)),
                          Expanded(flex: 3, child: Text('Giảm trừ người phụ thuộc', textAlign: TextAlign.right, style: headerStyle)),
                          Expanded(flex: 3, child: Text('Bảo hiểm bắt buộc', textAlign: TextAlign.right, style: headerStyle)),
                          Expanded(flex: 4, child: Text('Thu nhập miễn thuế', textAlign: TextAlign.right, style: headerStyle)),
                        ],
                      ),
                    ),
                    // Table Rows
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: Scrollbar(
                        thumbVisibility: true,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: _employeeDeductions.length,
                          itemBuilder: (context, index) {
                            final emp = _employeeDeductions[index];
                            final numDependents = (emp['numberOfDependents'] ?? 0) as int;
                            final mandatoryIns = (emp['mandatoryInsurance'] is num)
                                ? (emp['mandatoryInsurance'] as num).toDouble()
                                : (double.tryParse(emp['mandatoryInsurance']?.toString() ?? '0') ?? 0);
                            final otherExempt = (emp['otherExemptions'] is num)
                                ? (emp['otherExemptions'] as num).toDouble()
                                : (double.tryParse(emp['otherExemptions']?.toString() ?? '0') ?? 0);
                            final dependentDeduction = numDependents * dependentDeductionRate;
                            final totalExemption = personalDeduction + dependentDeduction + mandatoryIns + otherExempt;
                            final isAlt = index % 2 == 1;
                            final isLast = index == _employeeDeductions.length - 1;

                            return InkWell(
                              onTap: () => _showEmployeeDeductionDialog(index),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: isAlt ? const Color(0xFFFAFAFA) : Colors.white,
                                  borderRadius: isLast
                                      ? const BorderRadius.only(
                                          bottomLeft: Radius.circular(11),
                                          bottomRight: Radius.circular(11),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(flex: 1, child: Text('${index + 1}', style: mutedStyle)),
                                    Expanded(flex: 3, child: Text(emp['employeeCode'] ?? '', style: cellStyle.copyWith(fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 4, child: Text(emp['employeeName'] ?? '', style: cellStyle, overflow: TextOverflow.ellipsis)),
                                    Expanded(flex: 3, child: Text(_formatCurrency(personalDeduction), textAlign: TextAlign.right, style: mutedStyle)),
                                    Expanded(flex: 2, child: Text('$numDependents', textAlign: TextAlign.center, style: cellStyle)),
                                    Expanded(flex: 3, child: Text(_formatCurrency(dependentDeduction), textAlign: TextAlign.right, style: mutedStyle)),
                                    Expanded(flex: 3, child: Text(_formatCurrency(mandatoryIns), textAlign: TextAlign.right, style: mutedStyle)),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        _formatCurrency(totalExemption),
                                        textAlign: TextAlign.right,
                                        style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
            ),
        ],
      ),
    );
  }

  void _showEmployeeDeductionDialog(int index) {
    final emp = _employeeDeductions[index];
    final personalDeduction = parseFormattedNumber(_personalDeductionController.text)?.toDouble() ?? 11000000;
    final dependentDeductionRate = parseFormattedNumber(_dependentDeductionController.text)?.toDouble() ?? 4400000;

    final numDependents = (emp['numberOfDependents'] ?? 0) as int;
    final mandatoryIns = (emp['mandatoryInsurance'] is num)
        ? (emp['mandatoryInsurance'] as num).toDouble()
        : (double.tryParse(emp['mandatoryInsurance']?.toString() ?? '0') ?? 0);
    final otherExempt = (emp['otherExemptions'] is num)
        ? (emp['otherExemptions'] as num).toDouble()
        : (double.tryParse(emp['otherExemptions']?.toString() ?? '0') ?? 0);

    final nptCtrl = TextEditingController(text: '$numDependents');
    final insCtrl = TextEditingController(text: mandatoryIns > 0 ? _formatCurrency(mandatoryIns) : '0');
    final otherCtrl = TextEditingController(text: otherExempt > 0 ? _formatCurrency(otherExempt) : '0');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final npt = int.tryParse(nptCtrl.text) ?? 0;
          final ins = parseFormattedNumber(insCtrl.text)?.toDouble() ?? 0;
          final other = parseFormattedNumber(otherCtrl.text)?.toDouble() ?? 0;
          final depDeduction = npt * dependentDeductionRate;
          final total = personalDeduction + depDeduction + ins + other;

          final isMobile = Responsive.isMobile(ctx);
          return AlertDialog(
            insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person, color: Color(0xFF1E3A5F), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(emp['employeeName'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(emp['employeeCode'] ?? '', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Read-only info
                  _dialogInfoRow('Giảm trừ bản thân', _formatCurrency(personalDeduction)),
                  const Divider(height: 24),

                  // Editable fields
                  _dialogEditRow('Số người phụ thuộc', nptCtrl, setDialogState, isNumber: true),
                  const SizedBox(height: 8),
                  _dialogInfoRow('Giảm trừ NPT', _formatCurrency(depDeduction)),
                  const Divider(height: 24),
                  _dialogEditRow('BH bắt buộc', insCtrl, setDialogState),
                  const SizedBox(height: 8),
                  _dialogEditRow('Miễn thuế khác', otherCtrl, setDialogState),
                  const Divider(height: 24),

                  // Total
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Tổng TN miễn thuế', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(
                          '${_formatCurrency(total)} đ',
                          style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  _saveInlineEdit(
                    index,
                    numberOfDependents: int.tryParse(nptCtrl.text) ?? 0,
                    mandatoryInsurance: parseFormattedNumber(insCtrl.text)?.toDouble() ?? 0,
                    otherExemptions: parseFormattedNumber(otherCtrl.text)?.toDouble() ?? 0,
                  );
                },
                icon: const Icon(Icons.save, size: 18),
                label: const Text('Lưu'),
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _dialogInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Text('$value đ', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _dialogEditRow(String label, TextEditingController ctrl, void Function(void Function()) setDialogState, {bool isNumber = false}) {
    return Row(
      children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
        SizedBox(
          width: 150,
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 13),
            inputFormatters: isNumber ? null : [ThousandSeparatorFormatter()],
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixText: isNumber ? '' : 'đ',
              suffixStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
            onChanged: (_) => setDialogState(() {}),
          ),
        ),
      ],
    );
  }

  Future<void> _saveInlineEdit(int index, {int? numberOfDependents, double? mandatoryInsurance, double? otherExemptions}) async {
    final emp = _employeeDeductions[index];
    final data = {
      'employeeId': emp['employeeId'],
      'numberOfDependents': numberOfDependents ?? (emp['numberOfDependents'] ?? 0),
      'mandatoryInsurance': mandatoryInsurance ?? ((emp['mandatoryInsurance'] is num) ? (emp['mandatoryInsurance'] as num).toDouble() : (double.tryParse(emp['mandatoryInsurance']?.toString() ?? '0') ?? 0)),
      'otherExemptions': otherExemptions ?? ((emp['otherExemptions'] is num) ? (emp['otherExemptions'] as num).toDouble() : (double.tryParse(emp['otherExemptions']?.toString() ?? '0') ?? 0)),
    };
    final result = await _apiService.saveEmployeeTaxDeduction(data);
    if (result['isSuccess'] == true && mounted) {
      appNotification.showSuccess(title: 'Đã lưu', message: emp['employeeName'] ?? '');
      setState(() {
        _employeeDeductions[index]['numberOfDependents'] = data['numberOfDependents'];
        _employeeDeductions[index]['mandatoryInsurance'] = data['mandatoryInsurance'];
        _employeeDeductions[index]['otherExemptions'] = data['otherExemptions'];
      });
    } else if (mounted) {
      appNotification.showError(title: 'Lỗi', message: result['message'] ?? 'Không thể lưu');
    }
  }

  // Card Giảm trừ gia cảnh
  Widget _buildDeductionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 120,
                  height: 45,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3A5F), Color(0xFF60A5FA)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.bar_chart, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Giảm trừ gia cảnh',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Mức giảm trừ bản thân và người phụ thuộc',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                _buildDeductionField(
                  icon: Icons.person,
                  label: 'Giảm trừ bản thân',
                  description: 'Mức giảm trừ cho người nộp thuế',
                  controller: _personalDeductionController,
                  suffix: 'đ/tháng',
                ),
                const SizedBox(height: 20),
                _buildDeductionField(
                  icon: Icons.supervisor_account,
                  label: 'Giảm trừ người phụ thuộc',
                  description: 'Mức giảm trừ cho mỗi người phụ thuộc',
                  controller: _dependentDeductionController,
                  suffix: 'đ/người/tháng',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeductionField({
    required IconData icon,
    required String label,
    required String description,
    required TextEditingController controller,
    required String suffix,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF71717A), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w500, fontSize: 14)),
              const SizedBox(height: 2),
              Text(description, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 130,
          height: 40,
          child: TextField(
            controller: controller,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 14, fontWeight: FontWeight.w600),
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandSeparatorFormatter()],
            decoration: InputDecoration(
              suffixText: suffix.split('/').first,
              suffixStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1E3A5F), width: 2),
              ),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  // Card Biểu thuế lũy tiến từng phần
  Widget _buildTaxBracketsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 120,
                  height: 45,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.trending_up, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Biểu thuế lũy tiến từng phần',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '7 bậc thuế theo Luật thuế TNCN',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content - Tax brackets
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              children: [
                _buildBracketRow(1, 'Đến', _bracket1AmountController, _bracket1RateController),
                const SizedBox(height: 12),
                _buildBracketRow(2, 'Đến', _bracket2AmountController, _bracket2RateController),
                const SizedBox(height: 12),
                _buildBracketRow(3, 'Đến', _bracket3AmountController, _bracket3RateController),
                const SizedBox(height: 12),
                _buildBracketRow(4, 'Đến', _bracket4AmountController, _bracket4RateController),
                const SizedBox(height: 12),
                _buildBracketRow(5, 'Đến', _bracket5AmountController, _bracket5RateController),
                const SizedBox(height: 12),
                _buildBracketRow(6, 'Đến', _bracket6AmountController, _bracket6RateController),
                const SizedBox(height: 12),
                _buildBracketRow7(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBracketRow(int level, String prefix, TextEditingController amountController, TextEditingController rateController) {
    final colors = [
      const Color(0xFF1E3A5F), // Bracket 1
      const Color(0xFF1E3A5F), // Bracket 2
      const Color(0xFFF59E0B), // Bracket 3
      const Color(0xFFEF4444), // Bracket 4
      const Color(0xFF7C3AED), // Bracket 5
      const Color(0xFFEC4899), // Bracket 6
      const Color(0xFF0F2340), // Bracket 7
    ];
    final color = colors[level - 1];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            'BẬC $level',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        // Prefix
        Text(prefix, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        // Amount input
        SizedBox(
          width: 110,
          height: 36,
          child: TextField(
            controller: amountController,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 13, fontWeight: FontWeight.w600),
            keyboardType: TextInputType.number,
            inputFormatters: [ThousandSeparatorFormatter()],
            decoration: InputDecoration(
              suffixText: 'đ',
              suffixStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: color, width: 2),
              ),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Text('Thuế suất', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        // Rate input
        SizedBox(
          width: 70,
          height: 36,
          child: TextField(
            controller: rateController,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 13, fontWeight: FontWeight.w600),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: '%',
              suffixStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: BorderSide(color: color, width: 2),
              ),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  Widget _buildBracketRow7() {
    const color = Color(0xFF0F2340);
    final amount6 = parseFormattedNumber(_bracket6AmountController.text)?.toDouble() ?? 80000000;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Text(
            'BẬC 7',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        // Fixed text
        Text('Trên', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        // Fixed amount display
        Container(
          width: 110,
          height: 36,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE4E4E7)),
          ),
          child: Text(
            '${formatNumber(amount6)}đ',
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ),
        Text('Thuế suất', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        // Rate input
        SizedBox(
          width: 70,
          height: 36,
          child: TextField(
            controller: _bracket7RateController,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 13, fontWeight: FontWeight.w600),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: '%',
              suffixStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: color, width: 2),
              ),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
      ],
    );
  }

  // Card Bảng biểu thuế TNCN
  Widget _buildSummaryCard() {
    final amount1 = parseFormattedNumber(_bracket1AmountController.text)?.toDouble() ?? 5000000;
    final amount2 = parseFormattedNumber(_bracket2AmountController.text)?.toDouble() ?? 10000000;
    final amount3 = parseFormattedNumber(_bracket3AmountController.text)?.toDouble() ?? 18000000;
    final amount4 = parseFormattedNumber(_bracket4AmountController.text)?.toDouble() ?? 32000000;
    final amount5 = parseFormattedNumber(_bracket5AmountController.text)?.toDouble() ?? 52000000;
    final amount6 = parseFormattedNumber(_bracket6AmountController.text)?.toDouble() ?? 80000000;
    final rate1 = double.tryParse(_bracket1RateController.text) ?? 5;
    final rate2 = double.tryParse(_bracket2RateController.text) ?? 10;
    final rate3 = double.tryParse(_bracket3RateController.text) ?? 15;
    final rate4 = double.tryParse(_bracket4RateController.text) ?? 20;
    final rate5 = double.tryParse(_bracket5RateController.text) ?? 25;
    final rate6 = double.tryParse(_bracket6RateController.text) ?? 30;
    final rate7 = double.tryParse(_bracket7RateController.text) ?? 35;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 120,
                  height: 45,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1E3A5F), Color(0xFF2D5F8B)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.table_chart, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bảng biểu thuế TNCN',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Tóm tắt 7 bậc thuế lũy tiến',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Summary Table
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE4E4E7)),
              ),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFF1E3A5F),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(11),
                        topRight: Radius.circular(11),
                      ),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(width: 40, child: Text('Bậc', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                        Expanded(child: Text('Thu nhập tính thuế/tháng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                        SizedBox(width: 70, child: Text('Thuế suất', textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                  // Table Rows
                  _buildSummaryRow(1, 'Đến ${_formatMillion(amount1)} triệu', rate1, false),
                  _buildSummaryRow(2, 'Trên ${_formatMillion(amount1)} - ${_formatMillion(amount2)} triệu', rate2, true),
                  _buildSummaryRow(3, 'Trên ${_formatMillion(amount2)} - ${_formatMillion(amount3)} triệu', rate3, false),
                  _buildSummaryRow(4, 'Trên ${_formatMillion(amount3)} - ${_formatMillion(amount4)} triệu', rate4, true),
                  _buildSummaryRow(5, 'Trên ${_formatMillion(amount4)} - ${_formatMillion(amount5)} triệu', rate5, false),
                  _buildSummaryRow(6, 'Trên ${_formatMillion(amount5)} - ${_formatMillion(amount6)} triệu', rate6, true),
                  _buildSummaryRow(7, 'Trên ${_formatMillion(amount6)} triệu', rate7, false, isLast: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(int level, String range, double rate, bool isAlt, {bool isLast = false}) {
    final colors = [
      const Color(0xFF1E3A5F),
      const Color(0xFF1E3A5F),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF7C3AED),
      const Color(0xFFEC4899),
      const Color(0xFF0F2340),
    ];
    final color = colors[level - 1];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isAlt ? const Color(0xFFFAFAFA) : Colors.white,
        borderRadius: isLast
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(11),
                bottomRight: Radius.circular(11),
              )
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                '$level',
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(range, style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
          ),
          Text(
            '${rate.toStringAsFixed(rate == rate.toInt() ? 0 : 1)}%',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ],
      ),
    );
  }

  String _formatMillion(double amount) {
    return (amount / 1000000).toStringAsFixed(0);
  }
}
