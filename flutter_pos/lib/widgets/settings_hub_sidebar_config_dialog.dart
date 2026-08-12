import 'package:flutter/material.dart';

import '../models/settings_hub_sidebar_config.dart';
import '../utils/settings_hub_catalog.dart';
import '../widgets/hrm_page_chrome.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Dialog tùy chỉnh thứ tự và hiển thị module trong Thiết lập HRM.
class SettingsHubSidebarConfigDialog extends StatefulWidget {
  const SettingsHubSidebarConfigDialog({
    super.key,
    required this.initialConfig,
    required this.permittedItems,
    required this.onSave,
  });

  final SettingsHubSidebarConfig initialConfig;
  final List<SettingsHubItemDef> permittedItems;
  final Future<bool> Function(SettingsHubSidebarConfig config) onSave;

  static Future<SettingsHubSidebarConfig?> show(
    BuildContext context, {
    required SettingsHubSidebarConfig initialConfig,
    required List<SettingsHubItemDef> permittedItems,
    required Future<bool> Function(SettingsHubSidebarConfig config) onSave,
  }) {
    return showDialog<SettingsHubSidebarConfig>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SettingsHubSidebarConfigDialog(
        initialConfig: initialConfig,
        permittedItems: permittedItems,
        onSave: onSave,
      ),
    );
  }

  @override
  State<SettingsHubSidebarConfigDialog> createState() =>
      _SettingsHubSidebarConfigDialogState();
}

class _SettingsHubSidebarConfigDialogState
    extends State<SettingsHubSidebarConfigDialog> {
  late List<int> _order;
  late Set<int> _hidden;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final permittedIds = widget.permittedItems.map((e) => e.index).toSet();
    final baseOrder = widget.initialConfig.order.isNotEmpty
        ? List<int>.from(widget.initialConfig.order)
        : List<int>.from(SettingsHubCatalog.defaultOrder);
    _order = [
      for (final id in baseOrder)
        if (permittedIds.contains(id)) id,
      for (final item in widget.permittedItems)
        if (!baseOrder.contains(item.index)) item.index,
    ];
    _hidden = widget.initialConfig.hidden
        .where((id) => permittedIds.contains(id))
        .toSet();
  }

  SettingsHubSidebarConfig get _currentConfig =>
      SettingsHubSidebarConfig(order: _order, hidden: _hidden);

  Map<int, SettingsHubItemDef> get _itemMap =>
      {for (final item in widget.permittedItems) item.index: item};

  Future<void> _handleSave() async {
    setState(() => _saving = true);
    final ok = await widget.onSave(_currentConfig);
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.of(context).pop(_currentConfig);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('Không thể lưu cấu hình menu. Vui lòng thử lại.')),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  void _resetDefault() {
    setState(() {
      _order = widget.permittedItems.map((e) => e.index).toList();
      _hidden = {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width < 720
        ? (width < 520 ? width * 0.94 : 520.0)
        : 640.0;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(Icons.tune_rounded, color: HrmPageChrome.primaryNavy, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(tr('Tùy chỉnh module Thiết lập HRM'),
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: width < 600 ? 440 : 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('Bật/tắt module và kéo thả để sắp xếp thứ tự hiển thị trên trang Thiết lập HRM.'),
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.45),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: ReorderableListView.builder(
                buildDefaultDragHandles: false,
                itemCount: _order.length,
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = _order.removeAt(oldIndex);
                    _order.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final id = _order[index];
                  final item = _itemMap[id];
                  if (item == null) {
                    return SizedBox(key: ValueKey('missing-$id'));
                  }
                  final visible = !_hidden.contains(id);
                  return Material(
                    key: ValueKey('hub-item-$id'),
                    color: Colors.white,
                    child: ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
                      leading: ReorderableDragStartListener(
                        index: index,
                        child: const Icon(Icons.drag_indicator_rounded,
                            color: Color(0xFF94A3B8)),
                      ),
                      title: Text(
                        tr(item.label),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: visible
                              ? const Color(0xFF0F172A)
                              : const Color(0xFF94A3B8),
                          decoration:
                              visible ? null : TextDecoration.lineThrough,
                        ),
                      ),
                      subtitle: Text(
                        tr(item.groupTitle),
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: Switch(
                        value: visible,
                        activeTrackColor:
                            HrmPageChrome.primaryNavy.withOpacity(0.45),
                        onChanged: (v) {
                          setState(() {
                            if (v) {
                              _hidden.remove(id);
                            } else {
                              _hidden.add(id);
                            }
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : _resetDefault,
          child: Text(tr('Mặc định')),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: Text(tr('Hủy')),
        ),
        FilledButton(
          onPressed: _saving ? null : _handleSave,
          style: FilledButton.styleFrom(
            backgroundColor: HrmPageChrome.primaryNavy,
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(tr('Lưu')),
        ),
      ],
    );
  }
}
