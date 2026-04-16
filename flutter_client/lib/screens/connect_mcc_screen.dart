import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/device.dart';
import '../services/api_service.dart';
import '../widgets/notification_overlay.dart';

class ConnectMccScreen extends StatefulWidget {
  const ConnectMccScreen({super.key});

  @override
  State<ConnectMccScreen> createState() => _ConnectMccScreenState();
}

class _ConnectMccScreenState extends State<ConnectMccScreen> {
  final ApiService _apiService = ApiService();
  List<Device> _myDevices = [];
  List<Device> _availableDevices = []; // Thiết bị trong ADMS chưa được kết nối
  bool _isLoading = true;
  bool _isConnecting = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Lấy thiết bị của tôi
      final myData = await _apiService.getMyDevices();
      
      // Lấy tất cả thiết bị ADMS đã kết nối để kiểm tra
      final pendingData = await _apiService.getPendingDevices();
      final connectedData = await _apiService.getConnectedDevices();
      
      // Kết hợp pending + connected = available devices
      final Map<String, Device> availableMap = {};
      for (var data in pendingData) {
        final device = Device.fromJson(data);
        // Chỉ lấy thiết bị chưa được claim
        if (!(data['isClaimed'] ?? false)) {
          availableMap[device.serialNumber] = device;
        }
      }
      for (var data in connectedData) {
        final device = Device.fromJson(data);
        if (!(data['isClaimed'] ?? false)) {
          availableMap[device.serialNumber] = device;
        }
      }

