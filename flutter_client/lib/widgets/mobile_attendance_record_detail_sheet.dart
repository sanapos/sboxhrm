import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import 'map_location_picker.dart';

/// Chi tiết bản ghi chấm công mobile — vị trí GPS, ảnh mặt, duyệt (tuỳ chọn).
Future<void> showMobileAttendanceRecordDetailSheet(
  BuildContext context, {
  required MobileAttendanceRecord record,
  ApiService? apiService,
  /// Fallback khi API chưa trả employeePhotoUrl (vd. tra cứu từ danh sách NV).
  String? employeeAvatarUrl,
  VoidCallback? onApprove,
  VoidCallback? onReject,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => _MobileAttendanceRecordDetailBody(
        record: record,
        scrollController: scrollController,
        apiService: apiService ?? ApiService(),
        employeeAvatarUrl: employeeAvatarUrl,
        onApprove: onApprove,
        onReject: onReject,
      ),
    ),
  );
}

class _MobileAttendanceRecordDetailBody extends StatelessWidget {
  const _MobileAttendanceRecordDetailBody({
    required this.record,
    required this.scrollController,
    required this.apiService,
    this.employeeAvatarUrl,
    this.onApprove,
    this.onReject,
  });

  final MobileAttendanceRecord record;
  final ScrollController scrollController;
  final ApiService apiService;
  final String? employeeAvatarUrl;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;

  String _statusLabel() {
    switch (record.status) {
      case 'auto_approved':
        return 'Tự động duyệt';
      case 'approved':
        return 'Đã duyệt';
      case 'rejected':
        return 'Từ chối';
      default:
        return 'Chờ duyệt';
    }
  }

  String _verifyLabel() {
    switch (record.verifyMethod) {
      case 'face_gps':
        return 'Face ID + GPS';
      case 'face':
        return 'Face ID';
      case 'gps':
        return 'GPS';
      case 'wifi':
        return 'WiFi';
      default:
        return record.verifyMethod;
    }
  }

  Future<void> _openFullMap(BuildContext context) async {
    if (!record.hasGpsLocation) return;
    final lat = record.latitude!;
    final lng = record.longitude!;
    final title = record.locationName?.isNotEmpty == true
        ? record.locationName!
        : record.employeeName;

    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      final uri = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng');
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogCtx) => MapLocationPicker(
        initialLatitude: lat,
        initialLongitude: lng,
        initialZoom: 17,
        title: title,
        readOnly: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCheckIn = record.punchType == 0;
    final punchColor =
        isCheckIn ? const Color(0xFF1E3A5F) : const Color(0xFFEF4444);
    final timeFmt = DateFormat('HH:mm:ss');
    final dateFmt = DateFormat('dd/MM/yyyy');
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE4E4E7),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: punchColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isCheckIn ? 'Chấm vào' : 'Chấm ra',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: punchColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _statusLabel(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF71717A),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  record.employeeName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${timeFmt.format(record.punchTime)} · ${dateFmt.format(record.punchTime)}',
                  style: const TextStyle(
                      fontSize: 13, color: Color(0xFF71717A)),
                ),
                _PunchPhotoSection(
                  punchFacePath: record.faceImageUrl,
                  avatarPath: employeeAvatarUrl ?? record.employeePhotoUrl,
                  apiService: apiService,
                ),
                const SizedBox(height: 16),
                _DetailRow(
                  icon: Icons.place_outlined,
                  label: 'Điểm chấm công',
                  value: record.locationName?.isNotEmpty == true
                      ? record.locationName!
                      : '—',
                ),
                _DetailRow(
                  icon: Icons.straighten,
                  label: 'Khoảng cách',
                  value: record.distanceFromLocation != null
                      ? '${record.distanceFromLocation!.toInt()} m'
                      : '—',
                ),
                _DetailRow(
                  icon: Icons.face,
                  label: 'Độ khớp khuôn mặt',
                  value: record.faceMatchScore != null
                      ? '${record.faceMatchScore!.toStringAsFixed(1)}%'
                      : '—',
                ),
                _DetailRow(
                  icon: Icons.verified_outlined,
                  label: 'Phương thức',
                  value: _verifyLabel(),
                ),
                if (record.wifiSsid != null && record.wifiSsid!.isNotEmpty)
                  _DetailRow(
                    icon: Icons.wifi,
                    label: 'WiFi',
                    value: record.wifiSsid!,
                  ),
                if (record.deviceName != null && record.deviceName!.isNotEmpty)
                  _DetailRow(
                    icon: Icons.phone_android,
                    label: 'Thiết bị',
                    value: record.deviceName!,
                  ),
                if (record.approvedBy != null && record.approvedBy!.isNotEmpty)
                  _DetailRow(
                    icon: Icons.person_outline,
                    label: 'Người duyệt',
                    value: record.approvedBy!,
                  ),
                if (record.rejectReason != null &&
                    record.rejectReason!.isNotEmpty)
                  _DetailRow(
                    icon: Icons.info_outline,
                    label: 'Lý do từ chối',
                    value: record.rejectReason!,
                  ),
                const SizedBox(height: 12),
                Text(
                  'Vị trí GPS lúc chấm',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF18181B),
                  ),
                ),
                const SizedBox(height: 8),
                if (record.hasGpsLocation) ...[
                  _PunchLocationPreview(
                    latitude: record.latitude!,
                    longitude: record.longitude!,
                    onTap: () => _openFullMap(context),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${record.latitude!.toStringAsFixed(6)}, ${record.longitude!.toStringAsFixed(6)}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF71717A)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openFullMap(context),
                      icon: const Icon(Icons.map_outlined, size: 18),
                      label: const Text('Xem trên bản đồ'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E3A5F),
                        side: const BorderSide(color: Color(0xFF1E3A5F)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ] else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.location_off,
                            color: Color(0xFFF59E0B), size: 22),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bản ghi không có tọa độ GPS hợp lệ (có thể do tắt định vị khi chấm).',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF92400E)),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (onApprove != null || onReject != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (onReject != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onReject!();
                          },
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Từ chối'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    if (onReject != null && onApprove != null)
                      const SizedBox(width: 12),
                    if (onApprove != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onApprove!();
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Duyệt'),
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
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
}

