import 'package:flutter/material.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Tách chuỗi nhiều seri (xuống dòng / ; / ,) → danh sách viết hoa, bỏ ô trống.
List<String> parsePosSerialList(String text) => text
    .split(RegExp(r'[\r\n;,]+'))
    .map((e) => e.trim().toUpperCase())
    .where((e) => e.isNotEmpty)
    .toList();

/// Hộp nhập / quét nhiều seri cho một dòng hàng (mỗi seri một dòng). Trả về danh sách; null nếu huỷ.
Future<List<String>?> showPosSerialListDialog(
  BuildContext context, {
  required String productName,
  required int qty,
  List<String> initial = const [],
  bool readOnly = false,
  String hint = 'Quét hoặc dán seri — mỗi seri một dòng',
  Future<List<String>> Function()? loadSuggestions,
  /// Quét một mã bằng camera / đầu đọc, thêm vào danh sách.
  Future<String?> Function()? scanOne,
}) async {
  final ctl = TextEditingController(text: initial.join('\n'));
  List<String>? suggestions;
  try {
    return await showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final list = parsePosSerialList(ctl.text);
        final dup = list.length != list.toSet().length;
        final ok = (qty <= 0 || list.length == qty) && !dup;
        return AlertDialog(
          title: Text(tr('Seri máy — $productName')),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: ctl,
                  readOnly: readOnly,
                  autofocus: !readOnly,
                  minLines: 5,
                  maxLines: 10,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setD(() {}),
                  decoration: InputDecoration(hintText: tr(hint), border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                Text(
                  tr('Đã nhập ${list.length}${qty > 0 ? '/$qty' : ''} mã${dup ? ' — có mã bị trùng' : ''}'),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: ok ? Colors.green.shade700 : Colors.orange.shade800,
                  ),
                ),
                if (!readOnly && scanOne != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                      label: Text(tr('Quét mã')),
                      onPressed: () async {
                        final code = await scanOne();
                        if (code == null || code.trim().isEmpty) return;
                        final cur = parsePosSerialList(ctl.text);
                        final sn = code.trim().toUpperCase();
                        if (!cur.contains(sn)) {
                          ctl.text = [...cur, sn].join('\n');
                        }
                        setD(() {});
                      },
                    ),
                  ),
                ],
                if (!readOnly && loadSuggestions != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined, size: 16),
                      label: Text(tr('Lấy seri đang trong kho')),
                      onPressed: () async {
                        suggestions = await loadSuggestions();
                        final take = (suggestions ?? []).where((s) => !list.contains(s)).take(qty - list.length).toList();
                        if (take.isNotEmpty) {
                          ctl.text = [...list, ...take].join('\n');
                        }
                        setD(() {});
                      },
                    ),
                  ),
                ],
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr(readOnly ? 'Đóng' : 'Huỷ'))),
            if (!readOnly)
              FilledButton(
                onPressed: dup ? null : () => Navigator.pop(ctx, list),
                child: Text(tr('Xác nhận')),
              ),
          ],
        );
      }),
    );
  } finally {
    ctl.dispose();
  }
}
