import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/device.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';
import '../widgets/app_button.dart';
import 'main_layout.dart' show ScreenRefreshNotifier;

enum DeviceFilter {
  all,
  online,
  offline,
  today,
  thisWeek,
  thisMonth,
}

class AdmsDevicesScreen extends StatefulWidget {
  const AdmsDevicesScreen({super.key});

  @override
  State<AdmsDevicesScreen> createState() => _AdmsDevicesScreenState();
}

class _AdmsDevicesScreenState extends State<AdmsDevicesScreen> {
  final ApiService _apiService = ApiService();
  List<Device> _allDevices = [];
  List<Device> _filteredDevices = [];
  bool _isLoading = true;
  DeviceFilter _currentFilter = DeviceFilter.all;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  Timer? _refreshTimer;
  bool _showMobileFilters = false;

  @override
  void initState() {
    super.initState();
    _loadData();

    // Auto-refresh every 60 seconds so online/offline status stays current
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) _loadDataSilent();
    });

    // Listen for external refresh triggers
    ScreenRefreshNotifier.devices.addListener(_onExternalRefresh);
  }
  
  void _onExternalRefresh() {
    if (mounted) {
      debugPrint('🔄 AdmsDevicesScreen: External refresh triggered');
      _loadData();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    ScreenRefreshNotifier.devices.removeListener(_onExternalRefresh);
    super.dispose();
  }

  /// Silent refresh: updates list without showing the full-screen spinner.
  Future<void> _loadDataSilent() async {
    try {
      final results = await Future.wait([
        _apiService.getPendingDevices(),
        _apiService.getConnectedDevices(),
        _apiService.getDevices(),
      ]);
      final pendingData = results[0];
      final connectedData = results[1];
      final allDevicesData = results[2];

      final Map<String, Device> deviceMap = {};
      for (var data in allDevicesData) {
        final device = Device.fromJson(data);
        deviceMap[device.id] = device;
      }
      for (var data in pendingData) {
        final device = Device.fromJson(data);
        deviceMap[device.id] = device;
      }
      for (var data in connectedData) {
        final device = Device.fromJson(data);
        deviceMap[device.id] = device;
      }

      if (!mounted) return;
      setState(() {
        _allDevices = deviceMap.values.toList();
        _allDevices.sort((a, b) {
          if (a.isOnline && !b.isOnline) return -1;
          if (!a.isOnline && b.isOnline) return 1;
          if (a.lastOnline != null && b.lastOnline != null) {
            return b.lastOnline!.compareTo(a.lastOnline!);
          }
          return 0;
        });
        _applyFilter();
      });
    } catch (_) {
      // Ignore errors on silent refresh to avoid disrupting the user
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Lấy tất cả thiết bị đã kết nối (pending + connected) song song
      final results = await Future.wait([
        _apiService.getPendingDevices(),
        _apiService.getConnectedDevices(),
        _apiService.getDevices(),
      ]);
      final pendingData = results[0];
      final connectedData = results[1];
      final allDevicesData = results[2];
      
      // Kết hợp tất cả thiết bị, loại bỏ trùng lặp
      final Map<String, Device> deviceMap = {};
      
      for (var data in allDevicesData) {
        final device = Device.fromJson(data);
        deviceMap[device.id] = device;
      }
      for (var data in pendingData) {
        final device = Device.fromJson(data);
        deviceMap[device.id] = device;
      }
      for (var data in connectedData) {
        final device = Device.fromJson(data);
        deviceMap[device.id] = device;
      }
      
      setState(() {
        _allDevices = deviceMap.values.toList();
        _allDevices.sort((a, b) {
          // Sắp xếp: online trước, sau đó theo lastOnline
          if (a.isOnline && !b.isOnline) return -1;
          if (!a.isOnline && b.isOnline) return 1;
          if (a.lastOnline != null && b.lastOnline != null) {
            return b.lastOnline!.compareTo(a.lastOnline!);
          }
          return 0;
        });
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        appNotification.showError(
          title: 'Lỗi tải dữ liệu',
          message: '$e',
        );
      }
    }
  }

  void _applyFilter() {
    final now = DateTime.now();
    List<Device> filtered = _allDevices;

    // Áp dụng bộ lọc thời gian/trạng thái
    switch (_currentFilter) {
      case DeviceFilter.online:
        filtered = _allDevices.where((d) => d.isOnline).toList();
        break;
      case DeviceFilter.offline:
        filtered = _allDevices.where((d) => !d.isOnline).toList();
        break;
      case DeviceFilter.today:
        final startOfDay = DateTime(now.year, now.month, now.day);
        filtered = _allDevices.where((d) => 
          d.lastOnline != null && d.lastOnline!.isAfter(startOfDay)
        ).toList();
        break;
      case DeviceFilter.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        filtered = _allDevices.where((d) => 
          d.lastOnline != null && d.lastOnline!.isAfter(startOfWeekDay)
        ).toList();
        break;
      case DeviceFilter.thisMonth:
        final startOfMonth = DateTime(now.year, now.month, 1);
        filtered = _allDevices.where((d) => 
          d.lastOnline != null && d.lastOnline!.isAfter(startOfMonth)
        ).toList();
        break;
      case DeviceFilter.all:
        filtered = _allDevices;
    }

    // Áp dụng tìm kiếm
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((d) =>
        d.serialNumber.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        d.deviceName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (d.ipAddress?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
        (d.location?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false)
      ).toList();
    }

    setState(() {
      _filteredDevices = filtered;
    });
  }

  void _onSearchChanged(String query) {
    _searchQuery = query;
    _applyFilter();
  }

  void _onFilterChanged(DeviceFilter filter) {
    setState(() {
      _currentFilter = filter;
    });
    _applyFilter();
  }

  String _getFilterLabel(DeviceFilter filter) {
    switch (filter) {
      case DeviceFilter.all:
        return 'Tất cả';
      case DeviceFilter.online:
        return 'Đang online';
      case DeviceFilter.offline:
        return 'Offline';
      case DeviceFilter.today:
        return 'Hôm nay';
      case DeviceFilter.thisWeek:
        return 'Tuần này';
      case DeviceFilter.thisMonth:
        return 'Tháng này';
    }
  }

  int _getFilterCount(DeviceFilter filter) {
    final now = DateTime.now();
    switch (filter) {
      case DeviceFilter.all:
        return _allDevices.length;
      case DeviceFilter.online:
        return _allDevices.where((d) => d.isOnline).length;
      case DeviceFilter.offline:
        return _allDevices.where((d) => !d.isOnline).length;
      case DeviceFilter.today:
        final startOfDay = DateTime(now.year, now.month, now.day);
        return _allDevices.where((d) => 
          d.lastOnline != null && d.lastOnline!.isAfter(startOfDay)
        ).length;
      case DeviceFilter.thisWeek:
        final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
        final startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
        return _allDevices.where((d) => 
          d.lastOnline != null && d.lastOnline!.isAfter(startOfWeekDay)
        ).length;
      case DeviceFilter.thisMonth:
        final startOfMonth = DateTime(now.year, now.month, 1);
        return _allDevices.where((d) => 
          d.lastOnline != null && d.lastOnline!.isAfter(startOfMonth)
        ).length;
    }
  }

  Color _getFilterColor(DeviceFilter filter) {
    switch (filter) {
      case DeviceFilter.online:
        return Colors.green;
      case DeviceFilter.offline:
        return Colors.red;
      case DeviceFilter.today:
        return Colors.blue;
      case DeviceFilter.thisWeek:
        return Colors.orange;
      case DeviceFilter.thisMonth:
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  IconData _getFilterIcon(DeviceFilter filter) {
    switch (filter) {
      case DeviceFilter.online:
        return Icons.wifi;
      case DeviceFilter.offline:
        return Icons.wifi_off;
      case DeviceFilter.today:
        return Icons.today;
      case DeviceFilter.thisWeek:
        return Icons.date_range;
      case DeviceFilter.thisMonth:
        return Icons.calendar_month;
      default:
        return Icons.devices;
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineCount = _allDevices.where((d) => d.isOnline).length;
    final neverConnectedCount = _allDevices.where((d) => !d.isOnline && d.hasNeverConnected).length;
    final offlineCount = _allDevices.where((d) => !d.isOnline && !d.hasNeverConnected).length;

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('Máy Chấm Công ADMS', style: TextStyle(color: Color(0xFF18181B), fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis, maxLines: 1),
        actions: [
          // Hiển thị số lượng online/offline
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi, color: Colors.green, size: 16),
                const SizedBox(width: 4),
                Text('$onlineCount', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (neverConnectedCount > 0)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wifi_find, color: Colors.orange, size: 16),
                  const SizedBox(width: 4),
                  Text('$neverConnectedCount', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off, color: Colors.red, size: 16),
                const SizedBox(width: 4),
                Text('$offlineCount', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (Responsive.isMobile(context))
            IconButton(
              icon: Stack(
                children: [
                  Icon(
                    _showMobileFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
                    color: _showMobileFilters ? Colors.orange : const Color(0xFF71717A),
                  ),
                  if (_searchQuery.isNotEmpty || _currentFilter != DeviceFilter.all)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
                      ),
                    ),
                ],
              ),
              onPressed: () => setState(() => _showMobileFilters = !_showMobileFilters),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!Responsive.isMobile(context) || _showMobileFilters) ...[
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(color: Color(0xFF18181B)),
              decoration: InputDecoration(
                hintText: 'Tìm kiếm theo SN, tên, IP, vị trí...',
                hintStyle: const TextStyle(color: Color(0xFFA1A1AA)),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFA1A1AA)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Color(0xFFA1A1AA)),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFFAFAFA),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE4E4E7)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF1E3A5F)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          
          // Filter chips
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: DeviceFilter.values.map((filter) {
                final isSelected = _currentFilter == filter;
                final count = _getFilterCount(filter);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: FilterChip(
                    selected: isSelected,
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _getFilterIcon(filter),
                          size: 16,
                          color: isSelected ? Colors.white : _getFilterColor(filter),
                        ),
                        const SizedBox(width: 6),
                        Text(_getFilterLabel(filter)),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white24 : _getFilterColor(filter).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : _getFilterColor(filter),
                            ),
                          ),
                        ),
                      ],
                    ),
                    selectedColor: _getFilterColor(filter),
                    backgroundColor: Colors.white,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : const Color(0xFF71717A),
                    ),
                    onSelected: (_) => _onFilterChanged(filter),
                    side: BorderSide(
                      color: isSelected ? _getFilterColor(filter) : const Color(0xFFE4E4E7),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          ], // end _showMobileFilters

          // Stats summary
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE4E4E7)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Tổng', _allDevices.length, Icons.devices, Colors.blue),
                _buildStatItem('Online', onlineCount, Icons.wifi, Colors.green),
                _buildStatItem('Offline', offlineCount, Icons.wifi_off, Colors.red),
                _buildStatItem('Chưa KN', neverConnectedCount, Icons.wifi_find, Colors.orange),
              ],
            ),
          ),

          // Device list
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredDevices.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          itemCount: _filteredDevices.length,
                          itemBuilder: (context, index) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFE4E4E7)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: _buildDeviceDeckItem(_filteredDevices[index]),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          '$count',
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        Text(label, style: const TextStyle(color: Color(0xFF71717A), fontSize: 11)),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.devices_other, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty 
                ? 'Không tìm thấy thiết bị' 
                : 'Chưa có thiết bị nào kết nối',
            style: const TextStyle(color: Color(0xFF71717A), fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            _searchQuery.isNotEmpty
                ? 'Thử tìm kiếm với từ khóa khác'
                : 'Khi máy chấm công kết nối đến server,\nnó sẽ tự động xuất hiện ở đây',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 14),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildDeviceDeckItem(Device device) {
    final isOnline = device.isOnline;
    final neverConnected = device.hasNeverConnected;
    final Color statusColor;
    final String statusText;
    if (isOnline) { statusColor = Colors.green; statusText = 'Online'; }
    else if (neverConnected) { statusColor = Colors.orange; statusText = 'Chưa KN'; }
    else { statusColor = Colors.red; statusText = 'Offline'; }

    return InkWell(
      onTap: () => _showDeviceDetails(device),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.devices, color: statusColor, size: 18),
                ),
                Positioned(
                  right: 0, bottom: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(device.deviceName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    [
                      device.serialNumber,
                      if (device.ipAddress != null) device.ipAddress!,
                      if (device.location != null && device.location!.isNotEmpty) device.location!,
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(statusText, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFF71717A)),
          ],
        ),
      ),
    );
  }

  String _formatLastOnline(DateTime? lastOnline) {
    if (lastOnline == null) return 'Chưa kết nối bao giờ';
    
    final now = DateTime.now().toUtc();
    final utcLastOnline = lastOnline.toUtc();
    final diff = now.difference(utcLastOnline);
    
    if (diff.inSeconds < 60) {
      return 'Vừa xong';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes} phút trước';
    } else if (diff.inHours < 24) {
      return '${diff.inHours} giờ trước';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} ngày trước';
    } else {
      final local = utcLastOnline.toLocal();
      return '${local.day}/${local.month}/${local.year} ${local.hour}:${local.minute.toString().padLeft(2, '0')}';
    }
  }

  void _showDeviceDetails(Device device) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle bar
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
                
                // Header
                Builder(builder: (context) {
                      final detailColor = device.isOnline ? Colors.green : (device.hasNeverConnected ? Colors.orange : Colors.red);
                      final detailLabel = device.isOnline ? '● Online' : (device.hasNeverConnected ? '● Chưa kết nối' : '● Offline');
                      return Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: detailColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.devices, color: detailColor, size: 32),
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
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: detailColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    detailLabel,
                                    style: TextStyle(
                                      color: detailColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }),
                
                const SizedBox(height: 24),
                
                // Details
                _buildDetailRow('Serial Number', device.serialNumber, Icons.qr_code, Colors.blue),
                if (device.ipAddress != null)
                  _buildDetailRow('Địa chỉ IP', device.ipAddress!, Icons.lan, Colors.cyan),
                if (device.location != null && device.location!.isNotEmpty)
                  _buildDetailRow('Vị trí', device.location!, Icons.location_on, Colors.orange),
                if (device.description != null && device.description!.isNotEmpty)
                  _buildDetailRow('Mô tả', device.description!, Icons.description, Colors.purple),
                _buildDetailRow(
                  'Kết nối lần cuối',
                  _formatLastOnline(device.lastOnline),
                  Icons.access_time,
                  Colors.grey,
                ),
                _buildDetailRow(
                  'Trạng thái',
                  device.deviceStatus ?? (device.isActive ? 'Hoạt động' : 'Không hoạt động'),
                  Icons.info,
                  device.isActive ? Colors.green : Colors.red,
                ),
                
                const SizedBox(height: 24),
                
                // Info note
                Builder(builder: (context) {
                  final String noteText;
                  final Color noteColor;
                  final Color noteBorderColor;
                  if (device.isOnline) {
                    noteText = 'Thiết bị này đã kết nối và đang gửi dữ liệu đến server.';
                    noteColor = const Color(0xFF1E3A5F);
                    noteBorderColor = const Color(0xFF1E3A5F).withValues(alpha: 0.3);
                  } else if (device.hasNeverConnected) {
                    noteText = 'Thiết bị này chưa từng kết nối đến server. Vui lòng kiểm tra cấu hình mạng trên máy chấm công.';
                    noteColor = Colors.orange.shade800;
                    noteBorderColor = Colors.orange.withValues(alpha: 0.3);
                  } else {
                    noteText = 'Thiết bị hiện đang offline. Kiểm tra kết nối mạng hoặc nguồn điện của máy chấm công.';
                    noteColor = Colors.red.shade700;
                    noteBorderColor = Colors.red.withValues(alpha: 0.3);
                  }
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: noteColor.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: noteBorderColor),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: noteColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            noteText,
                            style: TextStyle(color: noteColor, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 16),

                // Delete button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(context);
                      final confirm = await showDialog<bool>(
                        context: this.context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Xóa thiết bị'),
                          content: Text('Bạn có chắc muốn xóa thiết bị "${device.deviceName}" (SN: ${device.serialNumber}) khỏi hệ thống?\n\nHành động này không thể hoàn tác.'),
                          actions: [
                            AppDialogActions.delete(
                              onCancel: () => Navigator.pop(ctx, false),
                              onConfirm: () => Navigator.pop(ctx, true),
                            ),
                          ],
                        ),
                      ) ?? false;
                      if (confirm) {
                        try {
                          await _apiService.deleteDevice(device.id);
                          _loadData();
                          if (mounted) {
                            NotificationOverlayManager().showSuccess(title: 'Thành công', message: 'Đã xóa thiết bị');
                          }
                        } catch (e) {
                          if (mounted) {
                            NotificationOverlayManager().showError(title: 'Lỗi', message: 'Lỗi xóa thiết bị: $e');
                          }
                        }
                      }
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('Xóa thiết bị khỏi hệ thống', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, Color color) {
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
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: Color(0xFF18181B), fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
