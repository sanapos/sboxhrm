import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../theme/sbox_tokens.dart';
import 'pos_quote_care_sheet.dart';
import 'pos_theme.dart';

/// Một lựa chọn trong [showPosQuoteActionSheet].
class PosSheetAction {
  const PosSheetAction(this.value, this.icon, this.label, {this.hint, this.color});

  final String value;
  final IconData icon;
  final String label;

  /// Một dòng giải thích nút làm gì (danh sách dạng dòng).
  final String? hint;
  final Color? color;
}

/// Bảng chọn thao tác có chữ, chia nhóm có tên — thay menu dài nhiều mục không nhóm.
/// [grid] = ô biểu tượng 4 cột (gửi / xuất file); không thì danh sách có dòng giải thích.
Future<String?> showPosQuoteActionSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<(String, List<PosSheetAction>)> sections,
  bool grid = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
    builder: (ctx) {
      Widget tile(PosSheetAction a) => InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => Navigator.pop(ctx, a.value),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: SboxColors.isBoss ? SboxColors.iconBox : (a.color ?? PosTheme.kiotBlue).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(a.icon, size: 22, color: SboxColors.isBoss ? SboxColors.iconOnBox : a.color ?? PosTheme.kiotBlue),
                ),
                const SizedBox(height: 6),
                Text(tr(a.label),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 11.5, height: 1.2, color: SboxColors.slate700)),
              ]),
            ),
          );
      Widget row(PosSheetAction a) => ListTile(
            leading: Icon(a.icon, color: a.color ?? PosTheme.kiotBlue),
            title: Text(tr(a.label), style: TextStyle(fontWeight: FontWeight.w600, color: a.color)),
            subtitle: a.hint == null
                ? null
                : Text(tr(a.hint!), style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
            onTap: () => Navigator.pop(ctx, a.value),
          );
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.88),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tr(title), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if ((subtitle ?? '').isNotEmpty)
                        Text(subtitle!, style: const TextStyle(fontSize: 12, color: SboxColors.slate500)),
                    ]),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ]),
              ),
              const Divider(height: 8),
              for (final (name, actions) in sections)
                if (actions.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(grid ? 12 : 0, 8, grid ? 12 : 0, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Padding(
                        padding: EdgeInsets.only(left: grid ? 4 : 16, bottom: 2),
                        child: Text(tr(name),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w700, color: SboxColors.slate500)),
                      ),
                      if (grid)
                        GridView(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 4,
                            mainAxisExtent: 16 + 44 + 6 + MediaQuery.textScalerOf(ctx).scale(11.5) * 1.2 * 2 + 6,
                          ),
                          children: [for (final a in actions) tile(a)],
                        )
                      else
                        for (final a in actions) row(a),
                    ]),
                  ),
              const SizedBox(height: 12),
            ]),
          ),
        ),
      );
    },
  );
}

/// Bảng «Gửi khách / In» của một chứng từ: In + tải file + gửi qua kênh. Trả về action cho
/// `PosQuoteExport.run` ('print', 'pdf', 'word', 'excel', 'png', 'zalo', 'email', 'facebook').
Future<String?> showPosDocSendSheet(BuildContext context, {required String title, String? subtitle}) =>
    showPosQuoteActionSheet(
      context,
      title: title,
      subtitle: subtitle,
      grid: true,
      sections: const [
        (
          'In / tải file',
          [
            PosSheetAction('print', Icons.print_outlined, 'In'),
            PosSheetAction('pdf', Icons.picture_as_pdf_outlined, 'Xuất PDF'),
            PosSheetAction('word', Icons.description_outlined, 'Xuất Word'),
            PosSheetAction('excel', Icons.table_chart_outlined, 'Xuất Excel'),
            PosSheetAction('png', Icons.image_outlined, 'Xuất ảnh PNG'),
          ]
        ),
        (
          'Gửi cho khách',
          [
            PosSheetAction('zalo', Icons.chat_outlined, 'Gửi Zalo'),
            PosSheetAction('email', Icons.email_outlined, 'Gửi Email'),
            PosSheetAction('facebook', Icons.facebook, 'Chia sẻ Facebook'),
          ]
        ),
      ],
    );

/// Hàng liên hệ khách có chữ: Gọi · Nhắn Zalo · Chăm sóc (màn báo giá + hợp đồng).
class PosQuoteContactRow extends StatelessWidget {
  const PosQuoteContactRow({super.key, required this.phone, required this.onCare});

  final String? phone;
  final VoidCallback onCare;

  @override
  Widget build(BuildContext context) {
    final p = (phone ?? '').trim();
    Widget tile(IconData icon, String label, VoidCallback? onTap) => Expanded(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: SboxColors.slate200),
                ),
                child: Column(children: [
                  Icon(icon, size: 22, color: onTap == null ? SboxColors.slate300 : PosTheme.kiotBlue),
                  const SizedBox(height: 4),
                  Text(tr(label),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: onTap == null ? SboxColors.slate400 : SboxColors.slate700)),
                ]),
              ),
            ),
          ),
        );
    return Row(children: [
      tile(Icons.call_outlined, 'Gọi khách', p.isEmpty ? null : () => callPosQuoteCustomer(p)),
      const SizedBox(width: 8),
      tile(Icons.chat_outlined, 'Nhắn Zalo', p.isEmpty ? null : () => openPosQuoteZalo(p)),
      const SizedBox(width: 8),
      tile(Icons.event_note_outlined, 'Chăm sóc khách', onCare),
    ]);
  }
}
