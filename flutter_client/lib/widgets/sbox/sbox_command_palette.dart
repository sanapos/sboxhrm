import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';

/// Một mục trong ô tìm nhanh chức năng.
class SboxCommandItem {
  const SboxCommandItem({
    required this.label,
    required this.onSelect,
    this.icon = Icons.chevron_right_rounded,
    this.group = '',
    this.subtitle,
    this.keywords = const [],
  });

  final String label;
  final IconData icon;
  final String group;
  final String? subtitle;
  final List<String> keywords;
  final VoidCallback onSelect;
}

/// Ô tìm nhanh chức năng (Ctrl+K): gõ không dấu vẫn ra, ↑↓ chọn, Enter mở, Esc đóng.
abstract final class SboxCommandPalette {
  static Future<void> show(BuildContext context, List<SboxCommandItem> items, {String hint = 'Tìm chức năng…'}) async {
    final picked = await showDialog<SboxCommandItem>(
      context: context,
      barrierColor: const Color(0x660F172A),
      builder: (_) => _Palette(items: items, hint: hint),
    );
    picked?.onSelect();
  }

  /// Bỏ dấu tiếng Việt + chữ thường để so khớp.
  static String fold(String input) {
    const from = 'àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ';
    const to = 'aaaaaaaaaaaaaaaaaeeeeeeeeeeeiiiiiooooooooooooooooouuuuuuuuuuuyyyyyd';
    final b = StringBuffer();
    for (final ch in input.toLowerCase().split('')) {
      final i = from.indexOf(ch);
      b.write(i >= 0 ? to[i] : ch);
    }
    return b.toString();
  }
}

class _Palette extends StatefulWidget {
  const _Palette({required this.items, required this.hint});

  final List<SboxCommandItem> items;
  final String hint;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  int _sel = 0;
  late List<SboxCommandItem> _hits = widget.items;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final f = SboxCommandPalette.fold(q.trim());
    setState(() {
      _sel = 0;
      if (f.isEmpty) {
        _hits = widget.items;
        return;
      }
      final words = f.split(RegExp(r'\s+'));
      final scored = <(int, SboxCommandItem)>[];
      for (final it in widget.items) {
        final label = SboxCommandPalette.fold(tr(it.label));
        final hay = SboxCommandPalette.fold(
            '${tr(it.label)} ${tr(it.group)} ${it.subtitle == null ? '' : tr(it.subtitle!)} ${it.keywords.join(' ')}');
        if (!words.every(hay.contains)) continue;
        final score = label.startsWith(f) ? 0 : (label.contains(f) ? 1 : 2);
        scored.add((score, it));
      }
      scored.sort((a, b) => a.$1.compareTo(b.$1));
      _hits = [for (final s in scored) s.$2];
    });
  }

  void _move(int d) {
    if (_hits.isEmpty) return;
    setState(() => _sel = (_sel + d).clamp(0, _hits.length - 1));
    const rowH = 52.0;
    final target = _sel * rowH;
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      if (target < pos.pixels) {
        _scroll.jumpTo(target);
      } else if (target + rowH > pos.pixels + pos.viewportDimension) {
        _scroll.jumpTo(target + rowH - pos.viewportDimension);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Align(
      alignment: const Alignment(0, -0.55),
      child: Material(
        color: SboxColors.surface,
        elevation: 0,
        shape: const RoundedRectangleBorder(borderRadius: SboxRadius.lgAll),
        clipBehavior: Clip.antiAlias,
        child: Container(
          width: size.width < 640 ? size.width - 24 : 600,
          constraints: BoxConstraints(maxHeight: size.height * 0.7),
          decoration: const BoxDecoration(boxShadow: SboxShadow.overlay),
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowDown): () => _move(1),
              const SingleActivator(LogicalKeyboardKey.arrowUp): () => _move(-1),
              const SingleActivator(LogicalKeyboardKey.enter): () {
                if (_hits.isNotEmpty) Navigator.pop(context, _hits[_sel]);
              },
              const SingleActivator(LogicalKeyboardKey.escape): () => Navigator.pop(context),
            },
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.all(SboxSpace.md),
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  onChanged: _filter,
                  style: SboxType.bodyStyle().copyWith(fontSize: SboxType.titleSm),
                  decoration: InputDecoration(
                    hintText: tr(widget.hint),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Center(
                        widthFactor: 1,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: SboxColors.slate100,
                            borderRadius: SboxRadius.smAll,
                            border: Border.all(color: SboxColors.border),
                          ),
                          child: Text('Esc', style: SboxType.captionStyle()),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: _hits.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(SboxSpace.xl),
                        child: Text(tr('Không tìm thấy chức năng phù hợp'), style: SboxType.smallStyle()),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: SboxSpace.xs),
                        itemCount: _hits.length,
                        itemExtent: 52,
                        itemBuilder: (_, i) {
                          final it = _hits[i];
                          final on = i == _sel;
                          return InkWell(
                            onTap: () => Navigator.pop(context, it),
                            onHover: (h) {
                              if (h) setState(() => _sel = i);
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: SboxSpace.sm),
                              padding: const EdgeInsets.symmetric(horizontal: SboxSpace.md),
                              decoration: BoxDecoration(
                                color: on ? SboxColors.brand50 : Colors.transparent,
                                borderRadius: SboxRadius.mdAll,
                              ),
                              child: Row(children: [
                                Icon(it.icon, size: 20, color: on ? SboxColors.brand600 : SboxColors.slate500),
                                const SizedBox(width: SboxSpace.md),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(tr(it.label),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: SboxType.bodyStyle(on ? SboxColors.brand900 : SboxColors.text)
                                              .copyWith(fontWeight: SboxType.medium)),
                                      if (it.subtitle != null)
                                        Text(tr(it.subtitle!),
                                            maxLines: 1, overflow: TextOverflow.ellipsis, style: SboxType.captionStyle()),
                                    ],
                                  ),
                                ),
                                if (it.group.isNotEmpty)
                                  Text(tr(it.group), style: SboxType.captionStyle(SboxColors.slate400)),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: SboxSpace.lg, vertical: SboxSpace.sm),
                decoration: const BoxDecoration(
                  color: SboxColors.slate50,
                  border: Border(top: BorderSide(color: SboxColors.border)),
                ),
                child: Row(children: [
                  Text(tr('↑↓ chọn · Enter mở · Esc đóng'), style: SboxType.captionStyle()),
                  const Spacer(),
                  Text(tr('${_hits.length} chức năng'), style: SboxType.captionStyle()),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
