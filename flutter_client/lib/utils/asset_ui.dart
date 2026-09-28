import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../models/asset.dart';
import '../theme/sbox_tokens.dart';

/// Màu / biểu tượng thống nhất cho tài sản — mỗi trạng thái một màu có nghĩa
/// (trước đây mọi trạng thái cùng một chip xanh: «Hỏng» trông như «Đang dùng»).
class AssetUi {
  AssetUi._();

  static Color statusColor(AssetStatus s) => switch (s) {
        AssetStatus.active => SboxColors.success,
        AssetStatus.inStock => SboxColors.brand600,
        AssetStatus.inMaintenance => SboxColors.warning,
        AssetStatus.broken => SboxColors.danger,
        AssetStatus.lost => SboxColors.violet,
        AssetStatus.disposed => SboxColors.slate500,
      };

  static Color statusSoft(AssetStatus s) => statusColor(s).withValues(alpha: 0.12);

  static IconData statusIcon(AssetStatus s) => switch (s) {
        AssetStatus.active => Icons.check_circle_rounded,
        AssetStatus.inStock => Icons.warehouse_rounded,
        AssetStatus.inMaintenance => Icons.build_circle_rounded,
        AssetStatus.broken => Icons.report_rounded,
        AssetStatus.lost => Icons.help_rounded,
        AssetStatus.disposed => Icons.delete_sweep_rounded,
      };

  static AssetStatus statusFromIndex(int i) =>
      i >= 0 && i < AssetStatus.values.length ? AssetStatus.values[i] : AssetStatus.active;

  static IconData typeIcon(AssetType t) => switch (t) {
        AssetType.electronics => Icons.devices_rounded,
        AssetType.furniture => Icons.chair_rounded,
        AssetType.vehicle => Icons.directions_car_rounded,
        AssetType.tool => Icons.handyman_rounded,
        AssetType.machinery => Icons.precision_manufacturing_rounded,
        AssetType.software => Icons.apps_rounded,
        AssetType.other => Icons.category_rounded,
      };

  /// Chip trạng thái: nền nhạt + chữ đậm cùng màu.
  static Widget statusChip(AssetStatus s, {bool dense = false}) {
    final c = statusColor(s);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 7 : 9, vertical: dense ? 2 : 4),
      decoration: BoxDecoration(
        color: statusSoft(s),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon(s), size: dense ? 12 : 14, color: c),
          const SizedBox(width: 4),
          Text(
            tr(getAssetStatusLabel(s)),
            style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, color: c),
          ),
        ],
      ),
    );
  }

  /// Ô ảnh vuông bo góc; không có ảnh → biểu tượng loại tài sản.
  static Widget typeAvatar(AssetType t, {double size = 44}) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: SboxColors.brand50,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Icon(typeIcon(t), color: SboxColors.brand600, size: size * 0.5),
      );
}