      if (mounted) {
        setState(() {
          _myDevices = myData.map((e) => Device.fromJson(e)).toList();
          _availableDevices = availableMap.values.toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        _showError('Không thể tải dữ liệu: $e');
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    appNotification.showError(title: 'Lỗi', message: message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    appNotification.showSuccess(title: 'Thành công', message: message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Kết Nối MCC', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
        actions: const [],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Form thêm thiết bị mới
                    _buildAddDeviceSection(),
                    
                    const SizedBox(height: 24),
                    
                    // Danh sách thiết bị có sẵn trong ADMS
                    if (_availableDevices.isNotEmpty) ...[
                      _buildAvailableDevicesSection(),
                      const SizedBox(height: 24),
                    ],
                    
                    // Danh sách thiết bị của tôi
                    _buildMyDevicesSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAddDeviceSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E3A5F).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_circle, color: Color(0xFF1E3A5F)),
              ),
              const SizedBox(width: 12),
              const Text(
                'Thêm Máy Chấm Công Mới',
                style: TextStyle(
                  color: Color(0xFF18181B),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Nhập số Serial (SN) trên máy chấm công để kết nối',
            style: TextStyle(color: Color(0xFF71717A), fontSize: 14),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () => _showAddDeviceDialog(),
            icon: const Icon(Icons.qr_code),
            label: const Text('Thêm thiết bị bằng SN'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailableDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.wifi_tethering, color: Color(0xFFF59E0B)),
            const SizedBox(width: 8),
            const Text(
              'Thiết Bị Sẵn Sàng Kết Nối',
              style: TextStyle(
                color: Color(0xFF18181B),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_availableDevices.length}',
                style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Các thiết bị đã kết nối đến server ADMS và chưa được đăng ký',
          style: TextStyle(color: Color(0xFF71717A), fontSize: 13),
        ),
        const SizedBox(height: 12),
        ...(_availableDevices.map((device) => _buildAvailableDeviceCard(device))),
      ],
    );
  }

  Widget _buildAvailableDeviceCard(Device device) {
    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.devices, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.qr_code, size: 14, color: Color(0xFFA1A1AA)),
                      const SizedBox(width: 4),
                      Text(
                        device.serialNumber,
                        style: const TextStyle(
                          color: Color(0xFF18181B),
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (device.ipAddress != null) ...[
                        const Icon(Icons.lan, size: 12, color: Color(0xFFA1A1AA)),
                        const SizedBox(width: 4),
                        Text(
                          device.ipAddress!,
                          style: const TextStyle(color: Color(0xFF71717A), fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Icon(
                        device.isOnline ? Icons.wifi : Icons.wifi_off,
                        size: 12,
                        color: device.isOnline ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        device.isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          color: device.isOnline ? Colors.green : Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: _isConnecting ? null : () => _connectAvailableDevice(device),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
              ),
              child: _isConnecting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Kết nối'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.devices, color: Color(0xFF1E3A5F)),
            const SizedBox(width: 8),
            const Text(
              'Thiết Bị Của Tôi',
              style: TextStyle(
                color: Color(0xFF18181B),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_myDevices.length}',
                style: const TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        if (_myDevices.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.devices_other, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text(
                    'Chưa có thiết bị nào',
                    style: TextStyle(color: Color(0xFF71717A), fontSize: 16),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Thêm thiết bị bằng cách nhập SN hoặc chọn từ danh sách sẵn sàng',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFA1A1AA), fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...(_myDevices.map((device) => _buildMyDeviceCard(device))),
      ],
    );
  }

  Widget _buildMyDeviceCard(Device device) {
    final isOnline = device.isOnline;
    final statusColor = isOnline ? Colors.green : Colors.red;

    return Card(
      color: Colors.white,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isOnline ? Colors.green.withValues(alpha: 0.3) : const Color(0xFFE4E4E7),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.devices, color: statusColor, size: 24),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName,
                        style: const TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.qr_code, size: 14, color: Color(0xFFA1A1AA)),
                          const SizedBox(width: 4),
                          Text(
                            device.serialNumber,
                            style: const TextStyle(color: Color(0xFF71717A), fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isOnline ? Icons.wifi : Icons.wifi_off,
                        size: 14,
                        color: statusColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(color: statusColor, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 12),
              const Divider(color: Color(0xFFE4E4E7), height: 1),
            const SizedBox(height: 12),
            
            // Info row
            Row(
              children: [
                if (device.ipAddress != null) ...[
                  const Icon(Icons.lan, size: 14, color: Color(0xFF1E3A5F)),
                  const SizedBox(width: 4),
                  Text(
                    device.ipAddress!,
                    style: const TextStyle(color: Color(0xFF1E3A5F), fontSize: 12),
                  ),
                  const SizedBox(width: 16),
                ],
                if (device.location != null && device.location!.isNotEmpty) ...[
                  const Icon(Icons.location_on, size: 14, color: Color(0xFFF59E0B)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      device.location!,
                      style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
            
            const SizedBox(height: 12),
            
            // Actions
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _showDeviceInfo(device),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Chi tiết'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1E3A5F),
                    side: const BorderSide(color: Color(0xFF1E3A5F)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _confirmDeleteDevice(device),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Xóa'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showAddDeviceDialog() {
    final snController = TextEditingController();
    final nameController = TextEditingController();
    bool isChecking = false;
    String? checkResult;
    bool isAvailable = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.add_circle, color: Color(0xFF1E3A5F)),
              SizedBox(width: 12),
              Text('Thêm Máy Chấm Công', style: TextStyle(color: Color(0xFF18181B))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // SN Input
                TextField(
                  controller: snController,
                  style: const TextStyle(color: Color(0xFF18181B)),
                  decoration: InputDecoration(
                    labelText: 'Số Serial (SN) *',
                    labelStyle: const TextStyle(color: Color(0xFF71717A)),
                    hintText: 'VD: 1313232261894',
                    hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                    prefixIcon: const Icon(Icons.qr_code, color: Color(0xFF71717A)),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                    ),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Barcode scan button
                        IconButton(
                          icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF0C56D0)),
                          tooltip: 'Quét mã barcode',
                          onPressed: () async {
                            final code = await showDialog<String>(
                              context: context,
                              builder: (scanCtx) => _BarcodeScannerDialog(),
                            );
                            if (code != null && code.isNotEmpty) {
                              snController.text = code;
                              // Trigger check
                              setDialogState(() {
                                isChecking = true;
                                checkResult = null;
                              });
                              final availableDevice = _availableDevices.firstWhere(
                                (d) => d.serialNumber == code.trim(),
                                orElse: () => Device(id: '', deviceName: '', serialNumber: '', isActive: false),
                              );
                              if (availableDevice.id.isNotEmpty) {
                                setDialogState(() {
                                  isChecking = false;
                                  isAvailable = true;
                                  checkResult = '✅ Thiết bị tìm thấy và sẵn sàng kết nối!';
                                  if (nameController.text.isEmpty) nameController.text = 'Máy chấm công $code';
                                });
                              } else {
                                final result = await _apiService.checkSerialNumber(code.trim());
                                setDialogState(() {
                                  isChecking = false;
                                  isAvailable = result['exists'] == true && result['isAvailable'] == true;
                                  if (isAvailable) {
                                    checkResult = '✅ Thiết bị sẵn sàng kết nối!';
                                    if (nameController.text.isEmpty) nameController.text = 'Máy chấm công $code';
                                  } else if (result['exists'] == false) {
                                    checkResult = '⚠️ Thiết bị chưa kết nối đến server.';
                                  } else if (result['isClaimed'] == true) {
                                    checkResult = '❌ Thiết bị đã được đăng ký bởi người khác';
                                  } else {
                                    checkResult = result['message'] ?? 'Không thể kiểm tra';
                                  }
                                });
                              }
                            }
                          },
                        ),
                        // Search/check button
                        IconButton(
                      icon: isChecking
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search, color: Color(0xFF1E3A5F)),
                      onPressed: isChecking
                          ? null
                          : () async {
                              if (snController.text.isEmpty) return;
                              setDialogState(() {
                                isChecking = true;
                                checkResult = null;
                              });
                              
                              // Kiểm tra trong danh sách available
                              final availableDevice = _availableDevices.firstWhere(
                                (d) => d.serialNumber == snController.text.trim(),
                                orElse: () => Device(
                                  id: '',
                                  deviceName: '',
                                  serialNumber: '',
                                  isActive: false,
                                ),
                              );
                              
                              if (availableDevice.id.isNotEmpty) {
                                setDialogState(() {
                                  isChecking = false;
                                  isAvailable = true;
                                  checkResult = '✅ Thiết bị tìm thấy và sẵn sàng kết nối!';
                                  if (nameController.text.isEmpty) {
                                    nameController.text = 'Máy chấm công ${snController.text}';
                                  }
                                });
                              } else {
                                // Kiểm tra từ server
                                final result = await _apiService.checkSerialNumber(snController.text.trim());
                                setDialogState(() {
                                  isChecking = false;
                                  isAvailable = result['exists'] == true && result['isAvailable'] == true;
                                  if (isAvailable) {
                                    checkResult = '✅ Thiết bị sẵn sàng kết nối!';
                                    if (nameController.text.isEmpty) {
                                      nameController.text = 'Máy chấm công ${snController.text}';
                                    }
                                  } else if (result['error'] == true) {
                                    checkResult = '❌ ${result['message']}';
                                  } else if (result['isClaimed'] == true) {
                                    checkResult = '❌ Thiết bị đã được đăng ký bởi người khác';
                                  } else if (result['exists'] == false) {
                                    checkResult = '⚠️ Thiết bị chưa kết nối đến server.\nHãy đảm bảo máy chấm công đã được cấu hình ADMS đúng địa chỉ server và số seri đúng.';
                                  } else {
                                    checkResult = result['message'] ?? 'Không thể kiểm tra';
                                  }
                                });
                              }
                            },
                        ),
                      ],
                    ),
                  ),
                  onChanged: (_) {
                    setDialogState(() {
                      checkResult = null;
                      isAvailable = false;
                    });
                  },
                ),
                
                // Check result
                if (checkResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isAvailable 
                          ? Colors.green.withValues(alpha: 0.1)
                          : Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isAvailable ? Icons.check_circle : Icons.warning,
                          color: isAvailable ? Colors.green : Colors.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            checkResult!,
                            style: TextStyle(
                              color: isAvailable ? Colors.green : Colors.orange,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 16),
                
                // Name Input
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Color(0xFF18181B)),
                  decoration: InputDecoration(
                    labelText: 'Tên máy chấm công *',
                    labelStyle: const TextStyle(color: Color(0xFF71717A)),
                    hintText: 'VD: Máy chấm công Tầng 1',
                    hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                    prefixIcon: const Icon(Icons.label, color: Color(0xFF71717A)),
                    filled: true,
                    fillColor: const Color(0xFFFAFAFA),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
                
                // Info
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF1E3A5F), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Số SN được in trên nhãn máy chấm công hoặc trong menu thông tin thiết bị.',
                          style: TextStyle(color: Color(0xFF1E3A5F), fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
            ),
            ElevatedButton(
              onPressed: (isAvailable && nameController.text.isNotEmpty)
                  ? () async {
                      Navigator.pop(context);
                      await _connectDevice(snController.text.trim(), nameController.text.trim());
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A5F),
                foregroundColor: Colors.white,
              ),
              child: const Text('Kết nối'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _connectAvailableDevice(Device device) async {
    final nameController = TextEditingController(text: 'Máy chấm công ${device.serialNumber}');
    
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Đặt tên thiết bị', style: TextStyle(color: Color(0xFF18181B))),
        content: SingleChildScrollView(
          child: TextField(
            controller: nameController,
            style: const TextStyle(color: Color(0xFF18181B)),
            decoration: InputDecoration(
              labelText: 'Tên máy chấm công',
              labelStyle: const TextStyle(color: Color(0xFF71717A)),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
              ),
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E3A5F),
            ),
            child: const Text('Kết nối'),
          ),
        ],
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      await _connectDevice(device.serialNumber, result);
    }
  }

  Future<void> _connectDevice(String serialNumber, String deviceName) async {
    setState(() => _isConnecting = true);
    
    try {
      final result = await _apiService.claimDevice(
        serialNumber: serialNumber,
        deviceName: deviceName,
      );
      
      if (result['success'] == true) {
        _showSuccess('Đã kết nối thiết bị thành công!');
        await _loadData();
      } else {
        _showError(result['message'] ?? 'Không thể kết nối thiết bị');
      }
    } catch (e) {
      _showError('Lỗi: $e');
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  void _showDeviceInfo(Device device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE4E4E7),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: (device.isOnline ? Colors.green : Colors.red).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.devices,
                    color: device.isOnline ? Colors.green : Colors.red,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.deviceName,
                        style: const TextStyle(
                          color: Color(0xFF18181B),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        device.isOnline ? '● Online' : '● Offline',
                        style: TextStyle(
                          color: device.isOnline ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildInfoRow('Serial Number', device.serialNumber, Icons.qr_code, const Color(0xFF1E3A5F)),
            if (device.ipAddress != null)
              _buildInfoRow('Địa chỉ IP', device.ipAddress!, Icons.lan, const Color(0xFF2D5F8B)),
            if (device.location != null && device.location!.isNotEmpty)
              _buildInfoRow('Vị trí', device.location!, Icons.location_on, const Color(0xFFF59E0B)),
            _buildInfoRow(
              'Trạng thái',
              device.isActive ? 'Đang hoạt động' : 'Không hoạt động',
              Icons.info,
              device.isActive ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
                Text(value, style: const TextStyle(color: Color(0xFF18181B), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDevice(Device device) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning, color: Color(0xFFEF4444)),
            SizedBox(width: 12),
            Text('Xác nhận xóa', style: TextStyle(color: Color(0xFF18181B))),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa thiết bị "${device.deviceName}"?\n\nThiết bị sẽ được trả về danh sách sẵn sàng và có thể được đăng ký lại.',
          style: const TextStyle(color: Color(0xFF71717A)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final result = await _apiService.unclaimDevice(device.id);
              if (result['success'] == true) {
                _showSuccess('Đã xóa thiết bị');
                await _loadData();
              } else {
                _showError(result['message'] ?? 'Không thể xóa thiết bị');
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
  }
}

// ==================== BARCODE SCANNER DIALOG ====================
class _BarcodeScannerDialog extends StatefulWidget {
  @override
  State<_BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<_BarcodeScannerDialog> {
  MobileScannerController? _scannerController;
  bool _hasScanned = false;
  String? _cameraError;
  bool _showManualInput = false;
  final _manualController = TextEditingController();
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    try {
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: CameraFacing.back,
        formats: [
          BarcodeFormat.code128,
          BarcodeFormat.code39,
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.qrCode,
        ],
      );
    } catch (e) {
      _cameraError = 'Không thể khởi tạo camera: $e';
    }
  }

  @override
  void dispose() {
    _scannerController?.dispose();
    _manualController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 400,
        height: 460,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0C56D0),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.qr_code_scanner, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text('Quét mã Barcode / QR', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _showManualInput
                  ? _buildManualInput()
                  : (_scannerController != null
                      ? Stack(
                          children: [
                            ClipRRect(
                              child: MobileScanner(
                                controller: _scannerController!,
                                errorBuilder: (context, error) {
                                  return _buildCameraError(
                                    error.errorDetails?.message ?? 'Không thể truy cập camera',
                                  );
                                },
                                onDetect: (capture) {
                                  if (_hasScanned) return;
                                  final barcodes = capture.barcodes;
                                  if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                                    _hasScanned = true;
                                    Navigator.pop(context, barcodes.first.rawValue!);
                                  }
                                },
                              ),
                            ),
                            // Scan guide overlay
                            Center(
                              child: Container(
                                width: 260,
                                height: 100,
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            // Torch toggle
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: IconButton(
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  padding: const EdgeInsets.all(10),
                                ),
                                icon: Icon(
                                  _torchOn ? Icons.flash_on : Icons.flash_off,
                                  color: _torchOn ? Colors.amber : Colors.white,
                                  size: 24,
                                ),
                                onPressed: () {
                                  _scannerController?.toggleTorch();
                                  setState(() => _torchOn = !_torchOn);
                                },
                              ),
                            ),
                          ],
                        )
                      : _buildCameraError(_cameraError ?? 'Camera không khả dụng')),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              child: _showManualInput
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        const Text(
                          'Hướng camera vào mã barcode trên máy chấm công',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF586064), fontSize: 13),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => setState(() => _showManualInput = true),
                          icon: const Icon(Icons.keyboard, size: 16),
                          label: const Text('Nhập thủ công', style: TextStyle(fontSize: 12)),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off, color: Colors.red, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red, fontSize: 13)),
            const SizedBox(height: 8),
            const Text(
              'Vui lòng kiểm tra:\n• Quyền camera trong trình duyệt\n• Kết nối qua HTTPS hoặc localhost',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF586064), fontSize: 11),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => setState(() => _showManualInput = true),
              icon: const Icon(Icons.keyboard, size: 16),
              label: const Text('Nhập mã thủ công'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C56D0), foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualInput() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code, color: Color(0xFF0C56D0), size: 40),
          const SizedBox(height: 12),
          const Text('Nhập mã Serial Number', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 16),
          TextField(
            controller: _manualController,
            decoration: InputDecoration(
              hintText: 'Nhập SN máy chấm công...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _showManualInput = false),
                child: const Text('Quay lại camera'),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: () {
                  final text = _manualController.text.trim();
                  if (text.isNotEmpty) Navigator.pop(context, text);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0C56D0), foregroundColor: Colors.white),
                child: const Text('Xác nhận'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
