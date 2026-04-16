import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../utils/number_formatter.dart';
import '../widgets/app_button.dart';
import '../widgets/app_responsive_dialog.dart';
import '../widgets/loading_widget.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

class InsuranceSettingsScreen extends StatefulWidget {
  const InsuranceSettingsScreen({super.key});

  @override
  State<InsuranceSettingsScreen> createState() => _InsuranceSettingsScreenState();
}

class _InsuranceSettingsScreenState extends State<InsuranceSettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;

  // Lương cơ sở & Tối thiểu vùng
  final _baseSalaryController = TextEditingController(text: '2.340.000');
  final _regionISalaryController = TextEditingController(text: '4.960.000');
  final _regionIISalaryController = TextEditingController(text: '4.410.000');
  final _regionIIISalaryController = TextEditingController(text: '3.860.000');
  final _regionIVSalaryController = TextEditingController(text: '3.450.000');
  final _maxInsuranceSalaryController = TextEditingController(text: '46.800.000');

  // BHXH - Bảo hiểm xã hội
  final _bhxhEmployeeController = TextEditingController(text: '8');
  final _bhxhEmployerController = TextEditingController(text: '17.5');

  // BHYT - Bảo hiểm y tế
  final _bhytEmployeeController = TextEditingController(text: '1.5');
  final _bhytEmployerController = TextEditingController(text: '3');

  // BHTN - Bảo hiểm thất nghiệp
  final _bhtnEmployeeController = TextEditingController(text: '1');
  final _bhtnEmployerController = TextEditingController(text: '1');

  // Công đoàn
  final _unionEmployeeController = TextEditingController(text: '1');
  final _unionEmployerController = TextEditingController(text: '2');

  // Vùng công ty
  int _companyRegion = 1;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  bool _loadedFromServer = false;

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      // getInsuranceSettings() already returns the unwrapped data map (not AppResponse)
      final settings = await _apiService.getInsuranceSettings();
      if (settings.isEmpty) {
        // API failed or returned empty — keep hardcoded defaults, don't allow accidental overwrite
        _loadedFromServer = false;
      } else {
        _loadedFromServer = true;
        setState(() {
          _baseSalaryController.text = formatNumber(settings['baseSalary'] ?? 2340000);
          _regionISalaryController.text = formatNumber(settings['minSalaryRegion1'] ?? 4960000);
          _regionIISalaryController.text = formatNumber(settings['minSalaryRegion2'] ?? 4410000);
          _regionIIISalaryController.text = formatNumber(settings['minSalaryRegion3'] ?? 3860000);
          _regionIVSalaryController.text = formatNumber(settings['minSalaryRegion4'] ?? 3450000);
          _maxInsuranceSalaryController.text = formatNumber(settings['maxInsuranceSalary'] ?? 46800000);
          _bhxhEmployeeController.text = settings['bhxhEmployeeRate']?.toString() ?? '8';
          _bhxhEmployerController.text = settings['bhxhEmployerRate']?.toString() ?? '17.5';
          _bhytEmployeeController.text = settings['bhytEmployeeRate']?.toString() ?? '1.5';
          _bhytEmployerController.text = settings['bhytEmployerRate']?.toString() ?? '3';
          _bhtnEmployeeController.text = settings['bhtnEmployeeRate']?.toString() ?? '1';
          _bhtnEmployerController.text = settings['bhtnEmployerRate']?.toString() ?? '1';
          _unionEmployeeController.text = settings['unionFeeEmployeeRate']?.toString() ?? '1';
          _unionEmployerController.text = settings['unionFeeEmployerRate']?.toString() ?? '2';
          _companyRegion = settings['defaultRegion'] ?? 1;
        });
      }
    } catch (e) {
      _loadedFromServer = false;
      debugPrint('Error loading insurance settings: $e');
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi tải dữ liệu',
          message: 'Không thể tải cài đặt bảo hiểm từ máy chủ. Đang hiển thị giá trị mặc định.',
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_loadedFromServer) {
      // Prevent accidental overwrite of saved settings with hardcoded defaults
      final confirm = await AppResponsiveDialog.show<bool>(
        context: context,
        title: 'Cảnh báo',
        icon: Icons.warning_amber_rounded,
        iconColor: Colors.orange,
        maxWidth: 420,
        scrollable: false,
        child: const Text(
          'Dữ liệu chưa được tải từ máy chủ. '
          'Lưu có thể ghi đè thiết lập đã lưu bằng giá trị mặc định.\n\n'
          'Bạn có chắc chắn muốn lưu không?',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: AppDialogActions(
          onCancel: () => Navigator.pop(context, false),
          onConfirm: () => Navigator.pop(context, true),
          cancelLabel: 'Hủy',
          confirmLabel: 'Vẫn lưu',
          confirmVariant: AppButtonVariant.danger,
        ),
      );
      if (confirm != true) return;
    }

    final settings = {
      'baseSalary': parseFormattedNumber(_baseSalaryController.text)?.toDouble() ?? 2340000,
      'minSalaryRegion1': parseFormattedNumber(_regionISalaryController.text)?.toDouble() ?? 4960000,
      'minSalaryRegion2': parseFormattedNumber(_regionIISalaryController.text)?.toDouble() ?? 4410000,
      'minSalaryRegion3': parseFormattedNumber(_regionIIISalaryController.text)?.toDouble() ?? 3860000,
      'minSalaryRegion4': parseFormattedNumber(_regionIVSalaryController.text)?.toDouble() ?? 3450000,
      'maxInsuranceSalary': parseFormattedNumber(_maxInsuranceSalaryController.text)?.toDouble() ?? 46800000,
      'bhxhEmployeeRate': double.tryParse(_bhxhEmployeeController.text) ?? 8,
      'bhxhEmployerRate': double.tryParse(_bhxhEmployerController.text) ?? 17.5,
      'bhytEmployeeRate': double.tryParse(_bhytEmployeeController.text) ?? 1.5,
      'bhytEmployerRate': double.tryParse(_bhytEmployerController.text) ?? 3,
      'bhtnEmployeeRate': double.tryParse(_bhtnEmployeeController.text) ?? 1,
      'bhtnEmployerRate': double.tryParse(_bhtnEmployerController.text) ?? 1,
      'unionFeeEmployeeRate': double.tryParse(_unionEmployeeController.text) ?? 1,
      'unionFeeEmployerRate': double.tryParse(_unionEmployerController.text) ?? 2,
      'defaultRegion': _companyRegion,
    };

    try {
      final response = await _apiService.saveInsuranceSettings(settings);
      if (mounted) {
        if (response['isSuccess'] == true) {
          appNotification.showSuccess(title: 'Thành công', message: 'Đã lưu thiết lập bảo hiểm');
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
    _baseSalaryController.dispose();
    _regionISalaryController.dispose();
    _regionIISalaryController.dispose();
    _regionIIISalaryController.dispose();
    _regionIVSalaryController.dispose();
    _maxInsuranceSalaryController.dispose();
    _bhxhEmployeeController.dispose();
    _bhxhEmployerController.dispose();
    _bhytEmployeeController.dispose();
    _bhytEmployerController.dispose();
    _bhtnEmployeeController.dispose();
    _bhtnEmployerController.dispose();
    _unionEmployeeController.dispose();
    _unionEmployerController.dispose();
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
        title: const Text('Bảo hiểm xã hội', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 18), overflow: TextOverflow.ellipsis, maxLines: 1),
        leading: Responsive.isMobile(context) ? null : IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
        actions: const [],
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
                        child: const Icon(Icons.settings, color: Color(0xFF71717A), size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Thiết lập Bảo hiểm xã hội',
                              style: TextStyle(
                                color: Color(0xFF1E3A5F),
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Cấu hình tỷ lệ đóng BHXH, BHYT, BHTN và phí công đoàn',
                              style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Row 1: Lương cơ sở, BHXH, BHYT
                  if (isWideScreen)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildBaseSalaryCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildBHXHCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildBHYTCard()),
                      ],
                    )
                  else if (isMediumScreen)
                    Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: _buildBaseSalaryCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildBHXHCard()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildBHYTCard(),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildBaseSalaryCard(),
                        const SizedBox(height: 16),
                        _buildBHXHCard(),
                        const SizedBox(height: 16),
                        _buildBHYTCard(),
                      ],
                    ),

                  const SizedBox(height: 16),

                  // Row 2: BHTN, Công đoàn, Tổng kết
                  if (isWideScreen)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildBHTNCard()),
                        const SizedBox(width: 16),
                        Expanded(child: _buildUnionCard()),
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
                            Expanded(child: _buildBHTNCard()),
                            const SizedBox(width: 16),
                            Expanded(child: _buildUnionCard()),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(),
                      ],
                    )
                  else
                    Column(
                      children: [
                        _buildBHTNCard(),
                        const SizedBox(height: 16),
                        _buildUnionCard(),
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
                      label: const Text('Lưu thiết lập bảo hiểm', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  // Card Lương cơ sở & Tối thiểu vùng
  Widget _buildBaseSalaryCard() {
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
          // Header với icon
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
                    child: Icon(Icons.account_balance_wallet, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Lương cơ sở & Tối thiểu vùng',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Mức lương làm căn cứ tính bảo hiểm',
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
                _buildSalaryField(
                  icon: Icons.foundation,
                  label: 'Lương cơ sở',
                  description: 'Mức lương cơ sở do nhà nước quy định (2024: 2.340.000đ)',
                  controller: _baseSalaryController,
                ),
                const SizedBox(height: 16),
                _buildSalaryField(
                  icon: Icons.location_city,
                  label: 'Lương tối thiểu Vùng I',
                  description: 'TP.HCM, Hà Nội, Đà Nẵng, Hải Phòng...',
                  controller: _regionISalaryController,
                ),
                const SizedBox(height: 16),
                _buildSalaryField(
                  icon: Icons.business,
                  label: 'Lương tối thiểu Vùng II',
                  description: 'Các quận/huyện còn lại thuộc tỉnh/TP lớn',
                  controller: _regionIISalaryController,
                ),
                const SizedBox(height: 16),
                _buildSalaryField(
                  icon: Icons.apartment,
                  label: 'Lương tối thiểu Vùng III',
                  description: 'Các tỉnh còn lại',
                  controller: _regionIIISalaryController,
                ),
                const SizedBox(height: 16),
                _buildSalaryField(
                  icon: Icons.home_work,
                  label: 'Lương tối thiểu Vùng IV',
                  description: 'Các huyện, xã vùng nông thôn',
                  controller: _regionIVSalaryController,
                ),
                const SizedBox(height: 16),
                _buildSalaryField(
                  icon: Icons.trending_up,
                  label: 'Mức trần đóng BHXH',
                  description: 'Tối đa 20 lần lương cơ sở (46.800.000đ)',
                  controller: _maxInsuranceSalaryController,
                ),
                const SizedBox(height: 16),
                // Công ty thuộc vùng
                Row(
                  children: [
                    const Icon(Icons.map, color: Color(0xFF71717A), size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Công ty thuộc vùng', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w500, fontSize: 14)),
                          Text('Vùng lương tối thiểu áp dụng cho công ty', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFAFAFA),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE4E4E7)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _companyRegion,
                          style: const TextStyle(color: Color(0xFF18181B), fontSize: 14, fontWeight: FontWeight.w600),
                          items: const [
                            DropdownMenuItem(value: 1, child: Text('Vùng I')),
                            DropdownMenuItem(value: 2, child: Text('Vùng II')),
                            DropdownMenuItem(value: 3, child: Text('Vùng III')),
                            DropdownMenuItem(value: 4, child: Text('Vùng IV')),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _companyRegion = value);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalaryField({
    required IconData icon,
    required String label,
    required String description,
    required TextEditingController controller,
  }) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF71717A), size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w500, fontSize: 14)),
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
              suffixText: 'đ',
              suffixStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
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

  // Card BHXH
  Widget _buildBHXHCard() {
    final employeeRate = double.tryParse(_bhxhEmployeeController.text) ?? 0;
    final employerRate = double.tryParse(_bhxhEmployerController.text) ?? 0;

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
                    child: Icon(Icons.health_and_safety, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bảo hiểm Xã hội (BHXH)',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Tỷ lệ đóng BHXH người lao động và doanh nghiệp',
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
                _buildInsuranceRateField(
                  label: 'Người lao động đóng',
                  description: 'Trích từ lương NLĐ (thường 8%)',
                  controller: _bhxhEmployeeController,
                ),
                const SizedBox(height: 16),
                _buildInsuranceRateField(
                  label: 'Doanh nghiệp đóng',
                  description: 'DN đóng thêm cho NLĐ (thường 17.5%)',
                  controller: _bhxhEmployerController,
                ),
                const SizedBox(height: 20),
                _buildTotalBox('Tổng BHXH:', employeeRate + employerRate, const Color(0xFF1E3A5F)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card BHYT
  Widget _buildBHYTCard() {
    final employeeRate = double.tryParse(_bhytEmployeeController.text) ?? 0;
    final employerRate = double.tryParse(_bhytEmployerController.text) ?? 0;

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
                      colors: [Color(0xFFEF4444), Color(0xFFF87171)],
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Icon(Icons.local_hospital, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bảo hiểm Y tế (BHYT)',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Tỷ lệ đóng BHYT người lao động và doanh nghiệp',
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
                _buildInsuranceRateField(
                  label: 'Người lao động đóng',
                  description: 'Trích từ lương NLĐ (thường 1.5%)',
                  controller: _bhytEmployeeController,
                ),
                const SizedBox(height: 16),
                _buildInsuranceRateField(
                  label: 'Doanh nghiệp đóng',
                  description: 'DN đóng thêm cho NLĐ (thường 3%)',
                  controller: _bhytEmployerController,
                ),
                const SizedBox(height: 20),
                _buildTotalBox('Tổng BHYT:', employeeRate + employerRate, const Color(0xFF1E3A5F)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card BHTN
  Widget _buildBHTNCard() {
    final employeeRate = double.tryParse(_bhtnEmployeeController.text) ?? 0;
    final employerRate = double.tryParse(_bhtnEmployerController.text) ?? 0;
    final total = employeeRate + employerRate;

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
                    child: Icon(Icons.work_off, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Bảo hiểm Thất nghiệp (BHTN)',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Tỷ lệ đóng BHTN người lao động và doanh nghiệp',
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
                _buildInsuranceRateField(
                  label: 'Người lao động đóng',
                  description: 'Trích từ lương NLĐ (thường 1%)',
                  controller: _bhtnEmployeeController,
                ),
                const SizedBox(height: 16),
                _buildInsuranceRateField(
                  label: 'Doanh nghiệp đóng',
                  description: 'DN đóng thêm cho NLĐ (thường 1%)',
                  controller: _bhtnEmployerController,
                ),
                const SizedBox(height: 20),
                _buildTotalBox('Tổng BHTN:', total, const Color(0xFF1E3A5F)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card Công đoàn
  Widget _buildUnionCard() {
    final employeeRate = double.tryParse(_unionEmployeeController.text) ?? 0;
    final employerRate = double.tryParse(_unionEmployerController.text) ?? 0;
    final total = employeeRate + employerRate;

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
                    child: Icon(Icons.groups, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Phi Công đoàn',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Phí công đoàn người lao động và kinh phí công đoàn',
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
                _buildInsuranceRateField(
                  label: 'Đoàn phí (NLĐ đóng)',
                  description: 'Đoàn viên đóng (thường 1% lương đóng BH)',
                  controller: _unionEmployeeController,
                ),
                const SizedBox(height: 16),
                _buildInsuranceRateField(
                  label: 'Kinh phí công đoàn (DN đóng)',
                  description: 'DN đóng (thường 2% quỹ lương)',
                  controller: _unionEmployerController,
                ),
                const SizedBox(height: 20),
                _buildTotalBox('Tổng Công đoàn:', total, const Color(0xFF1E3A5F)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsuranceRateField({
    required String label,
    required String description,
    required TextEditingController controller,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.w500, fontSize: 14)),
              Text(description, style: TextStyle(color: Colors.grey[500], fontSize: 11)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 90,
          height: 40,
          child: TextField(
            controller: controller,
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 14, fontWeight: FontWeight.w600),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: '%',
              suffixStyle: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
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

  Widget _buildTotalBox(String label, double value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF18181B),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            '${_formatRate(value)}%',
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRate(double value) {
    if (value % 1 == 0) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  // Card Tổng kết
  Widget _buildSummaryCard() {
    final bhxhEmp = double.tryParse(_bhxhEmployeeController.text) ?? 0;
    final bhytEmp = double.tryParse(_bhytEmployeeController.text) ?? 0;
    final bhtnEmp = double.tryParse(_bhtnEmployeeController.text) ?? 0;
    final unionEmp = double.tryParse(_unionEmployeeController.text) ?? 0;

    final bhxhEmr = double.tryParse(_bhxhEmployerController.text) ?? 0;
    final bhytEmr = double.tryParse(_bhytEmployerController.text) ?? 0;
    final bhtnEmr = double.tryParse(_bhtnEmployerController.text) ?? 0;
    final unionEmr = double.tryParse(_unionEmployerController.text) ?? 0;

    final totalEmp = bhxhEmp + bhytEmp + bhtnEmp + unionEmp;
    final totalEmr = bhxhEmr + bhytEmr + bhtnEmr + unionEmr;

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
                    child: Icon(Icons.summarize, color: Colors.white, size: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tổng kết tỷ lệ đóng',
                        style: TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Tổng hợp các khoản đóng bảo hiểm',
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
                        Expanded(flex: 3, child: Text('Loại bảo hiểm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                        Expanded(flex: 2, child: Text('NLĐ đóng', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                        Expanded(flex: 2, child: Text('DN đóng', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                        Expanded(flex: 2, child: Text('Tổng', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
                      ],
                    ),
                  ),
                  // Table Rows
                  _buildSummaryRow('BHXH', bhxhEmp, bhxhEmr, false),
                  _buildSummaryRow('BHYT', bhytEmp, bhytEmr, true),
                  _buildSummaryRow('BHTN', bhtnEmp, bhtnEmr, false),
                  _buildSummaryRow('Công đoàn', unionEmp, unionEmr, true),
                  // Total Row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(11),
                        bottomRight: Radius.circular(11),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(flex: 3, child: Text('TỔNG CỘNG', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 2, child: Text('${_formatRate(totalEmp)}%', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 2, child: Text('${_formatRate(totalEmr)}%', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 13))),
                        Expanded(flex: 2, child: Text('${_formatRate(totalEmp + totalEmr)}%', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 13))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, double empRate, double emrRate, bool isAlt) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isAlt ? const Color(0xFFFAFAFA) : Colors.white,
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 13))),
          Expanded(flex: 2, child: Text('${_formatRate(empRate)}%', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF18181B), fontSize: 13))),
          Expanded(flex: 2, child: Text('${_formatRate(emrRate)}%', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF18181B), fontSize: 13))),
          Expanded(flex: 2, child: Text('${_formatRate(empRate + emrRate)}%', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF18181B), fontSize: 13))),
        ],
      ),
    );
  }
}
