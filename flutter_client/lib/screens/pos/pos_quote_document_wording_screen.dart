import 'package:flutter/material.dart';

import '../../l10n/app_tr.dart';
import '../../models/pos_print_template.dart';
import '../../models/pos_quote.dart';
import '../../services/api_service.dart';
import '../../utils/pos_quote_document_wording.dart';
import '../../widgets/notification_overlay.dart';
import '../../widgets/pos/pos_commercial_a4_editor.dart';
import '../../widgets/pos/pos_quote_care_sheet.dart';

/// Sửa ngôn từ của một chứng từ đã lập. Lưu vào HTML của chứng từ đó.
class PosQuoteDocumentWordingScreen extends StatefulWidget {
  const PosQuoteDocumentWordingScreen({
    super.key,
    required this.quoteId,
    required this.document,
  });

  final String quoteId;
  final PosQuoteDocument document;

  @override
  State<PosQuoteDocumentWordingScreen> createState() =>
      _PosQuoteDocumentWordingScreenState();
}

class _PosQuoteDocumentWordingScreenState
    extends State<PosQuoteDocumentWordingScreen> {
  final _api = ApiService();
  final _editorKey = GlobalKey<PosCommercialA4EditorState>();
  String? _baseline;
  String? _editorHtml;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    var source = widget.document.htmlContent;
    if (widget.document.kind == 'Quote' &&
        !posQuoteDocWordingIsCustom(source)) {
      try {
        final res = await _api.getPosQuote(widget.quoteId);
        if (res['isSuccess'] == true && res['data'] is Map) {
          final q = PosQuote.fromJson(
            Map<String, dynamic>.from(res['data'] as Map),
          );
          if (q.lines.isNotEmpty) {
            final live = await bindPosQuotePrintHtml(_api, q, q.lines);
            if (live.trim().isNotEmpty) source = live;
          }
        }
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _baseline = source;
      _editorHtml = posQuoteWordingBody(source);
      _loading = false;
    });
  }

  Future<void> _save() async {
    final baseline = _baseline;
    if (baseline == null || _saving) return;
    setState(() => _saving = true);
    final edited = await _editorKey.currentState?.flushHtml() ??
        _editorHtml ??
        '';
    final html = posQuoteMergeWording(baseline, edited);
    final res = await _api.updatePosQuoteDocumentWording(
      widget.quoteId,
      widget.document.id,
      htmlContent: html,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Chưa lưu',
        message: res['message']?.toString() ?? tr('Không lưu được lời riêng'),
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã lưu lời riêng',
      message: tr('Chỉ chứng từ này đổi. Mẫu chung và chứng từ khác giữ nguyên.'),
    );
    Navigator.of(context).pop(true);
  }

  Future<void> _restore() async {
    if (_saving) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Khôi phục theo mẫu')),
        content: Text(tr(
          'Chứng từ này in lại theo mẫu chung. Phần chữ đã sửa riêng sẽ mất. Các chứng từ khác không đổi.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr('Huỷ')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr('Khôi phục')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    final res = await _api.updatePosQuoteDocumentWording(
      widget.quoteId,
      widget.document.id,
      restore: true,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['isSuccess'] != true) {
      NotificationOverlayManager().showError(
        title: 'Chưa khôi phục',
        message: res['message']?.toString() ?? tr('Không khôi phục được'),
      );
      return;
    }
    NotificationOverlayManager().showSuccess(
      title: 'Đã khôi phục',
      message: tr('Chứng từ này in theo mẫu chung.'),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final title = '${doc.docNo} · ${PosQuoteDocument.kindLabel(doc.kind)}';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(
            onPressed: _saving || _loading ? null : _restore,
            child: Text(tr('Theo mẫu')),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _saving || _loading ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(tr('Lưu riêng')),
            ),
          ),
        ],
      ),
      body: _loading || _editorHtml == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Material(
                  color: const Color(0xFFFFF7ED),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      tr('Sửa chữ trên trang giấy rồi bấm Lưu riêng. Không đổi mẫu in chung và không đổi chứng từ khác.'),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                Expanded(
                  child: PosCommercialA4Editor(
                    key: _editorKey,
                    snapshot: true,
                    html: _editorHtml!,
                    documentType: doc.kind,
                    paperSize: PosPrintPaperSizes.a4,
                    onChanged: (html) => _editorHtml = html,
                  ),
                ),
              ],
            ),
    );
  }
}
