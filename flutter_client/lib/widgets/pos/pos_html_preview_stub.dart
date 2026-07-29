import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';

import '../../models/pos_print_template.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Xem trước HTML mẫu in trên mobile/desktop (không cần web).
Widget buildPosHtmlPreview(String htmlDocument) {
  if (htmlDocument.trim().isEmpty) {
    return Center(child: Text(tr('Chưa có nội dung')));
  }
  return LayoutBuilder(
    builder: (context, constraints) {
      final paperW = constraints.maxWidth.clamp(280.0, 420.0);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            width: paperW,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.grey.shade300),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Html(
              data: htmlDocument,
              style: {
                'body': Style(
                  margin: Margins.zero,
                  padding: HtmlPaddings.all(8),
                  fontSize: FontSize(11),
                ),
                'table': Style(
                  width: Width(100, Unit.percent),
                  fontSize: FontSize(10),
                ),
              },
            ),
          ),
        ),
      );
    },
  );
}

Future<void> printPosHtmlDocument(String htmlDocument) async {}
