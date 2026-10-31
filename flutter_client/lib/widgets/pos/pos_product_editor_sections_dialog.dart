import 'package:flutter/material.dart';

import '../../utils/pos_product_editor_prefs.dart';
import 'pos_theme.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../../theme/sbox_tokens.dart';
/// Dialog chọn ngành chi tiết + mục hiển thị trên form thêm/sửa hàng hóa.
Future<PosProductFormLayout?> showPosProductEditorSectionsDialog(
  BuildContext context, {
  required Set<PosProductEditorSection> initial,
  PosProductIndustryPreset? preset,
}) {
  return showDialog<PosProductFormLayout>(
    context: context,
    builder: (_) => _PosProductEditorSectionsDialog(initial: initial, preset: preset),
  );
}

class _PosProductEditorSectionsDialog extends StatefulWidget {
  const _PosProductEditorSectionsDialog({required this.initial, this.preset});

  final Set<PosProductEditorSection> initial;
  final PosProductIndustryPreset? preset;

  @override
  State<_PosProductEditorSectionsDialog> createState() =>
      _PosProductEditorSectionsDialogState();
}

class _PosProductEditorSectionsDialogState
    extends State<_PosProductEditorSectionsDialog> {
  late Set<PosProductEditorSection> _selected;
  PosProductIndustryPreset? _preset;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
    _preset = widget.preset;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Tùy chọn form hàng hóa')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Áp dụng cho mọi máy của cửa hàng. Chọn ngành để có sẵn các mục ngành đó dùng, '
                'rồi bật / tắt thêm từng mục. Khi sửa hàng đã có dữ liệu, mục liên quan vẫn hiện.'),
                style: TextStyle(fontSize: 13, color: SboxColors.slate700),
              ),
              const SizedBox(height: 12),
              Text(tr('Ngành hàng của cửa hàng'),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in PosProductIndustryPreset.values)
                    Tooltip(
                      message: tr(p.hint),
                      child: ChoiceChip(
                        label: Text(tr(p.label), style: const TextStyle(fontSize: 12)),
                        selected: _preset == p,
                        selectedColor: PosTheme.kiotBlue.withValues(alpha: 0.15),
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() {
                          _preset = p;
                          _selected = {...p.sections};
                        }),
                      ),
                    ),
                ],
              ),
              if (_preset != null) ...[
                const SizedBox(height: 6),
                Text(tr(_preset!.hint),
                    style: TextStyle(fontSize: 12, color: SboxColors.slate600)),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(
                        () => _selected = defaultPosProductEditorSections()),
                    child: Text(tr('Form gọn')),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(
                        () => _selected = fullPosProductEditorSections()),
                    child: Text(tr('Hiện tất cả')),
                  ),
                ],
              ),
              const Divider(height: 20),
              ...PosProductEditorSection.values.map((s) {
                final on = _selected.contains(s);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: on,
                  activeColor: PosTheme.kiotBlue,
                  title: Text(tr(s.label), style: const TextStyle(fontSize: 14)),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selected.add(s);
                      } else {
                        _selected.remove(s);
                      }
                    });
                  },
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Hủy')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, PosProductFormLayout(_preset, {..._selected})),
          style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
          child: Text(tr('Lưu')),
        ),
      ],
    );
  }
}
