import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../services/api_service.dart';
import '../utils/number_formatter.dart';
import '../utils/pit_tax_utils.dart';
import '../utils/responsive_helper.dart';
import '../widgets/loading_widget.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/pos/pos_theme.dart';
import '../widgets/notification_overlay.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

class TaxSettingsScreen extends StatefulWidget {
  const TaxSettingsScreen({super.key});

  @override
  State<TaxSettingsScreen> createState() => _TaxSettingsScreenState();
}

class _TaxSettingsScreenState extends State<TaxSettingsScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  String _employeeSearch = '';

  // Personal deduction (Giảm trừ bản thân)
  final _personalDeductionController = TextEditingController(
      text: tr(formatNumber(PitTaxDefaults.personalDeduction)));

  // Dependent deduction (Giảm trừ người phụ thuộc)
  final _dependentDeductionController = TextEditingController(
      text: tr(formatNumber(PitTaxDefaults.dependentDeduction)));

  // Progressive tax brackets — 5 levels (2026)
  final _bracket1AmountController = TextEditingController(
      text: tr(formatNumber(PitTaxDefaults.bracket1Max)));
  final _bracket1RateController =
      TextEditingController(text: tr('${PitTaxDefaults.rate1.toInt()}'));
  final _bracket2AmountController = TextEditingController(
      text: tr(formatNumber(PitTaxDefaults.bracket2Max)));
  final _bracket2RateController =
      TextEditingController(text: tr('${PitTaxDefaults.rate2.toInt()}'));
  final _bracket3AmountController = TextEditingController(
      text: tr(formatNumber(PitTaxDefaults.bracket3Max)));
  final _bracket3RateController =
      TextEditingController(text: tr('${PitTaxDefaults.rate3.toInt()}'));
  final _bracket4AmountController = TextEditingController(
      text: tr(formatNumber(PitTaxDefaults.bracket4Max)));
  final _bracket4RateController =
      TextEditingController(text: tr('${PitTaxDefaults.rate4.toInt()}'));
  final _bracket5RateController =
      TextEditingController(text: tr('${PitTaxDefaults.rate5.toInt()}'));

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
          _personalDeductionController.text = formatNumber(
              settings['personalDeduction'] ?? PitTaxDefaults.personalDeduction);
          _dependentDeductionController.text = formatNumber(
              settings['dependentDeduction'] ??
                  PitTaxDefaults.dependentDeduction);
          _bracket1AmountController.text = formatNumber(
              settings['taxBracket1Max'] ?? PitTaxDefaults.bracket1Max);
          _bracket1RateController.text =
              settings['taxRate1']?.toString() ?? '${PitTaxDefaults.rate1.toInt()}';
          _bracket2AmountController.text = formatNumber(
              settings['taxBracket2Max'] ?? PitTaxDefaults.bracket2Max);
          _bracket2RateController.text =
              settings['taxRate2']?.toString() ?? '${PitTaxDefaults.rate2.toInt()}';
          _bracket3AmountController.text = formatNumber(
              settings['taxBracket3Max'] ?? PitTaxDefaults.bracket3Max);
          _bracket3RateController.text =
              settings['taxRate3']?.toString() ?? '${PitTaxDefaults.rate3.toInt()}';
          _bracket4AmountController.text = formatNumber(
              settings['taxBracket4Max'] ?? PitTaxDefaults.bracket4Max);
          _bracket4RateController.text =
              settings['taxRate4']?.toString() ?? '${PitTaxDefaults.rate4.toInt()}';          // Bậc 5 = trên bậc 4: ưu tiên taxRate5, fallback taxRate7 (schema cũ).
          _bracket5RateController.text = (settings['taxRate5'] ??
                  settings['taxRate7'] ??
                  PitTaxDefaults.rate5)
              .toString();
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
    final b4 = parseFormattedNumber(_bracket4AmountController.text)?.toDouble() ??
        PitTaxDefaults.bracket4Max;
    final r5 = double.tryParse(_bracket5RateController.text) ?? PitTaxDefaults.rate5;
    final settings = {
      'personalDeduction': parseFormattedNumber(_personalDeductionController.text)
              ?.toDouble() ??
          PitTaxDefaults.personalDeduction,
      'dependentDeduction':
          parseFormattedNumber(_dependentDeductionController.text)?.toDouble() ??
              PitTaxDefaults.dependentDeduction,
      'taxBracket1Max':
          parseFormattedNumber(_bracket1AmountController.text)?.toDouble() ??
              PitTaxDefaults.bracket1Max,
      'taxRate1':
          double.tryParse(_bracket1RateController.text) ?? PitTaxDefaults.rate1,
      'taxBracket2Max':
          parseFormattedNumber(_bracket2AmountController.text)?.toDouble() ??
              PitTaxDefaults.bracket2Max,
      'taxRate2':
          double.tryParse(_bracket2RateController.text) ?? PitTaxDefaults.rate2,
      'taxBracket3Max':
          parseFormattedNumber(_bracket3AmountController.text)?.toDouble() ??
              PitTaxDefaults.bracket3Max,
      'taxRate3':
          double.tryParse(_bracket3RateController.text) ?? PitTaxDefaults.rate3,
      'taxBracket4Max': b4,
      'taxRate4':
          double.tryParse(_bracket4RateController.text) ?? PitTaxDefaults.rate4,
      // Cột 5–7 schema cũ: không tạo thêm bậc — trùng ngưỡng bậc 4, suất = bậc 5.
      'taxBracket5Max': b4,
      'taxRate5': r5,
      'taxBracket6Max': b4,
      'taxRate6': r5,
      'taxRate7': r5,
    };

    try {
      final response = await _apiService.saveTaxSettings(settings);
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: tr('Đã lưu thiết lập thuế TNCN'));
        } else {
          appNotification.showError(title: 'Lỗi', message: response['message'] ?? 'Lỗi khi lưu thiết lập');
        }
      }
    } catch (e) {
      if (mounted) {
        appNotification.showError(title: 'Lỗi', message: tr('Lỗi: $e'));
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
    _bracket5RateController.dispose();
    super.dispose();
  }

  Widget _buildSaveSettingsButton() {
    if (!_perm.canEdit('Tax')) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: _saveSettings,
        icon: const Icon(Icons.save, size: 20),
        label: Text(tr('Lưu thiết lập thuế TNCN'),
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: HrmPageChrome.primaryNavy,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 1200;
    final isMediumScreen = screenWidth >= 800 && screenWidth < 1200;

    return Scaffold(
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: HrmPageChrome.appBar(title: 'Thuế TNCN'),
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: HrmSettingsMobileKit.active(context)
                  ? HrmSettingsMobileKit.pagePadding(context)
                  : EdgeInsets.all(Responsive.isMobile(context) ? 12 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (HrmPageChrome.isEmbedded) ...[
                    _buildSaveSettingsButton(),
                    const SizedBox(height: 16),
                  ],
                  if (!HrmPageChrome.isEmbedded) ...[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF71717A).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.receipt_long,
                              color: Color(0xFF71717A), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(tr('Thiết lập Thuế TNCN'),
                                style: TextStyle(
                                  color: HrmPageChrome.primaryNavy,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(tr('Cấu hình biểu thuế lũy tiến và giảm trừ gia cảnh theo Luật thuế TNCN sửa đổi 2026'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: Color(0xFF71717A), fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],

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

                  if (!HrmPageChrome.isEmbedded) ...[
                    const SizedBox(height: 24),
                    _buildSaveSettingsButton(),
                  ],

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

  // Employee Tax Deductions — gọn: tìm + chỉnh NPT nhanh
  List<Map<String, dynamic>> get _filteredEmployeeDeductions {
    final q = _employeeSearch.trim().toLowerCase();
    if (q.isEmpty) return _employeeDeductions;
    return _employeeDeductions.where((e) {
      final name = (e['employeeName'] ?? '').toString().toLowerCase();
      final code = (e['employeeCode'] ?? '').toString().toLowerCase();
      return name.contains(q) || code.contains(q);
    }).toList();
  }

  Widget _buildEmployeeDeductionsCard() {
    final personalDeduction = parseFormattedNumber(_personalDeductionController.text)
            ?.toDouble() ??
        PitTaxDefaults.personalDeduction;
    final dependentDeductionRate =
        parseFormattedNumber(_dependentDeductionController.text)?.toDouble() ??
            PitTaxDefaults.dependentDeduction;
    final filtered = _filteredEmployeeDeductions;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.people_outline,
                    color: HrmPageChrome.primaryNavy, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Người phụ thuộc theo nhân viên'),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      Text(
                        tr('Chỉnh số NPT tại chỗ · bấm tên để sửa BH / miễn khác'),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
                Text(tr('${filtered.length} NV'),
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF71717A))),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _employeeSearch = v),
              decoration: InputDecoration(
                hintText: tr('Tìm tên hoặc mã NV…'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                ),
              ),
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(tr('Không có nhân viên'),
                    style: const TextStyle(color: Color(0xFFA1A1AA))),
              ),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                itemCount: filtered.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFF4F4F5)),
                itemBuilder: (context, i) {
                  final emp = filtered[i];
                  final index = _employeeDeductions.indexOf(emp);
                  final npt = (emp['numberOfDependents'] ?? 0) as int;
                  final total = personalDeduction +
                      npt * dependentDeductionRate +
                      ((emp['mandatoryInsurance'] as num?)?.toDouble() ?? 0) +
                      ((emp['otherExemptions'] as num?)?.toDouble() ?? 0);
                  return ListTile(
                    dense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    onTap: () => _showEmployeeDeductionDialog(index),
                    title: Text(tr(emp['employeeName']?.toString() ?? ''),
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                      tr([
                        emp['employeeCode']?.toString() ?? '',
                        '$npt NPT',
                        'GT ${_formatCurrency(total)}',
                        if ((emp['dependentRegistrationFormUrl']
                                    ?.toString() ??
                                '')
                            .isNotEmpty)
                          'có phiếu',
                        if (_parseDependentDocs(emp['dependentDocumentsJson'])
                            .isNotEmpty)
                          'có hồ sơ',
                      ].where((s) => s.isNotEmpty).join(' · ')),
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF71717A)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('Giảm NPT'),
                          onPressed: !_perm.canEdit('Tax') || npt <= 0
                              ? null
                              : () => _saveInlineEdit(index,
                                  numberOfDependents: npt - 1),
                          icon: const Icon(Icons.remove_circle_outline,
                              size: 20),
                        ),
                        SizedBox(
                          width: 28,
                          child: Text('$npt',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: tr('Thêm NPT'),
                          onPressed: !_perm.canEdit('Tax')
                              ? null
                              : () => _saveInlineEdit(index,
                                  numberOfDependents: npt + 1),
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  void _showEmployeeDeductionDialog(int index) {
    final emp = _employeeDeductions[index];
    final personalDeduction = parseFormattedNumber(_personalDeductionController.text)?.toDouble() ?? PitTaxDefaults.personalDeduction;
    final dependentDeductionRate = parseFormattedNumber(_dependentDeductionController.text)?.toDouble() ?? PitTaxDefaults.dependentDeduction;

    final numDependents = (emp['numberOfDependents'] ?? 0) as int;
    final mandatoryIns = (emp['mandatoryInsurance'] is num)
        ? (emp['mandatoryInsurance'] as num).toDouble()
        : (double.tryParse(emp['mandatoryInsurance']?.toString() ?? '0') ?? 0);
    final otherExempt = (emp['otherExemptions'] is num)
        ? (emp['otherExemptions'] as num).toDouble()
        : (double.tryParse(emp['otherExemptions']?.toString() ?? '0') ?? 0);

    final nptCtrl = TextEditingController(text: tr('$numDependents'));
    final insCtrl = TextEditingController(text: tr(mandatoryIns > 0 ? _formatCurrency(mandatoryIns) : '0'));
    final otherCtrl = TextEditingController(text: tr(otherExempt > 0 ? _formatCurrency(otherExempt) : '0'));

    var registrationUrl =
        emp['dependentRegistrationFormUrl']?.toString() ?? '';
    var documents = _parseDependentDocs(emp['dependentDocumentsJson']);
    var uploading = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          final npt = int.tryParse(nptCtrl.text) ?? 0;
          final ins = parseFormattedNumber(insCtrl.text)?.toDouble() ?? 0;
          final other = parseFormattedNumber(otherCtrl.text)?.toDouble() ?? 0;
          final depDeduction = npt * dependentDeductionRate;
          final total = personalDeduction + depDeduction + ins + other;

          Future<void> pickAndUpload({required bool isRegistration}) async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
              withData: true,
            );
            if (result == null || result.files.isEmpty) return;
            final file = result.files.first;
            final bytes = file.bytes;
            if (bytes == null || bytes.isEmpty) {
              appNotification.showError(
                  title: 'Lỗi', message: tr('Không đọc được file'));
              return;
            }
            setDialogState(() => uploading = true);
            final up = await _apiService.uploadFile(
              bytes,
              file.name,
              folder: 'tax/dependents',
            );
            setDialogState(() => uploading = false);
            if (up['isSuccess'] != true) {
              appNotification.showError(
                  title: 'Lỗi',
                  message: up['message']?.toString() ?? 'Upload thất bại');
              return;
            }
            final data = up['data'];
            final path = data is Map
                ? (data['filePath'] ?? data['fileUrl'] ?? data['url'])
                    ?.toString()
                : null;
            if (path == null || path.isEmpty) {
              appNotification.showError(
                  title: 'Lỗi', message: tr('Upload không trả về đường dẫn'));
              return;
            }
            setDialogState(() {
              if (isRegistration) {
                registrationUrl = path;
              } else {
                documents = [
                  ...documents,
                  {
                    'fileName': file.name,
                    'url': path,
                    'note': '',
                    'uploadedAt': DateTime.now().toIso8601String(),
                  },
                ];
              }
            });
          }

          final isMobile = Responsive.isMobile(ctx);
          return ScrollableAlertDialog(
            insetPadding: isMobile ? EdgeInsets.zero : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(isMobile ? 0 : 16)),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.person, color: HrmPageChrome.primaryNavy, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr(emp['employeeName'] ?? ''), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(tr(emp['employeeCode'] ?? ''), style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: isMobile ? double.infinity : 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _dialogInfoRow('Giảm trừ bản thân', _formatCurrency(personalDeduction)),
                  const Divider(height: 24),
                  _dialogEditRow('Số người phụ thuộc', nptCtrl, setDialogState, isNumber: true),
                  const SizedBox(height: 8),
                  _dialogInfoRow('Giảm trừ NPT', _formatCurrency(depDeduction)),
                  const Divider(height: 24),
                  _dialogEditRow('BH bắt buộc', insCtrl, setDialogState),
                  const SizedBox(height: 8),
                  _dialogEditRow('Miễn thuế khác', otherCtrl, setDialogState),
                  const Divider(height: 24),
                  Text(tr('Phiếu đăng ký người phụ thuộc'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  if (registrationUrl.isNotEmpty)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.description_outlined, size: 20),
                      title: Text(tr('Đã có phiếu đăng ký'),
                          style: const TextStyle(fontSize: 12)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: tr('Xem'),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            onPressed: () => _openUploadedPath(registrationUrl),
                          ),
                          IconButton(
                            tooltip: tr('Xóa'),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            onPressed: () =>
                                setDialogState(() => registrationUrl = ''),
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: uploading
                        ? null
                        : () => pickAndUpload(isRegistration: true),
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: Text(tr(registrationUrl.isEmpty
                        ? 'Tải phiếu đăng ký (PDF/ảnh)'
                        : 'Đổi phiếu đăng ký')),
                  ),
                  const SizedBox(height: 12),
                  Text(tr('Hồ sơ giấy tờ NPT'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  ...documents.asMap().entries.map((e) {
                    final i = e.key;
                    final doc = e.value;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.attach_file, size: 18),
                      title: Text(tr(doc['fileName']?.toString() ?? 'Tài liệu'),
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: tr('Xem'),
                            icon: const Icon(Icons.open_in_new, size: 18),
                            onPressed: () =>
                                _openUploadedPath(doc['url']?.toString() ?? ''),
                          ),
                          IconButton(
                            tooltip: tr('Xóa'),
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => setDialogState(() {
                              documents = [...documents]..removeAt(i);
                            }),
                          ),
                        ],
                      ),
                    );
                  }),
                  OutlinedButton.icon(
                    onPressed: uploading
                        ? null
                        : () => pickAndUpload(isRegistration: false),
                    icon: const Icon(Icons.note_add_outlined, size: 18),
                    label: Text(tr('Thêm giấy tờ NPT')),
                  ),
                  if (uploading) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 2),
                  ],
                  const Divider(height: 24),
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
                        Text(tr('Tổng TN miễn thuế'), style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                        Text(tr('${_formatCurrency(total)} đ'),
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
                child: Text(tr('Đóng')),
              ),
              FilledButton.icon(
                onPressed: uploading
                    ? null
                    : () {
                        Navigator.pop(ctx);
                        _saveInlineEdit(
                          index,
                          numberOfDependents: int.tryParse(nptCtrl.text) ?? 0,
                          mandatoryInsurance:
                              parseFormattedNumber(insCtrl.text)?.toDouble() ??
                                  0,
                          otherExemptions:
                              parseFormattedNumber(otherCtrl.text)?.toDouble() ??
                                  0,
                          registrationFormUrl: registrationUrl,
                          documentsJson: jsonEncode(documents),
                        );
                      },
                icon: const Icon(Icons.save, size: 18),
                label: Text(tr('Lưu')),
                style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
              ),
            ],
          );
        });
      },
    );
  }

  List<Map<String, dynamic>> _parseDependentDocs(dynamic raw) {
    if (raw == null) return [];
    try {
      final decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) return [];
      return decoded
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _openUploadedPath(String path) async {
    if (path.isEmpty) return;
    final url = _apiService.getFileUrl(path);
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _dialogInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(tr(label), style: TextStyle(fontSize: 13, color: Colors.grey[600])),
        Text(tr('$value đ'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _dialogEditRow(String label, TextEditingController ctrl, void Function(void Function()) setDialogState, {bool isNumber = false}) {
    return Row(
      children: [
        Expanded(child: Text(tr(label), style: TextStyle(fontSize: 13, color: Colors.grey[600]))),
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
              suffixText: tr(isNumber ? '' : 'đ'),
              suffixStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
            ),
            onChanged: (_) => setDialogState(() {}),
          ),
        ),
      ],
    );
  }

  Future<void> _saveInlineEdit(
    int index, {
    int? numberOfDependents,
    double? mandatoryInsurance,
    double? otherExemptions,
    String? registrationFormUrl,
    String? documentsJson,
  }) async {
    final emp = _employeeDeductions[index];
    final data = {
      'employeeId': emp['employeeId'],
      'numberOfDependents':
          numberOfDependents ?? (emp['numberOfDependents'] ?? 0),
      'mandatoryInsurance': mandatoryInsurance ??
          ((emp['mandatoryInsurance'] is num)
              ? (emp['mandatoryInsurance'] as num).toDouble()
              : (double.tryParse(
                      emp['mandatoryInsurance']?.toString() ?? '0') ??
                  0)),
      'otherExemptions': otherExemptions ??
          ((emp['otherExemptions'] is num)
              ? (emp['otherExemptions'] as num).toDouble()
              : (double.tryParse(emp['otherExemptions']?.toString() ?? '0') ??
                  0)),
      'dependentRegistrationFormUrl': registrationFormUrl ??
          emp['dependentRegistrationFormUrl']?.toString() ??
          '',
      'dependentDocumentsJson': documentsJson ??
          emp['dependentDocumentsJson']?.toString() ??
          '[]',
    };
    final result = await _apiService.saveEmployeeTaxDeduction(data);
    if (result['isSuccess'] == true && mounted) {
      appNotification.showSuccess(
          title: 'Đã lưu', message: emp['employeeName'] ?? '');
      setState(() {
        _employeeDeductions[index]['numberOfDependents'] =
            data['numberOfDependents'];
        _employeeDeductions[index]['mandatoryInsurance'] =
            data['mandatoryInsurance'];
        _employeeDeductions[index]['otherExemptions'] = data['otherExemptions'];
        _employeeDeductions[index]['dependentRegistrationFormUrl'] =
            data['dependentRegistrationFormUrl'];
        _employeeDeductions[index]['dependentDocumentsJson'] =
            data['dependentDocumentsJson'];
      });
    } else if (mounted) {
      appNotification.showError(
          title: 'Lỗi', message: result['message'] ?? 'Không thể lưu');
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
                    color: PosTheme.kiotBlueLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.bar_chart, color: PosTheme.kiotBlue, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Giảm trừ gia cảnh'),
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(tr('Mức giảm trừ bản thân và người phụ thuộc'),
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
              Text(tr(label), style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w500, fontSize: 14)),
              const SizedBox(height: 2),
              Text(tr(description), style: TextStyle(color: Colors.grey[500], fontSize: 11)),
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
              suffixText: tr(suffix.split('/').first),
              suffixStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 11),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: HrmPageChrome.primaryNavy, width: 2),
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
                      Text(tr('Biểu thuế lũy tiến từng phần'),
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(tr('5 bậc thuế theo Luật thuế TNCN 2026'),
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
                _buildBracketRowTop(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBracketRow(int level, String prefix, TextEditingController amountController, TextEditingController rateController) {
    final colors = [
      HrmPageChrome.primaryNavy, // Bracket 1
      HrmPageChrome.primaryNavy, // Bracket 2
      const Color(0xFFF59E0B), // Bracket 3
      const Color(0xFFEF4444), // Bracket 4
      const Color(0xFF7C3AED), // Bracket 5
      const Color(0xFFEC4899), // Bracket 6
      HrmPageChrome.primaryNavy, // Bracket 7
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
          child: Text(tr('BẬC $level'),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        // Prefix
        Text(tr(prefix), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
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
              suffixText: tr('đ'),
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
        Text(tr('Thuế suất'), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
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
              suffixText: tr('%'),
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

  Widget _buildBracketRowTop() {
    const color = HrmPageChrome.primaryNavy;
    final amount4 = parseFormattedNumber(_bracket4AmountController.text)
            ?.toDouble() ??
        PitTaxDefaults.bracket4Max;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(tr('BẬC 5'),
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        Text(tr('Trên'), style: TextStyle(color: Colors.grey[600], fontSize: 13)),
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
          child: Text(tr('${formatNumber(amount4)}đ'),
            style: const TextStyle(
                color: Color(0xFF71717A),
                fontSize: 13,
                fontWeight: FontWeight.w500),
          ),
        ),
        Text(tr('Thuế suất'),
            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        SizedBox(
          width: 70,
          height: 36,
          child: TextField(
            controller: _bracket5RateController,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Color(0xFF18181B),
                fontSize: 13,
                fontWeight: FontWeight.w600),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: tr('%'),
              suffixStyle:
                  const TextStyle(color: Color(0xFF71717A), fontSize: 11),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
    final amount1 = parseFormattedNumber(_bracket1AmountController.text)
            ?.toDouble() ??
        PitTaxDefaults.bracket1Max;
    final amount2 = parseFormattedNumber(_bracket2AmountController.text)
            ?.toDouble() ??
        PitTaxDefaults.bracket2Max;
    final amount3 = parseFormattedNumber(_bracket3AmountController.text)
            ?.toDouble() ??
        PitTaxDefaults.bracket3Max;
    final amount4 = parseFormattedNumber(_bracket4AmountController.text)
            ?.toDouble() ??
        PitTaxDefaults.bracket4Max;
    final rate1 =
        double.tryParse(_bracket1RateController.text) ?? PitTaxDefaults.rate1;
    final rate2 =
        double.tryParse(_bracket2RateController.text) ?? PitTaxDefaults.rate2;
    final rate3 =
        double.tryParse(_bracket3RateController.text) ?? PitTaxDefaults.rate3;
    final rate4 =
        double.tryParse(_bracket4RateController.text) ?? PitTaxDefaults.rate4;
    final rate5 =
        double.tryParse(_bracket5RateController.text) ?? PitTaxDefaults.rate5;

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
                    color: PosTheme.kiotBlueLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.table_chart, color: PosTheme.kiotBlue, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('Bảng biểu thuế TNCN'),
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(tr('Tóm tắt 5 bậc thuế lũy tiến'),
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
                      color: HrmPageChrome.primaryNavy,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(11),
                        topRight: Radius.circular(11),
                      ),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text(tr('Bậc'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                        Expanded(child: Text(tr('Thu nhập tính thuế/tháng'), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                        SizedBox(width: 70, child: Text(tr('Thuế suất'), textAlign: TextAlign.right, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                  // Table Rows
                  _buildSummaryRow(1, 'Đến ${_formatMillion(amount1)} triệu', rate1, false),
                  _buildSummaryRow(2, 'Trên ${_formatMillion(amount1)} - ${_formatMillion(amount2)} triệu', rate2, true),
                  _buildSummaryRow(3, 'Trên ${_formatMillion(amount2)} - ${_formatMillion(amount3)} triệu', rate3, false),
                  _buildSummaryRow(4, 'Trên ${_formatMillion(amount3)} - ${_formatMillion(amount4)} triệu', rate4, true),
                  _buildSummaryRow(5, 'Trên ${_formatMillion(amount4)} triệu', rate5, false, isLast: true),
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
      HrmPageChrome.primaryNavy,
      HrmPageChrome.primaryNavy,
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF7C3AED),
      const Color(0xFFEC4899),
      HrmPageChrome.primaryNavy,
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
                tr('$level'),
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(tr(range), style: const TextStyle(color: Color(0xFF71717A), fontSize: 13)),
          ),
          Text(
            tr('${rate.toStringAsFixed(rate == rate.toInt() ? 0 : 1)}%'),
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
