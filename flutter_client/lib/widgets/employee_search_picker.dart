import 'package:flutter/material.dart';
import '../models/employee.dart';
import '../utils/employee_work_status.dart';
import 'full_screen_dialog.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Một dòng nhân viên trong picker (tên + mã tách dòng, có tìm kiếm).
class EmployeePickerItem {
  final String id;
  final String name;
  final String code;
  final String? department;
  final String? phone;

  const EmployeePickerItem({
    required this.id,
    required this.name,
    required this.code,
    this.department,
    this.phone,
  });

  factory EmployeePickerItem.fromEmployee(Employee e) => EmployeePickerItem(
        id: e.id,
        name: e.fullName,
        code: e.employeeCode,
        department: e.department,
        phone: e.phone,
      );

  factory EmployeePickerItem.fromMap(Map<String, dynamic> m) {
    final first = m['firstName']?.toString() ?? '';
    final last = m['lastName']?.toString() ?? '';
    var name = '${last} ${first}'.trim();
    if (name.isEmpty) {
      name = m['fullName']?.toString() ?? m['name']?.toString() ?? '';
    }
    if (name.isEmpty) {
      name = m['employeeCode']?.toString() ?? 'N/A';
    }
    return EmployeePickerItem(
      id: m['id']?.toString() ?? '',
      name: name,
      code: m['employeeCode']?.toString() ?? m['enrollNumber']?.toString() ?? '',
      department: m['departmentName']?.toString() ?? m['department']?.toString(),
      phone: m['phone']?.toString() ?? m['phoneNumber']?.toString(),
    );
  }

  static List<EmployeePickerItem> fromEmployees(
    List<Employee> list, {
    Iterable<String>? keepEmployeeIds,
  }) {
    final keep = keepEmployeeIds
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        const {};
    return list
        .where((e) =>
            keep.contains(e.id) ||
            !EmployeeWorkStatusUtil.isResigned(e.workStatus))
        .map(EmployeePickerItem.fromEmployee)
        .toList();
  }

  static List<EmployeePickerItem> fromMaps(
    List<dynamic> list, {
    Iterable<String>? keepEmployeeIds,
  }) =>
      EmployeeWorkStatusUtil.filterSelectableMaps(
        list,
        keepEmployeeIds: keepEmployeeIds,
      ).map(EmployeePickerItem.fromMap).toList();

  bool matchesQuery(String q) {
    if (q.isEmpty) return true;
    final lower = q.toLowerCase();
    return name.toLowerCase().contains(lower) ||
        code.toLowerCase().contains(lower) ||
        (department?.toLowerCase().contains(lower) ?? false) ||
        (phone?.toLowerCase().contains(lower) ?? false);
  }
}

/// Cách hiển thị picker nhân viên.
enum EmployeePickerPresentation {
  /// Toàn màn hình (mặc định).
  fullScreen,

  /// Bottom sheet ~68% chiều cao — chạm vùng trống / kéo xuống để đóng.
  bottomSheet,
}

/// Picker nhân viên có tìm kiếm — dùng thay Dropdown/Autocomplete `Tên (mã)`.
class EmployeeSearchPicker {
  EmployeeSearchPicker._();

  static Future<String?> pickId(
    BuildContext context, {
    required List<EmployeePickerItem> items,
    String? selectedId,
    String title = 'Chọn nhân viên',
    String? subtitle,
    bool allowClear = false,
    EmployeePickerPresentation presentation =
        EmployeePickerPresentation.fullScreen,
  }) async {
    if (items.isEmpty) return null;
    if (presentation == EmployeePickerPresentation.bottomSheet) {
      return showEmployeePickerBottomSheet(
        context,
        items: items,
        selectedId: selectedId,
        title: title,
        subtitle: subtitle,
        allowClear: allowClear,
      );
    }
    return showEmployeePickerSheet(
      context,
      items: items,
      selectedId: selectedId,
      title: title,
      subtitle: subtitle,
      allowClear: allowClear,
    );
  }

