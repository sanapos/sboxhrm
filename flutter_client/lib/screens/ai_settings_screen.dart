import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm/hrm_settings_mobile_kit.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/pos/pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';
class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

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

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAllConfigs());
  }

  @override
  void dispose() {
    _geminiApiKeyController.dispose();
    _geminiModelController.dispose();
    _geminiMaxTokensController.dispose();
    _geminiTemperatureController.dispose();
    super.dispose();
  }

  Future<void> _loadAllConfigs() async {
    setState(() => _isLoading = true);
    try {
      final gemini = await _apiService.getGeminiConfig();
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
    } catch (e) {
      debugPrint('Error loading AI configs: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleGemini(bool enabled) async {
    setState(() => _isSaving = true);
    try {
      final result = await _apiService.updateGeminiConfig({'enabled': enabled});
      if (result['isSuccess'] == true) {
        setState(() => _geminiEnabled = enabled);
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

      if (_geminiApiKeyController.text.isEmpty &&
          !_geminiConfigured &&
          data.length <= 2) {
        appNotification.showWarning(
            title: 'Chưa có API Key',
            message: tr('Vui lòng nhập API Key để sử dụng Gemini'));
        setState(() => _isSaving = false);
        return;
      }

      final result = await _apiService.updateGeminiConfig(data);
      if (result['isSuccess'] == true) {
        appNotification.showSuccess(
            title: 'Thành công', message: tr('Đã lưu cấu hình Gemini'));
        _geminiApiKeyController.clear();
        await _loadAllConfigs();
      } else {
        appNotification.showError(
            title: 'Lỗi',
            message: result['message'] ?? 'Không thể lưu cấu hình');
      }
    } catch (e) {
      appNotification.showError(
          title: 'Lỗi', message: tr('Không thể lưu cấu hình: $e'));
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });
    try {
      final result = await _apiService.testGeminiConnection();

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
      backgroundColor: HrmPageChrome.scaffoldBackground(context),
      appBar: HrmPageChrome.appBar(title: 'Thiết lập AI'),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildProviderTab(
              provider: 'gemini',
              name: 'Google Gemini',
              icon: Icons.auto_awesome,
              gradientColors: [
                PosTheme.kiotBlue,
                const Color(0xFF0056C7),
              ],
              enabled: _geminiEnabled,
              configured: _geminiConfigured,
              apiKeyController: _geminiApiKeyController,
              modelController: _geminiModelController,
              maxTokensController: _geminiMaxTokensController,
              temperatureController: _geminiTemperatureController,
              obscure: _geminiObscure,
              maskedKey: _geminiMaskedKey,
              onToggle: (v) => _toggleGemini(v),
              onObscureToggle: () =>
                  setState(() => _geminiObscure = !_geminiObscure),
              onSave: _saveGeminiConfig,
              onTest: () => _testConnection(),
              modelItems: [
                DropdownMenuItem(
                    value: 'gemini-2.5-flash',
                    child: Text(tr('Gemini 2.5 Flash (Nhanh, miễn phí)'))),
                DropdownMenuItem(
                    value: 'gemini-2.5-pro',
                    child: Text(tr('Gemini 2.5 Pro (Chất lượng cao)'))),
                DropdownMenuItem(
                    value: 'gemini-2.0-flash', child: Text(tr('Gemini 2.0 Flash'))),
                DropdownMenuItem(
                    value: 'gemini-2.0-flash-lite',
                    child: Text(tr('Gemini 2.0 Flash Lite (Siêu nhanh)'))),
              ],
              helpSteps: const [
                _HelpStep(1, 'Truy cập Google AI Studio',
                    'https://aistudio.google.com/apikey'),
                _HelpStep(2, 'Đăng nhập bằng tài khoản Google', null),
                _HelpStep(3, 'Nhấn "Create API Key" hoặc "Tạo API Key"', null),
                _HelpStep(4, 'Copy API Key và dán vào ô phía trên', null),
              ],
              helpNote: 'Gemini API miễn phí với giới hạn 15 request/phút.',
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
      padding: HrmSettingsMobileKit.active(context)
          ? HrmSettingsMobileKit.pagePadding(context)
          : EdgeInsets.all(isMobile ? 14 : 24),
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
                _buildModelSettingsSection(modelController, maxTokensController,
                    temperatureController, modelItems, isMobile),
                const SizedBox(height: 24),
                _buildTestSection(configured),
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
    final accent = gradientColors.isNotEmpty
        ? gradientColors.first
        : PosTheme.kiotBlue;
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(isMobile ? 10 : 16),
          decoration: BoxDecoration(
            color: PosTheme.kiotBlueLight,
            borderRadius: BorderRadius.circular(isMobile ? 12 : 16),
          ),
          child: Icon(icon, color: accent, size: isMobile ? 24 : 32),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr(name),
                  style: TextStyle(
                      fontSize: isMobile ? 17 : 22,
                      fontWeight: FontWeight.bold,
                      color: PosTheme.textPrimary)),
              const SizedBox(height: 4),
              Text(tr('Tích hợp AI để tự động tạo nội dung'),
                  style: TextStyle(
                      color: Colors.grey[600], fontSize: isMobile ? 12 : 14)),
            ],
          ),
        ),
        Column(
          children: [
            Switch(
              value: enabled,
              onChanged: _isSaving ? null : onToggle,
              activeThumbColor: PosTheme.kiotBlue,
            ),
            Text(tr(enabled ? 'Đang bật' : 'Đang tắt'),
                style: TextStyle(
                    fontSize: 11,
                    color: enabled ? const Color(0xFF16A34A) : Colors.grey[500],
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
                Text(tr(title),
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: textColor)),
                const SizedBox(height: 2),
                Text(tr(subtitle),
                    style: TextStyle(fontSize: 13, color: Colors.grey[600])),
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
                  child: Text(tr('Key hiện tại: $maskedKey'),
                      style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                          color: Color(0xFF71717A))),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(tr('Nhập API Key mới (để trống nếu không đổi):'),
              style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
          const SizedBox(height: 8),
        ] else ...[
          Text(tr('Nhập API Key:'),
              style: TextStyle(fontSize: 13, color: Color(0xFF71717A))),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          obscureText: obscure,
          decoration: InputDecoration(
            hintText: tr('sk-... hoặc AIza...'),
            prefixIcon: const Icon(Icons.vpn_key, size: 20),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility,
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
                borderSide:
                    const BorderSide(color: Color(0xFF2D5F8B), width: 2)),
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
      iconColor: HrmPageChrome.primaryNavy,
      children: [
        Text(tr('Model'),
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
              Text(tr('Độ dài tối đa (tokens)'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF52525B))),
              const SizedBox(height: 6),
              TextFormField(
                controller: maxTokensController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: tr('2048'),
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
            ],
          ),
          const SizedBox(height: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tr('Độ sáng tạo / Temperature (0.0 - 2.0)'),
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
                  hintText: tr('0.7'),
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
            ],
          ),
        ] else
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('Độ dài tối đa (tokens)'),
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF52525B))),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: maxTokensController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: tr('2048'),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7))),
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
                    Text(tr('Độ sáng tạo / Temperature (0.0 - 2.0)'),
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
                        hintText: tr('0.7'),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7))),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE4E4E7))),
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
        Text(tr('💡 Temperature thấp (0.1-0.3): chính xác, nhất quán. Cao (0.7-1.5): sáng tạo, đa dạng.'),
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
      ],
    );
  }

  Widget _buildTestSection(bool configured) {
    return _buildCard(
      title: 'Kiểm tra kết nối',
      icon: Icons.science,
      iconColor: HrmPageChrome.primaryNavy,
      children: [
        Text(tr('Gửi yêu cầu thử để kiểm tra API Key và kết nối.'),
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_isTesting || !configured) ? null : _testConnection,
            icon: _isTesting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.play_arrow),
            label: Text(tr(_isTesting ? 'Đang kiểm tra...' : 'Kiểm tra kết nối')),
            style: OutlinedButton.styleFrom(
              foregroundColor: HrmPageChrome.primaryNavy,
              side: const BorderSide(color: HrmPageChrome.primaryNavy),
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
                  _testSuccess == true ? Icons.check_circle : Icons.error,
                  color: _testSuccess == true
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFDC2626),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr(_testResult!),
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
    if (!_perm.canEdit('AIGemini')) return const SizedBox.shrink();
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton.icon(
        onPressed: _isSaving ? null : onSave,
        icon: _isSaving
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.save),
        label: Text(
          tr(_isSaving ? 'Đang lưu...' : 'Lưu cấu hình'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: HrmPageChrome.primaryNavy,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 2,
        ),
      ),
    );
  }

  Widget _buildHelpSection(List<_HelpStep> steps, String note) {
    return _buildCard(
      title: 'Hướng dẫn lấy API Key',
      icon: Icons.help_outline,
      iconColor: HrmPageChrome.primaryNavy,
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
              const Icon(Icons.info, size: 18, color: HrmPageChrome.primaryNavy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(tr(note),
                    style: TextStyle(fontSize: 13, color: Colors.grey[700])),
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
              child: Text(tr('$number'),
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
                Text(tr(title),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                if (subtitle != null)
                  Text(tr(subtitle),
                      style: TextStyle(fontSize: 12, color: Colors.blue[600])),
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
              Text(tr(title),
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
