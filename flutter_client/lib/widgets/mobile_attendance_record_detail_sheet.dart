import 'package:flutter/material.dart';
import 'app_scroll_safe.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/mobile_attendance.dart';
import '../services/api_service.dart';
import 'map_location_picker.dart';
import 'punch_location_preview.dart';
import 'punch_photo_preview.dart';

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
  return showAppSheet<void>(
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

class _MobileAttendanceRecordDetailBody extends StatefulWidget {
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

  @override
  State<_MobileAttendanceRecordDetailBody> createState() =>
      _MobileAttendanceRecordDetailBodyState();
}

class _MobileAttendanceRecordDetailBodyState
    extends State<_MobileAttendanceRecordDetailBody> {
  late MobileAttendanceRecord _record;
  bool _loadingDetail = false;

  bool get _isPending => _record.status == 'pending';

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _loadRecordDetail();
  }

  Future<void> _loadRecordDetail() async {
    final id = widget.record.id.trim();
    if (id.isEmpty) return;
    setState(() => _loadingDetail = true);
    try {
      final res = await widget.apiService.getMobileAttendanceRecord(id);
      if (!mounted) return;
      if (res['isSuccess'] == true && res['data'] is Map) {
        setState(() {
          _record = MobileAttendanceRecord.fromJson(
            Map<String, dynamic>.from(res['data'] as Map),
          );
        });
      }
    } finally {
      if (mounted) setState(() => _loadingDetail = false);
    }
  }

  String _statusLabel() {
    switch (_record.status) {
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
    switch (_record.verifyMethod) {
      case 'face_gps':
        return 'Face ID + GPS';
      case 'face':
        return 'Face ID';
      case 'gps':
        return 'GPS';
      case 'wifi':
        return 'WiFi';
      default:
        return _record.verifyMethod;
    }
  }

  Future<void> _openFullMap(BuildContext context) async {
    if (!_record.hasGpsLocation) return;
    final lat = _record.latitude!;
    final lng = _record.longitude!;
    final title = _record.locationName?.isNotEmpty == true
        ? _record.locationName!
        : _record.employeeName;

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
    final record = _record;
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
              controller: widget.scrollController,
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
                if (_isPending) ...[
                  const SizedBox(height: 16),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Ảnh hiện trường (check-in CT)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF18181B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  PunchPhotoPreview(
                    imagePath: _record.sitePhotoUrl?.trim().isNotEmpty == true
                        ? _record.sitePhotoUrl!.trim()
                        : null,
                    apiService: widget.apiService,
                    emptyHint: 'Chưa có ảnh hiện trường — chụp khi chấm công',
                  ),
                  const SizedBox(height: 16),
                ],
                _DetailRow(
                  icon: Icons.place_outlined,
                  label: 'Điểm chấm công',
                  value: record.locationName?.trim().isNotEmpty == true
                      ? record.locationName!.trim()
                      : (record.hasGpsLocation ? 'Tọa độ GPS' : '—'),
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
                  PunchLocationPreview(
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
          if (widget.onApprove != null || widget.onReject != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    if (widget.onReject != null)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onReject!();
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
                    if (widget.onReject != null && widget.onApprove != null)
                      const SizedBox(width: 12),
                    if (widget.onApprove != null)
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onApprove!();
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