  static Future<Employee?> pickEmployee(
    BuildContext context, {
    required List<Employee> employees,
    Employee? initial,
    String title = 'Chọn nhân viên',
    String? subtitle,
    bool allowClear = false,
  }) async {
    final keepIds = initial != null ? [initial.id] : null;
    final selectable = employees.where((e) {
      if (keepIds != null && keepIds.contains(e.id)) return true;
      return !EmployeeWorkStatusUtil.isResigned(e.workStatus);
    }).toList();
    if (selectable.isEmpty) return null;
    final pickerItems = EmployeePickerItem.fromEmployees(
      selectable,
      keepEmployeeIds: keepIds,
    );
    final id = await pickId(
      context,
      items: pickerItems,
      selectedId: initial?.id,
      title: title,
      subtitle: subtitle,
      allowClear: allowClear,
    );
    if (id == null) return allowClear ? null : initial;
    try {
      return selectable.firstWhere((e) => e.id == id);
    } catch (_) {
      return initial;
    }
  }

  static Future<EmployeePickerItem?> pickItem(
    BuildContext context, {
    required List<EmployeePickerItem> items,
    String? selectedId,
    String title = 'Chọn nhân viên',
    String? subtitle,
    bool allowClear = false,
    EmployeePickerPresentation presentation =
        EmployeePickerPresentation.fullScreen,
  }) async {
    final id = await pickId(
      context,
      items: items,
      selectedId: selectedId,
      title: title,
      subtitle: subtitle,
      allowClear: allowClear,
      presentation: presentation,
    );
    if (id == null) return null;
    try {
      return items.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Full màn hình, nút đóng trên AppBar, không đóng khi bấm ra ngoài.
  static Future<String?> showEmployeePickerSheet(
    BuildContext context, {
    required List<EmployeePickerItem> items,
    String? selectedId,
    String title = 'Chọn nhân viên',
    String? subtitle,
    bool allowClear = false,
  }) {
    return showFullScreenDialog<String>(
      context,
      child: _EmployeePickerSheet(
        items: items,
        selectedId: selectedId,
        title: title,
        subtitle: subtitle,
        allowClear: allowClear,
        embeddedInBottomSheet: false,
      ),
    );
  }

  /// Bottom sheet vừa phải — chạm nền tối / kéo xuống để thoát.
  static Future<String?> showEmployeePickerBottomSheet(
    BuildContext context, {
    required List<EmployeePickerItem> items,
    String? selectedId,
    String title = 'Chọn nhân viên',
    String? subtitle,
    bool allowClear = false,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final maxH = MediaQuery.sizeOf(sheetContext).height * 0.68;
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: Colors.white,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: maxH,
                child: _EmployeePickerSheet(
                  items: items,
                  selectedId: selectedId,
                  title: title,
                  subtitle: subtitle,
                  allowClear: allowClear,
                  embeddedInBottomSheet: true,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Ô form: bấm mở picker có tìm kiếm (thay DropdownButtonFormField nhân viên).
class EmployeePickerFormField extends StatelessWidget {
  final String? selectedId;
  final EmployeePickerItem? selectedItem;
  final List<EmployeePickerItem> candidates;
  final ValueChanged<EmployeePickerItem?> onChanged;
  final String labelText;
  final String? hintText;
  final IconData prefixIcon;
  final bool enabled;
  final bool allowClear;
  final String pickerTitle;
  final String? pickerSubtitle;
  final EmployeePickerPresentation presentation;

  const EmployeePickerFormField({
    super.key,
    required this.candidates,
    required this.onChanged,
    this.selectedId,
    this.selectedItem,
    this.labelText = 'Chọn nhân viên',
    this.hintText,
    this.prefixIcon = Icons.person_search,
    this.enabled = true,
    this.allowClear = false,
    this.pickerTitle = 'Chọn nhân viên',
    this.pickerSubtitle,
    this.presentation = EmployeePickerPresentation.fullScreen,
  });

  EmployeePickerItem? get _resolved {
    if (selectedItem != null) return selectedItem;
    if (selectedId == null || selectedId!.isEmpty) return null;
    try {
      return candidates.firstWhere((e) => e.id == selectedId);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = _resolved;
    return InkWell(
      onTap: !enabled
          ? null
          : () async {
              final picked = await EmployeeSearchPicker.pickItem(
                context,
                items: candidates,
                selectedId: selectedId ?? sel?.id,
                title: pickerTitle,
                subtitle: pickerSubtitle,
                allowClear: allowClear,
                presentation: presentation,
              );
              if (picked != null || allowClear) {
                onChanged(picked);
              }
            },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: tr(labelText),
          hintText: tr(hintText ?? 'Bấm để tìm và chọn...'),
          prefixIcon: Icon(prefixIcon),
          suffixIcon: sel != null && allowClear
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: !enabled ? null : () => onChanged(null),
                )
              : const Icon(Icons.arrow_drop_down),
          border: const OutlineInputBorder(),
        ),
        child: sel == null
            ? Text(
                tr(hintText ?? 'Bấm để tìm và chọn...'),
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(sel.name),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (sel.code.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(tr('${tr('Mã NV: ')}${sel.code}'
                      '${sel.department != null && sel.department!.isNotEmpty ? ' · ${sel.department}' : ''}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF71717A)),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _EmployeePickerSheet extends StatefulWidget {
  final List<EmployeePickerItem> items;
  final String? selectedId;
  final String title;
  final String? subtitle;
  final bool allowClear;
  final bool embeddedInBottomSheet;

  const _EmployeePickerSheet({
    required this.items,
    this.selectedId,
    required this.title,
    this.subtitle,
    this.allowClear = false,
    this.embeddedInBottomSheet = false,
  });

  @override
  State<_EmployeePickerSheet> createState() => _EmployeePickerSheetState();
}

class _EmployeePickerSheetState extends State<_EmployeePickerSheet> {
  final _search = TextEditingController();
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.selectedId;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim();
    final filtered = widget.items.where((e) => e.matchesQuery(q)).toList();

    final body = Column(
        children: [
          if (widget.embeddedInBottomSheet) ...[
            const SizedBox(height: 8),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr(widget.title),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        if (widget.subtitle != null &&
                            widget.subtitle!.isNotEmpty)
                          Text(
                            tr(widget.subtitle!),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: tr('Đóng'),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
          ],
          Padding(
            padding: EdgeInsets.fromLTRB(
                16, widget.embeddedInBottomSheet ? 4 : 8, 16, 0),
            child: TextField(
              controller: _search,
              autofocus: true,
              decoration: InputDecoration(
                hintText: tr('Tìm tên, mã NV, phòng ban, SĐT...'),
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(tr('${filtered.length} nhân viên'),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          ),
          if (widget.allowClear)
            ListTile(
              dense: true,
              leading: const Icon(Icons.clear, color: Color(0xFF71717A)),
              title: Text(tr('Không chọn')),
              onTap: () => Navigator.pop(context),
            ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(tr('Không tìm thấy nhân viên'),
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, indent: 56),
                    itemBuilder: (_, i) {
                      final emp = filtered[i];
                      final isSel = _selectedId == emp.id;
                      return Material(
                        color: isSel ? const Color(0xFFEFF6FF) : Colors.white,
                        child: InkWell(
                          onTap: () => setState(() => _selectedId = emp.id),
                          onDoubleTap: () =>
                              Navigator.pop(context, emp.id),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 20,
                                  backgroundColor: const Color(0xFFE4E4E7),
                                  child: Text(
                                    tr(emp.name.isNotEmpty
                                        ? emp.name[0].toUpperCase()
                                        : '?'),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF52525B),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        tr(emp.name),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF0F172A),
                                          height: 1.25,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        tr([
                                          if (emp.code.isNotEmpty)
                                            'Mã NV: ${emp.code}',
                                          if (emp.department != null &&
                                              emp.department!.isNotEmpty)
                                            emp.department!,
                                        ].join(' · ')),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Color(0xFF71717A),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  isSel
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color: isSel
                                      ? const Color(0xFF1E3A5F)
                                      : const Color(0xFFD4D4D8),
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(tr('Hủy')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selectedId == null
                          ? null
                          : () => Navigator.pop(context, _selectedId),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                      ),
                      child: Text(tr('Chọn')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );

    if (widget.embeddedInBottomSheet) {
      return body;
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: buildPickerCloseAppBar(
        context,
        title: widget.title,
        subtitle: widget.subtitle,
      ),
      body: body,
    );
  }
}
