import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

import '../widgets/pos/pos_html_preview_stub.dart'
    if (dart.library.js_interop) '../widgets/pos/pos_html_preview_web.dart';

const _blue = Color(0xFF2563EB);

/// Dialog xem trước + in HTML mẫu (K58/K80/A4/A5).
Future<void> showPosHtmlPrintDialog(
  BuildContext context, {
  required String title,
  required String htmlDocument,
  int initialCopies = 1,
}) async {
  var copies = initialCopies.clamp(1, 10);
  final screenW = MediaQuery.sizeOf(context).width;
  final isMobile = !kIsWeb && screenW < 600;
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenW * 0.95,
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
          minWidth: isMobile ? 0 : 720,
          minHeight: isMobile ? 0 : 520,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(tr(title),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(tr('Số bản in:'), style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  DropdownButton<int>(
                    value: copies,
                    items: List.generate(
                      10,
                      (i) => DropdownMenuItem(value: i + 1, child: Text(tr('${i + 1}'))),
                    ),
                    onChanged: (v) {
                      if (v != null) setDlg(() => copies = v);
                    },
                  ),
                  const Spacer(),
                  if (kIsWeb)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      onPressed: () async {
                        for (var i = 0; i < copies; i++) {
                          await printPosHtmlDocument(htmlDocument);
                        }
                      },
                      icon: const Icon(Icons.print, size: 18),
                      label: Text(tr('In')),
                    )
                  else if (isMobile)
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await Share.share(htmlDocument, subject: title);
                      },
                      icon: const Icon(Icons.share, size: 18),
                      label: Text(tr('Chia sẻ / In')),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    color: Colors.grey.shade100,
                  ),
                  child: buildPosHtmlPreview(htmlDocument),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    ),
  );
}
