import 'package:flutter/material.dart';

import '../models/mobile_bottom_nav_config.dart';
import '../services/mobile_bottom_nav_prefs.dart';
import '../utils/mobile_bottom_nav_catalog.dart';
import '../widgets/hrm_page_chrome.dart';

/// Sheet tùy chỉnh 5 ô cố định — kéo thả thứ tự, đổi chức năng từng ô.
class MobileBottomNavConfigSheet extends StatefulWidget {
  const MobileBottomNavConfigSheet({
    super.key,
    this.initialPage = 0,
  });

  /// 0 = thanh app, 1 = thanh POS.
  final int initialPage;

  static Future<void> show(
    BuildContext context, {
    int initialPage = 0,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => MobileBottomNavConfigSheet(initialPage: initialPage),
    );
  }

  @override
  State<MobileBottomNavConfigSheet> createState() =>
      _MobileBottomNavConfigSheetState();
}

class _MobileBottomNavConfigSheetState extends State<MobileBottomNavConfigSheet> {
  late List<String> _mainSlots;
  late List<String> _posSlots;
  bool _saving = false;
  late int _page;

  @override
  void initState() {
    super.initState();
    _page = widget.initialPage.clamp(0, 1);
    _mainSlots = List<String>.from(MobileBottomNavPrefs.mainLayout.slots);
    _posSlots = List<String>.from(MobileBottomNavPrefs.posLayout.slots);
    _padToFive(_mainSlots);
    _padToFive(_posSlots);
  }

  void _padToFive(List<String> list) {
    while (list.length < MobileBottomNavLayout.slotCount) {
      list.add(MobileBottomNavCatalog.emptyId);
    }
    if (list.length > MobileBottomNavLayout.slotCount) {
      list.removeRange(MobileBottomNavLayout.slotCount, list.length);
    }
  }

  List<String> get _activeSlots => _page == 0 ? _mainSlots : _posSlots;

  List<MobileBottomNavItemDef> get _catalog =>
      _page == 0 ? MobileBottomNavCatalog.mainItems : MobileBottomNavCatalog.posItems;

  Map<String, MobileBottomNavItemDef> get _itemMap =>
      MobileBottomNavCatalog.mapFor(_catalog);

  String _labelFor(String id) {
    if (id == MobileBottomNavCatalog.emptyId) return 'Trống';
    return _itemMap[id]?.label ?? id;
  }

  Future<void> _pickSlot(int index) async {
    final used = _activeSlots.toSet();
    final current = _activeSlots[index];
    final options = _catalog
        .where((d) => d.id == current || !used.contains(d.id))
        .toList()
      ..add(
        const MobileBottomNavItemDef(
          id: MobileBottomNavCatalog.emptyId,
          label: 'Trống',
          icon: Icons.remove_circle_outline,
          activeIcon: Icons.remove_circle_outline,
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
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            for (final opt in options)
              ListTile(
                leading: Icon(opt.icon),
                title: Text(opt.label),
                selected: opt.id == current,
                onTap: () => Navigator.pop(ctx, opt.id),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _activeSlots[index] = picked;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final okMain = await MobileBottomNavPrefs.saveMain(
      MobileBottomNavLayout(slots: List<String>.from(_mainSlots)),
    );
    final okPos = await MobileBottomNavPrefs.savePos(
      MobileBottomNavLayout(slots: List<String>.from(_posSlots)),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (okMain && okPos) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã lưu bố cục thanh công cụ')),
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

  Future<void> _resetCurrent() async {
    setState(() {
      if (_page == 0) {
        _mainSlots = List<String>.from(MobileBottomNavLayout.defaultMainSlots);
      } else {
        _posSlots = List<String>.from(MobileBottomNavLayout.defaultPosSlots);
      }
    });
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
                const Icon(Icons.tune_rounded, color: HrmPageChrome.primaryNavy),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Tùy chỉnh thanh công cụ',
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
              '5 vị trí cố định — kéo để đổi thứ tự, chạm để đổi chức năng.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Thanh app')),
                ButtonSegment(value: 1, label: Text('Thanh POS')),
              ],
              selected: {_page},
              onSelectionChanged: (s) => setState(() => _page = s.first),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: MobileBottomNavLayout.slotCount,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _activeSlots.removeAt(oldIndex);
                  _activeSlots.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final id = _activeSlots[index];
                final def = _itemMap[id];
                return Card(
                  key: ValueKey('${_page}_$index\_$id'),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: HrmPageChrome.primaryNavy.withValues(alpha: 0.1),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: HrmPageChrome.primaryNavy,
                        ),
                      ),
                    ),
                    title: Text(_labelFor(id)),
                    subtitle: index == 2
                        ? const Text(
                            'Vị trí giữa — nút nổi (Chấm công / Bán hàng)',
                            style: TextStyle(fontSize: 11),
                          )
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Đổi chức năng',
                          icon: const Icon(Icons.swap_horiz, size: 20),
                          onPressed: () => _pickSlot(index),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: Icon(Icons.drag_handle, color: Colors.grey.shade500),
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
                  onPressed: _saving ? null : _resetCurrent,
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
