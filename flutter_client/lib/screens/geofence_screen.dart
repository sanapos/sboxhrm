import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/permission_provider.dart';
import 'package:zkteco_flutter_client/widgets/app_responsive_dialog.dart';
import '../services/api_service.dart';
import '../utils/responsive_helper.dart';
import '../widgets/hrm_page_chrome.dart';
import '../widgets/hrm_fab_clearance.dart';

class GeofenceScreen extends StatefulWidget {
  const GeofenceScreen({super.key});

  @override
  State<GeofenceScreen> createState() => _GeofenceScreenState();
}

class _GeofenceScreenState extends State<GeofenceScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = false;
  List<Map<String, dynamic>> _geofences = [];

  PermissionProvider get _perm =>
      Provider.of<PermissionProvider>(context, listen: false);

  Widget? _geofenceActionMenu(Map<String, dynamic> geo) {
    final canEdit = _perm.canEdit('Geofence');
    final canDelete = _perm.canDelete('Geofence');
    if (!canEdit && !canDelete) return null;
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: Colors.grey[400], size: 20),
      itemBuilder: (_) => [
        if (canEdit)
          const PopupMenuItem(
              value: 'edit',
              child: Row(children: [
                Icon(Icons.edit, size: 16),
                SizedBox(width: 8),
                Text('Sửa')
              ])),
        if (canDelete)
          const PopupMenuItem(
              value: 'delete',
              child: Row(children: [
                Icon(Icons.delete, size: 16, color: Colors.red),
                SizedBox(width: 8),
                Text('Xóa', style: TextStyle(color: Colors.red))
              ])),
      ],
      onSelected: (v) {
        if (v == 'edit' && canEdit) _showGeofenceDialog(geo: geo);
        if (v == 'delete' && canDelete) _deleteGeofence(geo);
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadGeofences();
  }

  Future<void> _loadGeofences() async {
    setState(() => _isLoading = true);
    try {
      final res = await _apiService.getGeofences();
      if (res['isSuccess'] == true) {
        setState(() => _geofences = List<Map<String, dynamic>>.from(res['data'] ?? []));
      }
    } catch (e) {
      debugPrint('Error loading geofences: $e');
    }
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: HrmFabClearance(
              fabVisible: _perm.canCreate('Geofence'),
              extendedFab: true,
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _geofences.isEmpty
                      ? _buildEmptyState()
                      : _buildGeofenceGrid(),
            ),
          ),
        ],
      ),
      floatingActionButton:
          Provider.of<PermissionProvider>(context, listen: false)
                  .canCreate('Geofence')
              ? FloatingActionButton.extended(
                  onPressed: () => _showGeofenceDialog(),
                  icon: const Icon(Icons.add_location_alt),
                  label: const Text('Thêm khu vực'),
                  backgroundColor: HrmPageChrome.primaryNavy,
                )
              : null,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [HrmPageChrome.primaryNavy, HrmPageChrome.primaryNavy]),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.share_location, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quản lý Geofence', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                Text('Khu vực chấm công theo vị trí', style: TextStyle(color: Colors.white70, fontSize: 14)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
            child: Text('${_geofences.length} khu vực', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.share_location, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text('Chưa có khu vực geofence', style: TextStyle(color: Colors.grey[500], fontSize: 16)),
        const SizedBox(height: 8),
        Text('Tạo khu vực để chấm công theo vị trí GPS', style: TextStyle(color: Colors.grey[400], fontSize: 13)),
      ]),
    );
  }

  Widget _buildGeofenceGrid() {
    final isMobile = Responsive.isMobile(context);
    if (isMobile) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _geofences.length,
        itemBuilder: (ctx, i) => Padding(
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
            child: _buildGeofenceDeckItem(_geofences[i]),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 16, childAspectRatio: 1.4),
      itemCount: _geofences.length,
      itemBuilder: (ctx, i) => _buildGeofenceCard(_geofences[i]),
    );
  }

  Widget _buildGeofenceCard(Map<String, dynamic> geo) {
    final name = geo['name'] ?? 'Khu vực';
    final lat = geo['latitude'] ?? geo['centerLatitude'] ?? 0.0;
    final lng = geo['longitude'] ?? geo['centerLongitude'] ?? 0.0;
    final radius = geo['radius'] ?? geo['radiusMeters'] ?? 0;
    final isActive = geo['isActive'] as bool? ?? true;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: isActive ? HrmPageChrome.primaryNavy : Colors.grey, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.location_on, color: HrmPageChrome.primaryNavy, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis)),
                if (_geofenceActionMenu(geo) != null) _geofenceActionMenu(geo)!,
              ],
            ),
            const Spacer(),
            Row(children: [
              Icon(Icons.gps_fixed, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Expanded(child: Text('${(lat is double ? lat : double.tryParse(lat.toString()) ?? 0).toStringAsFixed(5)}, ${(lng is double ? lng : double.tryParse(lng.toString()) ?? 0).toStringAsFixed(5)}', style: TextStyle(color: Colors.grey[600], fontSize: 12))),
            ]),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text('${radius}m', style: const TextStyle(color: HrmPageChrome.primaryNavy, fontSize: 11, fontWeight: FontWeight.w600)),
                  backgroundColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isActive ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(isActive ? 'Hoạt động' : 'Tắt', style: TextStyle(color: isActive ? HrmPageChrome.primaryNavy : Colors.grey, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeofenceDeckItem(Map<String, dynamic> geo) {
    final name = geo['name'] ?? 'Khu vực';
    final lat = geo['latitude'] ?? geo['centerLatitude'] ?? 0.0;
    final lng = geo['longitude'] ?? geo['centerLongitude'] ?? 0.0;
    final radius = geo['radius'] ?? geo['radiusMeters'] ?? 0;
    final isActive = geo['isActive'] as bool? ?? true;

    return InkWell(
      onTap: _perm.canEdit('Geofence')
          ? () => _showGeofenceDialog(geo: geo)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: HrmPageChrome.primaryNavy.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.location_on, color: HrmPageChrome.primaryNavy, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${(lat is double ? lat : double.tryParse(lat.toString()) ?? 0).toStringAsFixed(4)}, ${(lng is double ? lng : double.tryParse(lng.toString()) ?? 0).toStringAsFixed(4)} · ${radius}m',
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive ? HrmPageChrome.primaryNavy.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(isActive ? 'Hoạt động' : 'Tắt', style: TextStyle(color: isActive ? HrmPageChrome.primaryNavy : Colors.grey, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
            if (_geofenceActionMenu(geo) != null)
              _geofenceActionMenu(geo)!,
          ],
        ),
      ),
    );
  }

  Future<void> _deleteGeofence(Map<String, dynamic> geo) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: const Text('Xóa khu vực'),
        content: Text('Xóa "${geo['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Xóa')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _apiService.deleteGeofence(geo['id']?.toString() ?? '');
      _loadGeofences();
    } catch (e) {
      debugPrint('Error deleting geofence: $e');
    }
  }

  void _showGeofenceDialog({Map<String, dynamic>? geo}) {
    final isEdit = geo != null;
    final nameCtrl = TextEditingController(text: geo?['name'] ?? '');
    final latCtrl = TextEditingController(text: (geo?['latitude'] ?? geo?['centerLatitude'] ?? '').toString());
    final lngCtrl = TextEditingController(text: (geo?['longitude'] ?? geo?['centerLongitude'] ?? '').toString());
    final radiusCtrl = TextEditingController(text: (geo?['radius'] ?? geo?['radiusMeters'] ?? '200').toString());
    final addressCtrl = TextEditingController(text: geo?['address'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) => ScrollableAlertDialog(
        title: Text(isEdit ? 'Sửa khu vực' : 'Thêm khu vực'),
        content: SizedBox(
          width: math.min(420, MediaQuery.of(context).size.width - 32).toDouble(),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              _dialogField(nameCtrl, 'Tên khu vực', Icons.label),
              const SizedBox(height: 12),
              _dialogField(addressCtrl, 'Địa chỉ', Icons.location_city),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _dialogField(latCtrl, 'Vĩ độ', Icons.north)),
                const SizedBox(width: 12),
                Expanded(child: _dialogField(lngCtrl, 'Kinh độ', Icons.east)),
              ]),
              const SizedBox(height: 12),
              _dialogField(radiusCtrl, 'Bán kính (m)', Icons.radar),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Hủy')),
          FilledButton(
            onPressed: () async {
              final data = {
                'name': nameCtrl.text,
                'address': addressCtrl.text,
                'latitude': double.tryParse(latCtrl.text) ?? 0,
                'longitude': double.tryParse(lngCtrl.text) ?? 0,
                'centerLatitude': double.tryParse(latCtrl.text) ?? 0,
                'centerLongitude': double.tryParse(lngCtrl.text) ?? 0,
                'radius': int.tryParse(radiusCtrl.text) ?? 200,
                'radiusMeters': int.tryParse(radiusCtrl.text) ?? 200,
              };
              try {
                if (isEdit) {
                  await _apiService.updateGeofence(geo['id']?.toString() ?? '', data);
                } else {
                  await _apiService.createGeofence(data);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _loadGeofences();
              } catch (e) {
                debugPrint('Error saving geofence: $e');
              }
            },
            style: FilledButton.styleFrom(backgroundColor: HrmPageChrome.primaryNavy),
            child: Text(isEdit ? 'Cập nhật' : 'Tạo'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      latCtrl.dispose();
      lngCtrl.dispose();
      radiusCtrl.dispose();
      addressCtrl.dispose();
    });
  }

  Widget _dialogField(TextEditingController ctrl, String label, IconData icon) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
