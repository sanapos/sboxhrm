import 'package:flutter/material.dart';

import '../../utils/pos_product_editor_prefs.dart';
import 'pos_theme.dart';
import 'package:sbox_pos/l10n/app_tr.dart';

/// Dialog chọn mục hiển thị trên form thêm/sửa hàng hóa.
Future<Set<PosProductEditorSection>?> showPosProductEditorSectionsDialog(
  BuildContext context, {
  required Set<PosProductEditorSection> initial,
}) {
  return showDialog<Set<PosProductEditorSection>>(
    context: context,
    builder: (_) => _PosProductEditorSectionsDialog(initial: initial),
  );
}

class _PosProductEditorSectionsDialog extends StatefulWidget {
  const _PosProductEditorSectionsDialog({required this.initial});

  final Set<PosProductEditorSection> initial;

  @override
  State<_PosProductEditorSectionsDialog> createState() =>
      _PosProductEditorSectionsDialogState();
}

class _PosProductEditorSectionsDialogState
    extends State<_PosProductEditorSectionsDialog> {
  late Set<PosProductEditorSection> _selected;

  @override
  void initState() {
    super.initState();
    _selected = {...widget.initial};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Tùy chọn form hàng hóa')),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr('Tắt các mục không dùng để form thêm hàng gọn hơn. '
                'Khi sửa hàng đã có dữ liệu, mục liên quan vẫn hiện.'),
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 8),
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
          onPressed: () async {
            await savePosProductEditorSections(_selected);
            if (!context.mounted) return;
            Navigator.pop(context, _selected);
          },
          style: FilledButton.styleFrom(backgroundColor: PosTheme.kiotBlue),
          child: Text(tr('Lưu')),
        ),
      ],
    );
  }
}
