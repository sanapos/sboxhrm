import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/dashboard.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';

class GoogleSheetsScreen extends StatefulWidget {
  const GoogleSheetsScreen({super.key});

  @override
  State<GoogleSheetsScreen> createState() => _GoogleSheetsScreenState();
}

class _GoogleSheetsScreenState extends State<GoogleSheetsScreen> {
  final ApiService _apiService = ApiService();

  final _spreadsheetIdController = TextEditingController();
  final _credentialsPathController =
      TextEditingController(text: 'credentials.json');

  bool _isConnected = false;
  bool _isLoading = false;
  DateTime _syncDate = DateTime.now();
  SyncAllResult? _lastSyncResult;

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    if (isError) {
      appNotification.showError(title: 'Lỗi', message: message);
    } else {
      appNotification.showSuccess(title: 'Thành công', message: message);
    }
  }

  Future<void> _testConnection() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.testGoogleSheetsConnection();
      if (!mounted) return;
      setState(() => _isConnected = result);
      if (result) {
        _showSnackBar('Kết nối Google Sheets thành công!');
      } else {
        _showSnackBar('Không thể kết nối', isError: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isConnected = false);
      _showSnackBar('Lỗi: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initializeSheet() async {
    if (_spreadsheetIdController.text.isEmpty) {
      _showSnackBar('Vui lòng nhập Spreadsheet ID', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await _apiService.initializeGoogleSheets(
        _spreadsheetIdController.text,
        _credentialsPathController.text,
      );
      if (result) {
        setState(() => _isConnected = true);
        _showSnackBar('Đã khởi tạo Google Sheets thành công!');
      } else {
        _showSnackBar('Không thể khởi tạo', isError: true);
      }
    } catch (e) {
      _showSnackBar('Lỗi: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncDevices() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.syncDevicesToSheets();
      if (result) {
        _showSnackBar('Đồng bộ thiết bị thành công!');
      } else {
        _showSnackBar('Không thể đồng bộ thiết bị', isError: true);
      }
    } catch (e) {
      _showSnackBar('Lỗi: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncEmployees() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.syncEmployeesToSheets();
      if (result) {
        _showSnackBar('Đồng bộ nhân viên thành công!');
      } else {
        _showSnackBar('Không thể đồng bộ nhân viên', isError: true);
      }
    } catch (e) {
      _showSnackBar('Lỗi: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncAttendances() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_syncDate);
      final result = await _apiService.syncAttendancesToSheets(dateStr);
      if (result) {
        _showSnackBar('Đồng bộ chấm công thành công!');
      } else {
        _showSnackBar('Không thể đồng bộ chấm công', isError: true);
      }
    } catch (e) {
      _showSnackBar('Lỗi: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _syncAll() async {
    setState(() => _isLoading = true);
    try {
      final result = await _apiService.syncAllToSheets();
      if (result != null) {
        setState(() => _lastSyncResult = SyncAllResult.fromJson(result));
        _showSnackBar('Đồng bộ tất cả dữ liệu thành công!');
      } else {
        _showSnackBar('Không thể đồng bộ', isError: true);
      }
    } catch (e) {
      _showSnackBar('Lỗi: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _syncDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(
              primary: Theme.of(context).primaryColor,
              onPrimary: Colors.white,
              surface: const Color(0xFF18181B),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _syncDate) {
      setState(() => _syncDate = picked);
    }
  }

  @override
  void dispose() {
    _spreadsheetIdController.dispose();
    _credentialsPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildConfigurationCard(),
            const SizedBox(height: 24),
            _buildSyncActionsGrid(),
            const SizedBox(height: 24),
            if (_lastSyncResult != null) ...[
              _buildSyncResultCard(),
              const SizedBox(height: 24),
            ],
            _buildInstructionsCard(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Google Sheets',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Đồng bộ dữ liệu chấm công realtime lên Google Sheets',
                style: TextStyle(color: Colors.grey[400]),
              ),
            ],
          ),
        ),
        _buildConnectionStatus(),
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _isConnected
            ? Colors.green.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _isConnected ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected ? Icons.check_circle : Icons.cancel,
            size: 18,
            color: _isConnected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            _isConnected ? 'Đã kết nối' : 'Chưa kết nối',
            style: TextStyle(
              color: _isConnected ? Colors.green : Colors.red,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.table_chart,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cấu hình Google Sheets',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Nhập thông tin để kết nối với Google Sheets của bạn',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Spreadsheet ID
            TextField(
              controller: _spreadsheetIdController,
              decoration: InputDecoration(
                labelText: 'Spreadsheet ID',
                hintText: '1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms',
                prefixIcon: const Icon(Icons.link),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    if (_spreadsheetIdController.text.isNotEmpty) {
                      Clipboard.setData(
                          ClipboardData(text: _spreadsheetIdController.text));
                      _showSnackBar('Đã sao chép Spreadsheet ID');
                    }
                  },
                  tooltip: 'Sao chép',
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'ID lấy từ URL: docs.google.com/spreadsheets/d/ID_HERE/edit',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            const SizedBox(height: 16),

            // Credentials Path
            TextField(
              controller: _credentialsPathController,
              decoration: const InputDecoration(
                labelText: 'Đường dẫn Credentials',
                hintText: 'credentials.json',
                prefixIcon: Icon(Icons.folder),
              ),
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _initializeSheet,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload),
                    label: const Text('Khởi tạo'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _testConnection,
                    icon: _isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).primaryColor,
                            ),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Kiểm tra kết nối'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncActionsGrid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 800
            ? 4
            : constraints.maxWidth > 500
                ? 2
                : 1;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: crossAxisCount == 1 ? 2.5 : 1.2,
          children: [
            _buildSyncCard(
              title: 'Thiết bị',
              icon: Icons.devices,
              color: Colors.blue,
              buttonText: 'Đồng bộ thiết bị',
              onPressed: _isConnected && !_isLoading ? _syncDevices : null,
            ),
            _buildSyncCard(
              title: 'Nhân viên',
              icon: Icons.people,
              color: Colors.purple,
              buttonText: 'Đồng bộ nhân viên',
              onPressed: _isConnected && !_isLoading ? _syncEmployees : null,
            ),
            _buildSyncCardWithDate(
              title: 'Chấm công',
              icon: Icons.calendar_today,
              color: Colors.orange,
              buttonText: 'Đồng bộ chấm công',
              onPressed: _isConnected && !_isLoading ? _syncAttendances : null,
            ),
            _buildSyncCard(
              title: 'Đồng bộ tất cả',
              icon: Icons.cloud_upload,
              color: Theme.of(context).primaryColor,
              buttonText: 'Đồng bộ tất cả',
              onPressed: _isConnected && !_isLoading ? _syncAll : null,
              isPrimary: true,
            ),
          ],
        );
      },
    );
  }

  Widget _buildSyncCard({
    required String title,
    required IconData icon,
    required Color color,
    required String buttonText,
    required VoidCallback? onPressed,
    bool isPrimary = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: isPrimary
                  ? ElevatedButton(
                      onPressed: onPressed,
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(buttonText),
                    )
                  : OutlinedButton(
                      onPressed: onPressed,
                      child: _isLoading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Theme.of(context).primaryColor,
                              ),
                            )
                          : Text(
                              buttonText,
                              style: const TextStyle(fontSize: 13),
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncCardWithDate({
    required String title,
    required IconData icon,
    required Color color,
    required String buttonText,
    required VoidCallback? onPressed,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _selectDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE4E4E7)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.date_range, size: 16, color: Color(0xFF71717A)),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('dd/MM/yyyy').format(_syncDate),
                      style: const TextStyle(color: Color(0xFF18181B), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: onPressed,
                child: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).primaryColor,
                        ),
                      )
                    : Text(
                        buttonText,
                        style: const TextStyle(fontSize: 13),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncResultCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.analytics,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Kết quả đồng bộ gần nhất',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildResultItem(
                    label: 'Thiết bị',
                    count: _lastSyncResult!.devicesCount,
                    isSuccess: _lastSyncResult!.devicesSynced,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildResultItem(
                    label: 'Nhân viên',
                    count: _lastSyncResult!.employeesCount,
                    isSuccess: _lastSyncResult!.employeesSynced,
                    color: Colors.purple,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildResultItem(
                    label: 'Chấm công',
                    count: _lastSyncResult!.attendancesCount,
                    isSuccess: _lastSyncResult!.attendancesSynced,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultItem({
    required String label,
    required int count,
    required bool isSuccess,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E4E7)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSuccess ? Icons.check_circle : Icons.cancel,
                size: 20,
                color: isSuccess ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                count.toString(),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF71717A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.help_outline,
                    color: Colors.amber,
                  ),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Hướng dẫn cài đặt',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInstructionStep(
              stepNumber: 1,
              title: 'Tạo Service Account trên Google Cloud Console',
              instructions: [
                'Truy cập Google Cloud Console (console.cloud.google.com)',
                'Tạo project mới hoặc chọn project có sẵn',
                'Vào APIs & Services → Enable Google Sheets API',
                'Vào IAM & Admin → Service Accounts → Create Service Account',
                'Tạo key JSON và download file credentials',
              ],
            ),
            const Divider(height: 32),
            _buildInstructionStep(
              stepNumber: 2,
              title: 'Chia sẻ Google Sheet với Service Account',
              instructions: [
                'Mở file credentials.json, copy email của service account',
                'Mở Google Sheet và chia sẻ (Share) với email đó với quyền Editor',
              ],
            ),
            const Divider(height: 32),
            _buildInstructionStep(
              stepNumber: 3,
              title: 'Cấu hình trong ứng dụng',
              instructions: [
                'Copy file credentials.json vào thư mục API',
                'Nhập Spreadsheet ID từ URL của Google Sheet',
                'Click "Khởi tạo" để tạo các sheet cần thiết',
              ],
            ),
            const Divider(height: 32),
            _buildInstructionStep(
              stepNumber: 4,
              title: 'Tính năng Realtime',
              instructions: [
                'Khi máy chấm công ADMS gửi dữ liệu lên server, dữ liệu sẽ tự động được đẩy lên Google Sheet trong tab "Attendance".',
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionStep({
    required int stepNumber,
    required String title,
    required List<String> instructions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  stepNumber.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.only(left: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: instructions.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.key + 1}. ',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 13,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
