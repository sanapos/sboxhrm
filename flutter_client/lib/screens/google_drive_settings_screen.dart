import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';
import 'settings_hub_screen.dart';

/// Màn hình cấu hình Google Drive storage
/// Cho phép SuperAdmin/Admin thiết lập lưu trữ ảnh trên Google Drive
class GoogleDriveSettingsScreen extends StatefulWidget {
  const GoogleDriveSettingsScreen({super.key});

  @override
  State<GoogleDriveSettingsScreen> createState() => _GoogleDriveSettingsScreenState();
}

class _GoogleDriveSettingsScreenState extends State<GoogleDriveSettingsScreen> {
  final _credentialsController = TextEditingController();
  final _folderIdController = TextEditingController();
  final _folderNameController = TextEditingController();
  
  final _apiService = ApiService();
  
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isTesting = false;
  bool _isEnabled = false;
  bool _hasCredentials = false;
  String _credentialsSummary = '';
  
  // Test result
  String? _testMessage;
  bool? _testSuccess;
  double? _usedGB;
  double? _limitGB;
  int? _fileCount;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadConfig());
  }

  @override
  void dispose() {
    _credentialsController.dispose();
    _folderIdController.dispose();
    _folderNameController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.getGoogleDriveConfig();
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        _isEnabled = data['isEnabled'] ?? false;
        _hasCredentials = data['hasCredentials'] ?? false;
        _credentialsSummary = data['credentialsSummary'] ?? '';
        _folderIdController.text = data['folderId'] ?? '';
        _folderNameController.text = data['folderName'] ?? '';
      }
    } catch (e) {
      debugPrint('Error loading Google Drive config: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final data = <String, dynamic>{
        'isEnabled': _isEnabled,
      };

      if (_credentialsController.text.isNotEmpty) {
        data['credentialsJson'] = _credentialsController.text.trim();
      }

      if (_folderIdController.text.isNotEmpty) {
        data['folderId'] = _folderIdController.text.trim();
      }

      data['folderName'] = _folderNameController.text.trim();

      final result = await _apiService.updateGoogleDriveConfig(data);
      if (result['isSuccess'] == true) {
        appNotification.showSuccess(
          title: 'Thành công',
          message: 'Đã lưu cấu hình Google Drive',
        );
        _credentialsController.clear();
        await _loadConfig();
      } else {
        appNotification.showError(
          title: 'Lỗi',
          message: result['message'] ?? 'Không thể lưu cấu hình',
        );
      }
    } catch (e) {
      appNotification.showError(title: 'Lỗi', message: 'Không thể lưu cấu hình: $e');
    }
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testMessage = null;
      _testSuccess = null;
    });
    try {
      final result = await _apiService.testGoogleDriveConnection();
      if (result['isSuccess'] == true && result['data'] != null) {
        final data = result['data'];
        setState(() {
          _testSuccess = true;
          _testMessage = data['message'] ?? 'Kết nối thành công!';
          _usedGB = (data['usedGB'] as num?)?.toDouble();
          _limitGB = (data['limitGB'] as num?)?.toDouble();
          _fileCount = data['fileCount'] as int?;
        });
      } else {
        setState(() {
          _testSuccess = false;
          _testMessage = result['message'] ?? 'Kết nối thất bại';
        });
      }
    } catch (e) {
      setState(() {
        _testSuccess = false;
        _testMessage = 'Lỗi: $e';
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF18181B)),
          onPressed: () => SettingsHubScreen.goBack(context),
        ),
        title: const Text(
          'Cấu hình Google Drive',
          style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveConfig,
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 18),
                label: Text(_isSaving ? 'Đang lưu...' : 'Lưu cấu hình'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2D5F8B),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header info
                      _buildInfoCard(),
                      const SizedBox(height: 24),

                      // Enable/Disable toggle
                      _buildToggleSection(),
                      const SizedBox(height: 24),

                      // Credentials
                      _buildCredentialsSection(),
                      const SizedBox(height: 24),

                      // Folder config
                      _buildFolderSection(),
                      const SizedBox(height: 24),

                      // Test connection
                      _buildTestSection(),
                      const SizedBox(height: 24),
                      
                      // Setup guide
                      _buildGuideSection(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2D5F8B), Color(0xFF34A853)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.cloud_upload, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Google Drive Storage',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  _isEnabled && _hasCredentials
                      ? '✅ Đang hoạt động - Ảnh được lưu trên Google Drive'
                      : '⚠️ Chưa kích hoạt - Ảnh đang lưu trên server cục bộ',
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleSection() {
    return _buildCard(
      title: 'Kích hoạt Google Drive',
      icon: Icons.toggle_on,
      iconColor: const Color(0xFF34A853),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('Sử dụng Google Drive để lưu trữ'),
            subtitle: Text(
              _isEnabled
                  ? 'Ảnh và file sẽ được upload lên Google Drive'
                  : 'Ảnh và file sẽ lưu trên server cục bộ (wwwroot)',
              style: const TextStyle(fontSize: 13),
            ),
            value: _isEnabled,
            activeThumbColor: const Color(0xFF34A853),
            onChanged: (value) => setState(() => _isEnabled = value),
          ),
          if (_isEnabled && !_hasCredentials)
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFD93D)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Color(0xFFF59E0B), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cần cấu hình Service Account credentials trước khi kích hoạt',
                      style: TextStyle(fontSize: 13, color: Color(0xFF92400E)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCredentialsSection() {
    return _buildCard(
      title: 'Service Account Credentials',
      icon: Icons.key,
      iconColor: const Color(0xFFF4B400),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasCredentials) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF86EFAC)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _credentialsSummary.isNotEmpty ? _credentialsSummary : 'Credentials đã được cấu hình',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF166534)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Nhập JSON mới để thay thế (để trống nếu giữ nguyên):',
              style: TextStyle(fontSize: 13, color: Color(0xFF71717A)),
            ),
          ] else
            const Text(
              'Dán nội dung file JSON Service Account credentials:',
              style: TextStyle(fontSize: 13, color: Color(0xFF71717A)),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _credentialsController,
            maxLines: 6,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: InputDecoration(
              hintText: '{\n  "type": "service_account",\n  "project_id": "...",\n  "client_email": "...@...iam.gserviceaccount.com",\n  ...\n}',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(12),
              suffixIcon: IconButton(
                icon: const Icon(Icons.paste, size: 20),
                tooltip: 'Dán từ clipboard',
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) {
                    _credentialsController.text = data!.text!;
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFolderSection() {
    return _buildCard(
      title: 'Thư mục lưu trữ',
      icon: Icons.folder,
      iconColor: const Color(0xFF2D5F8B),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ID thư mục gốc trên Google Drive (tùy chọn):',
            style: TextStyle(fontSize: 13, color: Color(0xFF71717A)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _folderIdController,
            decoration: InputDecoration(
              hintText: 'Ví dụ: 1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgVE2upms',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              prefixIcon: const Icon(Icons.link, size: 20),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tên thư mục (ghi chú):',
            style: TextStyle(fontSize: 13, color: Color(0xFF71717A)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _folderNameController,
            decoration: InputDecoration(
              hintText: 'Ví dụ: SBOX HRM Uploads',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              prefixIcon: const Icon(Icons.drive_file_rename_outline, size: 20),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Nếu để trống, hệ thống sẽ tạo folder tự động trong Drive của Service Account.',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildTestSection() {
    return _buildCard(
      title: 'Kiểm tra kết nối',
      icon: Icons.speed,
      iconColor: const Color(0xFFEA4335),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilledButton.icon(
                onPressed: _isTesting ? null : _testConnection,
                icon: _isTesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.play_arrow, size: 20),
                label: Text(_isTesting ? 'Đang kiểm tra...' : 'Test kết nối'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF34A853),
                ),
              ),
            ],
          ),
          if (_testMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _testSuccess == true ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _testSuccess == true ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _testSuccess == true ? Icons.check_circle : Icons.error,
                        color: _testSuccess == true ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _testMessage!,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _testSuccess == true ? const Color(0xFF166534) : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_testSuccess == true && _usedGB != null && _limitGB != null) ...[
                    const SizedBox(height: 12),
                    _buildStorageBar(),
                    const SizedBox(height: 8),
                    Text(
                      'Số file: ${_fileCount ?? 0}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF166534)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStorageBar() {
    final usedPercent = (_limitGB != null && _limitGB! > 0) ? (_usedGB! / _limitGB!) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: usedPercent.clamp(0.0, 1.0),
            backgroundColor: const Color(0xFFE4E4E7),
            color: usedPercent > 0.8 ? const Color(0xFFEF4444) : const Color(0xFF2D5F8B),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_usedGB?.toStringAsFixed(2)} GB / ${_limitGB?.toStringAsFixed(2)} GB (${(usedPercent * 100).toStringAsFixed(1)}%)',
          style: const TextStyle(fontSize: 12, color: Color(0xFF71717A)),
        ),
      ],
    );
  }

  Widget _buildGuideSection() {
    return _buildCard(
      title: 'Hướng dẫn thiết lập',
      icon: Icons.help_outline,
      iconColor: const Color(0xFF1E3A5F),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStep(1, 'Truy cập Google Cloud Console', 'https://console.cloud.google.com'),
          _buildStep(2, 'Tạo Project mới hoặc chọn Project có sẵn', null),
          _buildStep(3, 'Bật Google Drive API trong "APIs & Services" → "Library"', null),
          _buildStep(4, 'Tạo Service Account trong "IAM & Admin" → "Service Accounts"', null),
          _buildStep(5, 'Tạo Key JSON cho Service Account, tải file .json', null),
          _buildStep(6, 'Dán nội dung file JSON vào ô Credentials ở trên', null),
          _buildStep(7, '(Tùy chọn) Tạo folder trên Google Drive, chia sẻ cho Service Account email, copy Folder ID', null),
          _buildStep(8, 'Bấm "Test kết nối" để kiểm tra, rồi "Lưu cấu hình"', null),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F9FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF93C5FD)),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info, color: Color(0xFF1E3A5F), size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lưu ý: Service Account miễn phí có 15GB dung lượng. '
                    'File upload sẽ được set public read để hiển thị trực tiếp trong trình duyệt.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF0F2340)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep(int number, String text, String? url) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: const Color(0xFF1E3A5F),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: const TextStyle(fontSize: 13)),
                if (url != null)
                  Text(url, style: const TextStyle(fontSize: 11, color: Color(0xFF2D5F8B))),
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
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF18181B))),
            ],
          ),
          const Divider(height: 32),
          child,
        ],
      ),
    );
  }
}
