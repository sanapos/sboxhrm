import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../tokens/app_colors.dart';
import '../tokens/app_radius.dart';
import '../tokens/app_space.dart';

/// Ctrl/Cmd+K command palette — jump to modules by title.
class HrmCommandPalette extends StatefulWidget {
  const HrmCommandPalette({
    super.key,
    required this.items,
    required this.onSelected,
  });

  final List<HrmCommandItem> items;
  final ValueChanged<HrmCommandItem> onSelected;

  static Future<void> open(
    BuildContext context, {
    required List<HrmCommandItem> items,
    required ValueChanged<HrmCommandItem> onSelected,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => HrmCommandPalette(items: items, onSelected: (item) {
        Navigator.of(ctx).pop();
        onSelected(item);
      }),
    );
  }

  @override
  State<HrmCommandPalette> createState() => _HrmCommandPaletteState();
}

class HrmCommandItem {
  const HrmCommandItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.icon,
    this.group,
  });

  final String id;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? group;
}

class _HrmCommandPaletteState extends State<HrmCommandPalette> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<HrmCommandItem> get _filtered {
    final q = _controller.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items.take(24).toList();
    return widget.items
        .where((e) {
          final hay =
              '${e.title} ${e.subtitle ?? ''} ${e.group ?? ''}'.toLowerCase();
          return hay.contains(q);
        })
        .take(24)
        .toList();
  }

  void _select(HrmCommandItem item) => widget.onSelected(item);

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    if (_index >= filtered.length) _index = 0;
    final scheme = Theme.of(context).colorScheme;

    return Dialog(
      alignment: Alignment.topCenter,
      insetPadding: const EdgeInsets.only(top: 96, left: 24, right: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Material(
          color: scheme.surface,
          elevation: 8,
          borderRadius: AppRadius.dialog,
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  onChanged: (_) => setState(() => _index = 0),
                  onSubmitted: (_) {
                    if (filtered.isNotEmpty) _select(filtered[_index]);
                  },
                  decoration: InputDecoration(
                    hintText: 'Tìm module, chức năng…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    border: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        child: Text(
                          'Không tìm thấy',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          final selected = i == _index;
                          return ListTile(
                            selected: selected,
                            selectedTileColor:
                                AppColors.primary.withValues(alpha: 0.08),
                            leading: Icon(
                              item.icon ?? Icons.circle_outlined,
                              color: selected
                                  ? AppColors.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            title: Text(item.title),
                            subtitle: item.subtitle != null || item.group != null
                                ? Text(item.subtitle ?? item.group!)
                                : null,
                            onTap: () => _select(item),
                            onFocusChange: (f) {
                              if (f) setState(() => _index = i);
                            },
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpace.sm),
                child: Row(
                  children: [
                    Text(
                      'Enter mở · Esc đóng · Ctrl+K',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keyboard shortcut host for command palette.
class HrmCommandShortcut extends StatelessWidget {
  const HrmCommandShortcut({
    super.key,
    required this.child,
    required this.onOpen,
  });

  final Widget child;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): onOpen,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): onOpen,
      },
      child: Focus(autofocus: false, child: child),
    );
  }
}
