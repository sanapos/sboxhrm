import 'package:flutter/material.dart';

import 'shift_templates_v2/st_list_screen.dart';

/// Thiết lập ca (Ca mẫu) — giao diện mới ở [ShiftTemplatesV2Screen].
/// Giữ tên lớp cũ để Cài đặt và «Ca làm việc → Thiết lập» không phải đổi.
class ShiftSettingsScreen extends StatelessWidget {
  const ShiftSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => const ShiftTemplatesV2Screen();
}
