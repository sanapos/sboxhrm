import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/notification_overlay.dart';

class BiometricsScreen extends StatefulWidget {
  const BiometricsScreen({super.key});

  @override
  State<BiometricsScreen> createState() => _BiometricsScreenState();
}

class _BiometricsScreenState extends State<BiometricsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _devices = [];
  String? _selectedDeviceId;
  List<Map<String, dynamic>> _biometrics = [];
  Map<String, dynamic>? _summary;
  // ignore: unused_field
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getDevices(storeOnly: true);
      if (!mounted) return;
      setState(() {
        _devices = List<Map<String, dynamic>>.from(res);
      });
    } catch (e) {
      debugPrint('Error loading devices: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _loadBiometrics(String deviceId) async {
    setState(() { _isLoading = true; _selectedDeviceId = deviceId; });
    try {
      final results = await Future.wait([
        _apiService.getBiometricsByDevice(deviceId),
        _apiService.getBiometricSummary(deviceId),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0]['isSuccess'] == true) _biometrics = List<Map<String, dynamic>>.from(results[0]['data'] ?? []);
        if (results[1]['isSuccess'] == true) _summary = results[1]['data'];
      });
    } catch (e) {
      debugPrint('Error loading biometrics: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  // ignore: unused_element
  Future<void> _syncBiometrics() async {
    if (_selectedDeviceId == null) return;
    setState(() => _isSyncing = true);
    try {
      final res = await _apiService.syncBiometrics(_selectedDeviceId!);
      if (mounted) {
        if (res['isSuccess'] == true) {
          NotificationOverlayManager().showInfo(title: 'Đồng bộ', message: 'Đang đồng bộ sinh trắc học...');
        } else {
          NotificationOverlayManager().showError(title: 'Lỗi', message: res['message'] ?? 'Lỗi');
        }
      }
      await Future.delayed(const Duration(seconds: 2));
      _loadBiometrics(_selectedDeviceId!);
    } catch (e) {
      debugPrint('Error syncing biometrics: $e');
    }
    setState(() => _isSyncing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Responsive.isMobile(context)
                ? (_selectedDeviceId == null
                    ? _buildDeviceList()
                    : Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            color: Colors.white,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.arrow_back),
                                  onPressed: () => setState(() => _selectedDeviceId = null),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _devices.firstWhere((d) => d['id']?.toString() == _selectedDeviceId, orElse: () => {})['deviceName'] ?? 'Thiết bị',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 24),
                          Expanded(child: _buildBiometricContent()),
                        ],
                      ))
                : Row(
                    children: [
                      SizedBox(
                        width: 300,
                        child: _buildDeviceList(),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: _buildBiometricContent()),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFF0F2340), Color(0xFF1E3A5F)]),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.fingerprint, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quản lý sinh trắc học', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Vân tay, khuôn mặt trên thiết bị', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList() {
    return Container(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Thiết bị', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey[800])),
          ),
          const Divider(height: 24),
          Expanded(
            child: _devices.isEmpty
                ? Center(child: Text('Chưa có thiết bị', style: TextStyle(color: Colors.grey[500])))
                : ListView.builder(
                    itemCount: _devices.length,
                    itemBuilder: (ctx, i) {
                      final device = _devices[i];
                      final id = device['id']?.toString() ?? '';
                      final isSelected = id == _selectedDeviceId;
                      return ListTile(
                        selected: isSelected,
                        selectedTileColor: const Color(0xFF0F2340).withValues(alpha: 0.08),
                        leading: CircleAvatar(
                          backgroundColor: isSelected ? const Color(0xFF0F2340) : Colors.grey[200],
                          child: Icon(Icons.router, color: isSelected ? Colors.white : Colors.grey[600], size: 20),
                        ),
                        title: Text(device['deviceName'] ?? device['name'] ?? 'Device', style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                        subtitle: Text(device['serialNumber'] ?? '', style: const TextStyle(fontSize: 12)),
                        onTap: () => _loadBiometrics(id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBiometricContent() {
    if (_selectedDeviceId == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.fingerprint, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('Chọn thiết bị để xem sinh trắc học', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        ]),
      );
    }
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_summary != null) _buildSummaryCards(),
          const SizedBox(height: 20),
          Text('Danh sách sinh trắc học', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey[800])),
          const SizedBox(height: 12),
          if (_biometrics.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(children: [
                Icon(Icons.fingerprint, size: 48, color: Colors.grey[300]),
                const SizedBox(height: 12),
                Text('Chưa có dữ liệu sinh trắc học', style: TextStyle(color: Colors.grey[500])),
              ]),
            )
          else if (Responsive.isMobile(context))
            Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(_biometrics.length, (i) => Padding(
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
                  child: _buildBiometricDeckItem(_biometrics[i]),
                ),
              )),
            )
          else
            ...(_biometrics.map((b) => _buildBiometricCard(b))),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    return LayoutBuilder(builder: (context, constraints) {
      final narrow = constraints.maxWidth < 450;
      final cards = [
        _buildMiniStat('Tổng vân tay', '${_summary?['totalFingerprints'] ?? 0}', Icons.fingerprint, const Color(0xFF0F2340), expanded: !narrow),
        _buildMiniStat('Tổng khuôn mặt', '${_summary?['totalFaces'] ?? 0}', Icons.face, const Color(0xFF1E3A5F), expanded: !narrow),
        _buildMiniStat('Tổng người dùng', '${_summary?['totalUsers'] ?? 0}', Icons.people, const Color(0xFF0F2340), expanded: !narrow),
      ];
      if (narrow) {
        return Column(children: [
          for (int i = 0; i < cards.length; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: cards[i]),
        ]);
      }
      return Row(children: [
        for (int i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 12), cards[i]],
      ]);
    });
  }

  Widget _buildMiniStat(String label, String value, IconData icon, Color color, {bool expanded = true}) {
    final content = Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.15))),
      child: Row(
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 18)),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 11), overflow: TextOverflow.ellipsis),
          ])),
        ],
      ),
    );
    return expanded ? Expanded(child: content) : content;
  }

  Widget _buildBiometricDeckItem(Map<String, dynamic> bio) {
    final bioType = bio['type']?.toString() ?? 'fingerprint';
    final icon = bioType.contains('face') ? Icons.face : Icons.fingerprint;
    final color = bioType.contains('face') ? const Color(0xFF1E3A5F) : const Color(0xFF0F2340);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(bio['userName'] ?? bio['userId']?.toString() ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text('Index: ${bio['fingerIndex'] ?? bio['index'] ?? 'N/A'}', style: const TextStyle(color: Color(0xFF71717A), fontSize: 12)),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
          child: Text(bioType.contains('face') ? 'M\u1eb7t' : 'V\u00e2n tay', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
        ),
      ]),
    );
  }

  Widget _buildBiometricCard(Map<String, dynamic> bio) {
    final bioType = bio['type']?.toString() ?? 'fingerprint';
    final icon = bioType.contains('face') ? Icons.face : Icons.fingerprint;
    final color = bioType.contains('face') ? const Color(0xFF1E3A5F) : const Color(0xFF0F2340);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade200)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bio['userName'] ?? bio['userId']?.toString() ?? 'N/A', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('Finger Index: ${bio['fingerIndex'] ?? bio['index'] ?? 'N/A'}', style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              ]),
            ),
            Chip(
              label: Text(bioType.contains('face') ? 'Khuôn mặt' : 'Vân tay', style: TextStyle(color: color, fontSize: 11)),
              backgroundColor: color.withValues(alpha: 0.1),
            ),
          ],
        ),
      ),
    );
  }
}
