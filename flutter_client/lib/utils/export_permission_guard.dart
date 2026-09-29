import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../providers/permission_provider.dart';
import '../widgets/notification_overlay.dart';

/// Kiểm quyền Xuất trước khi xuất Excel / PDF / ảnh / gửi file. Không có quyền → báo và trả false.
bool ensureCanExport(BuildContext context, String moduleCode) {
  final perm = Provider.of<PermissionProvider>(context, listen: false);
  if (perm.canExport(moduleCode)) return true;
  NotificationOverlayManager().showWarning(
    title: 'Không có quyền xuất dữ liệu',
    message: 'Tài khoản chưa được tick quyền «Xuất» cho chức năng này — nhờ quản lý cấp trong Phân quyền.',
  );
  return false;
}