/// Ảnh chấm công; nếu không còn file thì dùng ảnh đại diện; không có cả hai thì ẩn.
class _PunchPhotoSection extends StatefulWidget {
  const _PunchPhotoSection({
    required this.punchFacePath,
    required this.avatarPath,
    required this.apiService,
  });

  final String? punchFacePath;
  final String? avatarPath;
  final ApiService apiService;

  @override
  State<_PunchPhotoSection> createState() => _PunchPhotoSectionState();
}

class _PunchPhotoSectionState extends State<_PunchPhotoSection> {
  String? _resolvedPath;
  bool _hidden = false;

  static String? _trimmed(String? v) {
    final t = v?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  void initState() {
    super.initState();
    _resolvedPath = _pickInitial();
  }

  String? _pickInitial() {
    return _trimmed(widget.punchFacePath) ?? _trimmed(widget.avatarPath);
  }

  void _onLoadFailed() {
    final punch = _trimmed(widget.punchFacePath);
    final avatar = _trimmed(widget.avatarPath);
    if (_resolvedPath == punch && avatar != null) {
      setState(() => _resolvedPath = avatar);
      return;
    }
    setState(() => _hidden = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_hidden || _resolvedPath == null) return const SizedBox.shrink();

    return Column(
      children: [
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: CachedNetworkImage(
              key: ValueKey(_resolvedPath),
              imageUrl: widget.apiService.getFileUrl(_resolvedPath!),
              fit: BoxFit.cover,
              placeholder: (_, __) => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (_, __, ___) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _onLoadFailed();
                });
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF71717A)),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: Text(label,
                style: const TextStyle(fontSize: 13, color: Color(0xFF71717A))),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF18181B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PunchLocationPreview extends StatelessWidget {
  const _PunchLocationPreview({
    required this.latitude,
    required this.longitude,
    required this.onTap,
  });

  final double latitude;
  final double longitude;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 180,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.zktecoadms.app',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.location_on,
                            color: Color(0xFFDC2626),
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, size: 14, color: Color(0xFF1E3A5F)),
                        SizedBox(width: 4),
                        Text('Chạm để phóng to',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF1E3A5F))),
                      ],
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
}
