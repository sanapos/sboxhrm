import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _apiService = ApiService();

  // Gemini
  final _geminiApiKeyController = TextEditingController();
  final _geminiModelController = TextEditingController();
  final _geminiMaxTokensController = TextEditingController();
  final _geminiTemperatureController = TextEditingController();
  bool _geminiEnabled = false;
  bool _geminiConfigured = false;
  bool _geminiObscure = true;
  String? _geminiMaskedKey;

  // DeepSeek
  final _deepSeekApiKeyController = TextEditingController();
  final _deepSeekModelController = TextEditingController();
  final _deepSeekMaxTokensController = TextEditingController();
  final _deepSeekTemperatureController = TextEditingController();
  bool _deepSeekEnabled = false;
  bool _deepSeekConfigured = false;
  bool _deepSeekObscure = true;
  String? _deepSeekMaskedKey;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllConfigs());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _geminiApiKeyController.dispose();
    _geminiModelController.dispose();
    _geminiMaxTokensController.dispose();
    _geminiTemperatureController.dispose();
    _deepSeekApiKeyController.dispose();
    _deepSeekModelController.dispose();
    _deepSeekMaxTokensController.dispose();
    _deepSeekTemperatureController.dispose();
    super.dispose();
  }

  Future<void> _loadAllConfigs() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _apiService.getGeminiConfig(),
        _apiService.getDeepSeekConfig(),
      ]);

      final gemini = results[0];
      if (gemini['isSuccess'] == true && gemini['data'] != null) {
        final d = gemini['data'];
        _geminiMaskedKey = d['apiKey'] ?? '';
        _geminiModelController.text = d['model'] ?? 'gemini-2.5-flash';
        _geminiMaxTokensController.text =
            (d['maxOutputTokens'] ?? 2048).toString();
        _geminiTemperatureController.text =
            (d['temperature'] ?? 0.7).toString();
        _geminiConfigured = d['isConfigured'] ?? false;
        _geminiEnabled = d['enabled'] ?? false;
      }

      final deepseek = results[1];
      if (deepseek['isSuccess'] == true && deepseek['data'] != null) {
        final d = deepseek['data'];
        _deepSeekMaskedKey = d['apiKey'] ?? '';
        _deepSeekModelController.text = d['model'] ?? 'deepseek-chat';
        _deepSeekMaxTokensController.text =
            (d['maxOutputTokens'] ?? 2048).toString();
        _deepSeekTemperatureController.text =
            (d['temperature'] ?? 0.7).toString();
        _deepSeekConfigured = d['isConfigured'] ?? false;
        _deepSeekEnabled = d['enabled'] ?? false;
      }
    } catch (e) {
      debugPrint('Error loading AI configs: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleProvider(String provider, bool enabled) async {
    setState(() => _isSaving = true);
    try {
      Map<String, dynamic> result;
      if (provider == 'gemini') {
        result = await _apiService.updateGeminiConfig({'enabled': enabled});
        if (result['isSuccess'] == true) {
          setState(() => _geminiEnabled = enabled);
        }
      } else {
        result =
            await _apiService.updateDeepSeekConfig({'enabled': enabled});
        if (result['isSuccess'] == true) {
          setState(() => _deepSeekEnabled = enabled);
        }
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi', message: '$e');
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _saveGeminiConfig() async {
    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{};
      if (_geminiApiKeyController.text.isNotEmpty) {
        data['apiKey'] = _geminiApiKeyController.text.trim();
      }
      if (_geminiModelController.text.isNotEmpty) {
        data['model'] = _geminiModelController.text.trim();
      }
      final maxTokens = int.tryParse(_geminiMaxTokensController.text);
      if (maxTokens != null) data['maxOutputTokens'] = maxTokens;
      final temp = double.tryParse(_geminiTemperatureController.text);
      if (temp != null) data['temperature'] = temp;
      data['enabled'] = _geminiEnabled;

      if (_geminiApiKeyController.text.isEmpty && !_geminiConfigured && data.length <= 2) {
        appNotification.showWarning(
            title: 'Chưa có API Key',
            message: 'Vui lòng nhập API Key để sử dụng Gemini');
        setState(() => _isSaving = false);
        return;
      }

      final result = await _apiService.updateGeminiConfig(data);
      if (result['isSuccess'] == true) {
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã lưu cấu hình Gemini');
        _geminiApiKeyController.clear();
        await _loadAllConfigs();
      } else {
        appNotification.showError(
            title: 'Lỗi',
            message: result['message'] ?? 'Không thể lưu cấu hình');
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Không thể lưu cấu hình: $e');
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _saveDeepSeekConfig() async {
    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{};
      if (_deepSeekApiKeyController.text.isNotEmpty) {
        data['apiKey'] = _deepSeekApiKeyController.text.trim();
      }
      if (_deepSeekModelController.text.isNotEmpty) {
        data['model'] = _deepSeekModelController.text.trim();
      }
      final maxTokens = int.tryParse(_deepSeekMaxTokensController.text);
      if (maxTokens != null) data['maxOutputTokens'] = maxTokens;
      final temp = double.tryParse(_deepSeekTemperatureController.text);
      if (temp != null) data['temperature'] = temp;
      data['enabled'] = _deepSeekEnabled;

      if (_deepSeekApiKeyController.text.isEmpty && !_deepSeekConfigured && data.length <= 2) {
        appNotification.showWarning(
            title: 'Chưa có API Key',
            message: 'Vui lòng nhập API Key để sử dụng DeepSeek');
        setState(() => _isSaving = false);
        return;
      }

      final result = await _apiService.updateDeepSeekConfig(data);
      if (result['isSuccess'] == true) {
        appNotification.showSuccess(
            title: 'Thành công', message: 'Đã lưu cấu hình DeepSeek');
        _deepSeekApiKeyController.clear();
        await _loadAllConfigs();
      } else {
        appNotification.showError(
            title: 'Lỗi',
            message: result['message'] ?? 'Không thể lưu cấu hình');
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: 'Không thể lưu cấu hình: $e');
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _testConnection(String provider) async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });
    try {
      final result = provider == 'gemini'
          ? await _apiService.testGeminiConnection()
          : await _apiService.testDeepSeekConnection();

      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        final isQuotaError = data['isQuotaError'] == true;
        final success = data['success'] == true;
        setState(() {
          _testSuccess = success;
          if (success && !isQuotaError) {
            _testResult =
                '${data['message']}\n\nTiêu đề mẫu: ${data['sampleTitle']}';
          } else if (isQuotaError) {
            _testResult = '${data['message']}\n\n${data['detail'] ?? ''}';
          } else {
            _testResult = data['message'] ?? 'Kết nối thất bại';
          }
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testResult = result['message'] ?? 'Không thể kiểm tra kết nối';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testResult = 'Lỗi: $e';
      });
    }
    if (mounted) setState(() => _isTesting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: Responsive.isMobile(context) ? null : IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
        title: const Text(
          'Thiết lập AI',
          style: TextStyle(
              color: Color(0xFF18181B), fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF1E3A5F),
          unselectedLabelColor: const Color(0xFF71717A),
          indicatorColor: const Color(0xFF2D5F8B),
          indicatorWeight: 3,
          onTap: (_) => setState(() {
            _testResult = null;
            _testSuccess = null;
          }),
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.auto_awesome, size: 18),
                  const SizedBox(width: 6),
                  const Text('Gemini'),
                  const SizedBox(width: 6),
                  _buildStatusDot(_geminiEnabled && _geminiConfigured),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.psychology, size: 18),
                  const SizedBox(width: 6),
                  const Text('DeepSeek'),
                  const SizedBox(width: 6),
                  _buildStatusDot(_deepSeekEnabled && _deepSeekConfigured),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildProviderTab(
                  provider: 'gemini',
                  name: 'Google Gemini',
                  icon: Icons.auto_awesome,
                  gradientColors: [
                    const Color(0xFF2D5F8B),
                    const Color(0xFF34A853)
                  ],
                  enabled: _geminiEnabled,
                  configured: _geminiConfigured,
                  apiKeyController: _geminiApiKeyController,
                  modelController: _geminiModelController,
                  maxTokensController: _geminiMaxTokensController,
                  temperatureController: _geminiTemperatureController,
                  obscure: _geminiObscure,
                  maskedKey: _geminiMaskedKey,
                  onToggle: (v) => _toggleProvider('gemini', v),
                  onObscureToggle: () =>
                      setState(() => _geminiObscure = !_geminiObscure),
                  onSave: _saveGeminiConfig,
                  onTest: () => _testConnection('gemini'),
                  modelItems: const [
                    DropdownMenuItem(
                        value: 'gemini-2.5-flash',
                        child:
                            Text('Gemini 2.5 Flash (Nhanh, miễn phí)')),
                    DropdownMenuItem(
                        value: 'gemini-2.5-pro',
                        child:
                            Text('Gemini 2.5 Pro (Chất lượng cao)')),
                    DropdownMenuItem(
                        value: 'gemini-2.0-flash',
                        child: Text('Gemini 2.0 Flash')),
                    DropdownMenuItem(
                        value: 'gemini-2.0-flash-lite',
                        child:
                            Text('Gemini 2.0 Flash Lite (Siêu nhanh)')),
                  ],
                  helpSteps: const [
                    _HelpStep(1, 'Truy cập Google AI Studio',
                        'https://aistudio.google.com/apikey'),
                    _HelpStep(
                        2, 'Đăng nhập bằng tài khoản Google', null),
                    _HelpStep(3,
                        'Nhấn "Create API Key" hoặc "Tạo API Key"', null),
                    _HelpStep(
                        4, 'Copy API Key và dán vào ô phía trên', null),
                  ],
                  helpNote:
                      'Gemini API miễn phí với giới hạn 15 request/phút.',
                ),
                _buildProviderTab(
                  provider: 'deepseek',
                  name: 'DeepSeek AI',
                  icon: Icons.psychology,
                  gradientColors: [
                    const Color(0xFF1E3A5F),
                    const Color(0xFF6366F1)
                  ],
                  enabled: _deepSeekEnabled,
                  configured: _deepSeekConfigured,
                  apiKeyController: _deepSeekApiKeyController,
                  modelController: _deepSeekModelController,
                  maxTokensController: _deepSeekMaxTokensController,
                  temperatureController: _deepSeekTemperatureController,
                  obscure: _deepSeekObscure,
                  maskedKey: _deepSeekMaskedKey,
                  onToggle: (v) => _toggleProvider('deepseek', v),
                  onObscureToggle: () =>
                      setState(() => _deepSeekObscure = !_deepSeekObscure),
                  onSave: _saveDeepSeekConfig,
                  onTest: () => _testConnection('deepseek'),
                  modelItems: const [
                    DropdownMenuItem(
                        value: 'deepseek-chat',
                        child: Text('DeepSeek Chat (Đa năng)')),
                    DropdownMenuItem(
                        value: 'deepseek-reasoner',
                        child:
                            Text('DeepSeek Reasoner (Suy luận mạnh)')),
                  ],
                  helpSteps: const [
                    _HelpStep(1, 'Truy cập DeepSeek Platform',
                        'https://platform.deepseek.com/api_keys'),
                    _HelpStep(
                        2, 'Đăng ký/Đăng nhập tài khoản DeepSeek', null),
                    _HelpStep(3, 'Tạo API Key mới', null),
                    _HelpStep(
                        4, 'Copy API Key và dán vào ô phía trên', null),
                  ],
                  helpNote:
                      'DeepSeek cung cấp giá rẻ nhất thị trường, phù hợp cho nội dung dài.',
                ),
              ],
            ),
    );
  }

  Widget _buildStatusDot(bool active) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: active ? const Color(0xFF16A34A) : const Color(0xFFD4D4D8),
      ),
    );
  }

  Widget _buildProviderTab({
    required String provider,
    required String name,
    required IconData icon,
    required List<Color> gradientColors,
    required bool enabled,
    required bool configured,
    required TextEditingController apiKeyController,
    required TextEditingController modelController,
    required TextEditingController maxTokensController,
    required TextEditingController temperatureController,
    required bool obscure,
    required String? maskedKey,
    required ValueChanged<bool> onToggle,
    required VoidCallback onObscureToggle,
    required VoidCallback onSave,
    required VoidCallback onTest,
    required List<DropdownMenuItem<String>> modelItems,
    required List<_HelpStep> helpSteps,
    required String helpNote,
  }) {
    final isMobile = Responsive.isMobile(context);
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header + Toggle
              _buildProviderHeader(
                  name, icon, gradientColors, enabled, onToggle),
              const SizedBox(height: 24),

              // Status
              _buildStatusCard(enabled, configured, name),
              const SizedBox(height: 24),

              // Config sections (only show when enabled)
              if (enabled) ...[
                _buildApiKeySection(
                    apiKeyController, maskedKey, obscure, onObscureToggle),
                const SizedBox(height: 24),
                _buildModelSettingsSection(
                    modelController, maxTokensController,
                    temperatureController, modelItems, isMobile),
                const SizedBox(height: 24),
                _buildTestSection(provider, configured),
                const SizedBox(height: 24),
                _buildSaveButton(onSave),
                const SizedBox(height: 32),
              ],

              // Help
              _buildHelpSection(helpSteps, helpNote),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProviderHeader(String name, IconData icon,
      List<Color> gradientColors, bool enabled, ValueChanged<bool> onToggle) {
    final isMobile = Responsive.isMobile(context);
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 10 : 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: gradientColors),
            borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
          ),
          child: Icon(icon, color: Colors.white, size: isMobile ? 24 : 32),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: isMobile ? 17 : 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF18181B))),
              const SizedBox(height: 4),
              Text('Tích hợp AI để tự động tạo nội dung',
                  style:
                      TextStyle(color: Colors.grey[600], fontSize: isMobile ? 12 : 14)),
            ],
          ),
        ),
        Column(
          children: [
            Switch(
              value: enabled,
              onChanged: _isSaving ? null : onToggle,
              activeThumbColor: const Color(0xFF2D5F8B),
            ),
            Text(enabled ? 'Đang bật' : 'Đang tắt',
                style: TextStyle(
                    fontSize: 11,
                    color: enabled
                        ? const Color(0xFF16A34A)
                        : Colors.grey[500],
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard(bool enabled, bool configured, String name) {
    Color bgColor, borderColor, textColor;
    IconData statusIcon;
    String title, subtitle;

    if (!enabled) {
      bgColor = const Color(0xFFF4F4F5);
      borderColor = const Color(0xFFE4E4E7);
      textColor = const Color(0xFF71717A);
      statusIcon = Icons.power_settings_new;
      title = '$name đang tắt';
      subtitle = 'Bật công tắc phía trên để bắt đầu sử dụng';
    } else if (!configured) {
      bgColor = const Color(0xFFFFF7ED);
      borderColor = const Color(0xFFFED7AA);
      textColor = const Color(0xFFF97316);
      statusIcon = Icons.warning_amber_rounded;
      title = 'Chưa cấu hình API Key';
      subtitle = 'Nhập API Key để bắt đầu sử dụng $name';
    } else {
      bgColor = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF86EFAC);
      textColor = const Color(0xFF16A34A);
      statusIcon = Icons.check_circle;
      title = '$name đã sẵn sàng';
      subtitle = 'AI đang hoạt động và sẵn sàng tạo nội dung';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: textColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 13, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApiKeySection(TextEditingController controller,
      String? maskedKey, bool obscure, VoidCallback onObscureToggle) {
    return _buildCard(
      title: 'API Key',
      icon: Icons.key,
      iconColor: const Color(0xFFF59E0B),
      children: [
        if (maskedKey != null && maskedKey.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock, size: 16, color: Color(0xFF71717A)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Key hiện tại: $maskedKey',
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFF71717A))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Nhập API Key mới (để trống nếu không đổi):',
              style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
          const SizedBox(height: 8),
        ] else ...[
          const Text('Nhập API Key:',
              style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: 'sk-... hoặc AIza...',
            prefixIcon: const Icon(Icons.vpn_key, size: 20),
            suffixIcon: IconButton(
              icon: Icon(
                  obscure ? Icons.visibility_off : Icons.visibility,
                  size: 20),
              onPressed: onObscureToggle,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: Color(0xFF2D5F8B), width: 2)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildModelSettingsSection(
    TextEditingController modelController,
    TextEditingController maxTokensController,
    TextEditingController temperatureController,
    List<DropdownMenuItem<String>> modelItems,
    bool isMobile,
  ) {
    return _buildCard(
      title: 'Cài đặt Model',
      icon: Icons.tune,
      iconColor: const Color(0xFF0F2340),
      children: [
        const Text('Model',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF52525B))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: modelItems.any((i) => i.value == modelController.text)
              ? modelController.text
              : modelItems.first.value,
          items: modelItems,
          onChanged: (val) {
            if (val != null) modelController.text = val;
          },
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7))),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 16),
        if (isMobile) ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Độ dài tối đa (tokens)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF52525B))),
              const SizedBox(height: 6),
              TextFormField(
                controller: maxTokensController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: '2048',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE4E4E7))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE4E4E7))),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nhiệt độ (0.0 - 2.0)',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF52525B))),
              const SizedBox(height: 6),
              TextFormField(
                controller: temperatureController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  hintText: '0.7',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE4E4E7))),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                          color: Color(0xFFE4E4E7))),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
              ),
            ],
          ),
        ] else
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Độ dài tối đa (tokens)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF52525B))),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: maxTokensController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: '2048',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE4E4E7))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE4E4E7))),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Nhiệt độ (0.0 - 2.0)',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF52525B))),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: temperatureController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      hintText: '0.7',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE4E4E7))),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFFE4E4E7))),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '💡 Nhiệt độ thấp (0.1-0.3): chính xác, nhất quán. Cao (0.7-1.5): sáng tạo, đa dạng.',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _buildTestSection(String provider, bool configured) {
    return _buildCard(
      title: 'Kiểm tra kết nối',
      icon: Icons.science,
      iconColor: const Color(0xFF1E3A5F),
      children: [
        Text(
          'Gửi yêu cầu thử để kiểm tra API Key và kết nối.',
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed:
                (_isTesting || !configured) ? null : () => _testConnection(provider),
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(
                _isTesting ? 'Đang kiểm tra...' : 'Kiểm tra kết nối'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A5F),
              side: const BorderSide(color: Color(0xFF1E3A5F)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _testSuccess == true
                  ? const Color(0xFFF0FDF4)
                  : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _testSuccess == true
                    ? const Color(0xFF86EFAC)
                    : const Color(0xFFFECACA),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _testSuccess == true
                      ? Icons.check_circle
                      : Icons.error,
                  color: _testSuccess == true
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _testResult!,
                    style: TextStyle(
                      fontSize: 13,
                      color: _testSuccess == true
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSaveButton(VoidCallback onSave) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isSaving ? null : onSave,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text(
          _isSaving ? 'Đang lưu...' : 'Lưu cấu hình',
          style:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2D5F8B),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildHelpSection(List<_HelpStep> steps, String note) {
    return _buildCard(
      title: 'Hướng dẫn lấy API Key',
      icon: Icons.help_outline,
      iconColor: const Color(0xFF1E3A5F),
      children: [
        ...steps.map((s) => _buildStep(s.number, s.title, s.subtitle)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info, size: 18, color: Color(0xFF1E3A5F)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(note,
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey[700])),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep(int number, String title, String? subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFF2D5F8B),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Center(
              child: Text('$number',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.blue[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 22),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF18181B))),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _HelpStep {
  final int number;
  final String title;
  final String? subtitle;
  const _HelpStep(this.number, this.title, this.subtitle);
}
