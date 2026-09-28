import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../services/api_service.dart';
import '../../theme/sbox_tokens.dart';
import '../../widgets/auth_cached_image.dart';

/// Tiện ích giao diện Bản đồ nhân sự.
class StaffMapUi {
  StaffMapUi._();

  static const statuses = <String, String>{
    'online': 'Trực tuyến',
    'stale': 'Vừa mất tín hiệu',
    'offline': 'Ngoại tuyến',
    'none': 'Chưa có vị trí',
  };

  static Color statusColor(String? s) => switch (s) {
        'online' => SboxColors.success,
        'stale' => SboxColors.warning,
        'offline' => SboxColors.slate500,
        _ => SboxColors.slate300,
      };

  /// Thời điểm UTC từ server (có thể thiếu hậu tố Z) → giờ máy.
  static DateTime? utc(dynamic v) {
    if (v == null) return null;
    final raw = v.toString().trim();
    if (raw.isEmpty) return null;
    final s = raw.endsWith('Z') || raw.contains('+') || RegExp(r'-\d\d:\d\d$').hasMatch(raw) ? raw : '${raw}Z';
    return DateTime.tryParse(s)?.toLocal();
  }

  /// Giờ ca (lưu theo giờ Việt Nam, không múi giờ) — hiển thị nguyên giờ.
  static DateTime? wall(dynamic v) => v == null ? null : DateTime.tryParse(v.toString().replaceAll('Z', ''));

  static String hm(DateTime? d) => d == null ? '--:--' : DateFormat('HH:mm').format(d);

  static String ago(int? minutes) {
    if (minutes == null) return '';
    if (minutes < 1) return 'vừa xong';
    if (minutes < 60) return '$minutes phút trước';
    final h = minutes ~/ 60;
    if (h < 24) return '$h giờ ${minutes % 60} phút trước';
    return '${h ~/ 24} ngày trước';
  }

  static String duration(num? minutes) {
    final m = (minutes ?? 0).round();
    if (m < 60) return '$m phút';
    return '${m ~/ 60}g ${(m % 60).toString().padLeft(2, '0')}p';
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts[parts.length - 2].characters.first + parts.last.characters.first).toUpperCase();
  }

  static num n(dynamic v) => v is num ? v : num.tryParse('$v') ?? 0;

  /// Ảnh đại diện tròn có viền màu trạng thái (dùng cả trên bản đồ và danh sách).
  static Widget avatar(Map<String, dynamic> e, ApiService api, {double size = 40, bool pulse = false}) {
    final color = statusColor(e['status']?.toString());
    final photo = e['photoUrl']?.toString() ?? '';
    final name = e['employeeName']?.toString() ?? '';
    final inner = photo.isEmpty
        ? Container(
            color: SboxColors.brand50,
            alignment: Alignment.center,
            child: Text(initials(name),
                style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w800, color: SboxColors.brand700)),
          )
        : AuthCachedImage(
            imagePath: photo,
            apiService: api,
            width: size,
            height: size,
            errorWidget: (_, __, ___) => Container(
              color: SboxColors.brand50,
              alignment: Alignment.center,
              child: Text(initials(name),
                  style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w800, color: SboxColors.brand700)),
            ),
          );
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: pulse ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10, spreadRadius: 2)] : null,
      ),
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
        child: ClipOval(child: inner),
      ),
    );
  }

  static Widget pill(String text, Color color, {IconData? icon}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(99)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 11, color: color), const SizedBox(width: 3)],
          Text(tr(text), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  static IconData timelineIcon(String? t) => switch (t) {
        'shift_start' => Icons.play_circle_outline_rounded,
        'shift_end' => Icons.stop_circle_outlined,
        'punch_in' => Icons.login_rounded,
        'punch_out' => Icons.logout_rounded,
        'checkin' => Icons.storefront_rounded,
        'stop' => Icons.local_parking_rounded,
        'gap' => Icons.signal_wifi_off_rounded,
        'first' => Icons.flag_rounded,
        'last' => Icons.sports_score_rounded,
        _ => Icons.circle,
      };

  static Color timelineColor(String? t) => switch (t) {
        'punch_in' || 'first' => SboxColors.success,
        'punch_out' => SboxColors.danger,
        'checkin' => SboxColors.violet,
        'stop' => SboxColors.warning,
        'gap' => SboxColors.slate400,
        'last' => SboxColors.brand700,
        _ => SboxColors.brand500,
      };
}
