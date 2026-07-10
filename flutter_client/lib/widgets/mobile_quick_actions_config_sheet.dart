import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/mobile_quick_actions_config.dart';
import '../providers/auth_provider.dart';
import '../providers/permission_provider.dart';
import '../services/mobile_quick_actions_prefs.dart';
import '../utils/mobile_quick_actions_catalog.dart';
import '../utils/permission_navigation.dart';
import '../widgets/hrm_page_chrome.dart';

/// Sheet tùy chỉnh lưới truy cập nhanh trong tab «Thêm».
class MobileQuickActionsConfigSheet extends StatefulWidget {
  const MobileQuickActionsConfigSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const MobileQuickActionsConfigSheet(),
    );
  }

  @override
  State<MobileQuickActionsConfigSheet> createState() =>
      _MobileQuickActionsConfigSheetState();
}

class _MobileQuickActionsConfigSheetState
    extends State<MobileQuickActionsConfigSheet> {
  late List<String> _modules;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _modules = List<String>.from(MobileQuickActionsPrefs.layout.modules);
    _padToNine();
  }

  void _padToNine() {
    while (_modules.length < MobileQuickActionsLayout.slotCount) {
      _modules.add(MobileQuickActionsLayout.emptySlot);
    }
    if (_modules.length > MobileQuickActionsLayout.slotCount) {
      _modules.removeRange(
        MobileQuickActionsLayout.slotCount,
        _modules.length,
      );
    }
  }

  Set<String> _allowedModuleCodes() {
    final authUser = Provider.of<AuthProvider>(context, listen: false).user;
    final allowedModules = authUser?.allowedModules;
    final role = authUser?.role;
    final perm = Provider.of<PermissionProvider>(context, listen: false);
    final out = <String>{};
    for (final def in MobileQuickActionsCatalog.items) {
      if (PermissionNavigation.canAccessModule(
        def.moduleCode,
        allowedModules: allowedModules,
        perm: perm,
        role: role,
      )) {
        out.add(def.moduleCode);
      }
    }
    return out;
  }

  String _labelFor(String code) {
    if (code.isEmpty) return 'Trống';
    return MobileQuickActionsCatalog.map[code]?.label ?? code;
  }

  Future<void> _pickSlot(int index) async {
    final used = _modules.where((c) => c.isNotEmpty).toSet();
    final current = _modules[index];
    final allowed = _allowedModuleCodes();
    final options = MobileQuickActionsCatalog.items
        .where((d) =>
            allowed.contains(d.moduleCode) &&
            (d.moduleCode == current || !used.contains(d.moduleCode)))
        .toList()
      ..add(
        const MobileQuickActionDef(
          moduleCode: MobileQuickActionsLayout.emptySlot,
          label: 'Trống',
          icon: Icons.remove_circle_outline,
        ),
      );

    final picked = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Ô ${index + 1} — chọn chức năng',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final opt in options)
                    ListTile(
                      leading: Icon(opt.icon),
                      title: Text(opt.label),
                      selected: opt.moduleCode == current,
                      onTap: () => Navigator.pop(ctx, opt.moduleCode),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _modules[index] = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final ok = await MobileQuickActionsPrefs.save(
      MobileQuickActionsLayout(modules: List<String>.from(_modules)),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu truy cập nhanh')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không lưu được — thử lại sau'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.72;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                const Icon(Icons.apps_rounded, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tùy chỉnh truy cập nhanh',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '9 ô trong tab «Thêm» — kéo đổi thứ tự, chạm để đổi chức năng.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: MobileQuickActionsLayout.slotCount,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _modules.removeAt(oldIndex);
                  _modules.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final code = _modules[index];
                final def = MobileQuickActionsCatalog.map[code];
                return Card(
                  key: ValueKey('qa_${index}_$code'),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: HrmPageChrome.primaryNavy,
                        ),
                      ),
                    ),
                    title: Text(_labelFor(code)),
                    subtitle: code.isNotEmpty
                        ? Text(code, style: const TextStyle(fontSize: 11))
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (def != null)
                          Icon(def.icon, size: 20, color: Colors.grey.shade600),
                        IconButton(
                          tooltip: 'Đổi chức năng',
                          icon: const Icon(Icons.swap_horiz, size: 20),
                          onPressed: () => _pickSlot(index),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle,
                              color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                    onTap: () => _pickSlot(index),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => setState(() {
                            _modules = List<String>.from(
                              MobileQuickActionsLayout.defaultModules,
                            );
                            _padToNine();
                          }),
                  child: const Text('Mặc định'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Lưu'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
